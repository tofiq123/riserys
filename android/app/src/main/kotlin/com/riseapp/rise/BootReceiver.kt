package com.riseapp.rise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The scheduled set does not survive reboot, app replacement, or a clock
 * change. Each of these spins up a headless Flutter engine whose only job is
 * to re-run reconcile from the local database and recover a missed alarm.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.i("BootReceiver", "received $action; re-running reconcile")

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> startReconcileEngine(context)
            else -> return
        }
    }

    private fun startReconcileEngine(context: Context) {
        val app = context.applicationContext

        // On a cold boot nothing has initialized the Flutter loader yet, so the
        // engine cannot find the app bundle. This must happen before the engine
        // is constructed.
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)

        val engine = FlutterEngine(app)
        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "reconcileEntrypoint")
        )
        AlarmHostApi.setUp(engine.dartExecutor.binaryMessenger, AlarmHostApiImpl(app))

        // The engine must outlive onReceive() or reconcile is killed mid-flight.
        FlutterEngineHolder.retain(engine)
    }
}

/** Keeps headless engines alive until their reconcile finishes. */
object FlutterEngineHolder {
    private val engines = mutableListOf<FlutterEngine>()

    fun retain(engine: FlutterEngine) {
        engines.add(engine)
    }

    fun releaseAll() {
        engines.forEach { it.destroy() }
        engines.clear()
    }
}
