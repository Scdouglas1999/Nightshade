import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as path;
import 'plugin_api.dart';

/// Implementation of PluginLogger that writes to console and developer log
class ConsolePluginLogger implements PluginLogger {
  final String _pluginId;

  /// Creates a console logger for a plugin
  ConsolePluginLogger(this._pluginId);

  @override
  void info(String message) {
    developer.log(message, name: 'Plugin.$_pluginId', level: 800);
  }

  @override
  void debug(String message) {
    developer.log(message, name: 'Plugin.$_pluginId', level: 500);
  }

  @override
  void warning(String message) {
    developer.log(message, name: 'Plugin.$_pluginId', level: 900);
  }

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: 'Plugin.$_pluginId',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
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

/// File-backed implementation of [PluginStorage].
///
/// Data is stored per-plugin in the application support directory and written
/// atomically so plugin settings survive app restarts and partial writes.
class FilePluginStorage implements PluginStorage {
  final String _pluginId;
  final Future<Directory> Function() _baseDirectoryProvider;

  Map<String, dynamic>? _storage;
  Future<void>? _loadFuture;

  /// Creates persistent storage for [pluginId].
  ///
  /// [baseDirectoryProvider] is primarily intended for tests.
  FilePluginStorage(
    this._pluginId, {
    Future<Directory> Function()? baseDirectoryProvider,
  }) : _baseDirectoryProvider =
            baseDirectoryProvider ?? _defaultPluginStorageDirectory;

  Future<File> _getStorageFile() async {
    final baseDir = await _baseDirectoryProvider();
    final pluginsDir =
        Directory(path.join(baseDir.path, 'nightshade_plugins', 'storage'));
    if (!await pluginsDir.exists()) {
      await pluginsDir.create(recursive: true);
    }
    return File(path.join(pluginsDir.path, '$_pluginId.json'));
  }

  Future<void> _ensureLoaded() async {
    _loadFuture ??= _load();
    await _loadFuture;
  }

  Future<void> _load() async {
    final file = await _getStorageFile();
    if (!await file.exists()) {
      _storage = <String, dynamic>{};
      return;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        _storage = <String, dynamic>{};
        return;
      }
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        _storage = Map<String, dynamic>.from(decoded);
      } else {
        throw const FormatException('Plugin storage root must be an object');
      }
    } catch (e, stackTrace) {
      developer.log(
        'Failed to load plugin storage for $_pluginId, resetting storage',
        name: 'Plugin.$_pluginId',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
      _storage = <String, dynamic>{};
    }
  }

