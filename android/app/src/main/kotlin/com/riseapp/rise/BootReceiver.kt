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
import io.flutter.plugins.GeneratedPluginRegistrant

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

        // Belt-and-suspenders: FlutterEngine's own constructor already
        // auto-registers the app's plugins (it reflectively invokes this
        // exact call via GeneratedPluginRegister, gated on
        // FlutterLoader#automaticallyRegisterPlugins(), which defaults to
        // true and is not overridden anywhere in this app's manifest) —
        // verified both by decompiling the engine and by an actual reboot
        // with this call removed, which still reconciled successfully with
        // no MissingPluginException. Kept explicit anyway so reconcile does
        // not silently start depending on that default: if a future change
        // to this app (an AndroidManifest meta-data override) or to Flutter
        // itself ever turns automatic registration off, the headless engine
        // still gets its plugins — timezone lookup, path_provider, and the
        // sqlite native libs all go through MethodChannels that throw
        // MissingPluginException without this. Calling registerWith twice on
        // one engine is safe (each plugin's onAttachedToEngine just runs
        // again). Must happen before the Dart entrypoint executes so the
        // channels are wired up before Dart code can call them.
        GeneratedPluginRegistrant.registerWith(engine)

        engine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "reconcileEntrypoint")
        )
        AlarmHostApi.setUp(engine.dartExecutor.binaryMessenger, AlarmHostApiImpl(app, engine))

        // The engine must outlive onReceive() or reconcile is killed mid-flight.
        FlutterEngineHolder.retain(engine)
    }
}

/**
 * Keeps headless reconcile engines alive until their own reconcile finishes,
 * then tears down that one engine. Without this, every boot / app-update /
 * clock-change reconcile leaks a full Dart isolate until the OS kills the
 * process.
 *
 * Release is scoped per-engine rather than "release everything retained" —
 * BOOT_COMPLETED and a clock-driven TIME_CHANGED/TIMEZONE_CHANGED can each
 * spin up their own engine and land close together. A blanket release would
 * let the first engine to finish destroy a sibling engine's isolate
 * mid-flight, possibly before it had read the database or armed anything.
 */
object FlutterEngineHolder {
    private val lock = Any()
    private val engines = mutableListOf<FlutterEngine>()

    fun retain(engine: FlutterEngine) {
        synchronized(lock) { engines.add(engine) }
    }

    /**
     * Destroys exactly [engine] and forgets about it — every other retained
     * engine is left running.
     *
     * Safe to call from any thread — [FlutterEngine.destroy] must run on the
     * platform thread, but this is invoked from a Pigeon channel callback,
     * which is not guaranteed to already be there, so the actual teardown is
     * posted to the main looper rather than run inline.
     *
     * Also safe to call more than once for the same engine, including
     * concurrently or re-entrantly: removal from the retained list happens
     * under a lock and [MutableList.remove] reports whether it actually
     * removed anything, so only the call that wins the race schedules
     * [FlutterEngine.destroy]; a repeat call for an engine already released
     * (or never retained) is a no-op.
     */
    fun release(engine: FlutterEngine) {
        val removed = synchronized(lock) { engines.remove(engine) }
        if (!removed) return
        Handler(Looper.getMainLooper()).post { engine.destroy() }
    }
}
