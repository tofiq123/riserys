package com.riseapp.rise

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Hosts the Flutter ringing UI over the lock screen. showWhenLocked and
 * turnScreenOn are declared in the manifest; they are also set in code because
 * some OEM skins honour only the runtime call.
 */
class RingActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // setShowWhenLocked/setTurnScreenOn are API 27+ (O_MR1); minSdk is 26,
        // so calling them unconditionally would throw NoSuchMethodError on
        // API 26 devices. Fall back to the equivalent window flags there.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun getInitialRoute(): String {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1)
        return "/ring/$id"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            AlarmHostApiImpl(applicationContext)
        )
    }
}
