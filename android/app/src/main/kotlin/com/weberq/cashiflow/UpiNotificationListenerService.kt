package com.weberq.cashiflow

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Listens for payment confirmation notifications from UPI apps.
 * Parses the notification text and sends structured data to Flutter via a shared callback.
 */
class UpiNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "UpiNotifListener"

        // SMS app package names we care about (where Bank SMS notifications arrive)
        val SMS_PACKAGES = setOf(
            "com.google.android.apps.messaging",  // Google Messages
            "com.samsung.android.messaging",        // Samsung Messages
            "com.android.mms",                     // Default Android MMS
            "com.oneplus.mms",                     // OnePlus Messages
            "com.motorola.messaging",              // Moto Messages
        )

        // Singleton callback to send data to Flutter side
        var onPaymentNotification: ((Map<String, String>) -> Unit)? = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val pkg = sbn.packageName ?: return

        if (pkg !in SMS_PACKAGES) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val bigText = extras.getCharSequence("android.bigText")?.toString() ?: text

        Log.d(TAG, "SMS notification from $pkg => title='$title', text='$bigText'")

        val parsed = parsePaymentNotification(pkg, title, bigText)
        if (parsed != null) {
            val mutableParsed = parsed.toMutableMap()
            mutableParsed["messageId"] = UUID.randomUUID().toString()
            
            Log.d(TAG, "Parsed payment: $mutableParsed")
            
            // **New Architecture:** Permanently save to disk until Flutter explicitly deletes it.
            queueNotification(mutableParsed)

            // Continue attempting live UI dispatch if the app happens to be open
            onPaymentNotification?.invoke(mutableParsed)
        }
    }

    private fun queueNotification(parsed: Map<String, String>) {
        val prefs = applicationContext.getSharedPreferences("cashiflow_notifications", Context.MODE_PRIVATE)
        val currentQueueStr = prefs.getString("pending_sms", "[]")
        
        try {
            val jsonArray = JSONArray(currentQueueStr)
            val jsonObject = JSONObject()
            
            parsed.forEach { (key, value) -> jsonObject.put(key, value) }
            jsonArray.put(jsonObject)
            
            prefs.edit().putString("pending_sms", jsonArray.toString()).apply()
            Log.d(TAG, "Queued SMS locally. Queue size: ${jsonArray.length()}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to queue notification", e)
        }
    }

    /**
     * Parse payment notifications from various UPI apps.
     * Returns a map with keys: amount, payee, status, app
     */
    private fun parsePaymentNotification(
        pkg: String,
        title: String,
        text: String
    ): Map<String, String>? {
        val combined = "$title $text"

        // Common patterns:
        // GPay: "Paid ₹500 to John" or "Payment of ₹500.00 to john@upi successful"
        // PhonePe: "₹500 paid to John" or "Payment of Rs.500 to John is successful"
        // Paytm: "₹500 paid to John" or "Payment of ₹500 to John successful"
        // BHIM: "Payment of Rs 500 to john@upi was successful"

        // Check if this is a debit/payment notification (not a received/credit one)
        val isPayment = combined.containsAny(
            "paid", "debited", "sent", "payment of", "transferred"
        )
        val isNotCredit = !combined.containsAny(
            "received", "credited", "added to"
        )

        // We still run regex to provide a fallback if Gemini isn't used
        val amountRegex = Regex("""(?:₹|Rs\.?|INR)\s*(\d+(?:[,\d]*)?(?:\.\d{1,2})?)""", RegexOption.IGNORE_CASE)
        val amountMatch = amountRegex.find(combined)
        val amount = amountMatch?.groupValues?.get(1)?.replace(",", "")
        
        val payeeRegex = Regex("""(?:to|paid)\s+(.+?)(?:\s+(?:is\s+)?(?:successful|completed|done)|[.!]|$)""", RegexOption.IGNORE_CASE)
        val payeeMatch = payeeRegex.find(combined)
        val payee = payeeMatch?.groupValues?.get(1)?.trim() ?: ""

        val appName = when (pkg) {
            "com.google.android.apps.messaging" -> "Google SMS"
            "com.samsung.android.messaging" -> "Samsung SMS"
            "com.android.mms" -> "Android SMS"
            else -> "SMS"
        }

        // Just pre-filter total spam (e.g. WhatsApp chats without money context)
        val hasMoneyContext = combined.containsAny("₹", "rs", "inr", "paid", "debited", "transferred", "payment")
        if (!hasMoneyContext) return null

        return mapOf(
            "amount" to (amount ?: ""),
            "payee" to payee,
            "status" to "success",
            "app" to appName,
            "package" to pkg,
            "rawTitle" to title,
            "rawText" to text,
        )
    }

    private fun String.containsAny(vararg keywords: String): Boolean {
        val lower = this.lowercase()
        return keywords.any { lower.contains(it) }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // No action needed
    }
}
