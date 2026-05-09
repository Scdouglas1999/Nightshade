import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Panel displaying astronomical transient alerts (novae, supernovae, etc.)
/// with the ability to queue them as observation targets.
///
/// Shows recent alerts from AAVSO and TNS sources, sorted by priority.
/// Each alert shows name, type, magnitude, coordinates, and discovery date.
/// Users can queue alerts for tonight's observation or dismiss them.
class TransientAlertsPanel extends ConsumerWidget {
  const TransientAlertsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final alertsAsync = ref.watch(activeTransientAlertsProvider);
    final alertStates = ref.watch(transientAlertStatesProvider);

    return NightshadeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Icon(LucideIcons.zap, size: 18, color: colors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Transient Alerts',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                // Unacknowledged badge
                _UnacknowledgedBadge(colors: colors),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(LucideIcons.refreshCw,
                      size: 16, color: colors.textSecondary),
                  tooltip: 'Refresh alerts',
                  onPressed: () => refreshTransientAlerts(ref),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(LucideIcons.settings,
                      size: 16, color: colors.textSecondary),
                  tooltip: 'Alert settings',
                  onPressed: () => _showSettingsDialog(context, ref),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Alert list
          alertsAsync.when(
            data: (alerts) {
              if (alerts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.bellOff,
                            size: 32, color: colors.textMuted),
                        const SizedBox(height: 8),
                        Text(
                          'No transient alerts',
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check back later or adjust filter settings.',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Show up to 10 alerts, with actionable ones first
              final displayAlerts = _sortForDisplay(alerts, alertStates);
              final limited = displayAlerts.take(10).toList();

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < limited.length; i++) ...[
                    _TransientAlertTile(
                      alert: limited[i],
                      alertState: alertStates[limited[i].id],
                    ),
                    if (i < limited.length - 1)
                      Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: colors.border,
                      ),
                  ],
                  if (alerts.length > 10)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '${alerts.length - 10} more alerts not shown',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 16, color: colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Failed to load alerts: $error',
                      style: TextStyle(fontSize: 12, color: colors.error),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.refreshCw,
                        size: 14, color: colors.error),
                    onPressed: () => refreshTransientAlerts(ref),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<TransientAlert> _sortForDisplay(
    List<TransientAlert> alerts,
    Map<String, TransientAlertState> states,
  ) {
    final sorted = List<TransientAlert>.from(alerts);
    sorted.sort((a, b) {
      final aState = states[a.id] ?? TransientAlertState.newAlert;
      final bState = states[b.id] ?? TransientAlertState.newAlert;

      // New/unacknowledged first
      final aActionable = aState == TransientAlertState.newAlert ||
          aState == TransientAlertState.acknowledged;
      final bActionable = bState == TransientAlertState.newAlert ||
          bState == TransientAlertState.acknowledged;

      if (aActionable && !bActionable) return -1;
      if (!aActionable && bActionable) return 1;

      // Then by priority
      return a.priority.compareTo(b.priority);
    });
    return sorted;
  }

  void _showSettingsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => _TransientSettingsDialog(),
    );
  }
}

// =============================================================================
// Unacknowledged Badge
// =============================================================================

class _UnacknowledgedBadge extends ConsumerWidget {
  final NightshadeColors colors;

  const _UnacknowledgedBadge({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unacknowledgedAlertCountProvider);
    if (count == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.warning,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: colors.background,
        ),
      ),
    );
  }
}

// =============================================================================
// Transient Alert Tile
// =============================================================================

class _TransientAlertTile extends ConsumerWidget {
  final TransientAlert alert;
  final TransientAlertState? alertState;

