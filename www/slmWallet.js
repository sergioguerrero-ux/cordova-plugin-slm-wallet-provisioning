/* global cordova */
var exec = require('cordova/exec');

module.exports = {
    appleCanAdd: function (success, error) {
        exec(success, error, 'SlmWalletProvisioning', 'appleCanAdd', []);
    },
    /**
     * opts:
     *   cardholderName, last4, description,
     *   cardId                          // required
     *   tokenizationEndpoint            // overrides https://api.pomelo.la/token-provisioning/mastercard/apple-pay
     *   tokenizationAuthorization       // value for Authorization header
     *   tokenizationAuthToken,          // alternative: token + optional tokenizationAuthScheme (default: "Bearer")
     *   tokenizationHeaders             // additional headers
     *   userId                          // optional Pomelo user_id
     * See https://developers.pomelo.la/api-reference/cards/Tokenization/mastercard#aprovisionar-mastercard-en-apple-pay
     */
    appleStartAdd: function (opts, success, error) {
        exec(success, error, 'SlmWalletProvisioning', 'appleStartAdd', [opts || {}]);
    },

    googleIsAvailable: function (success, error) {
        exec(success, error, 'SlmWalletProvisioning', 'googleIsAvailable', []);
    },
    googlePushProvision: function (opts, success, error) {
        exec(success, error, 'SlmWalletProvisioning', 'googlePushProvision', [opts || {}]);
    }
};
