import 'package:flutter_test/flutter_test.dart';
import 'package:rise/data/home_departure_checker.dart';
import 'package:rise/data/home_location_gateway.dart';
import 'package:rise/domain/rise_settings.dart';

void main() {
  // Home anchor for the scenarios. Offsets in latitude degrees: 0.001° ≈ 111 m.
  const homeLat = 52.5200;
  const homeLng = 13.4050;

  const homeSet = RiseSettings(
      homeLat: homeLat, homeLng: homeLng, homeShare: HomeShareTier.private);

  HomeFix fixAt(double lat, {double accuracy = 10}) =>
      HomeFix(latitude: lat, longitude: homeLng, accuracyMeters: accuracy);

  test('tier off → null and the gateway is NEVER touched (no location read)',
      () async {
    final gateway = FakeHomeLocationGateway(
        fix: fixAt(homeLat + 0.01)); // would be a clear departure
    final checker = HomeDepartureChecker(
        gateway: gateway,
        settings: homeSet.copyWith(homeShare: HomeShareTier.off));
    expect(await checker.leftHome(), isNull);
    expect(gateway.currentFixCalls, 0);
    expect(gateway.ensurePermissionCalls, 0);
  });

  test('home unset → null and the gateway is never touched', () async {
    final gateway = FakeHomeLocationGateway(fix: fixAt(homeLat + 0.01));
    final checker = HomeDepartureChecker(
        gateway: gateway,
        settings: const RiseSettings(homeShare: HomeShareTier.private));
    expect(await checker.leftHome(), isNull);
    expect(gateway.currentFixCalls, 0);
  });

  test('clearly beyond the radius → true (private tier)', () async {
    final gateway =
        FakeHomeLocationGateway(fix: fixAt(homeLat + 0.005)); // ≈ 556 m
    final checker =
        HomeDepartureChecker(gateway: gateway, settings: homeSet);
    expect(await checker.leftHome(), isTrue);
    expect(gateway.currentFixCalls, 1); // exactly ONE foreground fix
    expect(gateway.ensurePermissionCalls, 0); // never prompts mid-wake
  });

  test('crew tier runs the same check', () async {
    final gateway = FakeHomeLocationGateway(fix: fixAt(homeLat + 0.005));
    final checker = HomeDepartureChecker(
        gateway: gateway,
        settings: homeSet.copyWith(homeShare: HomeShareTier.crew));
    expect(await checker.leftHome(), isTrue);
  });

  test('within the radius → false', () async {
    final gateway =
        FakeHomeLocationGateway(fix: fixAt(homeLat + 0.0005)); // ≈ 56 m
    final checker =
        HomeDepartureChecker(gateway: gateway, settings: homeSet);
    expect(await checker.leftHome(), isFalse);
  });

  test('no fix (denied / services off / timeout) → null', () async {
    final gateway = FakeHomeLocationGateway(fix: null);
    final checker =
        HomeDepartureChecker(gateway: gateway, settings: homeSet);
    expect(await checker.leftHome(), isNull);
    expect(gateway.currentFixCalls, 1);
  });

  test('fix too imprecise (accuracy > 100 m) → null, not a guess', () async {
    final gateway = FakeHomeLocationGateway(
        fix: fixAt(homeLat + 0.05, accuracy: 180)); // far, but junk fix
    final checker =
        HomeDepartureChecker(gateway: gateway, settings: homeSet);
    expect(await checker.leftHome(), isNull);
  });
}
