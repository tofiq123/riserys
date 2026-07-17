package com.riseapp.rise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** "I'm up" tapped: cancel the pending re-fire and dismiss the notification. */
class WakeCheckActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(WakeCheckScheduler.EXTRA_ALARM_ID, -1)
        if (id < 0) return
        WakeCheckScheduler.cancel(context, id)
    }
}
