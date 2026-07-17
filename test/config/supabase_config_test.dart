import 'package:flutter_test/flutter_test.dart';
import 'package:rise/config/supabase_config.dart';

void main() {
  test('configured requires all three values non-empty', () {
    expect(SupabaseConfig.configured('u', 'k', 'c'), isTrue);
    expect(SupabaseConfig.configured('', 'k', 'c'), isFalse);
    expect(SupabaseConfig.configured('u', '', 'c'), isFalse);
    expect(SupabaseConfig.configured('u', 'k', ''), isFalse);
  });

  test('isConfigured is false with no --dart-define values (test env)', () {
    // In `flutter test` no dart-defines are set, so the const values are empty.
    expect(SupabaseConfig.isConfigured, isFalse);
  });
}
