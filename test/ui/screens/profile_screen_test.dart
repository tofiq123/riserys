import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/auth/auth_service.dart';
import 'package:rise/data/native/alarm_api.g.dart';
import 'package:rise/data/permission_gateway.dart';
import 'package:rise/domain/rise_account.dart';
import 'package:rise/ui/components/rise_card.dart';
import 'package:rise/ui/components/rise_skeleton.dart';
import 'package:rise/ui/screens/profile_screen.dart';
import 'package:rise/ui/state/auth_providers.dart';

class _FakeGateway implements PermissionGateway {
  _FakeGateway(this._p);
  final AlarmPermissions _p;
  @override
  Future<AlarmPermissions> status() async => _p;
  @override
  Future<void> requestNotifications() async {}
  @override
  Future<void> openExactAlarm() async {}
  @override
  Future<void> openFullScreenIntent() async {}
  @override
  Future<void> openBattery() async {}
}

AlarmPermissions _perms() => AlarmPermissions(
    notifications: false,
    exactAlarm: false,
    fullScreenIntent: false,
    batteryUnrestricted: false);

// Profile is taller than flutter_test's default 800x600 viewport; enlarge the
// virtual view so nothing asserted is clipped offstage (same as before).
Future<void> _pump(
  WidgetTester t, {
  List<Override> overrides = const [],
  VoidCallback? onSettings,
}) async {
  t.view.physicalSize = const Size(2400, 8000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(
        body: ProfileScreen(
          permissions: _FakeGateway(_perms()),
          onSettings: onSettings,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

/// Auth whose account() never emits — the "restoring" window.
class _RestoringAuthService implements AuthService {
  final StreamController<RiseAccount?> _controller =
      StreamController<RiseAccount?>.broadcast();

  @override
  Stream<RiseAccount?> account() => _controller.stream;
  @override
  RiseAccount? get current => null;
  @override
  Future<void> signInWithGoogle() async {}
  @override
  Future<bool> isUsernameAvailable(String username) async => true;
  @override
  Future<void> claimUsername(String username,
      {required String displayName}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

void main() {
  testWidgets('restoring auth shows a skeleton — never the sign-in card',
      (t) async {
    t.view.physicalSize = const Size(2400, 8000);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(_RestoringAuthService()),
      ],
      child: MaterialApp(
        home: Scaffold(
            body: ProfileScreen(permissions: _FakeGateway(_perms()))),
      ),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Sign in to Riserys'), findsNothing);
    expect(find.text('Sign in with Google'), findsNothing);
    expect(find.byType(RiseSkeleton), findsWidgets);
  });

  testWidgets('Settings and the wellbeing check-in share one grouped card',
      (t) async {
    await _pump(t);
    final settingsCard = find.ancestor(
        of: find.text('Settings'), matching: find.byType(RiseCard));
    final wellbeingCard = find.ancestor(
        of: find.text("How you've been feeling"),
        matching: find.byType(RiseCard));
    expect(settingsCard, findsOneWidget);
    expect(t.widget(settingsCard), same(t.widget(wellbeingCard)),
        reason: 'both rows live in one grouped card');
  });

  testWidgets('unconfigured: shows the guest card, permissions, and about',
      (t) async {
    // No override → default authServiceProvider is DisabledAuthService.
    await _pump(t);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Grant'), findsNWidgets(4));
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsNothing);
  });

  testWidgets('tapping the Settings row calls onSettings', (t) async {
    var tapped = false;
    await _pump(t, onSettings: () => tapped = true);
    await t.tap(find.text('Settings'));
    await t.pump();
    expect(tapped, isTrue);
  });

  testWidgets('configured + signed out: shows Sign in with Google and it works',
      (t) async {
    final fake = FakeAuthService();
    addTearDown(fake.dispose);
    await _pump(t, overrides: [authServiceProvider.overrideWithValue(fake)]);

    expect(find.text('Guest'), findsNothing);
    expect(find.text('Sign in with Google'), findsOneWidget);

    await t.tap(find.text('Sign in with Google'));
    await t.pumpAndSettle();
    expect(fake.current, isNotNull, reason: 'signed in');
  });

  testWidgets('signed in: shows the handle and Sign out signs out', (t) async {
    final fake = FakeAuthService();
    await fake.signInWithGoogle();
    await fake.claimUsername('ada', displayName: 'Ada L.');
    addTearDown(fake.dispose);
    await _pump(t, overrides: [authServiceProvider.overrideWithValue(fake)]);

    expect(find.text('@ada'), findsOneWidget);
    // Sign out now asks for confirmation first (no accidental silent logout).
    await t.tap(find.text('Sign out'));
    await t.pumpAndSettle();
    expect(fake.current, isNotNull, reason: 'not signed out until confirmed');
    // Sign-out now uses the shared Mono confirm dialog (confirm key below).
    await t.tap(find.byKey(const Key('confirm-dialog-confirm')));
    await t.pumpAndSettle();
    expect(fake.current, isNull);
  });

  testWidgets('signed in: Delete account requires typing DELETE, then deletes',
      (t) async {
    final fake = FakeAuthService();
    await fake.signInWithGoogle();
    await fake.claimUsername('ada', displayName: 'Ada L.');
    addTearDown(fake.dispose);
    await _pump(t, overrides: [authServiceProvider.overrideWithValue(fake)]);

    await t.tap(find.text('Delete account'));
    await t.pumpAndSettle();
    // Dialog is open; the confirm action is disabled until DELETE is typed.
    await t.enterText(find.byKey(const Key('delete-confirm-field')), 'DELETE');
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('delete-confirm-button')));
    await t.pumpAndSettle();
    expect(fake.current, isNull);
  });
}
