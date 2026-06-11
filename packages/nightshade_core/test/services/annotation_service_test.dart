import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:path/path.dart' as path;

class MockNightshadeBackend extends Mock implements NightshadeBackend {}

class MockCatalogManager extends Mock implements CatalogManager {}

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

class TestAnnotationSettingsNotifier extends AnnotationSettingsNotifier {
  @override
  Future<AnnotationSettings> build() async => const AnnotationSettings();
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(0.0);
  });

  test(
    'annotation pipeline uses annotation catalog when only annotation catalog is installed',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'annotation_service_test_',
      );
      addTearDown(() async => tempDir.delete(recursive: true));

      await CatalogManager.instance.initialize(tempDir.path);

      final annotationCatalogFile = File(
        CatalogManager.instance.annotationCatalogPath,
      );
      await annotationCatalogFile.writeAsString(
        'RAJ2000,DEJ2000,Bmag,zhelio,PGC\n'
        '10.0,20.0,12.3,7000,12345\n',
      );

      final mockBackend = MockNightshadeBackend();
      when(
        () => mockBackend.eventStream,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => mockBackend.polarAlignmentEvents,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => mockBackend.plateSolve(
          imagePath: any(named: 'imagePath'),
          ra: any(named: 'ra'),
          dec: any(named: 'dec'),
          fovDegrees: any(named: 'fovDegrees'),
        ),
      ).thenAnswer(
        (_) async => const PlateSolveResult(
          success: true,
          ra: 10.0,
          dec: 20.0,
          pixelScale: 1.5,
          rotation: 0.0,
          fieldWidth: 1.0,
          fieldHeight: 1.0,
          solveTimeSecs: 0.1,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => TestBackendNotifier(ref, mockBackend),
          ),
          annotationSettingsProvider.overrideWith(
            () => TestAnnotationSettingsNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(annotationServiceProvider);

      final imagePath = path.join(tempDir.path, 'test.fits');
      await File(imagePath).writeAsString('test');

      final imageData = CapturedImageData(
        width: 100,
        height: 100,
        displayData: Uint8List(100 * 100 * 4),
        histogram: List.filled(256, 0),
        stats: const ImageStats(mean: 0),
        capturedAt: DateTime.now(),
        settings: const ExposureSettings(
          exposureTime: 1.0,
          gain: 100,
          offset: 10,
        ),
        filePath: imagePath,
      );

      final terminalState = Completer<AnnotationState>();
      container.listen(annotationStateProvider, (previous, next) {
        if (!next.isProcessing &&
            next.status != AnnotationStatus.idle &&
            !terminalState.isCompleted) {
          terminalState.complete(next);
        }
      });

      container.read(currentImageProvider.notifier).state = imageData;

      final state = await terminalState.future.timeout(
        const Duration(seconds: 2),
      );

      expect(state.status, AnnotationStatus.complete);
      expect(state.objectsFound, greaterThan(0));
    },
  );

  test(
    'annotation service converts mount RA hint from hours to degrees before plate solve',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'annotation_ra_hint_test_',
      );
      addTearDown(() async => tempDir.delete(recursive: true));

      final annotationCatalogPath = path.join(
        tempDir.path,
        'glade_plus_galaxies.csv',
      );
      await File(annotationCatalogPath).writeAsString(
        'RAJ2000,DEJ2000,Bmag,zhelio,PGC\n'
        '180.0,30.0,12.0,7000,67890\n',
      );

      final mockCatalogManager = MockCatalogManager();
      when(() => mockCatalogManager.isInitialized).thenReturn(true);
      when(
        () => mockCatalogManager.getDsoCatalogStatus(),
      ).thenAnswer((_) async => CatalogStatus.notInstalled());
      when(
        () => mockCatalogManager.getStarCatalogStatus(),
      ).thenAnswer((_) async => CatalogStatus.notInstalled());
      when(() => mockCatalogManager.getAnnotationCatalogStatus()).thenAnswer(
        (_) async => CatalogStatus(
          isInstalled: true,
          installedPath: annotationCatalogPath,
        ),
      );
      when(
        () => mockCatalogManager.searchDsoNearby(
          ra: any(named: 'ra'),
          dec: any(named: 'dec'),
          radiusDegrees: any(named: 'radiusDegrees'),
          maxMagnitude: any(named: 'maxMagnitude'),
        ),
      ).thenAnswer((_) async => []);

      final mockBackend = MockNightshadeBackend();
      when(
        () => mockBackend.eventStream,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => mockBackend.polarAlignmentEvents,
      ).thenAnswer((_) => const Stream.empty());
      when(
        () => mockBackend.plateSolve(
          imagePath: any(named: 'imagePath'),
          ra: any(named: 'ra'),
          dec: any(named: 'dec'),
          fovDegrees: any(named: 'fovDegrees'),
        ),
      ).thenAnswer(
        (_) async => const PlateSolveResult(
          success: true,
          ra: 180.0,
          dec: 30.0,
          pixelScale: 1.5,
          rotation: 0.0,
          fieldWidth: 1.0,
          fieldHeight: 1.0,
          solveTimeSecs: 0.1,
        ),
      );

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => TestBackendNotifier(ref, mockBackend),
          ),
          annotationSettingsProvider.overrideWith(
            () => TestAnnotationSettingsNotifier(),
          ),
          annotationServiceProvider.overrideWith(
            (ref) => AnnotationService(ref, catalogManager: mockCatalogManager),
          ),
        ],
      );
      addTearDown(container.dispose);

      container.read(annotationServiceProvider);

      container
          .read(mountStateProvider.notifier)
          .updatePosition(12.0, 30.0, 0.0, 0.0);

      final imagePath = path.join(tempDir.path, 'test.fits');
      await File(imagePath).writeAsString('test');

      final imageData = CapturedImageData(
        width: 100,
        height: 100,
        displayData: Uint8List(100 * 100 * 4),
        histogram: List.filled(256, 0),
        stats: const ImageStats(mean: 50, stdDev: 10, snr: 5),
        capturedAt: DateTime.now(),
        settings: const ExposureSettings(
          exposureTime: 1.0,
          gain: 100,
          offset: 10,
        ),
        filePath: imagePath,
      );

      final terminalState = Completer<AnnotationState>();
      container.listen(annotationStateProvider, (previous, next) {
        if (!next.isProcessing &&
            next.status != AnnotationStatus.idle &&
            !terminalState.isCompleted) {
          terminalState.complete(next);
        }
      });

      container.read(currentImageProvider.notifier).state = imageData;

      final state = await terminalState.future.timeout(
        const Duration(seconds: 3),
      );
      expect(state.status, AnnotationStatus.complete);

      verify(
        () => mockBackend.plateSolve(
          imagePath: imagePath,
          ra: 180.0,
          dec: 30.0,
          fovDegrees: any(named: 'fovDegrees'),
        ),
      ).called(1);
    },
  );

  test(
    'findObjectsInFov rethrows a genuine annotation-catalog query failure as '
    'AnnotationCatalogQueryException instead of swallowing it into []',
    () async {
      // Drive a REAL query failure into the pipeline's site-1 catch by handing
      // findObjectsInFov an annotation catalog whose searchNearby throws.
      // Before the fix this was caught, logged, and converted into an empty list
      // — indistinguishable from "no objects in this frame". Now it must
      // re-throw a typed AnnotationCatalogQueryException so the failure surfaces.
      final tempDir = await Directory.systemTemp.createTemp(
        'annotation_query_failure_test_',
      );
      addTearDown(() async => tempDir.delete(recursive: true));

      await CatalogManager.instance.initialize(tempDir.path);

      final container = ProviderContainer(
        overrides: [
          annotationSettingsProvider.overrideWith(
            () => TestAnnotationSettingsNotifier(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(annotationServiceProvider);
      // Inject a catalog whose query throws — a genuine failure, not empty data.
      service.debugAnnotationCatalogOverride = _ThrowingAnnotationCatalog();

      const plateSolve = PlateSolveData(
        ra: 10.0,
        dec: 20.0,
        pixelScale: 1.5,
        rotation: 0.0,
        fieldWidth: 1.0,
        fieldHeight: 1.0,
        imageWidth: 100,
        imageHeight: 100,
      );

      await expectLater(
        () => service.findObjectsInFov(plateSolve: plateSolve),
        throwsA(
          isA<AnnotationCatalogQueryException>().having(
            (e) => e.catalog,
            'catalog',
            'annotation',
          ),
        ),
      );
    },
  );

  test('findObjectsInFov returns an empty list (no throw) when catalogs are '
      'present but match nothing in the frame', () async {
    // A successful-but-empty query is a legitimate result, not a failure. With
    // an annotation catalog installed but holding only an object far outside
    // this field of view, findObjectsInFov must return an empty list WITHOUT
    // throwing — this is how the pipeline reports a quiet "0 objects" complete.
    final tempDir = await Directory.systemTemp.createTemp(
      'annotation_empty_ok_test_',
    );
    addTearDown(() async => tempDir.delete(recursive: true));

    await CatalogManager.instance.initialize(tempDir.path);

    // One well-formed galaxy at RA=200, far from the RA=10 FOV below.
    await File(CatalogManager.instance.annotationCatalogPath).writeAsString(
      'RAJ2000,DEJ2000,Bmag,zhelio,PGC\n'
      '200.0,-30.0,12.3,7000,12345\n',
    );

    final container = ProviderContainer(
      overrides: [
        annotationSettingsProvider.overrideWith(
          () => TestAnnotationSettingsNotifier(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final service = container.read(annotationServiceProvider);

    const plateSolve = PlateSolveData(
      ra: 10.0,
      dec: 20.0,
      pixelScale: 1.5,
      rotation: 0.0,
      fieldWidth: 1.0,
      fieldHeight: 1.0,
      imageWidth: 100,
      imageHeight: 100,
    );

    final objects = await service.findObjectsInFov(plateSolve: plateSolve);
    expect(objects, isEmpty);
  });
}

/// An [AnnotationCatalog] whose [searchNearby] throws, standing in for a
/// corrupt/unreadable catalog so the pipeline's genuine-failure path can be
/// exercised. Reports itself available so the query is actually attempted.
class _ThrowingAnnotationCatalog extends AnnotationCatalog {
  @override
  bool get isAvailable => true;

  @override
  Future<List<AnnotationObject>> searchNearby({
    required double ra,
    required double dec,
    required double radiusDegrees,
    double? maxMagnitude,
    Set<AnnotationObjectType>? typeFilter,
  }) async {
    throw StateError('annotation catalog read failed');
  }
}
