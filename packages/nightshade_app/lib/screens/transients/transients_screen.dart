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
class TransientsScreen extends StatelessWidget {
  const TransientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: const SafeArea(
        bottom: false,
        child: TransientsView(),
      ),
    );
  }
}

/// Embeddable transient-alerts content: header, citizen-science strip, filter
/// bar, and the filtered alert list. Supplies no Scaffold/AppBar so it can sit
/// inside the Science screen's "Observing Alerts" tab as well as the standalone
/// [TransientsScreen].
class TransientsView extends ConsumerWidget {
  const TransientsView({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final alertsAsync = ref.watch(activeTransientAlertsProvider);
    final currentFilter = ref.watch(_transientFilterProvider);

    return Column(
      children: [
        if (showHeader)
          ScreenHeader(
            title: 'Observing Alerts',
            icon: NightshadeIcons.sparkle,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(NightshadeIcons.refresh,
                      size: NightshadeTokens.iconMd),
                  onPressed: () => refreshTransientAlerts(ref),
                  tooltip: 'Refresh alerts',
                  color: colors.textSecondary,
                  constraints: const BoxConstraints(
                    minWidth: NightshadeTokens.minTouchTarget,
                    minHeight: NightshadeTokens.minTouchTarget,
                  ),
                ),
                IconButton(
                  icon: const Icon(NightshadeIcons.settings,
                      size: NightshadeTokens.iconMd),
                  onPressed: () => showTransientSettingsDialog(context, ref),
                  tooltip: 'Alert settings',
                  color: colors.textSecondary,
                  constraints: const BoxConstraints(
                    minWidth: NightshadeTokens.minTouchTarget,
                    minHeight: NightshadeTokens.minTouchTarget,
                  ),
                ),
              ],
            ),
          ),

        _CitizenScienceStrip(colors: colors),

        _FilterTabBar(
          colors: colors,
          currentFilter: currentFilter,
          onFilterChanged: (filter) {
            ref.read(_transientFilterProvider.notifier).state = filter;
          },
        ),

        Expanded(
          child: alertsAsync.when(
            data: (alerts) =>
                _buildDataState(context, ref, alerts, currentFilter),
            loading: () => _buildLoadingState(),
            error: (error, stackTrace) => _buildErrorState(ref, error),
          ),
        ),
      ],
    );
  }

  Widget _buildDataState(
    BuildContext context,
    WidgetRef ref,
    List<TransientAlert> alerts,
    TransientFilter filter,
  ) {
    final states = ref.watch(transientAlertStatesProvider);

    // Filter alerts based on current filter
    final filteredAlerts = _filterAlerts(alerts, states, filter);

    if (filteredAlerts.isEmpty) {
      return _buildEmptyState(filter);
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
                onViewInFraming: () => _viewInFraming(context, ref, alert),
                onOpenScience: () => _openScience(context, alert),
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

  Widget _buildLoadingState() {
    return ShimmerLoading(
      child: ListView.builder(
        padding: NightshadeTokens.screenPadding,
        itemCount: 5,
        itemBuilder: (context, index) {
          return const Padding(
            padding: EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
            child: _TransientCardSkeleton(),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(TransientFilter filter) {
    final String message;
    final IconData icon;

    switch (filter) {
      case TransientFilter.all:
        message = 'No transient alerts';
        icon = NightshadeIcons.sparkle;
      case TransientFilter.newAlerts:
        message = 'No new alerts';
        icon = NightshadeIcons.notificationsOff;
      case TransientFilter.queued:
        message = 'No queued alerts';
        icon = NightshadeIcons.checklist;
      case TransientFilter.observed:
        message = 'No observed alerts';
        icon = NightshadeIcons.visible;
    }

    return EmptyState(
      icon: icon,
      title: message,
      body: filter == TransientFilter.all
          ? 'Transient alerts from AAVSO, TNS, and other sources will appear here when available.'
          : 'No alerts match the current filter.',
    );
  }

  Widget _buildErrorState(WidgetRef ref, Object error) {
    return EmptyState(
      icon: LucideIcons.alertCircle,
      title: 'Failed to load transient alerts',
      body: error.toString(),
      action: NightshadeButton(
        label: 'Retry',
        icon: NightshadeIcons.refresh,
        onPressed: () => refreshTransientAlerts(ref),
      ),
    );
  }

  Future<void> _queueAlert(
      BuildContext context, WidgetRef ref, TransientAlert alert) async {
    await queueTransientForTonight(ref, alert);
  }

  void _viewInFraming(BuildContext context, WidgetRef ref, TransientAlert alert) {
    // Seed the target before navigating: the /framing route redirects to
    // /planner?tab=sky&view=framing, which drops any query params.
    ref.read(framingProvider.notifier).setTargetCoordinates(
          alert.raHours,
          alert.decDegrees,
          name: alert.name,
        );
    context.goNamed('framing');
  }

  void _openScience(BuildContext context, TransientAlert alert) {
    context.go('/science');
  }

  void _dismissAlert(WidgetRef ref, TransientAlert alert) {
    ref.read(transientAlertStatesProvider.notifier).dismiss(alert.id);
  }
}

/// Opens the transient alert settings dialog. Shared by [TransientsView] and the
/// Science screen header when the view is embedded without its own header.
void showTransientSettingsDialog(BuildContext context, WidgetRef ref) {
  showDialog(
    context: context,
    builder: (context) => _TransientSettingsDialog(ref: ref),
  );
}

/// Framing strip presenting transient alerts as a citizen-science feed.
class _CitizenScienceStrip extends StatelessWidget {
  final NightshadeColors colors;

  const _CitizenScienceStrip({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
            decoration: NightshadeDecorations.tintedBadge(colors.info),
            child: Icon(
              LucideIcons.microscope,
              size: NightshadeTokens.iconSm,
              color: colors.info,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Text(
              'Real targets for citizen science. Queue an alert, capture it, '
              'and turn the result into a photometric or astrometric report.',
              style: NightshadeTypography.caption.copyWith(
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
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
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: TransientFilter.values.map((filter) {
            return Padding(
              padding: const EdgeInsets.only(right: NightshadeTokens.spaceSm),
              child: NightshadeChip(
                label: filter.label,
                selected: filter == currentFilter,
                onTap: () => onFilterChanged(filter),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Skeleton loading cards for transient items.
class _TransientCardSkeleton extends StatelessWidget {
  const _TransientCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusLg,
      padding: NightshadeTokens.cardPadding,
      child: Column(
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
    final colors = NightshadeColors.of(context);
    final settings = ref.watch(transientAlertSettingsProvider);
    final notifier = ref.read(transientAlertSettingsProvider.notifier);

    return NightshadeDialog(
      title: 'Alert Settings',
      icon: NightshadeIcons.settings,
      width: 400,
      actions: [
        NightshadeButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alert Sources',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: TransientSource.values.map((source) {
              return NightshadeChip(
                label: _getSourceLabel(source),
                selected: settings.enabledSources.contains(source),
                onTap: () => notifier.toggleSource(source),
              );
            }).toList(),
          ),

          const SizedBox(height: NightshadeTokens.spaceLg),

          Text(
            'Transient Types',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: TransientType.values.map((type) {
              return NightshadeChip(
                label: _getTypeLabel(type),
                selected: settings.typesToMonitor.contains(type),
                onTap: () => notifier.toggleType(type),
              );
            }).toList(),
          ),

          const SizedBox(height: NightshadeTokens.spaceLg),

          Text(
            'Magnitude Threshold',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: NightshadeSlider(
                  value: settings.magnitudeThreshold,
                  min: 5.0,
                  max: 20.0,
                  divisions: 30,
                  onChanged: (value) => notifier.setMagnitudeThreshold(value),
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              SizedBox(
                width: 50,
                child: Text(
                  'mag ${settings.magnitudeThreshold.toStringAsFixed(1)}',
                  style: NightshadeTypography.monoSm
                      .copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          Text(
            'Only show alerts brighter than this magnitude',
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textMuted),
          ),

          const SizedBox(height: NightshadeTokens.spaceLg),

          NightshadeSwitchRow(
            label: 'Notifications',
            subtitle: 'Show notifications for new alerts',
            value: settings.notifyOnNew,
            onChanged: (value) => notifier.setNotifyOnNew(value),
          ),
        ],
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
