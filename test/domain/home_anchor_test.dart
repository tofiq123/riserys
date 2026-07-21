import 'package:flutter_test/flutter_test.dart';
import 'package:rise/domain/home_anchor.dart';

void main() {
  group('distanceMeters (haversine)', () {
    test('zero for identical points', () {
      expect(distanceMeters(48.2082, 16.3738, 48.2082, 16.3738), 0);
    });

    test('one degree of latitude is ~111.2 km', () {
      expect(distanceMeters(0, 0, 1, 0), closeTo(111195, 50));
    });

    test('is symmetric', () {
      final ab = distanceMeters(40.7128, -74.0060, 51.5074, -0.1278);
      final ba = distanceMeters(51.5074, -0.1278, 40.7128, -74.0060);
      expect(ab, closeTo(ba, 0.001));
    });

    test('longitude shrinks with latitude (cos factor)', () {
      final equator = distanceMeters(0, 0, 0, 0.01);
      final at60 = distanceMeters(60, 0, 60, 0.01);
      // cos(60°) = 0.5 — a longitude degree is half as long at 60°N.
      expect(at60, closeTo(equator / 2, equator * 0.01));
    });

    test('antimeridian-safe: 179.999E to 179.999W is ~222 m, not ~40,000 km',
        () {
      expect(distanceMeters(0, 179.999, 0, -179.999), closeTo(222.4, 2));
    });
  });

  group('HomeDeparture.evaluate', () {
    // Home anchor for the scenarios below. Offsets are in latitude degrees:
    // 0.001° ≈ 111.2 m.
    const homeLat = 52.5200;
    const homeLng = 13.4050;

    test('at home: a good fix within the 120 m floor', () {
      final r = HomeDeparture.evaluate(
        homeLat: homeLat,
        homeLng: homeLng,
        lat: homeLat + 0.0005, // ≈ 56 m
        lng: homeLng,
        accuracyMeters: 10,
      );
      expect(r, HomeDeparture.atHome);
    });

    test('exactly at home with a perfect fix is atHome', () {
      final r = HomeDeparture.evaluate(
        homeLat: homeLat,
        homeLng: homeLng,
        lat: homeLat,
        lng: homeLng,
        accuracyMeters: 5,
      );
      expect(r, HomeDeparture.atHome);
    });

    test('clearly left: ~556 m away with a good fix', () {
      final r = HomeDeparture.evaluate(
        homeLat: homeLat,
        homeLng: homeLng,
        lat: homeLat + 0.005, // ≈ 556 m
        lng: homeLng,
        accuracyMeters: 20, // threshold max(120, 50) = 120
      );
      expect(r, HomeDeparture.leftHome);
    });

    test(
        'accuracy scales the threshold: 200 m away with a 100 m fix is NOT '
        'a departure (threshold 250 m)', () {
      final r = HomeDeparture.evaluate(
        homeLat: homeLat,
        homeLng: homeLng,
        lat: homeLat + 0.0018, // ≈ 200 m
        lng: homeLng,
        accuracyMeters: 100, // threshold max(120, 250) = 250
      );
      expect(r, HomeDeparture.atHome);
    });

    test('but 300 m away with the same 100 m fix IS a departure', () {
      final r = HomeDeparture.evaluate(
        homeLat: homeLat,
        homeLng: homeLng,
        lat: homeLat + 0.0027, // ≈ 300 m
        lng: homeLng,
        accuracyMeters: 100,
      );
      expect(r, HomeDeparture.leftHome);
    });

    test('accuracy worse than 100 m is too vague to judge → unknown', () {
      final r = HomeDeparture.evaluate(
        homeLat: homeLat,
        homeLng: homeLng,
        lat: homeLat + 0.05, // ≈ 5.6 km — far, but the fix is junk
        lng: homeLng,
        accuracyMeters: 150,
      );
      expect(r, HomeDeparture.unknown);
    });

    test('home unset → unknown (either coordinate missing)', () {
      expect(
          HomeDeparture.evaluate(
              homeLat: null,
              homeLng: homeLng,
              lat: homeLat,
              lng: homeLng,
              accuracyMeters: 10),
          HomeDeparture.unknown);
      expect(
          HomeDeparture.evaluate(
              homeLat: homeLat,
              homeLng: null,
              lat: homeLat,
              lng: homeLng,
              accuracyMeters: 10),
          HomeDeparture.unknown);
    });

    test('non-finite input → unknown, never a throw', () {
      expect(
          HomeDeparture.evaluate(
              homeLat: homeLat,
              homeLng: homeLng,
              lat: double.nan,
              lng: homeLng,
              accuracyMeters: 10),
          HomeDeparture.unknown);
      expect(
          HomeDeparture.evaluate(
              homeLat: homeLat,
              homeLng: homeLng,
              lat: homeLat,
              lng: homeLng,
              accuracyMeters: double.infinity),
          HomeDeparture.unknown);
    });

    test('departure across the antimeridian still detected', () {
      final r = HomeDeparture.evaluate(
        homeLat: 0,
        homeLng: 179.999,
        lat: 0,
        lng: -179.995, // ≈ 667 m across the wrap
        accuracyMeters: 15,
      );
      expect(r, HomeDeparture.leftHome);
    });

    test('never claims sub-floor precision: 119 m with a 5 m fix is atHome',
        () {
      final r = HomeDeparture.evaluate(
        homeLat: homeLat,
        homeLng: homeLng,
        lat: homeLat + 0.00107, // ≈ 119 m, just under the 120 m floor
        lng: homeLng,
        accuracyMeters: 5,
      );
      expect(r, HomeDeparture.atHome);
    });
  });
}
