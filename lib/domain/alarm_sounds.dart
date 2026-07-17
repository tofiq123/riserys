/// A selectable alarm tone. [asset] is the bundled audio path handed to the
/// native player. Until real audio files are bundled, the native layer falls
/// back to the platform default alarm tone for any missing asset — so every
/// option currently rings the system default. The user's choice is still
/// persisted and is ready to sound the moment the files are added.
class AlarmSound {
  const AlarmSound(this.label, this.asset);
  final String label;
  final String asset;
}

/// The first entry MUST be 'Default' → the entity's default `soundAsset`, so an
/// alarm created with no explicit sound reverse-maps to a selected chip.
const List<AlarmSound> kAlarmSounds = [
  AlarmSound('Default', 'sounds/default_alarm.mp3'),
  AlarmSound('Radar', 'sounds/radar.mp3'),
  AlarmSound('Chimes', 'sounds/chimes.mp3'),
  AlarmSound('Beacon', 'sounds/beacon.mp3'),
  AlarmSound('Signal', 'sounds/signal.mp3'),
];

/// The display label for a stored asset path; falls back to the first entry.
String soundLabelFor(String asset) => kAlarmSounds
    .firstWhere((s) => s.asset == asset, orElse: () => kAlarmSounds.first)
    .label;

/// The asset path for a display label; falls back to the first entry.
String soundAssetFor(String label) => kAlarmSounds
    .firstWhere((s) => s.label == label, orElse: () => kAlarmSounds.first)
    .asset;
