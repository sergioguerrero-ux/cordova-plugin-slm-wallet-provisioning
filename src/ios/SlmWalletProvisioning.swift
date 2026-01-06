import Foundation
import PassKit

@objc(SlmWalletProvisioning)
class SlmWalletProvisioning: CDVPlugin, PKAddPaymentPassViewControllerDelegate {

    private var pendingCallbackId: String?
    private var tokenizationEndpoint: URL?
    private var tokenizationHeaders: [String: String] = [:]
    private var tokenizationCardId: String?
    private var tokenizationUserId: String?

    // cordova.plugins.slmWallet.appleCanAdd(...)
    @objc(appleCanAdd:)
    func appleCanAdd(command: CDVInvokedUrlCommand) {
        let can = PKAddPaymentPassViewController.canAddPaymentPass()
        let payload: [String: Any] = ["ok": true, "canAdd": can]

        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }

    // cordova.plugins.slmWallet.appleStartAdd({ ... }, ...)
    @objc(appleStartAdd:)
    func appleStartAdd(command: CDVInvokedUrlCommand) {
        self.pendingCallbackId = command.callbackId

        guard let opts = command.arguments.first as? [String: Any] else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "missing_options")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            self.pendingCallbackId = nil
            return
        }

        // Campos típicos (ajustamos a tu backend/Pomelo):
        let cardholderName = (opts["cardholderName"] as? String) ?? ""
        let primaryAccountSuffix = (opts["last4"] as? String) ?? ""
        let localizedDescription = (opts["description"] as? String) ?? "Card"

        // Tokenización / Pomelo
        self.tokenizationCardId = (opts["cardId"] as? String) ?? (opts["card_id"] as? String)
        self.tokenizationUserId = (opts["userId"] as? String) ?? (opts["user_id"] as? String)
        self.tokenizationHeaders = [:]

        if let headers = opts["tokenizationHeaders"] as? [String: String] {
            self.tokenizationHeaders.merge(headers) { _, new in new }
        } else if let headers = opts["tokenizationHeaders"] as? [String: Any] {
            headers.forEach { key, value in
                if let stringValue = value as? String {
                    self.tokenizationHeaders[key] = stringValue
                }
            }
        }

        if let authorization = opts["tokenizationAuthorization"] as? String {
            self.tokenizationHeaders["Authorization"] = authorization
        } else if let token = opts["tokenizationAuthToken"] as? String {
            let scheme = (opts["tokenizationAuthScheme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Bearer"
            self.tokenizationHeaders["Authorization"] = "\(scheme) \(token)"
        }

        let endpointInput = (opts["tokenizationEndpoint"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endpointString = (endpointInput?.isEmpty == false)
            ? endpointInput!
            : "https://api.pomelo.la/token-provisioning/mastercard/apple-pay"
        self.tokenizationEndpoint = URL(string: endpointString)

        guard let promisedCardId = self.tokenizationCardId, !promisedCardId.isEmpty else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "missing_card_id")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            self.pendingCallbackId = nil
            return
        }

        guard self.tokenizationEndpoint != nil else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "invalid_tokenization_endpoint")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            self.pendingCallbackId = nil
            return
        }

        // ⚠️ Esto requiere el entitlement de Apple (Issuer / In-App provisioning),
        // si no, no podrás presentar el controller.
        guard let config = PKAddPaymentPassRequestConfiguration(encryptionScheme: .ECC_V2) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "config_failed")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        config.cardholderName = cardholderName
        config.primaryAccountSuffix = primaryAccountSuffix
        config.localizedDescription = localizedDescription

        guard let vc = PKAddPaymentPassViewController(requestConfiguration: config, delegate: self) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "cannot_create_controller")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        self.viewController.present(vc, animated: true)
    }

    // MARK: - PKAddPaymentPassViewControllerDelegate

    // Aquí Apple te da certificates/nonce/signature y tú se los mandas a tu backend (Pomelo),
    // y luego construyes PKAddPaymentPassRequest con la respuesta.
    func addPaymentPassViewController(_ controller: PKAddPaymentPassViewController,
                                      generateRequestWithCertificateChain certificates: [Data],
                                      nonce: Data,
                                      nonceSignature: Data,
                                      completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void) {

        guard self.tokenizationEndpoint != nil, self.tokenizationCardId != nil else {
            handler(PKAddPaymentPassRequest())
            return
        }

        fetchTokenizationData(
            certificates: certificates,
            nonce: nonce,
            nonceSignature: nonceSignature
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let _ = self else {
                    handler(PKAddPaymentPassRequest())
                    return
                }

                switch result {
                case .success(let response):
                    let request = PKAddPaymentPassRequest()
                    request.activationData = response.activationData
                    request.ephemeralPublicKey = response.ephemeralPublicKey
                    request.encryptedPassData = response.encryptedPassData
                    handler(request)

                case .failure(let error):
                    print("SlmWalletProvisioning: tokenization failed – \(error)")
                    handler(PKAddPaymentPassRequest())
                }
            }
        }
    }

    func addPaymentPassViewController(_ controller: PKAddPaymentPassViewController,
                                      didFinishAdding pass: PKPaymentPass?,
                                      error: Error?) {
        controller.dismiss(animated: true)

        guard let cb = self.pendingCallbackId else { return }
        self.pendingCallbackId = nil

        if let error = error {
            let payload: [String: Any] = ["ok": false, "error": error.localizedDescription]
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: payload)
            self.commandDelegate.send(result, callbackId: cb)
            return
        }

        let payload: [String: Any] = ["ok": true, "added": (pass != nil)]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        self.commandDelegate.send(result, callbackId: cb)
    }
}

