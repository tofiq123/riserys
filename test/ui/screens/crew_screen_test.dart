import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/crew/crew_service.dart';
import 'package:rise/data/nudge/nudge_service.dart';
import 'package:rise/data/status/status_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_state.dart';
import 'package:rise/domain/crew_status.dart';
import 'package:rise/ui/components/rise_card.dart';
import 'package:rise/ui/screens/crew_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/crew_providers.dart';
import 'package:rise/ui/state/nudge_providers.dart';
import 'package:rise/ui/state/status_providers.dart';

CrewMember _m(String id, String username) => CrewMember(
    id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

Future<FakeCrewService> _pumpSignedIn(
  WidgetTester t, {
  CrewState initial = CrewState.empty,
  List<CrewMember> directory = const [],
  Map<String, CrewStatus> statuses = const {},
  NudgeService? nudge,
}) async {
  final auth = FakeAuthService();
  await auth.signInWithGoogle();
  await auth.claimUsername('me', displayName: 'Me');
  addTearDown(auth.dispose);
  final crew = FakeCrewService(
      selfId: auth.current!.id, initial: initial, directory: directory);
  addTearDown(crew.dispose);
  final status = FakeStatusService(initial: statuses);
  addTearDown(status.dispose);

  t.view.physicalSize = const Size(2400, 8000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      crewServiceProvider.overrideWithValue(crew),
      statusServiceProvider.overrideWithValue(status),
      if (nudge != null) nudgeServiceProvider.overrideWithValue(nudge),
    ],
    child: const MaterialApp(home: Scaffold(body: CrewScreen())),
  ));
  await t.pumpAndSettle();
  return crew;
}

void main() {
  testWidgets('signed out shows the Profile prompt', (t) async {
    await t.pumpWidget(const ProviderScope(
        child: MaterialApp(home: Scaffold(body: CrewScreen()))));
    await t.pumpAndSettle();
    expect(find.textContaining('Sign in from the Profile tab'), findsOneWidget);
  });

  testWidgets('accepting an incoming request moves them to your crew',
      (t) async {
    final crew = await _pumpSignedIn(t, initial: CrewState(incoming: [_m('u1', 'ada')]));
    expect(find.text('@ada'), findsOneWidget);
    await t.tap(find.text('Accept'));
    await t.pumpAndSettle();
    expect(crew.current.friends.map((m) => m.id), ['u1']);
    expect(crew.current.incoming, isEmpty);
  });

  testWidgets('declining an incoming request removes it', (t) async {
    final crew = await _pumpSignedIn(t, initial: CrewState(incoming: [_m('u1', 'ada')]));
    await t.tap(find.text('Decline'));
    await t.pumpAndSettle();
    expect(crew.current.incoming, isEmpty);
    expect(crew.current.friends, isEmpty);
  });

  testWidgets('find + add sends a friend request', (t) async {
    final crew = await _pumpSignedIn(t, directory: [_m('u1', 'ada')]);
    await t.enterText(find.byKey(const Key('crew-search-field')), 'ada');
    await t.tap(find.text('Find'));
    await t.pumpAndSettle();
    // The resolved member is shown with an Add action.
    await t.tap(find.text('Add'));
    await t.pumpAndSettle();
    expect(crew.current.outgoing.map((m) => m.id), ['u1']);
  });

  testWidgets('searching an unknown handle shows a not-found message',
      (t) async {
    await _pumpSignedIn(t);
    await t.enterText(find.byKey(const Key('crew-search-field')), 'ghost');
    await t.tap(find.text('Find'));
    await t.pumpAndSettle();
    expect(find.textContaining('No one with the handle'), findsOneWidget);
  });

  testWidgets('removing a friend asks to confirm first', (t) async {
    final crew = await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(crew.current.friends, isNotEmpty, reason: 'not removed until confirmed');
    await t.tap(find.byKey(const Key('confirm-dialog-confirm')));
    await t.pumpAndSettle();
    expect(crew.current.friends, isEmpty);
  });

  testWidgets('cancelling an outgoing request', (t) async {
    final crew = await _pumpSignedIn(t, initial: CrewState(outgoing: [_m('u1', 'ada')]));
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(crew.current.outgoing, isEmpty);
  });

  testWidgets('a crew member shows their live status label', (t) async {
    await _pumpSignedIn(t,
        initial: CrewState(friends: [_m('u1', 'ada')]),
        statuses: {'u1': CrewStatus.waking});
    // Scoped to ada's own row: the always-visible legend also renders the
    // word "Waking", so an unscoped find.text('Waking') would over-match.
    final row = find.ancestor(of: find.text('@ada'), matching: find.byType(RiseCard));
    expect(find.descendant(of: row, matching: find.text('Waking')),
        findsOneWidget);
  });

  testWidgets('a member with unknown status shows no status label', (t) async {
    await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
    // no status seeded -> unknown -> no label on ada's row (the legend still
    // renders these words elsewhere on the page, so scope to ada's row).
    final row = find.ancestor(of: find.text('@ada'), matching: find.byType(RiseCard));
    expect(find.descendant(of: row, matching: find.text('Awake')), findsNothing);
    expect(find.descendant(of: row, matching: find.text('Asleep')), findsNothing);
    expect(find.descendant(of: row, matching: find.text('Waking')), findsNothing);
  });

  testWidgets('nudging a crew member calls the nudge service', (t) async {
    final nudge = FakeNudgeService();
    await _pumpSignedIn(t,
        initial: CrewState(friends: [_m('u1', 'ada')]), nudge: nudge);
    await t.tap(find.text('Nudge'));
    await t.pumpAndSettle();
    expect(nudge.lastNudged, 'u1');
  });

  testWidgets('Nudge appears only on crew rows, not requests/pending',
      (t) async {
    await _pumpSignedIn(t,
        initial: CrewState(
            incoming: [_m('u1', 'ada')], outgoing: [_m('u2', 'bo')]));
    expect(find.text('Nudge'), findsNothing);
  });
}
