import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/group/group_service.dart';
import 'package:rise/data/invite_links.dart';
import 'package:rise/domain/group.dart';

const _group = Group(
  id: 'g1',
  name: 'Early Risers',
  inviteCode: 'AB12CD',
  ownerId: 'other',
  role: 'member',
);

/// Builds an [InviteLinkHandler] whose gates are the mutable [ringShowing] /
/// [signedIn] fields and which records every callback outcome.
class _Harness {
  _Harness({
    this.ringShowing = false,
    this.signedIn = true,
    Future<Group> Function(String code)? join,
  }) {
    handler = InviteLinkHandler(
      isRingShowing: () => ringShowing,
      isSignedIn: () => signedIn,
      joinByCode: (code) {
        joinedCodes.add(code);
        return (join ?? (_) async => _group)(code);
      },
      onSignInNeeded: () => signInNeededCount++,
      onJoined: joined.add,
      onJoinFailed: failures.add,
    );
  }

  bool ringShowing;
  bool signedIn;
  late final InviteLinkHandler handler;

  final joinedCodes = <String>[];
  final joined = <Group>[];
  final failures = <String>[];
  int signInNeededCount = 0;
}

void main() {
  group('parseInviteCode', () {
    String? parse(String s) => parseInviteCode(Uri.parse(s));

    test('accepts a well-formed invite link', () {
      expect(parse('rise://invite/AB12CD'), 'AB12CD');
    });

    test('preserves the code case (the service normalizes, not the parser)',
        () {
      expect(parse('rise://invite/ab12cd'), 'ab12cd');
      expect(parse('rise://invite/Ab12Cd'), 'Ab12Cd');
    });

    test('scheme and host are case-insensitive', () {
      expect(parse('RISE://INVITE/AB12CD'), 'AB12CD');
      expect(parse('rise://Invite/AB12CD'), 'AB12CD');
    });

    test('rejects a missing or empty code', () {
      expect(parse('rise://invite'), isNull);
      expect(parse('rise://invite/'), isNull);
      expect(parse('rise://invite/%20%20'), isNull); // whitespace-only
    });

    test('trims surrounding whitespace from the code', () {
      expect(parse('rise://invite/%20%20AB12%20'), 'AB12');
    });

    test('rejects other schemes', () {
      expect(parse('https://invite/AB12CD'), isNull);
      expect(parse('risee://invite/AB12CD'), isNull);
      expect(parse('app://invite/AB12CD'), isNull);
    });

    test('rejects other hosts', () {
      expect(parse('rise://join/AB12CD'), isNull);
      expect(parse('rise://invitee/AB12CD'), isNull);
      expect(parse('rise:///AB12CD'), isNull); // empty host
    });

    test('rejects query junk', () {
      expect(parse('rise://invite/AB12CD?utm=1'), isNull);
      expect(parse('rise://invite/AB12CD?'), isNull);
    });

    test('rejects fragments', () {
      expect(parse('rise://invite/AB12CD#frag'), isNull);
    });

    test('rejects extra path segments', () {
      expect(parse('rise://invite/AB12CD/extra'), isNull);
      expect(parse('rise://invite/AB12CD/'), isNull); // trailing empty segment
    });
  });

  group('buildInviteLink', () {
    test('builds rise://invite/<CODE>', () {
      expect(buildInviteLink('AB12CD'), 'rise://invite/AB12CD');
    });

    test('trims the code', () {
      expect(buildInviteLink('  AB12CD '), 'rise://invite/AB12CD');
    });

    test('round-trips through parseInviteCode', () {
      final uri = Uri.parse(buildInviteLink('AB12CD'));
      expect(parseInviteCode(uri), 'AB12CD');
    });
  });

  group('InviteLinkHandler', () {
    late StreamController<Uri> links;

    // Broadcast, like app_links' own uriLinkStream — and close() on an
    // unlistened broadcast controller completes (a plain controller's would
    // hang tearDown in tests that never subscribe).
    setUp(() => links = StreamController<Uri>.broadcast());
    tearDown(() => links.close());

    Future<void> tap(_Harness h, String link) async {
      links.add(Uri.parse(link));
      await pumpEventQueue();
    }

    test('ignores non-invite links silently', () async {
      final h = _Harness()..handler.listen(links.stream);
      await tap(h, 'rise://other/AB12CD');
      await tap(h, 'https://example.com/');
      expect(h.joinedCodes, isEmpty);
      expect(h.signInNeededCount, 0);
      expect(h.failures, isEmpty);
    });

    test('signed out: asks to sign in, never calls join', () async {
      final h = _Harness(signedIn: false)..handler.listen(links.stream);
      await tap(h, 'rise://invite/AB12CD');
      expect(h.signInNeededCount, 1);
      expect(h.joinedCodes, isEmpty);
      expect(h.joined, isEmpty);
    });

    test('signed in: joins with the case-preserved code and reports success',
        () async {
      final h = _Harness()..handler.listen(links.stream);
      await tap(h, 'rise://invite/ab12cd');
      expect(h.joinedCodes, ['ab12cd']); // parser preserves; service uppercases
      expect(h.joined, [_group]);
      expect(h.failures, isEmpty);
    });

    test('surfaces the GroupException message on failure', () async {
      final h = _Harness(
          join: (_) async => throw const GroupException('No group with that code.'))
        ..handler.listen(links.stream);
      await tap(h, 'rise://invite/NOPE99');
      expect(h.failures, ['No group with that code.']);
      expect(h.joined, isEmpty);
    });

    test('maps unexpected errors to a generic message', () async {
      final h = _Harness(join: (_) async => throw StateError('boom'))
        ..handler.listen(links.stream);
      await tap(h, 'rise://invite/AB12CD');
      expect(h.failures, ['Could not join the group.']);
    });

    test('while the ring screen shows: queues, then joins on onRingGone',
        () async {
      final h = _Harness(ringShowing: true)..handler.listen(links.stream);
      await tap(h, 'rise://invite/AB12CD');
      expect(h.joinedCodes, isEmpty); // never disturb a ringing alarm
      expect(h.signInNeededCount, 0);

      h.ringShowing = false;
      h.handler.onRingGone();
      await pumpEventQueue();
      expect(h.joinedCodes, ['AB12CD']);
      expect(h.joined, [_group]);
    });

    test('while ringing, the latest tapped link wins', () async {
      final h = _Harness(ringShowing: true)..handler.listen(links.stream);
      await tap(h, 'rise://invite/FIRST1');
      await tap(h, 'rise://invite/SECOND');
      h.ringShowing = false;
      h.handler.onRingGone();
      await pumpEventQueue();
      expect(h.joinedCodes, ['SECOND']);
    });

    test('onRingGone with nothing queued is a no-op', () async {
      final h = _Harness()..handler.listen(links.stream);
      h.handler.onRingGone();
      await pumpEventQueue();
      expect(h.joinedCodes, isEmpty);
      expect(h.signInNeededCount, 0);
      expect(h.failures, isEmpty);
    });

    test('a queued code is only processed once', () async {
      final h = _Harness(ringShowing: true)..handler.listen(links.stream);
      await tap(h, 'rise://invite/AB12CD');
      h.ringShowing = false;
      h.handler.onRingGone();
      h.handler.onRingGone();
      await pumpEventQueue();
      expect(h.joinedCodes, ['AB12CD']);
    });

    test('drops a link tapped while a join is already in flight', () async {
      final gate = Completer<Group>();
      var calls = 0;
      final h = _Harness(join: (_) {
        calls++;
        return gate.future;
      })
        ..handler.listen(links.stream);
      await tap(h, 'rise://invite/AB12CD');
      await tap(h, 'rise://invite/OTHER1'); // in-flight — dropped
      expect(calls, 1);
      gate.complete(_group);
      await pumpEventQueue();
      expect(h.joined, [_group]);
      expect(h.joinedCodes, ['AB12CD']);
    });

    test('stream errors go to onError and do not break later links', () async {
      final errors = <Object>[];
      final h = _Harness();
      h.handler.listen(links.stream, onError: errors.add);
      links.addError(StateError('MissingPluginException-ish'));
      await pumpEventQueue();
      expect(errors, hasLength(1));
      await tap(h, 'rise://invite/AB12CD');
      expect(h.joinedCodes, ['AB12CD']);
    });

    test('dispose stops listening and drops the queue', () async {
      final h = _Harness(ringShowing: true)..handler.listen(links.stream);
      await tap(h, 'rise://invite/AB12CD');
      h.handler.dispose();
      h.ringShowing = false;
      h.handler.onRingGone(); // queue was dropped
      await pumpEventQueue();
      expect(h.joinedCodes, isEmpty);
    });

    test('end-to-end with FakeGroupService: a lowercase link code joins '
        '(service owns case normalization)', () async {
      final svc = FakeGroupService(joinCode: 'AB12CD');
      final joined = <Group>[];
      final failures = <String>[];
      final handler = InviteLinkHandler(
        isRingShowing: () => false,
        isSignedIn: () => true,
        joinByCode: svc.joinByCode,
        onSignInNeeded: () => fail('should not ask to sign in'),
        onJoined: joined.add,
        onJoinFailed: failures.add,
      );
      final code = parseInviteCode(Uri.parse('rise://invite/ab12cd'));
      await handler.handleUri(Uri.parse('rise://invite/ab12cd'));
      expect(code, 'ab12cd');
      expect(failures, isEmpty);
      expect(joined, hasLength(1));
      expect((await svc.myGroups()).any((g) => g.id == joined.single.id), isTrue);
    });
  });
}
