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
    },

    /**
     * Verifica si Google Pay está disponible en el dispositivo.
     * El callback de éxito recibe un objeto con:
     *   {
     *     googlePayAvailable: boolean,
     *     hasActiveWallet: boolean,
     *     needsWalletCreation: boolean,
     *     walletId?: string,
     *     statusMessage?: string,
     *     statusCode?: number
     *   }
     * Usa `needsWalletCreation` y el mensaje/número para mostrar el texto adecuado en español.
     * @param {Function} successCallback - Callback de éxito
     * @param {Function} errorCallback - Callback de error
     */
    googleIsAvailable: function (successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'WalletProvisioning', 'googleIsAvailable', []);
    },

    /**
     * Obtiene información de la app (package name y SHA-256)
     * Útil para el registro con Google Pay
     */
    getAppInfo: function (successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'WalletProvisioning', 'getAppInfo', []);
    },

    /**
     * Agrega una tarjeta a Google Pay usando Push Provisioning
     * @param {Object} params - Parámetros de provisioning
     * @param {string} params.opc - Opaque Payment Card (de Pomelo API)
     * @param {string} params.cardholderName - Nombre del tarjetahabiente
     * @param {string} params.last4 - Últimos 4 dígitos de la tarjeta
     * @param {string} params.network - Red de la tarjeta (MASTERCARD, VISA)
     * @param {Object} params.userAddress - Dirección del usuario (opcional)
     * @param {Function} successCallback - Callback de éxito
     * @param {Function} errorCallback - Callback de error
     */
    googlePushProvision: function (params, successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'WalletProvisioning', 'pushProvision', [params]);
    },

    /**
     * Verifica si una tarjeta ya existe en Google Wallet
     * @param {Object} options - { last4: "1234" }
     * @param {Function} successCallback - Callback de éxito
     * @param {Function} errorCallback - Callback de error
     * Retorna: { exists: boolean, last4Searched: string, matchedTokens: array, totalTokensInWallet: number }
     */
    isCardInGoogleWallet: function (options, successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'WalletProvisioning', 'isCardInGoogleWallet', [options]);
    },

    /**
     * Lista todos los tokens en Google Wallet
     * @param {Function} successCallback - Callback de éxito
     * @param {Function} errorCallback - Callback de error
     * Retorna: { tokens: array, count: number }
     */
    listGoogleWalletTokens: function (successCallback, errorCallback) {
        exec(successCallback, errorCallback, 'WalletProvisioning', 'listTokens', []);
    },

};

module.exports = SLMWalletProvisioning;
