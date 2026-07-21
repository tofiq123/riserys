import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/iap/entitlement_service.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/toast.dart';
import '../state/entitlement_providers.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Pushes the hard paywall. The single entry point used by every premium gate
/// and by the "Rise Premium" row in Profile.
void openPaywall(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const PaywallScreen()),
  );
}

/// The decided placeholder pricing, shown when RevenueCat is unconfigured or an
/// offering can't be read. Real prices come from [PremiumOffer.priceString].
class _PlanCopy {
  const _PlanCopy({
    required this.plan,
    required this.title,
    required this.placeholderPrice,
    required this.period,
    required this.note,
    this.hero = false,
  });

  final PremiumPlan plan;
  final String title;
  final String placeholderPrice;
  final String period;
  final String note;
  final bool hero;
}

// Annual first — the hero. Copy is intentionally honest: no trial framing.
const List<_PlanCopy> _planCopy = [
  _PlanCopy(
    plan: PremiumPlan.annual,
    title: 'Annual',
    placeholderPrice: r'$39.99',
    period: '/year',
    note: 'Best value — about \$3.33/mo',
    hero: true,
  ),
  _PlanCopy(
    plan: PremiumPlan.monthly,
    title: 'Monthly',
    placeholderPrice: r'$4.99',
    period: '/month',
    note: 'Flexible — cancel anytime',
  ),
  _PlanCopy(
    plan: PremiumPlan.lifetime,
    title: 'Lifetime',
    placeholderPrice: r'$79.99',
    period: 'one-time',
    note: 'Pay once — yours forever',
  ),
];

