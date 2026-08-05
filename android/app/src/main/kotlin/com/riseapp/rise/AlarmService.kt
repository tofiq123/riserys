package com.riseapp.rise

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/**
 * One alarm's ringing payload: everything needed to start or resume playing
 * it, captured off the triggering [Intent] so it can be replayed later
 * (queued behind another alarm, or restored after a process restart)
 * without the original Intent still being around.
 */
data class RingRequest(
    val id: Int,
    val label: String,
    val sound: String,
    val vibrate: Boolean,
    val vibrationPattern: String,
) {
    companion object {
        fun fromIntent(intent: Intent?): RingRequest = RingRequest(
            id = intent?.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1) ?: -1,
            label = intent?.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "Alarm",
            sound = intent?.getStringExtra(AlarmScheduler.EXTRA_SOUND) ?: "",
            vibrate = intent?.getBooleanExtra(AlarmScheduler.EXTRA_VIBRATE, true) ?: true,
            vibrationPattern = intent?.getStringExtra(AlarmScheduler.EXTRA_VIBRATION_PATTERN)
                ?: "standard",
        )

        fun toJson(request: RingRequest): JSONObject = JSONObject().apply {
            put("id", request.id)
            put("label", request.label)
            put("sound", request.sound)
            put("vibrate", request.vibrate)
            put("vibrationPattern", request.vibrationPattern)
        }

        fun fromJson(json: JSONObject): RingRequest = RingRequest(
            id = json.getInt("id"),
            label = json.getString("label"),
            sound = json.getString("sound"),
            vibrate = json.getBoolean("vibrate"),
            vibrationPattern = json.getString("vibrationPattern"),
        )
    }
}

/**
 * Owns the ringing lifetime: audio on the alarm stream, vibration, wake lock,
 * and the full-screen notification that launches [RingActivity]. Also owns a
 * FIFO queue of alarms that fired while another was already ringing — see
 * docs/superpowers/specs/2026-08-05-alarm-ring-queue-design.md.
 */
class AlarmService : Service() {

    companion object {
        private const val TAG = "AlarmService"
        private const val CHANNEL_ID = "rise_alarms"
        private const val NOTIF_ID = 4242
        private const val PREFS = "rise_ring_queue"
        private const val KEY_QUEUE = "queue"
        private const val KEY_SAVED_AT = "savedAt"

        /**
         * An overlapping-ring queue only ever needs to live for the minutes
         * it takes a person to deal with the first alarm. Anything older than
         * this on load is leftover from a session that never came back
         * naturally (a kill with no restart, or a reboot) — too stale to
         * trust, and dangerous to keep: replaying it into a later, unrelated
         * ring session could resurrect an alarm the user has since deleted.
         */
        private const val STALE_QUEUE_MS = 30 * 60 * 1000L

        /** Which alarm is ringing right now, if any. Read on cold start. */
        var ringingAlarmId: Int? = null
            private set

        /** Alarms that fired while another was already ringing, oldest first. */
        val ringQueue: MutableList<RingRequest> = mutableListOf()

        /** The next queued alarm's id, or null. Peeks — does not dequeue. */
        val queuedAlarmId: Int?
            get() = ringQueue.firstOrNull()?.id

        private var runningInstance: AlarmService? = null

        /**
         * Ends the current ring. If another alarm is queued behind it, hands
         * off to that one directly instead of tearing the service down — no
         * stopService/startForegroundService round trip, so there is no gap
         * where the OS could reap the service between the two.
         */
        fun stop(context: Context) {
            val svc = runningInstance
            if (svc != null && ringQueue.isNotEmpty()) {
                svc.advanceToNext()
            } else {
                context.stopService(Intent(context, AlarmService::class.java))
            }
        }

        /**
         * Restores the queue after a process restart. `ringingAlarmId` itself
         * is deliberately NOT persisted: `START_REDELIVER_INTENT` already
         * redelivers the currently-ringing alarm's own Intent, which drives
         * [onStartCommand]'s normal `ringingAlarmId == null` → [beginRinging]
         * path. Only the alarms waiting *behind* it would otherwise be lost.
         *
         * Discards (and clears) anything older than [STALE_QUEUE_MS] — see
         * its doc comment for why an old queue must never be trusted.
         */
        private fun loadQueue(context: Context): MutableList<RingRequest> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val raw = prefs.getString(KEY_QUEUE, null) ?: return mutableListOf()
            val savedAt = prefs.getLong(KEY_SAVED_AT, 0L)
            if (System.currentTimeMillis() - savedAt > STALE_QUEUE_MS) {
                prefs.edit().remove(KEY_QUEUE).remove(KEY_SAVED_AT).apply()
                return mutableListOf()
            }
            return try {
                val array = JSONArray(raw)
                MutableList(array.length()) { i -> RingRequest.fromJson(array.getJSONObject(i)) }
            } catch (e: Exception) {
                Log.w(TAG, "could not restore ring queue", e)
                mutableListOf()
            }
        }

