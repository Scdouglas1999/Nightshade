// Pillar C ("Constellation") — privacy plumbing for contributeTarget().
//
// Pins the fix for the "Share raw subframes (SUBS)" privacy choice being a
// no-op: the persisted choice is now plumbed into the service, and because no
// subframe export/push path exists yet, SUBS is refused up front instead of
// silently shipping the additive SUMS under a SUBS consent. SUMS (the default)
// keeps its existing behaviour.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Minimal seam — the privacy guard short-circuits before any bridge call, and
/// the SUMS no-coverage path never reaches the seam either.
class _StubSeam implements SkyAtlasSeam {
  @override
  Future<Map<String, dynamic>> dispatch(Map<String, dynamic> args) async =>
      {'ok': true};

  @override
  Future<Map<String, dynamic>> queryCutout(Map<String, dynamic> args) async =>
      {'ok': true};

  @override
  Future<Map<String, dynamic>> regionInfo(Map<String, dynamic> args) async =>
      {'ok': true, 'tilesWithData': 0};

  @override
  Future<Map<String, dynamic>> growth(Map<String, dynamic> args) async =>
      {'ok': true, 'points': const [], 'totalFrames': 0};

  @override
  Future<Map<String, dynamic>> mergeDelta(Map<String, dynamic> args) async =>
      {'ok': true};
}

void main() {
  late NightshadeDatabase db;
  late SkyAtlasService atlas;
  late ConstellationService service;

  const target = SharedTarget(
    targetId: 1,
    name: 'M31',
    raDeg: 10.68,
    decDeg: 41.27,
    contributors: 3,
    integrationSeconds: 7200,
    activeTileId: null,
  );

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    atlas = SkyAtlasService(
      dao: SkyAtlasDao(db),
      seam: _StubSeam(),
      logger: LoggingService(),
      atlasRootResolver: () async => '/tmp/constellation_privacy_test',
    );
    service = ConstellationService(
      atlas: atlas,
      logger: LoggingService(),
      // A configured (fake) hub so the SUMS path can reach the empty-cone
      // short-circuit; the SUBS path throws before ever resolving credentials.
      credentialsResolver: () async => ConstellationCredentials(
        hubBaseUrl: Uri.parse('https://hub.example.org'),
        bearerToken: 'tok',
      ),
      localTargetsResolver: () async => const [],
    );
    service.joinSharedTarget(target);
  });

  tearDown(() => db.close());

  test('SUBS is refused — the privacy choice is no longer a silent no-op',
      () async {
    await expectLater(
      service.contributeTarget(
        target.targetId,
        privacy: ConstellationPrivacy.subs,
      ),
      throwsA(
        isA<ConstellationException>()
            .having((e) => e.kind, 'kind', ConstellationErrorKind.conflict)
            .having(
              (e) => e.message,
              'message',
              contains('raw subframes'),
            ),
      ),
    );
  });

  test('SUMS (default) is accepted and follows the existing sums path',
      () async {
    // No local atlas coverage yet, so the contribute short-circuits to an empty
    // outcome rather than throwing — proving the default privacy does not trip
    // the SUBS guard and the working SUMS path is unchanged.
    final outcome = await service.contributeTarget(target.targetId);
    expect(outcome.acceptedCount, 0);
    expect(outcome.rejectedCount, 0);
  });
}
