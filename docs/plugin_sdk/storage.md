# Plugin Storage

The `PluginStorage` interface provides persistent key-value storage scoped to each plugin. Each plugin gets its own isolated storage namespace -- keys from one plugin never conflict with keys from another.

## Supported Types

| Type | Getter | Setter |
|------|--------|--------|
| `String` | `getString(key)` | `setString(key, value)` |
| `int` | `getInt(key)` | `setInt(key, value)` |
| `bool` | `getBool(key)` | `setBool(key, value)` |

All getters return `Future<T?>` -- they return `null` if the key doesn't exist or the stored value is not of the expected type.

## Basic Usage

### Storing and Retrieving Values

```dart
// Store values
await context.storage.setString('apiEndpoint', 'https://api.example.com');
await context.storage.setInt('pollingInterval', 30);
await context.storage.setBool('enabled', true);

// Retrieve values
final endpoint = await context.storage.getString('apiEndpoint');
final interval = await context.storage.getInt('pollingInterval');
final enabled = await context.storage.getBool('enabled');
```

### Removing Values

```dart
// Remove a single key
await context.storage.remove('apiEndpoint');

// Clear all plugin storage
await context.storage.clear();
```

### Listing All Values

```dart
final allData = await context.storage.getAll();
for (final entry in allData.entries) {
  context.logger.debug('${entry.key} = ${entry.value}');
}
```

## Common Patterns

### Storing Complex Data as JSON

For data types beyond string/int/bool, serialize to JSON:

```dart
import 'dart:convert';

// Store a list
final targets = ['M31', 'M42', 'NGC 7000'];
await context.storage.setString('targets', jsonEncode(targets));

// Retrieve the list
final targetsJson = await context.storage.getString('targets');
if (targetsJson != null) {
  final decoded = jsonDecode(targetsJson) as List;
  final targetsList = decoded.cast<String>();
}

// Store a map
final config = {'minAltitude': 30.0, 'maxExposure': 300};
await context.storage.setString('config', jsonEncode(config));

// Retrieve the map
final configJson = await context.storage.getString('config');
if (configJson != null) {
  final configMap = jsonDecode(configJson) as Map<String, dynamic>;
}
```

### Saving State on Disable

Save plugin state when the user disables the plugin so it can be restored on re-enable:

```dart
@override
Future<void> onDisable() async {
  await _context?.storage.setInt('counter', _counter);
  await _context?.storage.setString(
    'lastDisabled',
    DateTime.now().toIso8601String(),
  );
}

@override
Future<void> onEnable() async {
  final savedCounter = await _context?.storage.getInt('counter');
  if (savedCounter != null) {
    _counter = savedCounter;
  }
}
```

### Default Values

Since getters return `null` for missing keys, use the null-coalescing operator for defaults:

```dart
final interval = await context.storage.getInt('pollingInterval') ?? 30;
final endpoint = await context.storage.getString('apiEndpoint') ?? 'https://default.example.com';
final autoStart = await context.storage.getBool('autoStart') ?? true;
```

### Versioned Storage Migration

When your plugin changes its storage schema between versions, use a version key to migrate:

```dart
@override
Future<void> onLoad(PluginContext context) async {
  _context = context;

  final storedVersion = await context.storage.getInt('storageVersion') ?? 0;

  if (storedVersion < 1) {
    // Migration from v0 to v1: rename key
    final oldValue = await context.storage.getString('api_url');
    if (oldValue != null) {
      await context.storage.setString('apiEndpoint', oldValue);
      await context.storage.remove('api_url');
    }
  }

  if (storedVersion < 2) {
    // Migration from v1 to v2: add default for new key
    final existing = await context.storage.getInt('pollingInterval');
    if (existing == null) {
      await context.storage.setInt('pollingInterval', 30);
    }
  }

  // Mark current version
  await context.storage.setInt('storageVersion', 2);
}
```

## Implementation Notes

The default `InMemoryPluginStorage` implementation stores data in a Dart `Map<String, dynamic>`. This means data does **not** persist across application restarts.

For production use, the plugin host should supply a `PluginStorage` implementation backed by persistent storage (SharedPreferences, SQLite via Drift, or the filesystem). The `PluginContextFactory` can be subclassed to provide different storage backends:

```dart
class PersistentContextFactory extends PluginContextFactory {
  final Database _db;

  PersistentContextFactory(this._db);

  @override
  PluginContext createContext(String pluginId) {
    return PluginContext(
      logger: ConsolePluginLogger(pluginId),
      storage: DatabasePluginStorage(_db, pluginId),
      eventBus: _eventBus,
    );
  }
}
```
