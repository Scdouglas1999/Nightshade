import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nightshade_bridge/src/api.dart' as bridge_api;

/// Log level for filtering
enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

/// A log entry
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? source;
  final Map<String, Object?> fields;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
    Map<String, Object?>? fields,
  }) : fields = Map.unmodifiable(fields ?? const {});

  @override
  String toString() {
    final levelStr = level.name.toUpperCase().padRight(8);
    final sourceStr = source != null ? '[$source] ' : '';
    final fieldsStr = fields.isEmpty ? '' : ' ${jsonEncode(_jsonSafe(fields))}';
    return '${timestamp.toIso8601String()} $levelStr $sourceStr$message$fieldsStr';
  }

  static Object? _jsonSafe(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Iterable) {
      return value.map(_jsonSafe).toList(growable: false);
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    return value.toString();
  }
}

/// Service for managing application logs
class LoggingService {
  final Future<Directory> Function() _applicationSupportDirectoryProvider;
  final void Function({String? logDirectory}) _nativeInitWithLogging;
  final void Function() _nativeInit;
  final String? Function() _currentLogFileProvider;

  String? _logDirectory;
  bool _initialized = false;
  Future<void>? _initializationFuture;
  final List<LogEntry> _recentLogs = [];
  static const int _maxRecentLogs = 1000;

  LoggingService({
    Future<Directory> Function()? applicationSupportDirectoryProvider,
    void Function({String? logDirectory})? nativeInitWithLogging,
    void Function()? nativeInit,
    String? Function()? currentLogFileProvider,
  })  : _applicationSupportDirectoryProvider =
            applicationSupportDirectoryProvider ??
                getApplicationSupportDirectory,
        _nativeInitWithLogging =
            nativeInitWithLogging ?? bridge_api.apiInitWithLogging,
        _nativeInit = nativeInit ?? bridge_api.apiInit,
        _currentLogFileProvider =
            currentLogFileProvider ?? bridge_api.apiGetCurrentLogFile;

  /// Initialize logging with file output
  Future<void> initialize() async {
    await ensureInitialized();
  }

  /// Ensure initialization is started exactly once.
  Future<void> ensureInitialized() {
    return _initializationFuture ??= _initializeImpl();
  }

  Future<void> _initializeImpl() async {
    if (_initialized) return;

    try {
      // Get app data directory for logs
      final appDir = await _applicationSupportDirectoryProvider();
      _logDirectory = '${appDir.path}${Platform.pathSeparator}logs';

      // Create logs directory
      final logsDir = Directory(_logDirectory!);
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // Initialize native logging with file output
      _nativeInitWithLogging(logDirectory: _logDirectory);

      _initialized = true;
      log(LogLevel.info, 'Logging service initialized',
          source: 'LoggingService');
      log(LogLevel.info, 'Log directory: $_logDirectory',
          source: 'LoggingService');
    } catch (e) {
      // Fall back to console-only logging
      try {
        _nativeInit();
      } catch (_) {
        // Tests may not have the Rust bridge initialized yet.
      }
      _initialized = true;
      log(LogLevel.warning, 'File logging unavailable: $e',
          source: 'LoggingService');
    }
  }

  /// Get the log directory path
  String? get logDirectory => _logDirectory;

  /// Get the current log file path
  String? get currentLogFile => _initialized ? _currentLogFileProvider() : null;

  /// Log a message
  void log(
    LogLevel level,
    String message, {
    String? source,
    Map<String, Object?>? fields,
  }) {
    if (!_initialized) {
      unawaited(ensureInitialized());
    }

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      source: source,
      fields: fields,
    );

    // Keep recent logs in memory
    _recentLogs.add(entry);
    if (_recentLogs.length > _maxRecentLogs) {
      _recentLogs.removeAt(0);
    }

