import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Recording fake seam returning a canned `api_difference_image` envelope.
class _FakeDifferenceSeam implements DifferenceImageSeam {
  _FakeDifferenceSeam(this.result);
  Map<String, dynamic> result;
  final List<Map<String, dynamic>> dispatched = [];

  @override
  Future<Map<String, dynamic>> difference(Map<String, dynamic> args) async {
    dispatched.add(args);
    return result;
  }

  @override
  Future<Map<String, dynamic>> tileCenter(Map<String, dynamic> args) async => {
    'tileId': args['tileId'],
    'ra': 0.0,
    'dec': 0.0,
  };
}

/// Catalog matcher that returns a fixed star list (empty = no match).
class _FakeCatalogMatcher implements TransientCatalogMatcher {
  _FakeCatalogMatcher(this.stars, {this.throwError = false});
  List<PhotometricCatalogStar> stars;
  bool throwError;

  @override
  Future<List<PhotometricCatalogStar>> coneStars({
    required double raDegrees,
    required double decDegrees,
    required double radiusDegrees,
    double maxMagnitude = 18.0,
  }) async {
    if (throwError) throw StateError('network down');
    return stars;
  }
}

const _wcs = SolvedWcs(
  raHours: 8.0, // 120 deg
  decDegrees: 25.0,
  rotationDeg: 0.0,
  pixelScaleArcsec: 2.0,
  imageWidth: 1024,
  imageHeight: 1024,
);

Map<String, dynamic> _candidateJson({
  double ra = 120.0,
  double dec = 25.0,
  int tileId = 42,
  double snr = 18.0,
  String kind = 'newSource',
  double? deltaMag,
  double eccentricity = 0.1,
}) {
  return {
    'ra': ra,
    'dec': dec,
    'tileId': tileId,
    'tileX': 512.0,
    'tileY': 600.0,
    'residualFlux': 5000.0,
    'deltaMag': deltaMag,
    'snr': snr,
    'fwhm': 2.1,
    'eccentricity': eccentricity,
    'kind': kind,
    'catalogMatch': null,
  };
}

