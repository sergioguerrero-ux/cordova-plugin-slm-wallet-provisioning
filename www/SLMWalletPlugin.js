/**
 * SLM Wallet Plugin - JavaScript Interface
 * Expone métodos para Apple Pay y Google Pay
 */

var exec = require('cordova/exec');

var SLMWalletPlugin = {

    /**
     * Verifica si el dispositivo puede agregar tarjetas
     * @returns {Promise<{canAdd: boolean}>}
     */
    canAddPaymentPass: function () {
        return new Promise(function (resolve, reject) {
            exec(resolve, reject, 'SLMWalletPlugin', 'canAddPaymentPass', []);
        });
    },

    /**
     * FASE 1: Inicia el flujo de Apple Pay y devuelve los datos de Apple
     * @param {Object} options - Opciones de configuración
     * @param {string} options.cardId - ID de la tarjeta
     * @param {string} options.holderName - Nombre del tarjetahabiente
     * @param {string} options.last4 - Últimos 4 dígitos
     * @param {string} options.localizedDescription - Descripción de la tarjeta
     * @param {string} [options.encryptionScheme='ECC_V2'] - Esquema de encriptación
     * @returns {Promise<{ok: boolean, certificates: string[], nonce: string, nonceSignature: string}>}
     */
    startAddPaymentPass: function (options) {
        return new Promise(function (resolve, reject) {
            if (!options || typeof options !== 'object') {
                return reject({ error: 'Invalid options object' });
            }
            exec(resolve, reject, 'SLMWalletPlugin', 'startAddPaymentPass', [options]);
        });
    },

    /**
     * FASE 2: Completa el aprovisionamiento con los datos de Pomelo
     * @param {Object} options - Datos de Pomelo
     * @param {string} options.activationData - Activation data en Base64
     * @param {string} options.encryptedPassData - Encrypted pass data en Base64
     * @param {string} options.ephemeralPublicKey - Ephemeral public key en Base64
     * @returns {Promise<{ok: boolean, message: string}>}
     */
    completeAddPaymentPass: function (options) {
        return new Promise(function (resolve, reject) {
            if (!options || typeof options !== 'object') {
                return reject({ error: 'Invalid options object' });
            }
            exec(resolve, reject, 'SLMWalletPlugin', 'completeAddPaymentPass', [options]);
        });
    }
};

module.exports = SLMWalletPlugin;