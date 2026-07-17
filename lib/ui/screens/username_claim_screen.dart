import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth/auth_service.dart';
import '../components/rise_buttons.dart';
import '../components/section_label.dart';
import '../state/auth_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Shown after sign-in when the account has no username yet. Validates format
/// (3–20 chars: a–z, 0–9, underscore) and availability, then claims. A username
/// is required to be social, so this can't be skipped — but the user can sign
/// out to back out.
class UsernameClaimScreen extends ConsumerStatefulWidget {
  const UsernameClaimScreen({
    super.key,
    this.onClaimed,
    this.initialDisplayName = '',
  });

  final VoidCallback? onClaimed;
  final String initialDisplayName;

  @override
  ConsumerState<UsernameClaimScreen> createState() =>
      _UsernameClaimScreenState();
}

class _UsernameClaimScreenState extends ConsumerState<UsernameClaimScreen> {
  static final _usernameRe = RegExp(r'^[a-z0-9_]{3,20}$');

  final _username = TextEditingController();
  late final TextEditingController _displayName =
      TextEditingController(text: widget.initialDisplayName);

  int _checkToken = 0; // guards against a stale availability result winning
  bool _checking = false;
  bool? _available; // null = unknown/invalid; true/false = checked result
  bool _busy = false;
  String? _error;

  String get _normalized => _username.text.trim().toLowerCase();
  bool get _formatValid => _usernameRe.hasMatch(_normalized);
  bool get _canClaim => _formatValid && _available == true && !_busy;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _onUsernameChanged(String _) async {
    setState(() => _error = null);
    if (!_formatValid) {
      // Invalidate any in-flight check so its result can't land as a stale
      // "available" for text that is no longer valid.
      _checkToken++;
      setState(() {
        _available = null;
        _checking = false;
      });
      return;
    }
    final token = ++_checkToken;
    setState(() {
      _checking = true;
      _available = null;
    });
    try {
      final ok =
          await ref.read(authServiceProvider).isUsernameAvailable(_normalized);
      if (!mounted || token != _checkToken) return; // a newer keystroke won
      setState(() {
        _available = ok;
        _checking = false;
      });
    } catch (_) {
      if (!mounted || token != _checkToken) return;
      setState(() {
        _checking = false;
        _available = null; // couldn't check; leave Claim disabled
      });
    }
  }

  Future<void> _claim() async {
    if (!_canClaim) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).claimUsername(
            _normalized,
            displayName: _displayName.text.trim(),
          );
      if (!mounted) return;
      widget.onClaimed?.call();
    } on UsernameTakenException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _available = false;
        _error = 'That username was just taken. Try another.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not claim your username. Check your connection.';
      });
    }
  }

  Future<void> _signOut() => ref.read(authServiceProvider).signOut();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RiseSpacing.screen, 24, RiseSpacing.screen, 40),
        children: [
          Text('Claim your handle', style: RiseText.display),
          const SizedBox(height: 8),
          Text(
            'Pick a username so your crew can find you. It’s how you show up '
            'on the leaderboard.',
            style: RiseText.body.copyWith(color: RiseColors.textDim),
          ),
          const SizedBox(height: 28),
          const SectionLabel('Username'),
          const SizedBox(height: 10),
          TextField(
            key: const Key('username-field'),
            controller: _username,
            onChanged: _onUsernameChanged,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [
              FilteringTextInputFormatter.deny(RegExp(r'\s')),
              LengthLimitingTextInputFormatter(20),
            ],
            style: RiseText.body,
            cursorColor: RiseColors.primary,
            decoration: _fieldDecoration(hint: 'yourname', prefixText: '@'),
          ),
          const SizedBox(height: 8),
          _statusLine(),
          const SizedBox(height: 24),
          const SectionLabel('Display name'),
          const SizedBox(height: 10),
          TextField(
            key: const Key('displayname-field'),
            controller: _displayName,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            style: RiseText.body,
            cursorColor: RiseColors.primary,
            decoration: _fieldDecoration(hint: 'Your name'),
          ),
          const SizedBox(height: 28),
          PrimaryButton(
            label: 'Claim username',
            onPressed: _canClaim ? _claim : null,
          ),
          const SizedBox(height: 8),
          Center(
            child: GhostButton(
              label: 'Sign out',
              onPressed: _busy ? null : _signOut,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusLine() {
    String text;
    Color color;
    if (_error != null) {
      text = _error!;
      color = RiseColors.danger;
    } else if (_username.text.trim().isEmpty) {
      text = '3–20 characters: letters, numbers, underscores.';
      color = RiseColors.textFaint;
    } else if (!_formatValid) {
      text = 'Use 3–20 letters, numbers, or underscores.';
      color = RiseColors.danger;
    } else if (_checking) {
      text = 'Checking availability…';
      color = RiseColors.textDim;
    } else if (_available == true) {
      text = '@$_normalized is available.';
      color = RiseColors.positive;
    } else if (_available == false) {
      text = 'That username is taken.';
      color = RiseColors.danger;
    } else {
      text = '';
      color = RiseColors.textFaint;
    }
    return Text(text, style: RiseText.caption.copyWith(color: color));
  }

  InputDecoration _fieldDecoration({required String hint, String? prefixText}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: RiseText.body.copyWith(color: RiseColors.textFaint),
      prefixText: prefixText,
      prefixStyle: RiseText.body.copyWith(color: RiseColors.textDim),
      filled: true,
      fillColor: RiseColors.surface2,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: _border(RiseColors.border),
      enabledBorder: _border(RiseColors.border),
      focusedBorder: _border(RiseColors.primary),
    );
  }

  static OutlineInputBorder _border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(RiseRadii.base),
        borderSide: BorderSide(color: color),
      );
}
