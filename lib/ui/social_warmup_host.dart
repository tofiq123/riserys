import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/auth_providers.dart';
import 'state/crew_providers.dart';
import 'state/feed_providers.dart';
import 'state/group_providers.dart';
import 'state/leaderboard_providers.dart';
import 'state/status_providers.dart';
import 'state/voice_providers.dart';

/// Warms the social data layer the moment a signed-in account is known, so the
/// first visit to Crew/Stats renders content instead of a spinner storm.
///
/// Providers here are all session-cached (non-autoDispose): listening once at
/// shell level starts their streams/fetches and keeps them primed across tab
/// switches. Signed out (or unconfigured) it listens to nothing and is inert —
/// the alarm path never depends on it.
class SocialWarmupHost extends ConsumerWidget {
  const SocialWarmupHost({super.key, required this.child});

  final Widget child;

  static void _noop(Object? previous, Object? next) {}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(accountProvider.select((a) => a.value != null));
    if (signedIn) {
      ref.listen(crewProvider, _noop);
      ref.listen(crewStatusesProvider, _noop);
      ref.listen(crewFeedProvider, _noop);
      ref.listen(myGroupsProvider, _noop);
      ref.listen(voiceInboxProvider, _noop);
      ref.listen(leaderboardProvider, _noop);
    }
    return child;
  }
}
