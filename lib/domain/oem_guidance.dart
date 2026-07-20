/// Manufacturer-specific guidance for keeping Rise alive in the background —
/// the "dontkillmyapp" problem. Several Android OEMs ship aggressive battery
/// managers that silently kill or block background apps, so a perfectly
/// scheduled alarm never rings. No API can fix this; the only remedy is to walk
/// the user to the right OEM setting. This maps a device's manufacturer string
/// to concrete, plain-language steps.
///
/// All logic here is pure and unit-tested. The exact menu labels differ across
/// OS versions and regional skins, so the steps are written to be
/// recognisable rather than pixel-exact, and every path is device-verify.
library;

/// The OEM families with notably aggressive background-app killing, plus a
/// [generic] fallback for everything else (Pixel, Motorola, Nokia, …).
enum OemVendor { samsung, xiaomi, huawei, oneplus, oppo, vivo, generic }

/// One manufacturer's guidance: a display [vendorLabel], a one-line [summary]
/// of why this phone is a risk, and the ordered [steps] to fix it.
class OemGuidance {
  const OemGuidance({
    required this.vendor,
    required this.vendorLabel,
    required this.summary,
    required this.steps,
  });

  final OemVendor vendor;
  final String vendorLabel;
  final String summary;
  final List<String> steps;

  /// True for the OEM families known to kill background apps aggressively.
  /// The [generic] fallback is false — its guidance is precautionary, not a
  /// known-bad flag.
  bool get isAggressive => vendor != OemVendor.generic;
}

/// Classifies a raw `Build.MANUFACTURER` (or brand) string into an [OemVendor].
/// Case-insensitive and null-safe; unknown or null manufacturers map to
/// [OemVendor.generic]. Sub-brands are folded into their parent (Redmi/POCO →
/// Xiaomi, Honor → Huawei, iQOO → Vivo, Realme → Oppo/ColorOS family).
OemVendor oemVendorFor(String? manufacturer) {
  final m = manufacturer?.trim().toLowerCase() ?? '';
  if (m.isEmpty) return OemVendor.generic;
  if (m.contains('samsung')) return OemVendor.samsung;
  if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
    return OemVendor.xiaomi;
  }
  if (m.contains('huawei') || m.contains('honor')) return OemVendor.huawei;
  if (m.contains('oneplus')) return OemVendor.oneplus;
  if (m.contains('oppo') || m.contains('realme')) return OemVendor.oppo;
  if (m.contains('vivo') || m.contains('iqoo')) return OemVendor.vivo;
  return OemVendor.generic;
}

/// Maps a manufacturer string to its [OemGuidance]. Pure; the returned steps
/// are stable content, safe to render directly.
OemGuidance oemGuidanceFor(String? manufacturer) =>
    _guidance[oemVendorFor(manufacturer)]!;

const Map<OemVendor, OemGuidance> _guidance = {
  OemVendor.samsung: OemGuidance(
    vendor: OemVendor.samsung,
    vendorLabel: 'Samsung',
    summary:
        'Samsung\'s Device Care can move Rise into "sleeping apps" and stop it '
        'from waking you.',
    steps: [
      'Open Settings → Battery → Background usage limits.',
      'Make sure Rise is NOT under "Sleeping apps" or "Deep sleeping apps".',
      'Tap "Never sleeping apps" and add Rise.',
      'Then Settings → Apps → Rise → Battery, and choose "Unrestricted".',
    ],
  ),
  OemVendor.xiaomi: OemGuidance(
    vendor: OemVendor.xiaomi,
    vendorLabel: 'Xiaomi (MIUI / HyperOS)',
    summary:
        'MIUI blocks autostart and aggressively closes background apps, which '
        'silences alarms.',
    steps: [
      'Open Settings → Apps → Manage apps → Rise and turn ON "Autostart".',
      'On the same Rise page, set "Battery saver" to "No restrictions".',
      'Open Recents, swipe down on Rise and tap the lock icon so it isn\'t '
          'cleared.',
      'If asked, allow Rise to run in the background whenever prompted.',
    ],
  ),
  OemVendor.huawei: OemGuidance(
    vendor: OemVendor.huawei,
    vendorLabel: 'Huawei / Honor',
    summary:
        'Huawei\'s PowerGenie force-stops apps unless you protect them by hand.',
    steps: [
      'Open Settings → Battery → App launch and find Rise.',
      'Turn OFF "Manage automatically" for Rise.',
      'Turn ON "Auto-launch", "Secondary launch", and "Run in background".',
      'Then Settings → Apps → Rise → Battery, and allow background activity.',
    ],
  ),
  OemVendor.oneplus: OemGuidance(
    vendor: OemVendor.oneplus,
    vendorLabel: 'OnePlus (OxygenOS)',
    summary:
        'OxygenOS\'s aggressive optimisation can sleep Rise overnight so it '
        'never rings.',
    steps: [
      'Open Settings → Battery → Battery optimization → Rise → "Don\'t '
          'optimize".',
      'Open Settings → Apps → Rise → Battery and enable "Allow background '
          'activity".',
      'Open Recents and lock Rise so it isn\'t cleared from memory.',
      'If you see "Advanced optimization / Deep optimization", turn it off for '
          'Rise.',
    ],
  ),
  OemVendor.oppo: OemGuidance(
    vendor: OemVendor.oppo,
    vendorLabel: 'Oppo / Realme (ColorOS)',
    summary:
        'ColorOS limits background running and auto-startup by default.',
    steps: [
      'Open Settings → Battery → App battery management → Rise.',
      'Enable "Allow background activity" and "Allow auto launch".',
      'Open the Phone Manager / Startup manager and allow Rise to auto-start.',
      'Open Recents and lock Rise so the system doesn\'t clear it.',
    ],
  ),
  OemVendor.vivo: OemGuidance(
    vendor: OemVendor.vivo,
    vendorLabel: 'Vivo / iQOO (Funtouch OS)',
    summary:
        'Funtouch OS blocks background running and autostart out of the box.',
    steps: [
      'Open Settings → Battery → Background power consumption management → '
          'Rise → "Allow".',
      'Open Settings → Apps → Autostart and enable Rise.',
      'Open the i Manager / Phone Manager and allow Rise to run in the '
          'background.',
      'Open Recents and lock Rise so it isn\'t cleared.',
    ],
  ),
  OemVendor.generic: OemGuidance(
    vendor: OemVendor.generic,
    vendorLabel: 'your phone',
    summary:
        'Some phones limit background apps to save battery, which can quietly '
        'silence alarms.',
    steps: [
      'Open Settings → Apps → Rise → Battery and choose "Unrestricted" or '
          '"Don\'t optimize".',
      'Allow Rise to run in the background and to start automatically.',
      'If your phone has a "protected apps" or "auto-launch" list, add Rise.',
      'Open Recents and lock Rise so it isn\'t cleared from memory.',
    ],
  ),
};
