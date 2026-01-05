# SLM Wallet Provisioning Cordova Plugin

This Cordova plugin exposes the native tokenization flows for the Google Pay / Wallet API on Android and Apple PassKit in-app provisioning on iOS. It is intended for wallet issuers or tokenization backends that already own the necessary credentials (Gateway tokenization access, PassKit provisioning entitlement).

## Features

- Android: `PaymentsClient.isReadyToPay()` and `PaymentDataRequest` flows via Google Pay, with callbacks delivered through Cordova actions.
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
  gatewayName: 'example',
  gatewayMerchantId: 'your-merchant-id',
  totalPrice: '10.00',
  currencyCode: 'USD',
  countryCode: 'US',
  merchantName: 'SLM Wallet',
  environment: 'TEST'
}, res => {
  console.log('Payment data', res.paymentData);
}, err => {
  console.warn('Provision failed', err);
});
```

The `googlePushProvision` callback fires when the Google Pay UI completes. You receive the full `PaymentData` JSON (tokenization payload) in `res.paymentData`; send that payload to your gateway backend so it can create a tokenized card or payment method.

## Android Notes

- Requires `com.google.android.gms:play-services-wallet` and `play-services-base`.
- Provide the gateway tokenization information your backend owns (`gatewayName` + `gatewayMerchantId`). `googlePushProvision` builds a `PaymentDataRequest`, presents Google Pay, and returns the `PaymentData` token to your JS layer.
- The plugin checks `PaymentsClient.isReadyToPay` before starting the flow.

## iOS Notes

- Requires the PassKit in-app provisioning entitlement; add it through your Apple Developer portal and Xcode project.
- `appleCanAdd` returns whether the device supports provisioning; `appleStartAdd` presents the `PKAddPaymentPassViewController`.
- You must implement the backend exchange using `PKAddPaymentPassRequestConfiguration` and respond to Apple with `activationData`, `encryptedPassData`, and `ephemeralPublicKey` in `addPaymentPassViewController(_:generateRequestWithCertificateChain:nonce:nonceSignature:completionHandler:)`.

## Contributing

1. Implement the missing server-side handshake for your payment gateway (provide `gatewayName` + `gatewayMerchantId`) and for PassKit provisioning.
2. Test on real devices/emulators with Google Pay / Apple Wallet support to verify the flows and inspect the returned tokens.
