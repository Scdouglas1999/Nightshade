import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/nightshade_app.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_app_bootstrap.dart';
import 'desktop_logging_init.dart';
import 'main_headless.dart' as headless;

/// A remote rig the desktop GUI should drive as a thin client instead of
/// connecting local hardware. Populated from `--remote-host=` / `--remote-port=`
/// / `--remote-token=` / `--remote-scheme=` flags (or the matching
/// NIGHTSHADE_REMOTE_* env vars). When set, the GUI runs against the headless
/// rig's NetworkBackend and does NOT start its own embedded host server.
class _RemoteClientTarget {
  final String host;
  final int port;
  final String? token;
  final String scheme;

  const _RemoteClientTarget({
    required this.host,
    required this.port,
    this.token,
    this.scheme = 'http',
  });
}

/// Resolve `--flag=value` from [args], falling back to [envKey]. Returns null
/// when neither is present so callers can apply their own defaults.
String? _flagValue(List<String> args, String flag, String envKey) {
  final prefix = '--$flag=';
  for (final arg in args) {
    if (arg.startsWith(prefix)) {
      return arg.substring(prefix.length);
    }
  }
  final env = Platform.environment[envKey];
  return (env != null && env.isNotEmpty) ? env : null;
}

/// True when the operator asked this instance to be a MASTER — i.e. own the
/// hardware AND expose the embedded remote-access server so slave clients (and
/// the mobile app) can connect. Accepts `--serve` / `--master` (presence or
/// `=1`/`=true`) and the `NIGHTSHADE_SERVE` env var. This is the easy, reliable
/// switch for Pi / scripted launches: it forces the effective
/// `web_server_enabled` setting true for this run WITHOUT flipping the global
/// default (so a plain desktop launch never silently exposes a LAN server).
bool _parseServeFlag(List<String> args) {
  for (final flag in const ['serve', 'master']) {
    final prefix = '--$flag';
    for (final arg in args) {
      if (arg == prefix) {
        return true;
      }
      if (arg.startsWith('$prefix=')) {
        final value = arg.substring(prefix.length + 1).toLowerCase();
        return value == '1' || value == 'true' || value.isEmpty;
      }
    }
  }
  final env = Platform.environment['NIGHTSHADE_SERVE'];
  return env == '1' || env == 'true';
}

