import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'config/revenuecat_config.dart';
import 'config/supabase_config.dart';
import 'l10n/app_localizations.dart';
import 'data/alarm_sync_service.dart';
import 'data/app_settings.dart';
import 'data/iap/revenuecat_entitlement_service.dart';
import 'data/local/alarm_repository.dart';
import 'data/native/alarm_api.g.dart';
import 'domain/rise_settings.dart';
import 'ui/missions/mission_host.dart';
import 'ui/screens/app_shell.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/ring_screen.dart';
import 'ui/state/settings_providers.dart';
import 'ui/theme/tokens.dart';

/// Headless entrypoint invoked by Android's BootReceiver after boot, app
/// replacement, or a clock change. Re-arms the scheduler from the local
/// database and recovers any alarm missed while the device was off.
@pragma('vm:entry-point')
Future<void> reconcileEntrypoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try {
    await AlarmSyncService.configureForApp();
    await AlarmSyncService.instance.reconcileNow(recoverMissed: true);
  } finally {
    // Let the platform tear down the headless engine that ran this, even if
    // reconcile above threw — otherwise a crash leaks the engine forever.
    await AlarmHostApi().reconcileFinished();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  // ── Only what the first frame — and the dismiss/ring UI — actually needs runs
  // before runApp(). RingActivity cold-boots this SAME main() in its own engine
  // while an alarm is already audibly ringing (the sound is native and instant),
  // so every ms spent here before the dismiss screen renders is a ms the user
  // can't shut the alarm off. Firebase, RevenueCat and the scheduler reconcile
  // are NOT needed to show or dismiss the alarm, so they run in _deferredStartup
  // AFTER runApp. Everything here must also never let an exception escape, or
  // runApp() would be skipped and the ring would be unstoppable.

  // Social backend: the account/social providers read Supabase.instance eagerly,
  // so it must be initialized before runApp — but it's a local session restore,
  // not a network round-trip, so it's cheap. Best-effort.
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // `anonKey` is deprecated in favor of `publishableKey` as of
        // supabase_flutter 2.16 — same value (the dashboard's anon key).
        publishableKey: SupabaseConfig.anonKey,
      );
    } catch (e) {
      debugPrint('Rise: Supabase init failed (social disabled): $e');
    }
  }

  // App preferences (the onboarding flag) — local + fast. A failure must not
  // stop launch or trap the user in onboarding.
  AppSettings? settings;
  try {
    settings = await AppSettings.load();
  } catch (e) {
    debugPrint('Rise: settings load failed: $e');
  }

  // Open the local DB (fast) so the alarm list renders and the ring can record
  // its wake event. The scheduler *reconcile* (re-arm every alarm) is deferred
  // — it isn't needed to render or dismiss, and it's the costly loop.
  AlarmRepository? repository;
  try {
    await AlarmSyncService.configureForApp();
    repository = AlarmSyncService.instance.repository;
  } catch (e, s) {
    debugPrint('Rise: startup DB configure failed: $e\n$s');
  }

  runApp(ProviderScope(
    overrides: [
      if (settings != null) appSettingsProvider.overrideWithValue(settings),
    ],
    child: RiseApp(repository: repository, settings: settings),
  ));

  // Off the critical path-to-first-frame. Best-effort throughout.
  unawaited(_deferredStartup());
}

/// Non-critical startup that runs AFTER the first frame so the UI — especially
/// the alarm dismiss screen — appears immediately. Push (Firebase/FCM),
/// monetization (RevenueCat) and the scheduler reconcile all tolerate arriving
/// a beat late, and none is needed to show or dismiss a ringing alarm.
Future<void> _deferredStartup() async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Rise: Firebase init skipped (push disabled): $e');
  }

  if (RevenueCatConfig.isConfigured) {
    try {
      await RevenueCatEntitlementService.configureSdk(RevenueCatConfig.apiKey);
    } catch (e) {
      debugPrint('Rise: RevenueCat init failed (premium gating disabled): $e');
    }
  }

  // Every launch re-arms the scheduler: OEMs and OS updates silently clear it.
  // The alarms were already armed by the previous session, so re-arming a beat
  // after the UI shows is safe. Guarded: instance throws if configure failed.
  try {
    await AlarmSyncService.instance.reconcileNow();
  } catch (e, s) {
    debugPrint('Rise: deferred reconcile failed: $e\n$s');
  }
}

class RiseApp extends ConsumerStatefulWidget {
  const RiseApp({super.key, required this.repository, required this.settings});

  /// Null when startup failed to configure the service (see main()). The app
  /// degrades to [_StartupFailedPage] instead of crashing on a second throw.
  final AlarmRepository? repository;

  /// Null when settings failed to load; the app then skips onboarding rather
  /// than trapping the user in it.
  final AppSettings? settings;

  @override
  ConsumerState<RiseApp> createState() => _RiseAppState();
}

