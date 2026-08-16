import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart'
    show apiEventStream, NightshadeEvent, EventCategory, EventSeverity;
import '../backend/bridge_event_mapper.dart';
import '../backend/ffi_backend.dart';
import '../backend/network_backend.dart';
import '../models/backend/event_types.dart' as core;
import '../models/backend/host_mutation_event.dart'
    show hostStateChangedEventType;
import 'backend_provider.dart';
import 'host_mutation_event_provider.dart';
import 'sequence/run_stop_classification.dart';
import 'ui_notification_provider.dart';

/// Provider for the global event stream from the Rust native layer
///
/// Every sequencer, device, imaging, guiding and safety event arrives here.
/// UI components subscribe to this stream to react to backend state changes.
final nightshadeEventsProvider = StreamProvider<NightshadeEvent>((ref) {
  final backend = ref.watch(backendProvider);

  // Remote clients receive the same typed bridge events as local FFI
  // backends by reconstructing `EventPayload_*` variants from the
  // collapsed envelope on `NetworkBackend.eventStream` (WebSocket).
  if (backend is NetworkBackend) {
    // `HostStateChanged` is a host-mutation SYNC envelope (applied separately
    // by applyRemoteSyncEvent), NOT a Rust telemetry event. The typed bridge
    // mapper has no case for it, so its `default` arm turns every one into a
    // `SystemEvent.error` — which the dashboard flags critical and shows as a
    // "Critical · System" toast. Since the master emits HostStateChanged
    // constantly (the mirror mechanism), that produced a flood of bogus
    // critical errors on the slave. Drop it from the typed/telemetry stream.
    return backend.eventStream
        .where((event) => event.eventType != hostStateChangedEventType)
        .map(bridgeEventFromCoreEvent);
  }

  // Local desktop/headless: FRB stream plus host REST mutation events so the
  // GUI EventBus sees remote companion writes while the embedded API server
  // is enabled.
  final nativeStream = apiEventStream();
  if (backend is! FfiBackend) {
    return nativeStream;
  }

  // Same guard as the NetworkBackend branch above: `HostStateChanged` is a
  // host-mutation SYNC envelope (applied by host_local_sync_provider), NOT a
  // telemetry event. Every event on the mutation hub is a HostStateChanged, so
  // without this filter bridgeEventFromCoreEvent's default arm turned each one
  // into a `SystemEvent.error` — meaning any local settings write or companion
  // client mutation flashed a red "System error: HostStateChanged" banner on
  // the desktop (the embedded server's whole purpose is companion writes, so
  // this fired constantly).
  final mutationStream = ref
      .watch(hostMutationEventStreamProvider)
      .where((event) => event.eventType != hostStateChangedEventType)
      .map(bridgeEventFromCoreEvent);
  return _mergeEventStreams(nativeStream, mutationStream);
});

