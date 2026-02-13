package com.slm.wallet;

import android.app.Activity;
import android.content.Intent;
import android.util.Log;

import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.tapandpay.TapAndPay;
import com.google.android.gms.tapandpay.TapAndPayClient;
import com.google.android.gms.tapandpay.TapAndPayStatusCodes;
import com.google.android.gms.tapandpay.issuer.PushTokenizeRequest;
import com.google.android.gms.tapandpay.issuer.TokenInfo;
import com.google.android.gms.tapandpay.issuer.UserAddress;

import org.apache.cordova.CallbackContext;

import java.util.List;
import org.apache.cordova.CordovaPlugin;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public class SLMWalletProvisioning extends CordovaPlugin {

    private static final String TAG = "WalletProvisioning";
    private static final int REQUEST_CODE_CREATE_WALLET = 4;
    private static final int REQUEST_CODE_PUSH_TOKENIZE = 5;
    private TapAndPayClient tapAndPayClient;
    private CallbackContext pendingCallbackContext;

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        Log.d(TAG, "Execute action: " + action);

        if (tapAndPayClient == null) {
            tapAndPayClient = TapAndPay.getClient(cordova.getActivity());
        }

        if ("googleIsAvailable".equals(action)) {
            checkGooglePayAvailability(callbackContext);
            return true;
        }

        if ("getAppInfo".equals(action)) {
            getAppInfo(callbackContext);
            return true;
        }

        if ("pushProvision".equals(action)) {
            JSONObject params = args.optJSONObject(0);
            if (params == null) {
                callbackContext.error("Se requieren parámetros para pushProvision");
                return true;
            }
            pushProvision(params, callbackContext);
            return true;
        }

        if ("isCardInGoogleWallet".equals(action)) {
            JSONObject params = args.optJSONObject(0);
            String last4 = params != null ? params.optString("last4", "") : "";

            if (last4.isEmpty()) {
                callbackContext.error("last4 es requerido");
                return true;
            }

            isCardInGoogleWallet(last4, callbackContext);
            return true;
        }

        if ("listTokens".equals(action)) {
            listAllTokens(callbackContext);
            return true;
        }

        return false;
    }

    private void getAppInfo(CallbackContext callbackContext) {
        try {
            String packageName = cordova.getActivity().getPackageName();
            String sha256 = "No disponible";

            try {
                android.content.pm.PackageInfo packageInfo = cordova.getActivity()
                    .getPackageManager()
                    .getPackageInfo(packageName, android.content.pm.PackageManager.GET_SIGNATURES);

                for (android.content.pm.Signature signature : packageInfo.signatures) {
                    java.security.MessageDigest md = java.security.MessageDigest.getInstance("SHA-256");
                    md.update(signature.toByteArray());
                    byte[] digest = md.digest();
                    StringBuilder hexString = new StringBuilder();
                    for (byte b : digest) {
                        String hex = Integer.toHexString(0xff & b);
                        if (hex.length() == 1) hexString.append('0');
                        hexString.append(hex);
                    }
                    sha256 = hexString.toString().toUpperCase();
                }
            } catch (Exception e) {
                sha256 = "Error: " + e.getMessage();
            }

            JSONObject result = new JSONObject();
            result.put("packageName", packageName);
            result.put("sha256", sha256);
            callbackContext.success(result);
        } catch (JSONException e) {
            callbackContext.error("Error: " + e.getMessage());
        }
    }

    private void pushProvision(JSONObject params, CallbackContext callbackContext) {
        try {
            String opc = params.getString("opc");
            String cardholderName = params.optString("cardholderName", "Tarjetahabiente");
            String last4 = params.optString("last4", "0000");
            String network = params.optString("network", "MASTERCARD").toUpperCase();

            // Parsear dirección del usuario si existe
            JSONObject addressJson = params.optJSONObject("userAddress");

            Log.d(TAG, "pushProvision: opc length=" + opc.length() + ", cardholder=" + cardholderName + ", last4=" + last4 + ", network=" + network);

            // Determinar el tipo de red
            int cardNetwork;
            switch (network) {
                case "VISA":
                    cardNetwork = TapAndPay.CARD_NETWORK_VISA;
                    break;
                case "MASTERCARD":
                default:
                    cardNetwork = TapAndPay.CARD_NETWORK_MASTERCARD;
                    break;
            }

            // Determinar el servicio de tokenización
            int tokenServiceProvider;
            switch (network) {
                case "VISA":
                    tokenServiceProvider = TapAndPay.TOKEN_PROVIDER_VISA;
                    break;
                case "MASTERCARD":
                default:
                    tokenServiceProvider = TapAndPay.TOKEN_PROVIDER_MASTERCARD;
                    break;
            }

            // Construir la dirección del usuario
            UserAddress.Builder addressBuilder = UserAddress.newBuilder()
                .setName(cardholderName)
                .setCountryCode("MX");

            if (addressJson != null) {
                if (addressJson.has("phoneNumber")) {
                    addressBuilder.setPhoneNumber(addressJson.getString("phoneNumber"));
                }
                if (addressJson.has("address1")) {
                    addressBuilder.setAddress1(addressJson.getString("address1"));
                }
                if (addressJson.has("address2")) {
                    addressBuilder.setAddress2(addressJson.getString("address2"));
                }
                if (addressJson.has("city")) {
                    addressBuilder.setLocality(addressJson.getString("city"));
                }
                if (addressJson.has("state")) {
                    addressBuilder.setAdministrativeArea(addressJson.getString("state"));
                }
                if (addressJson.has("postalCode")) {
                    addressBuilder.setPostalCode(addressJson.getString("postalCode"));
                }
                if (addressJson.has("countryCode")) {
                    addressBuilder.setCountryCode(addressJson.getString("countryCode"));
                }
            }

            UserAddress userAddress = addressBuilder.build();

            // Construir el request de Push Tokenize
            PushTokenizeRequest pushTokenizeRequest = new PushTokenizeRequest.Builder()
                .setOpaquePaymentCard(opc.getBytes())
                .setNetwork(cardNetwork)
                .setTokenServiceProvider(tokenServiceProvider)
                .setDisplayName(cardholderName)
                .setLastDigits(last4)
                .setUserAddress(userAddress)
                .build();

            Log.d(TAG, "pushProvision: Request construido, iniciando tokenización...");

            // Guardar callback para usar en onActivityResult
            pendingCallbackContext = callbackContext;

            // Iniciar el flujo de Push Tokenize
            cordova.setActivityResultCallback(this);
            tapAndPayClient.pushTokenize(
                cordova.getActivity(),
                pushTokenizeRequest,
                REQUEST_CODE_PUSH_TOKENIZE
            );

        } catch (JSONException e) {
            Log.e(TAG, "pushProvision: Error parsing JSON", e);
            callbackContext.error("Error al parsear parámetros: " + e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "pushProvision: Error", e);
            callbackContext.error("Error en pushProvision: " + e.getMessage());
        }
    }

    private void isCardInGoogleWallet(String last4, CallbackContext callbackContext) {
        Log.d(TAG, "Checking card in wallet: " + last4);

        cordova.getThreadPool().execute(() -> {
            tapAndPayClient.listTokens()
                .addOnSuccessListener(tokenInfoList -> {
                    try {
                        JSONObject result = new JSONObject();
                        boolean isActive = false;
                        boolean hasToken = false;
                        String pendingState = null;
                        JSONArray matchedTokens = new JSONArray();

                        if (tokenInfoList != null) {
                            for (TokenInfo tokenInfo : tokenInfoList) {
                                String tokenLast4 = tokenInfo.getFpanLastFour();
                                String dpanLast4 = tokenInfo.getDpanLastFour();
                                int tokenState = tokenInfo.getTokenState();

                                if (last4.equals(tokenLast4) || last4.equals(dpanLast4)) {
                                    hasToken = true;
                                    String stateString = getTokenStateString(tokenState);

                                    Log.d(TAG, "Card found: " + last4 + " state=" + stateString);

                                    JSONObject tokenObj = new JSONObject();
                                    tokenObj.put("fpanLastFour", tokenLast4);
                                    tokenObj.put("dpanLastFour", dpanLast4);
                                    tokenObj.put("tokenState", tokenState);
                                    tokenObj.put("tokenStateString", stateString);
                                    tokenObj.put("network", tokenInfo.getNetwork());
                                    tokenObj.put("issuerName", tokenInfo.getIssuerName());
                                    matchedTokens.put(tokenObj);

                                    // Only consider ACTIVE tokens as "existing in wallet"
                                    // Yellow path tokens (NEEDS_IDENTITY_VERIFICATION, PENDING) should keep button visible
                                    if (tokenState == TapAndPay.TOKEN_STATE_ACTIVE) {
                                        isActive = true;
                                    } else {
                                        pendingState = stateString;
                                    }
                                }
                            }
                        }

                        // Card is considered "in wallet" only if it has an ACTIVE token
                        result.put("exists", isActive);
                        result.put("hasToken", hasToken);
                        result.put("isActive", isActive);
                        if (pendingState != null) {
                            result.put("pendingState", pendingState);
                        }
                        result.put("last4Searched", last4);
                        result.put("matchedTokens", matchedTokens);
                        result.put("totalTokensInWallet", tokenInfoList != null ? tokenInfoList.size() : 0);

                        callbackContext.success(result);
                    } catch (JSONException e) {
                        Log.e(TAG, "JSON error in isCardInGoogleWallet", e);
                        callbackContext.error("JSON error: " + e.getMessage());
                    }
                })
                .addOnFailureListener(e -> {
                    Log.e(TAG, "Error listing tokens: " + e.getMessage());
                    try {
                        JSONObject result = new JSONObject();
                        result.put("exists", false);
                        result.put("hasToken", false);
                        result.put("isActive", false);
                        result.put("error", true);
                        result.put("errorMessage", e.getMessage());
                        callbackContext.success(result);
                    } catch (JSONException ex) {
                        callbackContext.error("Error: " + e.getMessage());
                    }
                });
        });
    }

    private void listAllTokens(CallbackContext callbackContext) {
        Log.d(TAG, "listAllTokens: Listing all tokens in wallet");

        cordova.getThreadPool().execute(() -> {
            tapAndPayClient.listTokens()
                .addOnSuccessListener(tokenInfoList -> {
                    try {
                        JSONObject result = new JSONObject();
                        JSONArray tokens = new JSONArray();

                        if (tokenInfoList != null) {
                            for (TokenInfo tokenInfo : tokenInfoList) {
                                JSONObject tokenObj = new JSONObject();
                                tokenObj.put("fpanLastFour", tokenInfo.getFpanLastFour());
                                tokenObj.put("dpanLastFour", tokenInfo.getDpanLastFour());
                                tokenObj.put("tokenState", tokenInfo.getTokenState());
                                tokenObj.put("tokenStateString", getTokenStateString(tokenInfo.getTokenState()));
                                tokenObj.put("network", tokenInfo.getNetwork());
                                tokenObj.put("issuerName", tokenInfo.getIssuerName());
                                tokens.put(tokenObj);
                            }
                        }

                        result.put("tokens", tokens);
                        result.put("count", tokens.length());
                        callbackContext.success(result);
                    } catch (JSONException e) {
                        Log.e(TAG, "JSON error in listAllTokens", e);
                        callbackContext.error("JSON error: " + e.getMessage());
                    }
                })
                .addOnFailureListener(e -> {
                    Log.e(TAG, "Error listing tokens", e);
                    callbackContext.error("Error listing tokens: " + e.getMessage());
                });
        });
    }

    private String getTokenStateString(int tokenState) {
        switch (tokenState) {
            case TapAndPay.TOKEN_STATE_NEEDS_IDENTITY_VERIFICATION:
                return "NEEDS_IDENTITY_VERIFICATION";
            case TapAndPay.TOKEN_STATE_PENDING:
                return "PENDING";
            case TapAndPay.TOKEN_STATE_SUSPENDED:
                return "SUSPENDED";
            case TapAndPay.TOKEN_STATE_ACTIVE:
                return "ACTIVE";
            case TapAndPay.TOKEN_STATE_FELICA_PENDING_PROVISIONING:
                return "FELICA_PENDING_PROVISIONING";
            case TapAndPay.TOKEN_STATE_UNTOKENIZED:
                return "UNTOKENIZED";
            default:
                return "UNKNOWN_" + tokenState;
        }
    }

    private void checkGooglePayAvailability(CallbackContext callbackContext) {
        Log.d(TAG, "Checking Google Pay availability");

        cordova.getThreadPool().execute(() -> {
            try {
                tapAndPayClient.getActiveWalletId()
                    .addOnSuccessListener(walletId -> {
                        try {
                            JSONObject result = buildAvailabilityResult(
                                true,
                                true,
                                false,
                                walletId,
                                "Google Pay está disponible y tu cartera activa.",
                                null
                            );
                            callbackContext.success(result);
                        } catch (JSONException e) {
                            Log.e(TAG, "JSON error in getActiveWalletId success", e);
                            callbackContext.error("JSON error: " + e.getMessage());
                        }
                    })
                    .addOnFailureListener(e -> {
                        Integer statusCode = extractStatusCode(e);
                        Log.d(TAG, "getActiveWalletId failed with code: " + statusCode);

                        try {
                            boolean isNoActiveWallet = statusCode != null &&
                                (statusCode == TapAndPayStatusCodes.TAP_AND_PAY_NO_ACTIVE_WALLET || statusCode == 15002 || statusCode == 6002);
                            boolean isNotVerified = statusCode != null && statusCode == 15009;
                            boolean unavailable = isGooglePayUnavailable(statusCode) || isNotVerified;

                            JSONObject result = buildAvailabilityResult(
                                !unavailable,
                                false,
                                isNoActiveWallet,
                                null,
                                getAvailabilityFailureMessage(statusCode, e),
                                statusCode
                            );
                            callbackContext.success(result);
                        } catch (JSONException ex) {
                            Log.e(TAG, "JSON error in getActiveWalletId failure", ex);
                            callbackContext.error("JSON error: " + ex.getMessage());
                        }
                    });
            } catch (Exception e) {
                Log.e(TAG, "Error checking Google Pay availability", e);
                callbackContext.error("Error checking Google Pay availability: " + e.getMessage());
            }
        });
    }

    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        Log.d(TAG, "onActivityResult: requestCode=" + requestCode + ", resultCode=" + resultCode);

        if (requestCode == REQUEST_CODE_CREATE_WALLET) {
            if (pendingCallbackContext == null) {
                Log.e(TAG, "No pending callback context for wallet creation result");
                return;
            }

            if (resultCode == Activity.RESULT_OK) {
                // Cartera creada/activada exitosamente, verificar de nuevo
                Log.d(TAG, "Wallet created/activated successfully, checking again");
                checkGooglePayAvailabilityAfterWalletCreation(pendingCallbackContext);
            } else {
                // Usuario canceló o hubo error
                Log.d(TAG, "Wallet creation cancelled or failed");
                try {
                    JSONObject result = buildAvailabilityResult(
                        true,
                        false,
                        true,
                        null,
                        "Necesitas activar tu cartera de Google Pay para continuar.",
                        null
                    );
                    pendingCallbackContext.success(result);
                } catch (JSONException e) {
                    pendingCallbackContext.error("JSON error: " + e.getMessage());
                }
            }
            pendingCallbackContext = null;
        }

        if (requestCode == REQUEST_CODE_PUSH_TOKENIZE) {
            if (pendingCallbackContext == null) {
                Log.e(TAG, "No pending callback context for push tokenize result");
                return;
            }

            try {
                JSONObject result = new JSONObject();

                if (resultCode == Activity.RESULT_OK) {
                    Log.d(TAG, "Push tokenize SUCCESS");
                    result.put("success", true);
                    result.put("message", "Tarjeta agregada exitosamente a Google Pay");

                    // Obtener el token ID si está disponible
                    if (data != null) {
                        String tokenId = data.getStringExtra(TapAndPay.EXTRA_ISSUER_TOKEN_ID);
                        if (tokenId != null) {
                            result.put("tokenId", tokenId);
                            Log.d(TAG, "Token ID: " + tokenId);
                        }
                    }
                    pendingCallbackContext.success(result);
                } else if (resultCode == Activity.RESULT_CANCELED) {
                    Log.d(TAG, "Push tokenize CANCELLED by user");
                    result.put("success", false);
                    result.put("cancelled", true);
                    result.put("message", "El usuario canceló el proceso");
                    pendingCallbackContext.success(result);
                } else {
                    Log.d(TAG, "Push tokenize FAILED with resultCode: " + resultCode);
                    result.put("success", false);
                    result.put("message", "Error al agregar tarjeta (código: " + resultCode + ")");

                    // Intentar obtener más información del error
                    if (data != null) {
                        String errorMessage = data.getStringExtra("error_message");
                        if (errorMessage != null) {
                            result.put("errorDetail", errorMessage);
                        }
                    }
                    pendingCallbackContext.success(result);
                }
            } catch (JSONException e) {
                Log.e(TAG, "JSON error in pushTokenize result", e);
                pendingCallbackContext.error("JSON error: " + e.getMessage());
            }

            pendingCallbackContext = null;
        }
    }

    private void checkGooglePayAvailabilityAfterWalletCreation(CallbackContext callbackContext) {
        tapAndPayClient.getActiveWalletId()
            .addOnSuccessListener(walletId -> {
                try {
                    JSONObject result = buildAvailabilityResult(
                        true,
                        true,
                        false,
                        walletId,
                        "Google Pay está disponible y tu cartera activa.",
                        null
                    );
                    callbackContext.success(result);
                } catch (JSONException e) {
                    Log.e(TAG, "JSON error after wallet creation", e);
                    callbackContext.error("JSON error: " + e.getMessage());
                }
            })
            .addOnFailureListener(e -> {
                try {
                    Integer statusCode = extractStatusCode(e);
                    JSONObject result = buildAvailabilityResult(
                        true,
                        false,
                        true,
                        null,
                        "No se pudo activar la cartera de Google Pay.",
                        statusCode
                    );
                    callbackContext.success(result);
                } catch (JSONException ex) {
                    callbackContext.error("JSON error: " + ex.getMessage());
                }
            });
    }

    private JSONObject buildAvailabilityResult(
        boolean googlePayAvailable,
        boolean hasActiveWallet,
        boolean needsWalletCreation,
        String walletId,
        String statusMessage,
        Integer statusCode
    ) throws JSONException {
        JSONObject result = new JSONObject();
        result.put("googlePayAvailable", googlePayAvailable);
        result.put("hasActiveWallet", hasActiveWallet);
        result.put("needsWalletCreation", needsWalletCreation);
        if (walletId != null) {
            result.put("walletId", walletId);
        }
        if (statusMessage != null) {
            result.put("statusMessage", statusMessage);
        }
        if (statusCode != null) {
            result.put("statusCode", statusCode);
        }
        return result;
    }

    private Integer extractStatusCode(Exception e) {
        if (e instanceof ApiException) {
            return ((ApiException) e).getStatusCode();
        }
        return null;
    }

    private boolean isWalletCreationStatus(Integer statusCode) {
        if (statusCode == null) {
            return false;
        }
        return statusCode == TapAndPayStatusCodes.TAP_AND_PAY_NO_ACTIVE_WALLET || statusCode == 6002 || statusCode == 15009;
    }

    private boolean isGooglePayUnavailable(Integer statusCode) {
        if (statusCode == null) {
            return false;
        }
        return statusCode == 13;
    }

    private String getAvailabilityFailureMessage(Integer statusCode, Exception e) {
        if (statusCode != null) {
            switch (statusCode) {
                case 13:
                    return "Google Pay no está disponible en este dispositivo.";
                case 15002: // TAP_AND_PAY_NO_ACTIVE_WALLET
                case 6002:
                    return "Necesitas crear una cartera de Google Pay para continuar.";
                case 15009: // Calling package not verified
                    return "La aplicación no está autorizada para Google Pay. Contacta al soporte.";
                default:
                    return "Error de Google Pay (código " + statusCode + ").";
            }
        }

        if (e != null && e.getMessage() != null) {
            return e.getMessage();
        }

        return "Google Pay requiere que configures una cartera para continuar.";
    }
}
