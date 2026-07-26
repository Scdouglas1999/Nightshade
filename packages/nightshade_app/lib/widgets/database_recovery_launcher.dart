import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../utils/startup_surface_coordinator.dart';
import '../utils/startup_ui_context.dart';

/// Surfaces a one-shot dialog telling the user "your database was corrupted
/// and recovered from backup" on the first launch after the SQLite
/// integrity-check pre-flight rotated a corrupt `nightshade.db` into a
/// `nightshade-corrupt-<ts>.db` forensic backup.
///
/// Why a wrapper widget rather than an inline call in `desktop_app_bootstrap`:
/// the marker file must be consumed inside the Flutter widget tree because
/// (a) we need a [BuildContext] to push the dialog and (b) we don't want to
/// block startup behind an awaited dialog. Mirroring the pattern used by
/// [FirstNightWizardLauncher] keeps the launcher stack uniform — all
/// startup-triggered dialogs live in `widgets/*_launcher.dart`.
class DatabaseRecoveryLauncher extends ConsumerStatefulWidget {
  final Widget child;

  /// Optional override used by tests so the launcher can read the marker
  /// from a temp directory instead of the real `getApplicationDocumentsDirectory()`.
  final Future<DatabaseRecoveryMarker?> Function()? markerConsumer;

  /// Optional acknowledgement hook for a non-consuming [markerConsumer].
  /// When omitted alongside a custom consumer, the consumer is treated as the
  /// legacy read-and-delete operation.
  final Future<void> Function(DatabaseRecoveryMarker marker)?
      markerAcknowledger;

  const DatabaseRecoveryLauncher({
    super.key,
    required this.child,
    this.markerConsumer,
    this.markerAcknowledger,
  });

  @override
  ConsumerState<DatabaseRecoveryLauncher> createState() =>
      _DatabaseRecoveryLauncherState();
}

class _DatabaseRecoveryLauncherState
    extends ConsumerState<DatabaseRecoveryLauncher> {
  bool _hasReadMarker = false;
  bool _surfaceQueued = false;
  bool _dialogShown = false;
  DatabaseRecoveryMarker? _pendingMarker;
  Timer? _deferTimer;

  @override
  void initState() {
    super.initState();
    // Post-frame so the navigator is laid out before we push the dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCheck());
  }

  @override
  void dispose() {
    _deferTimer?.cancel();
    super.dispose();
  }

  void _scheduleCheck() {
    if (!mounted || _pendingMarker == null && _hasReadMarker) return;
    // Defer slightly so this dialog wins over the first-night wizard but
    // does not collide with the splash transition. 600 ms matches the
    // observed window between MaterialApp first frame and the router's
    // initial route settling.
    _deferTimer = Timer(const Duration(milliseconds: 600), _maybeShow);
  }

  Future<void> _maybeShow() async {
    if (!mounted || _surfaceQueued) return;

    if (!_hasReadMarker) {
      _hasReadMarker = true;
      final consumer =
          widget.markerConsumer ?? NightshadeDatabase.readRecoveryMarker;
      try {
        _pendingMarker = await consumer();
      } catch (e) {
        // This marker is how the operator learns their database was rebuilt
        // and data may be missing. A read that keeps failing retries forever
        // and the notice never appears, so the failure must be recorded —
        // otherwise a recovered database looks exactly like a healthy one.
        developer.log(
          'Could not read the database recovery marker; the recovery notice '
          'will not be shown until a retry succeeds: $e',
          name: 'DatabaseRecovery',
          level: 1000,
        );
        if (!mounted) return;
        _hasReadMarker = false;
        _scheduleRetry();
        return;
      }
    }
    if (!mounted || _pendingMarker == null) return;

    if (_dialogShown) {
      await _acknowledgePendingMarker();
      return;
    }

    _surfaceQueued = true;
    final shown = await _showRecoveryDialog(_pendingMarker!);
    if (!mounted) return;
    _surfaceQueued = false;
    if (!shown) {
      _scheduleRetry();
      return;
    }
    _dialogShown = true;
    await _acknowledgePendingMarker();
  }

  Future<bool> _showRecoveryDialog(DatabaseRecoveryMarker marker) {
    return ref.read(startupSurfaceCoordinatorProvider).run(() async {
      if (!mounted) return false;
      final uiContext = resolveStartupUiContext(ref, context);
      if (uiContext == null || !uiContext.mounted) return false;
      await showDialog<void>(
        context: uiContext,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Database recovered'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nightshade detected that your database file was corrupted '
                    'and recreated a fresh one so the app could start. Your '
                    'existing settings, profiles, sessions, and captures from '
                    'before the corruption are NOT in the new database.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A backup of the corrupt file has been retained on disk '
                    'so support engineers can recover what is salvageable. '
                    'Please contact support if you need help extracting '
                    'historical data.',
                  ),
                  const SizedBox(height: 16),
                  if (marker.backupPath != null) ...[
                    const Text('Backup file:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText(marker.backupPath!),
                    const SizedBox(height: 8),
                  ],
                  if (marker.reason != null) ...[
                    const Text('Reason reported by SQLite:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SelectableText(marker.reason!),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return true;
    });
  }

  Future<void> _acknowledgePendingMarker() async {
    final marker = _pendingMarker;
    if (marker == null) return;
    final acknowledge = widget.markerAcknowledger ??
        (widget.markerConsumer == null
            ? NightshadeDatabase.acknowledgeRecoveryMarker
            : null);
    if (acknowledge == null) {
      _pendingMarker = null;
      return;
    }
    try {
      await acknowledge(marker);
      if (mounted) _pendingMarker = null;
    } catch (e) {
      // An unacknowledged marker re-surfaces the recovery dialog on every
      // launch. Harmless on its own, but a permanently failing acknowledge
      // means the marker store is unwritable, which is worth knowing before
      // the next recovery needs to record one.
      developer.log(
        'Could not acknowledge the database recovery marker; the notice will '
        'be shown again: $e',
        name: 'DatabaseRecovery',
        level: 900,
      );
      if (mounted) _scheduleRetry();
    }
  }

  /// Retry backoff. The ordinary reason for a retry is that another startup
  /// surface holds the dialog slot, which clears in a second or two, so the
  /// first attempts stay fast. The pathological reason is a marker store that
  /// cannot be read at all — and at a flat 100ms that was an unbounded hot loop
  /// for the life of the process, on a machine that is expected to run all
  /// night. Back off to a slow poll instead.
  ///
  /// It keeps polling rather than giving up: this notice is how the operator
  /// learns their database was rebuilt and data may be missing, so abandoning
  /// it silently would be worse than the delay.
  static const _retryFloor = Duration(milliseconds: 100);
  static const _retryCeiling = Duration(seconds: 5);
  int _retryAttempt = 0;

  void _scheduleRetry() {
    _deferTimer?.cancel();
    final backoff = _retryFloor * (1 << _retryAttempt.clamp(0, 6));
    final delay = backoff > _retryCeiling ? _retryCeiling : backoff;
    if (delay == _retryCeiling && _retryAttempt == 6) {
      developer.log(
        'Database recovery notice still cannot be surfaced after '
        '$_retryAttempt attempts; continuing to poll every '
        '${_retryCeiling.inSeconds}s.',
        name: 'DatabaseRecovery',
        level: 900,
      );
    }
    _retryAttempt++;
    _deferTimer = Timer(delay, _maybeShow);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
