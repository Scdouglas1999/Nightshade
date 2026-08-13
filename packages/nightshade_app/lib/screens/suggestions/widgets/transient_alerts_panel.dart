import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/transient_type_style.dart';
import '../../../utils/user_facing_error.dart';

Future<void> _runAlertStateAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update this alert.')),
      );
    }
  }
}

/// Panel displaying astronomical transient alerts (novae, supernovae, etc.)
/// with the ability to queue them as observation targets.
///
/// Shows recent alerts from the fetched sources ([kFetchableTransientSources]
/// — today, TNS alone), sorted by priority. The source label below still
/// renders every [TransientSource] because an alert already stored, imported or
/// entered by hand carries its own origin.
/// Each alert shows name, type, magnitude, coordinates, and discovery date.
/// Users can queue alerts for tonight's observation or dismiss them.
final transientPanelTnsCredentialsReadyProvider =
    FutureProvider<bool>((ref) async {
  if (ref.watch(isRemoteModeProvider)) return true;
  final science = await ref.watch(scienceSettingsProvider.future);
  if (science.tnsBotId <= 0 || science.tnsBotName.trim().isEmpty) return false;
  return ref.watch(secretsStoreProvider).has(SecretField.tnsApiKey);
});

class TransientAlertsPanel extends ConsumerStatefulWidget {
  final bool initiallyExpanded;

  const TransientAlertsPanel({super.key, this.initiallyExpanded = true});

  @override
  ConsumerState<TransientAlertsPanel> createState() =>
      _TransientAlertsPanelState();
}

