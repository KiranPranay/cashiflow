package com.weberq.cashiflow

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val UPI_CHANNEL = "com.weberq.cashiflow/upi"
    private val NOTIF_CHANNEL = "com.weberq.cashiflow/notifications"
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── UPI Intent MethodChannel ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPI_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "launchUpi" -> handleLaunchUpi(call.argument("uri"), call.argument("package"), result)
                    "launchApp" -> handleLaunchApp(call.argument("package"), result)
                    "isNotificationAccessGranted" -> result.success(isNotificationAccessGranted())
                    "requestNotificationAccess" -> {
                        openNotificationAccessSettings()
                        result.success(true)
                    }
                    "getPendingNotifications" -> handleGetPendingNotifications(result)
                    "removeQueuedNotification" -> handleRemoveQueuedNotification(call.argument("id"), result)
                    else -> result.notImplemented()
                }
            }

        // ── Payment Notification EventChannel ──
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // Register the callback from the NotificationListenerService
                    UpiNotificationListenerService.onPaymentNotification = { paymentData ->
                        mainHandler.post {
                            events?.success(paymentData)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    UpiNotificationListenerService.onPaymentNotification = null
                }
            })
    }

    private fun handleLaunchUpi(upiUri: String?, packageName: String?, result: MethodChannel.Result) {
        if (upiUri == null) {
            result.error("INVALID_ARGS", "UPI URI is required", null)
            return
        }

        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = Uri.parse(upiUri)
                if (packageName != null) {
                    setPackage(packageName)
                }
            }

            if (intent.resolveActivity(packageManager) != null) {
                startActivity(intent)
                result.success(true)
            } else if (packageName != null) {
                // Fallback: let Android choose
                val fallbackIntent = Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse(upiUri)
                }
                if (fallbackIntent.resolveActivity(packageManager) != null) {
                    val chooser = Intent.createChooser(fallbackIntent, "Pay with")
                    startActivity(chooser)
                    result.success(true)
                } else {
                    result.error("NO_UPI_APP", "No UPI app found on device", null)
                }
            } else {
                result.error("NO_UPI_APP", "No UPI app found on device", null)
            }
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }

    private fun handleLaunchApp(packageName: String?, result: MethodChannel.Result) {
        if (packageName == null) {
            result.error("INVALID_ARGS", "Package name is required", null)
            return
        }
        try {
            val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            if (launchIntent != null) {
                startActivity(launchIntent)
                result.success(true)
            } else {
                result.error("APP_NOT_FOUND", "App not installed: $packageName", null)
            }
        } catch (e: Exception) {
            result.error("LAUNCH_FAILED", e.message, null)
        }
    }

    /**
     * Check if our app has notification listener permission.
     */
    private fun isNotificationAccessGranted(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
        if (!TextUtils.isEmpty(flat)) {
            val names = flat.split(":").toTypedArray()
            for (name in names) {
                val cn = ComponentName.unflattenFromString(name)
                if (cn != null && cn.packageName == packageName) {
                    return true
                }
            }
        }
        return false
    }

    /**
     * Open Android's notification access settings page.
     */
    private fun openNotificationAccessSettings() {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
        startActivity(intent)
    }

    private fun handleGetPendingNotifications(result: MethodChannel.Result) {
        try {
            val prefs = getSharedPreferences("cashiflow_notifications", Context.MODE_PRIVATE)
            val jsonStr = prefs.getString("pending_sms", "[]") ?: "[]"
            val jsonArray = JSONArray(jsonStr)
            
            val pendingList = mutableListOf<Map<String, String>>()
            for (i in 0 until jsonArray.length()) {
                val obj = jsonArray.getJSONObject(i)
                val map = mutableMapOf<String, String>()
                val keys = obj.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = obj.getString(key)
                }
                pendingList.add(map)
            }
            
            result.success(pendingList)
        } catch (e: Exception) {
            result.error("QUEUE_ERROR", "Failed to retrieve offline queue", e.message)
        }
    }

    private fun handleRemoveQueuedNotification(id: String?, result: MethodChannel.Result) {
        if (id == null) {
            result.error("INVALID_ARGS", "Message ID is required", null)
            return
        }
        try {
            val prefs = getSharedPreferences("cashiflow_notifications", Context.MODE_PRIVATE)
            val jsonStr = prefs.getString("pending_sms", "[]") ?: "[]"
            val oldArray = JSONArray(jsonStr)
            val newArray = JSONArray()
            
            var found = false
            for (i in 0 until oldArray.length()) {
                val obj = oldArray.getJSONObject(i)
                if (obj.optString("messageId") == id) {
                    found = true
                    continue 
                }
                newArray.put(obj)
            }
            
            if (found) {
                prefs.edit().putString("pending_sms", newArray.toString()).apply()
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("QUEUE_ERROR", "Failed to clear queue item", e.message)
        }
    }
}
