import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/data/local/excused_days_repository.dart';

void main() {
  late RiseDatabase db;
  late ExcusedDaysRepository repo;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    repo = ExcusedDaysRepository(db);
  });

  tearDown(() => db.close());

  test('dayOf normalises any instant to its local midnight', () {
    final d = ExcusedDaysRepository.dayOf(DateTime(2026, 7, 18, 23, 59, 30));
    expect(d, DateTime(2026, 7, 18));
  });

  test('excuse then read returns the normalised day', () async {
    await repo.excuse(DateTime(2026, 7, 18, 6, 30));
    final days = await repo.all();
    expect(days, {DateTime(2026, 7, 18)});
  });

  test('excusing the same day twice is idempotent (a set, not duplicates)',
      () async {
    await repo.excuse(DateTime(2026, 7, 18, 6));
    await repo.excuse(DateTime(2026, 7, 18, 22)); // same local day
    expect(await repo.all(), {DateTime(2026, 7, 18)});
  });

  test('unexcuse removes a marked day and no-ops for unmarked', () async {
    await repo.excuse(DateTime(2026, 7, 18));
    await repo.unexcuse(DateTime(2026, 7, 19)); // never marked — no-op
    expect(await repo.all(), {DateTime(2026, 7, 18)});
    await repo.unexcuse(DateTime(2026, 7, 18));
    expect(await repo.all(), isEmpty);
  });

  test('watchAll emits the live excused set', () async {
    final first = await repo.watchAll().first;
    expect(first, isEmpty);
    await repo.excuse(DateTime(2026, 7, 20));
    final next = await repo.watchAll().first;
    expect(next, {DateTime(2026, 7, 20)});
  });
}
