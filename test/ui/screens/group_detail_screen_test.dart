import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/group/group_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/group.dart';
import 'package:rise/domain/group_challenge.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/screens/group_detail_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/group_providers.dart';

CrewMember _m(String id) => CrewMember(
    id: id, username: id, displayName: id, avatarColor: '#7C9CF4');

CrewStanding _s(String id, int current, {bool isMe = false}) => CrewStanding(
    id: id,
    username: id,
    displayName: id,
    avatarColor: '#7C9CF4',
    stats: WakeStats(currentStreak: current),
    isMe: isMe);

Future<FakeGroupService> _pump(
  WidgetTester t, {
  required Group group,
  Map<String, List<CrewMember>> members = const {},
  Map<String, List<CrewStanding>> standings = const {},
  Map<String, GroupChallenge> challenges = const {},
  String selfId = 'me',
}) async {
  final auth = FakeAuthService(newAccountId: selfId);
  await auth.signInWithGoogle();
  await auth.claimUsername('me', displayName: 'Me');
  addTearDown(auth.dispose);

  final svc = FakeGroupService(
      selfId: selfId,
      groups: [group],
      members: members,
      standings: standings,
      challenges: challenges);

  t.view.physicalSize = const Size(2400, 9000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      groupServiceProvider.overrideWithValue(svc),
    ],
    child: MaterialApp(home: GroupDetailScreen(group: group)),
  ));
  await t.pumpAndSettle();
  return svc;
}

Group _owned() => const Group(
    id: 'g1',
    name: 'Early Risers',
    inviteCode: 'RISE42',
    ownerId: 'me',
    role: 'owner');

Group _joined() => const Group(
    id: 'g1',
    name: 'Night Owls',
    inviteCode: 'OWLS99',
    ownerId: 'other',
    role: 'member');

