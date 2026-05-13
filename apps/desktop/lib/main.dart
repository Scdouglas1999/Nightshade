import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_core/nightshade_core.dart';
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
