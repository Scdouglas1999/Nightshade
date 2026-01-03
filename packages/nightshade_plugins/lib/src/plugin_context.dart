import 'dart:async';
import 'dart:developer' as developer;

import 'plugin_api.dart';

/// Implementation of PluginLogger that writes to console and developer log
class ConsolePluginLogger implements PluginLogger {
  final String _pluginId;

  /// Creates a console logger for a plugin
  ConsolePluginLogger(this._pluginId);

  @override
  void info(String message) {
    final logMessage = '[$_pluginId] INFO: $message';
    developer.log(logMessage, name: 'Plugin.$_pluginId', level: 800);
    // ignore: avoid_print
    print(logMessage);
  }

  @override
  void debug(String message) {
    final logMessage = '[$_pluginId] DEBUG: $message';
    developer.log(logMessage, name: 'Plugin.$_pluginId', level: 500);
    // Only print debug in debug mode
    assert(() {
      // ignore: avoid_print
      print(logMessage);
      return true;
    }());
  }

  @override
  void warning(String message) {
    final logMessage = '[$_pluginId] WARNING: $message';
    developer.log(logMessage, name: 'Plugin.$_pluginId', level: 900);
    // ignore: avoid_print
    print(logMessage);
  }

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    final logMessage = '[$_pluginId] ERROR: $message';
    developer.log(
      logMessage,
      name: 'Plugin.$_pluginId',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    // ignore: avoid_print
    print(logMessage);
    if (error != null) {
      // ignore: avoid_print
      print('  Error: $error');
    }
    if (stackTrace != null) {
      // ignore: avoid_print
      print('  Stack trace:\n$stackTrace');
    }
  }
}

/// In-memory implementation of PluginStorage
///
/// In a production app, this should be backed by SharedPreferences,
/// SQLite, or another persistent storage mechanism.
class InMemoryPluginStorage implements PluginStorage {
  final Map<String, dynamic> _storage = {};

  @override
  Future<String?> getString(String key) async {
    final value = _storage[key];
    return value is String ? value : null;
  }

  @override
  Future<void> setString(String key, String value) async {
    _storage[key] = value;
  }

  @override
  Future<int?> getInt(String key) async {
    final value = _storage[key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  @override
  Future<void> setInt(String key, int value) async {
    _storage[key] = value;
  }

  @override
  Future<bool?> getBool(String key) async {
    final value = _storage[key];
    if (value is bool) return value;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return null;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    _storage[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _storage.remove(key);
  }

  @override
  Future<Map<String, dynamic>> getAll() async {
    return Map.from(_storage);
  }

  @override
  Future<void> clear() async {
    _storage.clear();
  }
}

/// Stream-based implementation of PluginEventBus
class StreamPluginEventBus implements PluginEventBus {
  final _controller = StreamController<PluginEvent>.broadcast();
  final Map<String, StreamController<Map<String, dynamic>>> _namedControllers = {};

  @override
  void emit(String eventName, [Map<String, dynamic>? data]) {
    final event = PluginEvent(
      name: eventName,
      data: data ?? {},
    );

    // Emit to general stream
    _controller.add(event);

    // Emit to named stream if it exists
    final namedController = _namedControllers[eventName];
    if (namedController != null && !namedController.isClosed) {
      namedController.add(event.data);
    }
  }

  @override
  Stream<Map<String, dynamic>> on(String eventName) {
    // Create a controller for this event name if it doesn't exist
    if (!_namedControllers.containsKey(eventName)) {
      _namedControllers[eventName] = StreamController<Map<String, dynamic>>.broadcast();
    }
    return _namedControllers[eventName]!.stream;
  }

  @override
  Stream<PluginEvent> onAny() {
    return _controller.stream;
  }

  /// Dispose of all stream controllers
  void dispose() {
    _controller.close();
    for (final controller in _namedControllers.values) {
      controller.close();
    }
    _namedControllers.clear();
  }
}

/// Factory for creating plugin contexts
class PluginContextFactory {
  final StreamPluginEventBus _eventBus = StreamPluginEventBus();

  /// Create a context for a specific plugin
  PluginContext createContext(String pluginId) {
    return PluginContext(
      logger: ConsolePluginLogger(pluginId),
      storage: InMemoryPluginStorage(),
      eventBus: _eventBus,
    );
  }

  /// Dispose of shared resources
  void dispose() {
    _eventBus.dispose();
  }
}
