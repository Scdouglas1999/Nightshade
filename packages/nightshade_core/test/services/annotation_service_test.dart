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

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(Ref ref, NightshadeBackend backend) : super(ref) {
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

  test('annotation pipeline uses annotation catalog when only annotation catalog is installed', () async {
    final tempDir = await Directory.systemTemp.createTemp('annotation_service_test_');
    addTearDown(() async => tempDir.delete(recursive: true));

    await CatalogManager.instance.initialize(tempDir.path);

    final annotationCatalogFile =
        File(CatalogManager.instance.annotationCatalogPath);
    await annotationCatalogFile.writeAsString(
      'RAJ2000,DEJ2000,Bmag,zhelio,PGC\n'
      '10.0,20.0,12.3,7000,12345\n',
    );

    final mockBackend = MockNightshadeBackend();
    when(() => mockBackend.eventStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockBackend.polarAlignmentEvents)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockBackend.plateSolve(
          imagePath: any(named: 'imagePath'),
          ra: any(named: 'ra'),
          dec: any(named: 'dec'),
          fovDegrees: any(named: 'fovDegrees'),
        )).thenAnswer(
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
        backendProvider.overrideWith((ref) => TestBackendNotifier(ref, mockBackend)),
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
      displayData: Uint8List(100 * 100),
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

    final state = await terminalState.future
        .timeout(const Duration(seconds: 2));

    expect(state.status, AnnotationStatus.complete);
    expect(state.objectsFound, greaterThan(0));
  });
}
