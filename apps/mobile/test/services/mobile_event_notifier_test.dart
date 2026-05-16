import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_mobile/services/mobile_event_notifier.dart';
import 'package:nightshade_mobile/services/mobile_preferences.dart';
import 'package:nightshade_mobile/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A test double that records every notify call instead of touching the
/// flutter_local_notifications plugin (which has no host-side
/// implementation in unit tests).
class _RecordingNotificationService implements MobileNotificationSink {
  final List<NotifyCall> calls = <NotifyCall>[];

  @override
  Future<void> notifySequenceComplete(
      String targetName, int imageCount) async {
    calls.add(NotifyCall('sequenceComplete', {
      'target': targetName,
      'count': imageCount,
    }));
  }

  @override
  Future<void> notifySequenceFailed(
      String targetName, String errorMessage) async {
    calls.add(NotifyCall('sequenceFailed', {
      'target': targetName,
      'error': errorMessage,
    }));
  }

  @override
  Future<void> notifySafety({
    required String title,
    required String body,
    String? eventType,
  }) async {
    calls.add(NotifyCall('safety', {
      'title': title,
      'body': body,
      if (eventType != null) 'eventType': eventType,
    }));
  }

  @override
  Future<void> notifyMountParked(String reason) async {
    calls.add(NotifyCall('mountParked', {'reason': reason}));
  }

  @override
  Future<void> notifyGuidingLost(String reason) async {
    calls.add(NotifyCall('guidingLost', {'reason': reason}));
  }

  @override
  Future<void> notifyExposureFailed(String errorMessage) async {
    calls.add(NotifyCall('exposureFailed', {'error': errorMessage}));
  }

  @override
  Future<void> notifyAutofocusFailed() async {
    calls.add(const NotifyCall('autofocusFailed', <String, Object?>{}));
  }

  @override
  Future<void> notifyEquipmentDisconnected(
      String deviceType, String deviceId) async {
    calls.add(NotifyCall('equipmentDisconnected', {
      'deviceType': deviceType,
      'deviceId': deviceId,
    }));
  }

  @override
  Future<void> notifyTargetCompleted(String targetName) async {
    calls.add(NotifyCall('targetCompleted', {'targetName': targetName}));
  }

  @override
  Future<void> notifyLowDiskSpace(double remainingGB) async {
    calls.add(NotifyCall('lowDiskSpace', {'gb': remainingGB}));
  }

  @override
  Future<void> notifyLowBattery(int percentage) async {
    calls.add(NotifyCall('lowBattery', {'pct': percentage}));
  }

  @override
  Future<void> notifyMeridianFlip(String targetName, DateTime flipTime) async {
    calls.add(NotifyCall('meridianFlip', {'target': targetName}));
  }

  @override
  Future<void> notifyPush(Map<String, dynamic> data) async {
    calls.add(NotifyCall('push', Map<String, Object?>.from(data)));
  }
}

class NotifyCall {
  final String kind;
  final Map<String, Object?> data;
  const NotifyCall(this.kind, this.data);

  @override
  String toString() => 'NotifyCall($kind, $data)';
}

NightshadeEvent _ev(
  EventCategory category,
  String type, {
  Map<String, dynamic>? data,
  EventSeverity severity = EventSeverity.warning,
}) {
  return NightshadeEvent(
    timestamp: DateTime.now().millisecondsSinceEpoch,
    severity: severity,
    category: category,
    eventType: type,
    data: data ?? const <String, dynamic>{},
  );
}

