# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Cordova plugin (`cordova-plugin-slm-wallet-provisioning`) that enables push provisioning of payment cards to Apple Wallet and Google Pay. The plugin supports OPC (Opaque Payment Card) tokenization and integrates with both iOS PassKit and Android Tap & Pay APIs.

## Architecture

### Three-Layer Structure

1. **JavaScript Interface** (`www/SLMWalletProvisioning.js`)
   - Exposes methods to Cordova applications via `cordova/exec`
   - Handles platform-agnostic API for both iOS and Android
   - Maps to platform-specific plugin names (`SLMWalletProvisioning` for iOS, `WalletProvisioning` for Android)

2. **iOS Implementation** (`src/ios/SLMWalletProvisioning.swift`)
   - Uses PassKit framework (`PKAddPaymentPassViewController`, `PKPassLibrary`)
   - Implements `PKAddPaymentPassViewControllerDelegate`
   - Handles certificate chain provisioning with async completion handlers
   - Fires custom Cordova events (`onApplePayProvisioningRequest`) for encryption data requests

3. **Android Implementation** (`src/android/SLMWalletProvisioning.java`)
   - Uses Google Play Services Tap & Pay API (`TapAndPayClient`)
   - Handles wallet creation and push tokenization flows
   - Manages activity results for wallet creation and provisioning completion
   - Supports both Visa and Mastercard networks

### Key Architectural Patterns

- **iOS Event-Driven Flow**: The provisioning process uses a delegate pattern where Apple requests encryption data via `addPaymentPassViewController:generateRequestWithCertificateChain:nonce:nonceSignature:completionHandler:`, which triggers a JavaScript event that must be completed with `completeProvisioning()`

- **Android Callback Management**: Uses `pendingCallbackContext` to maintain state across async operations and activity results. The `onActivityResult` method handles both wallet creation (`REQUEST_CODE_CREATE_WALLET`) and push tokenization (`REQUEST_CODE_PUSH_TOKENIZE`)

- **Platform Detection**: JavaScript methods use different plugin names:
  - iOS methods call `'SLMWalletProvisioning'`
  - Android methods call `'WalletProvisioning'`

### Provisioning Workflows

**iOS Apple Wallet:**
1. Check availability with `canAddCard()`
2. Start provisioning with `startProvisioning()` - opens PassKit UI
3. iOS fires `onApplePayProvisioningRequest` event with certificates/nonce
4. App backend encrypts card data and returns it
5. App calls `completeProvisioning()` with encrypted data
6. Delegate callback `addPaymentPassViewController:didFinishAdding:error:` fires on completion

**Android Google Pay:**
1. Check availability with `googleIsAvailable()` - returns wallet status and creation needs
2. Get app registration info with `getAppInfo()` (package name + SHA-256 signature)
3. Push provision with `googlePushProvision()` using OPC from backend
4. Activity result returns success/failure in `onActivityResult()`

## Plugin Configuration

### Android Dependencies

- Requires Google Play Services Tap & Pay SDK 18.7.0
- Custom gradle reference in `tapandpay.gradle` for local SDK bundle at `libs/tapandpay_skd`
- Requires AndroidX enabled
- NFC permissions (optional hardware requirement)

### iOS Entitlements

The plugin automatically configures required entitlements in both Debug and Release plists:
- `com.apple.developer.pass-type-identifiers` with `$(TeamIdentifierPrefix)*`
- `com.apple.developer.payment-pass-provisioning` set to true

### Platform Requirements

- Cordova >= 8.0.0
- cordova-android >= 9.0.0
- cordova-ios >= 6.0.0
- Swift 5.0

## Development Commands

This is a Cordova plugin, not a standalone app. Test it by installing into a Cordova project:

```bash
# Install plugin locally into a Cordova app
cordova plugin add /path/to/cordova-plugin-slm-wallet-provisioning

# Remove and reinstall during development
cordova plugin rm cordova-plugin-slm-wallet-provisioning
cordova plugin add /path/to/cordova-plugin-slm-wallet-provisioning

# Build and run on platforms
cordova build android
cordova run android
cordova build ios
cordova run ios
```

## Key Implementation Details

### Android Status Codes

The Android implementation handles specific Tap & Pay status codes in `getAvailabilityFailureMessage()`:
- `13` = Google Pay unavailable on device
- `15002` / `6002` = No active wallet (needs creation)
- `15009` = App not verified/authorized

### iOS View Controller Presentation

The iOS implementation includes complex logic to find the correct presenting view controller, searching for InAppBrowser instances. This is necessary because Cordova apps often run within InAppBrowser, and presenting PassKit UI requires the correct parent controller.

### Token Management

Both platforms support checking if a card already exists in the wallet:
- iOS: `isCardInWallet()` - searches `PKPassLibrary` by `primaryAccountNumberSuffix`
- Android: `isCardInGoogleWallet()` - searches tokens via `TapAndPayClient.listTokens()` comparing FPAN/DPAN last 4 digits

### Debug Logging

Android implementation includes extensive debug logging with tag `"WalletProvisioning"`. Key methods append debug information to results for troubleshooting provisioning flows.

## File References

- Plugin manifest: `plugin.xml`
- JavaScript API: `www/SLMWalletProvisioning.js`
- iOS implementation: `src/ios/SLMWalletProvisioning.swift`, `src/ios/SLMWalletProvisioning.m` (bridge header)
- Android implementation: `src/android/SLMWalletProvisioning.java`
- Android gradle config: `tapandpay.gradle`
