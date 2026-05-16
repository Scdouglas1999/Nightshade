import 'dart:async';
import 'dart:developer' as developer;

import 'package:nightshade_core/nightshade_core.dart';

import 'mobile_preferences.dart';
import 'notification_service.dart';

/// Subscribes to the backend's `NightshadeEvent` stream and converts critical
/// events into local OS notifications via [MobileNotificationService].
///
/// This is the mobile-direct path. The desktop also runs a
/// `PushNotificationService` that ships pre-formatted alerts over the
/// WebSocket; that path remains for advisory pings the mobile cannot
/// reconstruct (e.g., a server admin firing a manual test). But all
/// critical-event coverage now goes through this notifier so the mobile
/// app surfaces alarms even when desktop push is disabled or the desktop
/// crashes mid-publish.
///
/// Why a category-mute matrix lives in [MobilePreferences] rather than in
/// the shared desktop `PushNotificationConfig`: those toggles drive the
/// desktop's outbound stream and are scoped to a *server*; per-device mute
/// preferences (e.g., "this phone is in DnD") are scoped to the *client*.
/// A phone in your pocket has different mute needs than a tablet on the
/// observatory wall sharing the same server.
class MobileEventNotifier {
  MobileEventNotifier({
    required Stream<NightshadeEvent> eventStream,
    required MobilePreferences preferences,
    MobileNotificationSink? notificationService,
  })  : _eventStream = eventStream,
        _preferences = preferences,
        _notifications = notificationService ?? MobileNotificationService();

  final Stream<NightshadeEvent> _eventStream;
  final MobilePreferences _preferences;
  final MobileNotificationSink _notifications;

  StreamSubscription<NightshadeEvent>? _subscription;

  /// Tracks the last-fired wall clock per `(category, eventType)` pair so we
  /// can debounce repeat fires of the same event within [_repeatWindow].
  /// Sequence trees often emit `Disconnected` twice in a row when a device
  /// reconnects and immediately drops again; the user does not need two
  /// buzzes inside one second.
  final Map<String, DateTime> _lastFired = <String, DateTime>{};

  /// Tracks the last `notifyPush` arrival per event type so we don't fire
  /// a mobile-direct notification immediately after a desktop push for the
  /// same event landed (the order between the raw event and the push wrap
  /// is not guaranteed). Recorded by callers via [recordPushReceived].
  final Map<String, DateTime> _lastPushSeen = <String, DateTime>{};

  static const Duration _repeatWindow = Duration(seconds: 5);
  static const Duration _pushDedupeWindow = Duration(seconds: 10);

