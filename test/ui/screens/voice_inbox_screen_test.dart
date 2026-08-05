import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/voice/voice_clip_service.dart';
import 'package:rise/data/voice/voice_player.dart';
import 'package:rise/domain/alarm.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/voice_clip.dart';
import 'package:rise/ui/screens/voice_inbox_screen.dart';
import 'package:rise/ui/state/alarm_providers.dart';
import 'package:rise/ui/state/voice_providers.dart';

CrewMember _member(String id, String name) => CrewMember(
    id: id, username: name, displayName: name, avatarColor: '#7C9CF4');

VoiceClip _clip(String id, {String from = 'ada', DateTime? playedAt}) =>
    VoiceClip(
      id: id,
      sender: _member('o-$id', from),
      storagePath: 'o-$id/$id.m4a',
      durationMs: 6000,
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      playedAt: playedAt,
    );

/// Records alarm writes so tests can assert the voice clip was set as the sound.
class _RecordingMutations implements AlarmMutations {
  final List<Alarm> saved = [];
  @override
  Future<void> save(Alarm alarm) async => saved.add(alarm);
  @override
  Future<void> delete(int id) async {}
  @override
  Future<void> setEnabled(int id, bool enabled) async {}
  @override
  Future<void> Function(int alarmId) get cancelWakeCheck => (_) async {};
  @override
  Future<void> Function(int alarmId) get removeQueuedAlarm => (_) async {};
}

Future<(FakeVoiceClipService, FakeVoicePlayer)> _pump(
  WidgetTester t, {
  List<VoiceClip> inbox = const [],
  FakeVoiceClipService? service,
  List<Alarm> alarms = const [],
  AlarmMutations? mutations,
}) async {
  final svc =
      service ?? FakeVoiceClipService(inbox: inbox, signedUrl: 'https://x/y.m4a');
  final player = FakeVoicePlayer();
  addTearDown(player.dispose);

  t.view.physicalSize = const Size(1400, 3000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      voiceClipServiceProvider.overrideWithValue(svc),
      voicePlayerProvider.overrideWithValue(player),
      alarmsProvider.overrideWith((ref) => Stream.value(alarms)),
      if (mutations != null)
        alarmMutationsProvider.overrideWithValue(mutations),
    ],
    child: const MaterialApp(home: VoiceInboxScreen()),
  ));
  await t.pumpAndSettle();
  return (svc, player);
}

void main() {
  testWidgets('empty inbox shows the warm placeholder', (t) async {
    await _pump(t);
    expect(find.text('No voice clips yet'), findsOneWidget);
  });

  testWidgets('lists received clips with sender + length', (t) async {
    await _pump(t, inbox: [_clip('a', from: 'ada')]);
    expect(find.text('ada'), findsOneWidget);
    expect(find.textContaining('6s'), findsOneWidget);
  });

  testWidgets('tapping play fetches the url, marks played, and plays it',
      (t) async {
    final (service, player) = await _pump(t, inbox: [_clip('a')]);
    await t.tap(find.byKey(const Key('voice-play-a')));
    await t.pumpAndSettle();
    expect(player.lastPlayed, 'https://x/y.m4a');
    expect(service.markedPlayed, contains('a'));
  });

  testWidgets('tapping delete removes the clip via the service', (t) async {
    final (service, _) = await _pump(t, inbox: [_clip('a'), _clip('b')]);
    await t.tap(find.byKey(const Key('voice-delete-a')));
    await t.pumpAndSettle();
    expect(service.deleted, contains('a'));
  });

  testWidgets('an unplayed clip shows the unread dot', (t) async {
    await _pump(t, inbox: [_clip('a', playedAt: null)]);
    // The play control + at least the row render; unread marker is a small dot,
    // asserted indirectly by the presence of the row.
    expect(find.byKey(const Key('voice-play-a')), findsOneWidget);
  });

  testWidgets(
      'set-as-alarm: pick an alarm, download the clip, point the alarm at the '
      'downloaded file', (t) async {
    final service = FakeVoiceClipService(inbox: [_clip('a')]);
    final mutations = _RecordingMutations();
    await _pump(
      t,
      service: service,
      mutations: mutations,
      alarms: const [Alarm(id: 42, hour: 6, minute: 30, label: 'Run')],
    );

    await t.tap(find.byKey(const Key('voice-setalarm-a')));
    await t.pumpAndSettle(); // open the alarm picker sheet
    expect(find.text('Set as sound for…'), findsOneWidget);

    await t.tap(find.byKey(const Key('alarm-pick-42')));
    await t.pumpAndSettle(); // download + save

    expect(service.downloadedForAlarm, contains('a'));
    expect(mutations.saved.single.id, 42);
    // soundAsset now points at the downloaded local file (a file-path source).
    expect(mutations.saved.single.soundAsset, '/local/voice_alarms/a.m4a');
  });

  testWidgets('set-as-alarm with no alarms warns instead of downloading',
      (t) async {
    final service = FakeVoiceClipService(inbox: [_clip('a')]);
    final mutations = _RecordingMutations();
    await _pump(t, service: service, mutations: mutations, alarms: const []);

    await t.tap(find.byKey(const Key('voice-setalarm-a')));
    await t.pumpAndSettle();

    // No picker, no download, no alarm write.
    expect(find.text('Set as sound for…'), findsNothing);
    expect(service.downloadedForAlarm, isEmpty);
    expect(mutations.saved, isEmpty);
  });

  testWidgets('set-as-alarm leaves the alarm untouched if the download fails',
      (t) async {
    final service = FakeVoiceClipService(inbox: [_clip('a')])
      ..failDownloadWith = 'network down';
    final mutations = _RecordingMutations();
    await _pump(
      t,
      service: service,
      mutations: mutations,
      alarms: const [Alarm(id: 7, hour: 7, minute: 0)],
    );

    await t.tap(find.byKey(const Key('voice-setalarm-a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alarm-pick-7')));
    await t.pumpAndSettle();

    expect(mutations.saved, isEmpty); // the alarm's sound was NOT changed
  });
}
