import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/nightshade_app.dart' show iosBackgroundBannerProvider;
import 'package:nightshade_core/nightshade_core.dart';
import 'foreground_service.dart';
import 'notification_service.dart';
import 'power_service.dart';

/// Mobile-specific hooks for sequence execution
/// This class listens to sequence state changes and manages foreground service,
/// notifications, and power management for mobile devices
class MobileSequenceHooks {
  final Ref _ref;
  final ImagingForegroundService _foregroundService = ImagingForegroundService();
  final MobileNotificationService _notificationService = MobileNotificationService();
  final PowerService _powerService = PowerService();
  StreamSubscription<Map<String, dynamic>>? _pushNotificationSubscription;

  MobileSequenceHooks(this._ref);

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await _foregroundService.initialize();
    await _notificationService.initialize();
    await _powerService.initialize();

    // Set up battery warning callback
    _powerService.onCriticalBattery = _handleCriticalBattery;
    _powerService.onBatteryWarning = _handleBatteryWarning;

    // Listen to sequence execution state changes
    _ref.listen<SequenceExecutionState>(
      sequenceExecutionStateProvider,
      (previous, next) => _handleExecutionStateChange(previous, next),
    );

    // Listen to sequence progress for updates
    _ref.listen<SequenceProgress>(
      sequenceProgressProvider,
      (previous, next) => _handleProgressUpdate(previous, next),
    );

