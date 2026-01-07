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
        
        // ✅ BUSCAR INAPPBROWSER ESPECÍFICAMENTE
        logToJS("   → Buscando InAppBrowser específicamente...")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                self?.logToJS("❌ self is nil", type: "error")
                return
            }
            
            var inAppBrowserVC: UIViewController?
            
            // Función recursiva para buscar InAppBrowser
            func findInAppBrowser(in vc: UIViewController?) -> UIViewController? {
                guard let vc = vc else { return nil }
                
                let vcType = String(describing: type(of: vc))
                self.logToJS("      Chequeando: \(vcType)", type: "info")
                
                // Si es el InAppBrowser, lo encontramos
                if vcType.contains("InAppBrowser") || vcType.contains("IAB") {
                    self.logToJS("      ✅ ENCONTRADO: \(vcType)", type: "success")
                    return vc
                }
                
                // Buscar en presented view controller
                if let presented = vc.presentedViewController {
                    if let found = findInAppBrowser(in: presented) {
                        return found
                    }
                }
                
                // Buscar en child view controllers
                for child in vc.children {
                    if let found = findInAppBrowser(in: child) {
                        return found
                    }
                }
                
                return nil
            }
            
            // ESTRATEGIA 1: Buscar desde self.viewController
            self.logToJS("   → Estrategia 1: Buscando desde self.viewController...", type: "info")
            if let cordovaVC = self.viewController {
                self.logToJS("      Base: \(type(of: cordovaVC))", type: "info")
                inAppBrowserVC = findInAppBrowser(in: cordovaVC)
            } else {
                self.logToJS("      self.viewController es nil", type: "warning")
            }
            
            // ESTRATEGIA 2: Buscar en todas las windows
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
            
            // ESTRATEGIA 3: Si no encontramos InAppBrowser, usar top-most
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
            self.logToJS("   isBeingPresented: \(presentingVC.isBeingPresented)")
            self.logToJS("   isBeingDismissed: \(presentingVC.isBeingDismissed)")
            
            // Verificar si está ocupado
            if presentingVC.isBeingPresented || presentingVC.isBeingDismissed {
                self.logToJS("   ⚠️ View controller ocupado, esperando 0.5s...", type: "warning")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.attemptPresentation(from: presentingVC, vc: addPaymentPassVC)
                }
                return
            }
            
            // Presentar inmediatamente
            self.attemptPresentation(from: presentingVC, vc: addPaymentPassVC)
        }
    }
    
    // MARK: - Attempt Presentation
    
    private func attemptPresentation(from presentingVC: UIViewController, vc: PKAddPaymentPassViewController) {
        logToJS("🎬 PRESENTANDO APPLE WALLET SOBRE INAPPBROWSER...", type: "info")
        logToJS("   Desde: \(type(of: presentingVC))", type: "info")
        
        presentingVC.present(vc, animated: true) { [weak self] in
            self?.logToJS("✅ Completion handler ejecutado", type: "success")
        }
        
        // Verificar a los 0.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let presented = presentingVC.presentedViewController {
                self?.logToJS("✅ 0.5s: \(type(of: presented)) visible", type: "success")
                
                if presented is PKAddPaymentPassViewController {
                    self?.logToJS("✅ ✅ ✅ CONFIRMADO: Apple Wallet visible!", type: "success")
                }
            } else {
                self?.logToJS("❌ 0.5s: No hay presentedViewController", type: "error")
            }
        }
        
        // Verificación final a 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if presentingVC.presentedViewController != nil {
                self?.logToJS("✅ 1.5s: Apple Wallet sigue visible", type: "success")
            } else {
                self?.logToJS("❌ 1.5s: FALLO - No se presentó", type: "error")
                
                // Intentar sin animación como último recurso
                self?.logToJS("   → Reintentando sin animación...", type: "warning")
                presentingVC.present(vc, animated: false, completion: nil)
            }
        }
    }
    
    // MARK: - Generate Request Delegate
    
    // MARK: - Did Finish Delegate