class _RiseAppState extends ConsumerState<RiseApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();

  // The alarm id currently shown on a pushed RingScreen, or null if none is
  // showing. Tracked so a re-check can tell "same alarm still ringing" (do
  // nothing) from "a different alarm took over" (replace) from "nothing is
  // ringing any more" (pop). Kept in sync by the `.then` in _showRing, which
  // fires whenever the pushed route is popped for any reason.
  int? _shownRingId;

  late bool _showOnboarding;

  @override
  void initState() {
    super.initState();
    _showOnboarding =
        widget.settings != null && !widget.settings!.onboardingComplete;
    WidgetsBinding.instance.addObserver(this);
    _checkColdStartRing();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // RingActivity is singleInstance: a second alarm firing while it shows does
    // not recreate it, so initState never re-runs. Resuming is the one signal
    // available in both that case and the general "returned to the app while an
    // alarm rings" case.
    if (state == AppLifecycleState.resumed) _checkColdStartRing();
  }

  @override
  void didChangePlatformBrightness() {
    // The OS light/dark setting flipped. When themeMode is `system` the resolved
    // brightness depends on it, so rebuild the root to re-resolve the palette.
    if (mounted) setState(() {});
  }

  void _completeOnboarding() {
    widget.settings?.setOnboardingComplete(true);
    setState(() => _showOnboarding = false);
  }

  /// Cold start: RingActivity launched the engine from scratch, so nothing else
  /// tells Dart an alarm is ringing — ask the platform directly. Also re-run on
  /// every resume. A thrown PlatformException here must not go unhandled, or the
  /// ring screen would never appear and the alarm would render no way to stop.
  Future<void> _checkColdStartRing() async {
    int? id;
    try {
      id = await AlarmHostApi().getRingingAlarmId();
    } catch (e) {
      debugPrint('Rise: could not check for a ringing alarm: $e');
      return;
    }
    _reconcileRingScreen(id);
  }

  void _reconcileRingScreen(int? id) {
    if (id == _shownRingId) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    if (id == null) {
      _shownRingId = null;
      navigator.maybePop();
      return;
    }
    if (_shownRingId == null) {
      _showRing(id, replace: false);
    } else {
      _showRing(id, replace: true);
    }
  }

  void _showRing(int alarmId, {required bool replace}) {
    _shownRingId = alarmId;
    final route = MaterialPageRoute<void>(
      builder: (_) => RingScreen(
        alarmId: alarmId,
        record: true,
        missionBuilder: buildMission,
        onDismissed: () => _navigatorKey.currentState?.maybePop(),
      ),
    );
    final navigator = _navigatorKey.currentState!;
    final future =
        replace ? navigator.pushReplacement(route) : navigator.push(route);
    future.then((_) {
      if (_shownRingId == alarmId) _shownRingId = null;
    });
  }

  /// Resolve the user's theme choice to a concrete brightness. `system` reads
  /// the current OS setting (kept fresh by [didChangePlatformBrightness]).
  Brightness _resolveBrightness(RiseThemeMode mode) => switch (mode) {
        RiseThemeMode.system =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
        RiseThemeMode.light => Brightness.light,
        RiseThemeMode.dark => Brightness.dark,
      };

  /// Match the status-bar icons to the ground: dark icons on the light theme,
  /// light icons on the dark theme. Only the icon brightness is set (colour is
  /// left untouched) so the light theme's status bar is unchanged.
  void _applyStatusBarStyle(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    ));
  }

  /// Material's own defaults (dialogs, text fields, dividers, default text
  /// colour) for the dark theme. Reads the [RiseColors] getters, which the
  /// build below has already switched to the dark palette before this is
  /// consulted — MaterialApp only uses this when the resolved brightness is
  /// dark. The light theme is left as MaterialApp's default (theme: null) so it
  /// stays byte-identical to before dark mode.
  ThemeData _riseDarkTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: RiseColors.appBg,
        canvasColor: RiseColors.appBg,
        dividerColor: RiseColors.divider,
        colorScheme: ColorScheme.dark(
          surface: RiseColors.card,
          onSurface: RiseColors.text,
          primary: RiseColors.primary,
          onPrimary: RiseColors.primaryText,
          error: RiseColors.danger,
          outline: RiseColors.border,
        ),
        dialogTheme: DialogThemeData(backgroundColor: RiseColors.card),
        bottomSheetTheme:
            BottomSheetThemeData(backgroundColor: RiseColors.card),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: RiseColors.primary,
          selectionColor: RiseColors.accentSoft,
          selectionHandleColor: RiseColors.primary,
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Resolve the theme mode → brightness, then set the active RiseColors
    // palette BEFORE the tree below builds, so every widget that reads a
    // RiseColors/RiseText getter during its build sees the right theme. A change
    // to the setting (watched here) or the OS brightness rebuilds this root,
    // which re-reads the getters and re-runs setPalette.
    final themeMode =
        ref.watch(currentSettingsProvider.select((s) => s.themeMode));
    final brightness = _resolveBrightness(themeMode);
    RiseColors.setPalette(brightness);
    _applyStatusBarStyle(brightness);

    final repository = widget.repository;
    return MaterialApp(
      title: 'Rise',
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      // Light stays MaterialApp's default (theme: null) so the device-verified
      // light theme is byte-identical; darkTheme adapts Material's own defaults
      // in dark mode. themeMode is resolved here (never `system`) so it always
      // agrees with the palette set above.
      darkTheme: _riseDarkTheme(),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      // Localization infrastructure (scaffolding only). These delegates bundle
      // the global Material/Widgets/Cupertino delegates alongside the generated
      // AppLocalizations; existing UI strings are not yet migrated. See
      // docs/l10n.md.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: repository == null
          ? const _StartupFailedPage()
          : (_showOnboarding
              ? OnboardingScreen(onDone: _completeOnboarding)
              : const AppShell()),
    );
  }
}

/// Degrade-visibly screen shown when startup's configureForApp() failed. Alarms
/// already armed still ring — RingActivity runs its own engine and RingScreen's
/// Dismiss does not depend on this repository — but the home screen has no
/// database to read or write until the app restarts.
class _StartupFailedPage extends StatelessWidget {
  const _StartupFailedPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.error_outline, size: 48),
              SizedBox(height: 16),
              Text(
                'Rise failed to start and could not reach the database.\n'
                'Already-armed alarms will still ring. Restart the app to '
                'try again.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