    // Listen for push notifications from the desktop via NetworkBackend
    _setupPushNotificationListener();
  }

  /// Subscribe to push notifications from the desktop server.
  ///
  /// Only activates when connected via NetworkBackend (i.e., mobile controlling
  /// a remote desktop). Push notifications are displayed as local notifications.
  void _setupPushNotificationListener() {
    _pushNotificationSubscription?.cancel();
    final backend = _ref.read(backendProvider);
    if (backend is NetworkBackend) {
      _pushNotificationSubscription =
          backend.pushNotificationStream.listen((data) {
        developer.log(
          'Received push notification: ${data['title']}',
          name: 'MobileSequenceHooks',
          level: 800,
        );
        _notificationService.notifyPush(data);
      }, onError: (error) {
        // Caught + degraded: stream errors mean we miss push notifications
        // until the backend reconnects. Warn so the gap is visible.
        developer.log(
          'Push notification stream error: $error',
          name: 'MobileSequenceHooks',
          level: 900,
        );
      });
    }
  }

  void _handleExecutionStateChange(
    SequenceExecutionState? previous,
    SequenceExecutionState next,
  ) async {
    final progress = _ref.read(sequenceProgressProvider);
    final sequence = _ref.read(currentSequenceProvider);

    switch (next) {
      case SequenceExecutionState.idle:
        // Sequence stopped or not started
        if (previous == SequenceExecutionState.running ||
            previous == SequenceExecutionState.paused) {
          await _stopImagingSession(
            sequenceCompleted: false,
            errorMessage: 'Sequence stopped',
          );
        }
        _setIosBackgroundBanner(false);
        break;

      case SequenceExecutionState.running:
        if (previous == SequenceExecutionState.idle) {
          // Sequence just started
          await _startImagingSession(sequence);
        } else if (previous == SequenceExecutionState.paused) {
          // Sequence resumed - ensure services are still active
          await _powerService.acquireWakeLock();
        }
        _setIosBackgroundBanner(Platform.isIOS);
        break;

      case SequenceExecutionState.paused:
        // Could optionally release wake lock during pause, but we'll keep it
        // to ensure we can resume quickly
        _setIosBackgroundBanner(Platform.isIOS);
        break;

      case SequenceExecutionState.stopping:
        // Sequence is in the process of stopping
        // Keep services active until fully stopped (transitions to idle)
        _setIosBackgroundBanner(Platform.isIOS);
        break;

      case SequenceExecutionState.completed:
        await _stopImagingSession(
          sequenceCompleted: true,
          completedExposures: progress.completedExposures,
          targetName: progress.currentTarget ?? sequence?.name ?? 'Unknown',
        );
        _setIosBackgroundBanner(false);
        break;

      case SequenceExecutionState.failed:
        await _stopImagingSession(
          sequenceCompleted: false,
          errorMessage: progress.message ?? 'Sequence failed',
          targetName: progress.currentTarget ?? sequence?.name ?? 'Unknown',
        );
        _setIosBackgroundBanner(false);
        break;
    }
  }

  /// Toggle the iOS-only "honest banner" advisory. No-op on Android (where
  /// the foreground service keeps monitoring alive). Audit §3.2.
  void _setIosBackgroundBanner(bool visible) {
    final desired = Platform.isIOS && visible;
    final notifier = _ref.read(iosBackgroundBannerProvider.notifier);
    if (notifier.state != desired) {
      notifier.state = desired;
    }
  }

  void _handleProgressUpdate(
    SequenceProgress? previous,
    SequenceProgress next,
  ) {
    // Update foreground service notification with current progress
    if (_foregroundService.isRunning) {
      _foregroundService.updateProgress(
        completedExposures: next.completedExposures,
        totalExposures: next.totalExposures,
        currentFilter: next.currentFilter,
        statusMessage: next.message,
      );
    }

    // Check for meridian flip events
    if (next.message?.toLowerCase().contains('meridian flip') == true) {
      _notificationService.notifyMeridianFlip(
        next.currentTarget ?? 'Unknown',
        DateTime.now(),
      );
    }
  }

  Future<void> _startImagingSession(Sequence? sequence) async {
    if (sequence == null) return;

    developer.log(
      'Starting imaging session for ${sequence.name}',
      name: 'MobileSequenceHooks',
      level: 800,
    );

    // Start power management (wake lock + battery monitoring)
    await _powerService.startImagingSession();

    // Start foreground service (keeps app alive in background)
    if (Platform.isAndroid) {
      await _foregroundService.startService(
        targetName: sequence.name,
        totalExposures: sequence.totalExposures,
      );
    }
  }

  Future<void> _stopImagingSession({
    required bool sequenceCompleted,
    String? errorMessage,
    String? targetName,
    int? completedExposures,
  }) async {
    developer.log(
      'Stopping imaging session (completed: $sequenceCompleted)',
      name: 'MobileSequenceHooks',
      level: 800,
    );

    // Stop power management
    await _powerService.stopImagingSession();

    // Stop foreground service and show completion notification
    if (Platform.isAndroid) {
      await _foregroundService.stopService(
        sequenceCompleted: sequenceCompleted,
        errorMessage: errorMessage,
      );
    } else {
      // On iOS, manually send notification since we don't have foreground service
      if (sequenceCompleted) {
        await _notificationService.notifySequenceComplete(
          targetName ?? 'Unknown',
          completedExposures ?? 0,
        );
      } else if (errorMessage != null) {
        await _notificationService.notifySequenceFailed(
          targetName ?? 'Unknown',
          errorMessage,
        );
      }
    }
  }

  void _handleCriticalBattery() async {
    // Critical battery is a safety event — warn so it's visible above the
    // info noise floor in DevTools and the log file.
    developer.log(
      'Critical battery level - pausing sequence',
      name: 'MobileSequenceHooks',
      level: 900,
    );

    // Auto-pause sequence at critical battery level
    final executionState = _ref.read(sequenceExecutionStateProvider);
    if (executionState == SequenceExecutionState.running) {
      // Get the sequence executor and pause
      try {
        final backend = _ref.read(backendProvider);
        await backend.sequencerPause();
      } catch (e, st) {
        // Caught here, sequence keeps running on a critical battery — this
        // is a serious failure mode; log as severe with error chain.
        developer.log(
          'Failed to pause sequence: $e',
          name: 'MobileSequenceHooks',
          level: 1000,
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  void _handleBatteryWarning(BatteryWarningLevel level) {
    // Warnings are already sent by PowerService via MobileNotificationService
    // This callback is for any additional handling
    developer.log(
      'Battery warning: $level',
      name: 'MobileSequenceHooks',
      level: 900,
    );
  }

  Future<void> dispose() async {
    await _pushNotificationSubscription?.cancel();
    _pushNotificationSubscription = null;
    await _powerService.dispose();
  }
}

/// Provider for mobile sequence hooks
final mobileSequenceHooksProvider = Provider<MobileSequenceHooks>((ref) {
  final hooks = MobileSequenceHooks(ref);

  // Initialize on creation
  hooks.initialize();

  // Clean up on disposal
  ref.onDispose(() {
    hooks.dispose();
  });

  return hooks;
});
