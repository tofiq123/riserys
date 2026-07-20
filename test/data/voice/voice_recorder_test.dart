import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/voice/voice_recorder.dart';
import 'package:rise/domain/voice_recording.dart';

void main() {
  group('kMaxVoiceClipDuration', () {
    test('caps clips at 30 seconds', () {
      expect(kMaxVoiceClipDuration, const Duration(seconds: 30));
    });
  });

  group('FakeVoiceRecorder', () {
    test('start then stop returns the seeded recording and toggles state',
        () async {
      final rec = FakeVoiceRecorder(
          result: const VoiceRecording(
              path: '/tmp/a.m4a', duration: Duration(seconds: 4)));
      expect(rec.isRecording, isFalse);

      await rec.start();
      expect(rec.isRecording, isTrue);
      expect(rec.startCount, 1);

      final clip = await rec.stop();
      expect(rec.isRecording, isFalse);
      expect(clip, const VoiceRecording(path: '/tmp/a.m4a', duration: Duration(seconds: 4)));
      expect(rec.stopCount, 1);
    });

    test('stop before start returns null', () async {
      final rec = FakeVoiceRecorder();
      expect(await rec.stop(), isNull);
    });

    test('double start does not restart', () async {
      final rec = FakeVoiceRecorder();
      await rec.start();
      await rec.start();
      expect(rec.startCount, 1);
    });

    test('hasPermission reflects the permission flag', () async {
      expect(await FakeVoiceRecorder(permission: true).hasPermission(), isTrue);
      expect(await FakeVoiceRecorder(permission: false).hasPermission(), isFalse);
    });

    test('cancel clears the recording state', () async {
      final rec = FakeVoiceRecorder();
      await rec.start();
      await rec.cancel();
      expect(rec.isRecording, isFalse);
      expect(rec.cancelCount, 1);
    });
  });

  group('VoiceRecording', () {
    test('value equality', () {
      const a = VoiceRecording(path: '/x.m4a', duration: Duration(seconds: 2));
      const b = VoiceRecording(path: '/x.m4a', duration: Duration(seconds: 2));
      const c = VoiceRecording(path: '/y.m4a', duration: Duration(seconds: 2));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
