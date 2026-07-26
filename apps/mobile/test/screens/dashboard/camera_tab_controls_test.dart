import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_mobile/screens/dashboard/tabs/camera_tab.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('capture is single-flight and retires with its imaging host', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    late _SwappableBackendNotifier backendNotifier;
    late _ControlledImagingService imaging;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith((ref) {
            backendNotifier = _SwappableBackendNotifier(
              ref,
              DisconnectedBackend(),
            );
            return backendNotifier;
          }),
          imagingServiceProvider.overrideWith((ref) {
            imaging = _ControlledImagingService(ref);
            ref.onDispose(imaging.retire);
            return imaging;
          }),
          cameraStateProvider.overrideWith(
            (ref) => _CameraNotifier(
              ref,
              const CameraStateSnapshot(
                connectionState: DeviceConnectionState.connected,
                deviceId: 'camera-1',
                deviceName: 'Test Camera',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildCameraExposureControlsForTesting(
                state: const CameraStateSnapshot(
                  connectionState: DeviceConnectionState.connected,
                  deviceId: 'camera-1',
                  deviceName: 'Test Camera',
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final expose = find.text('Expose');
    await tester.ensureVisible(expose);
    await tester.tap(expose);
    await tester.tap(expose);
    await tester.pump();
    expect(imaging.captureCalls, 1);
    expect(find.text('Capturing…'), findsOneWidget);

    backendNotifier.switchTo(DisconnectedBackend());
    await tester.pump();
    expect(find.text('Expose'), findsOneWidget);

    await tester.tap(find.text('Expose'));
    await tester.pump();
    expect(imaging.captureCalls, 2);
    expect(find.text('Capturing…'), findsOneWidget);

    imaging.first.completeError(StateError('old host failed'));
    await tester.pump();
    expect(find.textContaining('old host failed'), findsNothing);
    expect(find.text('Capturing…'), findsOneWidget);

    imaging.second.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.text('Expose'), findsOneWidget);
  });

  testWidgets('resume cooling cancels warm-up and restores configured target', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = _MockDeviceService();
    late _CameraNotifier camera;
    when(() => service.cancelWarmCamera()).thenAnswer((_) {
      camera.setWarming(false);
    });
    when(
      () => service.setCameraCooling(
        enabled: true,
        targetTemp: any(named: 'targetTemp'),
      ),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceServiceProvider.overrideWithValue(service),
          cameraStateProvider.overrideWith((ref) {
            camera = _CameraNotifier(
              ref,
              const CameraStateSnapshot(
                connectionState: DeviceConnectionState.connected,
                deviceId: 'camera-1',
                deviceName: 'Test Camera',
                temperature: -5,
                targetTemp: 4,
                isCooling: true,
                isWarming: true,
              ),
            );
            return camera;
          }),
          coolingSettingsProvider.overrideWith(
            (ref) => const CoolingSettings(targetTemp: -15, enabled: true),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: const Scaffold(body: CameraTab()),
        ),
      ),
    );

    final resume = find.text('Resume cooling');
    await tester.ensureVisible(resume);
    await tester.tap(resume);
    await tester.pumpAndSettle();

    verify(() => service.cancelWarmCamera()).called(1);
    verify(
      () => service.setCameraCooling(enabled: true, targetTemp: -15),
    ).called(1);
    expect(camera.state.isWarming, isFalse);
    expect(camera.state.isCooling, isTrue);
    expect(camera.state.targetTemp, -15);
  });

  testWidgets('filter selection is single-flight across rapid taps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = _MockDeviceService();
    final moveGate = Completer<void>();
    when(
      () => service.setFilterWheelPosition(any()),
    ).thenAnswer((_) => moveGate.future);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceServiceProvider.overrideWithValue(service),
          activeEquipmentProfileProvider.overrideWithValue(null),
          cameraStateProvider.overrideWith(
            (ref) => _CameraNotifier(
              ref,
              const CameraStateSnapshot(
                connectionState: DeviceConnectionState.connected,
                deviceId: 'camera-1',
                deviceName: 'Test Camera',
              ),
            ),
          ),
          filterWheelStateProvider.overrideWith(
            (ref) => _FilterNotifier(
              ref,
              const FilterWheelState(
                connectionState: DeviceConnectionState.connected,
                deviceId: 'filter-1',
                deviceName: 'Test Wheel',
                currentPosition: 0,
                filterNames: ['L', 'Ha'],
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: const Scaffold(body: CameraTab()),
        ),
      ),
    );

    final ha = find.text('Ha');
    await tester.ensureVisible(ha);
    await tester.tap(ha);
    await tester.pump();
    await tester.tap(ha);
    await tester.pump();

    verify(() => service.setFilterWheelPosition(1)).called(1);
    moveGate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('old cooling failure cannot block or report on a new host', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final service = _MockDeviceService();
    final firstWarm = Completer<void>();
    final secondWarm = Completer<void>();
    var warmCalls = 0;
    when(
      () => service.warmCamera(),
    ).thenAnswer((_) => (warmCalls++ == 0 ? firstWarm : secondWarm).future);
    late _SwappableBackendNotifier backendNotifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith((ref) {
            backendNotifier = _SwappableBackendNotifier(
              ref,
              DisconnectedBackend(),
            );
            return backendNotifier;
          }),
          deviceServiceProvider.overrideWithValue(service),
          cameraStateProvider.overrideWith(
            (ref) => _CameraNotifier(
              ref,
              const CameraStateSnapshot(
                connectionState: DeviceConnectionState.connected,
                deviceId: 'camera-1',
                deviceName: 'Test Camera',
                isCooling: true,
                targetTemp: -10,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: Scaffold(
            body: SingleChildScrollView(
              child: buildCameraCoolingControlsForTesting(
                state: const CameraStateSnapshot(
                  connectionState: DeviceConnectionState.connected,
                  deviceId: 'camera-1',
                  deviceName: 'Test Camera',
                  isCooling: true,
                  targetTemp: -10,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.text('Warm camera'));
    await tester.tap(find.text('Warm camera'));
    await tester.pump();
    expect(warmCalls, 1);
    expect(find.text('Updating cooler…'), findsOneWidget);

    backendNotifier.switchTo(DisconnectedBackend());
    await tester.pump();
    expect(find.text('Warm camera'), findsOneWidget);

    await tester.tap(find.text('Warm camera'));
    await tester.pump();
    expect(warmCalls, 2);
    expect(find.text('Updating cooler…'), findsOneWidget);

    firstWarm.completeError(StateError('old cooler failed'));
    await tester.pump();
    expect(find.textContaining('old cooler failed'), findsNothing);
    expect(find.text('Updating cooler…'), findsOneWidget);

    secondWarm.complete();
    await tester.pump();
    expect(find.text('Warm camera'), findsOneWidget);
  });
}

class _MockDeviceService extends Mock implements DeviceService {}

class _ControlledImagingService extends ImagingService {
  _ControlledImagingService(super.ref);

  final first = Completer<CapturedImageData?>();
  final second = Completer<CapturedImageData?>();
  int captureCalls = 0;

  @override
  Future<CapturedImageData?> captureImage({
    required ExposureSettings settings,
    String? targetName,
    int? frameNumber,
    String? producingNodeId,
    String? producingRunId,
  }) => (captureCalls++ == 0 ? first : second).future;
}

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }

  void switchTo(NightshadeBackend backend) => state = backend;
}

class _CameraNotifier extends CameraStateNotifier {
  _CameraNotifier(super.ref, CameraStateSnapshot initial) {
    state = initial;
  }
}

class _FilterNotifier extends FilterWheelStateNotifier {
  _FilterNotifier(super.ref, FilterWheelState initial) {
    state = initial;
  }
}
