import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/data/local/wake_event_repository.dart';

void main() {
  late RiseDatabase db;
  late WakeEventRepository repo;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    repo = WakeEventRepository(db);
  });
  tearDown(() => db.close());

  final ring = DateTime.utc(2026, 7, 17, 6, 0);

  test('openRing inserts a new open event', () async {
    final id = await repo.openRing(
        alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.id, id);
    expect(all.single.isOpen, isTrue);
    expect(all.single.label, 'Run');
  });

  test('openRing reuses an open event within the reuse window', () async {
    final id1 = await repo.openRing(
        alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    final id2 = await repo.openRing(
        alarmId: 1,
        scheduledAt: ring,
        firstRingAt: ring.add(const Duration(minutes: 9)),
        label: 'Run');
    expect(id2, id1);
    expect(await repo.all(), hasLength(1));
  });

  test('openRing starts a new event past the reuse window', () async {
    await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    await repo.openRing(
        alarmId: 1,
        scheduledAt: ring,
        firstRingAt: ring.add(const Duration(hours: 7)),
        label: 'Run');
    expect(await repo.all(), hasLength(2));
  });

  test('openRing does not reuse a different alarm\'s open event', () async {
    final a = await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'A');
    final b = await repo.openRing(alarmId: 2, scheduledAt: ring, firstRingAt: ring, label: 'B');
    expect(b, isNot(a));
    expect(await repo.all(), hasLength(2));
  });

  test('finalizeDismiss within grace marks onTime true', () async {
    await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    await repo.finalizeDismiss(
        alarmId: 1,
        dismissedAt: ring.add(const Duration(minutes: 14, seconds: 59)),
        method: 'mission');
    final e = (await repo.all()).single;
    expect(e.isOpen, isFalse);
    expect(e.onTime, isTrue);
    expect(e.method, 'mission');
  });

  test('finalizeDismiss past grace marks onTime false', () async {
    await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    await repo.finalizeDismiss(
        alarmId: 1,
        dismissedAt: ring.add(const Duration(minutes: 15, seconds: 1)),
        method: 'slide');
    expect((await repo.all()).single.onTime, isFalse);
  });

  test('finalizeDismiss is a no-op when nothing is open', () async {
    await repo.finalizeDismiss(alarmId: 99, dismissedAt: ring, method: 'slide');
    expect(await repo.all(), isEmpty);
  });

  test('finalizeDismiss closes only the open event, leaving closed ones', () async {
    await repo.openRing(alarmId: 1, scheduledAt: ring, firstRingAt: ring, label: 'Run');
    await repo.finalizeDismiss(
        alarmId: 1, dismissedAt: ring.add(const Duration(minutes: 3)), method: 'mission');
    await repo.openRing(
        alarmId: 1,
        scheduledAt: ring,
        firstRingAt: ring.add(const Duration(hours: 24)),
        label: 'Run');
    await repo.finalizeDismiss(
        alarmId: 1,
        dismissedAt: ring.add(const Duration(hours: 24, minutes: 2)),
        method: 'slide');
    final all = await repo.all();
    expect(all, hasLength(2));
    expect(all.where((e) => e.isOpen), isEmpty);
    expect(all.map((e) => e.method).toSet(), {'mission', 'slide'});
  });
}
