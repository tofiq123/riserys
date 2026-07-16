package com.riseapp.rise

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine

/**
 * [engine] is the headless engine this instance was constructed for —
 * BootReceiver passes its own engine so [reconcileFinished] can release
 * exactly that one. MainActivity and RingActivity pass nothing: their engines
 * are activity-owned (torn down by the Android framework, not by us), so
 * [reconcileFinished] is a harmless no-op there.
 */
class AlarmHostApiImpl(
    private val context: Context,
    private val engine: FlutterEngine? = null,
) : AlarmHostApi {

    override fun reconcile(alarms: List<NativeAlarm>) {
        AlarmScheduler.reconcile(context, alarms)
    }

    override fun ringNow(alarm: NativeAlarm) {
        // Starts the ringing service directly, leaving the scheduled set alone.
        val service = Intent(context, AlarmService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, alarm.id.toIntAlarmId())
            putExtra(AlarmScheduler.EXTRA_LABEL, alarm.label)
            putExtra(AlarmScheduler.EXTRA_SOUND, alarm.soundAsset)
            putExtra(AlarmScheduler.EXTRA_VIBRATE, alarm.vibrate)
        }
        ContextCompat.startForegroundService(context, service)
    }

    override fun cancelAll() {
        AlarmScheduler.cancelAll(context)
    }

    override fun getPermissions(): AlarmPermissions {
        val nm = context.getSystemService(NotificationManager::class.java)
        val pm = context.getSystemService(PowerManager::class.java)

        val fullScreen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            nm.canUseFullScreenIntent()
        } else {
            true
        }

        return AlarmPermissions(
            notifications = NotificationManagerCompat.from(context).areNotificationsEnabled(),
            exactAlarm = AlarmScheduler.canScheduleExact(context),
            fullScreenIntent = fullScreen,
            batteryUnrestricted = pm.isIgnoringBatteryOptimizations(context.packageName)
        )
    }

    override fun requestNotificationPermission() {
        // Runtime request needs an Activity; deep-link to settings instead so
        // this works identically from MainActivity and RingActivity.
        context.startActivity(
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    override fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.startActivity(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    .setData(Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    override fun openBatterySettings() {
        // Allowed by Play policy: Rise's core function is alarms, which OEM
        // battery optimisation silently breaks.
        context.startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    override fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                    .setData(Uri.parse("package:${context.packageName}"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    // Peeks at the currently ringing alarm; does not clear state. See the
    // Pigeon doc comment on getRingingAlarmId for why this must stay a peek.
    override fun getRingingAlarmId(): Long? {
        val id = AlarmService.ringingAlarmId ?: return null
        return id.toLong()
    }

    override fun stopRinging(alarmId: Long) {
        // Stop only if this is still the alarm that's ringing. A second alarm can
        // take over the service between Dart deciding to dismiss and this call
        // landing; stopping unconditionally would silence the wrong one.
        if (AlarmService.ringingAlarmId?.toLong() == alarmId) {
            AlarmService.stop(context)
        }
    }

    // A headless reconcile engine (BootReceiver) calls this once its Dart
    // entrypoint is done, so we can tear down just that engine instead of
    // leaking it until the OS kills the process. On a normal app engine
    // (MainActivity, RingActivity) `engine` is null, so this is a no-op.
    override fun reconcileFinished() {
        engine?.let { FlutterEngineHolder.release(it) }
    }

    /**
     * Pigeon alarm ids are Long, but the Intent extra AlarmService reads
     * (EXTRA_ALARM_ID) is an Int. A bare `.toInt()` truncates silently on
     * overflow, so two ids could collide on the same truncated Int and
     * ringNow() would start the wrong alarm's notification/id — an alarm
     * that silently never shows as ringing, which is the exact failure this
     * app exists to prevent. Fail loudly instead, mirroring
     * AlarmScheduler.toRequestCode() (which is private to that file and so
     * cannot be reused here).
     */
    private fun Long.toIntAlarmId(): Int {
        require(this in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) {
            "Alarm id $this exceeds the 32-bit Int range"
        }
        return toInt()
    }
}
