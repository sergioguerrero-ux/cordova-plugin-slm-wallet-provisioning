package com.slm.plugins.wallet;

import org.apache.cordova.*;
import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONException;

import android.content.Intent;

public class SlmWalletProvisioning extends CordovaPlugin {

  @Override
  public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {

    if ("googleIsAvailable".equals(action)) {
      // TODO: check Google Play Services + TapAndPay availability
      JSONObject res = new JSONObject();
      res.put("ok", true);
      res.put("available", true);
      callbackContext.success(res);
      return true;
    }

    if ("googlePushProvision".equals(action)) {
      JSONObject opts = args.optJSONObject(0);
      // TODO: TapAndPayClient.pushTokenize(...) / startActivityForResult
      // callbackContext.success(...) when done
      JSONObject res = new JSONObject();
      res.put("ok", true);
      res.put("started", true);
      callbackContext.success(res);
      return true;
    }

    callbackContext.error("Unknown action: " + action);
    return false;
  }

  // Si vas a usar startActivityForResult, implementa onActivityResult y guarda callbackContext
}
