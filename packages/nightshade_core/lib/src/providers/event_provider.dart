import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/src/api_barrel.dart' show apiEventStream;
import 'package:nightshade_bridge/src/event.dart' show NightshadeEvent, EventCategory, EventSeverity;
import '../models/backend/event_types.dart' as core;
import 'backend_provider.dart';
import 'ui_notification_provider.dart';

/// Provider for the global event stream from the Rust native layer
///
/// This stream delivers all events from the sequencer, devices, imaging,
/// guiding, and safety systems. UI components should subscribe to this
/// stream to react to backend state changes and display notifications.
///
/// Events include:
/// - ExposureStarted, ExposureCompleted, ExposureCancelled
/// - DeviceConnected, DeviceDisconnected, DeviceError
/// - SequenceStarted, SequenceCompleted, SequencePaused
/// - GuidingStarted, GuidingStopped, DitherCompleted
/// - SafetyAlert, WeatherUnsafe, EmergencyStop
/// - And many more...
///
/// Example usage:
/// ```dart
/// ref.listen(nightshadeEventsProvider, (previous, next) {
///   next.when(
///     data: (event) {
///       // Handle event
///       if (event.category == EventCategory.Imaging) {
///         // Handle imaging events
///       }
///     },
///     loading: () {},
///     error: (error, stack) => print('Event stream error: $error'),
///   );
/// });
/// ```
final nightshadeEventsProvider = StreamProvider<NightshadeEvent>((ref) {
  // Connect to the Rust event stream
  // This stream delivers events from the sequencer, devices, imaging, etc.
  return apiEventStream();
});

/// Provider to track the last received event
///
/// Useful for displaying the most recent event in the UI
/// or for debugging purposes.
final lastEventProvider = StateNotifierProvider<LastEventNotifier, NightshadeEvent?>((ref) {
  final notifier = LastEventNotifier();

  ref.listen(nightshadeEventsProvider, (previous, next) {
    next.whenData((event) {
      notifier.updateEvent(event);
    });
  });

  return notifier;
});

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

class LastEventNotifier extends StateNotifier<NightshadeEvent?> {
  LastEventNotifier() : super(null);

  void updateEvent(NightshadeEvent event) {
    if (!mounted) return;
    state = event;
  }
}

/// Provider to track event history (last N events)
///
/// Keeps a rolling buffer of the most recent events for
/// displaying in an event log or notification center.
final eventHistoryProvider = StateNotifierProvider<EventHistoryNotifier, List<NightshadeEvent>>((ref) {
  final notifier = EventHistoryNotifier();

  ref.listen(nightshadeEventsProvider, (previous, next) {
    next.whenData((event) {
      notifier.addEvent(event);
    });
  });

  return notifier;
});

/// Notifier that maintains a history of events
class EventHistoryNotifier extends StateNotifier<List<NightshadeEvent>> {
  /// Maximum number of events to keep in history
  static const int maxHistorySize = 100;

  EventHistoryNotifier() : super([]);

  /// Add a new event to the history
  void addEvent(NightshadeEvent event) {
    if (!mounted) return;
    state = [
      event,
      ...state,
    ].take(maxHistorySize).toList();
  }

  /// Clear the event history
  void clear() {
    state = [];
  }

  /// Get events filtered by category
  List<NightshadeEvent> getByCategory(EventCategory category) {
    return state.where((e) => e.category == category).toList();
  }

  /// Get events filtered by severity
  List<NightshadeEvent> getBySeverity(EventSeverity severity) {
    return state.where((e) => e.severity == severity).toList();
  }
}

/// Bridges backend events with error/warning/critical severity to UI toast notifications.
///
/// This provider must be watched by the AppShell to stay active.
/// It subscribes to [backend.eventStream] and forwards error-severity
/// events to [uiNotificationProvider] for display as toast notifications.
final errorNotificationBridgeProvider = Provider<void>((ref) {
  final backend = ref.watch(backendProvider);
  final notifier = ref.read(uiNotificationProvider.notifier);

  StreamSubscription<core.NightshadeEvent>? subscription;

  subscription = backend.eventStream.listen((event) {
    if (event.severity == core.EventSeverity.info) return;

    final message = _extractEventMessage(event);
    final title = _eventTitle(event);

    switch (event.severity) {
      case core.EventSeverity.critical:
        notifier.showError(
          message,
          title: 'Critical: $title',
          duration: const Duration(seconds: 15),
        );
        break;
      case core.EventSeverity.error:
        notifier.showError(message, title: title);
        break;
      case core.EventSeverity.warning:
        notifier.showWarning(message, title: title);
        break;
      case core.EventSeverity.info:
        break;
    }
  }, onError: (error) {
    debugPrint('[ErrorNotificationBridge] Event stream error: $error');
  });

  ref.onDispose(() {
    subscription?.cancel();
  });
});

/// Extract a human-readable message from a NightshadeEvent's data map.
String _extractEventMessage(core.NightshadeEvent event) {
  final data = event.data;

  // Try common message keys in order of specificity
  if (data.containsKey('message') && data['message'] is String && (data['message'] as String).isNotEmpty) {
    return data['message'] as String;
  }
  if (data.containsKey('error') && data['error'] is String && (data['error'] as String).isNotEmpty) {
    return data['error'] as String;
  }
  if (data.containsKey('reason') && data['reason'] is String && (data['reason'] as String).isNotEmpty) {
    return data['reason'] as String;
  }

  // Fall back to event type
  return event.eventType;
}

/// Build a title string from the event's category and device type.
String _eventTitle(core.NightshadeEvent event) {
  final deviceType = event.data['device_type'] as String?;
  final categoryLabel = switch (event.category) {
    core.EventCategory.equipment => 'Device',
    core.EventCategory.imaging => 'Imaging',
    core.EventCategory.guiding => 'Guiding',
    core.EventCategory.sequencer => 'Sequence',
    core.EventCategory.safety => 'Safety',
    core.EventCategory.system => 'System',
    core.EventCategory.polarAlignment => 'Polar Alignment',
  };

  if (deviceType != null && deviceType.isNotEmpty) {
    return '$deviceType Error';
  }
  return '$categoryLabel ${event.severity == core.EventSeverity.warning ? "Warning" : "Error"}';
}
