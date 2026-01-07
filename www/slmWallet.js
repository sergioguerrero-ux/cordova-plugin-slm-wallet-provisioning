/* global cordova */
var exec = require('cordova/exec');

module.exports = {
    appleCanAdd: function (success, error) {
        exec(success, error, 'SLMWallet', 'appleCanAdd', []);
    },
    appleStartAdd: function (opts, success, error) {
        exec(success, error, 'SLMWallet', 'appleStartAdd', [opts || {}]);
    },
    googleIsAvailable: function (success, error) {
        exec(success, error, 'SLMWallet', 'googleIsAvailable', []);
    },
    googlePushProvision: function (opts, success, error) {
        exec(success, error, 'SLMWallet', 'googlePushProvision', [opts || {}]);
    }
};