  void start() {
    _subscription?.cancel();
    _subscription = _eventStream.listen(
      _handle,
      onError: (Object error, StackTrace st) {
        // Stream errors mean we miss critical events until the backend
        // reconnects. Log loudly; we already get a synthetic
        // `BackendReconnected` event when the WS comes back.
        developer.log(
          '[MobileEventNotifier] Event stream error: $error',
          name: 'MobileEventNotifier',
          level: 1000,
          error: error,
          stackTrace: st,
        );
      },
    );
    developer.log(
      '[MobileEventNotifier] Subscribed to backend event stream',
      name: 'MobileEventNotifier',
      level: 800,
    );
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Called by the push notification listener whenever a `push_notification`
  /// envelope is delivered, so we can suppress a redundant mobile-direct
  /// notification for the same event within the dedupe window.
  void recordPushReceived(String eventType) {
    if (eventType.isEmpty) return;
    _lastPushSeen[eventType] = DateTime.now();
  }

  bool _firedRecently(String key, Duration window) {
    final last = _lastFired[key];
    if (last == null) return false;
    return DateTime.now().difference(last) < window;
  }

  void _markFired(String key) {
    _lastFired[key] = DateTime.now();
  }

  bool _pushAlreadyCovered(String eventType) {
    final last = _lastPushSeen[eventType];
    if (last == null) return false;
    return DateTime.now().difference(last) < _pushDedupeWindow;
  }

  Future<void> _handle(NightshadeEvent event) async {
    try {
      switch (event.category) {
        case EventCategory.safety:
          await _handleSafety(event);
          break;
        case EventCategory.guiding:
          await _handleGuiding(event);
          break;
        case EventCategory.imaging:
          await _handleImaging(event);
          break;
        case EventCategory.equipment:
          await _handleEquipment(event);
          break;
        case EventCategory.sequencer:
          await _handleSequencer(event);
          break;
        case EventCategory.system:
          await _handleSystem(event);
          break;
        case EventCategory.polarAlignment:
          // Polar alignment runs in a foreground assistant; no need to
          // wake the operator's phone for each measurement frame.
          break;
      }
    } catch (e, st) {
      // Catching here keeps a malformed event from killing the subscriber.
      // We log loudly because a missed notification IS a failure mode.
      developer.log(
        '[MobileEventNotifier] Failed to dispatch ${event.eventType}: $e',
        name: 'MobileEventNotifier',
        level: 1000,
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _handleSafety(NightshadeEvent event) async {
    if (!_preferences.notifySafety) return;
    final key = 'safety:${event.eventType}';
    if (_firedRecently(key, _repeatWindow)) return;
    if (_pushAlreadyCovered(event.eventType)) return;

    switch (event.eventType) {
      case 'WeatherUnsafe':
        final reason = event.data['reason'] as String? ??
            'Safety monitor reports unsafe conditions';
        await _notifications.notifySafety(
          title: 'Weather Unsafe',
          body: 'Imaging halted: $reason',
        );
        _markFired(key);
        break;
      case 'EmergencyStop':
        final reason =
            event.data['reason'] as String? ?? 'Emergency stop triggered';
        await _notifications.notifySafety(
          title: 'Emergency Stop',
          body: reason,
        );
        _markFired(key);
        break;
      case 'ParkInitiated':
      case 'ParkCompleted':
        final reason =
            event.data['reason'] as String? ?? 'Mount has been parked';
        await _notifications.notifyMountParked(reason);
        _markFired(key);
        break;
      case 'WeatherSafe':
        // Recovery event — informational only and only useful as a
        // follow-up to a prior unsafe notification. Skipping rather than
        // adding a fourth channel pour les conditions normales.
        break;
    }
  }

  Future<void> _handleGuiding(NightshadeEvent event) async {
    if (!_preferences.notifyGuiding) return;
    final key = 'guiding:${event.eventType}';
    if (_firedRecently(key, _repeatWindow)) return;
    if (_pushAlreadyCovered(event.eventType)) return;

    switch (event.eventType) {
      case 'StarLost':
      case 'LostStar':
        // PHD2 emits "LostStar" historically; the Rust bridge canonicalizes
        // it to "StarLost" in the docs, but both are seen on older servers.
        await _notifications.notifyGuidingLost(
          'Guide star has been lost. Guiding has stopped.',
        );
        _markFired(key);
        break;
      case 'Disconnected':
        await _notifications.notifyGuidingLost('PHD2 guiding has disconnected.');
        _markFired(key);
        break;
    }
  }

  Future<void> _handleImaging(NightshadeEvent event) async {
    final key = 'imaging:${event.eventType}';
    switch (event.eventType) {
      case 'ExposureFailed':
      case 'ExposureFailed_Old':
        if (!_preferences.notifyExposureFailed) return;
        if (_firedRecently(key, _repeatWindow)) return;
        if (_pushAlreadyCovered(event.eventType)) return;
        final error = event.data['error'] as String? ??
            event.data['reason'] as String? ??
            'Camera exposure failed';
        await _notifications.notifyExposureFailed(error);
        _markFired(key);
        break;
    }
  }

  Future<void> _handleEquipment(NightshadeEvent event) async {
    if (!_preferences.notifyEquipmentDisconnected) return;
    final key = 'equipment:${event.eventType}';
    if (_firedRecently(key, _repeatWindow)) return;
    if (_pushAlreadyCovered(event.eventType)) return;

    switch (event.eventType) {
      case 'Disconnected':
        final deviceType =
            event.data['device_type'] as String? ?? 'Device';
        final deviceId =
            event.data['device_id'] as String? ?? 'unknown';
        await _notifications.notifyEquipmentDisconnected(deviceType, deviceId);
        _markFired(key);
        break;
      case 'Error':
        // Equipment-level error: only fire on transport-class errors that
        // include a "disconnect" hint, to avoid firing on every retryable
        // PropertyChanged blip.
        final message = event.data['message'] as String? ?? '';
        final lower = message.toLowerCase();
        if (lower.contains('disconnect') ||
            lower.contains('lost') ||
            lower.contains('not responding')) {
          final deviceType =
              event.data['device_type'] as String? ?? 'Device';
          await _notifications.notifyEquipmentDisconnected(
            deviceType,
            message.isEmpty ? 'error' : message,
          );
          _markFired(key);
        }
        break;
      case 'HeartbeatStatusChanged':
        final status = event.data['status'] as String? ?? '';
        if (status == 'Disconnected') {
          final deviceType =
              event.data['device_type'] as String? ?? 'Device';
          final deviceId =
              event.data['device_id'] as String? ?? 'unknown';
          await _notifications.notifyEquipmentDisconnected(
              deviceType, deviceId);
          _markFired(key);
        }
        break;
    }
  }

  Future<void> _handleSequencer(NightshadeEvent event) async {
    final key = 'sequencer:${event.eventType}';
    switch (event.eventType) {
      case 'NodeCompleted':
        // Status field in Rust is "status" (success/failed/cancelled/skipped).
        // Some legacy desktop builds emit "success" as a bool — read both.
        final status = event.data['status'] as String?;
        final success = event.data['success'] as bool?;
        final nodeType = event.data['node_type'] as String? ?? '';
        final isFailed = status == 'failed' || success == false;
        if (isFailed && nodeType.toLowerCase().contains('autofocus')) {
          if (!_preferences.notifyAutofocusFailed) return;
          if (_firedRecently(key, _repeatWindow)) return;
          if (_pushAlreadyCovered(event.eventType)) return;
          await _notifications.notifyAutofocusFailed();
          _markFired(key);
        }
        break;
      case 'TargetCompleted':
        if (!_preferences.notifyTargetCompleted) return;
        if (_firedRecently(key, _repeatWindow)) return;
        if (_pushAlreadyCovered(event.eventType)) return;
        final targetName =
            event.data['target_name'] as String? ?? 'Unknown target';
        await _notifications.notifyTargetCompleted(targetName);
        _markFired(key);
        break;
      case 'InstructionProgress':
        // Meridian flip is the only InstructionProgress we surface — and
        // only the first time within the window so a long flip doesn't
        // buzz every tick. The existing `mobile_sequence_hooks` path
        // matches on `SequenceProgress.message`, which is independent of
        // this event stream; we still fire here so a desktop that emits
        // InstructionProgress without filling SequenceProgress.message
        // gets covered.
        if (!_preferences.notifyMeridianFlip) return;
        final instruction = event.data['instruction'] as String? ?? '';
        if (!instruction.toLowerCase().contains('meridian')) return;
        const meridianKey = 'sequencer:InstructionProgress:meridian';
        if (_firedRecently(meridianKey, const Duration(minutes: 5))) return;
        await _notifications.notifyMeridianFlip(
          'Active sequence',
          DateTime.now(),
        );
        _markFired(meridianKey);
        break;
    }
  }

  Future<void> _handleSystem(NightshadeEvent event) async {
    final key = 'system:${event.eventType}';
    switch (event.eventType) {
      case 'DiskSpaceLow':
        if (!_preferences.notifyDiskLow) return;
        if (_firedRecently(key, const Duration(minutes: 5))) return;
        if (_pushAlreadyCovered(event.eventType)) return;
        final available = (event.data['available_gb'] as num?)?.toDouble();
        if (available == null) return;
        await _notifications.notifyLowDiskSpace(available);
        _markFired(key);
        break;
    }
  }
}
