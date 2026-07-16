package com.riseapp.rise

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Owns nothing but "ring at this instant". All scheduling decisions (repeat
 * days, DST, timezones) are made in Dart; this receives absolute UTC instants.
 */
object AlarmScheduler {
    private const val TAG = "AlarmScheduler"
    const val EXTRA_ALARM_ID = "alarmId"
    const val EXTRA_LABEL = "label"
    const val EXTRA_SOUND = "soundAsset"
    const val EXTRA_VIBRATE = "vibrate"

    private const val PREFS = "rise_scheduled"
    private const val KEY_IDS = "ids"

    // A dedicated request code for the "ring now" recovery PendingIntent, kept
    // distinct from any alarm id's request code so arming an immediate ring
    // never overwrites that alarm's own scheduled (future) PendingIntent.
    // Alarm ids come from a local autoincrement and never approach this value.
    private const val IMMEDIATE_REQUEST_CODE = Int.MAX_VALUE

    private fun alarmManager(context: Context): AlarmManager =
        context.getSystemService(AlarmManager::class.java)

    /**
     * PendingIntent request codes are 32-bit; alarm ids are Long. Truncating
     * silently would let two ids collide on one request code, and the second
     * alarm would overwrite the first's PendingIntent — an alarm that never
     * rings, with no error anywhere. Fail loudly instead: ids come from a local
     * autoincrement and are small, so this should be unreachable.
     */
    private fun Long.toRequestCode(): Int {
        require(this in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
            "Alarm id $this exceeds the 32-bit PendingIntent request code range"
        }
        return toInt()
    }

    fun canScheduleExact(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager(context).canScheduleExactAlarms()
        } else {
            true
        }

    private fun firePendingIntent(context: Context, alarm: NativeAlarm): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_ALARM_ID, alarm.id.toRequestCode())
            putExtra(EXTRA_LABEL, alarm.label)
            putExtra(EXTRA_SOUND, alarm.soundAsset)
            putExtra(EXTRA_VIBRATE, alarm.vibrate)
        }
        return PendingIntent.getBroadcast(
            context,
            alarm.id.toRequestCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    /**
     * Rings [alarm] almost immediately by arming a one-shot setAlarmClock ~1.5s
     * out, rather than starting the foreground service directly.
     *
     * Android 14+/OEMs block starting a foreground service from a background
     * context. Missed-alarm recovery runs in the headless boot engine (a
     * background context), so a direct startForegroundService there throws
     * ForegroundServiceStartNotAllowedException and the alarm silently never
     * rings — confirmed on a Samsung S24 (Android 16): recovery logged
     * "Recovering missed alarm N" but nothing rang. Scheduling an alarm is NOT
     * a foreground-service start and IS allowed from the background; the actual
     * FGS start then happens when AlarmReceiver fires, which is exempted because
     * it is triggered by an exact alarm — the same path a normal alarm takes.
     *
     * Uses [IMMEDIATE_REQUEST_CODE] so it never disturbs [alarm]'s own
     * scheduled (future) PendingIntent. The real alarm id still rides in
     * EXTRA_ALARM_ID, so AlarmService rings and stopRinging-identifies the
     * correct alarm.
     */
    fun ringNow(context: Context, alarm: NativeAlarm) {
        val realId = alarm.id.toRequestCode()
        val fireIntent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_ALARM_ID, realId)
            putExtra(EXTRA_LABEL, alarm.label)
            putExtra(EXTRA_SOUND, alarm.soundAsset)
            putExtra(EXTRA_VIBRATE, alarm.vibrate)
        }
        val firePi = PendingIntent.getBroadcast(
            context,
            IMMEDIATE_REQUEST_CODE,
            fireIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val showPi = PendingIntent.getActivity(
            context,
            IMMEDIATE_REQUEST_CODE,
            Intent(context, RingActivity::class.java).putExtra(EXTRA_ALARM_ID, realId),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val at = System.currentTimeMillis() + 1500
        alarmManager(context).setAlarmClock(
            AlarmManager.AlarmClockInfo(at, showPi),
            firePi
        )
        Log.i(TAG, "ringNow armed immediate alarm $realId at $at")
    }

    /** Replaces the entire scheduled set. Idempotent by construction. */
    fun reconcile(context: Context, alarms: List<NativeAlarm>) {
        // Validate every id before touching OS state: cancelAll() wipes
        // SharedPreferences up front, and the loop below only persists ids
        // to KEY_IDS after each is armed with the OS. If toRequestCode()
        // threw partway through the loop, every alarm already armed in this
        // call would be live with AlarmManager but missing from KEY_IDS —
        // cancelAll() reads only KEY_IDS, so it could never find or cancel
        // them again. Failing here, before cancelAll() runs, keeps
        // reconcile() atomic: either every alarm is validated and the whole
        // replace proceeds, or nothing is touched. Do not move or remove
        // this pre-pass.
        alarms.forEach { it.id.toRequestCode() }

        cancelAll(context)

        val am = alarmManager(context)
        val ids = mutableSetOf<String>()

        for (alarm in alarms) {
            val showIntent = PendingIntent.getActivity(
                context,
                alarm.id.toRequestCode(),
                Intent(context, RingActivity::class.java)
                    .putExtra(EXTRA_ALARM_ID, alarm.id.toRequestCode()),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // setAlarmClock: exact, never time-shifted, exits Doze shortly
            // before firing, and shows the system alarm indicator.
            am.setAlarmClock(
                AlarmManager.AlarmClockInfo(alarm.fireAtEpochMs, showIntent),
                firePendingIntent(context, alarm)
            )
            ids.add(alarm.id.toString())
            Log.i(TAG, "scheduled alarm ${alarm.id} at ${alarm.fireAtEpochMs}")
        }

        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putStringSet(KEY_IDS, ids).apply()
    }

    fun cancel(context: Context, id: Int) {
        val intent = Intent(context, AlarmReceiver::class.java)
        val pi = PendingIntent.getBroadcast(
            context, id, intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pi != null) {
            alarmManager(context).cancel(pi)
            pi.cancel()
        }
    }

    fun cancelAll(context: Context) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getStringSet(KEY_IDS, emptySet())?.forEach { cancel(context, it.toInt()) }
        prefs.edit().remove(KEY_IDS).apply()
    }
}
