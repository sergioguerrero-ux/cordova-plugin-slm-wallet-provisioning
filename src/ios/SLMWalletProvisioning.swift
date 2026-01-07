import Foundation
import PassKit

@objc(SLMWalletProvisioning)
class SLMWalletProvisioning: CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var commandCallback: String?
    private var addPaymentPassVC: PKAddPaymentPassViewController?
    private var pendingCompletionHandler: ((PKAddPaymentPassRequest) -> Void)?
    
    private func logToJS(_ message: String, type: String = "info") {
        print("[SWIFT] \(message)")
        
        let escapedMessage = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
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
    
    @objc(canAddCard:)
    func canAddCard(command: CDVInvokedUrlCommand) {
        logToJS("🔍 canAddCard iniciado")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var result: [String: Any] = [:]
            let canAddPass = PKAddPaymentPassViewController.canAddPaymentPass()
            let passLibrary = PKPassLibrary()
            let paymentPasses = passLibrary.passes(of: .payment)
            let hasCards = !paymentPasses.isEmpty
            let libraryAvailable = PKPassLibrary.isPassLibraryAvailable()
            
            result["canAdd"] = canAddPass
            result["hasCardsInWallet"] = hasCards
            result["deviceSupportsWallet"] = libraryAvailable
            result["message"] = canAddPass ? "Device supports Apple Wallet provisioning" : "Device does not support Apple Wallet"
            
            DispatchQueue.main.async {
                let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: result)
                self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
                self.logToJS("✅ canAddCard COMPLETADO", type: "success")
            }
        }
    }
    
    @objc(isCardInWallet:)
    func isCardInWallet(command: CDVInvokedUrlCommand) {
        logToJS("🔍 isCardInWallet iniciado")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            guard let params = command.arguments[0] as? [String: Any],
                  let lastFourDigits = params["lastFourDigits"] as? String else {
                DispatchQueue.main.async {
                    let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Missing lastFourDigits")
                    self.commandDelegate.send(result, callbackId: command.callbackId)
                }
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
                self.logToJS("✅ isCardInWallet COMPLETADO", type: "success")
            }
        }
    }
    
    @objc(startProvisioning:)
    func startProvisioning(command: CDVInvokedUrlCommand) {
        self.commandCallback = command.callbackId
        logToJS("🚀 startProvisioning iniciado", type: "info")
        
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
        
        logToJS("   → Buscando InAppBrowser...")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var inAppBrowserVC: UIViewController?
            
            func findInAppBrowser(in vc: UIViewController?) -> UIViewController? {
                guard let vc = vc else { return nil }
                let vcType = String(describing: type(of: vc))
                
                if vcType.contains("InAppBrowser") || vcType.contains("IAB") {
                    self.logToJS("      ✅ ENCONTRADO: \(vcType)", type: "success")
                    return vc
                }
                
                if let presented = vc.presentedViewController {
                    if let found = findInAppBrowser(in: presented) {
                        return found
                    }
                }
                
                for child in vc.children {
                    if let found = findInAppBrowser(in: child) {
                        return found
                    }
                }
                
                return nil
            }
            
            if let cordovaVC = self.viewController {
                inAppBrowserVC = findInAppBrowser(in: cordovaVC)
            }
            
            if inAppBrowserVC == nil {
                for window in UIApplication.shared.windows {
                    if let rootVC = window.rootViewController {
                        if let found = findInAppBrowser(in: rootVC) {
                            inAppBrowserVC = found
                            break
                        }
                    }
                }
            }
            
            if inAppBrowserVC == nil {
                var topVC = self.viewController ?? UIApplication.shared.keyWindow?.rootViewController
                if let vc = topVC {
                    var current = vc
                    while let presented = current.presentedViewController {
                        current = presented
                    }
                    inAppBrowserVC = current
                }
            }
            
            guard let presentingVC = inAppBrowserVC else {
                self.sendError("No view controller available")
                return
            }
            
            self.logToJS("✅ VC: \(type(of: presentingVC))", type: "success")
            
            if presentingVC.isBeingPresented || presentingVC.isBeingDismissed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.attemptPresentation(from: presentingVC, vc: addPaymentPassVC)
                }
                return
            }
            
            self.attemptPresentation(from: presentingVC, vc: addPaymentPassVC)
        }
    }
    
    private func attemptPresentation(from presentingVC: UIViewController, vc: PKAddPaymentPassViewController) {
        logToJS("🎬 PRESENTANDO APPLE WALLET...", type: "info")
        
        presentingVC.present(vc, animated: true) { [weak self] in
            self?.logToJS("✅ Presented", type: "success")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if presentingVC.presentedViewController is PKAddPaymentPassViewController {
                self?.logToJS("✅ ✅ ✅ APPLE WALLET VISIBLE!", type: "success")
            }
        }
    }
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        generateRequestWithCertificateChain certificates: [Data],
        nonce: Data,
        nonceSignature: Data,
        completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void
    ) {
        logToJS("📱 Apple solicitó datos!", type: "info")
        self.pendingCompletionHandler = handler
        
        guard let cardId = UserDefaults.standard.string(forKey: "currentCardIdProvisioning") else {
            return
        }
        
        let provisioningData: [String: Any] = [
            "cardId": cardId,
            "certificates": certificates.map { $0.base64EncodedString() },
            "nonce": nonce.base64EncodedString(),
            "nonceSignature": nonceSignature.base64EncodedString()
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: provisioningData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        let jsCode = """
        cordova.fireDocumentEvent('onApplePayProvisioningRequest', \(jsonString));
        """
        
        self.commandDelegate.evalJs(jsCode)
        logToJS("✅ Evento enviado", type: "success")
    }
    
    @objc(completeProvisioning:)
    func completeProvisioning(command: CDVInvokedUrlCommand) {
        logToJS("📥 Completando provisioning...")
        
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
            logToJS("✅ Enviado a Apple", type: "success")
        }
        
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Data sent")
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        didFinishAdding pass: PKPaymentPass?,
        error: Error?
    ) {
        logToJS("🏁 Apple Wallet finalizó", type: "info")
        logToJS("   pass: \(pass != nil ? "existe" : "nil")")
        logToJS("   error: \(error != nil ? error!.localizedDescription : "nil")")
        
        if let nsError = error as NSError? {
            logToJS("   error.domain: \(nsError.domain)")
            logToJS("   error.code: \(nsError.code)")
        }
        
        let presentingVC = controller.presentingViewController
        logToJS("   presentingVC: \(presentingVC != nil ? String(describing: type(of: presentingVC!)) : "nil")")
        logToJS("   → Dismiss...", type: "info")
        
        controller.dismiss(animated: true) { [weak self] in
            self?.logToJS("   ✅ Dismiss completado", type: "success")
            
            if let presenting = presentingVC {
                if presenting.view.window != nil {
                    self?.logToJS("   ✅ InAppBrowser visible", type: "success")
                } else {
                    self?.logToJS("   ❌ InAppBrowser perdió window", type: "error")
                }
            }
            
            UserDefaults.standard.removeObject(forKey: "currentCardIdProvisioning")
            
            if let error = error {
                let msg = "Failed: \(error.localizedDescription)"
                self?.logToJS("   📤 ANTES sendError", type: "error")
                self?.sendError(msg)
                self?.logToJS("   📤 DESPUÉS sendError", type: "error")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let presenting = presentingVC {
                        if presenting.view.window != nil {
                            self?.logToJS("   ✅ 0.3s: InAppBrowser SIGUE", type: "success")
                        } else {
                            self?.logToJS("   ❌ 0.3s: InAppBrowser DESAPARECIÓ", type: "error")
                            self?.logToJS("   ⚠️ JS lo cerró!", type: "error")
                        }
                    }
                }
            } else if let pass = pass {
                self?.sendSuccess([
                    "success": true,
                    "message": "Card added",
                    "passTypeIdentifier": pass.passTypeIdentifier,
                    "serialNumber": pass.serialNumber,
                    "primaryAccountSuffix": pass.primaryAccountNumberSuffix
                ])
            } else {
                self?.sendError("User cancelled")
            }
        }
    }
    
    @objc(testCallback:)
    func testCallback(command: CDVInvokedUrlCommand) {
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["test": "success"])
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    
    private func getPaymentNetwork(_ network: String) -> PKPaymentNetwork {
        switch network.lowercased() {
        case "visa": return .visa
        case "mastercard", "masterCard": return .masterCard
        case "amex", "americanexpress": return .amex
        case "discover": return .discover
        default: return .masterCard
        }
    }
    
    private func sendSuccess(_ data: [String: Any]) {
        guard let callbackId = self.commandCallback else { return }
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: data)
        result?.setKeepCallbackAs(false)
        self.commandDelegate.send(result, callbackId: callbackId)
        self.commandCallback = nil
    }
    
    private func sendError(_ message: String) {
        guard let callbackId = self.commandCallback else { return }
        let result = CDVPluginResult(
            status: CDVCommandStatus_ERROR,
            messageAs: ["error": true, "message": message]
        )
        result?.setKeepCallbackAs(false)
        self.commandDelegate.send(result, callbackId: callbackId)
        self.commandCallback = nil
    }
}