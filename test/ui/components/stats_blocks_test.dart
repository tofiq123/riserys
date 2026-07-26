import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/achievements.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/period_stats.dart';
import 'package:rise/domain/streak.dart';
import 'package:rise/domain/wake_event.dart';
import 'package:rise/domain/wake_rhythm.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/components/medallion_rail.dart';
import 'package:rise/ui/components/podium.dart';
import 'package:rise/ui/components/stat_summary.dart';

void main() {
  final now = DateTime(2026, 7, 26, 12);

  CrewStanding st(String id, String name, int streak, {bool me = false}) =>
      CrewStanding(
        id: id,
        username: id,
        displayName: name,
        avatarColor: '#7C9CF4',
        stats: WakeStats(currentStreak: streak, bestStreak: streak + 4,
            totalWakes: 20, onTimeCount: 17),
        isMe: me,
      );

  WakeEvent ev(int day, {int? after}) {
    final ring = DateTime(2026, 7, day, 6, 45);
    return WakeEvent(
      id: day,
      alarmId: 1,
      scheduledAt: ring,
      firstRingAt: ring,
      dismissedAt: after == null ? null : ring.add(Duration(minutes: after)),
      onTime: after != null && after <= kOnTimeGrace.inMinutes,
    );
  }

  Future<void> pump(WidgetTester t, Widget child, {double width = 1125}) async {
    t.view.physicalSize = Size(width, 2400);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(20), child: child)))));
    await t.pumpAndSettle();
  }

  group('Podium', () {
    testWidgets('puts the winner in the middle, second left, third right',
        (t) async {
      await pump(
          t,
          Podium(top: [st('a', 'Ada', 31), st('b', 'Ben', 18), st('c', 'Cara', 9)]));
      final ada = t.getCenter(find.byKey(const Key('podium-a'))).dx;
      final ben = t.getCenter(find.byKey(const Key('podium-b'))).dx;
      final cara = t.getCenter(find.byKey(const Key('podium-c'))).dx;
      expect(ben, lessThan(ada));
      expect(ada, lessThan(cara));
      expect(find.text('1ST'), findsOneWidget);
      expect(find.text('🔥31'), findsOneWidget);
    });

    testWidgets('the winner stands tallest', (t) async {
      await pump(
          t,
          Podium(top: [st('a', 'Ada', 31), st('b', 'Ben', 18), st('c', 'Cara', 9)]));
      final ada = t.getSize(find.byKey(const Key('podium-a'))).height;
      final cara = t.getSize(find.byKey(const Key('podium-c'))).height;
      expect(ada, greaterThan(cara));
    });

    testWidgets('two standings render two plinths, one renders one', (t) async {
      await pump(t, Podium(top: [st('a', 'Ada', 31), st('b', 'Ben', 18)]));
      expect(find.text('1ST'), findsOneWidget);
      expect(find.text('2ND'), findsOneWidget);
      expect(find.text('3RD'), findsNothing);

      await pump(t, Podium(top: [st('a', 'Ada', 31)]));
      expect(find.text('1ST'), findsOneWidget);
      expect(find.text('2ND'), findsNothing);
    });

    testWidgets('an empty leaderboard renders nothing at all', (t) async {
      await pump(t, const Podium(top: []));
      expect(find.text('1ST'), findsNothing);
    });

    testWidgets('your own plinth reads You and does not navigate', (t) async {
      final tapped = <String>[];
      await pump(
          t,
          Podium(
              top: [st('a', 'Ada', 31), st('me', 'Me', 12, me: true)],
              onTap: (s) => tapped.add(s.id)));
      expect(find.text('You'), findsOneWidget);
      await t.tap(find.byKey(const Key('podium-me')));
      await t.pump();
      expect(tapped, isEmpty);

      await t.tap(find.byKey(const Key('podium-a')));
      await t.pump();
      expect(tapped, ['a']);
    });
  });

  group('MedallionRail', () {
    List<Achievement> badges() => const [
          Achievement(
              id: 'streak_30',
              title: '30-day run',
              description: '',
              earned: false,
              progress: 12,
              target: 30),
          Achievement(
              id: 'first_light', title: 'First light', description: '',
              earned: true),
          Achievement(
              id: 'streak_100',
              title: 'Century',
              description: '',
              earned: false,
              progress: 12,
              target: 100),
        ];

    testWidgets('earned badges lead the rail', (t) async {
      await pump(t, MedallionRail(badges: badges()));
      final first = t.getCenter(find.byKey(const Key('medallion-first_light'))).dx;
      final next = t.getCenter(find.byKey(const Key('medallion-streak_30'))).dx;
      expect(first, lessThan(next));
      expect(find.text('earned'), findsOneWidget);
    });

    testWidgets('the nearest unearned badge shows its progress', (t) async {
      await pump(t, MedallionRail(badges: badges()));
      expect(find.text('12 / 30'), findsOneWidget);
    });

    testWidgets('the closest locked badge comes before the distant one',
        (t) async {
      await pump(t, MedallionRail(badges: badges()));
      final near = t.getCenter(find.byKey(const Key('medallion-streak_30'))).dx;
      final far = t.getCenter(find.byKey(const Key('medallion-streak_100'))).dx;
      expect(near, lessThan(far));
    });

    testWidgets('an all-earned wall does not crash looking for a next', (t) async {
      await pump(
          t,
          const MedallionRail(badges: [
            Achievement(
                id: 'first_light', title: 'First light', description: '',
                earned: true)
          ]));
      expect(t.takeException(), isNull);
      expect(find.text('earned'), findsOneWidget);
    });
  });

  group('StatSummary', () {
    Widget summary({
      StatsPeriod period = StatsPeriod.week,
      bool locked = false,
      int? consistency = 74,
      void Function(StatsPeriod)? onPeriod,
    }) =>
        StatSummary(
          streak: const StreakStats(
              current: 12, best: 18, freezesRemaining: 1, byDay: {}),
          week: buildRhythm(
              [for (var d = 20; d <= 26; d++) ev(d, after: d == 24 ? 40 : 3)],
              now,
              days: 7),
          stats: const PeriodStats(
              count: 7, onTimeCount: 6, avgWakeMinute: 409, bestStreak: 18),
          consistency: consistency,
          period: period,
          periodsLocked: locked,
          onPeriod: onPeriod ?? (_) {},
        );

    testWidgets('shows the run, the sentence and all four figures', (t) async {
      await pump(t, summary());
      expect(find.text('12'), findsOneWidget);
      // "days" appears twice on purpose: the run's unit, and best-run's.
      expect(find.text('days'), findsNWidgets(2));
      expect(find.text('On time 6 of 7 this week.'), findsOneWidget);
      expect(find.text('86%'), findsOneWidget);
      expect(find.text('06:49'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(find.text('74'), findsOneWidget);
      for (final label in ['on time', 'avg wake', 'best run', 'consistency']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the four figures sit on one row on a normal phone', (t) async {
      await pump(t, summary());
      final ys = [
        for (final l in ['on time', 'avg wake', 'best run', 'consistency'])
          t.getTopLeft(find.text(l)).dy
      ];
      expect(ys.toSet(), hasLength(1), reason: 'all four share a baseline');
    });

    testWidgets('they reflow to a 2x2 on a small phone instead of truncating',
        (t) async {
      await pump(t, summary(), width: 960); // 320pt
      final ys = [
        for (final l in ['on time', 'avg wake', 'best run', 'consistency'])
          t.getTopLeft(find.text(l)).dy
      ];
      expect(ys.toSet(), hasLength(2), reason: 'two rows of two');
      expect(t.takeException(), isNull);
      expect(find.text('consistency'), findsOneWidget);
    });

    testWidgets('a locked period carries the glyph and still reports the tap',
        (t) async {
      final picked = <StatsPeriod>[];
      await pump(t, summary(locked: true, onPeriod: picked.add));
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
      await t.tap(find.byKey(const Key('summary-period-month')));
      await t.pump();
      expect(picked, [StatsPeriod.month],
          reason: 'the screen decides whether to switch or open the paywall');
    });

    testWidgets('no consistency score yet reads as building, never as zero',
        (t) async {
      await pump(t, summary(consistency: null));
      expect(find.text('building'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a freeze in the week is named in the sentence', (t) async {
      await pump(
          t,
          StatSummary(
            streak: const StreakStats(
                current: 12, best: 18, freezesRemaining: 0, byDay: {}),
            week: buildRhythm(
                [for (var d = 20; d <= 26; d++) ev(d, after: d == 24 ? 40 : 3)],
                now,
                days: 7,
                freezeAbsorbed: {DateTime(2026, 7, 24)}),
            stats: const PeriodStats(
                count: 7, onTimeCount: 6, avgWakeMinute: 409, bestStreak: 18),
            consistency: 74,
            period: StatsPeriod.week,
            periodsLocked: false,
            onPeriod: (_) {},
          ));
      expect(find.text('On time 6 of 7 this week. A freeze covered one.'),
          findsOneWidget);
    });

    testWidgets('an empty week says so rather than dividing by zero', (t) async {
      await pump(
          t,
          StatSummary(
            streak: StreakStats.empty,
            week: buildRhythm(const [], now, days: 7),
            stats: PeriodStats.empty,
            consistency: null,
            period: StatsPeriod.week,
            periodsLocked: false,
            onPeriod: (_) {},
          ));
      expect(find.text('No mornings logged this week yet.'), findsOneWidget);
      expect(find.text('no wakes yet'), findsOneWidget);
    });
  });
}
