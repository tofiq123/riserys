import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/crew/crew_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/crew_state.dart';
import 'package:rise/ui/screens/crew_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';
import 'package:rise/ui/state/crew_providers.dart';

CrewMember _m(String id, String username) => CrewMember(
    id: id, username: username, displayName: username, avatarColor: '#7C9CF4');

Future<FakeCrewService> _pumpSignedIn(
  WidgetTester t, {
  CrewState initial = CrewState.empty,
  List<CrewMember> directory = const [],
}) async {
  final auth = FakeAuthService();
  await auth.signInWithGoogle();
  await auth.claimUsername('me', displayName: 'Me');
  addTearDown(auth.dispose);
  final crew = FakeCrewService(
      selfId: auth.current!.id, initial: initial, directory: directory);
  addTearDown(crew.dispose);

  t.view.physicalSize = const Size(2400, 8000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(auth),
      crewServiceProvider.overrideWithValue(crew),
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

  testWidgets('removing a friend', (t) async {
    final crew = await _pumpSignedIn(t, initial: CrewState(friends: [_m('u1', 'ada')]));
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(crew.current.friends, isEmpty);
  });

  testWidgets('cancelling an outgoing request', (t) async {
    final crew = await _pumpSignedIn(t, initial: CrewState(outgoing: [_m('u1', 'ada')]));
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(crew.current.outgoing, isEmpty);
  });
}
