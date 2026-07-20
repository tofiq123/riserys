import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/oem_guidance.dart';

void main() {
  group('oemVendorFor', () {
    test('maps the known manufacturers, case-insensitively', () {
      expect(oemVendorFor('samsung'), OemVendor.samsung);
      expect(oemVendorFor('SAMSUNG'), OemVendor.samsung);
      expect(oemVendorFor('Xiaomi'), OemVendor.xiaomi);
      expect(oemVendorFor('HUAWEI'), OemVendor.huawei);
      expect(oemVendorFor('OnePlus'), OemVendor.oneplus);
      expect(oemVendorFor('OPPO'), OemVendor.oppo);
      expect(oemVendorFor('vivo'), OemVendor.vivo);
    });

    test('folds sub-brands into their parent family', () {
      expect(oemVendorFor('Redmi'), OemVendor.xiaomi);
      expect(oemVendorFor('POCO'), OemVendor.xiaomi);
      expect(oemVendorFor('Honor'), OemVendor.huawei);
      expect(oemVendorFor('realme'), OemVendor.oppo);
      expect(oemVendorFor('iQOO'), OemVendor.vivo);
    });

    test('trims and tolerates surrounding whitespace', () {
      expect(oemVendorFor('  samsung  '), OemVendor.samsung);
    });

    test('unknown, empty, and null map to generic', () {
      expect(oemVendorFor('Google'), OemVendor.generic);
      expect(oemVendorFor('motorola'), OemVendor.generic);
      expect(oemVendorFor(''), OemVendor.generic);
      expect(oemVendorFor(null), OemVendor.generic);
    });
  });

  group('oemGuidanceFor', () {
    test('returns guidance matching the classified vendor', () {
      final g = oemGuidanceFor('samsung');
      expect(g.vendor, OemVendor.samsung);
      expect(g.vendorLabel, 'Samsung');
    });

    test('every vendor has a non-empty summary and steps', () {
      for (final m in [
        'samsung',
        'xiaomi',
        'huawei',
        'oneplus',
        'oppo',
        'vivo',
        'nokia', // -> generic
        null,
      ]) {
        final g = oemGuidanceFor(m);
        expect(g.summary, isNotEmpty, reason: 'summary for $m');
        expect(g.steps, isNotEmpty, reason: 'steps for $m');
        expect(g.vendorLabel, isNotEmpty, reason: 'label for $m');
        // Steps should be individually meaningful.
        expect(g.steps.every((s) => s.trim().isNotEmpty), isTrue,
            reason: 'blank step for $m');
      }
    });

    test('aggressive OEMs are flagged; generic fallback is not', () {
      expect(oemGuidanceFor('samsung').isAggressive, isTrue);
      expect(oemGuidanceFor('xiaomi').isAggressive, isTrue);
      expect(oemGuidanceFor('Pixel').isAggressive, isFalse);
      expect(oemGuidanceFor(null).isAggressive, isFalse);
    });

    test('generic guidance uses a neutral, phone-agnostic label', () {
      expect(oemGuidanceFor(null).vendorLabel, 'your phone');
    });
  });
}
