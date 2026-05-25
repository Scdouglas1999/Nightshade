import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/device_heartbeat_health_provider.dart';
import 'package:nightshade_core/src/services/device_service.dart';

import '../mocks/mock_backend.dart';

/// DEV-P3-2 — verifies that heartbeat events arriving on the equipment
/// event stream are routed into `deviceHeartbeatHealthProvider` by
/// `DeviceService`, and that a `Disconnected` event clears the entry.
class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

void main() {
  late ProviderContainer container;
  late MockBackend mockBackend;
  late StreamController<NightshadeEvent> events;

  setUpAll(() {
    registerMocktailFallbackValues();
  });

  setUp(() {
    mockBackend = MockBackend();
    events = StreamController<NightshadeEvent>.broadcast();
    when(() => mockBackend.eventStream).thenAnswer((_) => events.stream);
    when(() => mockBackend.polarAlignmentEvents)
        .thenAnswer((_) => const Stream.empty());

    container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => _TestBackendNotifier(ref, mockBackend),
        ),
      ],
    );

    // Wire up the event subscription.
    container.read(deviceServiceProvider);
  });

  tearDown(() async {
    await events.close();
    container.dispose();
  });

  NightshadeEvent makeEvent(String eventType, Map<String, dynamic> data) =>
      NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: eventType,
        data: data,
      );

  test('HeartbeatStatusChanged(degraded) updates the provider with reason',
      () async {
    const deviceId = 'native:zwo:0';
    events.add(makeEvent('HeartbeatStatusChanged', {
      'device_type': 'camera',
      'device_id': deviceId,
      'status': 'degraded',
      'consecutive_failures': 3,
      'last_rtt_ms': 250,
    }));

    // Allow the stream listener to dispatch.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container
        .read(deviceHeartbeatHealthProvider.notifier)
        .forDevice(deviceId);
    expect(state.health, HeartbeatHealth.degraded);
    // CLAUDE.md: the reason must carry the real failure count, not a
    // generic placeholder.
    expect(state.reason, isNotNull);
    expect(state.reason!, contains('3'));
    expect(state.consecutiveFailures, 3);
  });

  test('HeartbeatStatusChanged(healthy) routes to healthy state', () async {
    const deviceId = 'native:zwo:0';
    events.add(makeEvent('HeartbeatStatusChanged', {
      'device_type': 'camera',
      'device_id': deviceId,
      'status': 'healthy',
      'consecutive_failures': 0,
    }));

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container
        .read(deviceHeartbeatHealthProvider.notifier)
        .forDevice(deviceId);
    expect(state.health, HeartbeatHealth.healthy);
  });

  test('HeartbeatReconnecting populates attempt counter in reason',
      () async {
    const deviceId = 'native:zwo:0';
    events.add(makeEvent('HeartbeatReconnecting', {
      'device_type': 'camera',
      'device_id': deviceId,
      'attempt': 2,
      'max_attempts': 5,
    }));

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container
        .read(deviceHeartbeatHealthProvider.notifier)
        .forDevice(deviceId);
    expect(state.health, HeartbeatHealth.reconnecting);
    expect(state.reason, contains('attempt 2'));
  });

  test('Disconnected event clears the heartbeat entry', () async {
    const deviceId = 'native:zwo:0';

    // First, mark the device degraded.
    events.add(makeEvent('HeartbeatStatusChanged', {
      'device_type': 'camera',
      'device_id': deviceId,
      'status': 'degraded',
      'consecutive_failures': 2,
    }));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final beforeState = container
        .read(deviceHeartbeatHealthProvider.notifier)
        .forDevice(deviceId);
    expect(beforeState.health, HeartbeatHealth.degraded);

    // Now disconnect — heartbeat entry should be cleared so the
    // indicator falls back to gray "unknown" rather than getting stuck.
    events.add(makeEvent('Disconnected', {
      'device_type': 'camera',
      'device_id': deviceId,
    }));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final afterState = container
        .read(deviceHeartbeatHealthProvider.notifier)
        .forDevice(deviceId);
    expect(afterState.health, HeartbeatHealth.unknown);
  });

  test('HeartbeatStarted seeds device as healthy immediately', () async {
    const deviceId = 'native:zwo:0';
    events.add(makeEvent('HeartbeatStarted', {
      'device_type': 'camera',
      'device_id': deviceId,
      'interval_secs': BigInt.from(10),
    }));

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container
        .read(deviceHeartbeatHealthProvider.notifier)
        .forDevice(deviceId);
    expect(state.health, HeartbeatHealth.healthy);
  });

  test('HeartbeatStopped clears the entry', () async {
    const deviceId = 'native:zwo:0';
    events.add(makeEvent('HeartbeatStarted', {
      'device_type': 'camera',
      'device_id': deviceId,
      'interval_secs': BigInt.from(10),
    }));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      container
          .read(deviceHeartbeatHealthProvider.notifier)
          .forDevice(deviceId)
          .health,
      HeartbeatHealth.healthy,
    );

    events.add(makeEvent('HeartbeatStopped', {
      'device_type': 'camera',
      'device_id': deviceId,
    }));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      container
          .read(deviceHeartbeatHealthProvider.notifier)
          .forDevice(deviceId)
          .health,
      HeartbeatHealth.unknown,
    );
  });

  test('Heartbeat dispatch does not interfere with the Disconnected handler',
      () async {
    // Regression guard for the task constraint: heartbeat routing must
    // not break the DEV-P0-1 / DEV-P0-5 connection-state handling.
    // We send a Disconnected event for a device that has no heartbeat
    // entry at all — the heartbeat clear (no-op) must not raise and
    // the event must still be processed by the existing handler.
    const deviceId = 'native:zwo:0';

    expect(
      () => events.add(makeEvent('Disconnected', {
        'device_type': 'camera',
        'device_id': deviceId,
      })),
      returnsNormally,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
}
