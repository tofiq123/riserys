import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_member.dart';
import 'package:rise/domain/voice_clip.dart';

const _sender = CrewMember(
    id: 'u1', username: 'ada', displayName: 'Ada', avatarColor: '#7C9CF4');

VoiceClip _clip({DateTime? playedAt}) => VoiceClip(
      id: 'c1',
      sender: _sender,
      storagePath: 'u1/abc.m4a',
      durationMs: 4200,
      createdAt: DateTime.utc(2026, 1, 1),
      playedAt: playedAt,
    );

void main() {
  group('VoiceClip', () {
    test('isPlayed reflects playedAt', () {
      expect(_clip().isPlayed, isFalse);
      expect(_clip(playedAt: DateTime.utc(2026, 1, 2)).isPlayed, isTrue);
    });

    test('duration derives from durationMs', () {
      expect(_clip().duration, const Duration(milliseconds: 4200));
    });

    test('copyWith stamps playedAt without touching other fields', () {
      final played = _clip().copyWith(playedAt: DateTime.utc(2026, 1, 3));
      expect(played.isPlayed, isTrue);
      expect(played.id, 'c1');
      expect(played.sender, _sender);
      expect(played.storagePath, 'u1/abc.m4a');
    });

    test('value equality', () {
      expect(_clip(), _clip());
      expect(_clip().hashCode, _clip().hashCode);
      expect(_clip(), isNot(_clip(playedAt: DateTime.utc(2026, 1, 2))));
    });
  });
}
