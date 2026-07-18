import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_member.dart';

void main() {
  const a = CrewMember(
      id: 'u1', username: 'ada', displayName: 'Ada', avatarColor: '#7C9CF4');

  test('value equality + hashCode', () {
    const b = CrewMember(
        id: 'u1', username: 'ada', displayName: 'Ada', avatarColor: '#7C9CF4');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('differs on any field', () {
    expect(a.copyWith(id: 'u2'), isNot(a));
    expect(a.copyWith(username: 'bo'), isNot(a));
    expect(a.copyWith(displayName: 'B'), isNot(a));
    expect(a.copyWith(avatarColor: '#000000'), isNot(a));
  });

  test('copyWith overrides only named fields', () {
    final c = a.copyWith(displayName: 'Ada L.');
    expect(c.displayName, 'Ada L.');
    expect(c.id, 'u1');
    expect(c.username, 'ada');
  });
}