void main() {
  late StreamController<NightshadeEvent> eventStream;
  late _RecordingNotificationService notifications;
  late MobileEventNotifier notifier;
  late MobilePreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final raw = await SharedPreferences.getInstance();
    prefs = MobilePreferences(raw);
    eventStream = StreamController<NightshadeEvent>.broadcast();
    notifications = _RecordingNotificationService();
    notifier = MobileEventNotifier(
      eventStream: eventStream.stream,
      preferences: prefs,
      notificationService: notifications,
    );
    notifier.start();
  });

  tearDown(() async {
    await notifier.stop();
    await eventStream.close();
  });

  Future<void> emit(NightshadeEvent event) async {
    eventStream.add(event);
    // The subscriber handles asynchronously; let the broadcast deliver and
    // the async _handle complete before assertions.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('Safety category', () {
    test('WeatherUnsafe -> safety notification with reason', () async {
      await emit(_ev(
        EventCategory.safety,
        'WeatherUnsafe',
        data: {'reason': 'High wind 45 km/h'},
        severity: EventSeverity.critical,
      ));
      expect(notifications.calls, hasLength(1));
      expect(notifications.calls.single.kind, 'safety');
      expect(notifications.calls.single.data['title'], 'Weather Unsafe');
      expect(notifications.calls.single.data['body'],
          contains('High wind 45 km/h'));
    });

    test('EmergencyStop -> safety notification', () async {
      await emit(_ev(
        EventCategory.safety,
        'EmergencyStop',
        data: {'reason': 'Operator panic stop'},
        severity: EventSeverity.critical,
      ));
      expect(notifications.calls.single.kind, 'safety');
      expect(notifications.calls.single.data['body'], 'Operator panic stop');
    });

    test('ParkInitiated -> mount parked notification', () async {
      await emit(_ev(
        EventCategory.safety,
        'ParkInitiated',
        data: {'reason': 'Weather safety triggered'},
      ));
      expect(notifications.calls.single.kind, 'mountParked');
      expect(notifications.calls.single.data['reason'],
          'Weather safety triggered');
    });

    test('WeatherSafe -> no notification (recovery is silent)', () async {
      await emit(_ev(EventCategory.safety, 'WeatherSafe'));
      expect(notifications.calls, isEmpty);
    });

    test('respects notifySafety mute toggle', () async {
      await prefs.setNotifySafety(false);
      await emit(_ev(EventCategory.safety, 'WeatherUnsafe',
          data: {'reason': 'rain'}));
      expect(notifications.calls, isEmpty);
    });

    test('debounces repeat WeatherUnsafe within window', () async {
      await emit(_ev(EventCategory.safety, 'WeatherUnsafe',
          data: {'reason': 'rain'}));
      await emit(_ev(EventCategory.safety, 'WeatherUnsafe',
          data: {'reason': 'rain'}));
      expect(notifications.calls, hasLength(1));
    });
  });

  group('Guiding category', () {
    test('StarLost -> guiding lost notification', () async {
      await emit(_ev(EventCategory.guiding, 'StarLost',
          severity: EventSeverity.critical));
      expect(notifications.calls.single.kind, 'guidingLost');
    });

    test('LostStar legacy spelling -> guiding lost notification', () async {
      await emit(_ev(EventCategory.guiding, 'LostStar'));
      expect(notifications.calls.single.kind, 'guidingLost');
    });

    test('Disconnected -> guiding lost notification', () async {
      await emit(_ev(EventCategory.guiding, 'Disconnected'));
      expect(notifications.calls.single.kind, 'guidingLost');
      expect(notifications.calls.single.data['reason'],
          contains('disconnected'));
    });

    test('respects notifyGuiding mute toggle', () async {
      await prefs.setNotifyGuiding(false);
      await emit(_ev(EventCategory.guiding, 'StarLost'));
      expect(notifications.calls, isEmpty);
    });
  });

  group('Imaging category', () {
    test('ExposureFailed -> exposure failed notification', () async {
      await emit(_ev(EventCategory.imaging, 'ExposureFailed',
          data: {'error': 'Camera offline'}));
      expect(notifications.calls.single.kind, 'exposureFailed');
      expect(notifications.calls.single.data['error'], 'Camera offline');
    });

    test('ExposureFailed_Old legacy variant -> notification', () async {
      await emit(_ev(EventCategory.imaging, 'ExposureFailed_Old',
          data: {'reason': 'Shutter jam'}));
      expect(notifications.calls.single.kind, 'exposureFailed');
      expect(notifications.calls.single.data['error'], 'Shutter jam');
    });

    test('respects notifyExposureFailed mute toggle', () async {
      await prefs.setNotifyExposureFailed(false);
      await emit(_ev(EventCategory.imaging, 'ExposureFailed',
          data: {'error': 'x'}));
      expect(notifications.calls, isEmpty);
    });

    test('non-failure imaging events are ignored', () async {
      await emit(_ev(EventCategory.imaging, 'ExposureStarted'));
      await emit(_ev(EventCategory.imaging, 'ExposureCompleted'));
      await emit(_ev(EventCategory.imaging, 'ImageReady'));
      expect(notifications.calls, isEmpty);
    });
  });

  group('Equipment category', () {
    test('Disconnected -> equipment disconnected notification', () async {
      await emit(_ev(EventCategory.equipment, 'Disconnected',
          data: {'device_type': 'Camera', 'device_id': 'asi:0'}));
      expect(notifications.calls.single.kind, 'equipmentDisconnected');
      expect(notifications.calls.single.data['deviceType'], 'Camera');
      expect(notifications.calls.single.data['deviceId'], 'asi:0');
    });

    test('Error with disconnect keyword -> notification', () async {
      await emit(_ev(EventCategory.equipment, 'Error', data: {
        'device_type': 'Mount',
        'message': 'COM port lost connection',
      }));
      expect(notifications.calls.single.kind, 'equipmentDisconnected');
    });

    test('Error without transport keyword -> ignored', () async {
      await emit(_ev(EventCategory.equipment, 'Error', data: {
        'device_type': 'Mount',
        'message': 'Slew exceeded soft limit',
      }));
      expect(notifications.calls, isEmpty);
    });

    test('HeartbeatStatusChanged -> notification on Disconnected status',
        () async {
      await emit(_ev(EventCategory.equipment, 'HeartbeatStatusChanged', data: {
        'device_type': 'Focuser',
        'device_id': 'native:zwo:eaf:0',
        'status': 'Disconnected',
      }));
      expect(notifications.calls.single.kind, 'equipmentDisconnected');
    });

    test('respects notifyEquipmentDisconnected toggle', () async {
      await prefs.setNotifyEquipmentDisconnected(false);
      await emit(_ev(EventCategory.equipment, 'Disconnected', data: {
        'device_type': 'Camera',
        'device_id': 'asi:0',
      }));
      expect(notifications.calls, isEmpty);
    });
  });

  group('Sequencer category', () {
    test('NodeCompleted with failed autofocus -> autofocus failed notification',
        () async {
      await emit(_ev(EventCategory.sequencer, 'NodeCompleted', data: {
        'node_id': 'af-1',
        'node_type': 'Autofocus',
        'status': 'failed',
      }));
      expect(notifications.calls.single.kind, 'autofocusFailed');
    });

    test('NodeCompleted with success=false bool variant works', () async {
      await emit(_ev(EventCategory.sequencer, 'NodeCompleted', data: {
        'node_id': 'af-1',
        'node_type': 'Autofocus',
        'success': false,
      }));
      expect(notifications.calls.single.kind, 'autofocusFailed');
    });

    test('NodeCompleted with successful autofocus -> ignored', () async {
      await emit(_ev(EventCategory.sequencer, 'NodeCompleted', data: {
        'node_id': 'af-1',
        'node_type': 'Autofocus',
        'status': 'success',
      }));
      expect(notifications.calls, isEmpty);
    });

    test('NodeCompleted for non-autofocus failure -> ignored', () async {
      await emit(_ev(EventCategory.sequencer, 'NodeCompleted', data: {
        'node_id': 'exp-1',
        'node_type': 'Exposure',
        'status': 'failed',
      }));
      expect(notifications.calls, isEmpty);
    });

    test('TargetCompleted -> notification', () async {
      await emit(_ev(EventCategory.sequencer, 'TargetCompleted',
          data: {'target_name': 'M31'}));
      expect(notifications.calls.single.kind, 'targetCompleted');
      expect(notifications.calls.single.data['targetName'], 'M31');
    });

    test('TargetCompleted respects mute toggle', () async {
      await prefs.setNotifyTargetCompleted(false);
      await emit(_ev(EventCategory.sequencer, 'TargetCompleted',
          data: {'target_name': 'M31'}));
      expect(notifications.calls, isEmpty);
    });

    test('InstructionProgress meridian -> meridian flip notification',
        () async {
      await emit(_ev(EventCategory.sequencer, 'InstructionProgress', data: {
        'node_id': 'mf-1',
        'instruction': 'Meridian flip',
        'progress_percent': 30.0,
        'detail': 'Slewing past meridian',
      }));
      expect(notifications.calls.single.kind, 'meridianFlip');
    });

    test('InstructionProgress non-meridian -> ignored', () async {
      await emit(_ev(EventCategory.sequencer, 'InstructionProgress', data: {
        'node_id': 'cool-1',
        'instruction': 'Cool Camera',
        'progress_percent': 50.0,
        'detail': 'Cooling',
      }));
      expect(notifications.calls, isEmpty);
    });
  });

  group('System category', () {
    test('DiskSpaceLow -> low disk space notification', () async {
      await emit(_ev(EventCategory.system, 'DiskSpaceLow',
          data: {'available_gb': 2.5}));
      expect(notifications.calls.single.kind, 'lowDiskSpace');
      expect(notifications.calls.single.data['gb'], 2.5);
    });

    test('DiskSpaceLow respects mute toggle', () async {
      await prefs.setNotifyDiskLow(false);
      await emit(_ev(EventCategory.system, 'DiskSpaceLow',
          data: {'available_gb': 2.5}));
      expect(notifications.calls, isEmpty);
    });

    test('Other system events -> ignored', () async {
      await emit(_ev(EventCategory.system, 'Initialized'));
      await emit(_ev(EventCategory.system, 'Notification', data: {
        'title': 'Hello',
        'message': 'World',
        'level': 'info',
      }));
      expect(notifications.calls, isEmpty);
    });
  });

  group('Push dedupe', () {
    test('mobile-direct event is suppressed within dedupe window after push',
        () async {
      notifier.recordPushReceived('WeatherUnsafe');
      await emit(_ev(EventCategory.safety, 'WeatherUnsafe',
          data: {'reason': 'rain'}));
      expect(notifications.calls, isEmpty);
    });

    test('different eventType than the push is not dedupe-suppressed',
        () async {
      notifier.recordPushReceived('Completed');
      await emit(_ev(EventCategory.safety, 'WeatherUnsafe',
          data: {'reason': 'rain'}));
      expect(notifications.calls, hasLength(1));
    });
  });

  group('Polar alignment category', () {
    test('PolarAlignment events are not surfaced as notifications', () async {
      await emit(_ev(EventCategory.polarAlignment, 'StatusUpdate'));
      expect(notifications.calls, isEmpty);
    });
  });
}
