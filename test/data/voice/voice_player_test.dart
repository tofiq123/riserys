import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/voice/voice_player.dart';

void main() {
  group('FakeVoicePlayer', () {
    test('play records the source and emits playing true then false', () async {
      final player = FakeVoicePlayer();
      addTearDown(player.dispose);
      final states = <bool>[];
      final sub = player.playingStream.listen(states.add);

      await player.play('https://example.com/clip.m4a');
      await Future<void>.delayed(Duration.zero);

      expect(player.lastPlayed, 'https://example.com/clip.m4a');
      expect(player.playCount, 1);
      expect(states, [true, false]);
      await sub.cancel();
    });

    test('gate holds play open until released', () async {
      final player = FakeVoicePlayer();
      addTearDown(player.dispose);
      final gate = Completer<void>();
      player.gate = gate;

      var done = false;
      final future = player.play('/local.m4a').then((_) => done = true);
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse); // still "playing"

      gate.complete();
      await future;
      expect(done, isTrue);
    });

    test('stop increments the stop count', () async {
      final player = FakeVoicePlayer();
      addTearDown(player.dispose);
      await player.stop();
      expect(player.stopCount, 1);
    });
  });
}
