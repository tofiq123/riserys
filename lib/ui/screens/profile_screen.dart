import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/supabase_config.dart';
import '../../data/auth/auth_service.dart';
import '../../data/permission_gateway.dart';
import '../../data/push/push_registrar.dart';
import '../../domain/rise_account.dart';
import '../components/confirm_dialog.dart';
import '../components/permissions_section.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/rise_skeleton.dart';
import '../components/section_label.dart';
import '../components/toast.dart';
import '../state/auth_providers.dart';
import '../state/entitlement_providers.dart';
import '../theme/avatar_color.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'paywall_screen.dart';
import 'setup_guardian_screen.dart';
import 'wellbeing_checkin_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen(
      {super.key,
      this.permissions = const NativePermissionGateway(),
      this.onSettings});

  final PermissionGateway permissions;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 8, RiseSpacing.screen, 40),
        children: [
          Text('Profile', style: RiseText.display),
          const SizedBox(height: 16),
          const _AccountSection(),
          const SizedBox(height: 24),
          const _PremiumEntry(),
          const SizedBox(height: 12),
          RiseCard(
            child: Column(
              children: [
                _NavRow(
                  icon: Icons.tune,
                  title: 'Settings',
                  onTap: onSettings,
                ),
                Divider(height: 24, color: RiseColors.divider),
                _NavRow(
                  key: const Key('wellbeing-checkin-entry'),
                  icon: Icons.favorite_outline,
                  title: 'How you\'ve been feeling',
                  caption: 'A quick, private check-in — optional, anytime',
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => const WellbeingCheckinScreen())),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionLabel('Reliability'),
          const SizedBox(height: 6),
          Text('Make sure Riserys can always reach you.', style: RiseText.caption),
          const SizedBox(height: 12),
          RiseCard(
            child: _NavRow(
              key: const Key('setup-guardian-entry'),
              icon: Icons.shield_outlined,
              title: 'Setup Guardian',
              caption: 'Check everything that keeps your alarm firing',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      SetupGuardianScreen(permissions: permissions))),
            ),
          ),
          const SizedBox(height: 12),
          PermissionsSection(gateway: permissions),
          const SizedBox(height: 24),
          const SectionLabel('About'),
          const SizedBox(height: 12),
          RiseCard(
            child: Column(
              children: [
                _aboutRow('Version', '1.0.0'),
                Divider(height: 20, color: RiseColors.divider),
                _aboutRow('Made for', 'waking up, 100%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aboutRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: RiseText.body.copyWith(color: RiseColors.textDim)),
        Text(value, style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// One row of a grouped Profile card: icon, title (+ optional caption),
/// chevron. Rows sharing a card are separated by a hairline divider — one
/// surface per group instead of a stack of identical single-row cards.
class _NavRow extends StatelessWidget {
  const _NavRow({
    super.key,
    required this.icon,
    required this.title,
    this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: RiseColors.textDim, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: caption == null
                ? Text(title,
                    style: RiseText.body.copyWith(fontWeight: FontWeight.w600))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: RiseText.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(caption!, style: RiseText.caption),
                    ],
                  ),
          ),
          Icon(Icons.chevron_right, color: RiseColors.textFaint, size: 20),
        ],
      ),
    );
  }
}

/// The "Riserys Premium" row: opens the paywall, or shows an "Active" state when
/// premium (including the unconfigured graceful-degrade default, where everyone
/// is premium). Never gates anything itself — just the way in.
class _PremiumEntry extends ConsumerWidget {
  const _PremiumEntry();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPremium = ref.watch(isPremiumProvider).value ?? true;
    return GestureDetector(
      key: const Key('premium-entry'),
      behavior: HitTestBehavior.opaque,
      onTap: () => openPaywall(context),
      child: RiseCard(
        child: Row(
          children: [
            Icon(isPremium ? Icons.verified : Icons.workspace_premium_outlined,
                color: isPremium ? RiseColors.primary : RiseColors.accent,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Riserys Premium',
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                      isPremium
                          ? 'Active — everything unlocked'
                          : 'Unlock every mission, deeper stats, and groups',
                      style: RiseText.caption),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: RiseColors.textFaint, size: 20),
          ],
        ),
      ),
    );
  }
}