        /**
         * Removes any queued entry for [alarmId] — the alarm was deleted or
         * disabled while it was waiting behind another ringing alarm.
         * [reconcile]'s cancellation only reaches AlarmManager's future
         * schedule, not an alarm that already fired and is sitting in this
         * queue, so this is the only way to stop it from ringing anyway.
         * Safe to call whether or not the id is actually queued.
         */
        fun removeFromQueue(context: Context, alarmId: Int) {
            if (ringQueue.removeAll { it.id == alarmId }) {
                saveQueue(context)
            }
        }

        private fun saveQueue(context: Context) {
            val array = JSONArray()
            ringQueue.forEach { array.put(RingRequest.toJson(it)) }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_QUEUE, array.toString())
                .putLong(KEY_SAVED_AT, System.currentTimeMillis())
                .apply()
        }
    }

    /** The request currently ringing (mirrors [ringingAlarmId], plus label/sound/etc). */
    private var current: RingRequest? = null
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var rampStep = 0

    override fun onCreate() {
        super.onCreate()
        runningInstance = this
        ringQueue.clear()
        ringQueue.addAll(loadQueue(this))
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val request = RingRequest.fromIntent(intent)
        Log.i(TAG, "onStartCommand alarm ${request.id}, currently ringing $ringingAlarmId")

        when {
            ringingAlarmId == null -> beginRinging(request)
            request.id == ringingAlarmId -> {
                // Redelivery of the alarm already ringing (e.g. a process
                // restart via START_REDELIVER_INTENT) — nothing to do.
            }
            else -> {
                // Another alarm is already ringing: queue this one rather
                // than interrupting it. Still must call startForeground()
                // for THIS startForegroundService() call to satisfy the
                // platform contract, reusing the currently-ringing alarm's
                // own notification content so nothing about its active ring
                // changes.
                ringQueue.add(request)
                saveQueue(this)
                current?.let { startForeground(NOTIF_ID, buildNotification(it.id, it.label)) }
            }
        }
        // START_REDELIVER_INTENT: if the system kills us under memory
        // pressure while an alarm is ringing, come back with the *same*
        // Intent we were last started with, so the restarted service still
        // knows which alarm (id/label/vibrate) it's ringing. START_STICKY
        // would restart us with a null Intent instead, losing that identity
        // and falling back to the id=-1 sentinel throughout the pipeline.
        return START_REDELIVER_INTENT
    }

    private fun beginRinging(request: RingRequest) {
        Log.i(TAG, "ringing alarm ${request.id}")
        releaseResources()
        current = request
        ringingAlarmId = request.id
        createChannel()
        startForeground(NOTIF_ID, buildNotification(request.id, request.label))
        acquireWakeLock()
        startAudio(request.sound)
        if (request.vibrate) startVibration(request.vibrationPattern)
    }

    private fun advanceToNext() {
        val next = ringQueue.removeAt(0)
        saveQueue(this)
        beginRinging(next)
    }

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Alarms",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Rise alarms ringing"
            // We own audio and vibration ourselves via the alarm stream.
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    private fun buildNotification(id: Int, label: String): android.app.Notification {
        val fullScreen = PendingIntent.getActivity(
            this,
            id,
            Intent(this, RingActivity::class.java)
                .putExtra(AlarmScheduler.EXTRA_ALARM_ID, id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(label)
            .setContentText("Tap to wake up")
            .setSmallIcon(R.drawable.ic_stat_rise)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOngoing(true)
            .setAutoCancel(false)
            // The whole point: launch the ringing UI over the lock screen.
            .setFullScreenIntent(fullScreen, true)
            .build()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(PowerManager::class.java)
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "rise:alarm"
        ).apply { acquire(10 * 60 * 1000L) }
    }

    private fun startAudio(soundAsset: String) {
        Log.i(TAG, "startAudio sound='$soundAsset'")
        // USAGE_ALARM routes to the dedicated alarm volume stream, which is
        // immune to media mute and to the ringer being silenced.
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        // Built by hand rather than MediaPlayer.create(): create() prepares
        // immediately, and audio attributes set after prepare are ignored —
        // the alarm would silently play on the media stream and be muted.
        player = MediaPlayer().apply {
            setAudioAttributes(attrs)
            // Play the alarm's SELECTED sound; on ANY failure to resolve or set
            // it, fall back to the bundled default so the alarm always rings.
            // reset() drops the audio attributes, so re-apply them before the
            // fallback source.
            try {
                if (!setSelectedSource(this, soundAsset)) setDefaultSource(this)
            } catch (e: Exception) {
                Log.w(TAG, "sound '$soundAsset' failed; using default", e)
                reset()
                setAudioAttributes(attrs)
                setDefaultSource(this)
            }
            isLooping = true
            // Gentle start: ramp from low to full over 60 s. Abrupt waking
            // spikes the morning blood-pressure surge.
            setVolume(0.15f, 0.15f)
            prepare()
            start()
        }
        rampStep = 0
        scheduleRamp()
    }

    /** The guaranteed-present bundled fallback tone. */
    private fun setDefaultSource(mp: MediaPlayer) {
        resources.openRawResourceFd(R.raw.default_alarm).use { afd ->
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
        }
    }

    /**
     * Points [mp] at the alarm's chosen sound. Returns true when a source was
     * set; false means "not resolvable — caller must use the default" so the
     * alarm never goes silent. Two source kinds, in priority order:
     *  - an absolute local file (a downloaded voice clip): `/...` or `file://...`
     *  - a bundled tone (`sounds/rise_sunrise.ogg`), played from the FLUTTER
     *    ASSET BUNDLE (`flutter_assets/assets/sounds/rise_sunrise.ogg`) — the same
     *    file the picker previews. The `res/raw` copies are NOT included in
     *    release builds (unreferenced raw resources get dropped), so the old
     *    `getIdentifier(..., "raw")` returned 0 there and EVERY alarm fell back to
     *    the default. A missing/unreadable asset returns false; startAudio then
     *    rings the guaranteed default, so the alarm is never silent.
     */
    private fun setSelectedSource(mp: MediaPlayer, soundAsset: String): Boolean {
        if (soundAsset.isBlank()) return false
        // Voice-as-alarm: a downloaded clip stored as an absolute file path.
        if (soundAsset.startsWith("/") || soundAsset.startsWith("file://")) {
            val path =
                if (soundAsset.startsWith("file://")) Uri.parse(soundAsset).path
                else soundAsset
            if (path.isNullOrEmpty() || !File(path).exists()) return false
            mp.setDataSource(path)
            return true
        }
        // Bundled tone from the Flutter asset bundle. The Dart soundAsset is a
        // bundle-relative key like "sounds/rise_klaxon.ogg"; the app declares its
        // assets under `assets/`, so inside the APK the file lives at
        // flutter_assets/assets/sounds/rise_klaxon.ogg. The .ogg assets are stored
        // uncompressed, so openFd hands MediaPlayer a real file descriptor.
        val assetPath = "flutter_assets/assets/$soundAsset"
        return try {
            assets.openFd(assetPath).use { afd ->
                mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "sound asset '$assetPath' not playable; using default", e)
            false
        }
    }

    /** VibratorManager is API 31+; minSdk is 26. */
    private fun vibrator(): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Vibrator::class.java)
        }

    private fun scheduleRamp() {
        handler.postDelayed({
            rampStep++
            val v = (0.15f + (0.85f * rampStep / 12f)).coerceAtMost(1.0f)
            player?.setVolume(v, v)
            if (rampStep < 12) scheduleRamp()
        }, 5000) // 12 steps x 5 s = 60 s
    }

    /**
     * Starts the looping ring vibration for [pattern]:
     *  - "gentle":   short soft pulses  — timings [0,300,700], amplitude 140
     *  - "standard": today's pattern    — timings [0,600,400,600,400], amp 255
     *  - "intense":  long hard pulses,
     *    shorter gaps                   — timings [0,900,200,900,200], amp 255
     * Intermittent patterns rouse better than continuous buzzing. Any unknown
     * key (an older native build receiving a newer pattern, or a corrupt
     * value) falls back to "standard" — the pattern choice must never be able
     * to silence the alarm's vibration.
     */
    private fun startVibration(pattern: String) {
        val (timings, amplitudes) = when (pattern) {
            "gentle" -> longArrayOf(0, 300, 700) to intArrayOf(0, 140, 0)
            "intense" -> longArrayOf(0, 900, 200, 900, 200) to intArrayOf(0, 255, 0, 255, 0)
            else -> longArrayOf(0, 600, 400, 600, 400) to intArrayOf(0, 255, 0, 255, 0)
        }
        vibrator().vibrate(VibrationEffect.createWaveform(timings, amplitudes, 1))
    }

    /**
     * Tears down everything a ringing alarm holds: pending handler callbacks,
     * the MediaPlayer, vibration, and the wake lock. Safe to call when none
     * of these are currently held (e.g. the first onStartCommand call).
     */
    private fun releaseResources() {
        handler.removeCallbacksAndMessages(null)
        player?.run { if (isPlaying) stop(); release() }
        player = null
        vibrator().cancel()
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    override fun onDestroy() {
        Log.i(TAG, "stopping alarm ${ringingAlarmId}")
        releaseResources()
        ringingAlarmId = null
        current = null
        runningInstance = null
        super.onDestroy()
    }
}
