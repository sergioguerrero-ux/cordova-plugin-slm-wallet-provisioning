package com.slm.plugins.wallet;

import android.app.Activity;
import android.app.PendingIntent;
import android.content.Intent;
import android.content.IntentSender;
import android.os.Bundle;

import com.google.android.gms.common.api.ApiException;
import com.google.android.gms.tapandpay.PushTokenizeRequest;
import com.google.android.gms.tapandpay.PushTokenizeResponse;
import com.google.android.gms.tapandpay.TapAndPay;
import com.google.android.gms.tapandpay.TapAndPayClient;
import com.google.android.gms.tasks.OnFailureListener;
import com.google.android.gms.tasks.OnSuccessListener;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CDVPlugin;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

public class SlmWalletProvisioning extends CDVPlugin {

  private static final int REQUEST_PUSH_TOKENIZE = 0x5BDE;
  private CallbackContext pendingCallback;
  private TapAndPayClient tapAndPayClient;

  @Override
  public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
    if ("googleIsAvailable".equals(action)) {
      checkGoogleAvailability(callbackContext);
      return true;
    }

    if ("googlePushProvision".equals(action)) {
      JSONObject opts = args.optJSONObject(0);
      startGoogleProvisioning(opts, callbackContext);
      return true;
    }

    callbackContext.error("Unknown action: " + action);
    return false;
  }

  private void checkGoogleAvailability(final CallbackContext callbackContext) {
    TapAndPayClient client = getTapAndPayClient();
    client.isReadyToPay()
        .addOnSuccessListener(new OnSuccessListener<Boolean>() {
          @Override
          public void onSuccess(Boolean ready) {
            try {
              JSONObject res = new JSONObject();
              res.put("ok", true);
              res.put("available", ready);
              callbackContext.success(res);
            } catch (JSONException e) {
              callbackContext.error("json_error");
            }
          }
        })
        .addOnFailureListener(new OnFailureListener() {
          @Override
          public void onFailure(Exception e) {
            JSONObject res = new JSONObject();
            try {
              res.put("ok", false);
              res.put("error", e.getMessage());
            } catch (JSONException jsonException) {
              // ignore
            }
            callbackContext.success(res);
          }
        });
  }

  private void startGoogleProvisioning(JSONObject opts, final CallbackContext callbackContext) {
    if (pendingCallback != null) {
      callbackContext.error("provisioning_in_progress");
      return;
    }

    pendingCallback = callbackContext;

    String cardholderName = opts != null ? opts.optString("cardholderName", "") : "";
    String last4 = opts != null ? opts.optString("last4", "") : "";
    String description = opts != null ? opts.optString("description", "Card") : "Card";

    PushTokenizeRequest request = new PushTokenizeRequest.Builder()
        .setCardholderName(cardholderName)
        .setPrimaryAccountSuffix(last4)
        .setLocalizedDescription(description)
        .build();

    getTapAndPayClient()
        .pushTokenize(request)
        .addOnSuccessListener(new OnSuccessListener<PushTokenizeResponse>() {
          @Override
          public void onSuccess(PushTokenizeResponse response) {
            PendingIntent pi = response.getPendingIntent();
            if (pi == null) {
              sendError("missing_pending_intent");
              return;
            }

            cordova.setActivityResultCallback(SlmWalletProvisioning.this);
            try {
              cordova.getActivity()
                  .startIntentSenderForResult(pi.getIntentSender(), REQUEST_PUSH_TOKENIZE, null, 0, 0, 0);
            } catch (IntentSender.SendIntentException e) {
              sendError(e.getMessage());
            }
          }
        })
        .addOnFailureListener(new OnFailureListener() {
          @Override
          public void onFailure(Exception e) {
            if (e instanceof ApiException) {
              sendError(((ApiException) e).getStatusCode() + ": " + e.getMessage());
            } else {
              sendError(e != null ? e.getMessage() : "unknown_error");
            }
          }
        });
  }

  @Override
  public void onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode != REQUEST_PUSH_TOKENIZE) {
      super.onActivityResult(requestCode, resultCode, data);
      return;
    }

    if (pendingCallback == null) {
      super.onActivityResult(requestCode, resultCode, data);
      return;
    }

    try {
      JSONObject payload = new JSONObject();
      payload.put("ok", resultCode == Activity.RESULT_OK);
      payload.put("resultCode", resultCode);

      Bundle extras = data != null ? data.getExtras() : null;
      if (extras != null && !extras.isEmpty()) {
        JSONObject extrasJson = new JSONObject();
        for (String key : extras.keySet()) {
          Object value = extras.get(key);
          extrasJson.put(key, value != null ? value.toString() : JSONObject.NULL);
        }
        payload.put("extras", extrasJson);
      }

      if (resultCode == Activity.RESULT_OK) {
        pendingCallback.success(payload);
      } else {
        pendingCallback.error(payload);
      }
    } catch (JSONException e) {
      pendingCallback.error("result_json_error");
    } finally {
      pendingCallback = null;
    }
  }

  private void sendError(String message) {
    if (pendingCallback == null) {
      return;
    }
    JSONObject payload = new JSONObject();
    try {
      payload.put("ok", false);
      payload.put("error", message != null ? message : "unknown_error");
    } catch (JSONException e) {
      // ignore
    }
    pendingCallback.error(payload);
    pendingCallback = null;
  }

  private TapAndPayClient getTapAndPayClient() {
    if (tapAndPayClient == null) {
      tapAndPayClient = TapAndPay.getClient(cordova.getContext());
    }
    return tapAndPayClient;
  }
}
