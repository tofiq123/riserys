package com.riseapp.rise

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
}