  const _TransientAlertTile({
    required this.alert,
    this.alertState,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final effectiveState = alertState ?? TransientAlertState.newAlert;
    final isNew = effectiveState == TransientAlertState.newAlert;
    final isDismissed = effectiveState == TransientAlertState.dismissed;
    final isQueued = effectiveState == TransientAlertState.queued;
    final isObserved = effectiveState == TransientAlertState.observed;

    return Opacity(
      opacity: isDismissed ? 0.5 : 1.0,
      child: InkWell(
        onTap: isNew
            ? () => ref
                .read(transientAlertStatesProvider.notifier)
                .acknowledge(alert.id)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Priority/type indicator
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _TypeBadge(type: alert.type, priority: alert.priority),
              ),
              const SizedBox(width: 10),

              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alert.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  isNew ? FontWeight.w700 : FontWeight.w500,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                        if (isNew)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                          ),
                        if (isQueued)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'QUEUED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: colors.success,
                              ),
                            ),
                          ),
                        if (isObserved)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.info.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'OBSERVED',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: colors.info,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Type, magnitude, coordinates
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          _typeLabel(alert.type),
                          style:
                              TextStyle(fontSize: 11, color: colors.textMuted),
                        ),
                        if (alert.magnitude != null)
                          Text(
                            'mag ${alert.magnitude!.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          'RA ${_formatRa(alert.raHours)} Dec ${_formatDec(alert.decDegrees)}',
                          style:
                              TextStyle(fontSize: 11, color: colors.textMuted),
                        ),
                        Text(
                          DateFormat('MMM d').format(alert.discoveryTime),
                          style:
                              TextStyle(fontSize: 11, color: colors.textMuted),
                        ),
                      ],
                    ),
                    if (alert.classification != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        alert.classification!,
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Action buttons
              if (!isDismissed && !isQueued && !isObserved) ...[
                const SizedBox(width: 8),
                Column(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        icon: Icon(LucideIcons.plus,
                            size: 14, color: colors.success),
                        tooltip: 'Queue for tonight',
                        onPressed: () => queueTransientForTonight(ref, alert),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        icon: Icon(LucideIcons.x,
                            size: 14, color: colors.textMuted),
                        tooltip: 'Dismiss',
                        onPressed: () => ref
                            .read(transientAlertStatesProvider.notifier)
                            .dismiss(alert.id),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(TransientType type) {
    switch (type) {
      case TransientType.nova:
        return 'Nova';
      case TransientType.supernova:
        return 'Supernova';
      case TransientType.cataclysmic:
        return 'Cataclysmic Variable';
      case TransientType.comet:
        return 'Comet';
      case TransientType.asteroid:
        return 'Asteroid';
      case TransientType.variableStar:
        return 'Variable Star';
      case TransientType.gammaRayBurst:
        return 'GRB Afterglow';
      case TransientType.other:
        return 'Other';
    }
  }

  String _formatRa(double raHours) {
    final h = raHours.truncate();
    final m = ((raHours - h) * 60).truncate();
    final s = (((raHours - h) * 60 - m) * 60).truncate();
    return '${h}h${m.toString().padLeft(2, '0')}m${s.toString().padLeft(2, '0')}s';
  }

  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final absDec = decDegrees.abs();
    final d = absDec.truncate();
    final m = ((absDec - d) * 60).truncate();
    return "$sign$d\u00b0${m.toString().padLeft(2, '0')}'";
  }
}

// =============================================================================
// Type Badge
// =============================================================================

class _TypeBadge extends StatelessWidget {
  final TransientType type;
  final int priority;

  const _TypeBadge({required this.type, required this.priority});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    IconData icon;
    Color color;
    switch (type) {
      case TransientType.supernova:
        icon = LucideIcons.sparkles;
        color = colors.warning;
      case TransientType.nova:
        icon = LucideIcons.zap;
        color = colors.warning;
      case TransientType.cataclysmic:
        icon = LucideIcons.flame;
        color = colors.error;
      case TransientType.gammaRayBurst:
        icon = LucideIcons.radio;
        color = colors.accent;
      case TransientType.comet:
        icon = LucideIcons.orbit;
        color = colors.info;
      case TransientType.asteroid:
        icon = LucideIcons.diamond;
        color = colors.textSecondary;
      case TransientType.variableStar:
        icon = LucideIcons.star;
        color = colors.warning;
      case TransientType.other:
        icon = LucideIcons.helpCircle;
        color = colors.textMuted;
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 14, color: color),
    );
  }
}

// =============================================================================
// Settings Dialog
// =============================================================================

class _TransientSettingsDialog extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final settings = ref.watch(transientAlertSettingsProvider);
    final notifier = ref.read(transientAlertSettingsProvider.notifier);

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Transient Alert Settings',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sources
              Text(
                'Alert Sources',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ...TransientSource.values.map((source) {
                return CheckboxListTile(
                  title: Text(
                    _sourceLabel(source),
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textPrimary,
                    ),
                  ),
                  subtitle: source == TransientSource.tns
                      ? Text(
                          'Requires API key',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                        )
                      : null,
                  dense: true,
                  value: settings.enabledSources.contains(source),
                  onChanged: (_) => notifier.toggleSource(source),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),

              const SizedBox(height: 16),

              // Magnitude threshold
              Text(
                'Magnitude Threshold',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Only show objects brighter than this magnitude',
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '5',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.magnitudeThreshold,
                      min: 5.0,
                      max: 20.0,
                      divisions: 30,
                      label: settings.magnitudeThreshold.toStringAsFixed(1),
                      onChanged: (val) => notifier.setMagnitudeThreshold(val),
                    ),
                  ),
                  Text(
                    '20',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '<= ${settings.magnitudeThreshold.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Types to monitor
              Text(
                'Types to Monitor',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: TransientType.values.map((type) {
                  final isEnabled = settings.typesToMonitor.contains(type);
                  return FilterChip(
                    label: Text(
                      _typeLabel(type),
                      style: TextStyle(
                        fontSize: 11,
                        color:
                            isEnabled ? colors.primary : colors.textSecondary,
                      ),
                    ),
                    selected: isEnabled,
                    onSelected: (_) => notifier.toggleType(type),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Notification settings
              SwitchListTile(
                title: Text(
                  'Notify on new alerts',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textPrimary,
                  ),
                ),
                dense: true,
                value: settings.notifyOnNew,
                onChanged: (val) => notifier.setNotifyOnNew(val),
              ),
              SwitchListTile(
                title: Text(
                  'Auto-queue bright transients',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Automatically add transients brighter than mag ${settings.autoQueueMagnitude.toStringAsFixed(0)} to targets',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
                dense: true,
                value: settings.autoQueueBright,
                onChanged: (val) => notifier.setAutoQueueBright(val),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _sourceLabel(TransientSource source) {
    switch (source) {
      case TransientSource.aavso:
        return 'AAVSO (Variable Stars)';
      case TransientSource.tns:
        return 'TNS (Transient Name Server)';
      case TransientSource.mpec:
        return 'MPEC (Minor Planets)';
      case TransientSource.cbat:
        return 'CBAT (Astronomical Telegrams)';
      case TransientSource.manual:
        return 'Manual Entries';
    }
  }

  String _typeLabel(TransientType type) {
    switch (type) {
      case TransientType.nova:
        return 'Nova';
      case TransientType.supernova:
        return 'Supernova';
      case TransientType.cataclysmic:
        return 'Cataclysmic';
      case TransientType.comet:
        return 'Comet';
      case TransientType.asteroid:
        return 'Asteroid';
      case TransientType.variableStar:
        return 'Variable';
      case TransientType.gammaRayBurst:
        return 'GRB';
      case TransientType.other:
        return 'Other';
    }
  }
}
