import 'dart:async';

/// Signals when the deferred `Firebase.initializeApp()` call in `main.dart`'s
/// `_deferredStartup` has settled (succeeded or failed). Firebase init is
/// deferred past the first frame so the alarm dismiss screen never waits on
/// it — but anything that touches a Firebase Flutter plugin (e.g.
/// `firebase_messaging`) before it settles throws `[core/no-app]`, even
/// though a signed-in account can now render on the very first frame and
/// trigger that code well before Firebase catches up. Callers that need
/// Firebase should await [firebaseReady] rather than fire immediately.
final Completer<void> _firebaseReady = Completer<void>();

/// Completes [firebaseReady], once — safe to call more than once (e.g. if
/// `_deferredStartup` were ever re-entered).
void markFirebaseReady() {
  if (!_firebaseReady.isCompleted) _firebaseReady.complete();
}

Future<void> get firebaseReady => _firebaseReady.future;
