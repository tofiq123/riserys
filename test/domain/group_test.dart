import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/group.dart';

Group _g(String id, String name, {String role = 'member'}) => Group(
      id: id,
      name: name,
      inviteCode: 'CODE$id',
      ownerId: role == 'owner' ? id : 'someone',
      role: role,
    );

void main() {
  group('Group', () {
    test('isOwner reflects the role', () {
      expect(_g('a', 'A', role: 'owner').isOwner, isTrue);
      expect(_g('a', 'A', role: 'member').isOwner, isFalse);
    });

    test('copyWith overrides only the given fields', () {
      final g = _g('a', 'Alpha', role: 'owner');
      final r = g.copyWith(name: 'Beta');
      expect(r.name, 'Beta');
      expect(r.id, 'a');
      expect(r.role, 'owner');
      expect(r.inviteCode, g.inviteCode);
    });

    test('value equality', () {
      expect(_g('a', 'A'), _g('a', 'A'));
      expect(_g('a', 'A'), isNot(_g('a', 'B')));
      expect(_g('a', 'A').hashCode, _g('a', 'A').hashCode);
    });
  });

  group('sortGroups', () {
    test('orders alphabetically, case-insensitive', () {
      final sorted = sortGroups([
        _g('1', 'Zephyr'),
        _g('2', 'alpha'),
        _g('3', 'Mango'),
      ]);
      expect(sorted.map((g) => g.name), ['alpha', 'Mango', 'Zephyr']);
    });

    test('ties break by id for stability', () {
      final sorted = sortGroups([
        _g('b', 'Crew'),
        _g('a', 'crew'),
      ]);
      expect(sorted.map((g) => g.id), ['a', 'b']);
    });

    test('does not mutate the input', () {
      final input = [_g('1', 'Zed'), _g('2', 'Ada')];
      sortGroups(input);
      expect(input.map((g) => g.name), ['Zed', 'Ada']);
    });
  });
}
