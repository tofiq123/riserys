import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/voice/voice_clip_service.dart';
import 'package:rise/data/voice/voice_player.dart';
import 'package:rise/data/voice/voice_recorder.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/voice_recording.dart';
import 'package:rise/ui/screens/voice_composer_screen.dart';
import 'package:rise/ui/state/voice_providers.dart';

const _ada = CrewMember(
    id: 'u1', username: 'ada', displayName: 'Ada', avatarColor: '#7C9CF4');

Future<(FakeVoiceRecorder, FakeVoicePlayer, FakeVoiceClipService)> _pump(
  WidgetTester t, {
  bool permission = true,
  String? failSendWith,
}) async {
  final recorder = FakeVoiceRecorder(
    permission: permission,
    result:
        const VoiceRecording(path: '/tmp/clip.m4a', duration: Duration(seconds: 5)),
  );
  final player = FakeVoicePlayer();
  addTearDown(player.dispose);
  final service = FakeVoiceClipService(failSendWith: failSendWith);

  t.view.physicalSize = const Size(1400, 3000);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);

  await t.pumpWidget(ProviderScope(
    overrides: [
      voiceRecorderProvider.overrideWithValue(recorder),
      voicePlayerProvider.overrideWithValue(player),
      voiceClipServiceProvider.overrideWithValue(service),
    ],
    child: const MaterialApp(home: VoiceComposerScreen(member: _ada)),
  ));
  await t.pumpAndSettle();
  return (recorder, player, service);
}

/// Drives idle → record → stop → recorded, using single-frame pumps (never
/// pumpAndSettle while the recording ticker is live).
Future<void> _recordThenStop(WidgetTester t) async {
  await t.tap(find.byKey(const Key('voice-record-button')));
  await t.pump(); // hasPermission
  await t.pump(); // start + setState → recording
  expect(find.byKey(const Key('voice-stop-button')), findsOneWidget);
  await t.tap(find.byKey(const Key('voice-stop-button')));
  await t.pump(); // stop() → recorded
  await t.pump();
}

void main() {
  testWidgets('shows the target and the idle record prompt', (t) async {
    await _pump(t);
    expect(find.text('Voice clip for @ada'), findsOneWidget);
    expect(find.textContaining('up to 30s'), findsOneWidget);
    expect(find.byKey(const Key('voice-record-button')), findsOneWidget);
  });

  testWidgets('record then stop reveals preview + send controls', (t) async {
    await _pump(t);
    await _recordThenStop(t);
    expect(find.byKey(const Key('voice-preview-button')), findsOneWidget);
    expect(find.byKey(const Key('voice-send-button')), findsOneWidget);
    expect(find.text('0:05'), findsOneWidget); // seeded recording duration
  });

  testWidgets('preview plays the local recording path', (t) async {
    final (_, player, _) = await _pump(t);
    await _recordThenStop(t);
    await t.tap(find.byKey(const Key('voice-preview-button')));
    await t.pumpAndSettle();
    expect(player.lastPlayed, '/tmp/clip.m4a');
  });

  testWidgets('send hands the recording to the service', (t) async {
    final (_, _, service) = await _pump(t);
    await _recordThenStop(t);
    await t.tap(find.byKey(const Key('voice-send-button')));
    await t.pumpAndSettle();
    expect(service.sent, hasLength(1));
    expect(service.sent.first.targetId, 'u1');
  });

  testWidgets('a send failure surfaces the message and stays on the clip',
      (t) async {
    await _pump(t, failSendWith: 'You can only send clips to your crew.');
    await _recordThenStop(t);
    await t.tap(find.byKey(const Key('voice-send-button')));
    await t.pumpAndSettle();
    expect(find.text('You can only send clips to your crew.'), findsOneWidget);
    // still on the composer, clip preserved
    expect(find.byKey(const Key('voice-send-button')), findsOneWidget);
  });

  testWidgets('denied mic permission never starts recording', (t) async {
    final (recorder, _, _) = await _pump(t, permission: false);
    await t.tap(find.byKey(const Key('voice-record-button')));
    await t.pump();
    await t.pump();
    expect(recorder.startCount, 0);
    expect(find.textContaining('Microphone access is needed'), findsOneWidget);
    expect(find.byKey(const Key('voice-record-button')), findsOneWidget);
  });
}
