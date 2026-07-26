import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/capture_settings_card.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _ConnectedCameraNotifier extends CameraStateNotifier {
  _ConnectedCameraNotifier(super.ref) {
    state = const CameraStateSnapshot(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'camera-1',
      deviceName: 'Test Camera',
    );
  }
}

class _ControlledImagingService extends ImagingService {
  _ControlledImagingService(super.ref);

  final captureResult = Completer<CapturedImageData?>();
  int captureCalls = 0;
  bool cancelled = false;

  @override
  Future<CapturedImageData?> captureImage({
    required ExposureSettings settings,
    String? targetName,
    int? frameNumber,
    String? producingNodeId,
    String? producingRunId,
  }) {
    captureCalls++;
    return captureResult.future;
  }

  @override
  void cancelExposure() {
    cancelled = true;
  }
}

final _imagingHostProvider = StateProvider<int>((ref) => 0);

class _ConnectedFilterWheelNotifier extends FilterWheelStateNotifier {
  _ConnectedFilterWheelNotifier(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const FilterWheelState(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'filter-wheel-1',
      deviceName: 'Test Wheel',
      currentPosition: 0,
      filterNames: ['L', 'R'],
    );
  }
}

class _DelayedFilterDeviceService extends DeviceService {
  _DelayedFilterDeviceService(super.ref, super.backend);

  final move = Completer<void>();

  @override
  Future<void> setFilterWheelPosition(int position) => move.future;
}

Future<void> _selectFilter(
  WidgetTester tester, {
  required String current,
  required String next,
}) async {
  final dropdown = find.ancestor(
    of: find.text(current),
    matching: find.byType(DropdownButton<String>),
  );
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(next).last);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders 0-100 exposure progress as a 0-1 indicator',
      (tester) async {
    final handle = await pumpAppScreen(
      tester,
      const CaptureSettingsCard(colors: NightshadeColors.dark),
    );

    handle.container
        .read(exposureProgressProvider.notifier)
        .updateProgress(5, 5, 50);
    await tester.pump();

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 0.5);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('5000%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stop Loop remains enabled during the in-flight exposure',
      (tester) async {
    late _ControlledImagingService imagingService;
    await pumpAppScreen(
      tester,
      const CaptureSettingsCard(colors: NightshadeColors.dark),
      extraOverrides: [
        cameraStateProvider.overrideWith(_ConnectedCameraNotifier.new),
        imagingServiceProvider.overrideWith((ref) {
          return imagingService = _ControlledImagingService(ref);
        }),
      ],
    );

    await tester.tap(find.text('Loop'));
    await tester.pump();

    expect(imagingService.captureCalls, 1);
    final stopButton = tester.widget<NightshadeButton>(
      find.widgetWithText(NightshadeButton, 'Stop Loop'),
    );
    expect(stopButton.onPressed, isNotNull);

    await tester.tap(find.text('Stop Loop'));
    await tester.pump();
    expect(find.text('Loop'), findsOneWidget);
    expect(imagingService.cancelled, isFalse,
        reason: 'Stopping a loop lets the current frame finish; Abort is the '
            'separate immediate-cancel control.');

    imagingService.captureResult.complete(null);
    await tester.pump();
    expect(imagingService.captureCalls, 1);
  });

  testWidgets('host switch stops loop and discards the old capture completion',
      (tester) async {
    late _ControlledImagingService serviceA;
    late _ControlledImagingService serviceB;
    final handle = await pumpAppScreen(
      tester,
      const CaptureSettingsCard(colors: NightshadeColors.dark),
      extraOverrides: [
        cameraStateProvider.overrideWith(_ConnectedCameraNotifier.new),
        _imagingHostProvider.overrideWith((ref) => 0),
        imagingServiceProvider.overrideWith((ref) {
          final host = ref.watch(_imagingHostProvider);
          final service = _ControlledImagingService(ref);
          if (host == 0) {
            serviceA = service;
          } else {
            serviceB = service;
          }
          return service;
        }),
      ],
    );

    await tester.tap(find.text('Loop'));
    await tester.pump();
    expect(serviceA.captureCalls, 1);
    expect(find.text('Stop Loop'), findsOneWidget);

    handle.container.read(_imagingHostProvider.notifier).state = 1;
    await tester.pump();
    expect(find.text('Loop'), findsOneWidget);

    serviceA.captureResult.complete(null);
    await tester.pump();
    expect(serviceB.captureCalls, 0);
    expect(find.text('Loop'), findsOneWidget);

    await tester.tap(find.text('Loop'));
    await tester.pump();
    expect(serviceB.captureCalls, 1);
    serviceB.captureResult.complete(null);
    await tester.pump();
  });

  testWidgets('completed filter move survives card navigation', (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    late _DelayedFilterDeviceService deviceService;
    final handle = await pumpAppScreen(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (context, show, _) => show
            ? const CaptureSettingsCard(colors: NightshadeColors.dark)
            : const SizedBox(),
      ),
      extraOverrides: <Override>[
        filterWheelStateProvider.overrideWith(
          _ConnectedFilterWheelNotifier.new,
        ),
        deviceServiceProvider.overrideWith((ref) {
          final backend = ref.watch(backendProvider);
          deviceService = _DelayedFilterDeviceService(ref, backend);
          ref.onDispose(deviceService.dispose);
          return deviceService;
        }),
      ],
    );

    await _selectFilter(tester, current: 'L', next: 'R');
    visible.value = false;
    await tester.pump();
    deviceService.move.complete();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(handle.container.read(exposureSettingsProvider).filter, 'R');
    expect(handle.container.read(exposureSettingsUserDirtyProvider), isTrue);
  });
}
