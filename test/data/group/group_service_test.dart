import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/group/group_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/group.dart';
import 'package:rise/domain/wake_stats.dart';

CrewMember _m(String id) => CrewMember(
    id: id, username: id, displayName: id, avatarColor: '#7C9CF4');

CrewStanding _s(String id, int current) => CrewStanding(
    id: id,
    username: id,
    displayName: id,
    avatarColor: '#7C9CF4',
    stats: WakeStats(currentStreak: current));

Group _owned(String id) => Group(
    id: id,
    name: 'Owned $id',
    inviteCode: 'CODE$id',
    ownerId: 'me',
    role: 'owner');

Group _member(String id) => Group(
    id: id,
    name: 'Member $id',
    inviteCode: 'CODE$id',
    ownerId: 'other',
    role: 'member');

void main() {
  group('FakeGroupService', () {
    test('createGroup adds an owned group and returns it', () async {
      final svc = FakeGroupService();
      final g = await svc.createGroup('Early Risers');
      expect(g.name, 'Early Risers');
      expect(g.role, 'owner');
      expect(g.isOwner, isTrue);
      expect((await svc.myGroups()).map((x) => x.name), ['Early Risers']);
    });

    test('createGroup rejects a blank name', () async {
      final svc = FakeGroupService();
      await expectLater(
          svc.createGroup('   '), throwsA(isA<GroupException>()));
    });

    test('joinByCode with the right code joins; wrong code throws', () async {
      final svc = FakeGroupService(joinCode: 'RISE42');
      final g = await svc.joinByCode('rise42'); // case-insensitive
      expect(g.role, 'member');
      expect((await svc.myGroups()).any((x) => x.id == g.id), isTrue);
      await expectLater(
          svc.joinByCode('nope99'), throwsA(isA<GroupException>()));
    });

    test('myGroups is display-sorted', () async {
      final svc = FakeGroupService(groups: [
        _owned('z'),
        _member('a'),
      ]);
      // 'Member a' sorts before 'Owned z'
      expect((await svc.myGroups()).map((g) => g.id), ['a', 'z']);
    });

    test('a member can leave; an owner cannot', () async {
      final svc = FakeGroupService(groups: [_member('a'), _owned('b')]);
      await svc.leaveGroup('a');
      expect((await svc.myGroups()).map((g) => g.id), ['b']);
      await expectLater(
          svc.leaveGroup('b'), throwsA(isA<GroupException>()));
    });

    test('deleteGroup removes the group and its data', () async {
      final svc = FakeGroupService(
        groups: [_owned('b')],
        members: {'b': [_m('x')]},
        standings: {'b': [_s('x', 3)]},
      );
      await svc.deleteGroup('b');
      expect(await svc.myGroups(), isEmpty);
      expect(await svc.members('b'), isEmpty);
      expect(await svc.leaderboard('b'), isEmpty);
    });

    test('renameGroup changes the name', () async {
      final svc = FakeGroupService(groups: [_owned('b')]);
      await svc.renameGroup('b', 'New Name');
      expect((await svc.myGroups()).single.name, 'New Name');
    });

    test('removeMember drops them from roster and standings', () async {
      final svc = FakeGroupService(
        members: {'b': [_m('x'), _m('y')]},
        standings: {'b': [_s('x', 1), _s('y', 2)]},
      );
      await svc.removeMember('b', 'x');
      expect((await svc.members('b')).map((m) => m.id), ['y']);
      expect((await svc.leaderboard('b')).map((s) => s.id), ['y']);
    });

    test('leaderboard is ranked by streak', () async {
      final svc = FakeGroupService(
          standings: {'b': [_s('a', 2), _s('c', 5), _s('d', 3)]});
      expect((await svc.leaderboard('b')).map((s) => s.id), ['c', 'd', 'a']);
    });
  });

  group('DisabledGroupService', () {
    const svc = DisabledGroupService();
    test('reads are empty, never throw', () async {
      expect(await svc.myGroups(), isEmpty);
      expect(await svc.members('g'), isEmpty);
      expect(await svc.leaderboard('g'), isEmpty);
    });
    test('writes throw', () {
      expect(svc.createGroup('x'), throwsA(isA<StateError>()));
      expect(svc.joinByCode('x'), throwsA(isA<StateError>()));
      expect(svc.leaveGroup('g'), throwsA(isA<StateError>()));
      expect(svc.deleteGroup('g'), throwsA(isA<StateError>()));
      expect(svc.renameGroup('g', 'x'), throwsA(isA<StateError>()));
      expect(svc.removeMember('g', 'u'), throwsA(isA<StateError>()));
    });
  });
}
