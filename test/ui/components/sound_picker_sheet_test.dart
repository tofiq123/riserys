import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/alarm_sounds.dart';
import 'package:rise/ui/components/sound_picker_sheet.dart';

/// Records what the picker asks of the player without touching any platform.
class _FakePreviewer implements SoundPreviewer {
  final List<String> played = [];
  int stops = 0;
  bool disposed = false;

  @override
  Future<void> play(String assetKey) async => played.add(assetKey);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('lists Default + categories + tones and marks the current one',
      (t) async {
    final fake = _FakePreviewer();
    await t.pumpWidget(_host(SoundPickerSheet(
      initialAsset: kDefaultSound.asset,
      previewer: fake,
      onConfirm: (_) {},
      onCancel: () {},
    )));

    // Pinned Default at the top, checked because it's the current sound.
    expect(find.text('Default'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    // First category header + one of its tones are visible without scrolling.
    expect(find.text('GENTLE'), findsOneWidget);
    expect(find.text('Sunrise'), findsOneWidget);

    // Categories further down exist too — scroll to reach the last one.
    await t.scrollUntilVisible(find.text('BRUTAL'), 400,
        scrollable: find.byType(Scrollable));
    expect(find.text('BRUTAL'), findsOneWidget);
    expect(find.text('Air Raid'), findsOneWidget);
  });

  testWidgets('tapping a tone previews it, marks it selected, and Done confirms',
      (t) async {
    final fake = _FakePreviewer();
    String? confirmed;
    await t.pumpWidget(_host(SoundPickerSheet(
      initialAsset: kDefaultSound.asset,
      previewer: fake,
      onConfirm: (a) => confirmed = a,
      onCancel: () {},
    )));

    await t.tap(find.text('Sunrise'));
    await t.pump();

    // Previewed from the bundled asset, and now selected (check + volume glyph).
    expect(fake.played, ['assets/sounds/rise_sunrise.ogg']);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // Done applies the selected asset (not the old Default).
    await t.tap(find.text('Done'));
    await t.pump();
    expect(confirmed, 'sounds/rise_sunrise.ogg');
  });

  testWidgets(
      'an idle previewable tone still shows a persistent play affordance',
      (t) async {
    final fake = _FakePreviewer();
    await t.pumpWidget(_host(SoundPickerSheet(
      initialAsset: kDefaultSound.asset,
      previewer: fake,
      onConfirm: (_) {},
      onCancel: () {},
    )));

    // Nothing is previewing yet, but idle previewable tones advertise the play
    // control so the user can always see where to tap to (re)play a preview.
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);

    // Previewing swaps only that row's glyph to the volume icon; the other
    // idle tones keep their play affordance.
    await t.tap(find.text('Sunrise'));
    await t.pump();
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
  });

  testWidgets('re-tapping the playing tone stops the preview', (t) async {
    final fake = _FakePreviewer();
    await t.pumpWidget(_host(SoundPickerSheet(
      initialAsset: kDefaultSound.asset,
      previewer: fake,
      onConfirm: (_) {},
      onCancel: () {},
    )));

    await t.tap(find.text('Sunrise'));
    await t.pump();
    expect(fake.played, hasLength(1));
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);

    // Second tap on the same tone stops rather than replays.
    await t.tap(find.text('Sunrise'));
    await t.pump();
    expect(fake.played, hasLength(1)); // no new play
    expect(fake.stops, greaterThan(0));
    expect(find.byIcon(Icons.volume_up_rounded), findsNothing);
  });

  testWidgets('a voice-clip file sound shows a pinned, switchable Voice row',
      (t) async {
    final fake = _FakePreviewer();
    String? confirmed;
    const voicePath = '/data/user/0/app/voice_alarms/clip.m4a';
    await t.pumpWidget(_host(SoundPickerSheet(
      initialAsset: voicePath,
      previewer: fake,
      onConfirm: (a) => confirmed = a,
      onCancel: () {},
    )));

    // The voice clip is pinned and selected; it has no bundled preview.
    expect(find.text(kVoiceSoundLabel), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // Switching to a bundled tone previews it and confirming applies the tone.
    await t.tap(find.text('Sunrise'));
    await t.pump();
    expect(fake.played, ['assets/sounds/rise_sunrise.ogg']);
    await t.tap(find.text('Done'));
    await t.pump();
    expect(confirmed, 'sounds/rise_sunrise.ogg');
  });

  testWidgets('Cancel reports no selection', (t) async {
    final fake = _FakePreviewer();
    var cancelled = false;
    await t.pumpWidget(_host(SoundPickerSheet(
      initialAsset: kDefaultSound.asset,
      previewer: fake,
      onConfirm: (_) {},
      onCancel: () => cancelled = true,
    )));
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(cancelled, isTrue);
  });
}
