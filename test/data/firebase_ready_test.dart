import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/firebase_ready.dart';

void main() {
  test('firebaseReady completes once markFirebaseReady is called', () async {
    var completed = false;
    unawaited(firebaseReady.then((_) => completed = true));
    expect(completed, isFalse);

    markFirebaseReady();
    await Future<void>.delayed(Duration.zero);

    expect(completed, isTrue);
  });

  test('markFirebaseReady is idempotent — calling it twice does not throw',
      () {
    markFirebaseReady();
    expect(markFirebaseReady, returnsNormally);
  });

  test('firebaseReady resolves immediately for callers awaiting after it was already marked',
      () async {
    markFirebaseReady();
    await expectLater(firebaseReady, completes);
  });
}
