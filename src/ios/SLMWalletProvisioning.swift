import Foundation
import PassKit

@objc(SLMWalletProvisioning)
class SLMWalletProvisioning: CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var commandCallback: String?
    private var addPaymentPassVC: PKAddPaymentPassViewController?
    private var pendingCompletionHandler: ((PKAddPaymentPassRequest) -> Void)?
    
    // Helper para enviar logs a JavaScript
    private func logToJS(_ message: String, type: String = "info") {
        let escapedMessage = message.replacingOccurrences(of: "'", with: "\\'")
        let jsCode = "if(typeof addLog === 'function') { addLog('[SWIFT] \(escapedMessage)', '\(type)'); }"
        self.commandDelegate.evalJs(jsCode)
    }
    
    // MARK: - Can Add Card
    
    @objc(canAddCard:)
    func canAddCard(command: CDVInvokedUrlCommand) {
        logToJS("🔍 Verificando si puede agregar tarjeta...", type: "info")
        
        do {
            logToJS("   Step 1: Creando diccionario result...", type: "info")
            var result: [String: Any] = [:]
            
            logToJS("   Step 2: Llamando PKAddPaymentPassViewController.canAddPaymentPass()...", type: "info")
            let canAddPass = PKAddPaymentPassViewController.canAddPaymentPass()
            logToJS("   Step 2 OK: canAddPass = \(canAddPass)", type: "success")
            
            logToJS("   Step 3: Creando PKPassLibrary()...", type: "info")
            let passLibrary = PKPassLibrary()
            logToJS("   Step 3 OK", type: "success")
            
            logToJS("   Step 4: Obteniendo passes of .payment...", type: "info")
            let paymentPasses = passLibrary.passes(of: .payment)
            logToJS("   Step 4 OK: \(paymentPasses.count) passes encontrados", type: "success")
            
            logToJS("   Step 5: Calculando hasCards...", type: "info")
            let hasCards = !paymentPasses.isEmpty
            logToJS("   Step 5 OK: hasCards = \(hasCards)", type: "success")
            
            logToJS("   Step 6: Llamando PKPassLibrary.isPassLibraryAvailable()...", type: "info")
            let libraryAvailable = PKPassLibrary.isPassLibraryAvailable()
            logToJS("   Step 6 OK: libraryAvailable = \(libraryAvailable)", type: "success")
            
            logToJS("   Step 7: Construyendo result dictionary...", type: "info")
            result["canAdd"] = canAddPass
            result["hasCardsInWallet"] = hasCards
            result["deviceSupportsWallet"] = libraryAvailable
            result["message"] = canAddPass ? "Device supports Apple Wallet provisioning" : "Device does not support Apple Wallet"
            logToJS("   Step 7 OK", type: "success")
            
            logToJS("✅ Resultado: canAdd=\(canAddPass), hasCards=\(hasCards), deviceSupports=\(libraryAvailable)", type: "success")
            
            logToJS("   Step 8: Creando CDVPluginResult...", type: "info")
            let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
            logToJS("   Step 8 OK", type: "success")
            
            logToJS("   Step 9: Enviando resultado al callback...", type: "info")
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            logToJS("✅ ✅ ✅ CALLBACK ENVIADO EXITOSAMENTE!", type: "success")
            
        } catch let error {
            logToJS("❌ ERROR CAPTURADO: \(error.localizedDescription)", type: "error")
            let errorResult = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Error: \(error.localizedDescription)")
            self.commandDelegate.send(errorResult, callbackId: command.callbackId)
        }
    }
    
    // MARK: - Is Card In Wallet
    
    @objc(isCardInWallet:)
    func isCardInWallet(command: CDVInvokedUrlCommand) {
        logToJS("🔍 Verificando si tarjeta existe en Wallet...")
        
        guard let params = command.arguments[0] as? [String: Any],
              let lastFourDigits = params["lastFourDigits"] as? String else {
            logToJS("❌ Faltan parámetros", type: "error")
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Missing lastFourDigits")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
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
        
        logToJS("✅ Tarjeta existe: \(cardExists)", type: cardExists ? "warning" : "success")
        
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
    }
    
    // MARK: - Start Provisioning
    
    @objc(startProvisioning:)
    func startProvisioning(command: CDVInvokedUrlCommand) {
        self.commandCallback = command.callbackId
        
        logToJS("🚀 [SWIFT] Iniciando provisioning...")
        
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
        
        logToJS("✅ Parámetros: \(cardId), \(cardholderName), \(lastFourDigits)", type: "success")
        
        let localizedDescription = params["localizedDescription"] as? String ?? "Tarjeta"
        let paymentNetwork = params["paymentNetwork"] as? String ?? "mastercard"
        
        guard PKAddPaymentPassViewController.canAddPaymentPass() else {
            logToJS("❌ Device cannot add payment passes", type: "error")
            self.sendError("Device cannot add payment passes")
            return
        }
        
        logToJS("✅ Device puede agregar tarjetas", type: "success")
        
        guard let configuration = PKAddPaymentPassRequestConfiguration(encryptionScheme: .ECC_V2) else {
            logToJS("❌ Failed to create configuration", type: "error")
            self.sendError("Failed to create configuration")
            return
        }
        
        configuration.cardholderName = cardholderName
        configuration.primaryAccountSuffix = lastFourDigits
        configuration.localizedDescription = localizedDescription
        configuration.paymentNetwork = self.getPaymentNetwork(paymentNetwork)
        
        logToJS("✅ Configuration creada", type: "success")
        
        guard let addPaymentPassVC = PKAddPaymentPassViewController(
            requestConfiguration: configuration,
            delegate: self
        ) else {
            logToJS("❌ No se pudo crear PKAddPaymentPassViewController", type: "error")
            self.sendError("Cannot create Apple Pay view controller")
            return
        }
        
        logToJS("✅ PKAddPaymentPassViewController creado", type: "success")
        
        self.addPaymentPassVC = addPaymentPassVC
        UserDefaults.standard.set(cardId, forKey: "currentCardIdProvisioning")
        
        // BUSCAR VIEW CONTROLLER
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                self?.logToJS("❌ self is nil", type: "error")
                return
            }
            
            self.logToJS("🔍 Buscando view controller para presentar...")
            
            var topController: UIViewController?
            
            // Método 1: self.viewController
            if let cordovaVC = self.viewController {
                self.logToJS("✅ Método 1: self.viewController encontrado", type: "success")
                topController = cordovaVC
            } else {
                self.logToJS("⚠️ Método 1: self.viewController es nil", type: "warning")
            }
            
            // Método 2: keyWindow
            if topController == nil {
                if let keyWindow = UIApplication.shared.keyWindow,
                   let rootVC = keyWindow.rootViewController {
                    self.logToJS("✅ Método 2: keyWindow.rootViewController encontrado", type: "success")
                    topController = rootVC
                } else {
                    self.logToJS("⚠️ Método 2: keyWindow no disponible", type: "warning")
                }
            }
            
            // Método 3: Buscar en windows
            if topController == nil {
                for window in UIApplication.shared.windows {
                    if let rootVC = window.rootViewController {
                        self.logToJS("✅ Método 3: Window con rootViewController encontrado", type: "success")
                        topController = rootVC
                        break
                    }
                }
            }
            
            guard var presentingController = topController else {
                self.logToJS("❌ No se encontró ningún view controller", type: "error")
                self.sendError("No view controller available to present Apple Wallet")
                return
            }
            
            self.logToJS("✅ View controller inicial encontrado")
            
            // Subir por la jerarquía
            var levels = 0
            while let presentedViewController = presentingController.presentedViewController {
                levels += 1
                presentingController = presentedViewController
            }
            
            if levels > 0 {
                self.logToJS("⬆️ Subí \(levels) niveles en la jerarquía")
            }
            
            self.logToJS("🎬 Presentando Apple Wallet UI...", type: "info")
            
            presentingController.present(addPaymentPassVC, animated: true) {
                self.logToJS("✅ ✅ ✅ Apple Wallet UI PRESENTADO! ✅ ✅ ✅", type: "success")
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
            logToJS("❌ No se encontró cardId guardado", type: "error")
            return
        }
        
        let certificatesBase64 = certificates.map { $0.base64EncodedString() }
        let nonceBase64 = nonce.base64EncodedString()
        let nonceSignatureBase64 = nonceSignature.base64EncodedString()
        
        logToJS("📦 Datos de Apple: \(certificates.count) certificados, nonce length: \(nonce.count)")
        
        let provisioningData: [String: Any] = [
            "cardId": cardId,
            "certificates": certificatesBase64,
            "nonce": nonceBase64,
            "nonceSignature": nonceSignatureBase64
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: provisioningData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            logToJS("❌ Error al serializar JSON", type: "error")
            return
        }
        
        logToJS("📤 Enviando evento a JavaScript...")
        
        let jsCode = """
        cordova.fireDocumentEvent('onApplePayProvisioningRequest', \(jsonString));
        """
        
        self.commandDelegate.evalJs(jsCode)
        logToJS("✅ Evento enviado a JavaScript", type: "success")
    }
    
    // MARK: - Complete Provisioning
    
    @objc(completeProvisioning:)
    func completeProvisioning(command: CDVInvokedUrlCommand) {
        logToJS("📥 Recibiendo datos de Pomelo para completar provisioning...")
        
        guard let params = command.arguments[0] as? [String: Any],
              let activationDataBase64 = params["activationData"] as? String,
              let encryptedPassDataBase64 = params["encryptedPassData"] as? String,
              let ephemeralPublicKeyBase64 = params["ephemeralPublicKey"] as? String else {
            logToJS("❌ Faltan datos de Pomelo", type: "error")
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Missing data")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        guard let activationData = Data(base64Encoded: activationDataBase64),
              let encryptedPassData = Data(base64Encoded: encryptedPassDataBase64),
              let ephemeralPublicKey = Data(base64Encoded: ephemeralPublicKeyBase64) else {
            logToJS("❌ Error al decodificar Base64", type: "error")
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid Base64")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        logToJS("✅ Datos de Pomelo decodificados correctamente")
        logToJS("   activation_data: \(activationData.count) bytes")
        logToJS("   encrypted_pass_data: \(encryptedPassData.count) bytes")
        logToJS("   ephemeral_public_key: \(ephemeralPublicKey.count) bytes")
        
        let request = PKAddPaymentPassRequest()
        request.activationData = activationData
        request.encryptedPassData = encryptedPassData
        request.ephemeralPublicKey = ephemeralPublicKey
        
        if let handler = self.pendingCompletionHandler {
            logToJS("📤 Enviando datos a Apple...", type: "info")
            handler(request)
            self.pendingCompletionHandler = nil
            logToJS("✅ Datos enviados a Apple exitosamente", type: "success")
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
                self.logToJS("🎉 ¡Tarjeta agregada exitosamente!", type: "success")
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
        logToJS("🧪 Test callback ejecutado", type: "success")
        let result = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: ["test": "success", "message": "Plugin callbacks work!"]
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