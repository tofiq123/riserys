import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/voice/voice_clip_service.dart';
import 'package:rise/ui/state/voice_providers.dart';

void main() {
  // In tests SUPABASE_* dart-defines are absent, so the app is "unconfigured".
  test('voiceClipServiceProvider degrades to the disabled service', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(voiceClipServiceProvider),
        isA<DisabledVoiceClipService>());
  });

  test('voiceInboxProvider is empty when unconfigured', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final inbox = await container.read(voiceInboxProvider.future);
    expect(inbox, isEmpty);
  });

  test('voiceClipServiceProvider honors an override', () {
    final fake = FakeVoiceClipService();
    final container = ProviderContainer(
        overrides: [voiceClipServiceProvider.overrideWithValue(fake)]);
    addTearDown(container.dispose);
    expect(container.read(voiceClipServiceProvider), same(fake));
  });
}
