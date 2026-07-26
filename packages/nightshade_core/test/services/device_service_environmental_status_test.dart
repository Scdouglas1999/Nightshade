import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/equipment/equipment_models.dart'
    show DeviceConnectionState;
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/equipment_provider.dart';
import 'package:nightshade_core/src/services/device_service.dart';

class _EnvironmentalBackend extends Mock
    implements NightshadeBackend, EnvironmentalStatusBackend {}

class _BackendNotifier extends BackendNotifier {
  _BackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

void main() {
  late _EnvironmentalBackend backend;
  late ProviderContainer container;
  late StreamController<NightshadeEvent> events;

  setUp(() {
    backend = _EnvironmentalBackend();
    events = StreamController<NightshadeEvent>.broadcast();
    when(() => backend.eventStream).thenAnswer((_) => events.stream);
    when(
      () => backend.polarAlignmentEvents,
    ).thenAnswer((_) => const Stream.empty());
    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith((ref) => _BackendNotifier(ref, backend)),
      ],
    );
    container.read(deviceServiceProvider);
  });

  tearDown(() async {
    container.dispose();
    await events.close();
  });

  test(
    'weather connection publishes driver telemetry before connected',
    () async {
      const deviceId = 'simulator:weather-1';
      when(
        () => backend.connectDevice(DeviceType.weather, deviceId),
      ).thenAnswer((_) async {});
      when(() => backend.getHardwareWeatherConditions(deviceId)).thenAnswer(
        (_) async => const HardwareWeatherConditions(
          temperature: 7.5,
          humidity: 42,
          pressure: 1012.4,
          cloudCover: 8,
          dewPoint: -3,
          windSpeed: 1.25,
          windDirection: 210,
          skyQuality: 21.4,
          skyTemperature: -17,
          rainRate: 0,
        ),
      );

      await container.read(deviceServiceProvider).connectWeather(deviceId);

      final state = container.read(weatherStateProvider);
      expect(state.connectionState, DeviceConnectionState.connected);
      expect(state.deviceId, deviceId);
      expect(state.temperature, 7.5);
      expect(state.humidity, 42);
      expect(state.skyTemperature, -17);
      expect(state.rainRate, 0);
    },
  );

  test(
    'safety connection fails closed and disconnects when status read fails',
    () async {
      const deviceId = 'simulator:safety-1';
      when(
        () => backend.connectDevice(DeviceType.safetyMonitor, deviceId),
      ).thenAnswer((_) async {});
      when(
        () => backend.getHardwareSafetyStatus(deviceId),
      ).thenThrow(StateError('safety sensor unavailable'));
      when(
        () => backend.disconnectDevice(DeviceType.safetyMonitor, deviceId),
      ).thenAnswer((_) async {});

      await expectLater(
        container.read(deviceServiceProvider).connectSafetyMonitor(deviceId),
        throwsA(isA<StateError>()),
      );

      verify(
        () => backend.disconnectDevice(DeviceType.safetyMonitor, deviceId),
      ).called(1);
      final state = container.read(safetyMonitorStateProvider);
      expect(state.connectionState, DeviceConnectionState.error);
      expect(state.isSafe, isFalse);
      expect(state.deviceId, deviceId);
      expect(state.lastError?.message, contains('safety sensor unavailable'));
    },
  );
}
