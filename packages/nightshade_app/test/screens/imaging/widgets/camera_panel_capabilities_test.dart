// Widget tests for CameraPanel capability-driven controls (component C9).
//
// Scope:
//   1. cooler_slider_uses_capability_range — when CameraCapabilities reports
//      coolerMinTempC/coolerMaxTempC, the target-temperature slider adopts
//      that range instead of the -30..20 default.
//   2. cooler_slider_falls_back_with_null_caps — when capabilities are null,
//      the slider uses the conservative -30..20 default window.
//   3. read_mode_lists_capability_modes — when readoutModes is non-empty the
//      Read Mode dropdown lists exactly those modes (no synthetic
//      High Quality/Fast fallback).
//   4. read_mode_hidden_when_no_modes — when readoutModes is empty the entire
//      Read Mode row is hidden (hide-when-unsupported pattern).
//
// Why we read the live SliderRowInteractive min/max rather than dragging the
// slider: the load-bearing behavior of C9 is the *range wiring*, and asserting
// on the widget's resolved min/max is a direct, non-flaky check of exactly that.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/camera_panel.dart';
import 'package:nightshade_app/screens/imaging/widgets/panel_widgets.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/harness.dart';

const _kDeviceId = 'simulator:camera:0';

/// A [CameraStateNotifier] seeded to a connected device so the panel renders
/// its interactive (non-disabled) controls and resolves capabilities for the
/// matching device id.
class _ConnectedCameraNotifier extends CameraStateNotifier {
  _ConnectedCameraNotifier(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const CameraStateSnapshot(
      connectionState: DeviceConnectionState.connected,
      deviceId: _kDeviceId,
      deviceName: 'Simulated Camera',
      temperature: -5.0,
    );
  }
}

/// Locate the target-temperature [SliderRowInteractive] (the only slider the
/// panel renders) and return it for min/max assertions.
SliderRowInteractive _coolerSlider(WidgetTester tester) {
  return tester.widget<SliderRowInteractive>(
    find.byType(SliderRowInteractive),
  );
}

/// Build the standard override list pinning the camera to connected and the
/// capability provider for [_kDeviceId] to [caps].
List<Override> _overrides(CameraCapabilities? caps) => [
      cameraStateProvider.overrideWith(_ConnectedCameraNotifier.new),
      cameraCapabilitiesProvider(_kDeviceId).overrideWith((ref) async => caps),
    ];

CameraCapabilities _caps({
  double? coolerMin,
  double? coolerMax,
  List<String> readoutModes = const [],
}) {
  return CameraCapabilities(
    maxWidth: 1920,
    maxHeight: 1080,
    bitDepth: 16,
    canSetCcdTemperature: true,
    canSetCooler: true,
    canGetCoolerPower: true,
    coolerMinTempC: coolerMin,
    coolerMaxTempC: coolerMax,
    readoutModes: readoutModes,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  CameraCapabilities? caps,
) async {
  await pumpAppScreen(
    tester,
    const CameraPanel(colors: NightshadeColors.dark),
    extraOverrides: _overrides(caps),
    settle: false,
  );
  // Drain the capability FutureProvider override into the tree.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'cooler_slider_uses_capability_range: slider adopts coolerMin/Max from caps',
      (tester) async {
    await _pumpPanel(
      tester,
      _caps(coolerMin: -20, coolerMax: 40, readoutModes: const ['A', 'B']),
    );

    final slider = _coolerSlider(tester);
    expect(slider.min, -20,
        reason: 'Slider min must come from CameraCapabilities.coolerMinTempC.');
    expect(slider.max, 40,
        reason: 'Slider max must come from CameraCapabilities.coolerMaxTempC.');
  });

  testWidgets(
      'cooler_slider_falls_back_with_null_caps: slider is -30..20 when caps null',
      (tester) async {
    await _pumpPanel(tester, null);

    final slider = _coolerSlider(tester);
    expect(slider.min, -30,
        reason: 'Null capabilities must fall back to the -30°C default min.');
    expect(slider.max, 20,
        reason: 'Null capabilities must fall back to the 20°C default max.');
  });

  testWidgets(
      'cooler_slider_falls_back_on_inverted_range: guards against bad driver data',
      (tester) async {
    // min >= max is nonsensical driver data; the panel must ignore it and use
    // the conservative default window rather than feeding the Slider an
    // invalid range (which would assert).
    await _pumpPanel(tester, _caps(coolerMin: 50, coolerMax: 10));

    final slider = _coolerSlider(tester);
    expect(slider.min, -30);
    expect(slider.max, 20);
  });

  testWidgets(
      'read_mode_lists_capability_modes: dropdown lists exactly the cap modes',
      (tester) async {
    await _pumpPanel(
      tester,
      _caps(readoutModes: const ['Mode A', 'Mode B']),
    );

    // The Read Mode row renders a DropdownRow whose items are the cap modes.
    final readModeRow = tester.widgetList<DropdownRow>(
      find.byType(DropdownRow),
    );
    final dropdowns = readModeRow.where((d) => d.label == 'Read Mode').toList();
    expect(dropdowns, hasLength(1),
        reason: 'Read Mode row must be present when modes are reported.');
    expect(dropdowns.single.items, ['Mode A', 'Mode B'],
        reason:
            'Dropdown items must mirror CameraCapabilities.readoutModes with no '
            'synthetic High Quality/Fast fallback.');
    // Default selection resolves to index 0 (no explicit mode chosen yet).
    expect(dropdowns.single.value, 'Mode A');
  });

  testWidgets(
      'read_mode_hidden_when_no_modes: Read Mode row absent for empty modes',
      (tester) async {
    await _pumpPanel(
      tester,
      _caps(readoutModes: const []),
    );

    final readModeDropdowns = tester
        .widgetList<DropdownRow>(find.byType(DropdownRow))
        .where((d) => d.label == 'Read Mode');
    expect(readModeDropdowns, isEmpty,
        reason:
            'Read Mode row must be hidden entirely when the camera reports no '
            'readout modes (hide-when-unsupported pattern).');
  });
}
