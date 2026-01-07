import Foundation
import PassKit

@objc(SLMWalletPlugin) class SLMWalletPlugin : CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var currentCallbackId: String?
    private var addPaymentPassVC: PKAddPaymentPassViewController?
    
    // MARK: - Cordova JavaScript Bridge Helper
    
    private func evaluateJS(_ jsCode: String) {
        if let wkWebView = self.webView as? WKWebView {
            wkWebView.evaluateJavaScript(jsCode) { (result, error) in
                if let error = error {
                    print("JavaScript evaluation error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Cordova Plugin Methods
    
    @objc(appleCanAdd:)
    func appleCanAdd(_ command: CDVInvokedUrlCommand) {
        var pluginResult: CDVPluginResult
        
        // Verificar que el dispositivo sea compatible con Apple Pay
        guard PKAddPaymentPassViewController.canAddPaymentPass() else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["canAdd": false])
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            return
        }
        
        pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["canAdd": true])
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc(appleStartAdd:)
    func appleStartAdd(_ command: CDVInvokedUrlCommand) {
        guard let opts = command.arguments.first as? [String: Any] else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid parameters")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        // Verificar compatibilidad del dispositivo
        guard PKAddPaymentPassViewController.canAddPaymentPass() else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Device does not support adding payment passes")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        self.currentCallbackId = command.callbackId
        
        // Extraer parámetros de configuración
        let cardholderName = opts["cardholderName"] as? String ?? ""
        let last4 = opts["last4"] as? String ?? ""
        let description = opts["description"] as? String ?? "Card"
        let cardId = opts["cardId"] as? String ?? opts["card_id"] as? String ?? ""
        
        // Configuración del endpoint de tokenización
        let tokenizationEndpoint = opts["tokenizationEndpoint"] as? String 
            ?? "https://api.pomelo.la/token-provisioning/mastercard/apple-pay"
        
        var tokenizationAuthorization = opts["tokenizationAuthorization"] as? String ?? ""
        
        // Si no hay tokenizationAuthorization, intentar construirlo desde authToken y authScheme
        if tokenizationAuthorization.isEmpty {
            let authToken = opts["tokenizationAuthToken"] as? String ?? ""
            let authScheme = opts["tokenizationAuthScheme"] as? String ?? "Bearer"
            if !authToken.isEmpty {
                tokenizationAuthorization = "\(authScheme) \(authToken)"
            }
        }
        
        let tokenizationHeaders = opts["tokenizationHeaders"] as? [String: String] ?? [:]
        let userId = opts["userId"] as? String ?? opts["user_id"] as? String ?? ""
        
        // Guardar configuración para uso posterior
        UserDefaults.standard.set(tokenizationEndpoint, forKey: "SLMWallet_tokenizationEndpoint")
        UserDefaults.standard.set(tokenizationAuthorization, forKey: "SLMWallet_tokenizationAuthorization")
        UserDefaults.standard.set(tokenizationHeaders, forKey: "SLMWallet_tokenizationHeaders")
        UserDefaults.standard.set(cardId, forKey: "SLMWallet_cardId")
        UserDefaults.standard.set(userId, forKey: "SLMWallet_userId")
        
        // Configurar PKAddPaymentPassRequestConfiguration
        guard let configuration = PKAddPaymentPassRequestConfiguration(encryptionScheme: .ECC_V2) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to create payment pass configuration")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            self.currentCallbackId = nil
            return
        }
        
        configuration.cardholderName = cardholderName
        configuration.primaryAccountSuffix = last4
        configuration.localizedDescription = description
        configuration.primaryAccountIdentifier = cardId
        
        // Crear y presentar el view controller de Apple Pay
        guard let vc = PKAddPaymentPassViewController(requestConfiguration: configuration, delegate: self) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to create PKAddPaymentPassViewController")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            self.currentCallbackId = nil
            return
        }
        
        self.addPaymentPassVC = vc
        
        DispatchQueue.main.async {
            self.viewController.present(vc, animated: true, completion: nil)
        }
    }
    
    // MARK: - PKAddPaymentPassViewControllerDelegate
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        generateRequestWithCertificateChain certificates: [Data],
        nonce: Data,
        nonceSignature: Data,
        completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void
    ) {
        // Recuperar configuración guardada
        guard let endpoint = UserDefaults.standard.string(forKey: "SLMWallet_tokenizationEndpoint"),
              let authorization = UserDefaults.standard.string(forKey: "SLMWallet_tokenizationAuthorization"),
              let cardId = UserDefaults.standard.string(forKey: "SLMWallet_cardId") else {
            print("Missing tokenization configuration")
            return
        }
        
        let headers = UserDefaults.standard.dictionary(forKey: "SLMWallet_tokenizationHeaders") as? [String: String] ?? [:]
        let userId = UserDefaults.standard.string(forKey: "SLMWallet_userId") ?? ""
        
        // Convertir certificates, nonce y nonceSignature a Base64
        let certificatesBase64 = certificates.map { $0.base64EncodedString() }
        let nonceBase64 = nonce.base64EncodedString()
        let nonceSignatureBase64 = nonceSignature.base64EncodedString()
        
        // Construir el request body para Pomelo
        var requestBody: [String: Any] = [
            "card_id": cardId,
            "certificates": certificatesBase64,
            "nonce": nonceBase64,
            "nonce_signature": nonceSignatureBase64
        ]
        
        if !userId.isEmpty {
            requestBody["user_id"] = userId
        }
        
        // Llamar al endpoint de Pomelo
        guard let url = URL(string: endpoint) else {
            print("Invalid endpoint URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        
        // Agregar headers personalizados
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Failed to serialize request body: \(error)")
            return
        }
        
        // Realizar la llamada al backend
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Network error: \(error)")
                return
            }
            
            guard let data = data else {
                print("No data received from server")
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataObject = json["data"] as? [String: Any],
                      let activationDataBase64 = dataObject["activation_data"] as? String,
                      let encryptedPassDataBase64 = dataObject["encrypted_pass_data"] as? String,
                      let ephemeralPublicKeyBase64 = dataObject["ephemeral_public_key"] as? String else {
                    print("Invalid response structure from Pomelo")
                    return
                }
                
                // Decodificar de Base64
                guard let activationData = Data(base64Encoded: activationDataBase64),
                      let encryptedPassData = Data(base64Encoded: encryptedPassDataBase64),
                      let ephemeralPublicKey = Data(base64Encoded: ephemeralPublicKeyBase64) else {
                    print("Failed to decode base64 data")
                    return
                }
                
                // Construir PKAddPaymentPassRequest
                let passRequest = PKAddPaymentPassRequest()
                passRequest.activationData = activationData
                passRequest.encryptedPassData = encryptedPassData
                passRequest.ephemeralPublicKey = ephemeralPublicKey
                
                // Llamar al completion handler con el request
                DispatchQueue.main.async {
                    handler(passRequest)
                }
                
            } catch {
                print("Failed to parse response: \(error)")
            }
        }
        
        task.resume()
    }
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        didFinishAdding pass: PKPaymentPass?,
        error: Error?
    ) {
        controller.dismiss(animated: true) {
            guard let callbackId = self.currentCallbackId else { return }
            
            var result: CDVPluginResult
            
            if let error = error {
                // Error al agregar la tarjeta
                result = CDVPluginResult(
                    status: CDVCommandStatus_ERROR,
                    messageAs: ["error": error.localizedDescription, "added": false]
                )
            } else if let pass = pass {
                // Tarjeta agregada exitosamente
                let passInfo: [String: Any] = [
                    "added": true,
                    "serialNumber": pass.serialNumber,
                    "passTypeIdentifier": pass.passTypeIdentifier,
                    "deviceAccountIdentifier": pass.deviceAccountIdentifier,
                    "deviceAccountNumberSuffix": pass.deviceAccountNumberSuffix
                ]
                result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: passInfo)
            } else {
                // Cancelado por el usuario
                result = CDVPluginResult(
                    status: CDVCommandStatus_ERROR,
                    messageAs: ["error": "User cancelled", "added": false]
                )
            }
            
            self.commandDelegate.send(result, callbackId: callbackId)
            self.currentCallbackId = nil
            self.addPaymentPassVC = nil
            
            // Limpiar UserDefaults
            UserDefaults.standard.removeObject(forKey: "SLMWallet_tokenizationEndpoint")
            UserDefaults.standard.removeObject(forKey: "SLMWallet_tokenizationAuthorization")
            UserDefaults.standard.removeObject(forKey: "SLMWallet_tokenizationHeaders")
            UserDefaults.standard.removeObject(forKey: "SLMWallet_cardId")
            UserDefaults.standard.removeObject(forKey: "SLMWallet_userId")
        }
    }
}