/// The account-aware top card: guest (unconfigured), sign-in (configured +
/// signed out), or the signed-in account with sign-out / delete.
class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _busy = false;

  void _toast(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  Future<void> _run(Future<void> Function() action, {String? onError}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (onError != null) _toast(onError, kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(
      () => ref.read(authServiceProvider).signInWithGoogle(),
      onError: 'Sign-in was cancelled.');

  Future<void> _signOut() async {
    if (_busy) return;
    final confirmed = await _confirmSignOut();
    if (confirmed != true) return;
    await _run(() async {
      await _unregisterPush();
      await ref.read(authServiceProvider).signOut();
      _toast('Signed out.', kind: RiseToastKind.success);
    }, onError: 'Could not sign out. Try again.');
  }

  Future<bool?> _confirmSignOut() => showConfirmDialog(
        context,
        title: 'Sign out?',
        message: 'Your alarms and streak stay on this device. Sign back in '
            'anytime to sync with your crew.',
        confirmLabel: 'Sign out',
      );

  /// Removes this device's FCM token while still authenticated — must run BEFORE
  /// signOut(), since the reactive host unregister fires after the session is
  /// cleared, when the RLS-guarded delete would silently no-op as anon.
  Future<void> _unregisterPush() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      await ref.read(pushRegistrarProvider).unregister();
    } catch (_) {}
  }

  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await _confirmDelete();
    if (confirmed != true) return;
    await _run(() async {
      await ref.read(authServiceProvider).deleteAccount();
      _toast('Your account was deleted.', kind: RiseToastKind.success);
    }, onError: 'Could not delete your account. Try again.');
  }

  Future<bool?> _confirmDelete() {
    // The controller is intentionally not disposed: disposing it in the
    // dialog's whenComplete races the dismiss transition (which rebuilds the
    // field), and a single short-lived TextEditingController per delete attempt
    // is a negligible, rare leak.
    final controller = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) {
          final canDelete =
              controller.text.trim().toUpperCase() == 'DELETE';
          return AlertDialog(
            backgroundColor: RiseColors.card,
            title: Text('Delete account', style: RiseText.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This permanently deletes your account, username, and crew '
                  'connections. Your alarms stay on this device. Type DELETE '
                  'to confirm.',
                  style: RiseText.body.copyWith(color: RiseColors.textDim),
                ),
                const SizedBox(height: 14),
                TextField(
                  key: const Key('delete-confirm-field'),
                  controller: controller,
                  autocorrect: false,
                  enableSuggestions: false,
                  cursorColor: RiseColors.primary,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(hintText: 'DELETE'),
                ),
              ],
            ),
            actions: [
              GhostButton(
                label: 'Cancel',
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              GestureDetector(
                key: const Key('delete-confirm-button'),
                behavior: HitTestBehavior.opaque,
                onTap: canDelete
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Text('Delete',
                      style: RiseText.body.copyWith(
                        color: canDelete
                            ? RiseColors.danger
                            : RiseColors.textFaint,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(authServiceProvider) is! DisabledAuthService;
    final accountAsync = ref.watch(accountProvider);
    final account = accountAsync.value;

    if (!configured) return _guestCard();
    if (account == null) {
      // Restoring ≠ signed out: hold the account's shape until truth arrives
      // so the sign-in card can never flash for an already signed-in user.
      if (accountAsync.isLoading) return _restoringCard();
      return _signInCard();
    }
    return _accountCard(account);
  }

  Widget _restoringCard() {
    return RiseCard(
      child: Row(
        children: [
          const RiseSkeletonCircle(size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                RiseSkeleton(width: 120, height: 13),
                SizedBox(height: 8),
                RiseSkeleton(width: 80, height: 11),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _guestCard() {
    return RiseCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
                color: RiseColors.accentSoft, shape: BoxShape.circle),
            child: Icon(Icons.person_outline,
                color: RiseColors.accent, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Guest',
                    style:
                        RiseText.body.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Sign in to sync your alarms and crew — coming soon',
                    style: RiseText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _signInCard() {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: RiseColors.accentSoft, shape: BoxShape.circle),
                child: Icon(Icons.cloud_sync,
                    color: RiseColors.accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sign in to Riserys',
                        style: RiseText.body
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        'Sync your streaks, wake up with your crew, and climb '
                        'the leaderboard.',
                        style: RiseText.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PrimaryButton(
                  label: 'Sign in with Google',
                  icon: Icons.login,
                  onPressed: _busy ? null : _signIn,
                ),
                if (_busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: RiseColors.primaryText),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCard(RiseAccount account) {
    final handle = account.username != null ? '@${account.username}' : null;
    return Column(
      children: [
        RiseCard(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: avatarColorFromHex(account.avatarColor),
                    shape: BoxShape.circle),
                child: Text(_initial(account),
                    style: RiseText.title.copyWith(
                        color: RiseColors.primaryText,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName.isNotEmpty
                          ? account.displayName
                          : (handle ?? 'Riserys member'),
                      style:
                          RiseText.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(handle ?? account.email ?? 'Finish setting up',
                        style: RiseText.mono(
                            size: 12.5, color: RiseColors.textDim)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        RiseCard(
          child: Column(
            children: [
              _actionRow('Sign out', Icons.logout,
                  onTap: _busy ? null : _signOut, busy: _busy),
              Divider(height: 24, color: RiseColors.divider),
              _actionRow('Delete account', Icons.delete_outline,
                  danger: true, onTap: _busy ? null : _delete),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionRow(String label, IconData icon,
      {required VoidCallback? onTap, bool danger = false, bool busy = false}) {
    final color = danger ? RiseColors.danger : RiseColors.text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: RiseText.body
                  .copyWith(color: color, fontWeight: FontWeight.w600)),
          if (busy) ...[
            const Spacer(),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: RiseColors.textDim),
            ),
          ],
        ],
      ),
    );
  }

  static String _initial(RiseAccount a) {
    final source = (a.username?.isNotEmpty ?? false)
        ? a.username!
        : (a.displayName.isNotEmpty ? a.displayName : '?');
    return source.characters.first.toUpperCase();
  }
}
