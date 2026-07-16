import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../domain/missed_alarm.dart';
import '../domain/reconcile.dart';
import '../domain/schedule_math.dart';
import '../domain/scheduled_occurrence.dart';
import 'local/alarm_repository.dart';
import 'local/database.dart';
import 'native/alarm_api.g.dart';

/// What the sync service needs from the platform, in domain types.
///
/// This seam keeps the Pigeon-generated API out of the service and lets tests
/// fake the platform without depending on codegen output.
abstract class AlarmPlatform {
  Future<void> reconcile(List<ScheduledOccurrence> occurrences);
  Future<void> ringNow(ScheduledOccurrence occurrence);
}

/// The only place that knows [NativeAlarm] exists.
class PigeonAlarmPlatform implements AlarmPlatform {
  PigeonAlarmPlatform([AlarmHostApi? api]) : _api = api ?? AlarmHostApi();

  final AlarmHostApi _api;

  NativeAlarm _toNative(ScheduledOccurrence o) => NativeAlarm(
        id: o.alarmId,
        fireAtEpochMs: o.fireAt.millisecondsSinceEpoch,
        label: o.label,
        soundAsset: o.soundAsset,
        vibrate: o.vibrate,
        hour: o.hour,
        minute: o.minute,
        weekdays: o.weekdays.toList()..sort(),
      );

  @override
  Future<void> reconcile(List<ScheduledOccurrence> occurrences) =>
      _api.reconcile([for (final o in occurrences) _toNative(o)]);

  @override
  Future<void> ringNow(ScheduledOccurrence occurrence) =>
      _api.ringNow(_toNative(occurrence));
}

/// Single point where alarms in the local database become alarms armed in the
/// platform scheduler.
///
/// Called on: app launch, any alarm edit, dismissal, boot, app update, and
/// timezone or clock change. Reconcile is a full replace, so calling it more
/// often than necessary is always safe.
class AlarmSyncService {
  AlarmSyncService({
    required AlarmRepository repository,
    required AlarmPlatform platform,
    required tz.Location location,
    Future<void> Function()? refreshLocation,
  })  : _repository = repository,
        _platform = platform,
        _location = location,
        _refreshLocation = refreshLocation;

  final AlarmRepository _repository;
  final AlarmPlatform _platform;

  // Not final: reconcileNow() re-reads tz.local after _refreshLocation(), so
  // a live IANA zone change (rare — not an ordinary DST transition, which
  // tz.Location already encodes) is picked up on the next reconcile rather
  // than being stuck at whatever the device reported at construction time.
  tz.Location _location;

  // Null in tests: tests construct this service directly with an explicit
  // [location] and want it to stay fixed for the life of the test, not get
  // silently overwritten by whatever zone the test machine happens to be in.
  // Production wires this to _setLocalLocationFromDevice via
  // configureForApp().
  final Future<void> Function()? _refreshLocation;

  /// Exposed so the UI reads alarms through the same instance the scheduler
  /// was built from — two repositories over two database handles would drift.
  AlarmRepository get repository => _repository;

  static AlarmSyncService? _instance;