  Future<void> _persist() async {
    final file = await _getStorageFile();
    final tempFile = File('${file.path}.tmp');
    final encoded = jsonEncode(_storage ?? const <String, dynamic>{});

    await tempFile.writeAsString(encoded, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  @override
  Future<String?> getString(String key) async {
    await _ensureLoaded();
    final value = _storage![key];
    return value is String ? value : null;
  }

  @override
  Future<void> setString(String key, String value) async {
    await _ensureLoaded();
    _storage![key] = value;
    await _persist();
  }

  @override
  Future<int?> getInt(String key) async {
    await _ensureLoaded();
    final value = _storage![key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  @override
  Future<void> setInt(String key, int value) async {
    await _ensureLoaded();
    _storage![key] = value;
    await _persist();
  }

  @override
  Future<bool?> getBool(String key) async {
    await _ensureLoaded();
    final value = _storage![key];
    if (value is bool) return value;
    if (value is String) {
      if (value.toLowerCase() == 'true') return true;
      if (value.toLowerCase() == 'false') return false;
    }
    return null;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _ensureLoaded();
    _storage![key] = value;
    await _persist();
  }

  @override
  Future<void> remove(String key) async {
    await _ensureLoaded();
    _storage!.remove(key);
    await _persist();
  }

  @override
  Future<Map<String, dynamic>> getAll() async {
    await _ensureLoaded();
    return Map<String, dynamic>.from(_storage!);
  }

  @override
  Future<void> clear() async {
    await _ensureLoaded();
    _storage!.clear();
    await _persist();
  }
}

Future<Directory> _defaultPluginStorageDirectory() async {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      Directory.current.path;

  if (Platform.isWindows) {
    final appData = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        path.join(home, 'AppData', 'Local');
    return Directory(path.join(appData, 'Nightshade'));
  }

  if (Platform.isMacOS) {
    return Directory(path.join(home, 'Library', 'Application Support', 'Nightshade'));
  }

  final xdgDataHome =
      Platform.environment['XDG_DATA_HOME'] ?? path.join(home, '.local', 'share');
  return Directory(path.join(xdgDataHome, 'nightshade'));
}

/// Stream-based implementation of PluginEventBus
class StreamPluginEventBus implements PluginEventBus {
  final _controller = StreamController<PluginEvent>.broadcast();
  final Map<String, StreamController<Map<String, dynamic>>> _namedControllers = {};
  bool _disposed = false;

  @override
  void emit(String eventName, [Map<String, dynamic>? data]) {
    if (_disposed || _controller.isClosed) {
      return;
    }
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
    if (_disposed) {
      return Stream.error(
          StateError('Plugin event bus has been disposed and cannot be reused'));
    }
    final controller = _namedControllers.putIfAbsent(
      eventName,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );
    return controller.stream;
  }

  @override
  Stream<PluginEvent> onAny() {
    return _controller.stream;
  }

  /// Dispose of all stream controllers
  void dispose() {
    _disposed = true;
    _controller.close();
    for (final controller in _namedControllers.values) {
      controller.close();
    }
    _namedControllers.clear();
  }
}

/// Resource limits enforced for plugin-provided event access.
class PluginSandboxPolicy {
  final int maxEventPayloadBytes;
  final int maxNamedSubscriptions;
  final bool allowGlobalSubscriptions;

  const PluginSandboxPolicy({
    this.maxEventPayloadBytes = 16 * 1024,
    this.maxNamedSubscriptions = 32,
    this.allowGlobalSubscriptions = false,
  });
}

/// Event bus wrapper that applies basic sandboxing limits per plugin.
class SandboxedPluginEventBus implements PluginEventBus {
  final String _pluginId;
  final PluginEventBus _inner;
  final PluginSandboxPolicy _policy;
  int _subscriptionCount = 0;

  SandboxedPluginEventBus(
    this._pluginId,
    this._inner, {
    PluginSandboxPolicy policy = const PluginSandboxPolicy(),
  }) : _policy = policy;

  @override
  void emit(String eventName, [Map<String, dynamic>? data]) {
    _validateEventName(eventName);
    final payload = data ?? const <String, dynamic>{};
    final encoded = jsonEncode(payload);
    if (encoded.length > _policy.maxEventPayloadBytes) {
      throw PluginException(
        'Plugin $_pluginId emitted an event payload larger than '
        '${_policy.maxEventPayloadBytes} bytes',
      );
    }
    _inner.emit(eventName, payload);
  }

  @override
  Stream<Map<String, dynamic>> on(String eventName) {
    _validateEventName(eventName);
    _subscriptionCount++;
    if (_subscriptionCount > _policy.maxNamedSubscriptions) {
      throw PluginException(
        'Plugin $_pluginId exceeded the event subscription limit '
        '(${_policy.maxNamedSubscriptions})',
      );
    }
    return _inner.on(eventName);
  }

  @override
  Stream<PluginEvent> onAny() {
    if (!_policy.allowGlobalSubscriptions) {
      throw PluginException(
        'Plugin $_pluginId is not permitted to subscribe to the global event bus',
      );
    }
    return _inner.onAny();
  }

  void _validateEventName(String eventName) {
    if (eventName.trim().isEmpty) {
      throw PluginException('Plugin $_pluginId emitted or subscribed to an empty event name');
    }
    if (eventName.length > 128) {
      throw PluginException('Plugin $_pluginId used an event name longer than 128 characters');
    }
  }
}

/// Factory for creating plugin contexts
class PluginContextFactory {
  final StreamPluginEventBus _eventBus = StreamPluginEventBus();
  final PluginSandboxPolicy _policy;

  PluginContextFactory({
    PluginSandboxPolicy policy = const PluginSandboxPolicy(),
  }) : _policy = policy;

  /// Create a context for a specific plugin
  PluginContext createContext(String pluginId) {
    return PluginContext(
      logger: ConsolePluginLogger(pluginId),
      storage: FilePluginStorage(pluginId),
      eventBus: SandboxedPluginEventBus(pluginId, _eventBus, policy: _policy),
    );
  }

  /// Dispose of shared resources
  void dispose() {
    _eventBus.dispose();
  }
}
