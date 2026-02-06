import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/equipment/equipment_models.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/equipment_provider.dart';
import 'package:nightshade_core/src/services/device_service.dart';

import '../mocks/mock_backend.dart';

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(Ref ref, NightshadeBackend backend) : super(ref) {
    state = backend;
  }
}

void main() {
  late ProviderContainer container;
  late MockBackend mockBackend;
  late StreamController<NightshadeEvent> eventStreamController;

  setUpAll(() {
    registerMocktailFallbackValues();
  });

  setUp(() {
    mockBackend = MockBackend();
    eventStreamController = StreamController<NightshadeEvent>.broadcast();

    when(() => mockBackend.eventStream).thenAnswer((_) => eventStreamController.stream);
    when(() => mockBackend.polarAlignmentEvents).thenAnswer((_) => const Stream.empty());
    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith((ref) => TestBackendNotifier(ref, mockBackend)),
      ],
    );
  });

  tearDown(() {
    eventStreamController.close();
    container.dispose();
  });

  test('connectFilterWheel seeds state from backend status', () async {
    const deviceId = TestFixtures.filterWheelId;
    final filterNames = List<String>.from(TestFixtures.sampleFilterNames);
    final status = FilterWheelStatus(
      connected: true,
      position: 5,
      moving: false,
      filterCount: filterNames.length,
      filterNames: filterNames,
    );

    when(() => mockBackend.discoverDevices(DeviceType.filterWheel))
        .thenAnswer((_) async => const [
              DeviceInfo(
                id: deviceId,
                name: 'Test Filter Wheel',
                deviceType: DeviceType.filterWheel,
                driverType: DriverType.ascom,
                description: 'Test filter wheel',
                driverVersion: '1.0',
              ),
            ]);
    when(() => mockBackend.connectDevice(DeviceType.filterWheel, deviceId))
        .thenAnswer((_) async {});
    when(() => mockBackend.filterWheelGetNames(deviceId))
        .thenAnswer((_) async => filterNames);
    when(() => mockBackend.getFilterWheelStatus(deviceId))
        .thenAnswer((_) async => status);

    final service = container.read(deviceServiceProvider);
    await service.connectFilterWheel(deviceId);

    final state = container.read(filterWheelStateProvider);
    expect(state.connectionState, DeviceConnectionState.connected);
    expect(state.currentPosition, status.position);
    expect(state.filterNames, status.filterNames);
    expect(state.isMoving, status.moving);
  });

  test('setFilterWheelPosition throws when device reports different position', () async {
    const deviceId = TestFixtures.filterWheelId;
    final filterNames = List<String>.from(TestFixtures.sampleFilterNames);

    // Seed connected filter wheel state
    final filterWheelNotifier = container.read(filterWheelStateProvider.notifier);
    filterWheelNotifier.setConnecting(deviceId, 'Test Filter Wheel');
    filterWheelNotifier.setConnected(filterNames: filterNames);
    filterWheelNotifier.updatePosition(0);

    when(() => mockBackend.filterWheelSetPosition(deviceId, 1))
        .thenAnswer((_) async {});
    when(() => mockBackend.getFilterWheelStatus(deviceId))
        .thenAnswer((_) async => FilterWheelStatus(
              connected: true,
              position: 2, // Mismatch
              moving: false,
              filterCount: filterNames.length,
              filterNames: filterNames,
            ));

    final service = container.read(deviceServiceProvider);
    await expectLater(
      service.setFilterWheelPosition(1),
      throwsA(isA<Exception>()),
    );
  });
}
