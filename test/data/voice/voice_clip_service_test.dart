import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/voice/voice_clip_service.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/voice_clip.dart';
import 'package:rise/domain/voice_recording.dart';

const _sender = CrewMember(
    id: 'u1', username: 'ada', displayName: 'Ada', avatarColor: '#7C9CF4');

VoiceClip _clip(String id, {DateTime? playedAt}) => VoiceClip(
      id: id,
      sender: _sender,
      storagePath: 'u1/$id.m4a',
      durationMs: 3000,
      createdAt: DateTime.utc(2026, 1, 1),
      playedAt: playedAt,
    );

const _recording =
    VoiceRecording(path: '/tmp/x.m4a', duration: Duration(seconds: 3));

void main() {
  group('FakeVoiceClipService', () {
    test('send records the target + recording', () async {
      final svc = FakeVoiceClipService();
      await svc.send(targetId: 'u1', recording: _recording);
      expect(svc.sent, hasLength(1));
      expect(svc.sent.first.targetId, 'u1');
      expect(svc.sent.first.recording, _recording);
    });

    test('send throws when configured to fail', () async {
      final svc = FakeVoiceClipService(failSendWith: 'nope');
      await expectLater(
        svc.send(targetId: 'u1', recording: _recording),
        throwsA(isA<VoiceClipException>()),
      );
      expect(svc.sent, isEmpty);
    });

    test('inbox returns the seeded clips', () async {
      final svc = FakeVoiceClipService(inbox: [_clip('a'), _clip('b')]);
      final list = await svc.inbox();
      expect(list.map((c) => c.id), ['a', 'b']);
    });

    test('markPlayed records the id and flips the clip to played', () async {
      final svc = FakeVoiceClipService(inbox: [_clip('a')]);
      await svc.markPlayed('a');
      expect(svc.markedPlayed, ['a']);
      final list = await svc.inbox();
      expect(list.single.isPlayed, isTrue);
    });

    test('delete removes the clip from the inbox', () async {
      final svc = FakeVoiceClipService(inbox: [_clip('a'), _clip('b')]);
      await svc.delete(_clip('a'));
      expect(svc.deleted, ['a']);
      final list = await svc.inbox();
      expect(list.map((c) => c.id), ['b']);
    });

    test('urlFor returns the configured signed url', () async {
      final svc = FakeVoiceClipService(signedUrl: 'https://x/y.m4a');
      expect(await svc.urlFor(_clip('a')), 'https://x/y.m4a');
    });
  });

  group('DisabledVoiceClipService', () {
    const svc = DisabledVoiceClipService();

    test('inbox is empty', () async {
      expect(await svc.inbox(), isEmpty);
    });

    test('send throws', () async {
      await expectLater(
        svc.send(targetId: 'u1', recording: _recording),
        throwsA(isA<StateError>()),
      );
    });

    test('markPlayed and delete are no-ops', () async {
      await svc.markPlayed('a'); // must not throw
      await svc.delete(_clip('a')); // must not throw
    });
  });
}
