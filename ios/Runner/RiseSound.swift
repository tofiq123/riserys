import Foundation

/// Resolves an app sound asset to the matching file bundled with the iOS app.
///
/// The Dart side stores tones as Flutter asset paths (`sounds/rise_klaxon.ogg`).
/// iOS cannot decode `.ogg`, so the whole library is mirrored into the bundle as
/// IMA4 `.caf` — see `ios/Runner/Sounds/`. Both the notification path and
/// AlarmKit name their sound by that bundled file, so the mapping lives here
/// once rather than in each engine.
///
/// Deliberately NOT `@available`-gated: iOS 16–25 needs it just as much as the
/// AlarmKit path does.
enum RiseSound {
  /// The bundled sound's base name (no extension), or nil when nothing matches
  /// — a voice-clip file path, or a tone with no `.caf` twin.
  ///
  /// Callers must fall back to the system default rather than passing an
  /// unresolvable name onward: a notification whose sound file does not exist is
  /// delivered **silently** by iOS, which is what made every alarm on this app
  /// soundless until 2026-08-24. Resolving here is what makes that impossible.
  static func bundledStem(for asset: String) -> String? {
    let base = (asset as NSString).lastPathComponent
    let stem = (base as NSString).deletingPathExtension
    guard !stem.isEmpty,
          Bundle.main.url(forResource: stem, withExtension: "caf") != nil
    else { return nil }
    return stem
  }
}