void main() {
  testWidgets('shows the invite code', (t) async {
    await _pump(t, group: _owned());
    expect(find.text('RISE42'), findsOneWidget);
    expect(find.text('Invite code'), findsOneWidget);
  });

  testWidgets('one merged member list: ranked rows, each person exactly once',
      (t) async {
    await _pump(t,
        group: _owned(),
        members: {
          'g1': [_m('me'), _m('bob')]
        },
        standings: {
          'g1': [_s('bob', 5), _s('me', 2, isMe: true)],
        });
    // ONE list: the standalone leaderboard section is gone, and each member
    // appears exactly once — on the podium OR in a row, never both.
    expect(find.text('STANDINGS'), findsOneWidget);
    expect(find.text('MEMBERS'), findsNothing);
    expect(find.text('GROUP LEADERBOARD'), findsNothing);
    expect(find.textContaining('@bob'), findsNothing,
        reason: 'bob leads, so he is on the podium rather than in a row');
    expect(find.byKey(const Key('podium-bob')), findsOneWidget);
    expect(find.byKey(const Key('group-row-bob')), findsNothing);
    expect(find.text('🔥5'), findsOneWidget); // bob's run, on his plinth
  });

  testWidgets('the morning leads the page and the invite sits near the end',
      (t) async {
    await _pump(t,
        group: _owned(),
        members: {
          'g1': [_m('me'), _m('bob')]
        },
        standings: {
          'g1': [_s('bob', 5), _s('me', 2, isMe: true)],
        });
    expect(find.byKey(const Key('group-morning-hero')), findsOneWidget);
    final morning = t.getTopLeft(find.byKey(const Key('group-morning-hero'))).dy;
    final standings = t.getTopLeft(find.text('STANDINGS')).dy;
    final invite = t.getTopLeft(find.text('INVITE')).dy;
    expect(morning, lessThan(standings));
    expect(standings, lessThan(invite),
        reason: 'the code is needed once; the group is why you opened this');
  });

  testWidgets('a group of one reads as a share screen, not an empty board',
      (t) async {
    await _pump(t, group: _owned(), members: {
      'g1': [_m('me')]
    });
    expect(find.byKey(const Key('group-solo-hero')), findsOneWidget);
    expect(find.text('A group of one is a good start.'), findsOneWidget);
    expect(find.text('RISE42'), findsOneWidget);
    expect(find.text('Share link'), findsOneWidget);
    // No podium, no standings, no race CTA for a group that has none of those.
    expect(find.text('STANDINGS'), findsNothing);
    expect(find.text('Start a streak race'), findsNothing);
  });

  testWidgets('a member with no wake data yet appends unranked', (t) async {
    await _pump(t,
        group: _owned(),
        members: {
          'g1': [_m('me'), _m('newbie')]
        },
        standings: {
          'g1': [_s('me', 2, isMe: true)],
        });
    expect(find.textContaining('@newbie'), findsOneWidget);
    expect(find.textContaining('no wakes yet'), findsOneWidget);
  });

  testWidgets('live race folds into the score card and member rows',
      (t) async {
    final started = DateTime.now().toUtc().subtract(const Duration(days: 3));
    await _pump(t,
        group: _owned(),
        members: {
          'g1': [_m('me'), _m('bob')]
        },
        standings: {
          'g1': [_s('bob', 5), _s('me', 2, isMe: true)],
        },
        challenges: {
          'g1': GroupChallenge(id: 'c1', groupId: 'g1', startedAt: started),
        });
    // Status line lives in the score area — no separate roster of racers.
    expect(find.textContaining('still standing'), findsOneWidget);
    expect(find.text('🔥'), findsWidgets); // in-race chip on member rows
    expect(find.text('Start a streak race'), findsNothing);
  });

  testWidgets('no race: owner sees the start CTA', (t) async {
    await _pump(t,
        group: _owned(),
        members: {
          'g1': [_m('me'), _m('bob')]
        },
        standings: {
          'g1': [_s('me', 2, isMe: true)],
        });
    expect(find.text('Start a streak race'), findsOneWidget);
  });

  testWidgets('no race: a member is told who can start one, not given a dead '
      'button', (t) async {
    await _pump(t,
        group: _joined(),
        members: {
          'g1': [_m('me'), _m('bob')]
        },
        standings: {
          'g1': [_s('me', 2, isMe: true)],
        });
    expect(find.textContaining('the group owner can start one'),
        findsOneWidget);
    expect(find.text('Start a streak race'), findsNothing);
  });

  testWidgets('owner sees Delete group; member sees Leave group', (t) async {
    await _pump(t, group: _owned());
    expect(find.text('Delete group'), findsOneWidget);
    expect(find.text('Leave group'), findsNothing);
  });

  testWidgets('member sees Leave group; no Delete', (t) async {
    await _pump(t, group: _joined(), selfId: 'me');
    expect(find.text('Leave group'), findsOneWidget);
    expect(find.text('Delete group'), findsNothing);
  });

  testWidgets('owner removes a member via the row overflow', (t) async {
    final svc = await _pump(t,
        group: _owned(),
        members: {'g1': [_m('me'), _m('bob')]});
    expect(find.textContaining('@bob'), findsOneWidget);
    // The always-visible Remove pill is gone; the action hides behind "…".
    expect(find.text('Remove'), findsNothing);
    await t.tap(find.byKey(const Key('member-overflow-bob')));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove from group'));
    await t.pumpAndSettle();
    expect((await svc.members('g1')).map((m) => m.id), ['me']);
    // The row itself is gone (the "Removed @bob." toast may still show).
    expect(find.byKey(const Key('member-overflow-bob')), findsNothing);
  });

  testWidgets('owner row shows an Owner badge and no overflow on self',
      (t) async {
    await _pump(t,
        group: _owned(),
        members: {'g1': [_m('me'), _m('bob')]});
    expect(find.text('Owner'), findsOneWidget);
    expect(find.byKey(const Key('member-overflow-me')), findsNothing);
    expect(find.byKey(const Key('member-overflow-bob')), findsOneWidget);
  });

  testWidgets('leaving calls the service', (t) async {
    final svc = await _pump(t, group: _joined());
    await t.tap(find.text('Leave group'));
    await t.pumpAndSettle();
    expect(await svc.myGroups(), isEmpty);
  });
}
