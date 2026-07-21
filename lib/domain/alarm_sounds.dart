/// A category of alarm tones (e.g. `gentle` → "Gentle"). Categories group the
/// bundled ringtone library into browsable sections in the sound picker.
class SoundCategory {
  const SoundCategory(this.key, this.label);

  /// Stable lower-case key used in [AlarmSound.categoryKey] and lookups.
  final String key;

  /// Human display label shown as a section header (e.g. "Gentle").
  final String label;
}

/// A selectable alarm tone. [asset] is the bundled audio path handed to the
/// native player (e.g. `sounds/rise_sunrise.ogg`). The native layer strips the
/// extension and maps it to a raw resource (`R.raw.rise_sunrise`); for anything
/// it can't resolve it falls back to the platform default alarm tone — so the
/// alarm ALWAYS rings.
///
/// [asset] may also be an absolute local file path (starting with `/` or
/// `file://`): that signals a downloaded voice clip used as the wake sound. Such
/// a value is not in [kAlarmSounds]; see [isFileSound].
///
/// [categoryKey] is the [SoundCategory.key] this tone belongs to. The pinned
/// [kDefaultSound] uses the pseudo-category [kDefaultCategory].
class AlarmSound {
  const AlarmSound(this.label, this.asset, this.categoryKey);
  final String label;
  final String asset;
  final String categoryKey;
}

/// The label shown for a sound that is a local file (a friend's voice clip)
/// rather than one of the bundled tones. Not a real [kAlarmSounds] entry — the
/// picker synthesizes this row only while a voice sound is selected.
const String kVoiceSoundLabel = 'Voice clip';

/// The pseudo-category for the pinned [kDefaultSound]. Not part of
/// [kSoundCategories] (the browsable library sections) but a valid category any
/// tone's [AlarmSound.categoryKey] may resolve to.
const SoundCategory kDefaultCategory = SoundCategory('default', 'Default');

/// The browsable categories, in display order. Drives the sound picker's
/// section headers. The pinned Default tone lives outside this list.
const List<SoundCategory> kSoundCategories = [
  SoundCategory('gentle', 'Gentle'),
  SoundCategory('melodic', 'Melodic'),
  SoundCategory('energetic', 'Energetic'),
  SoundCategory('intense', 'Intense'),
  SoundCategory('nature', 'Nature'),
  SoundCategory('classic', 'Classic'),
  SoundCategory('brutal', 'Brutal'),
];

/// The pinned default tone. Its [AlarmSound.asset] MUST equal the entity's
/// default `Alarm.soundAsset`, so an alarm created with no explicit sound
/// reverse-maps to a selected entry. It is a native raw resource only
/// (`R.raw.default_alarm`) — not a Flutter asset — so it has no preview.
const AlarmSound kDefaultSound =
    AlarmSound('Default', 'sounds/default_alarm.mp3', 'default');

