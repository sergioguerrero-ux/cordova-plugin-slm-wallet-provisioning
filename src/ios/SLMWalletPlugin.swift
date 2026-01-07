import PassKit

@objc(SLMWalletPlugin)
class SLMWalletPlugin: CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var currentCommand: CDVInvokedUrlCommand?
    private var addPaymentVC: PKAddPaymentPassViewController?
    
    // Función auxiliar para enviar logs al JavaScript
    private func sendLog(_ message: String) {
        let jsCode = "console.log('[SWIFT] \(message.replacingOccurrences(of: "'", with: "\\'"))');"
        self.webView.evaluateJavaScript(jsCode, completionHandler: nil)
    }
    
    @objc(appleCanAdd:)
    func appleCanAdd(command: CDVInvokedUrlCommand) {
        sendLog("appleCanAdd llamado")
        let canAdd = PKAddPaymentPassViewController.canAddPaymentPass()
        sendLog("canAddPaymentPass = \(canAdd)")
        
        let result: [String: Any] = [
            "ok": true,
            "canAdd": canAdd
        ]
        
        let pluginResult = CDVPluginResult(status: .ok, messageAs: result)
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    @objc(appleStartAdd:)
    func appleStartAdd(command: CDVInvokedUrlCommand) {
        sendLog("========== INICIO appleStartAdd ==========")
        
        guard let options = command.arguments[0] as? [String: Any] else {
            sendLog("ERROR: options inválidas")
            sendError(command, "invalid_options")
            return
        }
        
        sendLog("Options recibidas OK")
        
        guard let cardId = options["cardId"] as? String else {
            sendLog("ERROR: cardId faltante")
            sendError(command, "missing_card_id")
            return
        }
        
        guard let holderName = options["holderName"] as? String else {
            sendLog("ERROR: holderName faltante")
            sendError(command, "missing_holder_name")
            return
        }
        
        guard let last4 = options["last4"] as? String else {
            sendLog("ERROR: last4 faltante")
            sendError(command, "missing_last4")
            return
        }
        
        sendLog("Parámetros OK - cardId: \(cardId)")
        
        let localizedDescription = options["localizedDescription"] as? String ?? "Tarjeta"
        
        let encryptionScheme: PKEncryptionScheme
        if let schemeStr = options["encryptionScheme"] as? String, schemeStr == "RSA_V2" {
            encryptionScheme = .RSA_V2
            sendLog("encryptionScheme: RSA_V2")
        } else {
            encryptionScheme = .ECC_V2
            sendLog("encryptionScheme: ECC_V2")
        }
        
        let cardBrand = options["cardBrand"] as? String ?? "mastercard"
        sendLog("cardBrand: \(cardBrand)")
        
        self.currentCommand = command
        sendLog("Command guardado")
        
        sendLog("Creando PKAddPaymentPassRequestConfiguration...")
        guard let config = PKAddPaymentPassRequestConfiguration(encryptionScheme: encryptionScheme) else {
            sendLog("ERROR: No se pudo crear configuración")
            sendError(command, "cannot_create_configuration")
            return
        }
        sendLog("✅ Configuración creada")
        
        config.cardholderName = holderName
        config.primaryAccountSuffix = last4
        config.localizedDescription = localizedDescription
        config.primaryAccountIdentifier = cardId
        
        if cardBrand.lowercased() == "visa" {
            config.paymentNetwork = .visa
            sendLog("paymentNetwork: VISA")
        } else {
            config.paymentNetwork = .masterCard
            sendLog("paymentNetwork: MASTERCARD")
        }
        
        sendLog("Creando PKAddPaymentPassViewController...")
        guard let vc = PKAddPaymentPassViewController(
            requestConfiguration: config,
            delegate: self
        ) else {
            sendLog("ERROR: No se pudo crear View Controller")
            sendError(command, "cannot_create_view_controller")
            return
        }
        sendLog("✅ View Controller creado")
        
        objc_setAssociatedObject(vc, "options", options, .OBJC_ASSOCIATION_RETAIN)
        self.addPaymentVC = vc
        
        sendLog("Intentando presentar UI...")
        DispatchQueue.main.async {
            self.sendLog("En main thread")
            
            if self.viewController.presentedViewController != nil {
                self.sendLog("WARNING: Ya hay un VC presentado")
            }
            
            self.viewController.present(vc, animated: true) {
                self.sendLog("✅ UI PRESENTADA (completion)")
            }
            
            self.sendLog("present() ejecutado")
        }
        
        sendLog("========== FIN appleStartAdd ==========")
    }
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        generateRequestWithCertificateChain certificates: [Data],
        nonce: Data,
        nonceSignature: Data,
        completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void
    ) {
        sendLog("========== generateRequest LLAMADO ==========")
        sendLog("Certificados: \(certificates.count)")
        
        guard let options = objc_getAssociatedObject(controller, "options") as? [String: Any],
              let cardId = options["cardId"] as? String else {
            sendLog("ERROR: No se pudieron recuperar opciones")
            handler(PKAddPaymentPassRequest())
            return
        }
        
        sendLog("cardId: \(cardId)")
        
        let backendUrl = options["backendUrl"] as? String ?? 
            "https://api.pomelo.la/token-provisioning/mastercard/apple-pay"
        sendLog("backendUrl: \(backendUrl)")
        
        let backendHeaders = options["backendHeaders"] as? [String: String] ?? [:]
        let userId = options["userId"] as? String
        
        var payload: [String: Any] = [
            "card_id": cardId,
            "certificates": certificates.map { $0.base64EncodedString() },
            "nonce": nonce.base64EncodedString(),
            "nonce_signature": nonceSignature.base64EncodedString()
        ]
        
        if let userId = userId {
            payload["user_id"] = userId
        }
        
        sendLog("Llamando API de Pomelo...")
        
        callPomeloAPI(
            url: backendUrl,
            headers: backendHeaders,
            payload: payload
        ) { result in
            switch result {
            case .success(let data):
                self.sendLog("✅ API respondió OK")
                
                guard let activationData = data["activation_data"] as? String,
                      let encryptedPassData = data["encrypted_pass_data"] as? String,
                      let ephemeralPublicKey = data["ephemeral_public_key"] as? String else {
                    self.sendLog("ERROR: Campos faltantes en respuesta")
                    handler(PKAddPaymentPassRequest())
                    return
                }
                
                self.sendLog("Decodificando datos...")
                
                let request = PKAddPaymentPassRequest()
                request.activationData = Data(base64Encoded: activationData)
                request.encryptedPassData = Data(base64Encoded: encryptedPassData)
                request.ephemeralPublicKey = Data(base64Encoded: ephemeralPublicKey)
                
                self.sendLog("✅ Enviando datos a Apple")
                handler(request)
                
            case .failure(let error):
                self.sendLog("ERROR API: \(error.localizedDescription)")
                handler(PKAddPaymentPassRequest())
            }
        }
    }
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        didFinishAdding pass: PKPaymentPass?,
        error: Error?
    ) {
        sendLog("========== didFinishAdding LLAMADO ==========")
        
        if let error = error {
            sendLog("ERROR: \(error.localizedDescription)")
        }
        
        if let pass = pass {
            sendLog("✅ Tarjeta agregada: \(pass.serialNumber)")
        }
        
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
                self.sendLog("✅ Resultado enviado")
            } else {
                self.sendError(command, "user_cancelled")
            }
            
            self.currentCommand = nil
            self.addPaymentVC = nil
        }
    }
    
    private func callPomeloAPI(
        url: String,
        headers: [String: String],
        payload: [String: Any],
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let requestUrl = URL(string: url) else {
            sendLog("ERROR: URL inválida")
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }
        
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            sendLog("ERROR: Serializando JSON")
            completion(.failure(error))
            return
        }
        
        sendLog("Request enviado")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.sendLog("ERROR: Network - \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                self.sendLog("HTTP Status: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                self.sendLog("ERROR: No data")
                completion(.failure(NSError(domain: "No data", code: -2)))
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseData = json["data"] as? [String: Any] else {
                self.sendLog("ERROR: Invalid JSON response")
                completion(.failure(NSError(domain: "Invalid response", code: -3)))
                return
            }
            
            completion(.success(responseData))
        }
        
        task.resume()
    }
    
    private func sendError(_ command: CDVInvokedUrlCommand, _ message: String) {
        sendLog("Enviando error: \(message)")
        let result: [String: Any] = ["ok": false, "error": message]
        let pluginResult = CDVPluginResult(status: .error, messageAs: result)
        commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
}