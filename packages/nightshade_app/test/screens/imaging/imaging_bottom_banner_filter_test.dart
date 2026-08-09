// The Imaging screen's filter strip is the ONLY filter control on the screen,
// and it shipped without an `onFilterSelected` callback: picking Ha moved the
// wheel and highlighted the chip, but `exposureSettingsProvider.filter` stayed
// on whatever it was before, so every reader of that mirror (the Dashboard
// session card among them) described the frame with the wrong filter.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/imaging_bottom_banner.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _ConnectedWheel extends FilterWheelStateNotifier {
  _ConnectedWheel(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const FilterWheelState(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'sim_filterwheel_1',
      deviceName: 'Simulated Filter Wheel',
      currentPosition: 1,
      filterNames: ['L', 'R', 'G', 'B', 'Ha'],
    );
  }
}

/// Accepts the move without a driver round-trip; the strip only needs the
/// command to succeed before it reports the selection.
class _AcceptingDeviceService extends DeviceService {
  _AcceptingDeviceService(super.ref, super.backend);

  int? lastPosition;

  @override
  Future<void> setFilterWheelPosition(int position) async {
    lastPosition = position;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('picking a filter chip records it on the exposure settings',
      (tester) async {
    late _AcceptingDeviceService deviceService;
    final handle = await pumpAppScreen(
      tester,
      Builder(
        builder: (context) => ImagingBottomBanner(
          colors: context.nightshadeColors,
          isLooping: false,
          isSingleCapture: false,
          isSavingCapture: false,
          isStoppingCapture: false,
          onSnapshot: () {},
          onToggleLoop: () {},
        ),
      ),
      size: const Size(1400, 700),
      settle: false,
      extraOverrides: <Override>[
        filterWheelStateProvider.overrideWith(_ConnectedWheel.new),
        deviceServiceProvider.overrideWith((ref) {
          final backend = ref.watch(backendProvider);
          deviceService = _AcceptingDeviceService(ref, backend);
          ref.onDispose(deviceService.dispose);
          return deviceService;
        }),
      ],
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(handle.container.read(exposureSettingsProvider).filter, isNull);

    await tester.tap(find.text('Ha'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(deviceService.lastPosition, 4);
    expect(handle.container.read(exposureSettingsProvider).filter, 'Ha');
  });
}
