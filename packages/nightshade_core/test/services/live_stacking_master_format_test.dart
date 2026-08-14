// The stacked-master writer is PNG-only, and it has to say so.
//
// Live finding ND-6: Live Stacking → Stop → "Save master" → typed
// `/tmp/ns-audit/waveD-imaging-spine/stack_master.fits` → the log recorded
// `Saving PNG file: …/stack_master.png` and the file on disk was
// `PNG image data, 1920 x 1080, 16-bit grayscale`. The 16-bit depth survives,
// but a "stacked master" saved as PNG carries no FITS header, no WCS and no
// integration metadata — and the extension swap was never disclosed.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/network_backend.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/services/live_stacking_service.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NetworkBackend backend) {
    state = backend;
  }
}

void main() {
  late _MockNetworkBackend backend;
  late ProviderContainer container;
  late LiveStackingService service;

  setUp(() {
    backend = _MockNetworkBackend();
    when(() => backend.stackingGetResult()).thenAnswer(
      (_) async => const LiveStackingResult(
        width: 4,
        height: 4,
        data: <int>[],
        stats: LiveStackingStats(stackedFrameCount: 12),
      ),
    );
    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => _TestBackendNotifier(ref, backend),
        ),
      ],
    );
    addTearDown(container.dispose);
    service = container.read(liveStackingServiceProvider);
  });

  test('a .fits destination is refused rather than rewritten', () async {
    await expectLater(
      service.saveMaster(filePath: '/tmp/stack_master.fits'),
      throwsA(
        isA<LiveStackingMasterFormatUnsupported>()
            .having((e) => e.requestedExtension, 'extension', '.fits')
            .having((e) => e.toString(), 'message', contains('PNG')),
      ),
    );
    // The refusal happens before anything is read out of the stacker, so a
    // wrong-format request cannot disturb a running session.
    verifyNever(() => backend.stackingGetResult());
  });

  test('a .tif destination is refused too', () async {
    await expectLater(
      service.saveMaster(filePath: '/tmp/stack_master.tif'),
      throwsA(isA<LiveStackingMasterFormatUnsupported>()),
    );
  });

  test('the refusal explains what is lost, not just that it failed', () {
    const error = LiveStackingMasterFormatUnsupported('.fits');
    final message = error.toString();
    expect(message, contains('FITS header'));
    expect(message, contains('.png'));
  });
}
