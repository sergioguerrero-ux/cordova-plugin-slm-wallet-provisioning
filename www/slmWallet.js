/* global cordova */
var exec = require('cordova/exec');

module.exports = {
    appleCanAdd: function (success, error) {
        exec(success, error, 'SlmWalletProvisioning', 'appleCanAdd', []);
    },
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
