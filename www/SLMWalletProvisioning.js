var exec = require('cordova/exec');

var SLMWalletProvisioning = {

    /**
     * Verifica si el dispositivo puede agregar tarjetas a Apple Wallet
     */
    canAddCard: function (successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'SLMWalletProvisioning', 'canAddCard', []);
    },

    /**
     * Verifica si una tarjeta ya existe en Apple Wallet
     * @param {Object} options - { lastFourDigits: "1234" }
     */
    isCardInWallet: function (options, successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'SLMWalletProvisioning', 'isCardInWallet', [options]);
    },

    /**
     * Inicia el proceso de provisioning
     * @param {Object} cardData - Datos de la tarjeta
     * @param {Function} onDataRequest - Callback cuando Apple solicita datos encriptados
     * @param {Function} successCallback - Callback de éxito
     * @param {Function} errorCallback - Callback de error
     */
    startProvisioning: function (cardData, onDataRequest, successCallback, errorCallback) {
        // Registrar listener para solicitud de datos
        document.addEventListener('onProvisioningDataRequest', function (event) {
            onDataRequest(event);
        }, false);

        exec(successCallback, errorCallback, 'SLMWalletProvisioning', 'startProvisioning', [cardData]);
    },

    /**
     * Completa el provisioning con datos del servidor
     * @param {Object} provisioningData - Datos encriptados del servidor
     */
    completeProvisioning: function (provisioningData, successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'SLMWalletProvisioning', 'completeProvisioning', [provisioningData]);
    },
    /**
     * TEST: Verifica que los callbacks funcionen
     */
    testCallback: function (successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'SLMWalletProvisioning', 'testCallback', []);
    }
};

module.exports = SLMWalletProvisioning;