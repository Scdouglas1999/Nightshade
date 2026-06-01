part of '../sequence_executor.dart';

extension _SequenceExecutorCheckpointWatchdogOperations on SequenceExecutor {
  void _startCheckpointTimer() {
    _checkpointTimer?.cancel();
    _checkpointTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_ref.read(sequenceExecutionStateProvider) ==
          SequenceExecutionState.running) {
        try {
          final backend = _ref.read(backendProvider);
          await backend.saveCheckpoint();
        } catch (e) {
          // Checkpoint write failure must not interrupt the running sequence;
          // the next tick will retry.
          _logger.warning('Failed to save checkpoint: $e',
              source: 'SequenceExecutor');
        }
      }
    });
  }

  /// Start the disk-space watchdog for the duration of this run.
  ///
  /// Watches the capture directory and:
  ///  - logs a warning event when free space drops below the configured
  ///    warning threshold (default 10 GB);
  ///  - pauses the running sequence when free space drops below the configured
  ///    abort threshold (default 2 GB), so the in-flight frame finishes
  ///    cleanly rather than the OS killing the writer mid-stream.
  ///
  /// Skipped silently when no capture path is configured â€” the pre-flight
  /// dialog already warns about that and there's nothing useful to monitor.
  void _startDiskSpaceWatchdog() {
    _diskWatchdogSubscription?.cancel();
    _diskWatchdogSubscription = null;

    final settings = _ref.read(appSettingsProvider).valueOrNull;
    final capturePath = settings?.imageOutputPath ?? '';
    if (capturePath.isEmpty) {
      _logger.warning(
        'Disk-space watchdog not started: no capture path configured',
        source: 'SequenceExecutor',
      );
      return;
    }

    final guard = _ref.read(diskSpaceGuardProvider);
    guard.start(capturePath: capturePath);
    _diskWatchdogSubscription = guard.events.listen((event) async {
      _logger.warning(
        '[disk-watchdog] ${event.message}',
        source: 'SequenceExecutor',
      );
      if (event.severity == DiskSpaceSeverity.blocking) {
        // Critical: pause the run so the user can intervene. We do NOT
        // fully stop because that would lose the checkpoint; pause keeps
        // state preserved.
        try {
          await pause();
        } catch (e, stack) {
          _logger.error(
            'Failed to pause sequence on disk-space abort: $e\n$stack',
            source: 'SequenceExecutor',
          );
        }
      }
    });
  }

  void _stopDiskSpaceWatchdog() {
    _diskWatchdogSubscription?.cancel();
    _diskWatchdogSubscription = null;
    try {
      _ref.read(diskSpaceGuardProvider).stop();
    } catch (_) {
      // Disposed provider â€” ignore.
    }
  }

  /// Cancel all owned timers and subscriptions.
  ///
  /// Wired into the owning Provider's `ref.onDispose`. Safe to call even when
  /// no sequence is running â€” all cancels are null-tolerant. Distinct from
  /// `stop()`, which also mutates execution state and ends the session.
}
