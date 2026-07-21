import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/home_location_gateway.dart';
import 'package:rise/domain/rise_settings.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/ui/morning_departure_host.dart';
import 'package:rise/ui/state/home_providers.dart';
import 'package:rise/ui/state/settings_providers.dart';
import 'package:rise/ui/state/wake_providers.dart';

// A Berlin home anchor; the "away" fix is ~11 km off (clearly beyond any radius)
// and the "home" fix is dead on it.
const _homeLat = 52.52;
const _homeLng = 13.405;
const _awayFix = HomeFix(latitude: 52.60, longitude: 13.50, accuracyMeters: 10);
const _homeFix =
    HomeFix(latitude: _homeLat, longitude: _homeLng, accuracyMeters: 10);

RiseSettings _settings(HomeShareTier tier, {bool withHome = true}) {
  final base = RiseSettings(homeShare: tier);
  return withHome ? base.copyWith(homeLat: _homeLat, homeLng: _homeLng) : base;
}

WakeEvent _ringAgo(Duration ago) {
  final t = DateTime.now().toUtc().subtract(ago);
  return WakeEvent(
      id: 1, alarmId: 1, scheduledAt: t, firstRingAt: t, label: 'Alarm');
}

/// Pumps a MorningDepartureHost over a container so the flag can be read back.
Future<ProviderContainer> _pump(
  WidgetTester t, {
  required HomeShareTier tier,
  required HomeFix? fix,
  required List<WakeEvent> events,
  bool withHome = true,
  bool initialFlag = false,
  FakeHomeLocationGateway? gateway,
}) async {
  final container = ProviderContainer(overrides: [
    currentSettingsProvider.overrideWithValue(_settings(tier, withHome: withHome)),
    homeLocationGatewayProvider
        .overrideWithValue(gateway ?? FakeHomeLocationGateway(fix: fix)),
    wakeEventsProvider.overrideWith((ref) => Stream.value(events)),
    leftHomeTodayProvider.overrideWith((ref) => initialFlag),
  ]);
  addTearDown(container.dispose);
  await t.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: MorningDepartureHost(child: SizedBox())),
  ));
  await t.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a fix beyond the home radius during the morning flips the flag',
      (t) async {
    final c = await _pump(t,
        tier: HomeShareTier.crew,
        fix: _awayFix,
        events: [_ringAgo(const Duration(minutes: 30))]);
    expect(c.read(leftHomeTodayProvider), isTrue);
  });

  testWidgets('the private tier also detects (local evidence), flag flips',
      (t) async {
    final c = await _pump(t,
        tier: HomeShareTier.private,
        fix: _awayFix,
        events: [_ringAgo(const Duration(minutes: 30))]);
    expect(c.read(leftHomeTodayProvider), isTrue);
  });

  testWidgets('a fix still within the home radius leaves the flag off',
      (t) async {
    final c = await _pump(t,
        tier: HomeShareTier.crew,
        fix: _homeFix,
        events: [_ringAgo(const Duration(minutes: 30))]);
    expect(c.read(leftHomeTodayProvider), isFalse);
  });

  testWidgets('the feature off takes NO location fix at all', (t) async {
    final gw = FakeHomeLocationGateway(fix: _awayFix);
    final c = await _pump(t,
        tier: HomeShareTier.off,
        fix: _awayFix,
        gateway: gw,
        events: [_ringAgo(const Duration(minutes: 30))]);
    expect(c.read(leftHomeTodayProvider), isFalse);
    expect(gw.currentFixCalls, 0, reason: 'no location read when tier is off');
  });

  testWidgets('no home anchor set takes NO location fix', (t) async {
    final gw = FakeHomeLocationGateway(fix: _awayFix);
    final c = await _pump(t,
        tier: HomeShareTier.crew,
        fix: _awayFix,
        gateway: gw,
        withHome: false,
        events: [_ringAgo(const Duration(minutes: 30))]);
    expect(c.read(leftHomeTodayProvider), isFalse);
    expect(gw.currentFixCalls, 0);
  });

  testWidgets('outside the morning window (old ring) takes NO fix', (t) async {
    final gw = FakeHomeLocationGateway(fix: _awayFix);
    final c = await _pump(t,
        tier: HomeShareTier.crew,
        fix: _awayFix,
        gateway: gw,
        events: [_ringAgo(const Duration(hours: 9))]);
    expect(c.read(leftHomeTodayProvider), isFalse);
    expect(gw.currentFixCalls, 0, reason: 'ring was 9h ago, past the 6h window');
  });

  testWidgets('already flagged out: skips the fix (battery)', (t) async {
    final gw = FakeHomeLocationGateway(fix: _awayFix);
    final c = await _pump(t,
        tier: HomeShareTier.crew,
        fix: _awayFix,
        gateway: gw,
        initialFlag: true,
        events: [_ringAgo(const Duration(minutes: 30))]);
    expect(c.read(leftHomeTodayProvider), isTrue);
    expect(gw.currentFixCalls, 0, reason: 'already known out — no re-check');
  });

  testWidgets('no wake events yet takes NO fix', (t) async {
    final gw = FakeHomeLocationGateway(fix: _awayFix);
    final c = await _pump(t,
        tier: HomeShareTier.crew, fix: _awayFix, gateway: gw, events: const []);
    expect(c.read(leftHomeTodayProvider), isFalse);
    expect(gw.currentFixCalls, 0);
  });
}