    // Forward to dart:developer with appropriate severity levels.
    // Level mapping: debug=300, info=500, warning=900, error=1000, critical=1200
    final int devLevel;
    switch (level) {
      case LogLevel.debug:
        devLevel = 300;
      case LogLevel.info:
        devLevel = 500;
      case LogLevel.warning:
        devLevel = 900;
      case LogLevel.error:
        devLevel = 1000;
      case LogLevel.critical:
        devLevel = 1200;
    }
    developer.log(
      entry.toString(),
      name: source ?? 'Nightshade',
      level: devLevel,
    );
  }

  /// Convenience methods
  void debug(String message, {String? source, Map<String, Object?>? fields}) =>
      log(LogLevel.debug, message, source: source, fields: fields);
  void info(String message, {String? source, Map<String, Object?>? fields}) =>
      log(LogLevel.info, message, source: source, fields: fields);
  void warning(
    String message, {
    String? source,
    Map<String, Object?>? fields,
  }) =>
      log(LogLevel.warning, message, source: source, fields: fields);
  void error(String message, {String? source, Map<String, Object?>? fields}) =>
      log(LogLevel.error, message, source: source, fields: fields);
  void critical(
    String message, {
    String? source,
    Map<String, Object?>? fields,
  }) =>
      log(LogLevel.critical, message, source: source, fields: fields);

  /// Get recent logs from memory
  List<LogEntry> getRecentLogs({LogLevel? minLevel}) {
    if (minLevel == null) return List.from(_recentLogs);
    return _recentLogs.where((e) => e.level.index >= minLevel.index).toList();
  }

  /// Get all available log files
  Future<List<String>> getLogFiles() async {
    await ensureInitialized();
    if (_logDirectory == null) return [];

    try {
      final dir = Directory(_logDirectory!);
      if (!await dir.exists()) return [];

      final files = await dir
          .list()
          .where((e) => e is File && e.path.contains('nightshade.log'))
          .map((e) => e.path)
          .toList();

      files.sort(); // Chronological order
      return files;
    } catch (e) {
      return [];
    }
  }

  /// Read a specific log file
  Future<String> readLogFile(String path) async {
    try {
      final file = File(path);
      return await file.readAsString();
    } catch (e) {
      return 'Error reading log file: $e';
    }
  }

  /// Export all logs to a single file
  Future<String> exportLogs(String outputPath) async {
    await ensureInitialized();
    try {
      final output = StringBuffer();
      output.writeln('=== Nightshade Log Export ===');
      output.writeln('Exported: ${DateTime.now().toIso8601String()}');
      output.writeln('Platform: ${Platform.operatingSystem}');
      output.writeln('');

      // Get all log files
      final logFiles = await getLogFiles();

      for (final logFile in logFiles) {
        output.writeln('\n=== $logFile ===\n');
        try {
          final content = await readLogFile(logFile);
          output.writeln(content);
        } catch (e) {
          output.writeln('Error reading file: $e');
        }
      }

      // Write to output file
      final file = File(outputPath);
      await file.writeAsString(output.toString());

      log(LogLevel.info, 'Logs exported to: $outputPath',
          source: 'LoggingService');
      return outputPath;
    } catch (e) {
      throw Exception('Failed to export logs: $e');
    }
  }

  /// Get total size of all log files
  Future<int> getLogSizeBytes() async {
    await ensureInitialized();
    if (_logDirectory == null) return 0;

    try {
      final dir = Directory(_logDirectory!);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('nightshade.log')) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// Clear all log files
  Future<void> clearLogs() async {
    await ensureInitialized();
    if (_logDirectory == null) return;

    try {
      final dir = Directory(_logDirectory!);
      if (!await dir.exists()) return;

      await for (final entity in dir.list()) {
        if (entity is File && entity.path.contains('nightshade.log')) {
          // Don't delete today's log file
          final currentLog = currentLogFile;
          if (currentLog == null || entity.path != currentLog) {
            await entity.delete();
          }
        }
      }

      log(LogLevel.info, 'Old log files cleared', source: 'LoggingService');
    } catch (e) {
      log(LogLevel.error, 'Failed to clear logs: $e', source: 'LoggingService');
    }
  }
}

/// Provider for the logging service
final loggingServiceProvider = Provider<LoggingService>((ref) {
  final service = LoggingService();
  unawaited(service.ensureInitialized());
  return service;
});

/// Provider that initializes logging on first access
final loggingInitializerProvider = FutureProvider<LoggingService>((ref) async {
  final service = ref.watch(loggingServiceProvider);
  await service.initialize();
  return service;
});
