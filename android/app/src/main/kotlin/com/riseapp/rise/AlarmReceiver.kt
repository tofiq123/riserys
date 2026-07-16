package com.riseapp.rise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * The alarm fired. Hand off to a foreground service immediately — a receiver
 * gets ~10 seconds and must not own the ringing lifetime.
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1)
        Log.i("AlarmReceiver", "alarm $id fired")
        if (id < 0) return

        val service = Intent(context, AlarmService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
            putExtra(AlarmScheduler.EXTRA_LABEL,
                intent.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "Alarm")
            putExtra(AlarmScheduler.EXTRA_SOUND,
                intent.getStringExtra(AlarmScheduler.EXTRA_SOUND) ?: "")
            putExtra(AlarmScheduler.EXTRA_VIBRATE,
                intent.getBooleanExtra(AlarmScheduler.EXTRA_VIBRATE, true))
        }
        // Starting an FGS from an exact-alarm broadcast is an allowed exemption.
        ContextCompat.startForegroundService(context, service)
    }
}
