package com.riseapp.rise

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AlarmHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            AlarmHostApiImpl(applicationContext)
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleWakeCheckAck(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleWakeCheckAck(intent)
    }

    /** Opening the app from the "Still up?" notification body counts as "I'm up":
     *  cancel the pending re-ring and confirm it (so the tap isn't a silent
     *  app-open). The notification auto-cancels on tap. */
    private fun handleWakeCheckAck(intent: Intent?) {
        if (intent?.getBooleanExtra(WakeCheckScheduler.EXTRA_ACK, false) != true) return
        val id = intent.getIntExtra(WakeCheckScheduler.EXTRA_ALARM_ID, -1)
        if (id < 0) return
        WakeCheckScheduler.cancel(applicationContext, id)
        Toast.makeText(this, "You're up — nice one 👋", Toast.LENGTH_SHORT).show()
    }
}
