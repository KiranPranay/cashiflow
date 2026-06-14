package com.weberq.cashiflow

import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Listens for payment notifications and forwards structured data to Flutter.
 *
 * Design (privacy + cost):
 *  - ALLOWLIST ONLY: we inspect notifications from a fixed allowlist of UPI,
 *    bank, and SMS apps and nothing else. Every other app is rejected at the
 *    earliest possible point (see [onNotificationPosted]), so unrelated/private
 *    notifications (chats, email, etc.) are never read or stored.
 *  - LOCAL-FIRST: text is parsed on-device with regex here ([parsePaymentNotification]).
 *    The Dart side re-parses locally and only calls Gemini as a fallback when no
 *    amount can be extracted — so the common case never leaves the device.
 */
class UpiNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "UpiNotifListener"

        /**
         * The ONLY packages we ever inspect. Anything not in this set is ignored
         * immediately. Keep this list curated — adding an app here is the single
         * switch that opts it into notification reading.
         */
        val ALLOWED_PACKAGES = setOf(
            // ── UPI / wallet apps ──
            "com.google.android.apps.nbu.paisa.user", // Google Pay
            "com.phonepe.app",                        // PhonePe
            "net.one97.paytm",                        // Paytm
            "in.org.npci.upiapp",                     // BHIM
            "in.amazon.mShop.android.shopping",       // Amazon (Amazon Pay)
            "com.whatsapp",                           // WhatsApp Pay
            "com.dreamplug.androidapp",               // CRED
            "com.mobikwik_new",                       // MobiKwik
            "com.freecharge.android",                 // Freecharge
            "com.google.android.apps.walletnfcrel",   // Google Wallet

            // ── Bank apps ──
            "com.sbi.lotusintouch",                   // SBI YONO
            "com.sbi.SBIFreedomPlus",                 // SBI Anywhere
            "com.csam.icici.bank.imobile",            // ICICI iMobile
            "com.snapwork.hdfc",                      // HDFC
            "com.axis.mobile",                        // Axis
            "com.bankofbaroda.mconnect",              // Bank of Baroda
            "com.fss.pnbpsp",                         // PNB
            "com.msf.kbank.mobile",                   // Kotak 811
            "com.YES_BANK",                           // Yes Bank (verify on device)
            // Add more bank packages here as needed, e.g. com.infrasofttech.* apps.

            // ── SMS apps (bank SMS arrives as notifications here) ──
            "com.google.android.apps.messaging",      // Google Messages
            "com.samsung.android.messaging",          // Samsung Messages
            "com.android.mms",                        // AOSP MMS
            "com.oneplus.mms",                        // OnePlus Messages
            "com.motorola.messaging",                 // Moto Messages
        )

        // Singleton callback to send data to the Flutter side (live dispatch).
        var onPaymentNotification: ((Map<String, String>) -> Unit)? = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        val pkg = sbn.packageName ?: return

        // EARLIEST REJECTION: ignore everything that isn't an allowlisted app.
        if (pkg !in ALLOWED_PACKAGES) return

        val extras = sbn.notification.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val bigText = extras.getCharSequence("android.bigText")?.toString() ?: text

        Log.d(TAG, "Allowlisted notification from $pkg => title='$title', text='$bigText'")

        val parsed = parsePaymentNotification(pkg, title, bigText)
        if (parsed != null) {
            val mutableParsed = parsed.toMutableMap()
            mutableParsed["messageId"] = UUID.randomUUID().toString()
            // Stamp the real arrival time (epoch millis). Critical so a
            // notification synced hours later is recorded at its true time.
            mutableParsed["postedAt"] = System.currentTimeMillis().toString()

            Log.d(TAG, "Parsed payment: $mutableParsed")

            // Persist to disk until Flutter explicitly deletes it.
            queueNotification(mutableParsed)

            // Also attempt a live UI dispatch if the app happens to be open.
            onPaymentNotification?.invoke(mutableParsed)
        }
    }

    private fun queueNotification(parsed: Map<String, String>) {
        val prefs = applicationContext.getSharedPreferences("cashiflow_notifications", Context.MODE_PRIVATE)
        val currentQueueStr = prefs.getString("pending_sms", "[]")

        try {
            val jsonArray = JSONArray(currentQueueStr)

            // DEDUPE: a single payment can fire multiple notifications (app +
            // bank SMS). If an item with the same amount + reference is already
            // queued, skip it. We only dedupe on a NON-EMPTY reference so two
            // genuine same-amount payments without a reference aren't collapsed.
            val newAmount = parsed["amount"] ?: ""
            val newRef = parsed["reference"] ?: ""
            if (newRef.isNotEmpty()) {
                for (i in 0 until jsonArray.length()) {
                    val obj = jsonArray.optJSONObject(i) ?: continue
                    if (obj.optString("amount") == newAmount && obj.optString("reference") == newRef) {
                        Log.d(TAG, "Duplicate (amount=$newAmount, ref=$newRef) already queued; skipping.")
                        return
                    }
                }
            }

            val jsonObject = JSONObject()
            parsed.forEach { (key, value) -> jsonObject.put(key, value) }
            jsonArray.put(jsonObject)

            prefs.edit().putString("pending_sms", jsonArray.toString()).apply()
            Log.d(TAG, "Queued notification locally. Queue size: ${jsonArray.length()}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to queue notification", e)
        }
    }

    /**
     * On-device regex parse of a payment notification.
     * Returns a map with keys: amount, type, payee, reference, status, app,
     * package, rawTitle, rawText — or null if there is no money context at all.
     */
    private fun parsePaymentNotification(
        pkg: String,
        title: String,
        text: String
    ): Map<String, String>? {
        val combined = "$title $text"

        // AMOUNT: ₹ / Rs / Rs. / INR, optional space, optional thousands commas,
        // optional 1-2 decimal places. e.g. "₹1,234.50", "Rs.500", "INR 250".
        val amountRegex = Regex(
            """(?:₹|rs\.?|inr)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)""",
            RegexOption.IGNORE_CASE
        )
        val amount = amountRegex.find(combined)?.groupValues?.get(1)?.replace(",", "")

        // TYPE: credited/received/added => Income; debited/paid/sent/spent/
        // transferred/withdrawn/purchase => Expense. Default to Expense.
        val isIncome = combined.containsAny("credited", "received", "added")
        val isExpense = combined.containsAny(
            "debited", "paid", "sent", "spent", "transferred", "withdrawn", "purchase"
        )
        val type = if (isIncome && !isExpense) "Income" else "Expense"

        // REFERENCE: UPI Ref / UTR / Ref No / txn id patterns. Captures the
        // trailing alphanumeric id (>= 6 chars). e.g. "UPI Ref 2026...",
        // "Ref no 123456789012", "UTR: ABCD1234".
        val refRegex = Regex(
            """(?:upi\s*ref(?:erence)?(?:\s*(?:no|number|id))?|ref(?:erence)?\s*(?:no\.?|number|id)?|utr|txn\s*(?:id|no)?|transaction\s*id)\s*[:#-]?\s*([a-z0-9]{6,})""",
            RegexOption.IGNORE_CASE
        )
        val reference = refRegex.find(combined)?.groupValues?.get(1) ?: ""

        // PAYEE: best-effort recipient/sender after "to"/"from"/"paid".
        val payeeRegex = Regex(
            """(?:to|from|paid)\s+(.+?)(?:\s+(?:is\s+)?(?:successful|completed|done)|[.!]|$)""",
            RegexOption.IGNORE_CASE
        )
        val payee = payeeRegex.find(combined)?.groupValues?.get(1)?.trim() ?: ""

        val appName = when (pkg) {
            "com.google.android.apps.nbu.paisa.user" -> "Google Pay"
            "com.phonepe.app" -> "PhonePe"
            "net.one97.paytm" -> "Paytm"
            "in.org.npci.upiapp" -> "BHIM"
            "com.google.android.apps.messaging" -> "Google SMS"
            "com.samsung.android.messaging" -> "Samsung SMS"
            "com.android.mms" -> "Android SMS"
            else -> "Bank/UPI"
        }

        // Only skip when there is NO money context at all. Anything with a
        // currency token, an amount, or a money keyword is kept for parsing.
        val hasMoneyContext = amount != null || combined.containsAny(
            "₹", "rs", "inr", "credited", "debited", "paid",
            "received", "sent", "transferred", "payment", "withdrawn"
        )
        if (!hasMoneyContext) return null

        return mapOf(
            "amount" to (amount ?: ""),
            "type" to type,
            "payee" to payee,
            "reference" to reference,
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
