import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

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

  const DatabaseRecoveryLauncher({
    super.key,
    required this.child,
    this.markerConsumer,
  });

  @override
  ConsumerState<DatabaseRecoveryLauncher> createState() =>
      _DatabaseRecoveryLauncherState();
}

class _DatabaseRecoveryLauncherState
    extends ConsumerState<DatabaseRecoveryLauncher> {
  bool _hasChecked = false;
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
    if (_hasChecked || !mounted) return;
    // Defer slightly so this dialog wins over the first-night wizard but
    // does not collide with the splash transition. 600 ms matches the
    // observed window between MaterialApp first frame and the router's
    // initial route settling.
    _deferTimer = Timer(const Duration(milliseconds: 600), _maybeShow);
  }

  Future<void> _maybeShow() async {
    if (_hasChecked || !mounted) return;
    _hasChecked = true;

    final consumer =
        widget.markerConsumer ?? NightshadeDatabase.consumeRecoveryMarker;
    final marker = await consumer();
    if (marker == null || !mounted) return;

    await _showRecoveryDialog(marker);
  }

  Future<void> _showRecoveryDialog(DatabaseRecoveryMarker marker) async {
    await showDialog<void>(
      context: context,
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
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
