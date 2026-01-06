import PassKit

@objc(SLMWalletPlugin)
class SLMWalletPlugin: CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var currentCommand: CDVInvokedUrlCommand?
    private var addPaymentVC: PKAddPaymentPassViewController?
    
    // PASO 1: Verificar si puede agregar tarjetas
    @objc(appleCanAdd:)
    func appleCanAdd(command: CDVInvokedUrlCommand) {
        let canAdd = PKAddPaymentPassViewController.canAddPaymentPass()
        
        let result: [String: Any] = [
            "ok": true,
            "canAdd": canAdd
        ]
        
        let pluginResult = CDVPluginResult(status: .ok, messageAs: result)
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    // PASO 2: Iniciar el flujo de aprovisionamiento
    @objc(appleStartAdd:)
    func appleStartAdd(command: CDVInvokedUrlCommand) {
        guard let options = command.arguments[0] as? [String: Any] else {
            sendError(command, "invalid_options")
            return
        }
        
        // Extraer parámetros
        guard let cardId = options["cardId"] as? String,
              let holderName = options["holderName"] as? String,
              let last4 = options["last4"] as? String else {
            sendError(command, "missing_required_fields")
            return
        }
        
        let localizedDescription = options["localizedDescription"] as? String ?? "Tarjeta"
        let encryptionScheme = options["encryptionScheme"] as? String ?? "ECC_V2"
        
        // Guardar el command para usarlo en el delegate
        self.currentCommand = command
        
        // Crear la configuración para Apple
        let config = PKAddPaymentPassRequestConfiguration(encryptionScheme: .ECC_V2)
        config?.cardholderName = holderName
        config?.primaryAccountSuffix = last4
        config?.localizedDescription = localizedDescription
        config?.primaryAccountIdentifier = cardId
        
        // IMPORTANTE: PaymentNetwork debe coincidir con tu BIN
        // config?.paymentNetwork = .masterCard  // o .visa
        
        guard let config = config,
              let vc = PKAddPaymentPassViewController(
                requestConfiguration: config,
                delegate: self
              ) else {
            sendError(command, "cannot_create_view_controller")
            return
        }
        
        // Guardar opciones para usar en generateRequest
        vc.view.tag = 999  // Tag temporal para identificar
        objc_setAssociatedObject(vc, "options", options, .OBJC_ASSOCIATION_RETAIN)
        
        self.addPaymentVC = vc
        
        // Presentar la UI de Apple
        DispatchQueue.main.async {
            self.viewController.present(vc, animated: true)
        }
    }
    
    // PASO 3: Apple solicita los certificados - aquí llamamos a Pomelo
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        generateRequestWithCertificateChain certificates: [Data],
        nonce: Data,
        nonceSignature: Data,
        completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void
    ) {
        // Obtener opciones guardadas
        guard let options = objc_getAssociatedObject(controller, "options") as? [String: Any],
              let cardId = options["cardId"] as? String else {
            handler(PKAddPaymentPassRequest())
            return
        }
        
        let backendUrl = options["backendUrl"] as? String ?? 
            "https://api.pomelo.la/token-provisioning/mastercard/apple-pay"
        let backendHeaders = options["backendHeaders"] as? [String: String] ?? [:]
        let userId = options["userId"] as? String
        
        // Preparar payload para Pomelo
        var payload: [String: Any] = [
            "card_id": cardId,
            "certificates": certificates.map { $0.base64EncodedString() },
            "nonce": nonce.base64EncodedString(),
            "nonce_signature": nonceSignature.base64EncodedString()
        ]
        
        if let userId = userId {
            payload["user_id"] = userId
        }
        
        // Llamar al endpoint de Pomelo
        callPomeloAPI(
            url: backendUrl,
            headers: backendHeaders,
            payload: payload
        ) { result in
            switch result {
            case .success(let data):
                // Pomelo devuelve: activation_data, encrypted_pass_data, ephemeral_public_key
                guard let activationData = data["activation_data"] as? String,
                      let encryptedPassData = data["encrypted_pass_data"] as? String,
                      let ephemeralPublicKey = data["ephemeral_public_key"] as? String else {
                    handler(PKAddPaymentPassRequest())
                    return
                }
                
                // Convertir de Base64 a Data
                let request = PKAddPaymentPassRequest()
                request.activationData = Data(base64Encoded: activationData)
                request.encryptedPassData = Data(base64Encoded: encryptedPassData)
                request.ephemeralPublicKey = Data(base64Encoded: ephemeralPublicKey)
                
                handler(request)
                
            case .failure(let error):
                print("Error calling Pomelo: \(error)")
                handler(PKAddPaymentPassRequest())
            }
        }
    }
    
    // PASO 4: Resultado final
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        didFinishAdding pass: PKPaymentPass?,
        error: Error?
    ) {
        controller.dismiss(animated: true) {
            guard let command = self.currentCommand else { return }
            
            if let error = error {
                self.sendError(command, error.localizedDescription)
            } else if let pass = pass {
                let result: [String: Any] = [
                    "ok": true,
                    "added": true,
                    "serialNumber": pass.serialNumber,
                    "deviceAccountIdentifier": pass.deviceAccountIdentifier ?? ""
                ]
                let pluginResult = CDVPluginResult(status: .ok, messageAs: result)
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            } else {
                self.sendError(command, "user_cancelled")
            }
            
            self.currentCommand = nil
            self.addPaymentVC = nil
        }
    }
    
    // Función auxiliar para llamar a Pomelo
    private func callPomeloAPI(
        url: String,
        headers: [String: String],
        payload: [String: Any],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let requestUrl = URL(string: url) else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Agregar headers personalizados (Authorization, etc.)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["data"] as? [String: Any] else {
                completion(.failure(NSError(domain: "Invalid response", code: -2)))
                return
            }
            
            completion(.success(responseData))
        }
        
        task.resume()
    }
    
    private func sendError(_ command: CDVInvokedUrlCommand, _ message: String) {
        let result: [String: Any] = ["ok": false, "error": message]
        let pluginResult = CDVPluginResult(status: .error, messageAs: result)
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
}