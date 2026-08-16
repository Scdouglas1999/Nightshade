import 'dart:async';

/// One named teardown step run during a headless shutdown.
///
/// [action] may be async, may throw, or may hang — the coordinator bounds and
/// isolates each step so none of those can wedge the daemon.
typedef ShutdownStep = ({String name, Future<void> Function() action});

/// Coordinates a bounded, idempotent headless shutdown that ALWAYS terminates
/// the process — even if a teardown step hangs or throws, and even if the
/// operator sends repeated stop signals.
///
/// Why this exists: the headless daemon's SIGINT/SIGTERM handler safes the rig
/// and then tears down its services (mDNS, relay uplink, HTTP server, OTA
/// stack, auto-save, provider container). Time-bounding only the rig-safing
/// call is not enough — one hung `stop()` (a dead WebSocket, an HTTP server
/// draining a stuck request) wedges the daemon with `exit()` unreachable and
/// swallows a second Ctrl+C, leaving SIGKILL as the operator's only escape.
/// That is exactly the unattended-safety failure the safing path prevents.
///
/// Correctness contract (pinned by tests):
///   * The safing + teardown sequence runs EXACTLY ONCE.
///   * A repeated [request] while a shutdown is already in flight forces an
///     immediate `exit` so an operator mashing Ctrl+C can always escape a
///     wedged teardown.
///   * EVERY teardown step is attempted even if an earlier one throws (safing
///     must never short-circuit), and each step is time-bounded so a hang
///     cannot block the rest.
///   * A hard deadline force-exits the process even if the whole sequence
///     overruns, as a final backstop.
///   * [request] itself never throws — a signal handler can call it directly.
class HeadlessShutdown {
  HeadlessShutdown({
    required Future<void> Function() safeRig,
    required List<ShutdownStep> Function() teardownSteps,
    required void Function(int code) exitProcess,
    void Function(String message, {Object? error})? onInfo,
    void Function(String message, {Object? error})? onCritical,
    void Function(String message)? onStderr,
    Duration safingTimeout = const Duration(seconds: 60),
    Duration stepTimeout = const Duration(seconds: 20),
    Duration hardDeadline = const Duration(seconds: 90),
    int completionExitCode = 0,
  }) : _safeRig = safeRig,
       _teardownSteps = teardownSteps,
       _exitProcess = exitProcess,
       _onInfo = onInfo,
       _onCritical = onCritical,
       _onStderr = onStderr,
       _safingTimeout = safingTimeout,
       _stepTimeout = stepTimeout,
       _hardDeadline = hardDeadline,
       _completionExitCode = completionExitCode;

  final Future<void> Function() _safeRig;
  final List<ShutdownStep> Function() _teardownSteps;
  final void Function(int code) _exitProcess;
  final void Function(String message, {Object? error})? _onInfo;
  final void Function(String message, {Object? error})? _onCritical;
  final void Function(String message)? _onStderr;
  final Duration _safingTimeout;
  final Duration _stepTimeout;
  final Duration _hardDeadline;
  final int _completionExitCode;

  bool _inProgress = false;
  bool _exited = false;
  Timer? _deadlineTimer;

  /// Terminate the process at most once. Models real `exit()` semantics (the
  /// first call wins; later ones are no-ops because the process is gone), so a
  /// racing deadline timer and the normal completion path can never
  /// double-exit or fight over the exit code.
  void _terminate(int code) {
    if (_exited) return;
    _exited = true;
    _deadlineTimer?.cancel();
    _exitProcess(code);
  }

  /// Begin (or, on a repeated call, force) shutdown.
  ///
  /// [reason] is a human-readable trigger for the logs ("Received SIGINT").
  Future<void> request(String reason) async {
    if (_inProgress) {
      // A shutdown is already running — possibly wedged on a slow teardown
      // step. A repeated operator signal must always be an escape hatch, not a
      // no-op: force an immediate exit rather than swallow it.
      _onStderr?.call(
        '$reason while shutdown already in progress; forcing immediate exit.',
      );
      _onCritical?.call('Repeated stop signal during shutdown; forcing exit');
      _terminate(1);
      return;
    }
    _inProgress = true;
    _onInfo?.call('$reason; shutting down');

    // Absolute backstop: even if the bounded sequence below somehow overruns
    // (a step builder that hangs, a pathological pile-up of slow steps), the
    // process must still die. Fires independently of any awaited future.
    _deadlineTimer = Timer(_hardDeadline, () {
      _onStderr?.call(
        'Shutdown exceeded ${_hardDeadline.inSeconds}s; forcing exit.',
      );
      _onCritical?.call('Shutdown hard-deadline exceeded; forcing exit');
      _terminate(1);
    });

    // 1. Safe the rig FIRST (bounded). A safing failure/timeout is logged
    //    loudly but never aborts teardown — the daemon must still exit.
    try {
      await _safeRig().timeout(_safingTimeout);
      _onInfo?.call('Pre-shutdown rig safing completed');
    } catch (e) {
      _onCritical?.call(
        'Pre-shutdown rig safing failed; continuing daemon teardown',
        error: e,
      );
      _onStderr?.call('CRITICAL: Pre-shutdown rig safing failed: $e');
    }

    // 2. Teardown — attempt EVERY step even if one throws, and bound each so a
    //    hung stop() cannot block the rest or the exit.
    for (final step in _teardownSteps()) {
      if (_exited) return; // deadline already forced us out
      try {
        await step.action().timeout(_stepTimeout);
      } catch (e) {
        _onCritical?.call('Shutdown step "${step.name}" failed', error: e);
      }
    }

    _terminate(_completionExitCode);
  }
}