Stream<NightshadeEvent> _mergeEventStreams(
  Stream<NightshadeEvent> primary,
  Stream<NightshadeEvent> secondary,
) {
  late final StreamController<NightshadeEvent> controller;
  StreamSubscription<NightshadeEvent>? primarySub;
  StreamSubscription<NightshadeEvent>? secondarySub;

  controller = StreamController<NightshadeEvent>.broadcast(
    onListen: () {
      primarySub = primary.listen(controller.add, onError: controller.addError);
      secondarySub = secondary.listen(
        controller.add,
        onError: controller.addError,
      );
    },
    onCancel: () async {
      await primarySub?.cancel();
      await secondarySub?.cancel();
      primarySub = null;
      secondarySub = null;
    },
  );

  return controller.stream;
}

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
final eventHistoryProvider =
    StateNotifierProvider<EventHistoryNotifier, List<NightshadeEvent>>((ref) {
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
    state = [event, ...state].take(maxHistorySize).toList();
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

  // Coalesce identical toasts that arrive in a tight burst. A mass event such
  // as "Disconnect All" makes every device emit a Disconnected/Error event,
  // often repeated as each driver tears down, and every one of those would
  // raise its own toast — hundreds-to-thousands in a single event-loop turn
  // flood the notification overlay and the Windows platform task runner
  // ("Failed to post message to main thread"). Suppressing a repeat of the
  // *same* (severity+title+message) toast within this window collapses a
  // driver's teardown chatter to one visible toast; the first occurrence of
  // every distinct error still shows.
  const dedupeWindow = Duration(seconds: 3);
  final lastShownAt = <String, DateTime>{};

  bool shouldSuppress(String dedupeKey, DateTime now) {
    // Opportunistically prune stale keys so the map can't grow without bound
    // across a long-running session of distinct errors.
    lastShownAt.removeWhere((_, when) => now.difference(when) > dedupeWindow);
    final previous = lastShownAt[dedupeKey];
    if (previous != null && now.difference(previous) < dedupeWindow) {
      return true;
    }
    lastShownAt[dedupeKey] = now;
    return false;
  }

  subscription = backend.eventStream.listen(
    (event) {
      if (event.severity == core.EventSeverity.info) return;

      // PRODUCER 4 of the stop pipeline, and the one the operator actually
      // reads. Like every other producer it asks `isSequenceCancelledNotice`
      // before calling a deliberate Stop a fault. It takes no part in the
      // NotificationRouter, so neither the router's classification nor its
      // content dedupe can reach it — the check has to live here.
      if (_isOperatorStopNotice(event)) {
        developer.log(
          '[$kStopClassificationLogTag] error_notification_bridge: sequencer '
          'Error carrying the cancellation notice -> no error toast',
          name: 'ErrorNotificationBridge',
        );
        return;
      }

      final message = _extractEventMessage(event);
      final title = _eventTitle(event);

      final now = DateTime.now();
      final dedupeKey = '${event.severity.name}|$title|$message';
      if (shouldSuppress(dedupeKey, now)) return;

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
    },
    onError: (error) {
      developer.log(
        '[ErrorNotificationBridge] Event stream error: $error',
        name: 'ErrorNotificationBridge',
        level: 1000,
        error: error,
      );
    },
  );

  ref.onDispose(() {
    subscription?.cancel();
  });
});

/// True when this backend event is the operator's Stop wearing an error's
/// clothes.
///
/// The wire shape is fixed: the native executor's `NodeStatus::Cancelled` arm
/// sends `ExecutorEvent::Error { message: "Sequence cancelled" }`
/// (`sequencer/src/executor/start.rs`), the bridge stamps it
/// `EventSeverity::Error` / `EventCategory::Sequencer`
/// (`bridge/src/api/sequencer/event_bridge.rs`), and the FFI mapper delivers it
/// as eventType `'Error'` with the notice under `message`
/// (`backend/ffi_backend/event_mapping.dart`). The remote/WebSocket envelope has
/// been seen using `error` for the same field, so both are read — the same pair
/// `NotificationEventClassifier._sequencerErrorMessage` reads.
///
/// Only the exact notice is reclassified; a real fault whose text merely
/// contains "cancelled" ("Temperature compensation cancelled") is still an
/// error and still reaches the operator. See [isSequenceCancelledNotice].
bool _isOperatorStopNotice(core.NightshadeEvent event) {
  if (event.category != core.EventCategory.sequencer) return false;
  if (event.eventType != 'Error') return false;
  final message =
      (event.data['message'] as String?) ??
      (event.data['error'] as String?) ??
      '';
  return isSequenceCancelledNotice(message);
}

/// Extract a human-readable message from a NightshadeEvent's data map.
String _extractEventMessage(core.NightshadeEvent event) {
  final data = event.data;

  // Try common message keys in order of specificity
  if (data.containsKey('message') &&
      data['message'] is String &&
      (data['message'] as String).isNotEmpty) {
    return data['message'] as String;
  }
  if (data.containsKey('error') &&
      data['error'] is String &&
      (data['error'] as String).isNotEmpty) {
    return data['error'] as String;
  }
  if (data.containsKey('reason') &&
      data['reason'] is String &&
      (data['reason'] as String).isNotEmpty) {
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
    core.EventCategory.job => 'Job',
    core.EventCategory.session => 'Session',
    core.EventCategory.catalog => 'Catalog',
  };

  if (deviceType != null && deviceType.isNotEmpty) {
    return '$deviceType Error';
  }
  return '$categoryLabel ${event.severity == core.EventSeverity.warning ? "Warning" : "Error"}';
}
