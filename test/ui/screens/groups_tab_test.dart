import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/group/group_service.dart';
import 'package:rise/domain/group.dart';
import 'package:rise/ui/screens/group_detail_screen.dart';
import 'package:rise/ui/screens/groups_tab.dart';
import 'package:rise/ui/state/group_providers.dart';

Group _g(String id, String name, {String role = 'member'}) => Group(
      id: id,
      name: name,
      inviteCode: 'CODE$id',
      ownerId: role == 'owner' ? 'me' : 'other',
      role: role,
    );

Future<FakeGroupService> _pump(
  WidgetTester t, {
  List<Group> groups = const [],
  String joinCode = 'RISE42',
  Group? joinTarget,
}) async {
  final svc = FakeGroupService(
      groups: groups, joinCode: joinCode, joinTarget: joinTarget);

  t.view.physicalSize = const Size(2400, 9000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [groupServiceProvider.overrideWithValue(svc)],
    child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: GroupsTab()))),
  ));
  await t.pumpAndSettle();
  return svc;
}

void main() {
  testWidgets('lists my groups', (t) async {
    await _pump(t, groups: [_g('1', 'Early Risers'), _g('2', 'Night Owls')]);
    expect(find.text('Early Risers'), findsOneWidget);
    expect(find.text('Night Owls'), findsOneWidget);
  });

  testWidgets('empty state prompts to start or join', (t) async {
    await _pump(t);
    expect(find.textContaining('No groups yet'), findsOneWidget);
  });

  testWidgets('creating a group opens its detail page', (t) async {
    final svc = await _pump(t);
    await t.enterText(find.byKey(const Key('group-name-field')), 'Early Risers');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    expect((await svc.myGroups()).map((g) => g.name), ['Early Risers']);
    expect(find.byType(GroupDetailScreen), findsOneWidget);
  });

  testWidgets('joining with the right code opens the joined group', (t) async {
    await _pump(t,
        joinCode: 'RISE42',
        joinTarget: _g('j', 'Joined Crew'));
    await t.enterText(find.byKey(const Key('group-code-field')), 'rise42');
    await t.tap(find.text('Join'));
    await t.pumpAndSettle();
    expect(find.byType(GroupDetailScreen), findsOneWidget);
  });

  testWidgets('joining with a bad code shows an error, no navigation',
      (t) async {
    await _pump(t, joinCode: 'RISE42');
    await t.enterText(find.byKey(const Key('group-code-field')), 'wrong1');
    await t.tap(find.text('Join'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.text('No group with that code.'), findsOneWidget);
    expect(find.byType(GroupDetailScreen), findsNothing);
  });
}
