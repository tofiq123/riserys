import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_status.dart';
import 'package:rise/domain/feed_item.dart';
import 'package:rise/domain/morning_line.dart';
import 'package:rise/ui/components/morning_line_view.dart';

void main() {
  final now = DateTime(2026, 7, 26, 6, 12);

  CrewMember m(String id, String name) => CrewMember(
      id: id, username: id, displayName: name, avatarColor: '#7C9CF4');

  FeedItem wake(String userId, int h, int min,
          {bool onTime = true,
          int streak = 5,
          List<FeedReaction> react = const []}) =>
      FeedItem(
        id: 'f_$userId',
        userId: userId,
        username: userId,
        displayName: userId,
        avatarColor: '#7C9CF4',
        wokeAt: DateTime(2026, 7, 26, h, min),
        onTime: onTime,
        streak: streak,
        reactions: react,
      );

  MorningLine lineAt(DateTime when,
          {List<CrewMember> friends = const [],
          Map<String, CrewStatus> statuses = const {},
          List<FeedItem> feed = const []}) =>
      buildMorningLine(
          now: when, friends: friends, statuses: statuses, feed: feed);

  Future<List<MorningEntry>> pump(
    WidgetTester t,
    MorningLine line, {
    DateTime? at,
    bool reduceMotion = false,
    void Function(MorningEntry, String)? onCheer,
    Widget? footer,
  }) async {
    final opened = <MorningEntry>[];
    t.view.physicalSize = const Size(1125, 2400);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          // The real screen scrolls; a bare Column would report a false
          // overflow for any crew long enough to be interesting.
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: MorningLineView(
                line: line,
                now: at ?? now,
                onOpen: opened.add,
                onCheer: onCheer ?? (_, __) {},
                footer: footer,
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    return opened;
  }

  testWidgets('a wake row shows the time, the verdict and the streak',
      (t) async {
    await pump(
        t,
        lineAt(now,
            friends: [m('ada', 'Ada Lovelace')],
            feed: [wake('ada', 5, 42, streak: 31)]));
    expect(find.text('05:42'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('on time'), findsOneWidget);
    expect(find.text('🔥31'), findsOneWidget);
  });

  testWidgets('a not-on-time wake reads as woke up, never as a failure',
      (t) async {
    await pump(
        t,
        lineAt(now,
            friends: [m('ben', 'Ben Ito')],
            feed: [wake('ben', 6, 5, onTime: false)]));
    expect(find.text('woke up'), findsOneWidget);
    expect(find.text('on time'), findsNothing);
  });

  testWidgets('the marker sits between the risen and the still-under',
      (t) async {
    final line = lineAt(now,
        friends: [m('ada', 'Ada'), m('cara', 'Cara')],
        statuses: {'cara': CrewStatus.asleep},
        feed: [wake('ada', 5, 42)]);
    expect(line.phase, MorningPhase.window);
    await pump(t, line);
    expect(find.byType(NowMarker), findsOneWidget);
    expect(find.text('NOW'), findsOneWidget);

    final markerY = t.getTopLeft(find.byType(NowMarker)).dy;
    expect(t.getTopLeft(find.text('Ada')).dy, lessThan(markerY));
    expect(t.getTopLeft(find.text('Cara')).dy, greaterThan(markerY));
  });

  testWidgets('the wrapped phase drops the marker — it is a record now',
      (t) async {
    final at = DateTime(2026, 7, 26, 11);
    final line = lineAt(at,
        friends: [m('ada', 'Ada')], feed: [wake('ada', 5, 42)]);
    expect(line.phase, MorningPhase.wrapped);
    await pump(t, line, at: at);
    expect(find.byType(NowMarker), findsNothing);
    expect(find.text('THE MORNING'), findsOneWidget);
  });

  testWidgets('someone who never woke reads as no wake logged', (t) async {
    final at = DateTime(2026, 7, 26, 11);
    await pump(
        t,
        lineAt(at,
            friends: [m('ada', 'Ada'), m('eve', 'Eve')],
            feed: [wake('ada', 5, 42)]),
        at: at);
    expect(find.text('no wake logged'), findsOneWidget);
  });

  testWidgets('a waking friend is promoted with a Cheer', (t) async {
    await pump(
        t,
        lineAt(now,
            friends: [m('cara', 'Cara')],
            statuses: {'cara': CrewStatus.waking}));
    expect(find.text('waking'), findsOneWidget);
    expect(find.byKey(const Key('line-wake-cheer-cara')), findsOneWidget);
  });

  testWidgets('your own waking row is never offered a cheer for yourself',
      (t) async {
    final line = buildMorningLine(
      now: now,
      friends: const [],
      statuses: const {},
      feed: const [],
      myId: 'me',
      myUsername: 'me',
      myStatus: CrewStatus.waking,
    );
    await pump(t, line);
    expect(find.byKey(const Key('line-wake-cheer-me')), findsNothing);
  });

  testWidgets('Cheer opens the palette and reports the emoji once', (t) async {
    final picked = <String>[];
    await pump(
      t,
      lineAt(now, friends: [m('ada', 'Ada')], feed: [wake('ada', 5, 42)]),
      onCheer: (_, e) => picked.add(e),
    );
    expect(find.byKey(const Key('line-cheer-ada')), findsOneWidget);

    await t.tap(find.byKey(const Key('line-cheer-ada')));
    await t.pump();
    await t.tap(find.byKey(const Key('line-cheer-ada-🔥')));
    await t.pump();

    expect(picked, ['🔥']);
    expect(find.byKey(const Key('line-cheer-ada')), findsOneWidget,
        reason: 'the palette closes again after a pick');
  });

  testWidgets('existing reactions show as a tally', (t) async {
    await pump(
      t,
      lineAt(now, friends: [m('ada', 'Ada')], feed: [
        wake('ada', 5, 42, react: const [
          FeedReaction(emoji: '🔥', count: 3, reactedByMe: true)
        ])
      ]),
    );
    expect(find.text('🔥 3'), findsOneWidget);
  });

  testWidgets('tapping a row opens that person; your own row does not',
      (t) async {
    final line = buildMorningLine(
      now: now,
      friends: [m('ada', 'Ada')],
      statuses: const {},
      feed: [wake('ada', 5, 42), wake('me', 5, 58)],
      myId: 'me',
      myUsername: 'me',
    );
    final opened = await pump(t, line);
    await t.tap(find.byKey(const Key('line-row-me')));
    await t.pump();
    expect(opened, isEmpty);

    await t.tap(find.byKey(const Key('line-row-ada')));
    await t.pump();
    expect(opened.single.username, 'ada');
  });

  testWidgets('an empty window says so instead of showing a bare rail',
      (t) async {
    await pump(t, lineAt(now));
    expect(find.text('Nobody yet — the window just opened.'), findsOneWidget);
  });

  testWidgets('the footer sits on the line, for the empty state', (t) async {
    await pump(t, lineAt(now),
        footer: const Text('This is where your crew shows up.'));
    expect(find.text('This is where your crew shows up.'), findsOneWidget);
  });

  testWidgets('a long crew truncates with a way to the rest', (t) async {
    final friends = [for (var i = 0; i < 12; i++) m('u$i', 'User $i')];
    final feed = [for (var i = 0; i < 12; i++) wake('u$i', 5, 10 + i)];
    await pump(t, lineAt(now, friends: friends, feed: feed));
    expect(find.byKey(const Key('line-see-earlier')), findsOneWidget);
    expect(find.text('4 earlier mornings'), findsOneWidget);
    expect(find.text('User 0'), findsNothing);
    expect(find.text('User 11'), findsOneWidget);
  });

  testWidgets('a big crew folds its quiet tail into one line', (t) async {
    final friends = [for (var i = 0; i < 14; i++) m('u$i', 'User $i')];
    await pump(
        t,
        lineAt(now,
            friends: friends,
            statuses: {for (final f in friends) f.id: CrewStatus.asleep}));
    expect(find.text('6 more still under'), findsOneWidget);
    // Ties are broken by username, which sorts as text: u0, u1, u10 … u9.
    expect(find.byKey(const Key('line-row-u0')), findsOneWidget);
    expect(find.byKey(const Key('line-row-u9')), findsNothing);
  });

  testWidgets('after the window the tail says what it means', (t) async {
    final at = DateTime(2026, 7, 26, 11);
    final friends = [for (var i = 0; i < 12; i++) m('u$i', 'User $i')];
    await pump(t, lineAt(at, friends: friends), at: at);
    expect(find.text('4 more with no wake logged'), findsOneWidget);
  });

  testWidgets('reduced motion keeps the marker static', (t) async {
    await pump(t, lineAt(now, friends: [m('ada', 'Ada')]),
        reduceMotion: true);
    expect(find.byType(NowMarker), findsOneWidget);
    // A repeating controller would leave a frame permanently scheduled.
    expect(t.binding.hasScheduledFrame, isFalse);
  });
}
