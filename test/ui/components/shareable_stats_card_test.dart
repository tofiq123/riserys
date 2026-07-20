import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/achievements.dart';
import 'package:rise/ui/components/shareable_stats_card.dart';

Future<void> _pump(WidgetTester t, Widget child) async {
  t.view.physicalSize = const Size(900, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
}

const _badge = Achievement(
  id: 'streak_7',
  title: '7-day streak',
  description: 'Woke on time 7 days in a row.',
  earned: true,
);

void main() {
  testWidgets('renders streak, best, consistency, handle and a badge', (t) async {
    await _pump(
      t,
      const ShareableStatsCard(
        streakDays: 12,
        bestStreak: 20,
        consistency: 88,
        badges: [_badge],
        handle: '@mo',
      ),
    );
    expect(find.text('12'), findsOneWidget); // streak
    expect(find.text('day streak'), findsOneWidget);
    expect(find.text('20'), findsOneWidget); // best
    expect(find.text('88'), findsOneWidget); // consistency
    expect(find.text('@mo'), findsOneWidget);
    expect(find.text('7-day streak'), findsOneWidget); // spotlight badge
    expect(find.text('RISE'), findsOneWidget);
  });

  testWidgets('handles no consistency and no badges gracefully', (t) async {
    await _pump(
      t,
      const ShareableStatsCard(streakDays: 0, bestStreak: 0),
    );
    expect(find.text('—'), findsOneWidget); // consistency placeholder
    expect(find.text('Just getting started.'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing); // no handle
  });

  testWidgets('spotlights at most two badges', (t) async {
    await _pump(
      t,
      const ShareableStatsCard(
        streakDays: 5,
        bestStreak: 5,
        badges: [
          Achievement(id: 'a', title: 'First light', description: 'x', earned: true),
          Achievement(id: 'b', title: 'Early bird', description: 'y', earned: true),
          Achievement(id: 'c', title: 'Sharp', description: 'z', earned: true),
        ],
      ),
    );
    expect(find.text('First light'), findsOneWidget);
    expect(find.text('Early bird'), findsOneWidget);
    expect(find.text('Sharp'), findsNothing); // third is dropped
  });
}
