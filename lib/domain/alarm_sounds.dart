/// A selectable alarm tone. [asset] is the bundled audio path handed to the
/// native player (e.g. `sounds/rise_sunrise.wav`). The native layer maps it to a
/// raw resource (`R.raw.rise_sunrise`) and, for anything it can't resolve, falls
/// back to the platform default alarm tone — so the alarm ALWAYS rings.
///
/// [asset] may also be an absolute local file path (starting with `/` or
/// `file://`): that signals a downloaded voice clip used as the wake sound. Such
/// a value is not in [kAlarmSounds]; see [isFileSound].
class AlarmSound {
  const AlarmSound(this.label, this.asset);
  final String label;
  final String asset;
}

/// The label shown for a sound that is a local file (a friend's voice clip)
/// rather than one of the bundled tones. Not a real [kAlarmSounds] entry — the
/// picker synthesizes this chip only while a voice sound is selected.
const String kVoiceSoundLabel = 'Voice clip';

/// The first entry MUST be 'Default' → the entity's default `soundAsset`, so an
/// alarm created with no explicit sound reverse-maps to a selected chip. The
/// remaining entries are the bundled ringtone library; each `sounds/rise_<n>.wav`
/// maps native-side to `R.raw.rise_<n>`.
const List<AlarmSound> kAlarmSounds = [
  AlarmSound('Default', 'sounds/default_alarm.mp3'),
  AlarmSound('Sunrise', 'sounds/rise_sunrise.wav'),
  AlarmSound('Aurora', 'sounds/rise_aurora.wav'),
  AlarmSound('Tide', 'sounds/rise_tide.wav'),
  AlarmSound('Ascend', 'sounds/rise_ascend.wav'),
  AlarmSound('Kalimba', 'sounds/rise_kalimba.wav'),
  AlarmSound('Pulse', 'sounds/rise_pulse.wav'),
];

/// The display label for a stored asset path; falls back to the first entry.
String soundLabelFor(String asset) => kAlarmSounds
    .firstWhere((s) => s.asset == asset, orElse: () => kAlarmSounds.first)
    .label;

/// The asset path for a display label; falls back to the first entry.
String soundAssetFor(String label) => kAlarmSounds
    .firstWhere((s) => s.label == label, orElse: () => kAlarmSounds.first)
    .asset;

/// True when [asset] points at a local file (a downloaded voice clip) instead of
/// a bundled tone. The native player uses this to choose `setDataSource(path)`
/// over a raw resource, and the picker uses it to show the "Voice clip" chip.
bool isFileSound(String asset) =>
    asset.startsWith('/') || asset.startsWith('file://');

/// The Flutter asset-bundle key to PREVIEW [asset] in the picker, or null when
/// it can't be previewed from the bundle. The bundled tones live under
/// `assets/sounds/`; the Default tone is only a native raw resource (not a
/// Flutter asset) and voice-clip files aren't bundled, so both return null and
/// the picker simply plays no preview for them.
String? previewAssetKeyFor(String asset) {
  if (isFileSound(asset)) return null;
  if (asset == kAlarmSounds.first.asset) return null; // Default: not a Flutter asset
  final bundled = kAlarmSounds.any((s) => s.asset == asset);
  return bundled ? 'assets/$asset' : null;
}
