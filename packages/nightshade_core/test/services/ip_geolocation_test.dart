// The "ask the internet where this rig is" request must be encrypted, and must
// never invent a coordinate.
//
// Two production paths did the same thing over cleartext
// `http://ip-api.com/json`: this one — `FfiBackend.getLocationFromInternet`,
// which is what the headless appliance answers `GET /api/location` with
// (apps/desktop/lib/headless_api/routes/profile_routes.dart:79) — and the
// desktop GUI's `GeolocationService` fallback. ip-api.com's free tier returns 403 over
// HTTPS, so the request was unencrypted by construction. The reply is written
// into observer_latitude/observer_longitude, which drive altitude/airmass,
// meridian-flip timing and the horizon mask, so anyone on the path could
// choose where the rig believed it was standing.
//
// The old parser also answered `0.0` for a missing lat/lon, turning a
// rate-limited or rewritten reply into Null Island — a real place in the Gulf
// of Guinea where nothing is up when the app says it is.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_core/nightshade_core.dart';
// ignore: implementation_imports
import 'package:nightshade_core/src/services/ip_geolocation.dart';

/// Records every request the service makes so the test can assert on the
/// transport rather than on a URL string in the source.
class _Recorder {
  final List<Uri> requests = <Uri>[];

  http.Client Function() factory(String body, {int status = 200}) {
    return () => MockClient((request) async {
      requests.add(request.url);
      return http.Response(body, status);
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final saved = IpGeolocation.clientFactory;
  tearDown(() => IpGeolocation.clientFactory = saved);

  const okBody =
      '{"success":true,"latitude":39.9527,"longitude":-75.1635,'
      '"city":"Philadelphia"}';

  test('the lookup endpoint is TLS', () {
    expect(IpGeolocation.endpoint.scheme, 'https');
  });

  test('the request actually goes out over TLS', () async {
    final recorder = _Recorder();
    IpGeolocation.clientFactory = recorder.factory(okBody);

    final site = await IpGeolocation.fetch();

    expect(recorder.requests, hasLength(1));
    expect(
      recorder.requests.single.scheme,
      'https',
      reason:
          'the observer position this answer becomes is not something a '
          'passer-by on the network gets to choose',
    );
    expect(site.latitude, closeTo(39.9527, 1e-6));
    expect(site.longitude, closeTo(-75.1635, 1e-6));
    expect(site.elevation, 0.0);
  });

  test('a whole-degree coordinate is not dropped', () {
    final site = IpGeolocation.parse(
      '{"success":true,"latitude":40,'
      '"longitude":-75}',
    );
    expect(site.latitude, 40.0);
    expect(site.longitude, -75.0);
  });

  test('a refused lookup is an error, not Null Island', () {
    expect(
      () => IpGeolocation.parse('{"success":false,"message":"Rate limited"}'),
      throwsA(isA<NightshadeError>()),
    );
    expect(
      () => IpGeolocation.parse('{"error":true,"reason":"RateLimited"}'),
      throwsA(isA<NightshadeError>()),
    );
  });

  test('an out-of-range coordinate is refused', () {
    expect(
      () => IpGeolocation.parse(
        '{"success":true,"latitude":991,'
        '"longitude":0}',
      ),
      throwsA(isA<NightshadeError>()),
    );
  });

  test('a non-200 answer is an error, not a coordinate', () async {
    final recorder = _Recorder();
    IpGeolocation.clientFactory = recorder.factory('nope', status: 503);
    await expectLater(IpGeolocation.fetch(), throwsA(isA<NightshadeError>()));
  });

  // Drives the REAL FfiBackend — the object the headless `/api/location`
  // handler calls — so re-inlining a raw
  // `http.get('http://ip-api.com/json')` in the backend fails here: the
  // injected client would never see the request.
  test('the FfiBackend path uses the shared TLS lookup', () async {
    final recorder = _Recorder();
    IpGeolocation.clientFactory = recorder.factory(okBody);

    final site = await FfiBackend().getLocationFromInternet();

    expect(recorder.requests, hasLength(1));
    expect(recorder.requests.single.scheme, 'https');
    expect(site.latitude, closeTo(39.9527, 1e-6));
  });

  test('the FfiBackend path refuses to answer Null Island', () async {
    final recorder = _Recorder();
    IpGeolocation.clientFactory = recorder.factory(
      '{"success":false,"message":"Rate limited"}',
    );

    await expectLater(
      FfiBackend().getLocationFromInternet(),
      throwsA(isA<NightshadeError>()),
    );
  });
}
