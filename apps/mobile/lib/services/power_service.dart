import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'notification_service.dart';

enum BatteryWarningLevel {
  normal,
  low,
  veryLow,
  critical,
}

class PowerService {
  static final PowerService _instance = PowerService._internal();
  factory PowerService() => _instance;
  PowerService._internal();

  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  Timer? _batteryMonitorTimer;

  bool _wakeLockActive = false;
  bool _isMonitoring = false;

  int _currentBatteryLevel = 100;
  BatteryState _currentBatteryState = BatteryState.full;
  BatteryWarningLevel _lastWarningLevel = BatteryWarningLevel.normal;

  // Callbacks for battery events
  Function(int percentage)? onBatteryLevelChanged;
  Function(BatteryState state)? onBatteryStateChanged;
  Function(BatteryWarningLevel level)? onBatteryWarning;
  Function()? onCriticalBattery;

  // Settings
  // Only CPU wake lock is honored. Screen wake lock was an unused config
  // surface that misled callers (see audit §3.14).
  bool enableCpuWakeLock = true; // Keep CPU awake (required for imaging)
  int batteryCheckIntervalSeconds = 30;

  bool get wakeLockActive => _wakeLockActive;
  int get currentBatteryLevel => _currentBatteryLevel;
  BatteryState get currentBatteryState => _currentBatteryState;
  bool get isMonitoring => _isMonitoring;

  Stream<int> get batteryLevelStream => _batteryLevelStreamController.stream;
  final _batteryLevelStreamController = StreamController<int>.broadcast();

  Future<void> initialize() async {
    // Get initial battery level
    _currentBatteryLevel = await _battery.batteryLevel;
    _currentBatteryState = await _battery.batteryState;

    // Listen to battery state changes (charging/discharging)
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((state) {
      _currentBatteryState = state;
      onBatteryStateChanged?.call(state);

      // Cancel critical warnings if charging
      if (state == BatteryState.charging || state == BatteryState.full) {
        _lastWarningLevel = BatteryWarningLevel.normal;
      }
    });
  }

  Future<void> acquireWakeLock() async {
    if (_wakeLockActive) return;

    try {
      if (enableCpuWakeLock) {
        // Enable wake lock to keep CPU running
        await WakelockPlus.enable();
        _wakeLockActive = true;
        print('[PowerService] Wake lock acquired (CPU)');
      }
    } catch (e) {
      print('[PowerService] Failed to acquire wake lock: $e');
    }
  }

  Future<void> releaseWakeLock() async {
    if (!_wakeLockActive) return;

    try {
      await WakelockPlus.disable();
      _wakeLockActive = false;
      print('[PowerService] Wake lock released');
    } catch (e) {
      print('[PowerService] Failed to release wake lock: $e');
    }
  }

  void startBatteryMonitoring() {
    if (_isMonitoring) return;

    _isMonitoring = true;
    print('[PowerService] Started battery monitoring (interval: ${batteryCheckIntervalSeconds}s)');

    // Check battery level periodically
    _batteryMonitorTimer = Timer.periodic(
      Duration(seconds: batteryCheckIntervalSeconds),
      (_) => _checkBatteryLevel(),
    );

    // Initial check
    _checkBatteryLevel();
  }

  void stopBatteryMonitoring() {
    if (!_isMonitoring) return;

    _batteryMonitorTimer?.cancel();
    _batteryMonitorTimer = null;
    _isMonitoring = false;
    _lastWarningLevel = BatteryWarningLevel.normal;

    print('[PowerService] Stopped battery monitoring');
  }

  Future<void> _checkBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      _currentBatteryLevel = level;

      // Emit to stream
      _batteryLevelStreamController.add(level);

      // Notify callback
      onBatteryLevelChanged?.call(level);

      // Check if we need to warn about battery level
      final warningLevel = _getBatteryWarningLevel(level);

      // Only notify if warning level changed and not charging
      if (warningLevel != _lastWarningLevel &&
          _currentBatteryState != BatteryState.charging &&
          _currentBatteryState != BatteryState.full) {
        _lastWarningLevel = warningLevel;

        switch (warningLevel) {
          case BatteryWarningLevel.low:
            await NotificationService().notifyLowBattery(level);
            onBatteryWarning?.call(warningLevel);
            break;

          case BatteryWarningLevel.veryLow:
            await NotificationService().notifyLowBattery(level);
            onBatteryWarning?.call(warningLevel);
            break;

          case BatteryWarningLevel.critical:
            await NotificationService().notifyLowBattery(level);
            onBatteryWarning?.call(warningLevel);
            onCriticalBattery?.call();
            break;

          case BatteryWarningLevel.normal:
            // Battery level returned to normal
            break;
        }
      }
    } catch (e) {
      print('[PowerService] Error checking battery level: $e');
    }
  }

  BatteryWarningLevel _getBatteryWarningLevel(int percentage) {
    if (percentage <= 10) {
      return BatteryWarningLevel.critical;
    } else if (percentage <= 15) {
      return BatteryWarningLevel.veryLow;
    } else if (percentage <= 20) {
      return BatteryWarningLevel.low;
    } else {
      return BatteryWarningLevel.normal;
    }
  }

  Future<void> startImagingSession() async {
    print('[PowerService] Starting imaging session');
    await acquireWakeLock();
    startBatteryMonitoring();
  }

  Future<void> stopImagingSession() async {
    print('[PowerService] Stopping imaging session');
    stopBatteryMonitoring();
    await releaseWakeLock();
  }

  Future<void> dispose() async {
    await _batteryStateSubscription?.cancel();
    _batteryMonitorTimer?.cancel();
    await _batteryLevelStreamController.close();
    if (_wakeLockActive) {
      await releaseWakeLock();
    }
  }

  bool shouldPauseForBattery() {
    return _currentBatteryLevel <= 10 &&
           _currentBatteryState != BatteryState.charging &&
           _currentBatteryState != BatteryState.full;
  }

  bool shouldWarnForBattery() {
    return _currentBatteryLevel <= 15 &&
           _currentBatteryState != BatteryState.charging &&
           _currentBatteryState != BatteryState.full;
  }
}
