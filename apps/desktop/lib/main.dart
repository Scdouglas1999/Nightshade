import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart'
    show planetariumEngineHandleProvider;
import 'package:window_manager/window_manager.dart';

import 'desktop_app_bootstrap.dart';
import 'desktop_logging_init.dart';
import 'main_headless.dart' as headless;

// Current app version - must match version.yaml
const String appVersion = '2.5.0';
const int appBuildNumber = 5;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final isHeadless = args.contains('--headless') ||
      Platform.environment['NIGHTSHADE_HEADLESS'] == '1';

  if (isHeadless) {
    headless.main(args);
    return;
  }

  await initialiseDesktopLogging();

  await windowManager.ensureInitialized();

  // Planetarium v2 registers a Flutter Texture via irondash_texture, which
  // needs the engine handle from the Dart side (it carries a version tag in
  // its high bits — passing the bare 0 default produces InvalidVersion at
  // texture-allocation time, breaking v2's first resize). Fetch it once up
  // front and override the provider before any planetarium widget mounts.
  final planetariumEngineHandle =
      await EngineContext.instance.getEngineHandle();

  const windowOptions = WindowOptions(
    size: Size(1600, 900),
    minimumSize: Size(1200, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Nightshade 2.0',
  );

  final container = ProviderContainer(
    overrides: [
      // Initialize backendProvider with FfiBackend immediately for desktop GUI
      backendProvider.overrideWith((ref) {
        final notifier = BackendNotifier(ref);
        notifier.useLocalBackend();
        return notifier;
      }),
      // Why: appVersionProvider throws by default to surface misconfiguration
      // loudly (an unset version masks OTA update logic). The desktop entry
      // is the canonical place to wire it.
      appVersionProvider.overrideWithValue(
        const AppVersionInfo(
          version: appVersion,
          buildNumber: appBuildNumber,
        ),
      ),
      // Wave 6 Pack P — wire `pluginNodeDispatcherProvider` (defined in
      // nightshade_core) to the real `PluginNodeExecutor` (defined in
      // nightshade_plugins). Without this override the Rust executor would
      // receive a structured "dispatcher not wired" failure for every
      // PluginNode invocation.
      pluginNodeDispatcherOverride(),
      // Audit §11 — surface plugin-contributed sequence nodes in the
      // sequencer palette. Without this override the palette never shows
      // plugin nodes even when the dispatcher above is fully wired (the
      // user could not author a sequence containing a plugin node from
      // the GUI).
      pluginNodePaletteBlueprintsOverride(),
      // C4 — make the bundled-plugin registration honour the user's
      // persisted enable/disable choices. Without this override C3's
      // `pluginEnablementStoreProvider` resolves to the default
      // `AllEnabledPluginEnablementStore`, which reports every plugin
      // enabled, so a plugin the user disabled on the Integrations page
      // would silently come back ENABLED on the next launch. The
      // settings-backed store reads the persisted `plugin_enablement`
      // map so the registration-time decision matches the saved state.
      pluginEnablementStoreOverride(),
      // Planetarium v2 — pass the live Irondash engine handle so
      // `Texture::new_with_provider` on the Rust side resolves a valid
      // Flutter texture registry (handle 0 produces InvalidVersion).
      planetariumEngineHandleProvider.overrideWithValue(
        planetariumEngineHandle,
      ),
    ],
  );

  final logger = container.read(loggingServiceProvider);
  await logger.ensureInitialized();

  await initialiseCatalogManager(logger);

  final shouldMinimize = await shouldStartMinimized(container);

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    if (shouldMinimize) {
      await windowManager.minimize();
    }
  });

  startBackgroundServices(
    container,
    appVersion: appVersion,
    appBuildNumber: appBuildNumber,
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NightshadeApp(isDesktop: true),
    ),
  );
}