func addPaymentPassViewController(
    _ controller: PKAddPaymentPassViewController,
    didFinishAdding pass: PKPaymentPass?,
    error: Error?
) {
    logToJS("🏁 Apple Wallet delegate didFinishAdding llamado", type: "info")
    
    // Log del estado ANTES de cerrar
    logToJS("   Estado ANTES de dismiss:", type: "info")
    logToJS("   - pass: \(pass != nil ? "existe" : "nil")")
    logToJS("   - error: \(error?.localizedDescription ?? "nil")")
    
    if let error = error {
        logToJS("   ❌ Error detectado: \(error.localizedDescription)", type: "error")
    } else if let pass = pass {
        logToJS("   ✅ Pass agregado: \(pass.primaryAccountNumberSuffix)", type: "success")
    } else {
        logToJS("   ⚠️ Usuario canceló (pass y error son nil)", type: "warning")
    }
    
    // Obtener referencia al presenting view controller ANTES de dismiss
    let presentingVC = controller.presentingViewController
    logToJS("   presentingViewController: \(presentingVC != nil ? String(describing: type(of: presentingVC!)) : "nil")")
    
    logToJS("   → Llamando controller.dismiss()...", type: "info")
    
    controller.dismiss(animated: true) { [weak self] in
        self?.logToJS("   ✅ Dismiss completion ejecutado", type: "success")
        
        // Verificar que el InAppBrowser sigue ahí
        if let presenting = presentingVC {
            self?.logToJS("   → Verificando presentingViewController después de dismiss...", type: "info")
            self?.logToJS("      Tipo: \(type(of: presenting))", type: "info")
            self?.logToJS("      isViewLoaded: \(presenting.isViewLoaded)")
            self?.logToJS("      view.window: \(presenting.view.window != nil ? "existe" : "nil")")
            
            if presenting.view.window != nil {
                self?.logToJS("   ✅ InAppBrowser sigue visible", type: "success")
            } else {
                self?.logToJS("   ❌ InAppBrowser perdió su window!", type: "error")
            }
        }
        
        // Limpiar datos
        UserDefaults.standard.removeObject(forKey: "currentCardIdProvisioning")
        self?.logToJS("   Datos de provisioning limpiados")
        
        // Preparar resultado
        var resultData: [String: Any] = [:]
        var resultMessage = ""
        var isError = false
        
        if let error = error {
            isError = true
            resultMessage = "Provisioning failed: \(error.localizedDescription)"
            resultData = ["error": true, "message": resultMessage]
            self?.logToJS("   📤 Enviando ERROR a webapp: \(resultMessage)", type: "error")
        } else if let pass = pass {
            isError = false
            resultMessage = "Card added successfully"
            resultData = [
                "success": true,
                "message": resultMessage,
                "passTypeIdentifier": pass.passTypeIdentifier,
                "serialNumber": pass.serialNumber,
                "primaryAccountSuffix": pass.primaryAccountNumberSuffix
            ]
            self?.logToJS("   📤 Enviando SUCCESS a webapp", type: "success")
        } else {
            isError = true
            resultMessage = "User cancelled"
            resultData = ["error": true, "message": resultMessage, "cancelled": true]
            self?.logToJS("   📤 Enviando CANCEL a webapp", type: "warning")
        }
        
        // Enviar resultado
        if isError {
            self?.sendError(resultMessage)
        } else {
            self?.sendSuccess(resultData)
        }
        
        self?.logToJS("✅ didFinishAdding COMPLETADO", type: "success")
        
        // Verificación adicional después de un delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.logToJS("   → Verificación 0.5s después de completar...", type: "info")
            
            if let presenting = presentingVC {
                if presenting.view.window != nil {
                    self?.logToJS("   ✅ InAppBrowser confirmado visible 0.5s después", type: "success")
                } else {
                    self?.logToJS("   ❌ InAppBrowser YA NO tiene window 0.5s después!", type: "error")
                    self?.logToJS("   Esto indica que algo lo cerró externamente", type: "error")
                }
            }
        }
    }
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
    logToJS("📤 sendSuccess iniciado", type: "info")
    
    guard let callbackId = self.commandCallback else {
        logToJS("   ⚠️ No hay callbackId", type: "warning")
        return
    }
    
    logToJS("   Enviando resultado SUCCESS al callback \(callbackId)")
    
    let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: data)
    
    // ✅ IMPORTANTE: keepCallback = false para que no se llame múltiples veces
    result?.setKeepCallbackAs(false)
    
    self.commandDelegate.send(result, callbackId: callbackId)
    self.commandCallback = nil
    
    logToJS("   ✅ SUCCESS enviado", type: "success")
}

private func sendError(_ message: String) {
    logToJS("📤 sendError iniciado", type: "info")
    
    guard let callbackId = self.commandCallback else {
        logToJS("   ⚠️ No hay callbackId", type: "warning")
        return
    }
    
    logToJS("   Enviando resultado ERROR al callback \(callbackId)")
    logToJS("   Mensaje: \(message)", type: "error")
    
    let result = CDVPluginResult(
        status: CDVCommandStatus_ERROR,
        messageAs: ["error": true, "message": message]
    )
    
    // ✅ IMPORTANTE: keepCallback = false
    result?.setKeepCallbackAs(false)
    
    self.commandDelegate.send(result, callbackId: callbackId)
    self.commandCallback = nil
    
    logToJS("   ✅ ERROR enviado", type: "success")
}
}