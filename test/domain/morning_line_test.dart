import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_status.dart';
import 'package:rise/domain/feed_item.dart';
import 'package:rise/domain/morning_line.dart';

void main() {
  CrewMember m(String id, String username) => CrewMember(
      id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

  FeedItem wake(String userId, DateTime at,
          {bool onTime = true, int streak = 5, List<FeedReaction> react = const []}) =>
      FeedItem(
        id: 'f_$userId',
        userId: userId,
        username: userId,
        displayName: userId,
        avatarColor: '#7C9CF4',
        wokeAt: at,
        onTime: onTime,
        streak: streak,
        reactions: react,
      );

  group('phaseFor', () {
    test('is tonight from 21:00 and before 04:00', () {
      for (final h in [21, 22, 23, 0, 2, 3]) {
        expect(
          phaseFor(
              now: DateTime(2026, 7, 26, h),
              todayWakes: const [],
              statuses: const []),
          MorningPhase.tonight,
          reason: 'hour $h',
        );
      }
    });

    test('is window while anyone is waking, even late in the day', () {
      expect(
        phaseFor(
            now: DateTime(2026, 7, 26, 14),
            todayWakes: const [],
            statuses: const [CrewStatus.asleep, CrewStatus.waking]),
        MorningPhase.window,
      );
    });

    test('night beats a waking status — bedtime is bedtime', () {
      expect(
        phaseFor(
            now: DateTime(2026, 7, 26, 22),
            todayWakes: const [],
            statuses: const [CrewStatus.waking]),
        MorningPhase.tonight,
      );
    });

    test('is window within three hours of the last wake', () {
      final now = DateTime(2026, 7, 26, 12);
      expect(
        phaseFor(
            now: now,
            todayWakes: [DateTime(2026, 7, 26, 9, 30)],
            statuses: const []),
        MorningPhase.window,
      );
    });

    test('goes wrapped once the last wake is over three hours old', () {
      expect(
        phaseFor(
            now: DateTime(2026, 7, 26, 12),
            todayWakes: [DateTime(2026, 7, 26, 8)],
            statuses: const []),
        MorningPhase.wrapped,
      );
    });

    test('is window before 10:00 even with nothing logged', () {
      expect(
        phaseFor(
            now: DateTime(2026, 7, 26, 5, 30),
            todayWakes: const [],
            statuses: const []),
        MorningPhase.window,
      );
    });

    test('is wrapped after 10:00 once the window has gone quiet', () {
      expect(
        phaseFor(
            now: DateTime(2026, 7, 26, 10, 1),
            todayWakes: const [],
            statuses: const []),
        MorningPhase.wrapped,
      );
    });

    test('a future wake from clock skew does not pin the window open', () {
      expect(
        phaseFor(
            now: DateTime(2026, 7, 26, 15),
            todayWakes: [DateTime(2026, 7, 26, 23)],
            statuses: const []),
        MorningPhase.wrapped,
      );
    });
  });

  group('buildMorningLine', () {
    final now = DateTime(2026, 7, 26, 6, 12);

    test('up is ascending by wake time; pending is ranked by status', () {
      final line = buildMorningLine(
        now: now,
        friends: [m('a', 'ada'), m('b', 'ben'), m('c', 'cara'), m('d', 'dan')],
        statuses: {
          'c': CrewStatus.waking,
          'd': CrewStatus.asleep,
        },
        feed: [
          wake('b', DateTime(2026, 7, 26, 6, 5)),
          wake('a', DateTime(2026, 7, 26, 5, 42)),
        ],
      );
      expect([for (final e in line.up) e.username], ['ada', 'ben']);
      expect([for (final e in line.pending) e.username], ['cara', 'dan']);
      expect(line.total, 4);
      expect(line.first!.username, 'ada');
    });

    test("only today's wakes count as up", () {
      final line = buildMorningLine(
        now: now,
        friends: [m('a', 'ada')],
        statuses: const {},
        feed: [wake('a', DateTime(2026, 7, 25, 5, 42))], // yesterday
      );
      expect(line.up, isEmpty);
      expect(line.pending.single.username, 'ada');
    });

    test('you appear in up when you have woken', () {
      final line = buildMorningLine(
        now: now,
        friends: [m('a', 'ada')],
        statuses: const {},
        feed: [wake('me', DateTime(2026, 7, 26, 5, 58))],
        myId: 'me',
        myUsername: 'me',
        myDisplayName: 'Me',
      );
      expect(line.up.single.isMe, isTrue);
      expect(line.up.single.shortName, 'You');
      expect(line.up.single.fullName, 'You');
    });

    test('you appear in pending with your own status when you have not', () {
      final line = buildMorningLine(
        now: now,
        friends: const [],
        statuses: const {},
        feed: const [],
        myId: 'me',
        myUsername: 'me',
        myStatus: CrewStatus.waking,
      );
      expect(line.up, isEmpty);
      expect(line.pending.single.isMe, isTrue);
      expect(line.pending.single.status, CrewStatus.waking);
    });

    test('a crew of nobody still shows your own row', () {
      final line = buildMorningLine(
        now: now,
        friends: const [],
        statuses: const {},
        feed: [wake('me', DateTime(2026, 7, 26, 5, 58))],
        myId: 'me',
        myUsername: 'me',
      );
      expect(line.total, 1);
      expect(line.up.single.isMe, isTrue);
    });

    test('you are never listed twice when you are also in the crew list', () {
      final line = buildMorningLine(
        now: now,
        friends: [m('me', 'me'), m('a', 'ada')],
        statuses: const {},
        feed: const [],
        myId: 'me',
        myUsername: 'me',
      );
      expect(line.total, 2);
      expect(line.pending.where((e) => e.id == 'me'), hasLength(1));
    });

    test('reactions and the feed id ride along for the cheer affordance', () {
      final line = buildMorningLine(
        now: now,
        friends: [m('a', 'ada')],
        statuses: const {},
        feed: [
          wake('a', DateTime(2026, 7, 26, 5, 42),
              react: const [FeedReaction(emoji: '🔥', count: 3, reactedByMe: true)])
        ],
      );
      final e = line.up.single;
      expect(e.feedId, 'f_a');
      expect(e.reactions.single.count, 3);
    });

    test('a status-only row has no feed id, so there is nothing to react to', () {
      final line = buildMorningLine(
        now: now,
        friends: [m('a', 'ada')],
        statuses: {'a': CrewStatus.asleep},
        feed: const [],
      );
      expect(line.pending.single.feedId, isNull);
    });

    test('a wake that was not on time reads as "woke up", never as late', () {
      final line = buildMorningLine(
        now: now,
        friends: [m('a', 'ada')],
        statuses: const {},
        feed: [wake('a', DateTime(2026, 7, 26, 7, 30), onTime: false)],
      );
      expect(line.up.single.verdict, 'woke up');
    });

    test('missed lists everyone with no wake at all', () {
      final line = buildMorningLine(
        now: DateTime(2026, 7, 26, 11),
        friends: [m('a', 'ada'), m('e', 'eve')],
        statuses: const {},
        feed: [wake('a', DateTime(2026, 7, 26, 5, 42))],
      );
      expect(line.phase, MorningPhase.wrapped);
      expect([for (final e in line.missed) e.username], ['eve']);
    });

    test('two feed rows for one person collapse to the later wake', () {
      final line = buildMorningLine(
        now: now,
        friends: [m('a', 'ada')],
        statuses: const {},
        feed: [
          wake('a', DateTime(2026, 7, 26, 5, 42), streak: 1),
          wake('a', DateTime(2026, 7, 26, 6, 5), streak: 2),
        ],
      );
      expect(line.up, hasLength(1));
      expect(line.up.single.streak, 2);
    });

    test('the empty line is a real value, not a null', () {
      expect(MorningLine.empty.total, 0);
      expect(MorningLine.empty.first, isNull);
      expect(MorningLine.empty.missed, isEmpty);
    });
  });
}
