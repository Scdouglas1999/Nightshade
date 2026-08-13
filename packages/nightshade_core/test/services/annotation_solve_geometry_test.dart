// A "successful" solve with no usable geometry is not a solution.
//
// Live finding IMG-4: the Annotate chip went "Searching catalogs…" →
// "Found 0 objects" in the green success treatment on a frame the solver had
// not solved — no .wcs on disk, the viewport's own sky readout still "Sky --".
// "Found 0 objects" is a statement about the sky; a user who trusts it concludes
// their field is empty rather than that solving is broken. The pipeline only
// checked the success flag, so a result carrying no field scale still became a
// catalog search over a field of zero size, which of course returns nothing.
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

class _MockBackend extends Mock implements NightshadeBackend {}

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

class _Settings extends AnnotationSettingsNotifier {
  @override
  Future<AnnotationSettings> build() async => const AnnotationSettings();
}

PlateSolveResult _result({
  required double pixelScale,
  required double fieldWidth,
  double ra = 10,
  double dec = 20,
}) => PlateSolveResult(
  success: true,
  ra: ra,
  dec: dec,
  pixelScale: pixelScale,
  rotation: 0,
  fieldWidth: fieldWidth,
  fieldHeight: fieldWidth,
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

void main() {
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(0.0);
  });

  Future<AnnotationState> runPipeline(PlateSolveResult solve) async {
    final tempDir = await Directory.systemTemp.createTemp(
      'annotation_geometry_test_',
    );
    addTearDown(() async => tempDir.delete(recursive: true));

    await CatalogManager.instance.initialize(tempDir.path);
    await File(CatalogManager.instance.annotationCatalogPath).writeAsString(
      'RAJ2000,DEJ2000,Bmag,zhelio,PGC\n'
      '10.0,20.0,12.3,7000,12345\n',
    );

    final backend = _MockBackend();
    when(() => backend.eventStream).thenAnswer((_) => const Stream.empty());
    when(
      () => backend.polarAlignmentEvents,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => backend.plateSolve(
        imagePath: any(named: 'imagePath'),
        ra: any(named: 'ra'),
        dec: any(named: 'dec'),
        fovDegrees: any(named: 'fovDegrees'),
        timeoutSeconds: any(named: 'timeoutSeconds'),
      ),
    ).thenAnswer((_) async => solve);

    final container = ProviderContainer(
      overrides: [
        inMemoryDatabaseOverride(),
        backendProvider.overrideWith(
          (ref) => _TestBackendNotifier(ref, backend),
        ),
        annotationSettingsProvider.overrideWith(_Settings.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(annotationServiceProvider);

    final imagePath = path.join(tempDir.path, 'frame.fits');
    await File(imagePath).writeAsString('test');

    final terminal = Completer<AnnotationState>();
    container.listen(annotationStateProvider, (previous, next) {
      if (!next.isProcessing &&
          next.status != AnnotationStatus.idle &&
          !terminal.isCompleted) {
        terminal.complete(next);
      }
    });

    container.read(currentImageProvider.notifier).state = CapturedImageData(
      width: 100,
      height: 100,
      displayData: Uint8List(100 * 100 * 4),
      histogram: List.filled(256, 0),
      stats: const ImageStats(mean: 0),
      capturedAt: DateTime.now(),
      settings: const ExposureSettings(exposureTime: 1, gain: 100, offset: 10),
      filePath: imagePath,
    );

    return terminal.future.timeout(const Duration(seconds: 5));
  }

  test('a solve with no field scale is reported as a failed solve', () async {
    final state = await runPipeline(_result(pixelScale: 0, fieldWidth: 0));

    expect(
      state.status,
      AnnotationStatus.plateSolveFailed,
      reason: 'no scale means no field to search, so "0 objects" is not a fact',
    );
    expect(state.objectsFound, isNot(0));
  });

  test('a solve with real geometry still annotates', () async {
    final state = await runPipeline(_result(pixelScale: 1.5, fieldWidth: 1));

    expect(state.status, AnnotationStatus.complete);
    expect(state.objectsFound, greaterThan(0));
  });
}
