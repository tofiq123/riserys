import 'dart:async';

import '../domain/group.dart';
import 'group/group_service.dart';

/// Group-invite deep links: `rise://invite/<CODE>`.
///
/// Pure helpers ([buildInviteLink] / [parseInviteCode]) plus the injectable
/// [InviteLinkHandler] that turns tapped links into `join_group_by_code` calls.
/// Nothing here imports Flutter or the `app_links` plugin — main.dart owns the
/// thin production wrapper that feeds the handler `AppLinks().uriLinkStream`,
/// so tests drive everything with a plain [Stream] and callbacks.

/// The custom URL scheme registered on both platforms (AndroidManifest
/// intent-filter + Info.plist CFBundleURLTypes).
const String inviteLinkScheme = 'rise';

/// The host part that marks a link as a group invite.
const String inviteLinkHost = 'invite';

/// The shareable deep link for a group's invite [code]:
/// `rise://invite/<CODE>`. The code is trimmed but otherwise passed through
/// as-is (codes are uppercase alphanumeric, so no percent-encoding is needed;
/// the join RPC normalizes case anyway).
String buildInviteLink(String code) =>
    '$inviteLinkScheme://$inviteLinkHost/${code.trim()}';

/// Extracts the invite code from [uri], or null if it is not a well-formed
/// invite link.
///
/// Strict on purpose — we generate these links ourselves, so anything that
/// doesn't match `rise://invite/<CODE>` exactly is rejected rather than
/// guessed at: wrong scheme or host, no code, an empty/whitespace code, extra
/// path segments, or any query/fragment junk all return null. The code itself
/// is trimmed but case-preserved — `join_group_by_code` (via
/// `GroupService.joinByCode`) owns case normalization, same as the type-a-code
/// sheet flow.
String? parseInviteCode(Uri uri) {
  // Uri already lowercases the scheme; comparing lowercase also tolerates a
  // platform handing us a raw 'RISE://…' string. Hosts are case-insensitive
  // per RFC 3986, so compare those lowercase too.
  if (uri.scheme.toLowerCase() != inviteLinkScheme) return null;
  if (uri.host.toLowerCase() != inviteLinkHost) return null;
  if (uri.hasQuery || uri.hasFragment) return null;
  final segments = uri.pathSegments;
  if (segments.length != 1) return null;
  final code = segments.first.trim();
  if (code.isEmpty) return null;
  return code;
}

/// Turns a stream of incoming app links into group joins, with the alarm
/// always taking priority over social.
///
/// Injectable: everything it touches — the ring gate, the signed-in gate, the
/// join call, and the three user-feedback outcomes — comes in as a callback,
/// so tests drive it with a [StreamController] and plain closures. Production
/// (main.dart) wires it to `AppLinks().uriLinkStream`, the auth/group
/// services, and [RiseToast]-style toasts.
///
/// Ring guard: a link is never allowed to disturb a ringing alarm. While the
/// ring screen is up ([isRingShowing]) the parsed code is queued (latest tap
/// wins) and nothing is shown; main.dart calls [onRingGone] when the ring
/// route reconciles back to null, which then processes the queued code. We
/// never navigate in any case — every outcome is a passive toast — so even a
/// race (an alarm firing mid-join) can at worst overlay a toast, never move
/// the user off the dismiss screen.
class InviteLinkHandler {
  InviteLinkHandler({
    required this.isRingShowing,
    required this.isSignedIn,
    required this.joinByCode,
    required this.onSignInNeeded,
    required this.onJoined,
    required this.onJoinFailed,
  });

  /// Whether the ring screen is currently showing (`_shownRingId != null`).
  final bool Function() isRingShowing;

  /// Whether a signed-in account exists (auth configured + session present).
  final bool Function() isSignedIn;

  /// The join call — production: `GroupService.joinByCode` (which trims and
  /// uppercases the code before the RPC).
  final Future<Group> Function(String code) joinByCode;

  /// A link arrived but the user is signed out or auth is unconfigured.
  final void Function() onSignInNeeded;

  /// The join succeeded.
  final void Function(Group group) onJoined;

  /// The join failed; [message] is user-facing (a [GroupException] message or
  /// a generic fallback).
  final void Function(String message) onJoinFailed;

  StreamSubscription<Uri>? _sub;
  String? _pendingCode;
  bool _handling = false;

  /// Subscribes to [uris] (initial link + later links in production). Stream
  /// errors — e.g. MissingPluginException in widget tests — go to [onError]
  /// and never throw.
  void listen(Stream<Uri> uris, {void Function(Object error)? onError}) {
    _sub?.cancel();
    _sub = uris.listen(
      (uri) => unawaited(handleUri(uri)),
      onError: onError ?? (Object _) {},
      cancelOnError: false,
    );
  }

  /// Handles one incoming link. Non-invite links are ignored silently.
  Future<void> handleUri(Uri uri) async {
    final code = parseInviteCode(uri);
    if (code == null) return;
    if (isRingShowing()) {
      // Never disturb a ringing alarm: queue (latest wins) until it pops.
      _pendingCode = code;
      return;
    }
    await _handle(code);
  }

  /// Call when the ring screen has popped (the shown ring id reconciled back
  /// to null); processes a link that arrived while the alarm was ringing.
  void onRingGone() {
    final code = _pendingCode;
    if (code == null) return;
    _pendingCode = null;
    unawaited(_handle(code));
  }

  Future<void> _handle(String code) async {
    // One join at a time; a link tapped while a join is already in flight is
    // dropped (double-tap protection — the first tap's outcome still toasts).
    if (_handling) return;
    _handling = true;
    try {
      if (!isSignedIn()) {
        onSignInNeeded();
        return;
      }
      try {
        final group = await joinByCode(code);
        onJoined(group);
      } on GroupException catch (e) {
        onJoinFailed(e.message);
      } catch (_) {
        onJoinFailed('Could not join the group.');
      }
    } finally {
      _handling = false;
    }
  }

  /// Cancels the subscription and drops any queued code.
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _pendingCode = null;
  }
}