// MARK: - Pomelo Tokenization Helpers

private struct TokenizationResponse {
    let activationData: Data
    let encryptedPassData: Data
    let ephemeralPublicKey: Data
}

private enum TokenizationError: Error {
    case missingConfiguration
    case httpError(statusCode: Int)
    case invalidResponse
    case invalidPayload

    var localizedDescription: String {
        switch self {
        case .missingConfiguration:
            return "Tokenization configuration missing"
        case .httpError(let status):
            return "Tokenization HTTP error \(status)"
        case .invalidResponse:
            return "Invalid tokenization response"
        case .invalidPayload:
            return "Tokenization payload missing required fields"
        }
    }
}

private extension SlmWalletProvisioning {
    func fetchTokenizationData(certificates: [Data],
                               nonce: Data,
                               nonceSignature: Data,
                               completion: @escaping (Result<TokenizationResponse, Error>) -> Void) {

        guard let endpoint = tokenizationEndpoint, let cardId = tokenizationCardId else {
            completion(.failure(TokenizationError.missingConfiguration))
            return
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        tokenizationHeaders.forEach { field, value in
            request.setValue(value, forHTTPHeaderField: field)
        }

        var body: [String: Any] = [
            "card_id": cardId,
            "certificates": certificates.map { $0.base64EncodedString() },
            "nonce": nonce.base64EncodedString(),
            "nonce_signature": nonceSignature.base64EncodedString()
        ]

        if let userId = tokenizationUserId, !userId.isEmpty {
            body["user_id"] = userId
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(TokenizationError.invalidResponse))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(TokenizationError.httpError(statusCode: httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                completion(.failure(TokenizationError.invalidResponse))
                return
            }

            do {
                guard let payload = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                      let dataBlock = payload["data"] as? [String: Any],
                      let activationString = dataBlock["activation_data"] as? String,
                      let encryptedString = dataBlock["encrypted_pass_data"] as? String,
                      let ephemeralString = dataBlock["ephemeral_public_key"] as? String,
                      let activationData = Data(base64Encoded: activationString),
                      let encrypted = Data(base64Encoded: encryptedString),
                      let ephemeralPublicKey = Data(base64Encoded: ephemeralString)
                else {
                    completion(.failure(TokenizationError.invalidPayload))
                    return
                }

                let tokenResponse = TokenizationResponse(
                    activationData: activationData,
                    encryptedPassData: encrypted,
                    ephemeralPublicKey: ephemeralPublicKey
                )
                completion(.success(tokenResponse))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
