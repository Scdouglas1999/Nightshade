import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// A recording fake [SkyAtlasSeam] that returns canned bridge results so the
/// service body (fold persistence, region bookkeeping) runs without native code.
class _FakeSkyAtlasSeam implements SkyAtlasSeam {
  final List<Map<String, dynamic>> dispatched = [];
  Map<String, dynamic> Function(Map<String, dynamic>)? onDispatch;

  @override
  Future<Map<String, dynamic>> dispatch(Map<String, dynamic> args) async {
    dispatched.add(args);
    final handler = onDispatch;
    if (handler != null) return handler(args);
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> queryCutout(Map<String, dynamic> args) async => {
    'ok': true,
    'pngPath': '/tmp/cutout.png',
    'coveredFraction': 0.9,
  };

  @override
  Future<Map<String, dynamic>> regionInfo(Map<String, dynamic> args) async => {
    'ok': true,
    'tilesWithData': 1,
  };

  @override
  Future<Map<String, dynamic>> growth(Map<String, dynamic> args) async => {
    'ok': true,
    'points': const [],
    'totalFrames': 0,
  };

  final List<Map<String, dynamic>> merged = [];

  @override
  Future<Map<String, dynamic>> mergeDelta(Map<String, dynamic> args) async {
    merged.add(args);
    return {
      'ok': true,
      'tileId': args['tileId'] ?? 0,
      'totalFramesAfter': 42,
      'integrationSecondsAfter': 1200.0,
      'contributorsAfter': 2,
    };
  }
}

/// A seam that models a single tile's running frame total as a non-atomic
/// load -> (async gap) -> store, so an interleaving fold would lose a frame.
/// Used to prove [SkyAtlasService]'s single-flight chain serializes folds.
class _AccumulatingSkyAtlasSeam implements SkyAtlasSeam {
  int tileFrames = 0;

