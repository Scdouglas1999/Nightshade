import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'plugin_api.dart';
import 'plugin_context.dart';

/// Represents a loaded plugin with its state
class LoadedPlugin {
  /// The plugin instance
  final NightshadePlugin plugin;

  /// Plugin context providing access to app services
  final PluginContext context;

  /// Whether the plugin is currently enabled
  final bool enabled;

  /// Timestamp when plugin was loaded
  final DateTime loadedAt;

  /// Error that occurred during plugin operation, if any
  final String? error;

  /// Creates a loaded plugin entry
  LoadedPlugin({
    required this.plugin,
    required this.context,
    required this.enabled,
    DateTime? loadedAt,
    this.error,
  }) : loadedAt = loadedAt ?? DateTime.now();

  /// Create a copy with updated fields
  LoadedPlugin copyWith({
    bool? enabled,
    String? error,
  }) {
    return LoadedPlugin(
      plugin: plugin,
      context: context,
      enabled: enabled ?? this.enabled,
      loadedAt: loadedAt,
      error: error ?? this.error,
    );
  }
}

/// Plugin information for UI display
class PluginInfo {
  /// Unique plugin identifier
  final String id;

  /// Human-readable name
  final String name;

  /// Version string
  final String version;

  /// Plugin description
  final String description;

  /// Plugin author
  final String author;

  /// Whether plugin is enabled
  final bool enabled;

  /// When plugin was loaded
  final DateTime loadedAt;

  /// Error message if plugin failed
  final String? error;

  /// Creates plugin info
  const PluginInfo({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.enabled,
    required this.loadedAt,
    this.error,
  });
}

/// Plugin host - manages loading and lifecycle of plugins
///
/// This is the central registry for all plugins. It handles:
/// - Plugin registration and unregistration
/// - Enable/disable state management
/// - Plugin lifecycle callbacks (load, enable, disable, unload)
/// - Error handling and recovery
class PluginHost {
  final Map<String, LoadedPlugin> _plugins = {};
  final PluginContextFactory _contextFactory = PluginContextFactory();

  /// Get all loaded plugins
  List<NightshadePlugin> get plugins =>
      _plugins.values.map((p) => p.plugin).toList();

  /// Get plugin information for UI display
  List<PluginInfo> get pluginInfo {
    return _plugins.values.map((loaded) {
      final plugin = loaded.plugin;
      return PluginInfo(
        id: plugin.id,
        name: plugin.name,
        version: plugin.version,
        description: plugin.description,
        author: plugin.author,
        enabled: loaded.enabled,
        loadedAt: loaded.loadedAt,
        error: loaded.error,
      );
    }).toList();
  }

  /// Get plugins of a specific type
  List<T> getPlugins<T extends NightshadePlugin>() {
    return _plugins.values
        .where((p) => p.enabled && p.plugin is T)
        .map((p) => p.plugin as T)
        .toList();
  }

  /// Get a plugin by ID
  NightshadePlugin? getPlugin(String pluginId) {
    return _plugins[pluginId]?.plugin;
  }

  /// Check if a plugin is loaded
  bool isLoaded(String pluginId) {
    return _plugins.containsKey(pluginId);
  }

  /// Check if a plugin is enabled
  bool isEnabled(String pluginId) {
    return _plugins[pluginId]?.enabled ?? false;
  }

  /// Register a plugin
  ///
  /// Loads the plugin and calls its [onLoad] lifecycle method.
  /// The plugin starts in enabled state by default.
  ///
  /// Throws [PluginException] if:
  /// - Plugin ID already registered
  /// - Plugin loading fails
  Future<void> registerPlugin(
    NightshadePlugin plugin, {
    bool enabled = true,
  }) async {
    if (_plugins.containsKey(plugin.id)) {
      throw PluginException(
        'Plugin ${plugin.id} is already registered',
      );
    }

    final context = _contextFactory.createContext(plugin.id);

    try {
      // Call onLoad lifecycle method
      await plugin.onLoad(context);

      // Store loaded plugin
      _plugins[plugin.id] = LoadedPlugin(
        plugin: plugin,
        context: context,
        enabled: enabled,
      );

      // Call onEnable if starting enabled
      if (enabled) {
        await plugin.onEnable();
      }

      context.logger.info('Plugin registered successfully');
    } catch (e, stackTrace) {
      context.logger.error('Failed to register plugin', e, stackTrace);

      // Store plugin with error state
      _plugins[plugin.id] = LoadedPlugin(
        plugin: plugin,
        context: context,
        enabled: false,
        error: e.toString(),
      );

      throw PluginException('Failed to register plugin ${plugin.id}', e);
    }
  }

  /// Unregister a plugin
  ///
  /// Disables the plugin if enabled, then unloads it by calling [onUnload].
  Future<void> unregisterPlugin(String pluginId) async {
    final loaded = _plugins[pluginId];
    if (loaded == null) return;

    try {
      // Disable if enabled
      if (loaded.enabled) {
        await loaded.plugin.onDisable();
      }

      // Unload plugin
      await loaded.plugin.onUnload();

      loaded.context.logger.info('Plugin unregistered successfully');
    } catch (e, stackTrace) {
      loaded.context.logger.error('Error unregistering plugin', e, stackTrace);
      // Continue with removal even if unload fails
    } finally {
      _plugins.remove(pluginId);
    }
  }

  /// Set plugin enabled state
  ///
  /// Calls [onEnable] when enabling or [onDisable] when disabling.
  ///
  /// Returns true if state was changed, false otherwise.
  Future<bool> setPluginEnabled(String pluginId, bool enabled) async {
    final loaded = _plugins[pluginId];
    if (loaded == null) {
      throw PluginException('Plugin $pluginId not found');
    }

    // No change needed
    if (loaded.enabled == enabled) {
      return false;
    }

    try {
      if (enabled) {
        await loaded.plugin.onEnable();
        loaded.context.logger.info('Plugin enabled');
      } else {
        await loaded.plugin.onDisable();
        loaded.context.logger.info('Plugin disabled');
      }

      // Update state
      _plugins[pluginId] = loaded.copyWith(enabled: enabled, error: null);
      return true;
    } catch (e, stackTrace) {
      loaded.context.logger.error(
        'Failed to ${enabled ? 'enable' : 'disable'} plugin',
        e,
        stackTrace,
      );

      // Update with error state
      _plugins[pluginId] = loaded.copyWith(error: e.toString());

      throw PluginException(
        'Failed to ${enabled ? 'enable' : 'disable'} plugin $pluginId',
        e,
      );
    }
  }

  /// Dispose all plugins and release resources
  ///
  /// Unregisters all plugins in reverse order of registration.
  Future<void> dispose() async {
    final pluginIds = _plugins.keys.toList().reversed;

    for (final pluginId in pluginIds) {
      try {
        await unregisterPlugin(pluginId);
      } catch (e) {
        // Log but continue disposing other plugins
        developer.log('Error disposing plugin $pluginId: $e', name: 'PluginHost', level: 1000);
      }
    }

    _contextFactory.dispose();
    _plugins.clear();
  }
}

/// Plugin host provider
final pluginHostProvider = Provider<PluginHost>((ref) {
  final host = PluginHost();
  ref.onDispose(() => host.dispose());
  return host;
});

/// UI extension points provider
final uiExtensionPointsProvider = Provider<List<UiExtensionPoint>>((ref) {
  final host = ref.watch(pluginHostProvider);
  return host.getPlugins<UiPlugin>()
      .expand((p) => p.extensionPoints)
      .toList();
});





