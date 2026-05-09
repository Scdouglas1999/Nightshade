import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../localization/nightshade_localizations.dart';
import 'dashboard_header_actions.dart';

/// Command Bar: Fixed header with session status, quick stats, clock, and controls.
///
/// This is the central nervous system status display showing:
/// - Session status indicator (Idle/Capturing with target name)
/// - Quick stats strip: Temp | Focus | HFR | RMS
/// - Clock/LST widget
/// - Edit mode toggle and controls
class DashboardCommandBar extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final VoidCallback onToggleEdit;
  final VoidCallback onManageWidgets;
  final VoidCallback onResetLayout;

  const DashboardCommandBar({
    super.key,
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onToggleEdit,
    required this.onManageWidgets,
    required this.onResetLayout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final exposurePercent = ref.watch(exposureProgressProvider.select((s) => s.percent));
    final isDownloading = ref.watch(exposureProgressProvider.select((s) => s.isDownloading));

    final isCapturing = sessionState.isCapturing || exposurePercent > 0 || isDownloading;
    final targetName = sessionState.targetName ?? 'No Target';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Responsive thresholds for command bar elements
        final showClock = width >= 900;
        final showDividers = width >= 850;
        final showStats = width >= 800;
        final compactPadding = width < 900;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compactPadding ? 12 : 16,
            vertical: compactPadding ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusLg,
            border: Border.all(color: colors.border),
            boxShadow: NightshadeTokens.elevationLevel1,
          ),
          child: Row(
            children: [
              // Session Status - always show but constrain width
              Flexible(
                flex: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: width < 900 ? 120 : 180),
                  child: _SessionStatusIndicator(
                    colors: colors,
                    pulseController: pulseController,
                    isCapturing: isCapturing,
                    targetName: targetName,
                  ),
                ),
              ),

              if (showDividers) ...[
                SizedBox(width: compactPadding ? 12 : 24),
                Container(
                  width: 1,
                  height: 32,
                  color: colors.border,
                ),
                SizedBox(width: compactPadding ? 12 : 24),
              ] else
                SizedBox(width: compactPadding ? 8 : 16),

              // Quick Stats Strip - only show on wider layouts
              if (showStats)
                Expanded(
                  child: _QuickStatsStrip(colors: colors),
                )
              else
                const Spacer(),

              if (showDividers && showStats) ...[
                SizedBox(width: compactPadding ? 12 : 24),
                Container(
                  width: 1,
                  height: 32,
                  color: colors.border,
                ),
              ],

              SizedBox(width: compactPadding ? 8 : 16),

              // Clock/LST - hide on narrower layouts
              if (showClock) ...[
                DashboardClockWidget(colors: colors),
                SizedBox(width: compactPadding ? 8 : 16),
              ],

              // Edit Controls
              DashboardHeaderActions(
                isEditing: isEditing,
                onToggleEdit: onToggleEdit,
                onManageWidgets: onManageWidgets,
                onResetLayout: onResetLayout,
                compact: !showClock,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Session status indicator showing capture state and current target.
class _SessionStatusIndicator extends StatelessWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isCapturing;
  final String targetName;

  const _SessionStatusIndicator({
    required this.colors,
    required this.pulseController,
    required this.isCapturing,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: pulseController,
          builder: (context, child) {
            return Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCapturing
                    ? colors.success.withValues(alpha: 0.4 + pulseController.value * 0.4)
                    : colors.textMuted.withValues(alpha: 0.4 + pulseController.value * 0.3),
                boxShadow: isCapturing
                    ? [
                        BoxShadow(
                          color: colors.success.withValues(alpha: 0.3),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            );
          },
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isCapturing ? l10n.text('capturing') : l10n.text('idle'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isCapturing ? colors.success : colors.textSecondary,
                ),
              ),
              Text(
                targetName,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quick stats strip showing Temp | Focus | HFR | RMS in the command bar.
class _QuickStatsStrip extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickStatsStrip({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    // Camera temperature
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final cameraTemp = ref.watch(cameraStateProvider.select((s) => s.temperature));

    // Focuser position
    final focuserConnected = ref.watch(focuserStateProvider.select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final focuserPosition = ref.watch(focuserStateProvider.select((s) => s.position));

    // HFR from last image
    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));

    // Guiding RMS
    final guiderConnected = ref.watch(guiderStateProvider.select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final guiderIsGuiding = ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderRms = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));

    // Format values
    final tempValue = cameraConnected && cameraTemp != null
        ? '${cameraTemp.toStringAsFixed(1)}°C'
        : '---';
    final focusValue = focuserConnected && focuserPosition != null
        ? focuserPosition.toString()
        : '---';
    final hfrValue = hfr != null ? hfr.toStringAsFixed(2) : '---';
    final rmsValue = guiderConnected && guiderIsGuiding && guiderRms != null
        ? '${guiderRms.toStringAsFixed(2)}"'
        : '---';

    // Use FittedBox to scale down gracefully on narrower layouts
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        mainAxisSize: MainAxisSize.min,
        children: [
          _CommandBarStat(
            icon: LucideIcons.thermometer,
            label: l10n.text('temp'),
            value: tempValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.focus,
            label: l10n.text('focus'),
            value: focusValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.target,
            label: l10n.text('hfr'),
            value: hfrValue,
            colors: colors,
          ),
          const SizedBox(width: 16),
          _CommandBarStat(
            icon: LucideIcons.activity,
            label: l10n.text('rms'),
            value: rmsValue,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _CommandBarStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _CommandBarStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: colors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact command bar for narrow screens (<768px).
///
/// Mobile-optimized header showing:
/// - Row 1: Session status + Edit button
/// - Row 2 (optional): Compact quick stats (Temp | HFR | RMS) when capturing
class CompactDashboardCommandBar extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;
  final bool isEditing;
  final VoidCallback onToggleEdit;

  const CompactDashboardCommandBar({
    super.key,
    required this.colors,
    required this.pulseController,
    required this.isEditing,
    required this.onToggleEdit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final exposurePercent = ref.watch(exposureProgressProvider.select((s) => s.percent));
    final isDownloading = ref.watch(exposureProgressProvider.select((s) => s.isDownloading));

    final isCapturing = sessionState.isCapturing || exposurePercent > 0 || isDownloading;
    final targetName = sessionState.targetName ?? 'No Target';

    // Quick stats for mobile (only when capturing or has data)
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) ==
        DeviceConnectionState.connected;
    final cameraTemp = ref.watch(cameraStateProvider.select((s) => s.temperature));
    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));
    final guiderIsGuiding = ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderRms = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));

    final l10n = context.l10n;
    final showStats = isCapturing || cameraConnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Status + Edit
          Row(
            children: [
              // Status dot
              AnimatedBuilder(
                animation: pulseController,
                builder: (context, child) {
                  return Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCapturing
                          ? colors.success.withValues(alpha: 0.4 + pulseController.value * 0.4)
                          : colors.textMuted.withValues(alpha: 0.4),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // Status and target name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isCapturing ? l10n.text('capturing') : l10n.text('idle'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: isCapturing ? colors.success : colors.textSecondary,
                      ),
                    ),
                    if (isCapturing)
                      Text(
                        targetName,
                        style: TextStyle(
                          fontSize: 10,
                          color: colors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Edit button
              NightshadeButton(
                label: isEditing ? 'Done' : 'Edit',
                icon: isEditing ? LucideIcons.check : LucideIcons.layoutDashboard,
                variant: isEditing ? ButtonVariant.primary : ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: onToggleEdit,
              ),
            ],
          ),

          // Row 2: Compact quick stats (shown when capturing or has data)
          if (showStats) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              // Use FittedBox to scale down stats on very narrow screens
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _MobileStatChip(
                      label: l10n.text('temp'),
                      value: cameraConnected && cameraTemp != null
                          ? '${cameraTemp.toStringAsFixed(0)}°'
                          : '---',
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    _MobileStatChip(
                      label: l10n.text('hfr'),
                      value: hfr != null ? hfr.toStringAsFixed(2) : '---',
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    _MobileStatChip(
                      label: l10n.text('rms'),
                      value: guiderIsGuiding && guiderRms != null
                          ? '${guiderRms.toStringAsFixed(1)}"'
                          : '---',
                      colors: colors,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact stat display for mobile command bar.
class _MobileStatChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _MobileStatChip({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 10,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