  static AlarmSyncService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
          'AlarmSyncService used before configure()/configureForApp()');
    }
    return i;
  }

  static void configure(AlarmSyncService service) => _instance = service;

  /// Builds the production service against the real database and platform.
  /// Call once from main() and once from the headless boot entrypoint.
  static Future<void> configureForApp() async {
    // tz.local defaults to UTC until setLocalLocation() is called — the
    // `timezone` package does not discover the device zone on its own. Skip
    // this and every alarm is armed off by the device's UTC offset: on a
    // UTC+4 device, "ring in 1 minute" fires ~4 hours late. This must happen
    // before the service (and anything backed by tz.local) is constructed.
    await _setLocalLocationFromDevice();

    final dir = await getApplicationDocumentsDirectory();
    final db = RiseDatabase(NativeDatabase(
      File(p.join(dir.path, 'rise.sqlite')),
      setup: (db) {
        // Several engines (foreground, RingActivity, headless boot) open this
        // file as separate isolates, running genuinely in parallel. Default
        // journaling forbids concurrent reads and writes, and busy_timeout
        // defaults to 0 — a read racing a write would throw SQLITE_BUSY
        // instantly, feeding straight into the startup-throw path this same
        // fix set guards against (see main()/reconcileEntrypoint()).
        db.execute('pragma journal_mode = WAL;');
        db.execute('pragma busy_timeout = 5000;');
      },
    ));
    configure(AlarmSyncService(
      repository: AlarmRepository(db),
      platform: PigeonAlarmPlatform(),
      location: tz.local,
      // Lets reconcileNow() re-resolve the device zone instead of trusting
      // whatever was current at construction time — see the doc comment on
      // AlarmSyncService._location for why that matters.
      refreshLocation: _setLocalLocationFromDevice,
    ));
  }

  /// Resolves the device's IANA timezone (e.g. "America/New_York") from the
  /// platform and makes it `tz.local`.
  ///
  /// Both current callers (main() and reconcileEntrypoint() in main.dart)
  /// already run `tzdata.initializeTimeZones()` before this, but a future
  /// caller might not, and a device can also report a zone name the bundled
  /// tz database doesn't recognize (stale platform data, an alias the
  /// database renamed, etc). Either way `tz.getLocation()` throws
  /// `LocationNotFoundException` rather than crashing the process.
  ///
  /// `getLocalTimezone()` itself can also fail — it is a MethodChannel call,
  /// so a host-side wiring problem (a plugin not registered on whatever
  /// engine is running this, a platform-side crash, etc) makes it throw
  /// `MissingPluginException`/`PlatformException` instead of returning.
  /// That failure is inside this try/catch too, for the same reason: a
  /// plugin hiccup must degrade to a wrong-timezone alarm, never to no
  /// alarms at all, since that is the exact failure this whole path exists
  /// to prevent.
  ///
  /// Either way this falls back to UTC — loudly, via debugPrint, since a
  /// silent fallback here would silently recreate the exact bug this method
  /// exists to fix.
  static Future<void> _setLocalLocationFromDevice() async {
    String? identifier;
    try {
      identifier = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(identifier));
    } catch (e) {
      final zone = identifier == null ? '' : ' "$identifier"';
      debugPrint(
        'AlarmSyncService: could not resolve device timezone$zone ($e). '
        'Falling back to UTC — alarms WILL be armed at the wrong instant on '
        'any device outside UTC until this is diagnosed and fixed.',
      );
      tz.setLocalLocation(tz.UTC);
    }
  }

  Future<List<ScheduledOccurrence>> currentPlan() async {
    return desiredOccurrences(
      alarms: await _repository.all(),
      now: tz.TZDateTime.now(_location),
      location: _location,
    );
  }

  /// Re-arms the platform scheduler from the local database.
  ///
  /// When [recoverMissed] is true (boot, app update, clock change), an alarm
  /// that came due within the last 30 minutes rings immediately rather than
  /// being silently lost — unless the user already dismissed that specific
  /// occurrence, which this method (not [findMissedAlarm]) is responsible for
  /// excluding before the missed-alarm search ever runs.
  Future<void> reconcileNow({bool recoverMissed = false}) async {
    // Re-resolve the device zone before computing the plan: BootReceiver's
    // headless engine runs this on every boot/app-update/clock-change, so an
    // actual IANA zone change (not an ordinary DST transition — tz.Location
    // already encodes those) is picked up here. Without this, a foreground
    // engine that started before the zone change keeps using the stale
    // _location for the rest of the process, and the next add/edit-triggered
    // reconcile would silently overwrite the just-corrected schedule.
    final refresh = _refreshLocation;
    if (refresh != null) {
      await refresh();
      _location = tz.local;
    }

    final plan = await currentPlan();
    await _platform.reconcile(plan);

    if (!recoverMissed) return;

    // Recovery reads the alarms' PREVIOUS occurrences, not `plan`: a missed
    // alarm has already rolled forward to its next firing, so it never appears
    // in the desired set.
    final now = tz.TZDateTime.now(_location);
    final previous = <ScheduledOccurrence>[];
    for (final alarm in await _repository.all()) {
      if (!alarm.enabled) continue;
      final before = previousOccurrence(
          alarm: alarm, before: now, location: _location);
      if (before == null) continue;

      final fireAt = before.toUtc();
      final dismissedAt = alarm.lastDismissedAt;
      // A dismissal at or after this occurrence's fireAt means the user
      // already dealt with it — do not ring it again. An older dismissal
      // (e.g. of yesterday's occurrence) must not suppress this one.
      if (dismissedAt != null && !dismissedAt.toUtc().isBefore(fireAt)) {
        continue;
      }

      previous.add(ScheduledOccurrence(
        alarmId: alarm.id,
        fireAt: fireAt,
        label: alarm.label,
        soundAsset: alarm.soundAsset,
        vibrate: alarm.vibrate,
      ));
    }

    final missed =
        findMissedAlarm(occurrences: previous, now: now.toUtc());
    if (missed != null) {
      debugPrint('Recovering missed alarm ${missed.alarmId}');
      // Never via reconcile(): that is a full replace and would cancel every
      // other alarm the user has set.
      await _platform.ringNow(missed);
    }
  }
}
