import 'package:flutter/material.dart';

import '../../data/permission_gateway.dart';
import '../components/permissions_section.dart';
import '../components/rise_buttons.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onDone,
    this.permissions = const NativePermissionGateway(),
  });

  final VoidCallback onDone;
  final PermissionGateway permissions;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _lastPage = 2;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _lastPage) {
      _controller.nextPage(
          duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
    } else {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: _page < _lastPage
                    ? GhostButton(label: 'Skip', onPressed: widget.onDone)
                    : const SizedBox(height: 44),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _intro(
                    icon: Icons.notifications_active,
                    title: 'Wake up, for real',
                    body:
                        'Rise rings through silent mode, Focus, and a locked screen — and makes sure you actually get up.',
                  ),
                  _intro(
                    icon: Icons.psychology_alt,
                    title: 'Wake up all the way',
                    body:
                        'Turn your alarm off with a quick mission — a little math, a pattern, or a button hold. A gentle nudge past the half-asleep swipe.',
                  ),
                  _permissionsPage(),
                ],
              ),
            ),
            _dots(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  RiseSpacing.screen, 12, RiseSpacing.screen, 16),
              child: PrimaryButton(
                label: _page < _lastPage ? 'Next' : 'Start using Rise',
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _intro(
      {required IconData icon, required String title, required String body}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: RiseColors.accentSoft,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 44, color: RiseColors.accent),
          ),
          const SizedBox(height: 28),
          Text(title, textAlign: TextAlign.center, style: RiseText.display),
          const SizedBox(height: 12),
          Text(body,
              textAlign: TextAlign.center,
              style: RiseText.body.copyWith(color: RiseColors.textDim)),
        ],
      ),
    );
  }

  Widget _permissionsPage() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          RiseSpacing.screen, 12, RiseSpacing.screen, 12),
      children: [
        Text('Ring through anything', style: RiseText.title),
        const SizedBox(height: 8),
        Text(
            'Rise needs a few permissions to reach you on silent, locked, or dozing.',
            style: RiseText.body.copyWith(color: RiseColors.textDim)),
        const SizedBox(height: 18),
        PermissionsSection(gateway: widget.permissions),
      ],
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i <= _lastPage; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: i == _page ? RiseColors.primary : RiseColors.border,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}
