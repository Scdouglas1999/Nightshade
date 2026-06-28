import 'dart:developer' as developer;
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'plugin_api.dart';
import 'plugin_context.dart';
import 'plugin_node_registry.dart';

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
  LoadedPlugin copyWith({bool? enabled, String? error}) {
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
  final PluginContextFactory _contextFactory;
  final Duration _lifecycleTimeout;

  /// Registry of plugin-contributed sequence node definitions. Populated
  /// automatically when a [SequencePlugin] is registered + enabled; emptied
  /// when the plugin is unregistered or disabled.
  ///
  /// Consumers (sequence editor palette, sequence executor dispatch) read
  /// from this registry — there is intentionally NO separate "register
  /// node" API for plugin authors. Authoring a node = exposing it from
  /// `SequencePlugin.nodeDefinitions`.
  final PluginNodeRegistry nodeRegistry;

  PluginHost({
    PluginContextFactory? contextFactory,
    Duration lifecycleTimeout = const Duration(seconds: 5),
    PluginNodeRegistry? nodeRegistry,
  }) : _contextFactory = contextFactory ?? PluginContextFactory(),
       _lifecycleTimeout = lifecycleTimeout,
       nodeRegistry = nodeRegistry ?? PluginNodeRegistry();

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

  /// Return the live [PluginContext] associated with [pluginId], or `null`
  /// if no such plugin is registered. Plugin nodes use this to access the
  /// same logger / storage / event bus their owning plugin sees during
  /// lifecycle callbacks.
  PluginContext? contextFor(String pluginId) {
    return _plugins[pluginId]?.context;
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
      throw PluginException('Plugin ${plugin.id} is already registered');
    }

    final context = _contextFactory.createContext(plugin.id);

    try {
      // Call onLoad lifecycle method
      await _runLifecycle(
        plugin,
        context,
        'onLoad',
        () => plugin.onLoad(context),
      );

      // Store loaded plugin
      _plugins[plugin.id] = LoadedPlugin(
        plugin: plugin,
        context: context,
        enabled: enabled,
      );

      // Call onEnable if starting enabled
      if (enabled) {
        await _runLifecycle(plugin, context, 'onEnable', plugin.onEnable);
        // Wire sequence-plugin nodes into the registry as soon as the
        // plugin is enabled. SequenceNodeDefinition.createNode is the
        // contract — we DON'T pre-instantiate nodes, just expose the
        // factories so the sequence executor can build instances later.
        if (plugin is SequencePlugin) {
          nodeRegistry.registerSequencePlugin(plugin);
        }
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

    // Drop sequence-node registrations BEFORE running onDisable so any
    // in-flight palette / executor lookups see a consistent state during
    // teardown. A late-firing executor that grabs a registration just
    // before unregister will still find the node in the host's plugin
    // map (the registration is purely a "is this node available right
    // now?" cache).
    nodeRegistry.unregisterPlugin(pluginId);

    try {
      // Disable if enabled
      if (loaded.enabled) {
        await _runLifecycle(
          loaded.plugin,
          loaded.context,
          'onDisable',
          loaded.plugin.onDisable,
        );
      }

      // Unload plugin
      await _runLifecycle(
        loaded.plugin,
        loaded.context,
        'onUnload',
        loaded.plugin.onUnload,
      );

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
        await _runLifecycle(
          loaded.plugin,
          loaded.context,
          'onEnable',
          loaded.plugin.onEnable,
        );
        // Re-publish sequence nodes when a previously-disabled plugin
        // is re-enabled. We do this AFTER onEnable returns so the
        // plugin's own context is in the enabled state by the time
        // the executor could resolve and run one of its nodes.
        if (loaded.plugin is SequencePlugin) {
          nodeRegistry.registerSequencePlugin(loaded.plugin as SequencePlugin);
        }
        loaded.context.logger.info('Plugin enabled');
      } else {
        // Yank registrations BEFORE onDisable so a late palette refresh
        // doesn't show ghost entries for a plugin that's halfway through
        // releasing resources.
        nodeRegistry.unregisterPlugin(pluginId);
        await _runLifecycle(
          loaded.plugin,
          loaded.context,
          'onDisable',
          loaded.plugin.onDisable,
        );
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
        developer.log(
          'Error disposing plugin $pluginId: $e',
          name: 'PluginHost',
          level: 1000,
        );
      }
    }

    _contextFactory.dispose();
    _plugins.clear();
    nodeRegistry.dispose();
  }

  Future<void> _runLifecycle(
    NightshadePlugin plugin,
    PluginContext context,
    String phase,
    Future<void> Function() action,
  ) async {
    final completer = Completer<void>();

    unawaited(
      runZonedGuarded(
        () async {
          try {
            await action();
            if (!completer.isCompleted) {
              completer.complete();
            }
          } catch (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        },
        (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );

    try {
      await completer.future.timeout(_lifecycleTimeout);
    } on TimeoutException catch (error) {
      context.logger.error('Plugin lifecycle timed out during $phase', error);
      throw PluginException(
        'Plugin ${plugin.id} timed out during $phase after '
        '${_lifecycleTimeout.inSeconds}s',
        error,
      );
    }
  }
}

/// Plugin host provider
final pluginHostProvider = Provider<PluginHost>((ref) {
  final host = PluginHost();
  ref.onDispose(() => host.dispose());
  return host;
});

/// Plugin sequence-node registry provider. Exposed at the package level so
/// the sequence editor (palette) and the sequence executor (dispatch) can
/// resolve plugin-contributed nodes without depending on the host directly.
final pluginNodeRegistryProvider = Provider<PluginNodeRegistry>((ref) {
  final host = ref.watch(pluginHostProvider);
  return host.nodeRegistry;
});

/// Stream of registry changes. Useful for editor widgets that want to keep
/// a live "available plugin nodes" listing in sync as the user installs /
/// enables / disables plugins.
final pluginNodeRegistrationsStreamProvider =
    StreamProvider<List<PluginNodeRegistration>>((ref) {
      final registry = ref.watch(pluginNodeRegistryProvider);
      // Seed the stream with the current snapshot so a subscriber attached
      // after registration still observes the existing entries on first build.
      return Stream<List<PluginNodeRegistration>>.value(
        registry.registrations,
      ).asyncExpand((seed) async* {
        yield seed;
        yield* registry.changes;
      });
    });
