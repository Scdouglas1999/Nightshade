// Nothing this service sends may go out in the clear.
//
// `GeolocationService` is what Settings → Location's "Detect Location" and the
// first-run site step both call. On a desktop the GPS attempt always fails, so
// the IP fallback is the path that actually runs, and a cleartext endpoint like
// `http://ip-api.com/json/` is tempting because that service answers 403 over
// HTTPS on its free tier. The reply becomes the operator's stored
// latitude/longitude, so a passer-by on the network would both see the public
// IP go out and get to pick where the rig thinks it is.
//
// The assertion is on the SCHEME of every request that leaves, not on a
// vendor name: swapping providers later must not be able to reintroduce
// cleartext. The primary is ipinfo.io (ZIP-level `loc`); the fallback is
// ipwho.is. City-centroid replies must not be stored as seven-decimal pins.

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_planetarium/src/services/geolocation_service.dart';

/// Drives the device half of `fetchLocationFromGPS` without a GPS receiver:
/// `Geolocator` delegates straight to `GeolocatorPlatform.instance`, so a
/// fake that reports services disabled or answers a fix is the machine the
/// service sees.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({this.position, this.enabled = true});

  final Position? position;
  final bool enabled;

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final fix = position;
    if (fix == null) throw StateError('no fix');
    return fix;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final saved = GeolocationService.clientFactory;
  final savedGeolocator = GeolocatorPlatform.instance;
  tearDown(() {
    GeolocationService.clientFactory = saved;
    GeolocatorPlatform.instance = savedGeolocator;
  });

  test(
    'every IP-geolocation request is HTTPS, including the fallback',
    () async {
      final requests = <Uri>[];
      GeolocationService.clientFactory = () => MockClient((request) async {
        requests.add(request.url);
        // Answer the primary the way it answers a rate-limited caller: HTTP
        // 200 with no coordinate. That is what pushes the service onto the
        // fallback leg, which must also be HTTPS.
        if (request.url.host.contains('ipinfo.io')) {
          return http.Response('{"error":{"title":"RateLimit"}}', 200);
        }
        return http.Response(
          '{"success":true,"latitude":39.9527,"longitude":-75.1635,'
          '"city":"Philadelphia","region":"Pennsylvania",'
          '"country":"United States"}',
          200,
        );
      });

      final result = await GeolocationService.fetchLocation();

      expect(
        requests.length,
        greaterThanOrEqualTo(2),
        reason:
            'the fallback leg has to have run for this test to mean '
            'anything',
      );
      for (final uri in requests) {
        expect(
          uri.scheme,
          'https',
          reason: '$uri left the machine in the clear',
        );
      }
      expect(result, isNotNull);
      expect(result!.$1, closeTo(39.9527, 1e-6));
      expect(result.$2, closeTo(-75.1635, 1e-6));
      expect(result.$3, 'Philadelphia, Pennsylvania, United States');
    },
  );

  test('ipinfo loc is the coordinate, not a city-hall centroid', () async {
    GeolocationService.clientFactory = () => MockClient((request) async {
      return http.Response(
        '{"city":"Broomall","region":"Pennsylvania","country":"US",'
        '"loc":"39.9815,-75.3566"}',
        200,
      );
    });

    final result = await GeolocationService.fetchLocationFromIP();

    expect(result, isNotNull);
    expect(result!.$1, closeTo(39.9815, 1e-6));
    expect(result.$2, closeTo(-75.3566, 1e-6));
    expect(result.$3, 'Broomall, Pennsylvania');
  });

  test('a seven-decimal city-centroid is rounded to four decimals', () async {
    GeolocationService.clientFactory = () => MockClient((request) async {
      return http.Response(
        '{"success":true,"latitude":39.9523835,'
        '"longitude":-75.1636197,"city":"Philadelphia"}',
        200,
      );
    });

    final result = await GeolocationService.fetchLocationFromIPAlternative();

    expect(result, isNotNull);
    expect(result!.$1, 39.9524);
    expect(result.$2, -75.1636);
  });

  test('a whole-degree coordinate is not silently dropped', () async {
    // `latitude: 40` decodes as an int, so an `as double?` cast throws — and
    // every catch here swallows the throw, which would tell an operator on a
    // round degree that no location could be found.
    GeolocationService.clientFactory = () => MockClient((request) async {
      return http.Response(
        '{"latitude":40,"longitude":-75,"city":"Somewhere"}',
        200,
      );
    });

    final result = await GeolocationService.fetchLocationFromIP();

    expect(result, isNotNull);
    expect(result!.$1, 40.0);
    expect(result.$2, -75.0);
  });

  test(
    'place search is HTTPS and returns the named town plus elevation',
    () async {
      final requests = <Uri>[];
      GeolocationService.clientFactory = () => MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          '{"results":[{"name":"Newtown Square","latitude":39.98678,'
          '"longitude":-75.40103,"elevation":127,"admin1":"Pennsylvania",'
          '"country":"United States"}]}',
          200,
        );
      });

      final hits = await GeolocationService.searchPlaces('Newtown Square');

      expect(requests, hasLength(1));
      expect(requests.single.scheme, 'https');
      expect(requests.single.host, 'geocoding-api.open-meteo.com');
      expect(hits, hasLength(1));
      expect(hits.single.latitude, 39.9868);
      expect(hits.single.longitude, -75.4010);
      expect(hits.single.elevation, 127);
      expect(hits.single.label, 'Newtown Square, Pennsylvania, United States');
    },
  );

  test('an empty place query does not leave the machine', () async {
    var calls = 0;
    GeolocationService.clientFactory = () => MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });

    expect(await GeolocationService.searchPlaces('  '), isEmpty);
    expect(calls, 0);
  });

  // The click behind Detect location: one call must land a fix on a machine
  // with no GPS receiver, and the result has to say it came from the
  // internet — with which host — because that answer is a ~10 km guess.

  test('with no GPS receiver, Detect falls back to the internet lookup in the '
      'same call', () async {
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform(enabled: false);
    GeolocationService.clientFactory = () => MockClient((request) async {
      return http.Response(
        '{"city":"Broomall","region":"Pennsylvania","country":"US",'
        '"loc":"39.9815,-75.3566"}',
        200,
      );
    });

    final fix = await GeolocationService.fetchLocationFromGPS(
      fallbackToIp: true,
    );

    expect(fix, isNotNull);
    expect(fix!.latitude, closeTo(39.9815, 1e-6));
    expect(fix.longitude, closeTo(-75.3566, 1e-6));
    expect(fix.source, GeolocationSource.internet);
    expect(fix.providerHost, 'ipinfo.io');
    expect(fix.accuracyMeters, isNull);
    expect(
      fix.describeSource(),
      'approximate: from your internet connection (ipinfo.io)',
    );
  });

  test('the fallback host is named when it is the one that answered', () async {
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform(enabled: false);
    GeolocationService.clientFactory = () => MockClient((request) async {
      if (request.url.host.contains('ipinfo.io')) {
        return http.Response('{"error":{"title":"RateLimit"}}', 200);
      }
      return http.Response(
        '{"success":true,"latitude":39.9527,"longitude":-75.1635,'
        '"city":"Philadelphia"}',
        200,
      );
    });

    final fix = await GeolocationService.fetchLocationFromGPS(
      fallbackToIp: true,
    );

    expect(fix, isNotNull);
    expect(fix!.source, GeolocationSource.internet);
    expect(fix.providerHost, 'ipwho.is');
    expect(
      fix.describeSource(),
      'approximate: from your internet connection (ipwho.is)',
    );
  });

  test(
    'without the IP fallback, no GPS receiver means no fix and no request',
    () async {
      GeolocatorPlatform.instance = _FakeGeolocatorPlatform(enabled: false);
      var calls = 0;
      GeolocationService.clientFactory = () => MockClient((request) async {
        calls++;
        return http.Response('{}', 200);
      });

      final fix = await GeolocationService.fetchLocationFromGPS(
        fallbackToIp: false,
      );

      expect(fix, isNull);
      expect(calls, 0, reason: 'a refused fallback still reached the network');
    },
  );

  test('a device fix names the device path and carries its metres', () async {
    GeolocatorPlatform.instance = _FakeGeolocatorPlatform(
      position: Position(
        latitude: 47.6062,
        longitude: -122.3321,
        timestamp: DateTime(2026, 9, 13),
        accuracy: 12.4,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
    );
    var calls = 0;
    GeolocationService.clientFactory = () => MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });

    final fix = await GeolocationService.fetchLocationFromGPS(
      fallbackToIp: true,
    );

    expect(fix, isNotNull);
    expect(fix!.source, GeolocationSource.device);
    expect(fix.providerHost, isNull);
    expect(fix.accuracyMeters, 12.4);
    expect(fix.describeSource(), 'this machine’s GPS fix, ±12 m');
    expect(calls, 0, reason: 'a working GPS still triggered an IP request');
  });
}
