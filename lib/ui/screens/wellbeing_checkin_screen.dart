import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/phq2.dart';
import '../components/rise_buttons.dart';
import '../components/rise_card.dart';
import '../components/section_label.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// An OPTIONAL, private wellbeing check-in (the public-domain PHQ-2) with a warm
/// care off-ramp. Reached only by the user's own tap from Profile — never
/// auto-triggered, never gated behind streaks or engagement.
///
/// Nothing here is persisted: the answers and the score live only in this
/// widget's state and are gone when it closes. It never diagnoses, never labels
/// the person or the score, and always shows the "informational only" note.
class WellbeingCheckinScreen extends StatefulWidget {
  const WellbeingCheckinScreen({super.key});

  @override
  State<WellbeingCheckinScreen> createState() => _WellbeingCheckinScreenState();
}

class _WellbeingCheckinScreenState extends State<WellbeingCheckinScreen> {
  // Local, in-memory only — deliberately never written to storage.
  final List<int?> _answers = [null, null];
  bool _showResult = false;

  bool get _complete => !_answers.contains(null);

  void _select(int question, int value) =>
      setState(() => _answers[question] = value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RiseColors.appBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              RiseSpacing.screen, 8, RiseSpacing.screen, 40),
          children: [
            Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child:
                        Icon(Icons.arrow_back, color: RiseColors.text, size: 22),
                  ),
                ),
                const SizedBox(width: 8),
                Text('How you\'ve been feeling', style: RiseText.title),
              ],
            ),
            const SizedBox(height: 16),
            if (_showResult) ..._result() else ..._questions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _questions() => [
        Text(
            'A couple of gentle questions about the last two weeks. There are no '
            'right answers — this is just for you, and nothing is saved.',
            style: RiseText.body.copyWith(color: RiseColors.textDim)),
        const SizedBox(height: 16),
        const _DisclaimerNote(),
        const SizedBox(height: 20),
        for (var q = 0; q < phq2Questions.length; q++) ...[
          _questionCard(q),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 6),
        PrimaryButton(
          key: const Key('phq-submit'),
          label: 'See how you\'re doing',
          onPressed: _complete ? () => setState(() => _showResult = true) : null,
        ),
      ];

  Widget _questionCard(int q) {
    return RiseCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(phq2Questions[q],
              style: RiseText.body.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          for (var v = 0; v < phq2Answers.length; v++) ...[
            _option(q, v),
            if (v < phq2Answers.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _option(int q, int v) {
    final selected = _answers[q] == v;
    return GestureDetector(
      key: Key('phq-$q-$v'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(q, v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? RiseColors.accentSoft : RiseColors.surface2,
          borderRadius: BorderRadius.circular(RiseRadii.base),
          border: Border.all(
              color: selected ? RiseColors.accent : RiseColors.border),
        ),
        child: Row(
          children: [
            Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? RiseColors.accent : RiseColors.textFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Text(phq2Answers[v],
                  style: RiseText.body.copyWith(
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _result() {
    final score = phq2Score([_answers[0]!, _answers[1]!]);
    final worthTalking = isAbovePhq2Threshold(score);

    return [
      RiseCard(
        padding: const EdgeInsets.all(RiseSpacing.screen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(worthTalking ? Icons.favorite_outline : Icons.wb_sunny_outlined,
                    color: RiseColors.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      worthTalking
                          ? 'Thank you for being honest'
                          : 'Thanks for checking in',
                      style: RiseText.body
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
                worthTalking
                    ? 'What you\'re feeling is real, and it\'s worth talking '
                        'through with someone. A doctor or mental-health '
                        'professional can really help — reaching out is a strong, '
                        'kind thing to do for yourself.'
                    : 'It sounds like things are feeling more okay right now — '
                        'that\'s good to hear. Checking in with yourself is always '
                        'worth doing, and support is here whenever you want it.',
                style: RiseText.body.copyWith(color: RiseColors.textDim)),
          ],
        ),
      ),
      const SizedBox(height: 20),
      const SectionLabel('Finding support'),
      const SizedBox(height: 10),
      _ResourcesCard(onOpenHelpline: () => _openHelpline(context)),
      const SizedBox(height: 16),
      const _DisclaimerNote(),
      const SizedBox(height: 20),
      PrimaryButton(
        key: const Key('phq-done'),
        label: 'Done',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      const SizedBox(height: 8),
      Center(
        child: GhostButton(
          label: 'Take it again',
          onPressed: () => setState(() {
            _answers[0] = null;
            _answers[1] = null;
            _showResult = false;
          }),
        ),
      ),
    ];
  }

  /// Opens findahelpline.com — an INTERNATIONAL directory, so no single
  /// country's number is hardcoded. Best-effort: if no browser can handle it,
  /// fall back to showing the address so the user can still reach it.
  //
  // LAUNCH PUNCH-LIST: localize the care resources — surface the user's
  // region's helpline directory and local crisis lines, and translate this
  // copy — before shipping to non-English / international markets.
  Future<void> _openHelpline(BuildContext context) async {
    final uri = Uri.parse('https://findahelpline.com');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) _helplineFallback(context);
    } catch (_) {
      if (context.mounted) _helplineFallback(context);
    }
  }

  void _helplineFallback(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Visit findahelpline.com to find support near you.')));
  }
}

/// The always-present, non-alarming "not medical advice" note.
class _DisclaimerNote extends StatelessWidget {
  const _DisclaimerNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(RiseSpacing.cardPad),
      decoration: BoxDecoration(
        color: RiseColors.surface2,
        borderRadius: BorderRadius.circular(RiseRadii.base),
        border: Border.all(color: RiseColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 16, color: RiseColors.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'This is informational only — not a diagnosis or medical advice.',
                style: RiseText.caption),
          ),
        ],
      ),
    );
  }
}

/// The care off-ramp: an international helpline directory plus a prompt to reach
/// a local doctor or crisis line. Never gated — shown at every result.
class _ResourcesCard extends StatelessWidget {
  const _ResourcesCard({required this.onOpenHelpline});

  final VoidCallback onOpenHelpline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          key: const Key('phq-helpline'),
          behavior: HitTestBehavior.opaque,
          onTap: onOpenHelpline,
          child: RiseCard(
            child: Row(
              children: [
                const Icon(Icons.support_agent,
                    color: RiseColors.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Find a helpline near you',
                          style: RiseText.body
                              .copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('findahelpline.com — free, confidential, worldwide',
                          style: RiseText.caption),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new,
                    color: RiseColors.textFaint, size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        RiseCard(
          child: Row(
            children: [
              const Icon(Icons.local_hospital_outlined,
                  color: RiseColors.textDim, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    'You can also reach out to a local doctor, or a crisis line '
                    'in your area. If you\'re in immediate danger, contact your '
                    'local emergency number.',
                    style: RiseText.caption),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
