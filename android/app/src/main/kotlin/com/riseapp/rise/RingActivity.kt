package com.riseapp.rise

import android.content.Intent
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

    /**
     * android:launchMode="singleInstance" (declared in the manifest) means a
     * second alarm firing while this activity is still alive is delivered
     * here rather than to a fresh instance — Android calls this instead of
     * onCreate. Without updating `intent`, later reads of
     * `intent.getIntExtra(EXTRA_ALARM_ID, ...)` (e.g. a future onCreate this
     * process never sees again, or any other code that trusts `getIntent()`)
     * would keep returning the *first* alarm's id forever.
     *
     * This alone does not repaint the Flutter UI — Dart's widget tree is not
     * rebuilt just because the Activity intent changed. That half of the fix
     * is `_RiseAppState`'s resumed-lifecycle re-check in main.dart, which
     * fires because a reused singleInstance activity being brought back to
     * the foreground always goes through onResume.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            AlarmHostApiImpl(applicationContext)
        )
    }
}
