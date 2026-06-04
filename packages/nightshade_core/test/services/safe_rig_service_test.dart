import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../mocks/mock_backend.dart';

/// Pin the backend StateNotifierProvider to a caller-supplied instance.
class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

/// SafeRigService variant that records (and optionally fails) the dome/cover
/// physical-close calls instead of dispatching them to the Rust bridge — the
/// real close goes through `bridge_api`, which has no native lib under test.
/// The decision logic (whether/when to call these) is exactly the production
/// path; only the leaf transport is overridden.
class _RecordingSafeRig extends SafeRigService {
  _RecordingSafeRig(super.ref, {this.failDome = false});

  final bool failDome;
  final List<String> domeClosedFor = [];
  final List<String> coverClosedFor = [];

  @override
  Future<void> closeDomeShutter(NightshadeBackend backend, String deviceId) async {
    domeClosedFor.add(deviceId);
    if (failDome) throw Exception('dome stuck');
  }

  @override
  Future<void> closeCalibratorCover(
      NightshadeBackend backend, String deviceId) async {
    coverClosedFor.add(deviceId);
  }
}

void main() {
  setUpAll(registerMocktailFallbackValues);

  group('SafeRigService.safeTheRig', () {
    late MockBackend backend;

    setUp(() {
      backend = MockBackend();
      when(() => backend.eventStream).thenAnswer((_) => const Stream.empty());
      when(() => backend.polarAlignmentEvents)
          .thenAnswer((_) => const Stream.empty());
      when(() => backend.sequencerPause()).thenAnswer((_) async {});
      when(() => backend.mountPark(any())).thenAnswer((_) async {});
    });

    ProviderContainer makeContainer({
      bool mountConnected = true,
      bool mountParked = false,
      bool domeConnected = false,
      ShutterStatus domeShutter = ShutterStatus.open,
      bool coverConnected = false,
      CoverStatus coverStatus = CoverStatus.open,
      SafeRigService Function(Ref)? safeRigBuilder,
    }) {
      return ProviderContainer(
        overrides: [
          backendProvider
              .overrideWith((ref) => _TestBackendNotifier(ref, backend)),
          mountStateProvider.overrideWith((ref) {
            final n = MountStateNotifier(ref);
            if (mountConnected) {
              n.setConnecting('simulator:test-mount-1');
              n.setConnected();
              n.setParked(mountParked);
              n.setTracking(!mountParked);
            }
            return n;
          }),
          domeStateProvider.overrideWith((ref) {
            final n = DomeStateNotifier(ref);
            if (domeConnected) {
              n.setConnecting('simulator:test-dome-1');
              n.setConnected();
              n.updateShutterStatus(domeShutter);
            }
            return n;
          }),
          coverCalibratorStateProvider.overrideWith((ref) {
            final n = CoverCalibratorStateNotifier(ref);
            if (coverConnected) {
              n.setConnecting('simulator:test-cover-1');
              n.setConnected();
              n.updateCoverStatus(coverStatus);
            }
            return n;
          }),
          if (safeRigBuilder != null)
            safeRigServiceProvider.overrideWith((ref) => safeRigBuilder(ref)),
        ],
      );
    }

    test('pauses sequence and parks an unparked connected mount', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container
          .read(safeRigServiceProvider)
          .safeTheRig(reason: 'test', park: true);

      verify(() => backend.sequencerPause()).called(1);
      verify(() => backend.mountPark('simulator:test-mount-1')).called(1);
      expect(result.sequencePaused, isTrue);
      expect(result.mountParked, isTrue);
      expect(result.hasFailures, isFalse);
      // Mount notifier state should reflect the park.
      expect(container.read(mountStateProvider).isParked, isTrue);
      expect(container.read(mountStateProvider).isTracking, isFalse);
    });

    test('skips park when mount already parked (recorded as already safe)',
        () async {
      final container = makeContainer(mountParked: true);
      addTearDown(container.dispose);

      final result = await container
          .read(safeRigServiceProvider)
          .safeTheRig(reason: 'test', park: true);

      verify(() => backend.sequencerPause()).called(1);
      verifyNever(() => backend.mountPark(any()));
      expect(result.mountParked, isFalse);
      expect(result.mountAlreadySafe, isTrue);
      expect(result.hasFailures, isFalse);
    });

    test('skips park when no mount connected (recorded as already safe)',
        () async {
      final container = makeContainer(mountConnected: false);
      addTearDown(container.dispose);

      final result = await container
          .read(safeRigServiceProvider)
          .safeTheRig(reason: 'test', park: true);

      verifyNever(() => backend.mountPark(any()));
      expect(result.mountAlreadySafe, isTrue);
      expect(result.hasFailures, isFalse);
    });

    test('does not park when park=false', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final result = await container
          .read(safeRigServiceProvider)
          .safeTheRig(reason: 'test', park: false);

      verify(() => backend.sequencerPause()).called(1);
      verifyNever(() => backend.mountPark(any()));
      expect(result.sequencePaused, isTrue);
      expect(result.mountParked, isFalse);
    });

    test('closes dome and cover when requested and open', () async {
      late _RecordingSafeRig recording;
      final container = makeContainer(
        domeConnected: true,
        domeShutter: ShutterStatus.open,
        coverConnected: true,
        coverStatus: CoverStatus.open,
        safeRigBuilder: (ref) => recording = _RecordingSafeRig(ref),
      );
      addTearDown(container.dispose);

      final result = await container.read(safeRigServiceProvider).safeTheRig(
            reason: 'test',
            park: true,
            closeDome: true,
            closeCover: true,
          );

      expect(recording.domeClosedFor, ['simulator:test-dome-1']);
      expect(recording.coverClosedFor, ['simulator:test-cover-1']);
      expect(result.domeClosed, isTrue);
      expect(result.coverClosed, isTrue);
      expect(result.hasFailures, isFalse);
    });

    test('does not re-close an already-closed dome', () async {
      late _RecordingSafeRig recording;
      final container = makeContainer(
        domeConnected: true,
        domeShutter: ShutterStatus.closed,
        safeRigBuilder: (ref) => recording = _RecordingSafeRig(ref),
      );
      addTearDown(container.dispose);

      final result = await container
          .read(safeRigServiceProvider)
          .safeTheRig(reason: 'test', park: true, closeDome: true);

      expect(recording.domeClosedFor, isEmpty);
      expect(result.domeClosed, isFalse);
      expect(result.hasFailures, isFalse);
    });

    test('attempts every step then throws when park fails', () async {
      when(() => backend.mountPark(any()))
          .thenThrow(Exception('park motor fault'));
      late _RecordingSafeRig recording;
      final container = makeContainer(
        domeConnected: true,
        domeShutter: ShutterStatus.open,
        safeRigBuilder: (ref) => recording = _RecordingSafeRig(ref),
      );
      addTearDown(container.dispose);

      await expectLater(
        () => container.read(safeRigServiceProvider).safeTheRig(
              reason: 'test',
              park: true,
              closeDome: true,
            ),
        throwsA(isA<SafeRigException>()),
      );

      // Pause still happened, and the dome was STILL closed despite the park
      // failure — safing must not short-circuit.
      verify(() => backend.sequencerPause()).called(1);
      expect(recording.domeClosedFor, ['simulator:test-dome-1']);
    });

    test('aggregates multiple failures into the thrown exception', () async {
      when(() => backend.sequencerPause())
          .thenThrow(Exception('no sequence running'));
      when(() => backend.mountPark(any()))
          .thenThrow(Exception('park fault'));
      final container = makeContainer(
        safeRigBuilder: (ref) =>
            _RecordingSafeRig(ref, failDome: true),
        domeConnected: true,
        domeShutter: ShutterStatus.open,
      );
      addTearDown(container.dispose);

      try {
        await container.read(safeRigServiceProvider).safeTheRig(
              reason: 'test',
              park: true,
              closeDome: true,
            );
        fail('expected SafeRigException');
      } on SafeRigException catch (e) {
        expect(e.result.failures.keys,
            containsAll(<String>['pause', 'park', 'dome']));
      }
    });

    test('emits a critical (error-level) notification on success', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container
          .read(safeRigServiceProvider)
          .safeTheRig(reason: 'Weather turned unsafe', park: true);

      final notes = container.read(uiNotificationProvider);
      expect(notes, isNotEmpty);
      expect(notes.last.level, UiNotificationLevel.error);
      expect(notes.last.message, contains('Weather turned unsafe'));
    });

    test('notify=false suppresses the notification', () async {
      final container = makeContainer();
      addTearDown(container.dispose);

      await container
          .read(safeRigServiceProvider)
          .safeTheRig(reason: 'test', park: true, notify: false);

      expect(container.read(uiNotificationProvider), isEmpty);
    });
  });
}
