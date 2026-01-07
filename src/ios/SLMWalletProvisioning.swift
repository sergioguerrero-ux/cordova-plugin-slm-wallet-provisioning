import Foundation
import PassKit

@objc(SLMWalletProvisioning)
class SLMWalletProvisioning: CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var commandCallback: String?
    private var addPaymentPassVC: PKAddPaymentPassViewController?
    private var pendingCompletionHandler: ((PKAddPaymentPassRequest) -> Void)?
    
    // ✅ VERSIÓN MEJORADA: No bloquea, usa async, con fallback
    private func logToJS(_ message: String, type: String = "info") {
        // Siempre print primero (por si acaso)
        print("[SWIFT] \(message)")
        
        // Escapar comillas y caracteres especiales
        let escapedMessage = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        // Ejecutar en background para no bloquear
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Intentar enviar a JS pero sin bloquear si falla
            let jsCode = """
            (function() {
                try {
                    if (typeof addLog === 'function') {
                        addLog('[SWIFT] \(escapedMessage)', '\(type)');
                    } else {
                        console.log('[SWIFT] \(escapedMessage)');
                    }
                } catch(e) {
                    console.log('[SWIFT LOG ERROR]', e);
                }
            })();
            """
            
            self.commandDelegate?.evalJs(jsCode)
        }
    }
    
    // MARK: - Can Add Card
    
    @objc(canAddCard:)
    func canAddCard(command: CDVInvokedUrlCommand) {
        logToJS("🔍 canAddCard iniciado")
        
        // Ejecutar en background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                self?.logToJS("❌ self is nil", type: "error")
                return
            }
            
            self.logToJS("   → Paso 1: Creando result dictionary")
            var result: [String: Any] = [:]
            
            self.logToJS("   → Paso 2: Verificando canAddPaymentPass")
            let canAddPass = PKAddPaymentPassViewController.canAddPaymentPass()
            self.logToJS("   ✅ canAddPass = \(canAddPass)", type: "success")
            
            self.logToJS("   → Paso 3: Creando PKPassLibrary")
            let passLibrary = PKPassLibrary()
            
            self.logToJS("   → Paso 4: Obteniendo payment passes")
            let paymentPasses = passLibrary.passes(of: .payment)
            self.logToJS("   ✅ Encontrados \(paymentPasses.count) passes", type: "success")
            
            let hasCards = !paymentPasses.isEmpty
            let libraryAvailable = PKPassLibrary.isPassLibraryAvailable()
            
            result["canAdd"] = canAddPass
            result["hasCardsInWallet"] = hasCards
            result["deviceSupportsWallet"] = libraryAvailable
            result["message"] = canAddPass ? "Device supports Apple Wallet provisioning" : "Device does not support Apple Wallet"
            
            self.logToJS("   → Paso 5: Enviando resultado", type: "success")
            
            // Volver al main thread para enviar el callback
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                self.logToJS("✅ ✅ ✅ canAddCard COMPLETADO!", type: "success")
            }
        }
    }
    
    // MARK: - Is Card In Wallet
    
    @objc(isCardInWallet:)
    func isCardInWallet(command: CDVInvokedUrlCommand) {
        logToJS("🔍 isCardInWallet iniciado")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard let params = command.arguments[0] as? [String: Any],
                  let lastFourDigits = params["lastFourDigits"] as? String else {
                self.logToJS("❌ Faltan parámetros", type: "error")
                DispatchQueue.main.async {
                    let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Missing lastFourDigits")
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                }
                return
            }
            
            self.logToJS("   → Buscando tarjeta terminada en \(lastFourDigits)")
            
            let passLibrary = PKPassLibrary()
            let paymentPasses = passLibrary.passes(of: .payment)
            
            var cardExists = false
            var matchedCards: [[String: Any]] = []
            
            for pass in paymentPasses {
                if let paymentPass = pass as? PKPaymentPass {
                    if paymentPass.primaryAccountNumberSuffix == lastFourDigits {
                        cardExists = true
                        matchedCards.append([
                            "suffix": paymentPass.primaryAccountNumberSuffix,
                            "passTypeIdentifier": paymentPass.passTypeIdentifier,
                            "serialNumber": paymentPass.serialNumber
                        ])
                    }
                }
            }
            
            self.logToJS("   ✅ Tarjeta existe: \(cardExists)", type: cardExists ? "warning" : "success")
            
            DispatchQueue.main.async {
                let result = CDVPluginResult(
                    status: CDVCommandStatus_OK,
                    messageAs: [
                        "exists": cardExists,
                        "lastFourDigits": lastFourDigits,
                        "matchedCards": matchedCards,
                        "totalCardsInWallet": paymentPasses.count
                    ]
                )
                self.commandDelegate.send(result, callbackId: command.callbackId)
                self.logToJS("✅ ✅ ✅ isCardInWallet COMPLETADO!", type: "success")
            }
        }
    }
    
    // MARK: - Start Provisioning
    
    @objc(startProvisioning:)
    func startProvisioning(command: CDVInvokedUrlCommand) {
        self.commandCallback = command.callbackId
        
        logToJS("🚀 startProvisioning iniciado", type: "info")
        
        guard let params = command.arguments[0] as? [String: Any] else {
            logToJS("❌ Parámetros inválidos", type: "error")
            self.sendError("Invalid parameters")
            return
        }
        
        guard let cardId = params["cardId"] as? String,
              let cardholderName = params["cardholderName"] as? String,
              let lastFourDigits = params["lastFourDigits"] as? String else {
            logToJS("❌ Faltan parámetros requeridos", type: "error")
            self.sendError("Missing required parameters")
            return
        }
        
        logToJS("   ✅ Parámetros OK: \(cardId), \(cardholderName), \(lastFourDigits)", type: "success")
        
        let localizedDescription = params["localizedDescription"] as? String ?? "Tarjeta"
        let paymentNetwork = params["paymentNetwork"] as? String ?? "mastercard"
        
        logToJS("   → Verificando canAddPaymentPass...")
        guard PKAddPaymentPassViewController.canAddPaymentPass() else {
            logToJS("❌ Device cannot add payment passes", type: "error")
            self.sendError("Device cannot add payment passes")
            return
        }
        logToJS("   ✅ Device puede agregar tarjetas", type: "success")
        
        logToJS("   → Creando configuration...")
        guard let configuration = PKAddPaymentPassRequestConfiguration(encryptionScheme: .ECC_V2) else {
            logToJS("❌ Failed to create configuration", type: "error")
            self.sendError("Failed to create configuration")
            return
        }
        
        configuration.cardholderName = cardholderName
        configuration.primaryAccountSuffix = lastFourDigits
        configuration.localizedDescription = localizedDescription
        configuration.paymentNetwork = self.getPaymentNetwork(paymentNetwork)
        logToJS("   ✅ Configuration creada", type: "success")
        
        logToJS("   → Creando PKAddPaymentPassViewController...")
        guard let addPaymentPassVC = PKAddPaymentPassViewController(
            requestConfiguration: configuration,
            delegate: self
        ) else {
            logToJS("❌ No se pudo crear PKAddPaymentPassViewController", type: "error")
            self.sendError("Cannot create Apple Pay view controller")
            return
        }
        logToJS("   ✅ PKAddPaymentPassViewController creado", type: "success")
        
        self.addPaymentPassVC = addPaymentPassVC
        UserDefaults.standard.set(cardId, forKey: "currentCardIdProvisioning")
        
        logToJS("   → Buscando view controller para presentar...")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                self?.logToJS("❌ self is nil en main queue", type: "error")
                return
            }
            
            var topController: UIViewController?
            
            // Método 1
            if let cordovaVC = self.viewController {
                self.logToJS("   ✅ Método 1: self.viewController encontrado", type: "success")
                topController = cordovaVC
            } else {
                self.logToJS("   ⚠️ Método 1 falló: self.viewController es nil", type: "warning")
            }
            
            // Método 2
            if topController == nil {
                if let keyWindow = UIApplication.shared.keyWindow,
                   let rootVC = keyWindow.rootViewController {
                    self.logToJS("   ✅ Método 2: keyWindow.rootViewController encontrado", type: "success")
                    topController = rootVC
                } else {
                    self.logToJS("   ⚠️ Método 2 falló", type: "warning")
                }
            }
            
            // Método 3
            if topController == nil {
                for window in UIApplication.shared.windows {
                    if let rootVC = window.rootViewController {
                        self.logToJS("   ✅ Método 3: Window rootViewController encontrado", type: "success")
                        topController = rootVC
                        break
                    }
                }
            }
            
            guard var presentingController = topController else {
                self.logToJS("❌ No se encontró view controller", type: "error")
                self.sendError("No view controller available")
                return
            }
            
            self.logToJS("   ✅ View controller base encontrado")
            
            // Subir por la jerarquía
            var levels = 0
            while let presentedVC = presentingController.presentedViewController {
                levels += 1
                presentingController = presentedVC
            }
            
            if levels > 0 {
                self.logToJS("   ⬆️ Subí \(levels) niveles")
            }
            
            self.logToJS("🎬 PRESENTANDO APPLE WALLET UI...", type: "info")
            
            presentingController.present(addPaymentPassVC, animated: true) {
                self.logToJS("✅ ✅ ✅ APPLE WALLET UI VISIBLE! ✅ ✅ ✅", type: "success")
            }
        }
    }
    
    // MARK: - Generate Request Delegate
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        generateRequestWithCertificateChain certificates: [Data],
        nonce: Data,
        nonceSignature: Data,
        completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void
    ) {
        logToJS("📱 Apple solicitó datos de provisioning!", type: "info")
        
        self.pendingCompletionHandler = handler
        
        guard let cardId = UserDefaults.standard.string(forKey: "currentCardIdProvisioning") else {
            logToJS("❌ cardId no encontrado", type: "error")
            return
        }
        
        let certificatesBase64 = certificates.map { $0.base64EncodedString() }
        let nonceBase64 = nonce.base64EncodedString()
        let nonceSignatureBase64 = nonceSignature.base64EncodedString()
        
        logToJS("📦 Datos: \(certificates.count) certs, nonce: \(nonce.count) bytes")
        
        let provisioningData: [String: Any] = [
            "cardId": cardId,
            "certificates": certificatesBase64,
            "nonce": nonceBase64,
            "nonceSignature": nonceSignatureBase64
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: provisioningData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            logToJS("❌ Error serializando JSON", type: "error")
            return
        }
        
        logToJS("📤 Enviando evento a JavaScript...")
        
        let jsCode = """
        cordova.fireDocumentEvent('onApplePayProvisioningRequest', \(jsonString));
        """
        
        self.commandDelegate.evalJs(jsCode)
        logToJS("✅ Evento enviado", type: "success")
    }
    
    // MARK: - Complete Provisioning
    
    @objc(completeProvisioning:)
    func completeProvisioning(command: CDVInvokedUrlCommand) {
        logToJS("📥 Completando provisioning con datos de Pomelo...")
        
        guard let params = command.arguments[0] as? [String: Any],
              let activationDataBase64 = params["activationData"] as? String,
              let encryptedPassDataBase64 = params["encryptedPassData"] as? String,
              let ephemeralPublicKeyBase64 = params["ephemeralPublicKey"] as? String else {
            logToJS("❌ Faltan datos", type: "error")
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Missing data")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        guard let activationData = Data(base64Encoded: activationDataBase64),
              let encryptedPassData = Data(base64Encoded: encryptedPassDataBase64),
              let ephemeralPublicKey = Data(base64Encoded: ephemeralPublicKeyBase64) else {
            logToJS("❌ Error decodificando Base64", type: "error")
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid Base64")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        logToJS("✅ Datos decodificados: act=\(activationData.count), enc=\(encryptedPassData.count), eph=\(ephemeralPublicKey.count)")
        
        let request = PKAddPaymentPassRequest()
        request.activationData = activationData
        request.encryptedPassData = encryptedPassData
        request.ephemeralPublicKey = ephemeralPublicKey
        
        if let handler = self.pendingCompletionHandler {
            logToJS("📤 Enviando a Apple...", type: "info")
            handler(request)
            self.pendingCompletionHandler = nil
            logToJS("✅ Datos enviados a Apple", type: "success")
        } else {
            logToJS("❌ No hay handler pendiente", type: "error")
        }
        
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Data sent to Apple")
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    
    // MARK: - Did Finish Delegate
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        didFinishAdding pass: PKPaymentPass?,
        error: Error?
    ) {
        logToJS("🏁 Apple Wallet finalizó", type: "info")
        
        controller.dismiss(animated: true) {
            UserDefaults.standard.removeObject(forKey: "currentCardIdProvisioning")
            
            if let error = error {
                self.logToJS("❌ Error: \(error.localizedDescription)", type: "error")
                self.sendError("Provisioning failed: \(error.localizedDescription)")
            } else if let pass = pass {
                self.logToJS("🎉 Tarjeta agregada!", type: "success")
                self.sendSuccess([
                    "success": true,
                    "message": "Card added successfully",
                    "passTypeIdentifier": pass.passTypeIdentifier,
                    "serialNumber": pass.serialNumber,
                    "primaryAccountSuffix": pass.primaryAccountNumberSuffix
                ])
            } else {
                self.logToJS("⚠️ Usuario canceló", type: "warning")
                self.sendError("User cancelled")
            }
        }
    }
    
    // MARK: - Test Callback
    
    @objc(testCallback:)
    func testCallback(command: CDVInvokedUrlCommand) {
        logToJS("🧪 Test callback", type: "success")
        let result = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: ["test": "success", "message": "Plugin works!"]
        )
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    
    // MARK: - Helpers
    
    private func getPaymentNetwork(_ network: String) -> PKPaymentNetwork {
        switch network.lowercased() {
        case "visa":
            return .visa
        case "mastercard", "masterCard":
            return .masterCard
        case "amex", "americanexpress":
            return .amex
        case "discover":
            return .discover
        default:
            return .masterCard
        }
    }
    
    private func sendSuccess(_ data: [String: Any]) {
        guard let callbackId = self.commandCallback else { return }
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: data)
        self.commandDelegate.send(result, callbackId: callbackId)
        self.commandCallback = nil
    }
    
    private func sendError(_ message: String) {
        guard let callbackId = self.commandCallback else { return }
        let result = CDVPluginResult(
            status: CDVCommandStatus_ERROR,
            messageAs: ["error": true, "message": message]
        )
        self.commandDelegate.send(result, callbackId: callbackId)
        self.commandCallback = nil
    }
}