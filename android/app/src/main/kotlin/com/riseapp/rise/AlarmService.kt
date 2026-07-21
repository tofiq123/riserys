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

/**
 * Owns the ringing lifetime: audio on the alarm stream, vibration, wake lock,
 * and the full-screen notification that launches [RingActivity].
 */
class AlarmService : Service() {

    companion object {
        private const val TAG = "AlarmService"
        private const val CHANNEL_ID = "rise_alarms"
        private const val NOTIF_ID = 4242

        /** Which alarm is ringing right now, if any. Read on cold start. */
        var ringingAlarmId: Int? = null
            private set

        fun stop(context: Context) {
            context.stopService(Intent(context, AlarmService::class.java))
        }
    }

    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private var rampStep = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Tear down any previously ringing alarm's resources first. Without
        // this, a second onStartCommand on a still-live service (e.g. another
        // alarm firing while one is already ringing) would overwrite `player`
        // and `wakeLock` with new instances, orphaning the old MediaPlayer —
        // which loops forever with no reference left to stop it — and
        // leaking the old WakeLock until its 10-minute timeout. This is not
        // deletable as "redundant": on the very first start there is nothing
        // held yet, and releaseResources() is safe to call in that case.
        releaseResources()

        val id = intent?.getIntExtra(AlarmScheduler.EXTRA_ALARM_ID, -1) ?: -1
        val label = intent?.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "Alarm"
        val sound = intent?.getStringExtra(AlarmScheduler.EXTRA_SOUND) ?: ""
        val vibrate = intent?.getBooleanExtra(AlarmScheduler.EXTRA_VIBRATE, true) ?: true
        Log.i(TAG, "ringing alarm $id")

        ringingAlarmId = id
        createChannel()
        startForeground(NOTIF_ID, buildNotification(id, label))

        acquireWakeLock()
        startAudio(sound)
        if (vibrate) startVibration()

        // START_REDELIVER_INTENT: if the system kills us under memory
        // pressure while an alarm is ringing, come back with the *same*
        // Intent we were last started with, so the restarted service still
        // knows which alarm (id/label/vibrate) it's ringing. START_STICKY
        // would restart us with a null Intent instead, losing that identity
        // and falling back to the id=-1 sentinel throughout the pipeline.
        return START_REDELIVER_INTENT
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
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
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
     *  - a bundled tone asset (`sounds/rise_sunrise.wav`) -> `R.raw.rise_sunrise`
     *    via getIdentifier; an unknown name (id 0) returns false.
     * A missing/empty file returns false; a corrupt file lets setDataSource
     * throw, which startAudio catches and recovers from with the default.
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
        // Bundled raw resource: "sounds/rise_sunrise.wav" -> "rise_sunrise".
        val name = soundAsset.substringAfterLast('/').substringBeforeLast('.')
        if (name.isEmpty()) return false
        val resId = resources.getIdentifier(name, "raw", packageName)
        if (resId == 0) return false
        resources.openRawResourceFd(resId).use { afd ->
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
        }
        return true
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

    private fun startVibration() {
        // Intermittent patterns rouse better than continuous buzzing.
        val timings = longArrayOf(0, 600, 400, 600, 400)
        val amplitudes = intArrayOf(0, 255, 0, 255, 0)
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
        super.onDestroy()
    }
}
