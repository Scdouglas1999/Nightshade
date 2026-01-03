/// Nightshade Plugins - Plugin host and API
///
/// This library provides the plugin system for Nightshade, allowing users
/// to extend the application with custom functionality.
///
/// ## Core Components
///
/// - [NightshadePlugin] - Base interface all plugins must implement
/// - [PluginContext] - Provides access to app services (logging, storage, events)
/// - [PluginHost] - Manages plugin lifecycle and registration
///
/// ## Plugin Types
///
/// - [UiPlugin] - Add custom UI panels and widgets
/// - [DevicePlugin] - Support additional hardware devices
/// - [SequencePlugin] - Add custom automation sequence nodes
///
/// ## Example Usage
///
/// ```dart
/// class MyPlugin extends NightshadePlugin {
///   @override
///   String get id => 'com.example.myplugin';
///
///   @override
///   String get name => 'My Plugin';
///
///   @override
///   String get version => '1.0.0';
///
///   @override
///   String get description => 'Does something cool';
///
///   @override
///   String get author => 'Me';
///
///   @override
///   Future<void> onLoad(PluginContext context) async {
///     context.logger.info('Plugin loaded!');
///   }
///
///   @override
///   Future<void> onUnload() async {
///     // Clean up resources
///   }
/// }
///
/// // Register plugin
/// await pluginHost.registerPlugin(MyPlugin());
/// ```
library nightshade_plugins;

// Core plugin API
export 'src/plugin_api.dart';

// Plugin host and lifecycle management
export 'src/plugin_host.dart';

// Plugin context implementations
export 'src/plugin_context.dart';

// Example plugins demonstrating the API
export 'src/example_plugin.dart';