const List<({IconData icon, String text})> _valueProps = [
  (
    icon: Icons.bolt_outlined,
    text: 'Every wake mission — typing, QR, walk-it-off, and more',
  ),
  (
    icon: Icons.link,
    text: 'Mission chains — stack 2–3 so waking is unmissable',
  ),
  (
    icon: Icons.trending_up,
    text: 'Alertness history & trends from your PVT scores',
  ),
  (
    icon: Icons.tune,
    text: 'Adaptive difficulty and smart wake-check',
  ),
  (
    icon: Icons.insights_outlined,
    text: 'Monthly & yearly stats and a shareable progress card',
  ),
  (
    icon: Icons.groups_outlined,
    text: 'Unlimited crew and groups to wake up together',
  ),
];

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  PremiumPlan _selected = PremiumPlan.annual;
  bool _busy = false;

  void _snack(String message, {RiseToastKind kind = RiseToastKind.info}) {
    if (!mounted) return;
    RiseToast.show(context, message, kind: kind);
  }

  /// The real offer for [plan], if the store returned one.
  PremiumOffer? _offerFor(List<PremiumOffer> offers, PremiumPlan plan) {
    for (final o in offers) {
      if (o.plan == plan) return o;
    }
    return null;
  }

  Future<void> _subscribe(List<PremiumOffer> offers) async {
    if (_busy) return;
    final offer = _offerFor(offers, _selected);
    if (offer == null) {
      _snack('That plan isn\'t available right now. Please try again later.',
          kind: RiseToastKind.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await ref.read(entitlementServiceProvider).purchase(offer);
      if (!mounted) return;
      if (ok) {
        _snack('Welcome to Rise Premium. Everything\'s unlocked.',
            kind: RiseToastKind.success);
        Navigator.of(context).maybePop();
      } else {
        _snack('Purchase didn\'t complete. Nothing was charged.',
            kind: RiseToastKind.info);
      }
    } catch (_) {
      _snack('Couldn\'t complete the purchase. Nothing was charged.',
          kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ref.read(entitlementServiceProvider).restorePurchases();
      if (!mounted) return;
      if (ok) {
        _snack('Restored — welcome back to Premium.', kind: RiseToastKind.success);
        Navigator.of(context).maybePop();
      } else {
        _snack('No previous purchase found for this account.',
            kind: RiseToastKind.info);
      }
    } catch (_) {
      _snack('Couldn\'t restore right now. Try again in a moment.',
          kind: RiseToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = ref.watch(isPremiumProvider).value ?? true;
    final offers = ref.watch(premiumOffersProvider).value ?? const [];

    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                key: const Key('paywall-close'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Icon(Icons.close, color: RiseColors.text, size: 22),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (isPremium) ..._premiumBody() else ..._offerBody(offers),
          ],
        ),
      ),
    );
  }

  // ---- Already-premium (also the unconfigured/unlocked default) ------------

  List<Widget> _premiumBody() {
    return [
      const SizedBox(height: 24),
      Center(
        child: Icon(Icons.verified, size: 48, color: RiseColors.primary),
      ),
      const SizedBox(height: 16),
      Center(child: Text('You\'re on Rise Premium', style: RiseText.display)),
      const SizedBox(height: 8),
      Center(
        child: Text('Everything below is unlocked. Thanks for backing Rise.',
            textAlign: TextAlign.center, style: RiseText.caption),
      ),
      const SizedBox(height: 24),
      _propsCard(),
      const SizedBox(height: 20),
      GestureDetector(
        key: const Key('paywall-restore'),
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : _restore,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Restore purchases',
              style: RiseText.body.copyWith(color: RiseColors.textDim)),
        ),
      ),
    ];
  }

  // ---- Not premium: the hard paywall --------------------------------------

  List<Widget> _offerBody(List<PremiumOffer> offers) {
    return [
      const SizedBox(height: 8),
      Text('Rise Premium', style: RiseText.display),
      const SizedBox(height: 8),
      Text(
          'Unlock every mission, the deeper stats, and the whole crew. '
          'One simple upgrade — no free trial, no games.',
          style: RiseText.body.copyWith(color: RiseColors.textDim)),
      const SizedBox(height: 24),
      _propsCard(),
      const SizedBox(height: 24),
      for (final copy in _planCopy) ...[
        _planTile(copy, _offerFor(offers, copy.plan)),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 12),
      PrimaryButton(
        key: const Key('paywall-subscribe'),
        label: _busy ? 'Please wait…' : 'Continue',
        onPressed: _busy ? null : () => _subscribe(offers),
      ),
      const SizedBox(height: 8),
      GestureDetector(
        key: const Key('paywall-restore'),
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : _restore,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('Restore purchases',
              style: RiseText.body.copyWith(color: RiseColors.textDim)),
        ),
      ),
      const SizedBox(height: 12),
      Text(
          'Your alarm, the Setup Guardian, permission help, and the wellbeing '
          'check-in are always free — Premium is only the extras. '
          'Subscriptions renew until cancelled; manage or cancel anytime in '
          'your store account.',
          textAlign: TextAlign.center,
          style: RiseText.caption.copyWith(color: RiseColors.textFaint)),
    ];
  }

  Widget _propsCard() {
    return RiseCard(
      padding: const EdgeInsets.all(RiseSpacing.screen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _valueProps.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_valueProps[i].icon, size: 20, color: RiseColors.accent),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(_valueProps[i].text, style: RiseText.body)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _planTile(_PlanCopy copy, PremiumOffer? offer) {
    final selected = _selected == copy.plan;
    final price = offer?.priceString ?? copy.placeholderPrice;
    return GestureDetector(
      key: Key('paywall-plan-${copy.plan.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = copy.plan),
      child: Container(
        padding: const EdgeInsets.all(RiseSpacing.screen),
        decoration: BoxDecoration(
          color: selected ? RiseColors.accentSoft : RiseColors.card,
          borderRadius: BorderRadius.circular(RiseRadii.lg),
          border: Border.all(
            color: selected ? RiseColors.primary : RiseColors.border,
            width: selected ? 2 : 1,
          ),
          boxShadow: RiseShadows.card,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 22,
              color: selected ? RiseColors.primary : RiseColors.textFaint,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(copy.title,
                          style: RiseText.body
                              .copyWith(fontWeight: FontWeight.w700)),
                      if (copy.hero) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: RiseColors.primary,
                            borderRadius:
                                BorderRadius.circular(RiseRadii.pill),
                          ),
                          child: Text('BEST VALUE',
                              style: RiseText.sectionLabel.copyWith(
                                  fontSize: 9,
                                  color: RiseColors.primaryText)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(copy.note, style: RiseText.caption),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(price,
                    style: RiseText.mono(size: 20, weight: FontWeight.w700)),
                Text(copy.period,
                    style: RiseText.caption.copyWith(fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
