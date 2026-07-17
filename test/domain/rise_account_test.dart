import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/rise_account.dart';

void main() {
  const base = RiseAccount(
    id: 'uid-1',
    displayName: 'Ada',
    avatarColor: '#7C9CF4',
    username: 'ada',
    email: 'ada@example.com',
  );

  test('needsUsername is true only when username is null', () {
    const noName = RiseAccount(
      id: 'uid-2',
      displayName: '',
      avatarColor: '#7C9CF4',
    );
    expect(noName.needsUsername, isTrue);
    expect(noName.username, isNull);
    expect(base.needsUsername, isFalse);
  });

  test('copyWith overrides only the named fields', () {
    final claimed = const RiseAccount(
      id: 'uid-2',
      displayName: '',
      avatarColor: '#7C9CF4',
    ).copyWith(username: 'newby', displayName: 'New Person');

    expect(claimed.username, 'newby');
    expect(claimed.displayName, 'New Person');
    expect(claimed.id, 'uid-2');            // unchanged
    expect(claimed.avatarColor, '#7C9CF4'); // unchanged
    expect(claimed.needsUsername, isFalse);
  });

  test('copyWith with no arguments equals the original', () {
    expect(base.copyWith(), base);
  });

  test('value equality: same fields are equal and share a hashCode', () {
    const a = RiseAccount(
      id: 'uid-1',
      displayName: 'Ada',
      avatarColor: '#7C9CF4',
      username: 'ada',
      email: 'ada@example.com',
    );
    expect(a, base);
    expect(a.hashCode, base.hashCode);
  });

  test('value equality: differing on any field is unequal', () {
    expect(base.copyWith(id: 'other'), isNot(base));
    expect(base.copyWith(username: 'other'), isNot(base));
    expect(base.copyWith(displayName: 'other'), isNot(base));
    expect(base.copyWith(avatarColor: '#000000'), isNot(base));
    expect(base.copyWith(email: 'other@example.com'), isNot(base));
  });
}
