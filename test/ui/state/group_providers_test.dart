import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/group/group_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/group.dart';
import 'package:rise/domain/wake_stats.dart';
import 'package:rise/ui/state/group_providers.dart';

Group _g(String id, String name) =>
    Group(id: id, name: name, inviteCode: 'C$id', ownerId: 'me', role: 'owner');

CrewStanding _s(String id, int current) => CrewStanding(
    id: id,
    username: id,
    displayName: id,
    avatarColor: '#7C9CF4',
    stats: WakeStats(currentStreak: current));

void main() {
  test('unconfigured: groupServiceProvider is Disabled, myGroups empty',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(groupServiceProvider), isA<DisabledGroupService>());
    expect(await container.read(myGroupsProvider.future), isEmpty);
  });

  test('myGroupsProvider returns the (overridden) fake groups, sorted',
      () async {
    final fake = FakeGroupService(groups: [_g('1', 'Zed'), _g('2', 'Ada')]);
    final container = ProviderContainer(overrides: [
      groupServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    final groups = await container.read(myGroupsProvider.future);
    expect(groups.map((g) => g.name), ['Ada', 'Zed']);
  });

  test('groupLeaderboardProvider ranks the fake standings', () async {
    final fake = FakeGroupService(
        standings: {'g1': [_s('a', 1), _s('b', 4)]});
    final container = ProviderContainer(overrides: [
      groupServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    final board = await container.read(groupLeaderboardProvider('g1').future);
    expect(board.map((s) => s.id), ['b', 'a']);
  });

  test('groupMembersProvider returns the fake roster', () async {
    final fake = FakeGroupService(members: {
      'g1': [
        const CrewMember(
            id: 'x', username: 'x', displayName: 'X', avatarColor: '#7C9CF4'),
      ]
    });
    final container = ProviderContainer(overrides: [
      groupServiceProvider.overrideWithValue(fake),
    ]);
    addTearDown(container.dispose);
    final members = await container.read(groupMembersProvider('g1').future);
    expect(members.map((m) => m.id), ['x']);
  });
}
