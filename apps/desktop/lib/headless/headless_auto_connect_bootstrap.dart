import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

const _headlessLogSource = 'HeadlessAutoConnect';

/// Attempt startup equipment auto-connect for the headless daemon.
///
/// This is the headless twin of the desktop `StartupAutoConnectLauncher`: it is
/// the production call site that finally makes the "Auto-connect equipment"
/// setting do something on a Pi/appliance. It is invoked exactly once from
/// `main_headless.dart`, after the local FFI backend is installed and the API
/// server has started, at a deterministic point BEFORE the daemon prints its
/// "running" ready banner.
///
/// Design constraints (contract):
///   * Uses the daemon's existing [ProviderContainer] and the same
///     [ProfileService.autoConnectOnStartup] core as the GUI, so selection /
///     activation / connect semantics are identical across surfaces.
///   * The headless daemon is definitionally the LOCAL hardware-owning master
///     (it runs the FfiBackend and serves the API), but we still gate on
///     [FfiBackend] defensively so a future misconfiguration can never make the
///     daemon drive a remote host.
///   * Failure MUST NOT crash-loop the daemon: a single offline device (or a
///     total activation failure) is logged loudly and printed to stderr, and
///     the server keeps running so the operator can recover remotely. This is
///     the smallest injection seam — it takes the container + logger and does
///     not require booting the HTTP server — so it is directly unit-testable.
///   * [backendReady] is the `useLocalBackend()` FfiBackend-swap future. It is
///     awaited INSIDE this fail-soft seam (rather than in `main_headless` before
///     the call) so that a readiness FAILURE is logged loudly and swallowed here
///     — the already-started API server stays up for remote recovery — instead
///     of escaping to `main_headless`'s outer catch, which would tear the server
///     down and exit. When null (unit tests that pre-install a backend) the
///     readiness step is skipped.
Future<void> headlessAutoConnectBootstrap({
  required ProviderContainer container,
  required LoggingService logger,
  Future<void>? backendReady,
}) async {
  // (0) Await local-backend readiness INSIDE the fail-soft boundary. A rejected
  //     readiness future must NOT propagate: the HTTP server is already running
  //     (this seam is invoked only after `startHeadlessServices`), so a throw
  //     here would reach main_headless's outer catch and shut the server down,
  //     contradicting server-survival. Log loudly, echo to stderr, and return
  //     without connecting.
  if (backendReady != null) {
    try {
      await backendReady;
    } catch (error, stack) {
      logger.error(
        'Local backend readiness failed; server continues so you can recover '
        'remotely — startup auto-connect skipped: $error',
        source: _headlessLogSource,
        fields: {'error': error.toString(), 'stack': stack.toString()},
      );
      stderr.writeln(
        'Nightshade: local backend readiness failed; auto-connect skipped, '
        'server still running: $error',
      );
      return;
    }
  }

  try {
    final backend = container.read(backendProvider);
    if (backend is! FfiBackend) {
      // A headless daemon should always own local hardware; if it somehow does
      // not, skip rather than drive someone else's rig.
      logger.warning(
        'Startup auto-connect skipped: backend is not a local FfiBackend '
        '(${backend.runtimeType})',
        source: _headlessLogSource,
      );
      return;
    }

    await container.read(profileServiceProvider).autoConnectOnStartup();
    logger.info('Startup auto-connect completed', source: _headlessLogSource);
  } catch (error, stack) {
    // Never take the daemon down because equipment is offline — log loudly,
    // echo to stderr for operators tailing the console, and continue so the
    // rig stays reachable for remote recovery.
    logger.error(
      'Startup auto-connect failed; server continues so you can recover '
      'remotely: $error',
      source: _headlessLogSource,
      fields: {'error': error.toString(), 'stack': stack.toString()},
    );
    stderr.writeln('Nightshade: startup auto-connect failed: $error');
  }
}
