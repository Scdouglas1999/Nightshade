import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_updater/src/models/update_manifest.dart';
import 'package:nightshade_updater/src/models/update_state.dart';
import 'package:nightshade_updater/src/providers/update_provider.dart';
import 'package:nightshade_updater/src/services/update_service.dart';

class MockUpdateService extends Mock implements UpdateService {}

class MockNightshadeBackend extends Mock implements NightshadeBackend {}

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(super.ref, NightshadeBackend initial) {
    state = initial;
  }
}

final updateSafetyProbeProvider = FutureProvider<void>((ref) {
  return defaultUpdateApplySafetyCheck(ref);
});

void main() {
  late MockUpdateService updateService;

  setUp(() {
    updateService = MockUpdateService();
    when(() => updateService.verifyPendingInstall())
        .thenAnswer((_) async => const PendingInstallStatus.none());
    when(() => updateService.getStagedUpdate()).thenAnswer((_) async => null);
    when(() => updateService.dispose()).thenReturn(null);
  });

  UpdateManifest manifest() => UpdateManifest(
        version: '2.1.0',
        buildNumber: 42,
        releaseDate: DateTime.utc(2026, 5, 25),
        platform: 'windows',
        arch: 'x64',
        files: const {},
        totalSize: 0,
        compressedSize: 0,
        downloadUrl: 'https://example.invalid/nightshade.zip',
      );

  Future<UpdateNotifier> stagedNotifier({
    required UpdateApplySafetyCheck safetyCheck,
  }) async {
    final notifier = UpdateNotifier(
      currentVersion: '2.0.0',
      currentBuildNumber: 41,
      updateService: updateService,
      applySafetyCheck: safetyCheck,
    );

    await Future<void>.delayed(Duration.zero);
    notifier.setStagedFromLanPush(manifest(), r'C:\staged');
    return notifier;
  }

  test('applyUpdate refuses staged update when safety check blocks', () async {
    final notifier = await stagedNotifier(
      safetyCheck: () async {
        throw UpdateException('active sequence must stop first');
      },
    );

    await notifier.applyUpdate();

    expect(notifier.state.status, UpdateStatus.error);
    expect(notifier.state.errorMessage, contains('active sequence'));
    verifyNever(() => updateService.applyUpdate());

    notifier.dispose();
  });

  test('applyUpdate runs safety check before spawning updater', () async {
    final calls = <String>[];
    when(() => updateService.applyUpdate()).thenAnswer((_) async {
      calls.add('apply');
    });

    final notifier = await stagedNotifier(
      safetyCheck: () async {
        calls.add('safety');
      },
    );

    await notifier.applyUpdate();

    expect(calls, ['safety', 'apply']);
    verify(() => updateService.applyUpdate()).called(1);

    notifier.dispose();
  });

  test('default safety check checkpoints then blocks active sequence',
      () async {
    final backend = MockNightshadeBackend();
    when(() => backend.saveCheckpoint()).thenAnswer((_) async {});

    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => TestBackendNotifier(ref, backend),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(sequenceExecutionStateProvider.notifier).state =
        SequenceExecutionState.running;

    await expectLater(
      container.read(updateSafetyProbeProvider.future),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('running'),
        ),
      ),
    );
    verify(() => backend.saveCheckpoint()).called(1);
  });

  test('default safety check blocks active camera cooler', () async {
    final backend = MockNightshadeBackend();

    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => TestBackendNotifier(ref, backend),
        ),
      ],
    );
    addTearDown(container.dispose);

    final camera = container.read(cameraStateProvider.notifier);
    camera.setConnecting('cam1', 'Camera');
    camera.setConnected();
    camera.setCooling(true);

    await expectLater(
      container.read(updateSafetyProbeProvider.future),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('cooler'),
        ),
      ),
    );
    verifyNever(() => backend.saveCheckpoint());
  });

  test('default safety check blocks unparked mount', () async {
    final backend = MockNightshadeBackend();

    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => TestBackendNotifier(ref, backend),
        ),
      ],
    );
    addTearDown(container.dispose);

    final mount = container.read(mountStateProvider.notifier);
    mount.setConnecting('mount1');
    mount.setConnected();
    mount.setParked(false);

    await expectLater(
      container.read(updateSafetyProbeProvider.future),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.message,
          'message',
          contains('parked'),
        ),
      ),
    );
    verifyNever(() => backend.saveCheckpoint());
  });
}
