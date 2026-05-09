import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'widgets/transient_card.dart';

/// Filter options for the transient alerts list.
enum TransientFilter {
  all('All'),
  newAlerts('New'),
  queued('Queued'),
  observed('Observed');

  const TransientFilter(this.label);
  final String label;
}

/// Provider for tracking the current filter selection.
final _transientFilterProvider = StateProvider<TransientFilter>((ref) {
  return TransientFilter.all;
});

/// Screen for managing astronomical transient alerts.
///
/// Displays a filterable list of transient alerts (novae, supernovae, comets, etc.)
/// with options to queue targets for observation, view in framing, or dismiss.
class TransientsScreen extends ConsumerWidget {
  const TransientsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final alertsAsync = ref.watch(activeTransientAlertsProvider);
    final currentFilter = ref.watch(_transientFilterProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          // Header with title and actions
          _TransientsHeader(
            colors: colors,
            onRefresh: () => refreshTransientAlerts(ref),
            onSettingsTap: () => _showSettingsDialog(context, ref),
          ),

          // Filter tabs
          _FilterTabBar(
            colors: colors,
            currentFilter: currentFilter,
            onFilterChanged: (filter) {
              ref.read(_transientFilterProvider.notifier).state = filter;
            },
          ),

          // Main content area
          Expanded(
            child: alertsAsync.when(
              data: (alerts) =>
                  _buildDataState(context, ref, colors, alerts, currentFilter),
              loading: () => _buildLoadingState(colors),
              error: (error, stackTrace) =>
                  _buildErrorState(context, ref, colors, error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataState(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    List<TransientAlert> alerts,
    TransientFilter filter,
  ) {
    final states = ref.watch(transientAlertStatesProvider);

    // Filter alerts based on current filter
    final filteredAlerts = _filterAlerts(alerts, states, filter);

    if (filteredAlerts.isEmpty) {
      return _buildEmptyState(colors, filter);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;

        return ListView.builder(
          padding: isMobile
              ? NightshadeTokens.screenPaddingCompact
              : NightshadeTokens.screenPadding,
          itemCount: filteredAlerts.length,
          itemBuilder: (context, index) {
            final alert = filteredAlerts[index];
            final alertState = states[alert.id];
            return Padding(
              padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
              child: TransientCard(
                alert: alert,
                state: alertState,
                onQueue: () => _queueAlert(context, ref, alert),
                onViewInFraming: () => _viewInFraming(context, alert),
                onDismiss: () => _dismissAlert(ref, alert),
              ),
            );
          },
        );
      },
    );
  }

  List<TransientAlert> _filterAlerts(
    List<TransientAlert> alerts,
    Map<String, TransientAlertState> states,
    TransientFilter filter,
  ) {
    switch (filter) {
      case TransientFilter.all:
        return alerts;
      case TransientFilter.newAlerts:
        return alerts.where((alert) {
          final state = states[alert.id];
          return state == null || state == TransientAlertState.newAlert;
        }).toList();
      case TransientFilter.queued:
        return alerts.where((alert) {
          return states[alert.id] == TransientAlertState.queued;
        }).toList();
      case TransientFilter.observed:
        return alerts.where((alert) {
          return states[alert.id] == TransientAlertState.observed;
        }).toList();
    }
  }

  Widget _buildLoadingState(NightshadeColors colors) {
    return ShimmerLoading(
      child: ListView.builder(
        padding: NightshadeTokens.screenPadding,
        itemCount: 5,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
            child: _TransientCardSkeleton(colors: colors),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(NightshadeColors colors, TransientFilter filter) {
    final String message;
    final IconData icon;

    switch (filter) {
      case TransientFilter.all:
        message = 'No transient alerts';
        icon = LucideIcons.sparkles;
      case TransientFilter.newAlerts:
        message = 'No new alerts';
        icon = LucideIcons.bellOff;
      case TransientFilter.queued:
        message = 'No queued alerts';
        icon = LucideIcons.listChecks;
      case TransientFilter.observed:
        message = 'No observed alerts';
        icon = LucideIcons.eye;
    }

    return Center(
      child: Padding(
        padding: NightshadeTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: NightshadeTokens.icon2xl,
              color: colors.textMuted,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              filter == TransientFilter.all
                  ? 'Transient alerts from AAVSO, TNS, and other sources will appear here when available.'
                  : 'No alerts match the current filter.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    Object error,
  ) {
    return Center(
      child: Padding(
        padding: NightshadeTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: NightshadeTokens.icon2xl,
              color: colors.error,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              'Failed to load transient alerts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXl),
            NightshadeButton(
              label: 'Retry',
              icon: LucideIcons.refreshCw,
              onPressed: () => refreshTransientAlerts(ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _queueAlert(
      BuildContext context, WidgetRef ref, TransientAlert alert) async {
    await queueTransientForTonight(ref, alert);
  }

  void _viewInFraming(BuildContext context, TransientAlert alert) {
    // Navigate to framing screen with the alert coordinates
    // Encode RA and Dec as query parameters
    context.go(
      '/framing?ra=${alert.raHours}&dec=${alert.decDegrees}&name=${Uri.encodeComponent(alert.name)}',
    );
  }

  void _dismissAlert(WidgetRef ref, TransientAlert alert) {
    ref.read(transientAlertStatesProvider.notifier).dismiss(alert.id);
  }

  void _showSettingsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => _TransientSettingsDialog(ref: ref),
    );
  }
}

/// Header widget for the transients screen with title, refresh, and settings buttons.
class _TransientsHeader extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onRefresh;
  final VoidCallback onSettingsTap;

  const _TransientsHeader({
    required this.colors,
    required this.onRefresh,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: NightshadeTokens.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceLg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              LucideIcons.sparkles,
              size: NightshadeTokens.iconMd,
              color: colors.warning,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Text(
            'Transient Alerts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(LucideIcons.refreshCw,
                size: NightshadeTokens.iconMd),
            onPressed: onRefresh,
            tooltip: 'Refresh alerts',
            color: colors.textSecondary,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          IconButton(
            icon:
                const Icon(LucideIcons.settings, size: NightshadeTokens.iconMd),
            onPressed: onSettingsTap,
            tooltip: 'Alert settings',
            color: colors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Filter tab bar for switching between alert categories.
class _FilterTabBar extends StatelessWidget {
  final NightshadeColors colors;
  final TransientFilter currentFilter;
  final ValueChanged<TransientFilter> onFilterChanged;

  const _FilterTabBar({
    required this.colors,
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: TransientFilter.values.map((filter) {
          final isSelected = filter == currentFilter;
          return Padding(
            padding: const EdgeInsets.only(right: NightshadeTokens.spaceSm),
            child: _FilterChip(
              label: filter.label,
              isSelected: isSelected,
              colors: colors,
              onTap: () => onFilterChanged(filter),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Individual filter chip button.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Material(
      color: isSelected ? colors.primary : colors.surfaceAlt,
      borderRadius: NightshadeTokens.borderRadiusFull,
      child: InkWell(
        onTap: onTap,
        borderRadius: NightshadeTokens.borderRadiusFull,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceSm,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isSelected ? onPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Skeleton loading cards for transient items.
class _TransientCardSkeleton extends StatelessWidget {
  final NightshadeColors colors;

  const _TransientCardSkeleton({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      padding: NightshadeTokens.cardPadding,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SkeletonBox(
                  width: 32,
                  height: 32,
                  borderRadius: NightshadeTokens.radiusMd),
              SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 150, height: 16),
                    SizedBox(height: NightshadeTokens.spaceXs),
                    SkeletonBox(width: 80, height: 12),
                  ],
                ),
              ),
              SkeletonBox(
                  width: 60,
                  height: 24,
                  borderRadius: NightshadeTokens.radiusFull),
            ],
          ),
          SizedBox(height: NightshadeTokens.spaceMd),
          SkeletonBox(width: double.infinity, height: 14),
          SizedBox(height: NightshadeTokens.spaceSm),
          SkeletonBox(width: 200, height: 14),
          SizedBox(height: NightshadeTokens.spaceMd),
          Row(
            children: [
              SkeletonBox(
                  width: 80,
                  height: 32,
                  borderRadius: NightshadeTokens.radiusSm),
              SizedBox(width: NightshadeTokens.spaceSm),
              SkeletonBox(
                  width: 100,
                  height: 32,
                  borderRadius: NightshadeTokens.radiusSm),
              SizedBox(width: NightshadeTokens.spaceSm),
              SkeletonBox(
                  width: 70,
                  height: 32,
                  borderRadius: NightshadeTokens.radiusSm),
            ],
          ),
        ],
      ),
    );
  }
}

/// Settings dialog for configuring transient alert preferences.
class _TransientSettingsDialog extends ConsumerWidget {
  final WidgetRef ref;

  const _TransientSettingsDialog({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final settings = ref.watch(transientAlertSettingsProvider);
    final notifier = ref.read(transientAlertSettingsProvider.notifier);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: NightshadeTokens.borderRadiusXl,
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: NightshadeTokens.dialogPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  LucideIcons.settings,
                  size: NightshadeTokens.iconMd,
                ),
                const SizedBox(width: NightshadeTokens.spaceMd),
                Text(
                  'Alert Settings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon:
                      const Icon(LucideIcons.x, size: NightshadeTokens.iconMd),
                  onPressed: () => Navigator.of(context).pop(),
                  color: colors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),

            // Sources section
            Text(
              'Alert Sources',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Wrap(
              spacing: NightshadeTokens.spaceSm,
              runSpacing: NightshadeTokens.spaceSm,
              children: TransientSource.values.map((source) {
                final isEnabled = settings.enabledSources.contains(source);
                return FilterChip(
                  label: Text(_getSourceLabel(source)),
                  selected: isEnabled,
                  onSelected: (_) => notifier.toggleSource(source),
                  selectedColor: colors.primary.withValues(alpha: 0.2),
                  checkmarkColor: colors.primary,
                  labelStyle: TextStyle(
                    color: isEnabled ? colors.primary : colors.textSecondary,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: NightshadeTokens.spaceLg),

            // Types section
            Text(
              'Transient Types',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Wrap(
              spacing: NightshadeTokens.spaceSm,
              runSpacing: NightshadeTokens.spaceSm,
              children: TransientType.values.map((type) {
                final isEnabled = settings.typesToMonitor.contains(type);
                return FilterChip(
                  label: Text(_getTypeLabel(type)),
                  selected: isEnabled,
                  onSelected: (_) => notifier.toggleType(type),
                  selectedColor: colors.primary.withValues(alpha: 0.2),
                  checkmarkColor: colors.primary,
                  labelStyle: TextStyle(
                    color: isEnabled ? colors.primary : colors.textSecondary,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: NightshadeTokens.spaceLg),

            // Magnitude threshold
            Text(
              'Magnitude Threshold',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: colors.primary,
                      inactiveTrackColor: colors.surfaceAlt,
                      thumbColor: colors.primary,
                      overlayColor: colors.primary.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: settings.magnitudeThreshold,
                      min: 5.0,
                      max: 20.0,
                      divisions: 30,
                      onChanged: (value) =>
                          notifier.setMagnitudeThreshold(value),
                    ),
                  ),
                ),
                const SizedBox(width: NightshadeTokens.spaceMd),
                SizedBox(
                  width: 50,
                  child: Text(
                    'mag ${settings.magnitudeThreshold.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Only show alerts brighter than this magnitude',
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),

            const SizedBox(height: NightshadeTokens.spaceLg),

            // Notifications toggle
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Show notifications for new alerts',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.notifyOnNew,
                  onChanged: (value) => notifier.setNotifyOnNew(value),
                  activeTrackColor: colors.primary,
                  activeThumbColor: Colors.white,
                ),
              ],
            ),

            const SizedBox(height: NightshadeTokens.spaceLg),

            // Close button
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                label: 'Done',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getSourceLabel(TransientSource source) {
    switch (source) {
      case TransientSource.aavso:
        return 'AAVSO';
      case TransientSource.tns:
        return 'TNS';
      case TransientSource.mpec:
        return 'MPEC';
      case TransientSource.cbat:
        return 'CBAT';
      case TransientSource.manual:
        return 'Manual';
    }
  }

  String _getTypeLabel(TransientType type) {
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
        return 'Variable Star';
      case TransientType.gammaRayBurst:
        return 'GRB';
      case TransientType.other:
        return 'Other';
    }
  }
}
