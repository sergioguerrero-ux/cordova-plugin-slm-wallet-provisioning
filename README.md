# SLM Wallet Provisioning Cordova Plugin

This Cordova plugin exposes the native tokenization flows for Google Play Services Tap & Pay on Android and Apple PassKit in-app provisioning on iOS. It is intended for wallet issuers or tokenization backends that already own the necessary credentials (Tap & Pay issuer ID / PassKit provisioning entitlement).

## Features

- Android: `isReadyToPay()` and `pushTokenize()` via `TapAndPayClient`, with callbacks delivered through Cordova actions.
- iOS: `PKAddPaymentPassViewController` backed by the PassKit issuer provisioning APIs.
- JavaScript bridge: `cordova.plugins.slmWallet` exposes `appleCanAdd`, `appleStartAdd`, `googleIsAvailable` and `googlePushProvision`.

## Installation

Install from your Cordova project root:

```
cordova plugin add /path/to/cordova-plugin-slm-wallet-provisioning
```

Add any required platform-specific entitlements/manifests as described below.

## Usage

```js
const plugin = cordova.plugins.slmWallet;

plugin.googleIsAvailable(res => {
  console.log('Ready to pay?', res.available);
}, err => console.warn(err));

plugin.googlePushProvision({
  cardholderName: 'Juan Perez',
  last4: '4242',
  description: 'SLM card'
}, res => {
  console.log('Provisioning intent result', res);
}, err => {
  console.warn('Provision failed', err);
});
```

The `googlePushProvision` callback fires after the Tap & Pay UI completes; inspect `res.extras` for provider-specific data. For production you still need to call your backend to retrieve activation data, encrypted pass data, and ephemeral keys, and populate the request before completing the flow.

## Android Notes

- Requires `com.google.android.gms:play-services-tapandpay` and `play-services-base`.
- Add the Issuer ID, certification, and backend handshake: `TapAndPayClient.pushTokenize` returns a pending intent that must be completed via an activation data payload provided by your server.
- The plugin checks `TapAndPayClient.isReadyToPay` before starting provisioning.
- Handle the pending intent result in your JS layer to finalize provisioning or surface errors.

## iOS Notes

- Requires the PassKit in-app provisioning entitlement; add it through your Apple Developer portal and Xcode project.
- `appleCanAdd` returns whether the device supports provisioning; `appleStartAdd` presents the `PKAddPaymentPassViewController`.
- You must implement the backend exchange using `PKAddPaymentPassRequestConfiguration` and respond to Apple with `activationData`, `encryptedPassData`, and `ephemeralPublicKey` in `addPaymentPassViewController(_:generateRequestWithCertificateChain:nonce:nonceSignature:completionHandler:)`.

## Contributing

1. Implement the missing server-side handshake for Push Tokenize (activation data) and for PassKit provisioning.
2. Test on real devices/emulators with Google Play Services or Apple Wallet support.
