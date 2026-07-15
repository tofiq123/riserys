import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/local/alarm_repository.dart';
import 'package:rise/data/local/database.dart';
import 'package:rise/domain/alarm.dart';

void main() {
  late RiseDatabase db;
  late AlarmRepository repo;

  setUp(() {
    db = RiseDatabase(NativeDatabase.memory());
    repo = AlarmRepository(db);
  });

  tearDown(() async => db.close());

  test('starts empty', () async {
    expect(await repo.all(), isEmpty);
  });

  test('inserts an alarm and assigns an id', () async {
    final saved = await repo.upsert(
        const Alarm(id: 0, hour: 6, minute: 30, label: 'Run', days: {1, 2, 3, 4, 5}));
    expect(saved.id, greaterThan(0));

    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.label, 'Run');
    expect(all.single.days, {1, 2, 3, 4, 5});
  });

  test('round-trips an empty day set as a one-shot alarm', () async {
    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    expect((await repo.all()).single.days, isEmpty);
  });

  test('updates an existing alarm in place', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.upsert(saved.copyWith(hour: 7, label: 'Later'));

    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.hour, 7);
    expect(all.single.label, 'Later');
  });

  test('toggles enabled', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.setEnabled(saved.id, false);
    expect((await repo.all()).single.enabled, isFalse);
  });

  test('deletes an alarm', () async {
    final saved = await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));
    await repo.delete(saved.id);
    expect(await repo.all(), isEmpty);
  });

  test('watchAll emits on change', () async {
    final firstEmission = Completer<void>();
    final afterWrite = Completer<List<Alarm>>();

    final sub = repo.watchAll().listen(
      (rows) {
        if (!firstEmission.isCompleted) {
          firstEmission.complete();
        } else if (!afterWrite.isCompleted) {
          afterWrite.complete(rows);
        }
      },
      onDone: () {
        if (!afterWrite.isCompleted) {
          afterWrite.completeError(
              StateError('watchAll closed without re-emitting after the write'));
        }
      },
    );

    // Wait for the stream to go live before writing. The first emission's value
    // is deliberately not asserted: whether a subscriber observes the pre-write
    // state depends on drift coalescing an in-flight initial fetch when a change
    // lands first, which is correct behaviour and not a requirement of ours. The
    // requirement is that a write is reflected in a subsequent emission.
    await firstEmission.future;

    await repo.upsert(const Alarm(id: 0, hour: 6, minute: 30));

    final rows = await afterWrite.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw StateError('watchAll did not re-emit after the write'),
    );
    expect(rows, hasLength(1));
    expect(rows.single.hour, 6);
    expect(rows.single.minute, 30);

    await sub.cancel();
  });
}