void main() {
  late NightshadeDatabase db;
  late TransientDetectionsDao dao;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    dao = TransientDetectionsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  FirstLightService build({
    required Map<String, dynamic> diffResult,
    List<PhotometricCatalogStar> stars = const [],
    bool catalogThrows = false,
  }) {
    return FirstLightService(
      dao: dao,
      seam: _FakeDifferenceSeam(diffResult),
      catalog: _FakeCatalogMatcher(stars, throwError: catalogThrows),
      logger: LoggingService(),
      atlasRootResolver: () async => '/tmp/test_atlas',
    );
  }

  test('persists an unnamed new source as a possible transient', () async {
    final service = build(
      diffResult: {
        'ok': true,
        'candidates': [_candidateJson()],
        'tilesChecked': [42],
      },
    );

    final rows = await service.scanFrame(
      framePath: '/tmp/light_999.fits',
      wcs: _wcs,
      sessionId: null,
    );

    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row.catalogMatch, isNull);
    expect(row.kind, 'newSource');
    expect(row.tileId, 42);
    expect(row.confidence, greaterThan(0.0));

    final persisted = await dao.allDetections();
    expect(persisted, hasLength(1));
  });

  test('a coincident catalog star with template backing names + reclassifies '
      'to a brightening', () async {
    final service = build(
      diffResult: {
        'ok': true,
        // A finite deltaMag means the differencing measured template flux beneath
        // the residual — the source pre-existed, so this IS a brightening.
        'candidates': [_candidateJson(deltaMag: -1.2)],
        'tilesChecked': [42],
      },
      stars: const [
        PhotometricCatalogStar(raDegrees: 120.0, decDegrees: 25.0, magV: 14.2),
      ],
    );

    final rows = await service.scanFrame(
      framePath: '/tmp/light.fits',
      wcs: _wcs,
    );

    expect(rows, hasLength(1));
    expect(rows.single.catalogMatch, isNotNull);
    // The catalog brightness must be explicitly labelled APASS Johnson V at
    // J2000 — not implied to be the residual's instrumental Δmag.
    expect(rows.single.catalogMatch, contains('V (APASS, J2000)='));
    // A residual on a known star WITH template flux is a brightening of it.
    expect(rows.single.kind, 'pointBrightening');
  });

  test('a new source coincident with a faint catalog star but with NO template '
      'backing is NOT demoted to a brightening', () async {
    // The chance-coincidence case: a true newcomer (no template flux, deltaMag
    // null) that happens to land within 5" of a faint background star must stay
    // flagged as a possible transient, not silently renamed a "brightening".
    final service = build(
      diffResult: {
        'ok': true,
        'candidates': [
          _candidateJson(),
        ], // deltaMag null -> no template backing
        'tilesChecked': [42],
      },
      stars: const [
        PhotometricCatalogStar(raDegrees: 120.0, decDegrees: 25.0, magV: 17.8),
      ],
    );

    final rows = await service.scanFrame(framePath: '/tmp/c.fits', wcs: _wcs);
    expect(rows, hasLength(1));
    // Kept as a new source (not demoted), and named to disclose the coincidence.
    expect(rows.single.kind, 'newSource');
    expect(rows.single.catalogMatch, contains('New source near'));
  });

  test('a star only inside the proper-motion-widened band is flagged epoch '
      'uncertain, not confidently named', () async {
    // A catalog star ~8" away (beyond the 5" tight radius but inside the PM band)
    // must be reported as a possible high-PM coincidence with the epoch caveat,
    // and a clean new source there must not be demoted.
    const decOffsetDeg = 8.0 / 3600.0; // 8 arcsec north
    final service = build(
      diffResult: {
        'ok': true,
        'candidates': [_candidateJson()],
        'tilesChecked': [42],
      },
      stars: const [
        PhotometricCatalogStar(
          raDegrees: 120.0,
          decDegrees: 25.0 + decOffsetDeg,
          magV: 9.5,
        ),
      ],
    );

    final rows = await service.scanFrame(framePath: '/tmp/d.fits', wcs: _wcs);
    expect(rows, hasLength(1));
    expect(rows.single.kind, 'newSource');
    expect(rows.single.catalogMatch, contains('epoch uncertain'));
  });

  test('drops residuals below the SNR floor', () async {
    final service = build(
      diffResult: {
        'ok': true,
        'candidates': [_candidateJson(snr: 3.0)],
        'tilesChecked': [42],
      },
    );
    final rows = await service.scanFrame(framePath: '/tmp/a.fits', wcs: _wcs);
    expect(rows, isEmpty);
    expect(await dao.allDetections(), isEmpty);
  });

  test('suppresses a residual at a previously-dismissed position', () async {
    // Seed a dismissed detection at the candidate's position.
    final service = build(
      diffResult: {
        'ok': true,
        'candidates': [_candidateJson()],
        'tilesChecked': [42],
      },
    );
    final first = await service.scanFrame(framePath: '/tmp/a.fits', wcs: _wcs);
    expect(first, hasLength(1));
    await service.markReviewed(first.single.id, dismissed: true);

    // A new scan of the same residual is suppressed.
    final second = await service.scanFrame(framePath: '/tmp/b.fits', wcs: _wcs);
    expect(second, isEmpty);
  });

  test(
    'a degraded (network-down) cross-match still surfaces the transient',
    () async {
      final service = build(
        diffResult: {
          'ok': true,
          'candidates': [_candidateJson()],
          'tilesChecked': [42],
        },
        catalogThrows: true,
      );
      final rows = await service.scanFrame(framePath: '/tmp/a.fits', wcs: _wcs);
      expect(rows, hasLength(1));
      expect(rows.single.catalogMatch, isNull);
    },
  );

  test('rejects an invalid WCS', () async {
    final service = build(diffResult: {'ok': true, 'candidates': const []});
    expect(
      () => service.scanFrame(
        framePath: '/tmp/a.fits',
        wcs: const SolvedWcs(
          raHours: 8.0,
          decDegrees: 25.0,
          rotationDeg: 0.0,
          pixelScaleArcsec: 0.0, // invalid
          imageWidth: 1024,
          imageHeight: 1024,
        ),
      ),
      throwsArgumentError,
    );
  });
}
