# Overlapping-alarms ring queue — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a second alarm fires while one is already ringing, it queues
behind the first instead of clobbering it — the first alarm's audio,
vibration, and mission state ring uninterrupted, and the queued alarm starts
automatically when the first is dismissed or snoozed.

**Architecture:** `AlarmService` (Android foreground service) gains a
persisted FIFO queue next to its existing single `ringingAlarmId` slot. A new
Pigeon method (`getQueuedAlarmId`) lets `RingScreen` show a quiet "next: X
queued" indicator, polled the same way `getRingingAlarmId` already is. No
change to `main.dart`'s ring-reconciliation logic is needed — it is already
correct once the native layer stops changing `ringingAlarmId` prematurely.

**Tech Stack:** Flutter/Dart, Kotlin (Android, JDK 21 / SDK 36), Pigeon
`^26.3.4`, `org.json` (Android SDK built-in, no new dependency), Riverpod
2.6.1 (existing usage only, unchanged).

**Spec:** `docs/superpowers/specs/2026-08-05-alarm-ring-queue-design.md`

## Global Constraints

- `flutter analyze` must be clean before any commit.
- Never bulk-edit `.dart`/`.kt`/`.swift` files with PowerShell `Get-Content`/
  `Set-Content` — it corrupts non-ASCII characters (em-dashes appear in this
  codebase's comments). Use the Edit tool for all source edits in this plan.
- `flutter test` must stay green (1222+ tests) — this plan adds tests, never
  removes or skips them.
- The alarm path is sacred: ring, dismiss, snooze, and scheduling are the
  product. Every native change in this plan must fail safe — if anything
  about the queue goes wrong, the currently-ringing alarm must still be
  stoppable and the service must still eventually settle to a known state.
- This feature is Android-only. Do not touch `ios/Runner/AlarmHostApiImpl.swift`
  beyond the one-line stub needed to keep the generated Swift protocol
  satisfied — the iOS engine has never been compiled and is out of scope.
- Never edit generated files (`lib/data/native/alarm_api.g.dart`,
  `android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt`,
  `ios/Runner/AlarmApi.g.swift`) by hand. They are produced by
  `dart run pigeon --input pigeons/alarm_api.dart` and are committed (this
  repo force-adds them past `*.g.dart` in `.gitignore` — Drift codegen is
  ignored, Pigeon output is not).
- Pigeon maps Dart `int` to Kotlin `Long`. Convert with `.toInt()` /
  `.toLong()` at the Kotlin call site rather than editing the generated
  signature.

---

### Task 1: Pigeon contract + Android native ring queue

**Files:**
- Modify: `pigeons/alarm_api.dart` (add `getQueuedAlarmId` to `AlarmHostApi`)
- Regenerate: `lib/data/native/alarm_api.g.dart`,
  `android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt`,
  `ios/Runner/AlarmApi.g.swift`
- Modify: `android/app/src/main/kotlin/com/riseapp/rise/AlarmService.kt`
  (full rewrite — queue, persistence, `beginRinging`/`advanceToNext`)
- Modify: `android/app/src/main/kotlin/com/riseapp/rise/AlarmHostApiImpl.kt:99-104`
  (add `getQueuedAlarmId` override)
- Modify: `ios/Runner/AlarmHostApiImpl.swift:203-205` (add a one-line stub so
  the Swift protocol conformance still compiles — see step 6)

**Interfaces:**
- Consumes: `AlarmScheduler.EXTRA_ALARM_ID` / `EXTRA_LABEL` / `EXTRA_SOUND` /
  `EXTRA_VIBRATE` / `EXTRA_VIBRATION_PATTERN` (existing constants, unchanged).
- Produces:
  - Kotlin: `AlarmService.queuedAlarmId: Int?` (companion property, peek-only).
  - Kotlin: `AlarmService.RingRequest` data class (`id, label, sound, vibrate, vibrationPattern`).
  - Dart: `AlarmHostApi().getQueuedAlarmId(): Future<int?>` — Task 2 calls this.

- [ ] **Step 1: Add the Pigeon method**

Edit `pigeons/alarm_api.dart`. Insert immediately after the existing
`getRingingAlarmId()` declaration (currently lines 117–128, ending
`int? getRingingAlarmId();`) and before `void stopRinging(int alarmId);`:

```dart
  /// The next alarm waiting behind the one currently ringing, or null.
  /// Peeks like [getRingingAlarmId] — does not clear state, poll it.
  int? getQueuedAlarmId();
```

- [ ] **Step 2: Regenerate the Pigeon bindings**

Run: `dart run pigeon --input pigeons/alarm_api.dart`

Expected: exits 0, and `git status --short` shows modifications to
`lib/data/native/alarm_api.g.dart`,
`android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt`, and
`ios/Runner/AlarmApi.g.swift`. Do not hand-edit any of the three.

- [ ] **Step 3: Rewrite `AlarmService.kt`**

Replace the full contents of
`android/app/src/main/kotlin/com/riseapp/rise/AlarmService.kt` with:

```kotlin
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
```

- [ ] **Step 4: Wire `getQueuedAlarmId` into `AlarmHostApiImpl.kt`**

Edit `android/app/src/main/kotlin/com/riseapp/rise/AlarmHostApiImpl.kt`. The
existing `getRingingAlarmId` override reads:

```kotlin
    // Peeks at the currently ringing alarm; does not clear state. See the
    // Pigeon doc comment on getRingingAlarmId for why this must stay a peek.
    override fun getRingingAlarmId(): Long? {
        val id = AlarmService.ringingAlarmId ?: return null
        return id.toLong()
    }
```

Add immediately after it:

```kotlin

    // Peeks at the next queued alarm; does not dequeue. See the Pigeon doc
    // comment on getQueuedAlarmId.
    override fun getQueuedAlarmId(): Long? {
        val id = AlarmService.queuedAlarmId ?: return null
        return id.toLong()
    }
```

- [ ] **Step 5: iOS stub (keeps the generated Swift protocol satisfied)**

Edit `ios/Runner/AlarmHostApiImpl.swift`. The existing `getRingingAlarmId`
reads:

```swift
  func getRingingAlarmId() throws -> Int64? {
    return ringingAlarmId
  }
```

Add immediately after it:

```swift

  // iOS has no single-service ring model to queue behind — each alarm is
  // its own local notification and the OS delivers them independently, so
  // there is nothing to report as "queued." Always nil.
  func getQueuedAlarmId() throws -> Int64? {
    return nil
  }
```

This file is not compiled in this environment (no Mac toolchain) — this step
only keeps it from being a known break for the eventual iOS compile-and-fix
pass.

- [ ] **Step 6: Build to verify**

Run: `flutter build apk --debug 2>&1 | tail -30`

Expected: `✓ Built build\app\outputs\flutter-apk\app-debug.apk` (or
equivalent success line), no Kotlin compile errors. If the Kotlin compiler
reports a type mismatch on `id`/`alarmId` (`Int` vs `Long`), fix it with
`.toInt()`/`.toLong()` at the call site — do not edit `AlarmApi.g.kt`.

- [ ] **Step 7: Commit**

```bash
git add -f pigeons/ lib/data/native/alarm_api.g.dart \
  android/app/src/main/kotlin/com/riseapp/rise/AlarmApi.g.kt \
  ios/Runner/AlarmApi.g.swift
git add android/app/src/main/kotlin/com/riseapp/rise/AlarmService.kt \
  android/app/src/main/kotlin/com/riseapp/rise/AlarmHostApiImpl.kt \
  ios/Runner/AlarmHostApiImpl.swift
git commit -m "feat(alarm): native ring queue — overlapping alarms no longer clobber"
```

---

### Task 2: `RingScreen` queued-alarm chip

**Files:**
- Modify: `lib/ui/screens/ring_screen.dart` (add `getQueuedAlarmId` field,
  `_queuedAlarmId` state, poll, chip UI)
- Test: `test/ui/screens/ring_screen_test.dart`

**Interfaces:**
- Consumes: `AlarmHostApi().getQueuedAlarmId(): Future<int?>` (Task 1).
  `alarmsProvider` (existing, `AsyncValue<List<Alarm>>`) for label lookup —
  same provider `build()` already watches for the ringing alarm's own label.
- Produces: `RingScreen(..., getQueuedAlarmId: Future<int?> Function())` —
  no other task depends on this; it is the last piece of the feature.

- [ ] **Step 1: Write the failing tests**

Edit `test/ui/screens/ring_screen_test.dart`. Add `getQueuedAlarmId` to the
`_host()` helper's parameter list and pass it through to `RingScreen`:

```dart
Widget _host({
  required List<Alarm> alarms,
  required int alarmId,
  Future<void> Function(int)? dismissAlarm,
  VoidCallback? onDismissed,
  MissionBuilder? missionBuilder,
  RiseSettings settings = const RiseSettings(),
  List<WakeEvent> wakeEvents = const [],
  Future<void> Function(int, Duration)? snooze,
  bool record = false,
  WakeRecorder? recorder,
  Future<void> Function(Alarm, Duration)? armWakeCheck,
  Future<void> Function(int)? cancelWakeCheck,
  StayUpDecider? stayUpDecision,
  BrightnessController? brightness,
  Future<int?> Function()? getQueuedAlarmId,
}) {
  return ProviderScope(
    overrides: [
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      currentSettingsProvider.overrideWithValue(settings),
      wakeEventsProvider.overrideWith((ref) => Stream.value(wakeEvents)),
      if (recorder != null) wakeRecorderProvider.overrideWithValue(recorder),
    ],
    child: MaterialApp(
      home: RingScreen(
        alarmId: alarmId,
        onDismissed: onDismissed,
        dismissAlarm: dismissAlarm ?? (_) async {},
        missionBuilder: missionBuilder,
        snooze: snooze ?? (_, __) async {},
        record: record,
        armWakeCheck: armWakeCheck ?? (_, __) async {},
        cancelWakeCheck: cancelWakeCheck ?? (_) async {},
        stayUpDecision: stayUpDecision ?? defaultStayUpDecision,
        brightness: brightness ?? const NoopBrightnessController(),
        getQueuedAlarmId: getQueuedAlarmId ?? () async => null,
      ),
    ),
  );
}
```

Add three new tests, anywhere alongside the other `testWidgets` calls in the
file:

```dart
  testWidgets('shows a queued-alarm chip when another alarm is waiting',
      (t) async {
    await t.pumpWidget(_host(
      alarms: const [
        Alarm(id: 5, hour: 6, minute: 30, label: 'Run'),
        Alarm(id: 9, hour: 6, minute: 32, label: 'Backup'),
      ],
      alarmId: 5,
      getQueuedAlarmId: () async => 9,
    ));
    await t.pump();
    expect(find.text('Next: Backup queued'), findsOneWidget);
  });

  testWidgets('shows no chip when nothing is queued', (t) async {
    await t.pumpWidget(_host(
      alarms: const [Alarm(id: 5, hour: 6, minute: 30, label: 'Run')],
      alarmId: 5,
      getQueuedAlarmId: () async => null,
    ));
    await t.pump();
    expect(find.textContaining('queued'), findsNothing);
  });

  testWidgets('chip appears once a second alarm queues while ringing',
      (t) async {
    int? queued;
    await t.pumpWidget(_host(
      alarms: const [
        Alarm(id: 5, hour: 6, minute: 30, label: 'Run'),
        Alarm(id: 9, hour: 6, minute: 32, label: 'Backup'),
      ],
      alarmId: 5,
      getQueuedAlarmId: () async => queued,
    ));
    await t.pump();
    expect(find.textContaining('queued'), findsNothing);

    queued = 9;
    await t.pump(const Duration(seconds: 1));
    await t.pump();
    expect(find.text('Next: Backup queued'), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ui/screens/ring_screen_test.dart`

Expected: FAIL to compile — `The named parameter 'getQueuedAlarmId' isn't
defined` (both in `_host()`'s call to `RingScreen` and in the new tests).

- [ ] **Step 3: Add the field, state, poll, and chip**

Edit `lib/ui/screens/ring_screen.dart`.

In the `RingScreen` constructor (currently ending at `this.brightness = const
ScreenBrightnessController(),`), add a new parameter and field:

```dart
class RingScreen extends ConsumerStatefulWidget {
  const RingScreen({
    super.key,
    required this.alarmId,
    this.onDismissed,
    this.dismissAlarm = dismissRingingAlarm,
    this.missionBuilder,
    this.record = false,
    this.snooze = snoozeAlarm,
    this.armWakeCheck = defaultArmWakeCheck,
    this.cancelWakeCheck = defaultCancelWakeCheck,
    this.stayUpDecision = defaultStayUpDecision,
    this.brightness = const ScreenBrightnessController(),
    this.getQueuedAlarmId = defaultGetQueuedAlarmId,
  });
```

and, alongside the other injectable-function doc comments (near `snooze`):

```dart
  /// The alarm waiting behind this one, if any. Injectable for tests;
  /// defaults to [defaultGetQueuedAlarmId]. Polled, not pushed — see the
  /// Pigeon doc comment on `getQueuedAlarmId`.
  final Future<int?> Function() getQueuedAlarmId;
```

Add a top-level default next to `dismissRingingAlarm`/`snoozeAlarm` (near the
top of the file, after the `dismissRingingAlarm` function):

```dart
/// Peeks the next alarm queued behind the one currently ringing.
Future<int?> defaultGetQueuedAlarmId() => AlarmHostApi().getQueuedAlarmId();
```

In `_RingScreenState`, add state next to the other flags (near `_elapsedSec`):

```dart
  /// The alarm queued behind this one, if any — polled, not pushed.
  int? _queuedAlarmId;
```

In `initState()`, poll once immediately and then on every clock tick:

```dart
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.92,
      upperBound: 1.08,
    ); // started in didChangeDependencies, only when animations are enabled
    _sunrise = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 45),
    );
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSec++); // advances the live clock + auto-SOS timer
      _maybeAutoSos();
      _pollQueuedAlarm();
    });
    if (widget.record) _recordRingStart();
    _pollQueuedAlarm();
  }

  /// A thrown PlatformException must not go unhandled here, or a single
  /// failed poll would crash the ring screen — the chip is a nice-to-have,
  /// never load-bearing for dismissing the alarm.
  Future<void> _pollQueuedAlarm() async {
    int? id;
    try {
      id = await widget.getQueuedAlarmId();
    } catch (e) {
      debugPrint('Rise: could not check for a queued alarm: $e');
      return;
    }
    if (!mounted || id == _queuedAlarmId) return;
    setState(() => _queuedAlarmId = id);
  }
```

In `build()`, resolve the queued alarm's label the same way `label` is
already resolved (right after the existing `final label = alarm?.label ??
'Alarm';` line):

```dart
    final label = alarm?.label ?? 'Alarm';
    final queuedLabel = _queuedAlarmId == null
        ? null
        : (ref
                .watch(alarmsProvider)
                .value
                ?.firstWhereOrNull((a) => a.id == _queuedAlarmId)
                ?.label ??
            'Alarm');
```

Render the chip right after the label `Text` widget (currently `Text(label,
style: RiseText.title.copyWith(color: RiseColors.textDim)),`):

```dart
            Text(label,
                style: RiseText.title.copyWith(color: RiseColors.textDim)),
            if (_queuedAlarmId != null) ...[
              const SizedBox(height: 8),
              Text('Next: $queuedLabel queued',
                  style: RiseText.body.copyWith(color: RiseColors.textDim)),
            ],
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/screens/ring_screen_test.dart`

Expected: PASS, all tests including the three new ones. Also run the full
suite to confirm no regression: `flutter test`. Expected: PASS, 1222+ tests.

- [ ] **Step 5: Analyze**

Run: `flutter analyze`

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/ui/screens/ring_screen.dart test/ui/screens/ring_screen_test.dart
git commit -m "feat(alarm): show the next queued alarm on the ring screen"
```

---

### Task 3: Device verification (required — the ring path is sacred)

This task has no automated steps; it is a manual pass on a physical device,
matching this repo's existing convention for native alarm-path changes (see
`docs/superpowers/reliability/`).

**Prerequisites:**
- A build with the real backend config: `flutter build apk --debug
  --dart-define-from-file=rise.env.json`
- Install on the connected device: `adb install -r
  build/app/outputs/flutter-apk/app-debug.apk`

- [ ] **Step 1: Set up two overlapping alarms**

In the app, create two alarms a few minutes apart (e.g. now + 2 min and now +
3 min), each with a different label and a mission on at least one of them.

- [ ] **Step 2: Confirm the first alarm rings uninterrupted**

Let the first alarm fire. Confirm it rings normally (sound, vibration,
full-screen ring UI). While it is still ringing, let the second alarm's
scheduled time pass. Confirm:
- The first alarm's audio and vibration do **not** glitch, stop, or restart
  at the moment the second alarm's time arrives.
- The ring screen shows a "Next: `<second alarm's label>` queued" line.

- [ ] **Step 3: Confirm dismissal advances the queue**

Dismiss the first alarm (slide-to-wake, or complete its mission if it has
one). Confirm the second alarm starts ringing immediately afterward — its own
sound/vibration/mission, ring screen showing its own label, no chip (nothing
queued behind it).

- [ ] **Step 4: Confirm snooze advances the queue too**

Repeat steps 1–2 with a fresh pair of alarms, but this time **snooze** the
first instead of dismissing it. Confirm the second alarm starts ringing
immediately (does not wait for the first's snooze window to elapse).

- [ ] **Step 5: Record results**

Create `docs/superpowers/reliability/2026-08-05-alarm-ring-queue-device-results.md`
following the format of
`docs/superpowers/reliability/2026-07-18-phase4b-device-results.md` (date,
device, build, then PASS/FAIL per scenario with any observed deviations).
Commit it:

```bash
git add docs/superpowers/reliability/2026-08-05-alarm-ring-queue-device-results.md
git commit -m "docs(reliability): device-verify the ring queue"
```
