import Foundation
import PassKit

@objc(SLMWalletProvisioning)
class SLMWalletProvisioning: CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var commandCallback: String?
    private var addPaymentPassVC: PKAddPaymentPassViewController?
    private var pendingCompletionHandler: ((PKAddPaymentPassRequest) -> Void)?
    
    // MARK: - Verificar disponibilidad de Apple Pay
    
    @objc(canAddCard:)
    func canAddCard(command: CDVInvokedUrlCommand) {
        var result: [String: Any] = [:]
        
        // Verificar si el dispositivo soporta Apple Pay
        let canAddPass = PKAddPaymentPassViewController.canAddPaymentPass()
        
        // Verificar si hay al menos una tarjeta en Wallet (opcional)
        let passLibrary = PKPassLibrary()
        let hasCards = !passLibrary.passes(of: .payment).isEmpty
        
        result["canAdd"] = canAddPass
        result["hasCardsInWallet"] = hasCards
        result["deviceSupportsWallet"] = PKPassLibrary.isPassLibraryAvailable()
        
        if canAddPass {
            result["message"] = "Device supports Apple Wallet provisioning"
        } else {
            result["message"] = "Device does not support Apple Wallet or user has restrictions"
        }
        
        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: result
        )
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    // MARK: - Verificar si tarjeta existe en Wallet
    
    @objc(isCardInWallet:)
    func isCardInWallet(command: CDVInvokedUrlCommand) {
        guard let params = command.arguments[0] as? [String: Any],
              let lastFourDigits = params["lastFourDigits"] as? String else {
            let result = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: "Missing lastFourDigits parameter"
            )
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
    
    // MARK: - Iniciar Push Provisioning (Pomelo Flow)
    
    @objc(startProvisioning:)
    func startProvisioning(command: CDVInvokedUrlCommand) {
        self.commandCallback = command.callbackId
        
        guard let params = command.arguments[0] as? [String: Any] else {
            self.sendError("Invalid parameters")
            return
        }
        
        // Parámetros requeridos por Pomelo
        guard let cardId = params["cardId"] as? String,
              let cardholderName = params["cardholderName"] as? String,
              let lastFourDigits = params["lastFourDigits"] as? String else {
            self.sendError("Missing required parameters: cardId, cardholderName, or lastFourDigits")
            return
        }
        
        // Parámetros opcionales
        let localizedDescription = params["localizedDescription"] as? String ?? "Tarjeta"
        let paymentNetwork = params["paymentNetwork"] as? String ?? "mastercard"
        
        // Crear configuración para Apple Pay
        guard let configuration = PKAddPaymentPassRequestConfiguration(
            encryptionScheme: .ECC_V2
        ) else {
            self.sendError("Failed to create provisioning configuration")
            return
        }
        
        configuration.cardholderName = cardholderName
        configuration.primaryAccountSuffix = lastFourDigits
        configuration.localizedDescription = localizedDescription
        configuration.paymentNetwork = self.getPaymentNetwork(paymentNetwork)
        
        // Crear el view controller
        guard let addPaymentPassVC = PKAddPaymentPassViewController(
            requestConfiguration: configuration,
            delegate: self
        ) else {
            self.sendError("Cannot create Apple Pay view controller. Check device compatibility.")
            return
        }
        
        self.addPaymentPassVC = addPaymentPassVC
        
        // Guardar cardId para usarlo en el callback
        UserDefaults.standard.set(cardId, forKey: "currentCardIdProvisioning")
        
        // Presentar UI de Apple Pay
        DispatchQueue.main.async {
            self.viewController.present(addPaymentPassVC, animated: true) {
                NSLog("✅ Apple Pay provisioning view presented")
            }
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
        NSLog("📱 Apple requesting provisioning data...")
        
        // Guardar el handler para usarlo después
        self.pendingCompletionHandler = handler
        
        // Recuperar cardId
        guard let cardId = UserDefaults.standard.string(forKey: "currentCardIdProvisioning") else {
            NSLog("❌ Missing cardId in UserDefaults")
            return
        }
        
        // Convertir datos a Base64 para enviar a Pomelo
        let certificatesBase64 = certificates.map { $0.base64EncodedString() }
        let nonceBase64 = nonce.base64EncodedString()
        let nonceSignatureBase64 = nonceSignature.base64EncodedString()
        
        // Preparar datos para enviar al JavaScript
        let provisioningData: [String: Any] = [
            "cardId": cardId,
            "certificates": certificatesBase64,
            "nonce": nonceBase64,
            "nonceSignature": nonceSignatureBase64
        ]
        
        // Convertir a JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: provisioningData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            NSLog("❌ Failed to serialize provisioning data")
            return
        }
        
        // Enviar evento a JavaScript para que llame a Pomelo
        let jsCode = """
        cordova.fireDocumentEvent('onApplePayProvisioningRequest', \(jsonString));
        """
        
        self.commandDelegate.evalJs(jsCode)
        
        NSLog("✅ Provisioning data sent to JavaScript layer")
    }
    
    // MARK: - Completar Provisioning con respuesta de Pomelo
    
    @objc(completeProvisioning:)
    func completeProvisioning(command: CDVInvokedUrlCommand) {
        guard let params = command.arguments[0] as? [String: Any],
              let activationDataBase64 = params["activationData"] as? String,
              let encryptedPassDataBase64 = params["encryptedPassData"] as? String,
              let ephemeralPublicKeyBase64 = params["ephemeralPublicKey"] as? String else {
            
            let result = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: "Missing provisioning data from Pomelo"
            )
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        // Decodificar datos de Pomelo
        guard let activationData = Data(base64Encoded: activationDataBase64),
              let encryptedPassData = Data(base64Encoded: encryptedPassDataBase64),
              let ephemeralPublicKey = Data(base64Encoded: ephemeralPublicKeyBase64) else {
            
            let result = CDVPluginResult(
                status: CDVCommandStatus_ERROR,
                messageAs: "Invalid base64 data from Pomelo"
            )
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        // Crear request para Apple
        let request = PKAddPaymentPassRequest()
        request.activationData = activationData
        request.encryptedPassData = encryptedPassData
        request.ephemeralPublicKey = ephemeralPublicKey
        
        // Ejecutar el completion handler guardado
        if let handler = self.pendingCompletionHandler {
            NSLog("✅ Sending encrypted data to Apple...")
            handler(request)
            self.pendingCompletionHandler = nil
        } else {
            NSLog("❌ No pending completion handler found")
        }
        
        // Confirmar a JavaScript
        let result = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: "Provisioning data sent to Apple"
        )
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }

    @objc(testCallback:)
    func testCallback(command: CDVInvokedUrlCommand) {
        NSLog("🧪 [SLMWallet] TEST CALLBACK called")
        
        // Responder inmediatamente con éxito
        let result = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: ["test": "success", "message": "Plugin callbacks work!"]
        )
        self.commandDelegate.send(result, callbackId: command.callbackId)
        
        NSLog("🧪 [SLMWallet] TEST CALLBACK response sent")
    }
    // MARK: - Resultado final del provisioning
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        didFinishAdding pass: PKPaymentPass?,
        error: Error?
    ) {
        // Cerrar el view controller
        controller.dismiss(animated: true) {
            // Limpiar datos temporales
            UserDefaults.standard.removeObject(forKey: "currentCardIdProvisioning")
            
            if let error = error {
                NSLog("❌ Provisioning failed: \(error.localizedDescription)")
                self.sendError("Provisioning failed: \(error.localizedDescription)")
                
            } else if let pass = pass {
                NSLog("✅ Card successfully added to Apple Wallet!")
                
                self.sendSuccess([
                    "success": true,
                    "message": "Card successfully added to Apple Wallet",
                    "passTypeIdentifier": pass.passTypeIdentifier,
                    "serialNumber": pass.serialNumber,
                    "primaryAccountSuffix": pass.primaryAccountNumberSuffix,
                    "deviceAccountIdentifier": pass.deviceAccountIdentifier ?? "N/A",
                    "deviceAccountNumberSuffix": pass.deviceAccountNumberSuffix ?? "N/A"
                ])
                
            } else {
                NSLog("⚠️ Provisioning cancelled by user")
                self.sendError("Provisioning cancelled by user")
            }
        }
    }
    
    // MARK: - Helper Functions
    
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
            return .masterCard // Pomelo usa principalmente Mastercard
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