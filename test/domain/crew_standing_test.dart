import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/crew_standing.dart';
import 'package:rise/domain/wake_stats.dart';

CrewStanding _s(String id, {int current = 0, int best = 0, double rate = 0}) {
  // Encode a target onTimeRate via totalWakes/onTimeCount.
  final total = rate == 0 ? 0 : 100;
  return CrewStanding(
    id: id,
    username: id,
    displayName: id,
    avatarColor: '#7C9CF4',
    stats: WakeStats(
        currentStreak: current,
        bestStreak: best,
        totalWakes: total,
        onTimeCount: (rate * total).round()),
  );
}

void main() {
  test('ranks by current streak desc', () {
    final ranked = rankStandings([_s('a', current: 2), _s('b', current: 5), _s('c', current: 3)]);
    expect(ranked.map((s) => s.id), ['b', 'c', 'a']);
  });

  test('tiebreak: best streak, then on-time rate, then username', () {
    final ranked = rankStandings([
      _s('z', current: 3, best: 1, rate: 0.9),
      _s('y', current: 3, best: 5, rate: 0.1), // higher best -> first
      _s('x', current: 3, best: 1, rate: 0.9), // ties z on all but username -> x before z
    ]);
    expect(ranked.map((s) => s.id), ['y', 'x', 'z']);
  });

  test('does not mutate the input list', () {
    final input = [_s('a', current: 1), _s('b', current: 2)];
    rankStandings(input);
    expect(input.map((s) => s.id), ['a', 'b']); // original order preserved
  });

  test('value equality', () {
    const a = CrewStanding(
        id: 'u', username: 'u', displayName: 'U', avatarColor: '#000000', stats: WakeStats());
    const b = CrewStanding(
        id: 'u', username: 'u', displayName: 'U', avatarColor: '#000000', stats: WakeStats());
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(a.copyWith(isMe: true)));
  });
}
