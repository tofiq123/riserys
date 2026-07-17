package com.riseapp.rise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Fires at the check time: posts the "Still up?" notification. The re-fire
 * was already armed by [WakeCheckScheduler.schedule]. */
class WakeCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(WakeCheckScheduler.EXTRA_ALARM_ID, -1)
        if (id < 0) return
        val label = intent.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "your alarm"
        WakeCheckScheduler.showStillUp(context, id, label)
    }
}
