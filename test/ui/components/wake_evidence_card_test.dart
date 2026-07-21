import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/wake_evidence.dart';
import 'package:rise/ui/components/wake_evidence_card.dart';

Widget _wrap(WakeEvidence e) =>
    MaterialApp(home: Scaffold(body: WakeEvidenceCard(evidence: e)));

void main() {
  testWidgets('renders the verdict, score and every signal', (t) async {
    const evidence = WakeEvidence(
      score: 82,
      verdict: 'Clean wake-up',
      blurb: 'Up, out, and moving.',
      tone: EvidenceTone.good,
      signals: [
        EvidenceSignal(
            label: 'On time', detail: 'Up within 2 min', tone: EvidenceTone.good),
        EvidenceSignal(
            label: 'Left home',
            detail: 'Up and out the door',
            tone: EvidenceTone.good),
        EvidenceSignal(
            label: 'Alertness', detail: '85/100', tone: EvidenceTone.good),
      ],
    );

    await t.pumpWidget(_wrap(evidence));

    expect(find.text('HOW YOU WOKE UP'), findsOneWidget); // SectionLabel uppercases
    expect(find.text('Clean wake-up'), findsOneWidget);
    expect(find.text('82'), findsOneWidget);
    expect(find.text('On time'), findsOneWidget);
    expect(find.text('Left home'), findsOneWidget);
    expect(find.text('85/100'), findsOneWidget);
  });

  testWidgets('a rough verdict still renders without overflow', (t) async {
    const evidence = WakeEvidence(
      score: 22,
      verdict: 'Rough morning',
      blurb: 'You got there in the end. Tomorrow\'s a fresh start.',
      tone: EvidenceTone.bad,
      signals: [
        EvidenceSignal(
            label: 'Woke late', detail: '1h 15m late', tone: EvidenceTone.warn),
        EvidenceSignal(
            label: 'Safety dismiss',
            detail: 'Fell back to the safety exit',
            tone: EvidenceTone.bad),
      ],
    );

    // A layout overflow would throw here and fail the test automatically.
    await t.pumpWidget(_wrap(evidence));
    await t.pump();

    expect(find.text('Rough morning'), findsOneWidget);
    expect(find.text('22'), findsOneWidget);
    expect(find.text('1h 15m late'), findsOneWidget);
  });
}
