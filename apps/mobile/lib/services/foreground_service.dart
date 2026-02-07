// ignore_for_file: unused_field

import 'dart:async';
import 'dart:isolate';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'notification_service.dart';

class ImagingForegroundService {
  static final ImagingForegroundService _instance =
      ImagingForegroundService._internal();
  factory ImagingForegroundService() => _instance;
  ImagingForegroundService._internal();

  bool _isRunning = false;
  String _currentTarget = '';
  int _completedExposures = 0;
  int _totalExposures = 0;
  double _percentComplete = 0.0;

  bool get isRunning => _isRunning;

  Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'nightshade_imaging',
        channelName: 'Nightshade Imaging',
        channelDescription: 'Displays imaging sequence progress',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  Future<bool> startService({
    required String targetName,
    required int totalExposures,
  }) async {
    _currentTarget = targetName;
    _totalExposures = totalExposures;
    _completedExposures = 0;
    _percentComplete = 0.0;

    if (await FlutterForegroundTask.isRunningService) {
      return await FlutterForegroundTask.restartService();
    } else {
      return await FlutterForegroundTask.startService(
        notificationTitle: 'Imaging $targetName',
        notificationText: 'Starting sequence... (0/$totalExposures)',
        callback: startCallback,
      );
    }
  }

  void updateProgress({
    required int completedExposures,
    required int totalExposures,
    String? currentFilter,
    String? statusMessage,
  }) {
    if (!_isRunning) return;

    _completedExposures = completedExposures;
    _totalExposures = totalExposures;
    _percentComplete =
        totalExposures > 0 ? (completedExposures / totalExposures) * 100 : 0;

    String text = '$completedExposures/$totalExposures exposures';
    if (currentFilter != null) {
      text += ' ($currentFilter)';
    }
    if (statusMessage != null && statusMessage.isNotEmpty) {
      text += ' - $statusMessage';
    }

    FlutterForegroundTask.updateService(
      notificationTitle: 'Imaging $_currentTarget',
      notificationText: text,
    );

    // Note: sendDataToTask removed in v6.0.0+
    // Data is now sent via updateService notification only
  }

  Future<void> stopService({
    bool sequenceCompleted = false,
    String? errorMessage,
  }) async {
    if (!_isRunning) return;

    // Send final notification before stopping service
    if (sequenceCompleted) {
      await NotificationService().notifySequenceComplete(
        _currentTarget,
        _completedExposures,
      );
    } else if (errorMessage != null) {
      await NotificationService().notifySequenceFailed(
        _currentTarget,
        errorMessage,
      );
    }

    await FlutterForegroundTask.stopService();
    _isRunning = false;
    _currentTarget = '';
    _completedExposures = 0;
    _totalExposures = 0;
    _percentComplete = 0.0;
  }

  void setRunning(bool running) {
    _isRunning = running;
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ImagingTaskHandler());
}

class ImagingTaskHandler extends TaskHandler {
  SendPort? _sendPort;
  int _updateCount = 0;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    _sendPort = sendPort;
    ImagingForegroundService().setRunning(true);
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp, SendPort? sendPort) async {
    _updateCount++;

    // Send keep-alive signal
    FlutterForegroundTask.updateService(
      notificationTitle: 'Nightshade Imaging',
      notificationText: 'Sequence running...',
    );

    // Send update to UI if needed
    _sendPort?.send(_updateCount);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    ImagingForegroundService().setRunning(false);
  }

  @override
  void onNotificationPressed() {
    // Handle notification tap - app will be brought to foreground
    FlutterForegroundTask.launchApp('/');
  }
}
