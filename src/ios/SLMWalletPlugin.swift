import Foundation
import PassKit

@objc(SLMWalletPlugin) class SLMWalletPlugin : CDVPlugin, PKAddPaymentPassViewControllerDelegate {
    
    private var currentCallbackId: String?
    private var completionHandlerForGenerate: ((PKAddPaymentPassRequest) -> Void)?
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
    
    @objc(canAddPaymentPass:)
    func canAddPaymentPass(_ command: CDVInvokedUrlCommand) {
        var pluginResult: CDVPluginResult
        
        guard PKAddPaymentPassViewController.canAddPaymentPass() else {
            pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["canAdd": false])
            self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
            return
        }
        
        pluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["canAdd": true])
        self.commandDelegate.send(pluginResult, callbackId: command.callbackId)
    }
    
    // FASE 1: Iniciar el flujo y devolver los datos de Apple
    @objc(startAddPaymentPass:)
    func startAddPaymentPass(_ command: CDVInvokedUrlCommand) {
        guard let opts = command.arguments.first as? [String: Any] else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid parameters")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        guard PKAddPaymentPassViewController.canAddPaymentPass() else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Device does not support adding payment passes")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        self.currentCallbackId = command.callbackId
        
        // Extraer parámetros
        let cardholderName = opts["holderName"] as? String ?? opts["cardholderName"] as? String ?? ""
        let last4 = opts["last4"] as? String ?? ""
        let description = opts["localizedDescription"] as? String ?? opts["description"] as? String ?? "Card"
        let cardId = opts["cardId"] as? String ?? opts["card_id"] as? String ?? ""
        let encryptionScheme = opts["encryptionScheme"] as? String ?? "ECC_V2"
        
        // Configurar PKAddPaymentPassRequestConfiguration
        var scheme: PKEncryptionScheme = .ECC_V2
        if encryptionScheme == "RSA_V2" {
            scheme = .RSA_V2
        }
        
        guard let configuration = PKAddPaymentPassRequestConfiguration(encryptionScheme: scheme) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to create payment pass configuration")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            self.currentCallbackId = nil
            return
        }
        
        configuration.cardholderName = cardholderName
        configuration.primaryAccountSuffix = last4
        configuration.localizedDescription = description
        configuration.primaryAccountIdentifier = cardId
        
        // Configurar primaryAccountNumberSuffix si existe
        if let pan4 = opts["primaryAccountNumberSuffix"] as? String, !pan4.isEmpty {
            configuration.primaryAccountSuffix = pan4
        }
        
        // Crear y presentar el view controller
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
    
    // FASE 2: Completar el aprovisionamiento con los datos de Pomelo
    @objc(completeAddPaymentPass:)
    func completeAddPaymentPass(_ command: CDVInvokedUrlCommand) {
        guard let opts = command.arguments.first as? [String: Any] else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Invalid parameters")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        guard let handler = self.completionHandlerForGenerate else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "No completion handler available. Did you call startAddPaymentPass first?")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        // Extraer datos de Pomelo (deben venir en Base64)
        guard let activationDataBase64 = opts["activationData"] as? String ?? opts["activation_data"] as? String,
              let encryptedPassDataBase64 = opts["encryptedPassData"] as? String ?? opts["encrypted_pass_data"] as? String,
              let ephemeralPublicKeyBase64 = opts["ephemeralPublicKey"] as? String ?? opts["ephemeral_public_key"] as? String else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Missing required Pomelo data: activationData, encryptedPassData, or ephemeralPublicKey")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        // Decodificar de Base64
        guard let activationData = Data(base64Encoded: activationDataBase64),
              let encryptedPassData = Data(base64Encoded: encryptedPassDataBase64),
              let ephemeralPublicKey = Data(base64Encoded: ephemeralPublicKeyBase64) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "Failed to decode base64 data from Pomelo")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }
        
        // Construir PKAddPaymentPassRequest
        let passRequest = PKAddPaymentPassRequest()
        passRequest.activationData = activationData
        passRequest.encryptedPassData = encryptedPassData
        passRequest.ephemeralPublicKey = ephemeralPublicKey
        
        // Llamar al completion handler de Apple
        handler(passRequest)
        
        // Limpiar el handler
        self.completionHandlerForGenerate = nil
        
        // Enviar respuesta de éxito
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: ["ok": true, "message": "Provisioning data sent to Apple"])
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }
    
    // MARK: - PKAddPaymentPassViewControllerDelegate
    
    func addPaymentPassViewController(
        _ controller: PKAddPaymentPassViewController,
        generateRequestWithCertificateChain certificates: [Data],
        nonce: Data,
        nonceSignature: Data,
        completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void
    ) {
        // Guardar el completion handler para usarlo después
        self.completionHandlerForGenerate = handler
        
        guard let callbackId = self.currentCallbackId else {
            print("No callback ID available")
            return
        }
        
        // Convertir a Base64
        let certificatesBase64 = certificates.map { $0.base64EncodedString() }
        let nonceBase64 = nonce.base64EncodedString()
        let nonceSignatureBase64 = nonceSignature.base64EncodedString()
        
        // Devolver los datos a JavaScript para que haga la llamada a Pomelo
        let responseData: [String: Any] = [
            "ok": true,
            "certificates": certificatesBase64,
            "nonce": nonceBase64,
            "nonceSignature": nonceSignatureBase64,
            "certificatesCount": certificates.count
        ]
        
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: responseData)
        result?.keepCallback = true // Importante: mantener el callback activo
        self.commandDelegate.send(result, callbackId: callbackId)
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
                result = CDVPluginResult(
                    status: CDVCommandStatus_ERROR,
                    messageAs: ["error": error.localizedDescription, "added": false]
                )
            } else if let pass = pass {
                let passInfo: [String: Any] = [
                    "added": true,
                    "serialNumber": pass.serialNumber,
                    "passTypeIdentifier": pass.passTypeIdentifier,
                    "deviceAccountIdentifier": pass.deviceAccountIdentifier,
                    "deviceAccountNumberSuffix": pass.deviceAccountNumberSuffix
                ]
                result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: passInfo)
                
                // Disparar evento personalizado
                self.evaluateJS("""
                    window.dispatchEvent(new CustomEvent('slm.appleWallet.finished', {
                        detail: \(self.jsonString(from: passInfo))
                    }));
                """)
            } else {
                result = CDVPluginResult(
                    status: CDVCommandStatus_ERROR,
                    messageAs: ["error": "User cancelled", "added": false]
                )
            }
            
            self.commandDelegate.send(result, callbackId: callbackId)
            self.currentCallbackId = nil
            self.addPaymentPassVC = nil
            self.completionHandlerForGenerate = nil
        }
    }
    
    // MARK: - Helper
    
    private func jsonString(from dictionary: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}