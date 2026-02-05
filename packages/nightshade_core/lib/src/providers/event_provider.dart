import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/src/api.dart' show apiEventStream;
import 'package:nightshade_bridge/src/event.dart' show NightshadeEvent, EventCategory, EventSeverity;

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