  @override
  Future<Map<String, dynamic>> dispatch(Map<String, dynamic> args) async {
    if (args['action'] != 'fold') return {'ok': true};
    // Read-modify-write with an awaited gap in the middle: without
    // serialization, two concurrent folds both read the same prior total and
    // one increment is lost.
    final prior = tileFrames;
    await Future<void>.delayed(Duration.zero);
    tileFrames = prior + 1;
    return {
      'ok': true,
      'tilesTouched': const [42],
      'foldsByTile': [
        {
          'tileId': 42,
          'channels': 1,
          'centerRa': 83.6,
          'centerDec': -5.39,
          'coverageMean': 1.0,
          'totalFrames': tileFrames,
          'integrationSeconds': 300.0 * tileFrames,
          'framesAdded': 1,
          'weightAdded': 1.0,
          'rejected': 0,
        },
      ],
      'framesSkippedNoCoverage': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> queryCutout(Map<String, dynamic> args) async => {
    'ok': true,
  };

  @override
  Future<Map<String, dynamic>> regionInfo(Map<String, dynamic> args) async => {
    'ok': true,
  };

  @override
  Future<Map<String, dynamic>> growth(Map<String, dynamic> args) async => {
    'ok': true,
  };

  @override
  Future<Map<String, dynamic>> mergeDelta(Map<String, dynamic> args) async => {
    'ok': true,
  };
}

void main() {
  late NightshadeDatabase db;
  late SkyAtlasDao dao;
  late _FakeSkyAtlasSeam seam;
  late SkyAtlasService service;

  setUp(() async {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    dao = SkyAtlasDao(db);
    await db
        .into(db.imagingSessions)
        .insert(
          ImagingSessionsCompanion.insert(
            id: const Value(7),
            startTime: DateTime.utc(2026, 6, 11, 21),
          ),
        );
    seam = _FakeSkyAtlasSeam();
    service = SkyAtlasService(
      dao: dao,
      seam: seam,
      logger: LoggingService(),
      atlasRootResolver: () async => '/tmp/test_atlas',
    );
  });

  tearDown(() async {
    await db.close();
  });

  SolvedFrameRef frame({String path = '/tmp/light_001.fits'}) {
    return SolvedFrameRef.fromSolvedWcs(
      framePath: path,
      exposureSec: 300.0,
      wcs: const SolvedWcs(
        raHours: 5.575, // ~83.6 deg
        decDegrees: -5.39,
        rotationDeg: 0.0,
        pixelScaleArcsec: 1.5,
        imageWidth: 1000,
        imageHeight: 800,
      ),
    );
  }

  test('SolvedFrameRef builds the SipWcs JSON contract keys', () {
    final json = frame().toWcsJson();
    expect(
      json.keys,
      containsAll(<String>{
        'crval1',
        'crval2',
        'crpix1',
        'crpix2',
        'cd1_1',
        'cd1_2',
        'cd2_1',
        'cd2_2',
        'aOrder',
        'bOrder',
        'aCoeffs',
        'bCoeffs',
        'apOrder',
        'bpOrder',
        'apCoeffs',
        'bpCoeffs',
      }),
    );
    // crval from RA hours -> degrees, crpix at 1-based image centre.
    expect(json['crval1'] as double, closeTo(83.625, 1e-6));
    expect(json['crpix1'] as double, closeTo(500.5, 1e-9));
    expect(json['crpix2'] as double, closeTo(400.5, 1e-9));
    // CD reconstructed from scale+rotation (cd1_1 = -scale, no rotation).
    expect(json['cd1_1'] as double, closeTo(-1.5 / 3600.0, 1e-12));
  });

  test('foldSession dispatches a fold and persists tiles + timeline', () async {
    seam.onDispatch = (args) => {
      'ok': true,
      'tilesTouched': [42],
      'foldsByTile': [
        {
          'tileId': 42,
          'framesAdded': 1,
          'weightAdded': 1.0,
          'rejected': 0,
          'coverageMean': 1.0,
          'centerRa': 83.6,
          'centerDec': -5.39,
          'totalFrames': 1,
          'integrationSeconds': 300.0,
          'channels': 1,
        },
      ],
      'framesSkippedNoCoverage': 0,
    };

    final summary = await service.foldSession(
      sessionId: 7,
      frames: [frame()],
      label: '2026-06-11',
    );

    expect(summary.tilesTouched, [42]);
    expect(summary.totalFramesFolded, 1);
    expect(seam.dispatched.single['action'], 'fold');

    final tile = await dao.getTile(42);
    expect(tile, isNotNull);
    expect(tile!.totalFrames, 1);
    expect(tile.integrationSeconds, 300.0);
    expect(tile.lastFoldSessionId, 7);

    final folds = await dao.listFoldsForTileOverTime(42);
    expect(folds, hasLength(1));
    expect(folds.single.label, '2026-06-11');
    expect(folds.single.framesAdded, 1);
  });

  test('foldSession drops degenerate-WCS frames before dispatch', () async {
    const bad = SolvedFrameRef(
      framePath: '/tmp/bad.fits',
      crval1: 0,
      crval2: 0,
      crpix1: 0,
      crpix2: 0,
      cd1_1: 0,
      cd1_2: 0,
      cd2_1: 0,
      cd2_2: 0,
    );
    final summary = await service.foldSession(sessionId: 7, frames: [bad]);
    expect(summary.tilesTouched, isEmpty);
    expect(seam.dispatched, isEmpty, reason: 'no usable frames -> no dispatch');
  });

  test('ensureRegion upserts a region and refreshes rollups', () async {
    final id = await service.ensureRegion(
      name: 'Orion',
      centerRaDeg: 83.6,
      centerDecDeg: -5.39,
      radiusDeg: 1.0,
      kind: 'custom',
    );
    final regions = await service.regions();
    expect(regions.where((r) => r.id == id), hasLength(1));
    expect(regions.firstWhere((r) => r.id == id).name, 'Orion');
  });

  test('autoFoldCapturedImage skips non-light frames', () async {
    final image = DbCapturedImage(
      id: 1,
      filePath: '/tmp/dark.fits',
      fileName: 'dark.fits',
      fileFormat: 'fits',
      frameType: 'dark',
      exposureDuration: 300.0,
      binX: 1,
      binY: 1,
      isPlateSolved: true,
      solvedRa: 83.6,
      solvedDec: -5.39,
      capturedAt: DateTime.utc(2026, 6, 11, 22),
      createdAt: DateTime.utc(2026, 6, 11, 22),
      isAccepted: true,
    );
    final result = await service.autoFoldCapturedImage(
      image: image,
      imageWidth: 1000,
      imageHeight: 800,
    );
    expect(result, isNull);
    expect(seam.dispatched, isEmpty);
  });

  test(
    'mergeSwarmDelta writes the swarm overlay tree, not the own-light base',
    () async {
      // The `info` dispatch (read against the overlay root) supplies the
      // centre/channels used to seed a base index row for a never-imaged tile.
      seam.onDispatch = (args) {
        if (args['action'] == 'info') {
          return {
            'ok': true,
            'provenance': {
              'totalFrames': 42,
              'totalIntegrationSeconds': 1200.0,
              'contributors': const ['alice', 'bob'],
              'folds': const [],
            },
            'centerRa': 83.6,
            'centerDec': -5.39,
            'channels': 1,
            'coverageMean': 12.5,
          };
        }
        return {'ok': true};
      };

      final overlayFrames = await service.mergeSwarmDelta(
        tileId: 99,
        deltaPath: '/tmp/atlas/swarm/9/tile_99_9.nst',
      );

      // The merge targets the OVERLAY sidecar tree (separate from tiles/9), so
      // exportDelta — which only ever reads tiles/<order> — never sees it.
      expect(seam.merged, hasLength(1));
      expect(
        seam.merged.single['deltaPath'],
        '/tmp/atlas/swarm/9/tile_99_9.nst',
      );
      expect(
        seam.merged.single['basePath'],
        contains('swarm_overlay/tiles/9/99.nst'),
      );
      // The returned total is the overlay's own (community) depth.
      expect(overlayFrames, 42);

      // The base index row keeps own-light totals at zero (the user never
      // imaged this tile); the blended community depth lands in the overlay
      // columns so the contribution bar stays honest after a pull.
      final tile = await dao.getTile(99, healpixOrder: 9);
      expect(tile, isNotNull);
      expect(tile!.totalFrames, 0);
      expect(tile.integrationSeconds, 0);
      expect(tile.swarmOverlayFrames, 42);
      expect(tile.swarmOverlayIntegrationSeconds, closeTo(1200.0, 1e-9));
    },
  );

  test(
    'mergeSwarmDelta keeps own-light totals when a base row already exists',
    () async {
      // Seed a base row with own-light depth via a fold.
      seam.onDispatch = (args) {
        if (args['action'] == 'fold') {
          return {
            'ok': true,
            'tilesTouched': const [99],
            'foldsByTile': [
              {
                'tileId': 99,
                'channels': 1,
                'centerRa': 83.6,
                'centerDec': -5.39,
                'coverageMean': 4.0,
                'totalFrames': 5,
                'integrationSeconds': 1500.0,
                'framesAdded': 5,
                'weightAdded': 5.0,
                'rejected': 0,
              },
            ],
            'framesSkippedNoCoverage': 0,
          };
        }
        return {'ok': true};
      };
      await service.foldFrame(sessionId: 7, frame: frame());

      final before = await dao.getTile(99, healpixOrder: 9);
      expect(before!.totalFrames, 5);

      await service.mergeSwarmDelta(
        tileId: 99,
        deltaPath: '/tmp/atlas/swarm/9/tile_99_9.nst',
      );

      // Own-light totals + base sidecar pointer are untouched; only the overlay
      // columns gained the community depth — no `info` seed dispatch needed.
      final after = await dao.getTile(99, healpixOrder: 9);
      expect(after!.totalFrames, 5);
      expect(after.integrationSeconds, closeTo(1500.0, 1e-9));
      expect(after.sidecarPath, contains('tiles/9/99.nst'));
      expect(after.sidecarPath, isNot(contains('swarm_overlay')));
      expect(after.swarmOverlayFrames, 42);
    },
  );

  test(
    'single-flight chain serializes concurrent folds with no lost frames',
    () async {
      // A-concurrent-fold-no-loss: fire N folds at the same tile concurrently.
      // The accumulating seam models a non-atomic read-modify-write; only the
      // SkyAtlasService _serialized chain prevents interleaving from dropping a
      // frame. The persisted base total must equal the number of folds.
      final accSeam = _AccumulatingSkyAtlasSeam();
      final accService = SkyAtlasService(
        dao: dao,
        seam: accSeam,
        logger: LoggingService(),
        atlasRootResolver: () async => '/tmp/test_atlas',
      );

      const n = 8;
      await Future.wait(
        List.generate(
          n,
          (i) => accService.foldFrame(
            sessionId: 7,
            frame: frame(path: '/tmp/light_$i.fits'),
          ),
        ),
      );

      expect(
        accSeam.tileFrames,
        n,
        reason: 'serialized read-modify-write loses no fold',
      );
      final tile = await dao.getTile(42, healpixOrder: 9);
      expect(tile, isNotNull);
      expect(
        tile!.totalFrames,
        n,
        reason: 'every concurrent fold lands in the base tile total',
      );
    },
  );
}
