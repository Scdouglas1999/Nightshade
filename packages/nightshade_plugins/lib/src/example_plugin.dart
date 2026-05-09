import 'dart:async';

import 'plugin_api.dart';

/// Example plugin demonstrating the Nightshade plugin API
///
/// This plugin shows how to:
/// - Implement the NightshadePlugin interface
/// - Use the PluginContext for logging, storage, and events
/// - Handle lifecycle callbacks
/// - Store and retrieve persistent data
/// - Emit and subscribe to events
class ExamplePlugin extends NightshadePlugin {
  PluginContext? _context;
  StreamSubscription? _eventSubscription;
  int _counter = 0;

  @override
  String get id => 'com.nightshade.example';

  @override
  String get name => 'Example Plugin';

  @override
  String get version => '1.0.0';

  @override
  String get description =>
      'Demonstrates the plugin API with logging, storage, and events';

  @override
  String get author => 'Nightshade Team';

  @override
  String? get minAppVersion => '2.0.0';

  @override
  Future<void> onLoad(PluginContext context) async {
    _context = context;
    context.logger.info('Example plugin loading...');

    // Load persistent counter value
    final savedCounter = await context.storage.getInt('counter');
    if (savedCounter != null) {
      _counter = savedCounter;
      context.logger.info('Restored counter value: $_counter');
    }

    // Subscribe to events
    _eventSubscription = context.eventBus.on('app.ready').listen((data) {
      context.logger.info('Received app.ready event: $data');
    });

    context.logger.info('Example plugin loaded successfully');
  }

  @override
  Future<void> onEnable() async {
    _context?.logger.info('Example plugin enabled');

    // Emit an event when enabled
    _context?.eventBus.emit('plugin.example.enabled', {
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> onDisable() async {
    _context?.logger.info('Example plugin disabled');

    // Save state before disabling
    await _context?.storage.setInt('counter', _counter);

    // Emit an event when disabled
    _context?.eventBus.emit('plugin.example.disabled', {
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<void> onUnload() async {
    _context?.logger.info('Example plugin unloading...');

    // Cancel event subscription
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    // Save final state
    await _context?.storage.setInt('counter', _counter);

    _context?.logger.info('Example plugin unloaded');
    _context = null;
  }

  /// Increment the internal counter and save to storage
  Future<void> incrementCounter() async {
    _counter++;
    _context?.logger.debug('Counter incremented to $_counter');

    await _context?.storage.setInt('counter', _counter);

    // Emit event about counter change
    _context?.eventBus.emit('plugin.example.counter', {
      'value': _counter,
    });
  }

  /// Get the current counter value
  int get counter => _counter;

  /// Reset the counter
  Future<void> resetCounter() async {
    _counter = 0;
    _context?.logger.info('Counter reset to 0');

    await _context?.storage.setInt('counter', 0);

    _context?.eventBus.emit('plugin.example.counter', {
      'value': 0,
    });
  }
}

/// Example UI plugin showing how to add custom panels
///
/// This demonstrates the UiPlugin interface for adding UI extensions.
class ExampleUiPlugin extends UiPlugin {
  PluginContext? _context;

  @override
  String get id => 'com.nightshade.example.ui';

  @override
  String get name => 'Example UI Plugin';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Adds example UI panels to demonstrate UI extensions';

  @override
  String get author => 'Nightshade Team';

  @override
  Future<void> onLoad(PluginContext context) async {
    _context = context;
    context.logger.info('Example UI plugin loaded');
  }

  @override
  Future<void> onUnload() async {
    _context?.logger.info('Example UI plugin unloaded');
    _context = null;
  }

  @override
  List<UiExtensionPoint> get extensionPoints => [
        UiExtensionPoint(
          type: UiExtensionPointType.equipmentPanel,
          title: 'Example Equipment Panel',
          widgetBuilder: () {
            // Example plugin intentionally does not provide a concrete widget.
            return null;
          },
        ),
        UiExtensionPoint(
          type: UiExtensionPointType.statusBar,
          title: 'Example Status',
          widgetBuilder: () {
            return null;
          },
        ),
      ];
}

/// Example device plugin showing how to add hardware support
///
/// This demonstrates the DevicePlugin interface for adding custom device drivers.
class ExampleDevicePlugin extends DevicePlugin {
  PluginContext? _context;

  @override
  String get id => 'com.nightshade.example.device';

  @override
  String get name => 'Example Device Plugin';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Adds support for example hardware devices';

  @override
  String get author => 'Nightshade Team';

  @override
  Future<void> onLoad(PluginContext context) async {
    _context = context;
    context.logger.info('Example device plugin loaded');

    // In a real device plugin, you would:
    // - Initialize device SDK
    // - Scan for connected devices
    // - Register device drivers
  }

  @override
  Future<void> onUnload() async {
    _context?.logger.info('Example device plugin unloaded');

    // In a real device plugin, you would:
    // - Disconnect from devices
    // - Clean up SDK resources
    // - Unregister device drivers

    _context = null;
  }

  @override
  List<DevicePluginType> get supportedDevices => [
        DevicePluginType.camera,
        DevicePluginType.focuser,
      ];
}

/// Example sequence plugin showing how to add custom sequence nodes
///
/// This demonstrates the SequencePlugin interface for extending the sequencer.
class ExampleSequencePlugin extends SequencePlugin {
  PluginContext? _context;

  @override
  String get id => 'com.nightshade.example.sequence';

  @override
  String get name => 'Example Sequence Plugin';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Adds custom sequence nodes for automation';

  @override
  String get author => 'Nightshade Team';

  @override
  Future<void> onLoad(PluginContext context) async {
    _context = context;
    context.logger.info('Example sequence plugin loaded');
  }

  @override
  Future<void> onUnload() async {
    _context?.logger.info('Example sequence plugin unloaded');
    _context = null;
  }

  @override
  List<SequenceNodeDefinition> get nodeDefinitions => [
        SequenceNodeDefinition(
          id: 'example.wait',
          name: 'Custom Wait',
          category: 'Example',
          description: 'Wait for a custom duration',
          createNode: (params) {
            final durationMs = params['durationMs'] as int? ?? 5000;
            return _ExampleWaitNode(durationMs: durationMs);
          },
        ),
        SequenceNodeDefinition(
          id: 'example.notify',
          name: 'Send Notification',
          category: 'Example',
          description: 'Send a custom notification',
          createNode: (params) {
            final message = params['message'] as String? ?? 'Notification';
            return _ExampleNotifyNode(message: message);
          },
        ),
      ];
}

/// Example wait node that pauses execution for a specified duration
class _ExampleWaitNode implements PluginSequenceNode {
  final int durationMs;

  _ExampleWaitNode({required this.durationMs});

  @override
  Future<bool> execute(PluginContext context) async {
    context.logger.info('Waiting for ${durationMs}ms...');
    await Future<void>.delayed(Duration(milliseconds: durationMs));
    context.logger.info('Wait complete');
    return true;
  }

  @override
  String? validate() {
    if (durationMs <= 0) {
      return 'Duration must be positive';
    }
    return null;
  }
}

/// Example notify node that emits a notification event
class _ExampleNotifyNode implements PluginSequenceNode {
  final String message;

  _ExampleNotifyNode({required this.message});

  @override
  Future<bool> execute(PluginContext context) async {
    context.logger.info('Sending notification: $message');
    context.eventBus.emit('plugin.notification', {
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
    return true;
  }

  @override
  String? validate() {
    if (message.isEmpty) {
      return 'Message must not be empty';
    }
    return null;
  }
}
