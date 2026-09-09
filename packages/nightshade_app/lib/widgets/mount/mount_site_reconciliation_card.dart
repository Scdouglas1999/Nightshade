import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Watches for a pending site/time disagreement and puts the card up once.
///
/// Mounted high in the app shell. Kept separate from the card so the card
/// itself stays a plain widget that can be previewed with fixture data.
class MountSiteReconciliationListener extends ConsumerStatefulWidget {
  const MountSiteReconciliationListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<MountSiteReconciliationListener> createState() =>
      _MountSiteReconciliationListenerState();
}

class _MountSiteReconciliationListenerState
    extends ConsumerState<MountSiteReconciliationListener> {
  bool _showing = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<MountSiteReconciliation?>(
      pendingMountSiteReconciliationProvider,
      (previous, next) {
        // One card at a time: a mount that reconnects while the operator is
        // still reading the first one must not stack a second on top of it.
        if (next == null || _showing) return;
        _showing = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => MountSiteReconciliationCard(comparison: next),
        ).whenComplete(() {
          _showing = false;
          ref.read(pendingMountSiteReconciliationProvider.notifier).clear();
        });
      },
    );
    return widget.child;
  }
}

/// Side-by-side of what this computer believes and what the mount believes,
/// with the choice of which one wins.
class MountSiteReconciliationCard extends ConsumerStatefulWidget {
  const MountSiteReconciliationCard({super.key, required this.comparison});

  final MountSiteReconciliation comparison;

  @override
  ConsumerState<MountSiteReconciliationCard> createState() =>
      _MountSiteReconciliationCardState();
}

class _MountSiteReconciliationCardState
    extends ConsumerState<MountSiteReconciliationCard> {
  bool _remember = false;
  bool _busy = false;
  String? _error;

  MountSiteReconciliation get _c => widget.comparison;

  String _formatLatitude(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(4)}°';

  String _formatLongitude(double? value) {
    if (value == null) return '—';
    // Spell out the hemisphere. A bare signed number is exactly where a
    // west/east mix-up hides, and this card exists to catch that.
    final hemisphere = value < 0 ? 'W' : 'E';
    return '${value.abs().toStringAsFixed(4)}° $hemisphere';
  }

  String _formatClock(int? utcSeconds, double? offsetHours) {
    if (utcSeconds == null) return '—';
    final utc = DateTime.fromMillisecondsSinceEpoch(
      utcSeconds * 1000,
      isUtc: true,
    );
    final offset = offsetHours ?? 0;
    final local = utc.add(Duration(minutes: (offset * 60).round()));
    final sign = offset < 0 ? '-' : '+';
    final hours = offset.abs().floor().toString().padLeft(2, '0');
    final minutes =
        ((offset.abs() - offset.abs().floor()) * 60).round().toString().padLeft(2, '0');
    return '${local.toIso8601String().substring(0, 19).replaceFirst('T', ' ')} '
        'UTC$sign$hours:$minutes';
  }

  Future<void> _apply(MountSiteSyncDirection direction) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final failures =
        await ref.read(mountSiteReconcilerProvider).apply(_c, direction);

    if (_remember) {
      await ref.read(appSettingsProvider.notifier).setMountSiteSyncMode(
            direction == MountSiteSyncDirection.computerToMount
                ? 'computerToMount'
                : 'mountToComputer',
          );
    }

    if (!mounted) return;
    if (failures.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = failures.join('\n');
    });
  }

  Future<void> _dismiss({required bool never}) async {
    if (never) {
      await ref
          .read(appSettingsProvider.notifier)
          .setMountSiteSyncMode('never');
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final toMountReason =
        _c.unavailableReason(MountSiteSyncDirection.computerToMount);
    final toComputerReason =
        _c.unavailableReason(MountSiteSyncDirection.mountToComputer);

    return NightshadeDialog(
      title: 'Site and time differ',
      icon: Icons.public,
      width: 560,
      showCloseButton: false,
      actions: [
        NightshadeButton(
          label: 'Keep both as they are',
          variant: ButtonVariant.ghost,
          onPressed: _busy ? null : () => _dismiss(never: false),
        ),
        NightshadeButton(
          label: "Use the mount's",
          variant: ButtonVariant.outline,
          onPressed: _busy || toComputerReason != null
              ? null
              : () => _apply(MountSiteSyncDirection.mountToComputer),
          semanticsHint: toComputerReason,
        ),
        NightshadeButton(
          label: 'Send this computer\'s',
          variant: ButtonVariant.primary,
          isLoading: _busy,
          onPressed: _busy || toMountReason != null
              ? null
              : () => _apply(MountSiteSyncDirection.computerToMount),
          semanticsHint: toMountReason,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_c.deviceName} does not agree with this computer about where '
            'or when it is. Pointing, meridian flips and horizon limits all '
            'depend on getting this right.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _ComparisonTable(
            rows: [
              if (_c.siteDiffers) ...[
                _ComparisonRow(
                  label: 'Latitude',
                  computer: _formatLatitude(_c.computerLatitudeDeg),
                  mount: _formatLatitude(_c.mountLatitudeDeg),
                ),
                _ComparisonRow(
                  label: 'Longitude',
                  computer: _formatLongitude(_c.computerLongitudeDeg),
                  mount: _formatLongitude(_c.mountLongitudeDeg),
                ),
              ],
              if (_c.timeDiffers)
                _ComparisonRow(
                  label: 'Clock',
                  computer: _formatClock(
                    _c.computerUtcSeconds,
                    _c.computerUtcOffsetHours,
                  ),
                  mount: _formatClock(_c.mountUtcSeconds, _c.mountUtcOffsetHours),
                ),
            ],
          ),
          if (toComputerReason != null || toMountReason != null) ...[
            const SizedBox(height: 12),
            // Say why a direction is closed instead of showing a dead button.
            for (final reason in [toMountReason, toComputerReason])
              if (reason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
          if (_c.timeDiffers) ...[
            const SizedBox(height: 8),
            Text(
              "Taking the mount's values changes the site only — this app will "
              'not set your computer’s clock.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            NightshadeAlert(
              severity: NightshadeAlertSeverity.error,
              title: 'Not everything was applied',
              message: _error!,
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              NightshadeCheckbox(
                value: _remember,
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _remember = v ?? false),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Do this every time without asking',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => _dismiss(never: true),
                child: const Text('Never ask again'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparisonRow {
  const _ComparisonRow({
    required this.label,
    required this.computer,
    required this.mount,
  });

  final String label;
  final String computer;
  final String mount;
}

class _ComparisonTable extends StatelessWidget {
  const _ComparisonTable({required this.rows});

  final List<_ComparisonRow> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return NightshadeCard(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(flex: 2, child: SizedBox()),
              Expanded(flex: 3, child: Text('This computer', style: headerStyle)),
              Expanded(flex: 3, child: Text('The mount', style: headerStyle)),
            ],
          ),
          const Divider(height: 16),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(row.label, style: headerStyle),
                  ),
                  Expanded(flex: 3, child: Text(row.computer, style: valueStyle)),
                  Expanded(flex: 3, child: Text(row.mount, style: valueStyle)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
