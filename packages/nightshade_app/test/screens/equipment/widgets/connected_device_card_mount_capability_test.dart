import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/equipment/widgets/connected_device_card.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/harness.dart';

class _MountNotifier extends MountStateNotifier {
  _MountNotifier(super.ref, this.initial) {
    state = initial;
  }

  final MountState initial;
}

NightshadeButton button(WidgetTester tester, String label) =>
    tester.widget<NightshadeButton>(
      find.widgetWithText(NightshadeButton, label),
    );

Future<HarnessHandle> pumpMount(
  WidgetTester tester, {
  required MountState state,
  required MountCapabilities capabilities,
  SequenceExecutionState execution = SequenceExecutionState.idle,
}) {
  final backend = mockBackend();
  when(() => backend.getMountCapabilities('mount-1'))
      .thenAnswer((_) async => capabilities);
  return pumpAppScreen(
    tester,
    const ConnectedDeviceCard(type: ConnectedDeviceType.mount),
    backend: backend,
    extraOverrides: [
      mountStateProvider.overrideWith((ref) => _MountNotifier(ref, state)),
      sequenceExecutionStateProvider.overrideWith((ref) => execution),
    ],
  );
}

void main() {
  const connected = MountState(
    connectionState: DeviceConnectionState.connected,
    deviceId: 'mount-1',
    isTracking: true,
    isParked: false,
    ra: 7.5,
    dec: -20,
  );

  testWidgets('mount actions are disabled when capabilities are unsupported',
      (tester) async {
    await pumpMount(
      tester,
      state: connected,
      capabilities: const MountCapabilities(),
    );

    for (final label in ['Park', 'Stop Tracking', 'Home', 'Flip']) {
      expect(button(tester, label).onPressed, isNull, reason: label);
    }
  });

  testWidgets('supported mount actions are enabled when the rig is settled',
      (tester) async {
    await pumpMount(
      tester,
      state: connected,
      capabilities: const MountCapabilities(
        canPark: true,
        canSetTracking: true,
        canFindHome: true,
        canSlew: true,
        canGetSideOfPier: true,
        isEquatorial: true,
      ),
    );

    for (final label in ['Park', 'Stop Tracking', 'Home', 'Flip']) {
      expect(button(tester, label).onPressed, isNotNull, reason: label);
    }
  });

  testWidgets('manual Flip is disabled while a sequence owns the mount',
      (tester) async {
    await pumpMount(
      tester,
      state: connected,
      execution: SequenceExecutionState.running,
      capabilities: const MountCapabilities(
        canSlew: true,
        canGetSideOfPier: true,
        isEquatorial: true,
      ),
    );

    expect(button(tester, 'Flip').onPressed, isNull);
  });

  testWidgets('parked mount requires explicit unpark capability',
      (tester) async {
    await pumpMount(
      tester,
      state: connected.copyWith(isParked: true),
      capabilities: const MountCapabilities(canPark: true, canUnpark: false),
    );
    expect(button(tester, 'Unpark').onPressed, isNull);

    await pumpMount(
      tester,
      state: connected.copyWith(isParked: true),
      capabilities: const MountCapabilities(canPark: true, canUnpark: true),
    );
    expect(button(tester, 'Unpark').onPressed, isNotNull);
  });
}
