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

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.source,
  });

  @override
  String toString() {
    final levelStr = level.name.toUpperCase().padRight(8);
    final sourceStr = source != null ? '[$source] ' : '';
    return '${timestamp.toIso8601String()} $levelStr $sourceStr$message';
  }
}

/// Service for managing application logs
class LoggingService {
  String? _logDirectory;
  bool _initialized = false;
  final List<LogEntry> _recentLogs = [];
  static const int _maxRecentLogs = 1000;

  /// Initialize logging with file output
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Get app data directory for logs
      final appDir = await getApplicationSupportDirectory();
      _logDirectory = '${appDir.path}${Platform.pathSeparator}logs';

      // Create logs directory
      final logsDir = Directory(_logDirectory!);
      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      // Initialize native logging with file output
      bridge_api.apiInitWithLogging(logDirectory: _logDirectory);

      _initialized = true;
      log(LogLevel.info, 'Logging service initialized', source: 'LoggingService');
      log(LogLevel.info, 'Log directory: $_logDirectory', source: 'LoggingService');
    } catch (e) {
      // Fall back to console-only logging
      bridge_api.apiInit();
      _initialized = true;
      log(LogLevel.warning, 'File logging unavailable: $e', source: 'LoggingService');
    }
  }

  /// Get the log directory path
  String? get logDirectory => _logDirectory;

  /// Get the current log file path
  String? get currentLogFile => bridge_api.apiGetCurrentLogFile();

  /// Log a message
  void log(LogLevel level, String message, {String? source}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      source: source,
    );

    // Keep recent logs in memory
    _recentLogs.add(entry);
    if (_recentLogs.length > _maxRecentLogs) {
      _recentLogs.removeAt(0);
    }

    // Also log to native (which handles file output)
    switch (level) {
      case LogLevel.debug:
        // Debug logs go to tracing::debug in Rust
        break;
      case LogLevel.info:
        // Info logs go to tracing::info in Rust
        break;
      case LogLevel.warning:
        // Warning logs go to tracing::warn in Rust
        break;
      case LogLevel.error:
      case LogLevel.critical:
        // Error logs go to tracing::error in Rust
        break;
    }
  }

  /// Convenience methods
  void debug(String message, {String? source}) => log(LogLevel.debug, message, source: source);
  void info(String message, {String? source}) => log(LogLevel.info, message, source: source);
  void warning(String message, {String? source}) => log(LogLevel.warning, message, source: source);
  void error(String message, {String? source}) => log(LogLevel.error, message, source: source);
  void critical(String message, {String? source}) => log(LogLevel.critical, message, source: source);

  /// Get recent logs from memory
  List<LogEntry> getRecentLogs({LogLevel? minLevel}) {
    if (minLevel == null) return List.from(_recentLogs);
    return _recentLogs.where((e) => e.level.index >= minLevel.index).toList();
  }

  /// Get all available log files
  Future<List<String>> getLogFiles() async {
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

      log(LogLevel.info, 'Logs exported to: $outputPath', source: 'LoggingService');
      return outputPath;
    } catch (e) {
      throw Exception('Failed to export logs: $e');
    }
  }

  /// Get total size of all log files
  Future<int> getLogSizeBytes() async {
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
  return LoggingService();
});

/// Provider that initializes logging on first access
final loggingInitializerProvider = FutureProvider<LoggingService>((ref) async {
  final service = ref.watch(loggingServiceProvider);
  await service.initialize();
  return service;
});
