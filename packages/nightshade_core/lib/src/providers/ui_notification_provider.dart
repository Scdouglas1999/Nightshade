import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Severity level for UI notifications
enum UiNotificationLevel {
  info,
  success,
  warning,
  error,
}

/// A UI notification to be displayed to the user (e.g., snackbar, banner, toast)
class UiNotification {
  final String id;
  final String message;
  final UiNotificationLevel level;
  final DateTime timestamp;
  final String? title;
  final Duration? duration;

  const UiNotification({
    required this.id,
    required this.message,
    required this.level,
    required this.timestamp,
    this.title,
    this.duration,
  });
}

/// Notifier that manages a queue of UI notifications
class UiNotificationNotifier extends StateNotifier<List<UiNotification>> {
  UiNotificationNotifier() : super([]);

  /// Hard upper bound on the number of notifications retained in state.
  ///
  /// The toast overlay only ever renders the most recent few (see
  /// `NotificationToastOverlay._maxVisibleToasts`), so keeping more than a
  /// small backlog serves no UI purpose and is pure cost. Crucially, this cap
  /// is what makes a *burst* of notifications safe: without it a mass event
  /// (e.g. "Disconnect All" emitting a driver-error/disconnect for every
  /// device, multiplied by any teardown chatter on the Rust EventBus) would
  /// append unboundedly. Each append rebuilds the overlay and copies the whole
  /// list, so an unbounded queue turns a burst into O(n^2) list copies plus one
  /// overlay rebuild — and one batch of post-frame callbacks / toast animation
  /// ticks — *per event*. On Windows that floods the platform task runner
  /// ("Failed to post message to main thread"). Capping the retained list keeps
  /// each append O(cap) and bounds the rebuild cost.
  ///
  /// Sized comfortably above the overlay's visible count so a normal flurry of
  /// distinct notifications still scrolls through naturally; only a genuine
  /// flood is trimmed.
  static const int maxRetained = 20;

  /// A counter appended to the millisecond timestamp so that several
  /// notifications raised inside the same millisecond (exactly what happens
  /// during a synchronous burst) still receive unique ids. Without this two
  /// burst entries could collide on id and the overlay's `ValueKey(id)` /
  /// dismiss-by-id bookkeeping would conflate them.
  int _idSequence = 0;

  /// Show a notification
  void show({
    required String message,
    required UiNotificationLevel level,
    String? title,
    Duration? duration,
  }) {
    final notification = UiNotification(
      id: '${DateTime.now().millisecondsSinceEpoch}-${_idSequence++}',
      message: message,
      level: level,
      timestamp: DateTime.now(),
      title: title,
      duration: duration ?? const Duration(seconds: 4),
    );

    final appended = [...state, notification];
    // Trim from the front so the most recent notifications (the only ones the
    // overlay shows) are always retained.
    state = appended.length > maxRetained
        ? appended.sublist(appended.length - maxRetained)
        : appended;
  }

  /// Show an info notification
  void showInfo(String message, {String? title, Duration? duration}) {
    show(
      message: message,
      level: UiNotificationLevel.info,
      title: title,
      duration: duration,
    );
  }

  /// Show a success notification
  void showSuccess(String message, {String? title, Duration? duration}) {
    show(
      message: message,
      level: UiNotificationLevel.success,
      title: title,
      duration: duration,
    );
  }

  /// Show a warning notification
  void showWarning(String message, {String? title, Duration? duration}) {
    show(
      message: message,
      level: UiNotificationLevel.warning,
      title: title,
      duration: duration ?? const Duration(seconds: 6),
    );
  }

  /// Show an error notification
  void showError(String message, {String? title, Duration? duration}) {
    show(
      message: message,
      level: UiNotificationLevel.error,
      title: title,
      duration: duration ?? const Duration(seconds: 8),
    );
  }

  /// Dismiss a specific notification by ID
  void dismiss(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  /// Dismiss the oldest notification
  void dismissOldest() {
    if (state.isNotEmpty) {
      state = state.skip(1).toList();
    }
  }

  /// Clear all notifications
  void clearAll() {
    state = [];
  }
}

/// Provider for UI notifications
final uiNotificationProvider =
    StateNotifierProvider<UiNotificationNotifier, List<UiNotification>>((ref) {
  return UiNotificationNotifier();
});
