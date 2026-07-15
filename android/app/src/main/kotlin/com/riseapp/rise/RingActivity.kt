package com.riseapp.rise

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Hosts the Flutter ringing UI over the lock screen. showWhenLocked and
 * turnScreenOn are declared in the manifest; they are also set in code because
 * some OEM skins honour only the runtime call.
 */
class RingActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
    }

    override fun getInitialRoute(): String {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1)
        return "/ring/$id"
    }
}
