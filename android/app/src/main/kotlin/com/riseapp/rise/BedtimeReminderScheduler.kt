package com.riseapp.rise

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Calendar

/**
 * The opt-in nightly wind-down reminder (Phase 8.5): a plain, DEFAULT-importance
 * notification every night at the user's chosen wall-clock time. Deliberately
 * NOT the alarm channel, not exact, not full-screen — it is a gentle nudge with
 * zero stakes, so it must never look or sound like an alarm, and missing one
 * (Doze slippage, reboot race) has no effect on any alarm.
 *
 * Scheduling model: one `setAndAllowWhileIdle` shot at the next occurrence
 * (inexact is fine for a reminder and needs no exact-alarm permission). When it
 * fires, [BedtimeReminderReceiver] posts the notification and re-arms tomorrow
 * from the persisted state. The state also survives reboot/app-update:
 * [BootReceiver] calls [rearmFromPrefs] — pure native re-arm, no Dart engine.
 *
 * Request codes live in their own 950_000_000 namespace so they can never
 * collide with an alarm's own PendingIntent (small autoincrement ids), the
 * wake-check bases (500M–900M), or the immediate-recovery code (Int.MAX_VALUE).
 */
object BedtimeReminderScheduler {
    private const val TAG = "BedtimeReminder"
    const val CHANNEL_ID = "rise_bedtime"

    private const val TRIGGER_REQUEST_CODE = 950_000_000
    private const val CONTENT_REQUEST_CODE = 950_000_001
    private const val NOTIFICATION_ID = 950_000_002

    private const val PREFS = "rise_bedtime"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_HOUR = "hour"
    private const val KEY_MINUTE = "minute"
    private const val KEY_TITLE = "title"
    private const val KEY_BODY = "body"

    private fun prefs(c: Context) =
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun am(c: Context): AlarmManager =
        c.getSystemService(AlarmManager::class.java)

    private fun nm(c: Context): NotificationManager =
        c.getSystemService(NotificationManager::class.java)

    /** Arms (or re-arms at a new time) the nightly reminder and persists the
     *  schedule so the fire-and-re-arm loop and boot recovery can rebuild it. */
    fun schedule(context: Context, hour: Int, minute: Int, title: String, body: String) {
        prefs(context).edit()
            .putBoolean(KEY_ENABLED, true)
            .putInt(KEY_HOUR, hour)
            .putInt(KEY_MINUTE, minute)
            .putString(KEY_TITLE, title)
            .putString(KEY_BODY, body)
            .apply()
        armNext(context, hour, minute)
    }

    /** Cancels the reminder: clears the persisted schedule, the pending
     *  trigger, and any currently showing notification. Safe when not armed. */
    fun cancel(context: Context) {
        prefs(context).edit().clear().apply()
        val pi = PendingIntent.getBroadcast(
            context, TRIGGER_REQUEST_CODE,
            Intent(context, BedtimeReminderReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pi != null) {
            am(context).cancel(pi)
            pi.cancel()
        }
        nm(context).cancel(NOTIFICATION_ID)
        Log.i(TAG, "bedtime reminder cancelled")
    }

    /** Re-arms from the persisted schedule (boot, app update, clock change).
     *  A no-op while the reminder is disabled. */
    fun rearmFromPrefs(context: Context) {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ENABLED, false)) return
        armNext(context, p.getInt(KEY_HOUR, 22), p.getInt(KEY_MINUTE, 30))
    }

    /** Posts the reminder notification and arms tomorrow's occurrence. Called
     *  by [BedtimeReminderReceiver]; a stale fire after cancel() is dropped. */
    fun showAndRearm(context: Context) {
        val p = prefs(context)
        if (!p.getBoolean(KEY_ENABLED, false)) return

        createChannel(context)
        val openApp = PendingIntent.getActivity(
            context, CONTENT_REQUEST_CODE,
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(p.getString(KEY_TITLE, null) ?: "Wind down for tomorrow")
            .setContentText(p.getString(KEY_BODY, null)
                ?: "A gentle nudge: heading to bed soon makes the morning easier.")
            .setSmallIcon(R.drawable.ic_stat_rise)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .build()
        nm(context).notify(NOTIFICATION_ID, notification)

        armNext(context, p.getInt(KEY_HOUR, 22), p.getInt(KEY_MINUTE, 30))
    }

    /** Arms the next occurrence of [hour]:[minute] local time — today if still
     *  ahead, else tomorrow. Inexact (`setAndAllowWhileIdle`) by design. */
    private fun armNext(context: Context, hour: Int, minute: Int) {
        val now = Calendar.getInstance()
        val next = (now.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) add(Calendar.DAY_OF_YEAR, 1)
        }
        val pi = PendingIntent.getBroadcast(
            context, TRIGGER_REQUEST_CODE,
            Intent(context, BedtimeReminderReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am(context).setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP, next.timeInMillis, pi
        )
        Log.i(TAG, "bedtime reminder armed for ${next.time}")
    }

    private fun createChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID, "Bedtime reminder", NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "A nightly nudge to start winding down."
        }
        nm(context).createNotificationChannel(channel)
    }
}
