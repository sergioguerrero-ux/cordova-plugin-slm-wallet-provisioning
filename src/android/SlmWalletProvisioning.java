package com.slm.plugins.wallet;

import android.app.Activity;
import android.content.Intent;

import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.wallet.AutoResolveHelper;
import com.google.android.gms.wallet.IsReadyToPayRequest;
import com.google.android.gms.wallet.PaymentData;
import com.google.android.gms.wallet.PaymentDataRequest;
import com.google.android.gms.wallet.PaymentsClient;
import com.google.android.gms.wallet.Wallet;
import com.google.android.gms.wallet.WalletConstants;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CDVPlugin;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public class SlmWalletProvisioning extends CDVPlugin {

  private static final int LOAD_PAYMENT_DATA_REQUEST_CODE = 0x7F03;
  private CallbackContext pendingCallback;
  private PaymentsClient paymentsClient;
  private int paymentsEnvironment = WalletConstants.ENVIRONMENT_TEST;

  @Override
  public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
    if ("googleIsAvailable".equals(action)) {
      JSONObject opts = args.optJSONObject(0);
      checkGoogleAvailability(opts, callbackContext);
      return true;
    }

    if ("googlePushProvision".equals(action)) {
      JSONObject opts = args.optJSONObject(0);
      requestGooglePayment(opts, callbackContext);
      return true;
    }

    callbackContext.error("Unknown action: " + action);
    return false;
  }

  private void checkGoogleAvailability(JSONObject opts, final CallbackContext callbackContext) {
    try {
      int env = resolveEnvironment(opts);
      ensurePaymentsClient(env);
      IsReadyToPayRequest request = IsReadyToPayRequest.fromJson(createIsReadyToPayRequest().toString());
      paymentsClient.isReadyToPay(request)
          .addOnSuccessListener(ready -> {
            try {
              JSONObject res = new JSONObject();
              res.put("ok", true);
              res.put("available", ready);
              callbackContext.success(res);
            } catch (JSONException e) {
              callbackContext.error("json_error");
            }
          })
          .addOnFailureListener(e -> {
            JSONObject res = new JSONObject();
            try {
              res.put("ok", false);
              res.put("error", e.getMessage());
            } catch (JSONException jsonException) {
              // ignore
            }
            callbackContext.success(res);
          });
    } catch (JSONException e) {
      callbackContext.error("invalid_request");
    }
  }

  private void requestGooglePayment(JSONObject opts, final CallbackContext callbackContext) {
    if (pendingCallback != null) {
      callbackContext.error("payment_in_progress");
      return;
    }

    try {
      int env = resolveEnvironment(opts);
      ensurePaymentsClient(env);
      JSONObject requestJson = createPaymentDataRequest(opts);
      if (requestJson == null) {
        callbackContext.error("missing_tokenization_spec");
        return;
      }

      PaymentDataRequest request = PaymentDataRequest.fromJson(requestJson.toString());
      pendingCallback = callbackContext;
      cordova.setActivityResultCallback(this);
      AutoResolveHelper.resolveTask(
          paymentsClient.loadPaymentData(request),
          cordova.getActivity(),
          LOAD_PAYMENT_DATA_REQUEST_CODE
      );
    } catch (JSONException e) {
      callbackContext.error("json_error");
    }
  }

  @Override
  public void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode != LOAD_PAYMENT_DATA_REQUEST_CODE) {
      super.onActivityResult(requestCode, resultCode, data);
      return;
    }

    if (pendingCallback == null) {
      super.onActivityResult(requestCode, resultCode, data);
      return;
    }

    try {
      if (resultCode == Activity.RESULT_OK && data != null) {
        PaymentData paymentData = PaymentData.getFromIntent(data);
        if (paymentData != null) {
          JSONObject payload = new JSONObject(paymentData.toJson());
          JSONObject res = new JSONObject();
          res.put("ok", true);
          res.put("paymentData", payload);
          pendingCallback.success(res);
          return;
        }
      }

      String error = "payment_canceled";
      if (data != null) {
        int statusCode = AutoResolveHelper.getStatusFromIntent(data).getStatusCode();
        error = "status_" + statusCode;
      }
      JSONObject res = new JSONObject();
      res.put("ok", false);
      res.put("error", error);
      pendingCallback.error(res);
    } catch (JSONException e) {
      pendingCallback.error("result_json_error");
    } finally {
      pendingCallback = null;
    }
  }

  private void ensurePaymentsClient(int environment) {
    if (paymentsClient == null || environment != paymentsEnvironment) {
      Wallet.WalletOptions options = new Wallet.WalletOptions.Builder()
          .setEnvironment(environment)
          .build();
      paymentsClient = Wallet.getPaymentsClient(cordova.getContext(), options);
      paymentsEnvironment = environment;
    }
  }

  private int resolveEnvironment(JSONObject opts) {
    if (opts != null) {
      String env = opts.optString("environment");
      if ("PRODUCTION".equalsIgnoreCase(env)) {
        return WalletConstants.ENVIRONMENT_PRODUCTION;
      }
    }
    return WalletConstants.ENVIRONMENT_TEST;
  }

  private JSONObject createIsReadyToPayRequest() throws JSONException {
    JSONObject baseCardPaymentMethod = createBaseCardPaymentMethodBuilder(false);
    JSONObject data = new JSONObject();
    JSONArray allowedMethods = new JSONArray();
    allowedMethods.put(baseCardPaymentMethod);
    data.put("allowedPaymentMethods", allowedMethods);
    return data;
  }

  private JSONObject createPaymentDataRequest(JSONObject opts) throws JSONException {
    if (opts == null) {
      return null;
    }

    String gatewayName = opts.optString("gatewayName");
    String gatewayMerchantId = opts.optString("gatewayMerchantId");
    if (gatewayName.isEmpty() || gatewayMerchantId.isEmpty()) {
      return null;
    }

    JSONObject paymentDataRequest = new JSONObject();
    paymentDataRequest.put("apiVersion", 2);
    paymentDataRequest.put("apiVersionMinor", 0);

    JSONObject baseCardPaymentMethod = createBaseCardPaymentMethodBuilder(true);
    JSONObject tokenSpec = baseCardPaymentMethod.getJSONObject("tokenizationSpecification");
    JSONObject params = tokenSpec.getJSONObject("parameters");
    params.put("gateway", gatewayName);
    params.put("gatewayMerchantId", gatewayMerchantId);

    paymentDataRequest.put("allowedPaymentMethods", new JSONArray().put(baseCardPaymentMethod));

    JSONObject transactionInfo = new JSONObject();
    transactionInfo.put("totalPriceStatus", "FINAL");
    transactionInfo.put("totalPrice", opts.optString("totalPrice", "0.00"));
    transactionInfo.put("currencyCode", opts.optString("currencyCode", "USD"));
    transactionInfo.put("countryCode", opts.optString("countryCode", "US"));
    paymentDataRequest.put("transactionInfo", transactionInfo);

    JSONObject merchantInfo = new JSONObject();
    merchantInfo.put("merchantName", opts.optString("merchantName", "SLM Wallet"));
    paymentDataRequest.put("merchantInfo", merchantInfo);

    return paymentDataRequest;
  }

  private JSONObject createBaseCardPaymentMethodBuilder(boolean withTokenization) throws JSONException {
    JSONObject cardParameters = new JSONObject();
    cardParameters.put("allowedAuthMethods", new JSONArray().put("PAN_ONLY").put("CRYPTOGRAM_3DS"));
    cardParameters.put("allowedCardNetworks", new JSONArray()
        .put("AMEX")
        .put("DISCOVER")
        .put("JCB")
        .put("MASTERCARD")
        .put("VISA"));

    JSONObject cardPaymentMethod = new JSONObject();
    cardPaymentMethod.put("type", "CARD");
    cardPaymentMethod.put("parameters", cardParameters);

    if (withTokenization) {
      JSONObject tokenizationSpecification = new JSONObject();
      tokenizationSpecification.put("type", "PAYMENT_GATEWAY");

      JSONObject parameters = new JSONObject();
      parameters.put("gateway", "");
      parameters.put("gatewayMerchantId", "");
      tokenizationSpecification.put("parameters", parameters);
      cardPaymentMethod.put("tokenizationSpecification", tokenizationSpecification);
    }

    return cardPaymentMethod;
  }
}
