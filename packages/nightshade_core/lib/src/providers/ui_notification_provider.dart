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

  /// Show a notification
  void show({
    required String message,
    required UiNotificationLevel level,
    String? title,
    Duration? duration,
  }) {
    final notification = UiNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      message: message,
      level: level,
      timestamp: DateTime.now(),
      title: title,
      duration: duration ?? const Duration(seconds: 4),
    );

    state = [...state, notification];
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