class _TransientAlertsPanelState extends ConsumerState<TransientAlertsPanel> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final alertsAsync = ref.watch(activeTransientAlertsProvider);
    final alertStates = ref.watch(transientAlertStatesProvider);
    final settings = ref.watch(transientAlertSettingsProvider);
    final credentials = ref.watch(transientPanelTnsCredentialsReadyProvider);
    final feedCheck = ref.watch(transientFeedCheckProvider);
    final tnsNeedsSetup =
        settings.enabledSources.contains(TransientSource.tns) &&
            credentials.valueOrNull == false;
    final collapsedSummary = alertsAsync.when(
      loading: () => ('Checking for alerts…', colors.textMuted),
      error: (error, _) => tnsNeedsSetup
          ? ('Setup needed for live TNS alerts', colors.warning)
          : ('Fetch failed: ${userFacingError(error)}', colors.error),
      data: (alerts) {
        if (tnsNeedsSetup) {
          return ('Setup needed for live TNS alerts', colors.warning);
        }
        if (alerts.isEmpty) {
          final (label, unchecked) = _emptyFeedSummary(feedCheck);
          return (label, unchecked ? colors.warning : colors.textMuted);
        }
        final sorted = _sortForDisplay(alerts, alertStates);
        final top = sorted.first;
        final magnitude = top.magnitude == null
            ? ''
            : ', mag ${top.magnitude!.toStringAsFixed(1)}';
        return (
          '${alerts.length} alert${alerts.length == 1 ? '' : 's'} · '
              '${top.name}$magnitude',
          colors.textSecondary,
        );
      },
    );

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
                      fontSize: NightshadeTypography.fontSize15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                // Unacknowledged badge
                _UnacknowledgedBadge(colors: colors),
                const SizedBox(width: 4),
                // Checking is otherwise on a 15-minute timer with no way to ask
                // now — and no way to tell "nothing is happening" from "nothing
                // was asked".
                IconButton(
                  key: const ValueKey('transient_check_now'),
                  icon: Icon(LucideIcons.refreshCw,
                      size: 16, color: colors.textSecondary),
                  tooltip: 'Check for alerts now',
                  onPressed: () => refreshTransientAlerts(ref),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                      _expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                      color: colors.textSecondary),
                  tooltip: _expanded ? 'Collapse alerts' : 'Expand alerts',
                  onPressed: () => setState(() => _expanded = !_expanded),
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

          if (!_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                collapsedSummary.$1,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  color: collapsedSummary.$2,
                ),
              ),
            )
          else
            // Alert list
            alertsAsync.when(
              data: (alerts) {
                if (alerts.isEmpty) {
                  if (tnsNeedsSetup) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(LucideIcons.info,
                              size: 16, color: colors.warning),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'TNS alerts are enabled but not configured. Add '
                              'your bot credentials in Science settings to fetch '
                              'live alerts; manual alerts remain available.',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  final (headline, unchecked) = _emptyFeedSummary(feedCheck);
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            unchecked
                                ? LucideIcons.alertTriangle
                                : LucideIcons.bellOff,
                            size: 32,
                            color:
                                unchecked ? colors.warning : colors.textMuted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            headline,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize13,
                              color: unchecked
                                  ? colors.warning
                                  : colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _emptyFeedDetail(feedCheck),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize11,
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
                        key: ValueKey(limited[i].id),
                        alert: limited[i],
                        alertState: resolveTransientAlertState(
                          limited[i],
                          alertStates,
                        ),
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
                            fontSize: NightshadeTypography.fontSize11,
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
                    Icon(
                      tnsNeedsSetup
                          ? LucideIcons.settings
                          : LucideIcons.alertTriangle,
                      size: 16,
                      color: tnsNeedsSetup ? colors.warning : colors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tnsNeedsSetup
                            ? 'Setup needed for live TNS alerts'
                            : 'Failed to load alerts: ${userFacingError(error)}',
                        style: TextStyle(
                            fontSize: NightshadeTypography.fontSize12,
                            color:
                                tnsNeedsSetup ? colors.warning : colors.error),
                      ),
                    ),
                    if (!tnsNeedsSetup)
                      IconButton(
                        icon: Icon(LucideIcons.refreshCw,
                            size: 14, color: colors.error),
                        tooltip: 'Retry',
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

  /// The headline for an empty feed, and whether that emptiness is untrustworthy
  /// because nothing was actually polled.
  ///
  /// "No active alerts" and "we never asked anyone" look identical from the
  /// alert list, and on the app's only channel for time-critical events that is
  /// exactly the wrong ambiguity: enabling AAVSO alone (which no build fetches)
  /// produced a confident empty state.
  (String, bool) _emptyFeedSummary(TransientFeedCheck? check) {
    if (check == null) return ('Not checked yet', true);
    if (!check.contactedAnySource) {
      return ('No alert source is being checked', true);
    }
    return ('No active alerts · checked ${_ago(check.checkedAt)}', false);
  }

  String _emptyFeedDetail(TransientFeedCheck? check) {
    if (check == null) {
      return 'The first check runs when this screen opens.';
    }
    if (check.skippedSources.isNotEmpty) {
      final reasons = check.skippedSources.entries
          .map((entry) => '${_transientSourceLabel(entry.key)}: ${entry.value}')
          .join('; ');
      return check.contactedAnySource
          ? 'Not polled — $reasons.'
          : 'Nothing was polled — $reasons.';
    }
    return check.contactedAnySource
        ? 'Adjust the magnitude threshold or monitored types to widen the net.'
        : 'Enable an alert source in the settings above.';
  }

  String _ago(DateTime when) {
    final delta = DateTime.now().difference(when);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
    if (delta.inHours < 24) return '${delta.inHours} h ago';
    return DateFormat.yMMMd().add_Hm().format(when.toLocal());
  }

  List<TransientAlert> _sortForDisplay(
    List<TransientAlert> alerts,
    Map<String, TransientAlertState> states,
  ) {
    final sorted = List<TransientAlert>.from(alerts);
    sorted.sort((a, b) {
      final aState = resolveTransientAlertState(a, states);
      final bState = resolveTransientAlertState(b, states);

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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize10,
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

class _TransientAlertTile extends ConsumerStatefulWidget {
  final TransientAlert alert;
  final TransientAlertState? alertState;

  const _TransientAlertTile({
    super.key,
    required this.alert,
    this.alertState,
  });

  @override
  ConsumerState<_TransientAlertTile> createState() =>
      _TransientAlertTileState();
}

class _TransientAlertTileState extends ConsumerState<_TransientAlertTile> {
  bool _queueing = false;

  Future<void> _queue() async {
    if (_queueing) return;
    setState(() => _queueing = true);
    try {
      await queueTransientForTonight(ref, widget.alert);
    } finally {
      if (mounted) setState(() => _queueing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final alert = widget.alert;
    final effectiveState = widget.alertState ?? TransientAlertState.newAlert;
    final isNew = effectiveState == TransientAlertState.newAlert;
    final isDismissed = effectiveState == TransientAlertState.dismissed;
    final isQueued = effectiveState == TransientAlertState.queued;
    final isObserved = effectiveState == TransientAlertState.observed;

    return Opacity(
      opacity: isDismissed ? 0.5 : 1.0,
      child: InkWell(
        onTap: isNew
            ? () => _runAlertStateAction(
                  context,
                  () => ref
                      .read(transientAlertStatesProvider.notifier)
                      .acknowledge(alert.id),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Priority/type indicator
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _TypeBadge(type: alert.type),
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
                              fontSize: NightshadeTypography.fontSize13,
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
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize9,
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
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              'QUEUED',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize9,
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
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline4),
                            ),
                            child: Text(
                              'OBSERVED',
                              style: TextStyle(
                                fontSize: NightshadeTypography.fontSize9,
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
                          TransientTypeStyle.label(alert.type),
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize11,
                              color: colors.textMuted),
                        ),
                        if (alert.magnitude != null)
                          Text(
                            'mag ${alert.magnitude!.toStringAsFixed(1)}',
                            style: TextStyle(
                              fontSize: NightshadeTypography.fontSize11,
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          'RA ${_formatRa(alert.raHours)} Dec ${_formatDec(alert.decDegrees)}',
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize11,
                              color: colors.textMuted),
                        ),
                        Text(
                          DateFormat('MMM d').format(alert.discoveryTime),
                          style: TextStyle(
                              fontSize: NightshadeTypography.fontSize11,
                              color: colors.textMuted),
                        ),
                      ],
                    ),
                    if (alert.classification != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        alert.classification!,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize10,
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
                        icon: _queueing
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.success,
                                ),
                              )
                            : Icon(
                                LucideIcons.plus,
                                size: 14,
                                color: colors.success,
                              ),
                        tooltip: 'Queue for tonight',
                        onPressed: _queueing ? null : _queue,
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
                        onPressed: () => _runAlertStateAction(
                          context,
                          () => ref
                              .read(transientAlertStatesProvider.notifier)
                              .dismiss(alert.id),
                        ),
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

  String _formatRa(double raHours) => CoordinateFormat.ra(
        raHours,
        style: SexagesimalStyle.compactLeadPlainLetters,
        seconds: SecondsPrecision.integerFloored,
      );

  String _formatDec(double decDegrees) => CoordinateFormat.decDm(
        decDegrees,
        style: SexagesimalStyle.compactLeadPlainLetters,
      );
}

// =============================================================================
// Type Badge
// =============================================================================

class _TypeBadge extends StatelessWidget {
  final TransientType type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final color = TransientTypeStyle.color(type, colors);

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      ),
      child: Icon(TransientTypeStyle.icon(type), size: 14, color: color),
    );
  }
}

// =============================================================================
// Settings Dialog
// =============================================================================

class _TransientSettingsDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_TransientSettingsDialog> createState() =>
      _TransientSettingsDialogState();
}

class _TransientSettingsDialogState
    extends ConsumerState<_TransientSettingsDialog> {
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save the alert settings.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final settings = ref.watch(transientAlertSettingsProvider);
    final notifier = ref.read(transientAlertSettingsProvider.notifier);

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Transient Alert Settings',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: SizedBox(
        width: dialogMaxWidth(context, 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sources
              Text(
                'Alert Sources',
                style: NightshadeTypography.labelStrong.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              ...TransientSource.values.map((source) {
                return CheckboxListTile(
                  title: Text(
                    _transientSourceLabel(source),
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      color: colors.textPrimary,
                    ),
                  ),
                  subtitle: switch (source) {
                    TransientSource.tns => Text(
                        'Requires TNS bot credentials in Science settings',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.textMuted,
                        ),
                      ),
                    TransientSource.manual => null,
                    // Ticking a source this build cannot poll used to look
                    // exactly like subscribing to it, and then reported "No
                    // active alerts" from a feed nobody ever asked.
                    _ when !kFetchableTransientSources.contains(source) => Text(
                        'Not polled — this build has no live feed for it; '
                        'alerts from it can still be entered by hand',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.warning,
                        ),
                      ),
                    _ => null,
                  },
                  dense: true,
                  value: settings.enabledSources.contains(source),
                  onChanged: (_) => _run(() => notifier.toggleSource(source)),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              }),

              const SizedBox(height: 16),

              // Magnitude threshold
              Text(
                'Magnitude Threshold',
                style: NightshadeTypography.labelStrong.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Only show objects brighter than this magnitude',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textMuted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '5',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textMuted),
                  ),
                  Expanded(
                    child: Slider(
                      value: settings.magnitudeThreshold,
                      min: 5.0,
                      max: 20.0,
                      divisions: 30,
                      label: settings.magnitudeThreshold.toStringAsFixed(1),
                      onChanged: (val) =>
                          _run(() => notifier.setMagnitudeThreshold(val)),
                    ),
                  ),
                  Text(
                    '20',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '<= ${settings.magnitudeThreshold.toStringAsFixed(1)}',
                    style: NightshadeTypography.h6.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Types to monitor
              Text(
                'Types to Monitor',
                style: NightshadeTypography.labelStrong.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: TransientType.values.map((type) {
                  final isEnabled = settings.typesToMonitor.contains(type);
                  // The chips are a subscription list, so they must announce
                  // on/off the way the checkboxes above them already do —
                  // assistive tech saw eight plain buttons and no way to tell,
                  // or verify after toggling, which types were monitored.
                  return MergeSemantics(
                    child: Semantics(
                      checked: isEnabled,
                      child: FilterChip(
                        label: Text(
                          TransientTypeStyle.shortLabel(type),
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize11,
                            color: isEnabled
                                ? colors.primary
                                : colors.textSecondary,
                          ),
                        ),
                        selected: isEnabled,
                        onSelected: (_) =>
                            _run(() => notifier.toggleType(type)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Notification settings
              SwitchListTile(
                title: Text(
                  'Notify on new alerts',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize13,
                    color: colors.textPrimary,
                  ),
                ),
                dense: true,
                value: settings.notifyOnNew,
                onChanged: (val) => _run(() => notifier.setNotifyOnNew(val)),
              ),
              SwitchListTile(
                title: Text(
                  'Auto-queue bright transients',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize13,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Automatically add transients brighter than mag ${settings.autoQueueMagnitude.toStringAsFixed(0)} to targets',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted),
                ),
                dense: true,
                value: settings.autoQueueBright,
                onChanged: (val) =>
                    _run(() => notifier.setAutoQueueBright(val)),
              ),
              // The threshold this switch acts on. It defaults to mag 10, which
              // is brighter than almost every transient an amateur rig can
              // reach (most TNS supernovae sit at mag 13-17), so auto-queue
              // shipped switchable but effectively inert: the number was
              // settable over the headless API and by nothing in the app.
              if (settings.autoQueueBright) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Row(
                    children: [
                      Text(
                        '5',
                        style: TextStyle(
                            fontSize: NightshadeTypography.fontSize11,
                            color: colors.textMuted),
                      ),
                      Expanded(
                        child: Slider(
                          value: settings.autoQueueMagnitude.clamp(5.0, 20.0),
                          min: 5.0,
                          max: 20.0,
                          divisions: 30,
                          label: settings.autoQueueMagnitude.toStringAsFixed(1),
                          semanticFormatterCallback: (value) =>
                              'Auto-queue magnitude ${value.toStringAsFixed(1)}',
                          onChanged: (val) =>
                              _run(() => notifier.setAutoQueueMagnitude(val)),
                        ),
                      ),
                      Text(
                        '20',
                        style: TextStyle(
                            fontSize: NightshadeTypography.fontSize11,
                            color: colors.textMuted),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '<= ${settings.autoQueueMagnitude.toStringAsFixed(1)}',
                        style: NightshadeTypography.h6.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                // An auto-queue threshold fainter than the display threshold
                // can never fire: the feed drops those alerts before
                // auto-queue ever sees them.
                if (settings.autoQueueMagnitude > settings.magnitudeThreshold)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Alerts fainter than the magnitude threshold '
                      '(${settings.magnitudeThreshold.toStringAsFixed(1)}) are '
                      'filtered out before auto-queue sees them.',
                      style: TextStyle(
                          fontSize: NightshadeTypography.fontSize11,
                          color: colors.warning),
                    ),
                  ),
              ],
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
}

String _transientSourceLabel(TransientSource source) {
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
