import Foundation
import PassKit

@objc(SLMWalletProvisioning)
class SLMWalletProvisioning: CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var commandCallback: String?
    private var addPaymentPassVC: PKAddPaymentPassViewController?
    private var pendingCompletionHandler: ((PKAddPaymentPassRequest) -> Void)?
    
    // ✅ Log a JavaScript sin bloquear
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
    
    // MARK: - Can Add Card
    
    @objc(canAddCard:)
    func canAddCard(command: CDVInvokedUrlCommand) {
        logToJS("🔍 canAddCard iniciado")
        
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
        
        logToJS("   → Buscando InAppBrowser específicamente...")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                self?.logToJS("❌ self is nil", type: "error")
                return
            }
            
            var inAppBrowserVC: UIViewController?
            
            func findInAppBrowser(in vc: UIViewController?) -> UIViewController? {
                guard let vc = vc else { return nil }
                
                let vcType = String(describing: type(of: vc))
                self.logToJS("      Chequeando: \(vcType)", type: "info")
                
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
            
            self.logToJS("   → Estrategia 1: Buscando desde self.viewController...", type: "info")
            if let cordovaVC = self.viewController {
                self.logToJS("      Base: \(type(of: cordovaVC))", type: "info")
                inAppBrowserVC = findInAppBrowser(in: cordovaVC)
            } else {
                self.logToJS("      self.viewController es nil", type: "warning")
            }
            
            if inAppBrowserVC == nil {
                self.logToJS("   → Estrategia 2: Buscando en windows...", type: "info")
                
                for (index, window) in UIApplication.shared.windows.enumerated() {
                    self.logToJS("      Window \(index): \(type(of: window))", type: "info")
                    if let rootVC = window.rootViewController {
                        if let found = findInAppBrowser(in: rootVC) {
                            inAppBrowserVC = found
                            self.logToJS("      ✅ Encontrado en window \(index)", type: "success")
                            break
                        }
                    }
                }
            }
            
            if inAppBrowserVC == nil {
                self.logToJS("   ⚠️ InAppBrowser no encontrado, usando top-most...", type: "warning")
                
                var topVC = self.viewController ?? UIApplication.shared.keyWindow?.rootViewController
                
                if let vc = topVC {
                    var current = vc
                    var levels = 0
                    while let presented = current.presentedViewController {
                        levels += 1
                        current = presented
                    }
                    inAppBrowserVC = current
                    self.logToJS("      Usando: \(type(of: current)) (subió \(levels) niveles)", type: "info")
                }
            }
            
            guard let presentingVC = inAppBrowserVC else {
                self.logToJS("❌ No se encontró view controller", type: "error")
                self.sendError("No view controller available")
                return
            }
            
            self.logToJS("✅ View controller seleccionado: \(type(of: presentingVC))", type: "success")
            self.logToJS("   isViewLoaded: \(presentingVC.isViewLoaded)")
            self.logToJS("   view.window: \(presentingVC.view.window != nil ? "existe" : "nil")")
            
            if presentingVC.isBeingPresented || presentingVC.isBeingDismissed {
                self.logToJS("   ⚠️ View controller ocupado, esperando...", type: "warning")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.attemptPresentation(from: presentingVC, vc: addPaymentPassVC)
                }
                return
            }
            
            self.attemptPresentation(from: presentingVC, vc: addPaymentPassVC)
        }
    }
    
    // MARK: - Attempt Presentation
    
    private func attemptPresentation(from presentingVC: UIViewController, vc: PKAddPaymentPassViewController) {
        logToJS("🎬 PRESENTANDO APPLE WALLET...", type: "info")
        
        presentingVC.present(vc, animated: true) { [weak self] in
            self?.logToJS("✅ Completion handler ejecutado", type: "success")
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let presented = presentingVC.presentedViewController {
                self?.logToJS("✅ 0.5s: \(type(of: presented)) visible", type: "success")
                
                if presented is PKAddPaymentPassViewController {
                    self?.logToJS("✅ ✅ ✅ APPLE WALLET VISIBLE!", type: "success")
                }
            } else {
                self?.logToJS("❌ 0.5s: No presentedViewController", type: "error")
            }
        }
    }
    
    // MARK: - Generate Request Delegate
    
    func addPaymentPassViewController(
    _ controller: PKAddPaymentPassViewController,
    didFinishAdding pass: PKPaymentPass?,
    error: Error?
) {
    logToJS("🏁 Apple Wallet finalizó", type: "info")
    logToJS("   pass: \(pass != nil ? "existe" : "nil")")
    logToJS("   error: \(error != nil ? error!.localizedDescription : "nil")")
    
    // Log del NSError para ver el código exacto
    if let nsError = error as NSError? {
        logToJS("   error.domain: \(nsError.domain)")
        logToJS("   error.code: \(nsError.code)")
        logToJS("   error.userInfo: \(nsError.userInfo)")
    }
    
    let presentingVC = controller.presentingViewController
    logToJS("   presentingVC: \(presentingVC != nil ? String(describing: type(of: presentingVC!)) : "nil")")
    
    logToJS("   → Iniciando dismiss...", type: "info")
    
    controller.dismiss(animated: true) { [weak self] in
        self?.logToJS("   ✅ Dismiss animation completado", type: "success")
        
        // Verificación inmediata
        if let presenting = presentingVC {
            self?.logToJS("   → Verificando InAppBrowser...", type: "info")
            self?.logToJS("      Tipo: \(type(of: presenting))")
            self?.logToJS("      isViewLoaded: \(presenting.isViewLoaded)")
            self?.logToJS("      view.window: \(presenting.view.window != nil ? "existe" : "nil")")
            self?.logToJS("      view.superview: \(presenting.view.superview != nil ? "existe" : "nil")")
            
            if presenting.view.window != nil {
                self?.logToJS("   ✅ InAppBrowser CONFIRMADO visible", type: "success")
            } else {
                self?.logToJS("   ❌ InAppBrowser perdió window!", type: "error")
            }
        } else {
            self?.logToJS("   ❌ presentingVC es nil", type: "error")
        }
        
        // Limpiar
        UserDefaults.standard.removeObject(forKey: "currentCardIdProvisioning")
        self?.logToJS("   Datos limpiados")
        
        // Preparar resultado
        var resultMessage = ""
        
        if let error = error {
            resultMessage = "Provisioning failed: \(error.localizedDescription)"
            self?.logToJS("   📤 ANTES de sendError: \(resultMessage)", type: "error")
            self?.sendError(resultMessage)
            self?.logToJS("   📤 DESPUÉS de sendError", type: "error")
            
            // Verificar de nuevo después de sendError
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let presenting = presentingVC {
                    if presenting.view.window != nil {
                        self?.logToJS("   ✅ 0.3s después de sendError: InAppBrowser SIGUE visible", type: "success")
                    } else {
                        self?.logToJS("   ❌ 0.3s después de sendError: InAppBrowser DESAPARECIÓ", type: "error")
                        self?.logToJS("   ⚠️ Algo en JavaScript cerró el InAppBrowser!", type: "error")
                    }
                }
            }
            
        } else if let pass = pass {
            resultMessage = "Card added successfully"
            self?.logToJS("   📤 Enviando SUCCESS", type: "success")
            self?.sendSuccess([
                "success": true,
                "message": resultMessage,
                "passTypeIdentifier": pass.passTypeIdentifier,
                "serialNumber": pass.serialNumber,
                "primaryAccountSuffix": pass.primaryAccountNumberSuffix
            ])
        } else {
            resultMessage = "User cancelled"
            self?.logToJS("   📤 Enviando CANCEL", type: "warning")
            self?.sendError(resultMessage)
        }
        
        self?.logToJS("✅ didFinishAdding COMPLETADO", type: "success")
    }
}
    
    // MARK: - Complete Provisioning
    
    @objc(completeProvisioning:)
    func completeProvisioning(command: CDVInvokedUrlCommand) {
        logToJS("📥 Completando provisioning...")
        
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
            logToJS("❌ Base64 inválido", type: "error")
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid Base64")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        logToJS("✅ Datos OK")
        
        let request = PKAddPaymentPassRequest()
        request.activationData = activationData
        request.encryptedPassData = encryptedPassData
        request.ephemeralPublicKey = ephemeralPublicKey
        
        if let handler = self.pendingCompletionHandler {
            logToJS("📤 Enviando a Apple...", type: "info")
            handler(request)
            self.pendingCompletionHandler = nil
            logToJS("✅ Enviado", type: "success")
        } else {
            logToJS("❌ No handler", type: "error")
        }
        
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: "Data sent")
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    
    // MARK: - Did Finish Delegate (ÚNICA VERSIÓN)
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        didFinishAdding pass: PKPaymentPass?,
        error: Error?
    ) {
        logToJS("🏁 Apple Wallet finalizó", type: "info")
        
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
                self?.logToJS("❌ Error: \(error.localizedDescription)", type: "error")
                self?.sendError("Failed: \(error.localizedDescription)")
            } else if let pass = pass {
                self?.logToJS("🎉 Tarjeta agregada!", type: "success")
                self?.sendSuccess([
                    "success": true,
                    "message": "Card added",
                    "passTypeIdentifier": pass.passTypeIdentifier,
                    "serialNumber": pass.serialNumber,
                    "primaryAccountSuffix": pass.primaryAccountNumberSuffix
                ])
            } else {
                self?.logToJS("⚠️ Cancelado", type: "warning")
                self?.sendError("User cancelled")
            }
        }
    }
    
    // MARK: - Test Callback
    
    @objc(testCallback:)
    func testCallback(command: CDVInvokedUrlCommand) {
        logToJS("🧪 Test", type: "success")
        let result = CDVPluginResult(
            status: CDVCommandStatus_OK,
            messageAs: ["test": "success"]
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