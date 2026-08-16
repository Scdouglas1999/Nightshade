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
// cleartext.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_planetarium/src/services/geolocation_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final saved = GeolocationService.clientFactory;
  tearDown(() => GeolocationService.clientFactory = saved);

  test(
    'every IP-geolocation request is HTTPS, including the fallback',
    () async {
      final requests = <Uri>[];
      GeolocationService.clientFactory = () => MockClient((request) async {
        requests.add(request.url);
        // Answer the primary the way it answers a rate-limited caller: HTTP
        // 200 with no coordinate. That is what pushes the service onto the
        // fallback leg, which must also be HTTPS.
        if (request.url.host.contains('ipapi.co')) {
          return http.Response('{"error":true,"reason":"RateLimited"}', 200);
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
}