_RemoteClientTarget? _parseRemoteTarget(List<String> args) {
  final host = _flagValue(args, 'remote-host', 'NIGHTSHADE_REMOTE_HOST');
  if (host == null || host.isEmpty) {
    return null;
  }
  final portRaw = _flagValue(args, 'remote-port', 'NIGHTSHADE_REMOTE_PORT');
  final token = _flagValue(args, 'remote-token', 'NIGHTSHADE_REMOTE_TOKEN');
  final scheme =
      _flagValue(args, 'remote-scheme', 'NIGHTSHADE_REMOTE_SCHEME') ?? 'http';
  return _RemoteClientTarget(
    host: host,
    port: int.tryParse(portRaw ?? '') ?? 8080,
    token: (token == null || token.isEmpty) ? null : token,
    scheme: scheme,
  );
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final isHeadless =
      args.contains('--headless') ||
      Platform.environment['NIGHTSHADE_HEADLESS'] == '1';

  if (isHeadless) {
    headless.main(args);
    return;
  }

  final remoteTarget = _parseRemoteTarget(args);
  final serveRequested = _parseServeFlag(args);

  // Single-owner invariant: one instance cannot both OWN the hardware (master)
  // and be a thin client of another rig (slave). Refuse the contradictory
  // combination loudly instead of silently picking one.
  if (serveRequested && remoteTarget != null) {
    stderr.writeln(
      'Nightshade: --serve/--master cannot be combined with --remote-host '
      '(an instance cannot be both a hardware-owning master and a remote '
      'slave). Aborting.',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  await initialiseDesktopLogging();
  final appVersion = await loadDesktopAppVersion();

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1600, 900),
    minimumSize: Size(1200, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'Nightshade',
  );

  final container = ProviderContainer(
    overrides: [
      // Initialize backendProvider for the desktop GUI. Default: the local
      // FfiBackend (this machine owns the hardware). With --remote-host, run as
      // a thin client against a remote headless rig via NetworkBackend instead,
      // so the GUI drives that rig as if its devices were attached locally.
      backendProvider.overrideWith((ref) {
        final notifier = BackendNotifier(ref);
        // In remote mode we connect explicitly AFTER the container is built (see
        // below) so we can await the handshake and then invalidate the
        // host-backed providers — doing it here, fire-and-forget, lets profiles
        // and settings cache an empty disconnected value that never refreshes.
        if (remoteTarget == null) {
          notifier.useLocalBackend();
        }
        return notifier;
      }),
      // Why: appVersionProvider throws by default to surface misconfiguration
      // loudly (an unset version masks OTA update logic). The desktop entry
      // is the canonical place to wire it.
      appVersionProvider.overrideWithValue(appVersion),
      // wire `pluginNodeDispatcherProvider` (defined in
      // nightshade_core) to the real `PluginNodeExecutor` (defined in
      // nightshade_plugins). Without this override the Rust executor would
      // receive a structured "dispatcher not wired" failure for every
      // PluginNode invocation.
      pluginNodeDispatcherOverride(),
      // surface plugin-contributed sequence nodes in the
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

  // Remote-client mode: connect to the headless rig now that the container is
  // live, then invalidate the host-backed providers so they re-fetch against
  // the open NetworkBackend connection (equipment profiles, app settings, and
  // anything else keyed on the backend). Without this refresh they keep the
  // empty value they resolved while the backend was still DisconnectedBackend,
  // which is why profiles/devices appeared missing. Mirrors the mobile
  // post-connect sequence (invalidate appSettings + equipmentProfiles).
  if (remoteTarget != null) {
    try {
      await container
          .read(backendProvider.notifier)
          .connect(
            remoteTarget.host,
            remoteTarget.port,
            authToken: remoteTarget.token,
            scheme: remoteTarget.scheme,
          );
    } catch (error) {
      developer.log(
        'Remote connect to ${remoteTarget.scheme}://'
        '${remoteTarget.host}:${remoteTarget.port} failed: $error',
        name: 'desktop.main',
        level: 1000,
        error: error,
      );
    }
    container.invalidate(appSettingsProvider);
    container.invalidate(equipmentProfilesProvider);
  }

  // In remote-client mode this GUI is a consumer of a remote rig, not a host,
  // so it must NOT stand up its own embedded API server / discovery / host-side
  // seed listeners (those belong to the machine that owns the hardware).
  if (remoteTarget == null) {
    // --serve/--master: force the effective web-server setting ON for this run
    // so the embedded host server starts and slave clients can connect. We do
    // NOT flip the global default — we await the settings notifier, persist
    // web_server_enabled=true, and patch in-memory state BEFORE
    // startBackgroundServices attaches its fireImmediately listener, so the
    // server comes up on launch. A normal (no-flag) launch is untouched and
    // honours whatever the user toggled in Settings → Remote Access.
    if (serveRequested) {
      try {
        // Ensure the settings state is loaded so setWebServerEnabled can both
        // persist and patch the live state the lifecycle listener reads.
        await container.read(appSettingsProvider.future);
        await container
            .read(appSettingsProvider.notifier)
            .setWebServerEnabled(true);
      } catch (error) {
        developer.log(
          '--serve: failed to force web_server_enabled on; the embedded '
          'remote-access server may not start: $error',
          name: 'desktop.main',
          level: 1000,
          error: error,
        );
      }
    }
    startBackgroundServices(
      container,
      appVersion: appVersion.version,
      appBuildNumber: appVersion.buildNumber,
    );
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const NightshadeApp(isDesktop: true),
    ),
  );
}