/// The 58 bundled tones per category, mirroring the library manifest. Each
/// `[assetName, displayLabel]` becomes `sounds/rise_<assetName>.ogg`.
const Map<String, List<List<String>>> _library = {
  'gentle': [
    ['sunrise', 'Sunrise'],
    ['aurora', 'Aurora'],
    ['kalimba', 'Kalimba'],
    ['dewdrop', 'Dewdrop'],
    ['lullaby', 'Lullaby'],
    ['driftwood', 'Driftwood'],
    ['meadow', 'Meadow'],
    ['harp', 'Harp'],
  ],
  'melodic': [
    ['ascend', 'Ascend'],
    ['musicbox', 'Music Box'],
    ['wanderer', 'Wanderer'],
    ['daybreak', 'Daybreak'],
    ['reverie', 'Reverie'],
    ['carousel', 'Carousel'],
    ['sonnet', 'Sonnet'],
    ['waltz', 'Waltz'],
  ],
  'energetic': [
    ['pulse', 'Pulse'],
    ['sprint', 'Sprint'],
    ['momentum', 'Momentum'],
    ['uplift', 'Uplift'],
    ['bounce', 'Bounce'],
    ['rally', 'Rally'],
    ['sunbeam', 'Sunbeam'],
    ['disco', 'Disco'],
  ],
  'intense': [
    ['klaxon', 'Klaxon'],
    ['overdrive', 'Overdrive'],
    ['redalert', 'Red Alert'],
    ['jackhammer', 'Jackhammer'],
    ['stampede', 'Stampede'],
    ['blitz', 'Blitz'],
    ['inferno', 'Inferno'],
  ],
  'nature': [
    ['tide', 'Tide'],
    ['rainfall', 'Rainfall'],
    ['birdsong', 'Birdsong'],
    ['forest', 'Forest'],
    ['ocean', 'Ocean'],
    ['brook', 'Brook'],
    ['storm', 'Storm'],
    ['crickets', 'Crickets'],
  ],
  'classic': [
    ['beacon', 'Beacon'],
    ['signal', 'Signal'],
    ['radar', 'Radar'],
    ['telegraph', 'Telegraph'],
    ['belltower', 'Bell Tower'],
    ['retro', 'Retro'],
    ['marimba', 'Marimba'],
    ['westminster', 'Westminster'],
  ],
  'brutal': [
    ['airraid', 'Air Raid'],
    ['firebell', 'Fire Bell'],
    ['buzzsaw', 'Buzzsaw'],
    ['dissonance', 'Dissonance'],
    ['banshee', 'Banshee'],
    ['emergency', 'Emergency'],
    ['foghorn', 'Foghorn'],
    ['meltdown', 'Meltdown'],
    ['warfare', 'Warfare'],
    ['siren', 'Siren'],
    ['warble', 'Warble'],
  ],
};

/// The full catalog: [kDefaultSound] pinned first, then every bundled tone in
/// category order ([kSoundCategories]). Built from [_library] so ordering and
/// category membership stay in lock-step with the categories list.
final List<AlarmSound> kAlarmSounds = [
  kDefaultSound,
  for (final cat in kSoundCategories)
    for (final e in _library[cat.key]!)
      AlarmSound(e[1], 'sounds/rise_${e[0]}.ogg', cat.key),
];

/// The tones in [key]'s category, in catalog order. The Default pseudo-category
/// returns just [kDefaultSound]. Unknown keys return an empty list.
List<AlarmSound> soundsInCategory(String key) =>
    kAlarmSounds.where((s) => s.categoryKey == key).toList();

/// The [SoundCategory] a stored [asset] belongs to, or null if the asset is not
/// a catalog tone (e.g. a voice-clip file path). Every entry in [kAlarmSounds]
/// resolves to a non-null category.
SoundCategory? soundCategoryFor(String asset) {
  for (final s in kAlarmSounds) {
    if (s.asset == asset) return _categoryByKey(s.categoryKey);
  }
  return null;
}

/// Looks up a [SoundCategory] by its [key], including the Default pseudo-
/// category. Returns null for an unknown key.
SoundCategory? _categoryByKey(String key) {
  if (key == kDefaultCategory.key) return kDefaultCategory;
  for (final c in kSoundCategories) {
    if (c.key == key) return c;
  }
  return null;
}

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
/// over a raw resource, and the picker uses it to show the "Voice clip" row.
bool isFileSound(String asset) =>
    asset.startsWith('/') || asset.startsWith('file://');

/// The Flutter asset-bundle key to PREVIEW [asset] in the picker, or null when
/// it can't be previewed from the bundle. The bundled tones live under
/// `assets/sounds/`; the Default tone is only a native raw resource (not a
/// Flutter asset) and voice-clip files aren't bundled, so both return null and
/// the picker simply plays no preview for them.
String? previewAssetKeyFor(String asset) {
  if (isFileSound(asset)) return null;
  if (asset == kDefaultSound.asset) return null; // Default: not a Flutter asset
  final bundled = kAlarmSounds.any((s) => s.asset == asset);
  return bundled ? 'assets/$asset' : null;
}
