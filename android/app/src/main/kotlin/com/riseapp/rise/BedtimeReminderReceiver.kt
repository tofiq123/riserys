package com.riseapp.rise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Fires at the wind-down time: posts the bedtime notification and re-arms
 * tomorrow's occurrence. All state lives in [BedtimeReminderScheduler]'s
 * prefs, so a stale fire after cancel() is a safe no-op. */
class BedtimeReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        BedtimeReminderScheduler.showAndRearm(context)
    }
}
