import Foundation
import PassKit

@objc(SLMWalletProvisioning)
class SLMWalletProvisioning: CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var commandCallback: String?
    private var addPaymentPassVC: PKAddPaymentPassViewController?
    private var pendingCompletionHandler: ((PKAddPaymentPassRequest) -> Void)?
    
    // MARK: - Can Add Card
    
    @objc(canAddCard:)
    func canAddCard(command: CDVInvokedUrlCommand) {
        var result: [String: Any] = [:]
        
        let canAddPass = PKAddPaymentPassViewController.canAddPaymentPass()
        let passLibrary = PKPassLibrary()
        let hasCards = !passLibrary.passes(of: .payment).isEmpty
        
        result["canAdd"] = canAddPass
        result["hasCardsInWallet"] = hasCards
        result["deviceSupportsWallet"] = PKPassLibrary.isPassLibraryAvailable()
        result["message"] = canAddPass ? "Device supports Apple Wallet provisioning" : "Device does not support Apple Wallet"
        
        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    // MARK: - Is Card In Wallet
    
    @objc(isCardInWallet:)
    func isCardInWallet(command: CDVInvokedUrlCommand) {
        guard let params = command.arguments[0] as? [String: Any],
              let lastFourDigits = params["lastFourDigits"] as? String else {
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
        
        guard let params = command.arguments[0] as? [String: Any] else {
            self.sendError("Invalid parameters")
            return
        }
        
        guard let cardId = params["cardId"] as? String,
              let cardholderName = params["cardholderName"] as? String,
              let lastFourDigits = params["lastFourDigits"] as? String else {
            self.sendError("Missing required parameters")
            return
        }
        
        let localizedDescription = params["localizedDescription"] as? String ?? "Tarjeta"
        let paymentNetwork = params["paymentNetwork"] as? String ?? "mastercard"
        
        guard PKAddPaymentPassViewController.canAddPaymentPass() else {
            self.sendError("Device cannot add payment passes")
            return
        }
        
        guard let configuration = PKAddPaymentPassRequestConfiguration(encryptionScheme: .ECC_V2) else {
            self.sendError("Failed to create configuration")
            return
        }
        
        configuration.cardholderName = cardholderName
        configuration.primaryAccountSuffix = lastFourDigits
        configuration.localizedDescription = localizedDescription
        configuration.paymentNetwork = self.getPaymentNetwork(paymentNetwork)
        
        guard let addPaymentPassVC = PKAddPaymentPassViewController(
            requestConfiguration: configuration,
            delegate: self
        ) else {
            self.sendError("Cannot create Apple Pay view controller")
            return
        }
        
        self.addPaymentPassVC = addPaymentPassVC
        UserDefaults.standard.set(cardId, forKey: "currentCardIdProvisioning")
        
        guard let viewController = self.viewController else {
            self.sendError("No view controller available")
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            viewController.present(addPaymentPassVC, animated: true, completion: nil)
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
        self.pendingCompletionHandler = handler
        
        guard let cardId = UserDefaults.standard.string(forKey: "currentCardIdProvisioning") else {
            return
        }
        
        let certificatesBase64 = certificates.map { $0.base64EncodedString() }
        let nonceBase64 = nonce.base64EncodedString()
        let nonceSignatureBase64 = nonceSignature.base64EncodedString()
        
        let provisioningData: [String: Any] = [
            "cardId": cardId,
            "certificates": certificatesBase64,
            "nonce": nonceBase64,
            "nonceSignature": nonceSignatureBase64
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: provisioningData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        let jsCode = """
        cordova.fireDocumentEvent('onApplePayProvisioningRequest', \(jsonString));
        """
        
        self.commandDelegate.evalJs(jsCode)
    }
    
    // MARK: - Complete Provisioning
    
    @objc(completeProvisioning:)
    func completeProvisioning(command: CDVInvokedUrlCommand) {
        guard let params = command.arguments[0] as? [String: Any],
              let activationDataBase64 = params["activationData"] as? String,
              let encryptedPassDataBase64 = params["encryptedPassData"] as? String,
              let ephemeralPublicKeyBase64 = params["ephemeralPublicKey"] as? String else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Missing data")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        guard let activationData = Data(base64Encoded: activationDataBase64),
              let encryptedPassData = Data(base64Encoded: encryptedPassDataBase64),
              let ephemeralPublicKey = Data(base64Encoded: ephemeralPublicKeyBase64) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid Base64")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        let request = PKAddPaymentPassRequest()
        request.activationData = activationData
        request.encryptedPassData = encryptedPassData
        request.ephemeralPublicKey = ephemeralPublicKey
        
        if let handler = self.pendingCompletionHandler {
            handler(request)
            self.pendingCompletionHandler = nil
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
        controller.dismiss(animated: true) {
            UserDefaults.standard.removeObject(forKey: "currentCardIdProvisioning")
            
            if let error = error {
                self.sendError("Provisioning failed: \(error.localizedDescription)")
            } else if let pass = pass {
                self.sendSuccess([
                    "success": true,
                    "message": "Card added successfully",
                    "passTypeIdentifier": pass.passTypeIdentifier,
                    "serialNumber": pass.serialNumber,
                    "primaryAccountSuffix": pass.primaryAccountNumberSuffix
                ])
            } else {
                self.sendError("User cancelled")
            }
        }
    }
    
    // MARK: - Test Callback
    
    @objc(testCallback:)
    func testCallback(command: CDVInvokedUrlCommand) {
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