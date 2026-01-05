import Foundation
import PassKit

@objc(SlmWalletProvisioning)
class SlmWalletProvisioning: CDVPlugin, PKAddPaymentPassViewControllerDelegate {

    private var pendingCallbackId: String?

    // cordova.plugins.slmWallet.appleCanAdd(...)
    @objc(appleCanAdd:)
    func appleCanAdd(command: CDVInvokedUrlCommand) {
        let can = PKAddPaymentPassViewController.canAddPaymentPass()
        let payload: [String: Any] = ["ok": true, "canAdd": can]

        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        self.commandDelegate.send(result, callbackId: command.callbackId)
    }

    // cordova.plugins.slmWallet.appleStartAdd({ ... }, ...)
    @objc(appleStartAdd:)
    func appleStartAdd(command: CDVInvokedUrlCommand) {
        self.pendingCallbackId = command.callbackId

        guard let opts = command.arguments.first as? [String: Any] else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "missing_options")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        // Campos típicos (ajustamos a tu backend/Pomelo):
        let cardholderName = (opts["cardholderName"] as? String) ?? ""
        let primaryAccountSuffix = (opts["last4"] as? String) ?? ""
        let localizedDescription = (opts["description"] as? String) ?? "Card"

        // ⚠️ Esto requiere el entitlement de Apple (Issuer / In-App provisioning),
        // si no, no podrás presentar el controller.
        guard let config = PKAddPaymentPassRequestConfiguration(encryptionScheme: .ECC_V2) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "config_failed")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        config.cardholderName = cardholderName
        config.primaryAccountSuffix = primaryAccountSuffix
        config.localizedDescription = localizedDescription

        guard let vc = PKAddPaymentPassViewController(requestConfiguration: config, delegate: self) else {
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: "cannot_create_controller")
            self.commandDelegate.send(result, callbackId: command.callbackId)
            return
        }

        self.viewController.present(vc, animated: true)
    }

    // MARK: - PKAddPaymentPassViewControllerDelegate

    // Aquí Apple te da certificates/nonce/signature y tú se los mandas a tu backend (Pomelo),
    // y luego construyes PKAddPaymentPassRequest con la respuesta.
    func addPaymentPassViewController(_ controller: PKAddPaymentPassViewController,
                                      generateRequestWithCertificateChain certificates: [Data],
                                      nonce: Data,
                                      nonceSignature: Data,
                                      completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void) {

        // TODO:
        // 1) Enviar certificates/nonce/nonceSignature a tu backend
        // 2) Recibir activationData, encryptedPassData, ephemeralPublicKey
        // 3) Crear PKAddPaymentPassRequest y llamar handler(request)

        // Por ahora: si no implementas esto, el flow no completará.
        let request = PKAddPaymentPassRequest()
        handler(request)
    }

    func addPaymentPassViewController(_ controller: PKAddPaymentPassViewController,
                                      didFinishAdding pass: PKPaymentPass?,
                                      error: Error?) {
        controller.dismiss(animated: true)

        guard let cb = self.pendingCallbackId else { return }
        self.pendingCallbackId = nil

        if let error = error {
            let payload: [String: Any] = ["ok": false, "error": error.localizedDescription]
            let result = CDVPluginResult(status: CDVCommandStatus_ERROR, messageAs: payload)
            self.commandDelegate.send(result, callbackId: cb)
            return
        }

        let payload: [String: Any] = ["ok": true, "added": (pass != nil)]
        let result = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: payload)
        self.commandDelegate.send(result, callbackId: cb)
    }
}
