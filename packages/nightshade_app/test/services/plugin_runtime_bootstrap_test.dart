import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/services/plugin_node_palette_wiring.dart';
import 'package:nightshade_app/services/plugin_runtime_bootstrap.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_plugins/nightshade_plugins.dart';
import '../harness/mock_database.dart' show inMemoryDatabaseOverride;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('startup bootstrap registers bundled nodes without opening settings',
      () async {
    final container = ProviderContainer(
      overrides: [
        inMemoryDatabaseOverride(),
        pluginNodePaletteBlueprintsOverride()
      ],
    );
    addTearDown(container.dispose);

    expect(container.read(pluginHostProvider).pluginInfo, isEmpty);

    await initializeBundledPluginRuntime(container);
    await Future<void>.delayed(Duration.zero);

    final pluginIds = container
        .read(pluginHostProvider)
        .pluginInfo
        .map((plugin) => plugin.id)
        .toSet();
    expect(pluginIds, {
      'com.nightshade.examples.discord_webhook',
      'com.nightshade.examples.pushover',
      'com.nightshade.examples.home_assistant',
      'com.nightshade.weatherlogger',
    });

    final nodeKeys = container
        .read(pluginNodeBlueprintsProvider)
        .map((node) => node.registrationKey)
        .toSet();
    expect(nodeKeys, isNotEmpty);
    expect(
      nodeKeys,
      contains(
        'com.nightshade.examples.home_assistant::home_assistant.toggle',
      ),
    );
  });
}
