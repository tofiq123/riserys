package com.riseapp.rise

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * The post-dismissal "still up?" wake-up check. Two OS-scheduled events, so it
 * works with the app dead: a notification at checkAt, and a re-fire at
 * checkAt + [RESPONSE_WINDOW_MS] that re-enters the normal ring path
 * ([AlarmReceiver] -> foreground service -> [RingActivity]). Tapping "I'm up"
 * ([WakeCheckActionReceiver]) cancels the re-fire.
 *
 * Request codes live in dedicated high namespaces so they never collide with an
 * alarm's own scheduled PendingIntent (small ids) or the immediate-recovery
 * code (Int.MAX_VALUE). Alarm ids come from a local autoincrement and never
 * approach these bases.
 */
object WakeCheckScheduler {
    private const val TAG = "WakeCheck"
    const val CHANNEL_ID = "rise_wake_check"
    const val RESPONSE_WINDOW_MS = 100_000L

    const val EXTRA_ALARM_ID = "wc_alarmId"

    /** Set on the notification's content (body-tap) intent: opening the app this
     *  way counts as "I'm up" — [MainActivity] cancels the pending re-ring. */
    const val EXTRA_ACK = "wc_ack"

    private const val NOTIF_TRIGGER_BASE = 500_000_000
    private const val REFIRE_BASE = 600_000_000
    private const val NOTIFICATION_ID_BASE = 700_000_000
    private const val ACTION_BASE = 800_000_000
    private const val CONTENT_BASE = 900_000_000

    private fun am(c: Context): AlarmManager =
        c.getSystemService(AlarmManager::class.java)

    private fun nm(c: Context): NotificationManager =
        c.getSystemService(NotificationManager::class.java)

    fun schedule(context: Context, alarm: NativeAlarm, checkAtMs: Long) {
        val id = alarm.id.toInt()

        // 1) Re-fire at checkAt + response window, via the normal ring path.
        // Armed first: setAlarmClock is exempt from the exact-alarm permission,
        // so this is the safety net that always works.
        val refireAt = checkAtMs + RESPONSE_WINDOW_MS
        val fireIntent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
            putExtra(AlarmScheduler.EXTRA_LABEL, alarm.label)
            putExtra(AlarmScheduler.EXTRA_SOUND, alarm.soundAsset)
            putExtra(AlarmScheduler.EXTRA_VIBRATE, alarm.vibrate)
            putExtra(AlarmScheduler.EXTRA_VIBRATION_PATTERN, alarm.vibrationPattern)
        }
        val firePi = PendingIntent.getBroadcast(
            context, REFIRE_BASE + id, fireIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val showPi = PendingIntent.getActivity(
            context, REFIRE_BASE + id,
            Intent(context, RingActivity::class.java)
                .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am(context).setAlarmClock(
            AlarmManager.AlarmClockInfo(refireAt, showPi), firePi
        )

        // 2) Notification trigger at checkAt, best-effort. Requires the
        // exact-alarm permission; if it's off, the re-fire above still fires.
        val notifIntent = Intent(context, WakeCheckReceiver::class.java).apply {
            putExtra(EXTRA_ALARM_ID, id)
            putExtra(AlarmScheduler.EXTRA_LABEL, alarm.label)
        }
        val notifPi = PendingIntent.getBroadcast(
            context, NOTIF_TRIGGER_BASE + id, notifIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        try {
            am(context).setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, checkAtMs, notifPi
            )
        } catch (e: SecurityException) {
            // No exact-alarm permission: the "still up?" notification won't show,
            // but the re-fire above is already armed, so the check degrades to
            // "always re-rings" rather than vanishing.
            Log.w(TAG, "wake-check $id notification not armed: $e")
        }
        Log.i(TAG, "wake-check $id: notify@$checkAtMs refire@$refireAt")
    }

    fun cancel(context: Context, alarmId: Int) {
        val notifPi = PendingIntent.getBroadcast(
            context, NOTIF_TRIGGER_BASE + alarmId,
            Intent(context, WakeCheckReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (notifPi != null) {
            am(context).cancel(notifPi)
            notifPi.cancel()
        }
        val firePi = PendingIntent.getBroadcast(
            context, REFIRE_BASE + alarmId,
            Intent(context, AlarmReceiver::class.java),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (firePi != null) {
            am(context).cancel(firePi)
            firePi.cancel()
        }
        nm(context).cancel(NOTIFICATION_ID_BASE + alarmId)
        Log.i(TAG, "wake-check $alarmId cancelled")
    }

    private fun createChannel(context: Context) {
        val channel = NotificationChannel(
            CHANNEL_ID, "Wake-up check", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Checks you are still awake after dismissing an alarm."
        }
        nm(context).createNotificationChannel(channel)
    }

    /** Posts the "Still up?" notification with an "I'm up" action. */
    fun showStillUp(context: Context, alarmId: Int, label: String) {
        createChannel(context)
        val imUp = PendingIntent.getBroadcast(
            context, ACTION_BASE + alarmId,
            Intent(context, WakeCheckActionReceiver::class.java)
                .putExtra(EXTRA_ALARM_ID, alarmId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        // Tapping the notification body opens the app and counts as "I'm up".
        val openApp = PendingIntent.getActivity(
            context, CONTENT_BASE + alarmId,
            Intent(context, MainActivity::class.java)
                .putExtra(EXTRA_ALARM_ID, alarmId)
                .putExtra(EXTRA_ACK, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle("Still up?")
            .setContentText("Tap \"I'm up\", or $label rings again.")
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(openApp)
            .addAction(0, "I'm up", imUp)
            .setAutoCancel(true)
            .build()
        nm(context).notify(NOTIFICATION_ID_BASE + alarmId, notification)
    }
}
