import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_plugins/nightshade_plugins.dart';

/// Integration test demonstrating the complete plugin lifecycle
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Plugin System Integration', () {
    late PluginHost host;

    setUp(() {
      host = PluginHost();
    });

    tearDown(() async {
      await host.dispose();
    });

    test('Example plugin loads and operates correctly', () async {
      final plugin = ExamplePlugin();

      // Register plugin
      await host.registerPlugin(plugin);

      // Verify plugin is loaded and enabled
      expect(host.isLoaded(plugin.id), isTrue);
      expect(host.isEnabled(plugin.id), isTrue);
      expect(host.plugins.length, equals(1));

      // Verify plugin info
      final info = host.pluginInfo.first;
      expect(info.id, equals('com.nightshade.example'));
      expect(info.name, equals('Example Plugin'));
      expect(info.version, equals('1.0.0'));
      expect(info.enabled, isTrue);
      expect(info.error, isNull);

      // Disable plugin
      final disabled = await host.setPluginEnabled(plugin.id, false);
      expect(disabled, isTrue);
      expect(host.isEnabled(plugin.id), isFalse);

      // Re-enable plugin
      final enabled = await host.setPluginEnabled(plugin.id, true);
      expect(enabled, isTrue);
      expect(host.isEnabled(plugin.id), isTrue);

      // Unregister plugin
      await host.unregisterPlugin(plugin.id);
      expect(host.isLoaded(plugin.id), isFalse);
      expect(host.plugins.length, equals(0));
    });

    test('Multiple plugins can coexist', () async {
      final plugin1 = ExamplePlugin();
      final plugin2 = ExampleUiPlugin();
      final plugin3 = ExampleDevicePlugin();

      await host.registerPlugin(plugin1);
      await host.registerPlugin(plugin2);
      await host.registerPlugin(plugin3);

      expect(host.plugins.length, equals(3));
      expect(host.isLoaded(plugin1.id), isTrue);
      expect(host.isLoaded(plugin2.id), isTrue);
      expect(host.isLoaded(plugin3.id), isTrue);

      // Get UI plugins
      final uiPlugins = host.getPlugins<UiPlugin>();
      expect(uiPlugins.length, equals(1));
      expect(uiPlugins.first.id, equals(plugin2.id));

      // Get device plugins
      final devicePlugins = host.getPlugins<DevicePlugin>();
      expect(devicePlugins.length, equals(1));
      expect(devicePlugins.first.id, equals(plugin3.id));
    });

    test('Plugin duplicate registration throws exception', () async {
      final plugin = ExamplePlugin();

      await host.registerPlugin(plugin);

      // Try to register again
      expect(
        () => host.registerPlugin(plugin),
        throwsA(isA<PluginException>()),
      );
    });

    test('Plugin context provides working services', () async {
      final plugin = ExamplePlugin();
      await host.registerPlugin(plugin);

      // Test counter increment (uses storage)
      expect(plugin.counter, equals(0));
      await plugin.incrementCounter();
      expect(plugin.counter, equals(1));
      await plugin.incrementCounter();
      expect(plugin.counter, equals(2));

      // Test reset
      await plugin.resetCounter();
      expect(plugin.counter, equals(0));
    });

    test('Disabled plugin does not appear in typed queries', () async {
      final plugin = ExampleUiPlugin();
      await host.registerPlugin(plugin);

      // Plugin is enabled, should appear
      var uiPlugins = host.getPlugins<UiPlugin>();
      expect(uiPlugins.length, equals(1));

      // Disable plugin
      await host.setPluginEnabled(plugin.id, false);

      // Plugin is disabled, should not appear
      uiPlugins = host.getPlugins<UiPlugin>();
      expect(uiPlugins.length, equals(0));
    });

    test('Plugin can be retrieved by ID', () async {
      final plugin = ExamplePlugin();
      await host.registerPlugin(plugin);

      final retrieved = host.getPlugin(plugin.id);
      expect(retrieved, isNotNull);
      expect(retrieved!.id, equals(plugin.id));
      expect(retrieved, same(plugin));
    });

    test('Dispose cleans up all plugins', () async {
      await host.registerPlugin(ExamplePlugin());
      await host.registerPlugin(ExampleUiPlugin());
      await host.registerPlugin(ExampleDevicePlugin());

      expect(host.plugins.length, equals(3));

      await host.dispose();

      expect(host.plugins.length, equals(0));
    });
  });

  group('Plugin Context Services', () {
    test('Logger works correctly', () {
      final logger = ConsolePluginLogger('test.plugin');

      // Should not throw
      expect(() => logger.debug('Debug message'), returnsNormally);
      expect(() => logger.info('Info message'), returnsNormally);
      expect(() => logger.warning('Warning message'), returnsNormally);
      expect(() => logger.error('Error message'), returnsNormally);
      expect(
        () => logger.error('Error with exception', Exception('test')),
        returnsNormally,
      );
    });

    test('Storage persists values', () async {
      final storage = InMemoryPluginStorage();

      // String storage
      await storage.setString('key1', 'value1');
      final str = await storage.getString('key1');
      expect(str, equals('value1'));

      // Integer storage
      await storage.setInt('key2', 42);
      final num = await storage.getInt('key2');
      expect(num, equals(42));

      // Boolean storage
      await storage.setBool('key3', true);
      final bool = await storage.getBool('key3');
      expect(bool, isTrue);

      // Get all
      final all = await storage.getAll();
      expect(all.length, equals(3));
      expect(all['key1'], equals('value1'));
      expect(all['key2'], equals(42));
      expect(all['key3'], isTrue);

      // Remove
      await storage.remove('key1');
      final removed = await storage.getString('key1');
      expect(removed, isNull);

      // Clear
      await storage.clear();
      final allAfterClear = await storage.getAll();
      expect(allAfterClear.length, equals(0));
    });

    test('File storage survives new instances', () async {
      final tempRoot =
          await Directory.systemTemp.createTemp('nightshade_plugins_test_');
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      Future<Directory> baseDir() async => tempRoot;

      final first = FilePluginStorage(
        'com.nightshade.persistence-test',
        baseDirectoryProvider: baseDir,
      );
      await first.setString('greeting', 'hello');
      await first.setInt('count', 7);
      await first.setBool('enabled', true);

      final second = FilePluginStorage(
        'com.nightshade.persistence-test',
        baseDirectoryProvider: baseDir,
      );
      expect(await second.getString('greeting'), equals('hello'));
      expect(await second.getInt('count'), equals(7));
      expect(await second.getBool('enabled'), isTrue);
    });

    test('Sandboxed plugin event bus blocks global subscriptions', () async {
      final factory = PluginContextFactory();
      final context = factory.createContext('com.nightshade.sandbox-test');
      addTearDown(factory.dispose);

      expect(() => context.eventBus.onAny(), throwsA(isA<PluginException>()));
    });

    test('Event bus delivers events', () async {
      final eventBus = StreamPluginEventBus();
      final receivedEvents = <Map<String, dynamic>>[];

      // Subscribe to specific event
      final subscription = eventBus.on('test.event').listen((data) {
        receivedEvents.add(data);
      });

      // Emit events
      eventBus.emit('test.event', {'count': 1});
      eventBus.emit('test.event', {'count': 2});
      eventBus.emit('other.event', {'ignored': true});

      // Wait for async delivery
      await Future.delayed(Duration.zero);

      expect(receivedEvents.length, equals(2));
      expect(receivedEvents[0]['count'], equals(1));
      expect(receivedEvents[1]['count'], equals(2));

      await subscription.cancel();
      eventBus.dispose();
    });

    test('Event bus onAny receives all events', () async {
      final eventBus = StreamPluginEventBus();
      final receivedEvents = <PluginEvent>[];

      // Subscribe to all events
      final subscription = eventBus.onAny().listen((event) {
        receivedEvents.add(event);
      });

      // Emit different events
      eventBus.emit('event.one', {'data': 'first'});
      eventBus.emit('event.two', {'data': 'second'});

      // Wait for async delivery
      await Future.delayed(Duration.zero);

      expect(receivedEvents.length, equals(2));
      expect(receivedEvents[0].name, equals('event.one'));
      expect(receivedEvents[1].name, equals('event.two'));

      await subscription.cancel();
      eventBus.dispose();
    });
  });

  group('Plugin Types', () {
    test('UiPlugin declares extension points', () {
      final plugin = ExampleUiPlugin();
      expect(plugin.extensionPoints, isNotEmpty);
      expect(plugin.extensionPoints.length, equals(2));

      final equipmentPanel = plugin.extensionPoints
          .where((e) => e.type == UiExtensionPointType.equipmentPanel)
          .first;
      expect(equipmentPanel.title, equals('Example Equipment Panel'));
    });

    test('DevicePlugin declares supported devices', () {
      final plugin = ExampleDevicePlugin();
      expect(plugin.supportedDevices, isNotEmpty);
      expect(plugin.supportedDevices, contains(DevicePluginType.camera));
      expect(plugin.supportedDevices, contains(DevicePluginType.focuser));
    });

    test('SequencePlugin declares node definitions', () {
      final plugin = ExampleSequencePlugin();
      expect(plugin.nodeDefinitions, isNotEmpty);
      expect(plugin.nodeDefinitions.length, equals(2));

      final waitNode =
          plugin.nodeDefinitions.where((n) => n.id == 'example.wait').first;
      expect(waitNode.name, equals('Custom Wait'));
      expect(waitNode.category, equals('Example'));
    });
  });

  group('Plugin sandboxing', () {
    test('Plugin onLoad timeout is enforced', () async {
      final host = PluginHost(
        lifecycleTimeout: const Duration(milliseconds: 50),
      );
      addTearDown(host.dispose);

      expect(
        () => host.registerPlugin(_HangingPlugin()),
        throwsA(isA<PluginException>()),
      );
    });
  });
}

class _HangingPlugin implements NightshadePlugin {
  @override
  String get id => 'com.nightshade.hanging';

  @override
  String get name => 'Hanging Plugin';

  @override
  String get version => '1.0.0';

  @override
  String get description => 'Deliberately hangs during onLoad';

  @override
  String get author => 'test';

  @override
  String? get minAppVersion => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> onDisable() async {}

  @override
  Future<void> onEnable() async {}

  @override
  Future<void> onLoad(PluginContext context) async {
    await Future<void>.delayed(const Duration(seconds: 10));
  }

  @override
  Future<void> onUnload() async {}

  @override
  Future<void> dispose() async {}
}
