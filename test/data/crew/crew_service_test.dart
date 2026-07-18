import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/crew/crew_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_state.dart';

CrewMember _m(String id, String username) => CrewMember(
    id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

void main() {
  group('FakeCrewService', () {
    test('findByUsername resolves from the directory, case-insensitive; misses -> null',
        () async {
      final svc = FakeCrewService(directory: [_m('u1', 'ada')]);
      addTearDown(svc.dispose);
      expect((await svc.findByUsername('ADA'))?.id, 'u1');
      expect(await svc.findByUsername('nobody'), isNull);
    });

    test('sendRequest adds to outgoing and emits', () async {
      final svc = FakeCrewService(directory: [_m('u1', 'ada')]);
      addTearDown(svc.dispose);
      await svc.sendRequest('u1');
      expect(svc.current.outgoing.map((m) => m.id), ['u1']);
    });

    test('sendRequest rejects self, duplicate, and existing friend', () async {
      final svc = FakeCrewService(
        selfId: 'me',
        directory: [_m('u1', 'ada'), _m('me', 'myself')],
        initial: CrewState(friends: [_m('f1', 'bo')]),
      );
      addTearDown(svc.dispose);
      await expectLater(svc.sendRequest('me'), throwsA(isA<FriendshipException>()));
      await expectLater(svc.sendRequest('f1'), throwsA(isA<FriendshipException>()));
      await svc.sendRequest('u1');
      await expectLater(svc.sendRequest('u1'), throwsA(isA<FriendshipException>()));
    });

    test('sendRequest to an unknown id throws UserNotFoundException', () async {
      final svc = FakeCrewService();
      addTearDown(svc.dispose);
      await expectLater(svc.sendRequest('ghost'), throwsA(isA<UserNotFoundException>()));
    });

    test('sendRequest to someone who already asked you throws (accept instead)',
        () async {
      final svc = FakeCrewService(initial: CrewState(incoming: [_m('u1', 'ada')]));
      addTearDown(svc.dispose);
      await expectLater(
          svc.sendRequest('u1'), throwsA(isA<FriendshipException>()));
      // unchanged: still a pending incoming, nothing added to outgoing
      expect(svc.current.incoming.map((m) => m.id), ['u1']);
      expect(svc.current.outgoing, isEmpty);
    });

    test('acceptRequest moves incoming -> friends', () async {
      final svc = FakeCrewService(initial: CrewState(incoming: [_m('u1', 'ada')]));
      addTearDown(svc.dispose);
      await svc.acceptRequest('u1');
      expect(svc.current.friends.map((m) => m.id), ['u1']);
      expect(svc.current.incoming, isEmpty);
    });

    test('acceptRequest on a non-incoming id throws and changes nothing',
        () async {
      final svc = FakeCrewService();
      addTearDown(svc.dispose);
      await expectLater(
          svc.acceptRequest('ghost'), throwsA(isA<FriendshipException>()));
      expect(svc.current.friends, isEmpty);
    });

    test('declineRequest removes from incoming', () async {
      final svc = FakeCrewService(initial: CrewState(incoming: [_m('u1', 'ada')]));
      addTearDown(svc.dispose);
      await svc.declineRequest('u1');
      expect(svc.current.incoming, isEmpty);
      expect(svc.current.friends, isEmpty);
    });

    test('cancelRequest removes from outgoing', () async {
      final svc = FakeCrewService(initial: CrewState(outgoing: [_m('u1', 'ada')]));
      addTearDown(svc.dispose);
      await svc.cancelRequest('u1');
      expect(svc.current.outgoing, isEmpty);
    });

    test('removeFriend removes from friends', () async {
      final svc = FakeCrewService(initial: CrewState(friends: [_m('u1', 'ada')]));
      addTearDown(svc.dispose);
      await svc.removeFriend('u1');
      expect(svc.current.friends, isEmpty);
    });

    test('watch() emits current then updates', () async {
      final svc = FakeCrewService(directory: [_m('u1', 'ada')]);
      addTearDown(svc.dispose);
      final expectation = expectLater(
        svc.watch(),
        emitsInOrder([
          predicate<CrewState>((s) => s.isEmpty),
          predicate<CrewState>((s) => s.outgoing.any((m) => m.id == 'u1')),
        ]),
      );
      await Future<void>.delayed(Duration.zero);
      await svc.sendRequest('u1');
      await expectation;
    });
  });

  group('DisabledCrewService', () {
    const svc = DisabledCrewService();
    test('current/watch are empty, never throw', () async {
      expect(svc.current.isEmpty, isTrue);
      expect((await svc.watch().first).isEmpty, isTrue);
      expect(await svc.findByUsername('ada'), isNull);
    });
    test('writes throw', () {
      expect(svc.sendRequest('u1'), throwsA(isA<StateError>()));
      expect(svc.acceptRequest('u1'), throwsA(isA<StateError>()));
    });
  });
}
