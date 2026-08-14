import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:path/path.dart' as path;
import '../harness/in_memory_database.dart';

class MockNightshadeBackend extends Mock implements NightshadeBackend {}

class MockCatalogManager extends Mock implements CatalogManager {}

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

/// The annotate pipeline solves through `PlateSolveService` — the same entry
/// centering, framing and the polar wizard use — so every backend double has
/// to answer the solver-choice probe that entry makes before it dispatches.
void stubSolverDetection(MockNightshadeBackend backend) {
  when(() => backend.detectPlateSolvers()).thenAnswer(
    (_) async => const PlateSolverDetection(
      astapPath: '/usr/bin/astap',
      catalogPath: '/usr/share/astap',
    ),
  );
  when(() => backend.getPlateSolverConfig()).thenAnswer(
    (_) async => const PlateSolverPreference(choice: PlateSolverChoice.astap),
  );
}

class TestAnnotationSettingsNotifier extends AnnotationSettingsNotifier {
  @override
  Future<AnnotationSettings> build() async => const AnnotationSettings();
}

class FailingAnnotationSettingsNotifier extends AnnotationSettingsNotifier {
  @override
  Future<AnnotationSettings> build() async {
    throw StateError('settings database unavailable');
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(0.0);
  });

  test(
    'annotation pipeline surfaces unavailable settings and does no work',
    () async {
      final container = ProviderContainer(
        overrides: [
          inMemoryDatabaseOverride(),
          annotationSettingsProvider.overrideWith(
            FailingAnnotationSettingsNotifier.new,
          ),
        ],
      );
      addTearDown(container.dispose);
      final service = container.read(annotationServiceProvider);
      final imageData = CapturedImageData(
        width: 1,
        height: 1,
        displayData: Uint8List(4),
        histogram: List.filled(256, 0),
        stats: const ImageStats(mean: 0),
        capturedAt: DateTime.now(),
        settings: const ExposureSettings(
          exposureTime: 1,
          gain: 100,
          offset: 10,
        ),
        filePath: '/tmp/unavailable-settings.fits',
      );

      await service.processNewImage(imageData);

      final state = container.read(annotationStateProvider);
      expect(state.status, AnnotationStatus.error);
      expect(state.errorDetails, contains('settings database unavailable'));
      expect(container.read(currentAnnotationProvider), isNull);
    },
  );

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
      stubSolverDetection(mockBackend);
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
          timeoutSeconds: any(named: 'timeoutSeconds'),
        ),
      ).thenAnswer(
        (_) async => PlateSolveResult(
          success: true,
          ra: 10.0,
          dec: 20.0,
          pixelScale: 1.5,
          rotation: 0.0,
          fieldWidth: 1.0,
          fieldHeight: 1.0,
          solveTimeSecs: 0.1,
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: Float64List(0),
          sipBCoeffs: Float64List(0),
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: Float64List(0),
          sipBpCoeffs: Float64List(0),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          inMemoryDatabaseOverride(),
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
      stubSolverDetection(mockBackend);
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
          timeoutSeconds: any(named: 'timeoutSeconds'),
        ),
      ).thenAnswer(
        (_) async => PlateSolveResult(
          success: true,
          ra: 180.0,
          dec: 30.0,
          pixelScale: 1.5,
          rotation: 0.0,
          fieldWidth: 1.0,
          fieldHeight: 1.0,
          solveTimeSecs: 0.1,
          cd11: 0,
          cd12: 0,
          cd21: 0,
          cd22: 0,
          sipAOrder: 0,
          sipBOrder: 0,
          sipACoeffs: Float64List(0),
          sipBCoeffs: Float64List(0),
          sipApOrder: 0,
          sipBpOrder: 0,
          sipApCoeffs: Float64List(0),
          sipBpCoeffs: Float64List(0),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          inMemoryDatabaseOverride(),
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
          timeoutSeconds: any(named: 'timeoutSeconds'),
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
          inMemoryDatabaseOverride(),
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

  test(
    'a late solve cannot overwrite the newer image annotation state',
    () async {
      final mockCatalogManager = MockCatalogManager();
      when(() => mockCatalogManager.isInitialized).thenReturn(true);
      when(
        mockCatalogManager.getDsoCatalogStatus,
      ).thenAnswer((_) async => CatalogStatus.notInstalled());
      when(
        mockCatalogManager.getStarCatalogStatus,
      ).thenAnswer((_) async => CatalogStatus.notInstalled());
      when(() => mockCatalogManager.getAnnotationCatalogStatus()).thenAnswer(
        (_) async => const CatalogStatus(
          isInstalled: true,
          installedPath: '/tmp/annotation.csv',
        ),
      );

      final backend = MockNightshadeBackend();
      stubSolverDetection(backend);
      final firstSolve = Completer<PlateSolveResult>();
      var solveCalls = 0;
      when(
        () => backend.plateSolve(
          imagePath: any(named: 'imagePath'),
          ra: any(named: 'ra'),
          dec: any(named: 'dec'),
          fovDegrees: any(named: 'fovDegrees'),
          timeoutSeconds: any(named: 'timeoutSeconds'),
        ),
      ).thenAnswer((invocation) {
        solveCalls++;
        final imagePath = invocation.namedArguments[#imagePath] as String;
        if (imagePath == '/tmp/first.fits') return firstSolve.future;
        return Future.value(_failedSolve('new image failed'));
      });

      final container = ProviderContainer(
        overrides: [
          inMemoryDatabaseOverride(),
          backendProvider.overrideWith(
            (ref) => TestBackendNotifier(ref, backend),
          ),
          annotationSettingsProvider.overrideWith(
            TestAnnotationSettingsNotifier.new,
          ),
          annotationServiceProvider.overrideWith(
            (ref) => AnnotationService(ref, catalogManager: mockCatalogManager),
          ),
        ],
      );
      addTearDown(container.dispose);
      final service = container.read(annotationServiceProvider);

      final first = service.processNewImage(_image('/tmp/first.fits'));
      while (solveCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await service.processNewImage(_image('/tmp/second.fits'));
      final newImageState = container.read(annotationStateProvider);
      expect(newImageState.status, AnnotationStatus.plateSolveFailed);

      firstSolve.complete(_failedSolve('old image failed'));
      await first;

      final finalState = container.read(annotationStateProvider);
      expect(finalState.status, newImageState.status);
      expect(finalState.errorDetails, newImageState.errorDetails);
      expect(container.read(currentAnnotationProvider), isNull);
      // ONE backend solve, not two: the annotate path now goes through
      // PlateSolveService, whose single-flight gate refuses a solve while
      // another is in flight instead of launching a second solver process
      // against the same catalog. (The live log showed exactly that — two
      // ASTAP invocations 45 ms apart over one frame.) The invariant this
      // test exists for is unchanged: the newer image's state stands.
      expect(solveCalls, 1);
    },
  );

  test(
    'a late progressive SNR search cannot overwrite a newer image state',
    () async {
      final catalogManager = MockCatalogManager();
      when(() => catalogManager.isInitialized).thenReturn(true);
      when(catalogManager.getDsoCatalogStatus).thenAnswer(
        (_) async => const CatalogStatus(
          isInstalled: true,
          installedPath: '/tmp/dso.csv',
        ),
      );
      when(
        catalogManager.getStarCatalogStatus,
      ).thenAnswer((_) async => CatalogStatus.notInstalled());
      when(
        catalogManager.getAnnotationCatalogStatus,
      ).thenAnswer((_) async => CatalogStatus.notInstalled());

      final progressiveSearch = Completer<List<OpenNgcData>>();
      final progressiveSearchStarted = Completer<void>();
      var catalogSearches = 0;
      when(
        () => catalogManager.searchDsoNearby(
          ra: any(named: 'ra'),
          dec: any(named: 'dec'),
          radiusDegrees: any(named: 'radiusDegrees'),
          maxMagnitude: any(named: 'maxMagnitude'),
        ),
      ).thenAnswer((_) {
        catalogSearches++;
        if (catalogSearches == 1) return Future.value([]);
        if (!progressiveSearchStarted.isCompleted) {
          progressiveSearchStarted.complete();
        }
        return progressiveSearch.future;
      });

      final backend = MockNightshadeBackend();
      stubSolverDetection(backend);
      when(
        () => backend.plateSolve(
          imagePath: any(named: 'imagePath'),
          ra: any(named: 'ra'),
          dec: any(named: 'dec'),
          fovDegrees: any(named: 'fovDegrees'),
          timeoutSeconds: any(named: 'timeoutSeconds'),
        ),
      ).thenAnswer((invocation) {
        final imagePath = invocation.namedArguments[#imagePath] as String;
        return Future.value(
          imagePath == '/tmp/first.fits'
              ? _successfulSolve()
              : _failedSolve('new image failed'),
        );
      });

      final container = ProviderContainer(
        overrides: [
          inMemoryDatabaseOverride(),
          backendProvider.overrideWith(
            (ref) => TestBackendNotifier(ref, backend),
          ),
          annotationSettingsProvider.overrideWith(
            TestAnnotationSettingsNotifier.new,
          ),
          annotationServiceProvider.overrideWith(
            (ref) => AnnotationService(ref, catalogManager: catalogManager),
          ),
        ],
      );
      addTearDown(container.dispose);
      final service = container.read(annotationServiceProvider);

      await service.processNewImage(_image('/tmp/first.fits'));
      expect(
        container.read(annotationStateProvider).status,
        AnnotationStatus.complete,
      );

      final progressive = service.progressiveReAnnotate(10, 17);
      await progressiveSearchStarted.future;

      container.read(currentAnnotationProvider.notifier).state = null;
      await service.processNewImage(_image('/tmp/second.fits'));
      final newImageState = container.read(annotationStateProvider);
      expect(newImageState.status, AnnotationStatus.plateSolveFailed);

      progressiveSearch.complete([]);
      await progressive;

      final finalState = container.read(annotationStateProvider);
      expect(finalState.status, newImageState.status);
      expect(finalState.errorDetails, newImageState.errorDetails);
      expect(container.read(currentAnnotationProvider), isNull);
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
        inMemoryDatabaseOverride(),
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

CapturedImageData _image(String filePath) => CapturedImageData(
  width: 10,
  height: 10,
  displayData: Uint8List(10 * 10 * 4),
  histogram: List.filled(256, 0),
  stats: const ImageStats(mean: 10, snr: 5),
  capturedAt: DateTime.now(),
  settings: const ExposureSettings(exposureTime: 1, gain: 100, offset: 10),
  filePath: filePath,
);

PlateSolveResult _failedSolve(String error) => PlateSolveResult(
  success: false,
  ra: 0,
  dec: 0,
  pixelScale: 0,
  rotation: 0,
  fieldWidth: 0,
  fieldHeight: 0,
  solveTimeSecs: 0,
  error: error,
  cd11: 0,
  cd12: 0,
  cd21: 0,
  cd22: 0,
  sipAOrder: 0,
  sipBOrder: 0,
  sipACoeffs: Float64List(0),
  sipBCoeffs: Float64List(0),
  sipApOrder: 0,
  sipBpOrder: 0,
  sipApCoeffs: Float64List(0),
  sipBpCoeffs: Float64List(0),
);

PlateSolveResult _successfulSolve() => PlateSolveResult(
  success: true,
  ra: 10,
  dec: 20,
  pixelScale: 1,
  rotation: 0,
  fieldWidth: 1,
  fieldHeight: 1,
  solveTimeSecs: 0.1,
  cd11: 0,
  cd12: 0,
  cd21: 0,
  cd22: 0,
  sipAOrder: 0,
  sipBOrder: 0,
  sipACoeffs: Float64List(0),
  sipBCoeffs: Float64List(0),
  sipApOrder: 0,
  sipBpOrder: 0,
  sipApCoeffs: Float64List(0),
  sipBpCoeffs: Float64List(0),
);

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
