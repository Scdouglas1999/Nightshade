// Regression: the shell's device count must count every device the app can
// connect.
//
// Observed live with six simulated devices attached (camera, mount, focuser,
// filter wheel, dome, weather station): the global status bar read "My
// Equipment / 4 connected" while the Equipment header read "6 connected · 6
// unsaved" in the same frame. The chip only tallied the six slots the profile
// editor lists first, so the dome and the weather station were invisible to the
// one readout an operator glances at before starting an unattended run.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/equipment_status_indicator.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../harness/pump_app_screen.dart';

const _connected = DeviceConnectionState.connected;

class _FakeCameraNotifier extends StateNotifier<CameraStateSnapshot>
    implements CameraStateNotifier {
  _FakeCameraNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDomeNotifier extends StateNotifier<DomeState>
    implements DomeStateNotifier {
  _FakeDomeNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWeatherNotifier extends StateNotifier<WeatherState>
    implements WeatherStateNotifier {
  _FakeWeatherNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _profile = EquipmentProfileModel(
  id: 1,
  name: 'My Equipment',
  focalLength: 600,
  aperture: 100,
);

Future<void> _pumpIndicator(WidgetTester tester) async {
  await pumpAppScreen(
    tester,
    const EquipmentStatusIndicator(),
    settle: false,
    extraOverrides: [
      activeEquipmentProfileProvider.overrideWithValue(_profile),
      cameraStateProvider.overrideWith(
        (ref) => _FakeCameraNotifier(
          const CameraStateSnapshot(
            connectionState: _connected,
            deviceId: 'sim:camera:1',
            deviceName: 'Simulated Camera',
          ),
        ),
      ),
      domeStateProvider.overrideWith(
        (ref) => _FakeDomeNotifier(
          const DomeState(
            connectionState: _connected,
            deviceId: 'sim:dome:1',
            deviceName: 'Simulated Dome',
          ),
        ),
      ),
      weatherStateProvider.overrideWith(
        (ref) => _FakeWeatherNotifier(
          const WeatherState(
            connectionState: _connected,
            deviceId: 'sim:weather:1',
            deviceName: 'Simulated Weather Station',
          ),
        ),
      ),
    ],
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('the chip counts auxiliary devices, not just the first six slots',
      (tester) async {
    await _pumpIndicator(tester);

    expect(
      find.text('3 connected'),
      findsOneWidget,
      reason: 'camera + dome + weather station are all attached',
    );
  });

  testWidgets('the dropdown accounts for every device the chip counted',
      (tester) async {
    await _pumpIndicator(tester);

    await tester.tap(find.byType(EquipmentStatusIndicator));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Simulated Camera'), findsOneWidget);
    expect(find.text('Simulated Dome'), findsOneWidget);
    expect(find.text('Simulated Weather Station'), findsOneWidget);
  });
}
