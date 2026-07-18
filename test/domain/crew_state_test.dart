import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_state.dart';

void main() {
  const m = CrewMember(
      id: 'u1', username: 'ada', displayName: 'Ada', avatarColor: '#7C9CF4');

  test('empty is empty', () {
    expect(CrewState.empty.isEmpty, isTrue);
    expect(CrewState.empty.friends, isEmpty);
  });

  test('isEmpty is false when any list is non-empty', () {
    expect(const CrewState(friends: [m]).isEmpty, isFalse);
    expect(const CrewState(incoming: [m]).isEmpty, isFalse);
    expect(const CrewState(outgoing: [m]).isEmpty, isFalse);
  });

  test('value equality by list contents', () {
    expect(const CrewState(friends: [m]), const CrewState(friends: [m]));
    expect(const CrewState(friends: [m]).hashCode,
        const CrewState(friends: [m]).hashCode);
    expect(const CrewState(friends: [m]), isNot(const CrewState(incoming: [m])));
  });

  test('copyWith replaces only named lists', () {
    final s = CrewState.empty.copyWith(friends: const [m]);
    expect(s.friends, const [m]);
    expect(s.incoming, isEmpty);
  });
}
