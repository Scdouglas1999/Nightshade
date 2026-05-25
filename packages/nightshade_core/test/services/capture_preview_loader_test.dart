import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/imaging/imaging_models.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/services/capture_preview_loader.dart';
import 'package:nightshade_core/src/services/imaging_service.dart';

import '../mocks/mock_backend.dart';
import '../services/imaging_service_test.dart' show makeCapturedImageResult;

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(Ref ref, NightshadeBackend backend) : super(ref) {
    state = backend;
  }
}

void main() {
  late MockBackend mockBackend;
  late ProviderContainer container;

  setUp(() {
    mockBackend = MockBackend();
    registerFallbackValue(FrameType.light);
    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => TestBackendNotifier(ref, mockBackend),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  CapturedImageData _samplePreview() {
    final result = makeCapturedImageResult(width: 4, height: 2);
    return capturedImageDataFromResult(
      capturedImage: result,
      settings: const ExposureSettings(
        exposureTime: 1.0,
        gain: 0,
        offset: 0,
        binningX: 1,
        binningY: 1,
        frameType: FrameType.light,
      ),
      capturedAt: DateTime.utc(2026, 5, 23, 12),
    );
  }

  test('publish shows JPEG immediately then merges raw when ready', () async {
    final rawBytes = Uint8List(4 * 2 * 2);
    for (var i = 0; i < rawBytes.length; i++) {
      rawBytes[i] = i % 256;
    }

    when(() => mockBackend.getLastRawImageData(any()))
        .thenAnswer((_) async => rawBytes);

    final publisher = container.read(capturePreviewPublisherProvider);
    final preview = _samplePreview();

    publisher.publish(container, preview, 'cam-1');

    final immediate = container.read(currentImageProvider);
    expect(immediate, isNotNull);
    expect(immediate!.displayData, preview.displayData);
    expect(immediate.rawLoadStatus, RawLoadStatus.loading);
    expect(immediate.rawU16, isNull);

    await pumpEventQueue(times: 5);

    final merged = container.read(currentImageProvider);
    expect(merged, isNotNull);
    expect(merged!.rawLoadStatus, RawLoadStatus.ready);
    expect(merged.rawU16, isNotNull);
    expect(merged.rawU16!.length, 4 * 2);
    expect(merged.displayData, preview.displayData);
  });

  test('raw failure keeps JPEG preview', () async {
    when(() => mockBackend.getLastRawImageData(any()))
        .thenThrow(Exception('503 unavailable'));

    final publisher = container.read(capturePreviewPublisherProvider);
    publisher.publish(container, _samplePreview(), 'cam-1');

    await pumpEventQueue(times: 5);

    final after = container.read(currentImageProvider);
    expect(after, isNotNull);
    expect(after!.rawLoadStatus, RawLoadStatus.failed);
    expect(after.rawU16, isNull);
    expect(after.displayData.isNotEmpty, isTrue);
  });

  test('stale raw load does not overwrite newer capture', () async {
    var fetchCount = 0;
    when(() => mockBackend.getLastRawImageData(any())).thenAnswer((_) async {
      fetchCount++;
      if (fetchCount == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return Uint8List(4 * 2 * 2);
    });

    final publisher = container.read(capturePreviewPublisherProvider);
    final older = _samplePreview();
    publisher.publish(container, older, 'cam-1');

    await Future<void>.delayed(const Duration(milliseconds: 20));

    final newer = _samplePreview().copyWith(
      capturedAt: DateTime.utc(2026, 5, 23, 13),
    );
    publisher.publish(container, newer, 'cam-1');

    await pumpEventQueue(times: 20);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final current = container.read(currentImageProvider);
    expect(current!.capturedAt, newer.capturedAt);
    expect(current.rawLoadStatus, RawLoadStatus.ready);
  });
}
