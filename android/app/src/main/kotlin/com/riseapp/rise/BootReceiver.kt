package com.riseapp.rise

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
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

/**
 * Keeps headless reconcile engines alive until their reconcile finishes, then
 * tears them down. Without this, every boot / app-update / clock-change
 * reconcile leaks a full Dart isolate until the OS kills the process.
 */
object FlutterEngineHolder {
    private val lock = Any()
    private val engines = mutableListOf<FlutterEngine>()

    fun retain(engine: FlutterEngine) {
        synchronized(lock) { engines.add(engine) }
    }

    /**
     * Destroys every retained headless engine and forgets about it.
     *
     * Safe to call from any thread — [FlutterEngine.destroy] must run on the
     * platform thread, but this is invoked from a Pigeon channel callback,
     * which is not guaranteed to already be there, so the actual teardown is
     * posted to the main looper rather than run inline.
     *
     * Also safe to call more than once, including concurrently or
     * re-entrantly: the retained list is snapshotted and cleared under a lock
     * before anything is destroyed, so an overlapping call sees nothing left
     * to release and never destroys an engine twice or while it is already
     * mid-teardown.
     */
    fun releaseAll() {
        val toRelease: List<FlutterEngine>
        synchronized(lock) {
            if (engines.isEmpty()) return
            toRelease = engines.toList()
            engines.clear()
        }
        Handler(Looper.getMainLooper()).post {
            toRelease.forEach { it.destroy() }
        }
    }
}
