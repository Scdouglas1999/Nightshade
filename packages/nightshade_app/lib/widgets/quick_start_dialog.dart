import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Dialog for quick session resumption on app startup.
///
/// Shows when a previous imaging session is available and offers three options:
/// - Start Fresh: loads profile, target, sequence but resets to frame 1
/// - Resume Progress: continues from where the sequence left off
/// - Skip: dismisses and goes to normal dashboard
class QuickStartDialog extends ConsumerWidget {
  final QuickStartContext quickStartContext;
  final VoidCallback onStartFresh;
  final VoidCallback onResumeProgress;
  final VoidCallback onSkip;

  const QuickStartDialog({
    super.key,
    required this.quickStartContext,
    required this.onStartFresh,
    required this.onResumeProgress,
    required this.onSkip,
  });

  /// Show the quick start dialog.
  ///
  /// Returns a Future that completes when the dialog is dismissed.
  static Future<void> show(
    BuildContext buildContext, {
    required QuickStartContext quickStartContext,
    required VoidCallback onStartFresh,
    required VoidCallback onResumeProgress,
    required VoidCallback onSkip,
  }) {
    return showDialog(
      context: buildContext,
      barrierDismissible: true,
      builder: (ctx) => QuickStartDialog(
        quickStartContext: quickStartContext,
        onStartFresh: () {
          Navigator.of(ctx).pop();
          onStartFresh();
        },
        onResumeProgress: () {
          Navigator.of(ctx).pop();
          onResumeProgress();
        },
        onSkip: () {
          Navigator.of(ctx).pop();
          onSkip();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext buildContext, WidgetRef ref) {
    final colors = Theme.of(buildContext).extension<NightshadeColors>()!;
    final theme = Theme.of(buildContext);

    return AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.3)),
      ),
      title: _buildTitle(colors, theme),
      content: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          buildContext,
          preferredWidth: 560,
          preferredHeight: 480,
          minWidth: 400,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSessionCard(colors, theme),
              const SizedBox(height: NightshadeTokens.spaceLg),
              _buildEquipmentSettingsCard(colors, theme),
              const SizedBox(height: NightshadeTokens.spaceXl),
              _buildProgressInfo(colors, theme),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        NightshadeTokens.space2xl,
        NightshadeTokens.spaceSm,
        NightshadeTokens.space2xl,
        NightshadeTokens.spaceLg,
      ),
      actions: [
        _buildActions(buildContext, colors),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays == 0) {
      return 'Today at ${_formatTime(dt)}';
    } else if (diff.inDays == 1) {
      return 'Yesterday at ${_formatTime(dt)}';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatIntegration(double hours) {
    if (hours >= 1.0) {
      return '${hours.toStringAsFixed(1)} hours';
    }
    final minutes = (hours * 60).round();
    return '$minutes minutes';
  }

  Widget _buildTitle(NightshadeColors colors, ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          ),
          child: Icon(
            LucideIcons.play,
            color: colors.primary,
            size: NightshadeTokens.iconLg,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Continue Session',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(quickStartContext.lastSessionDate),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
        // Close button
        IconButton(
          icon: Icon(LucideIcons.x, color: colors.textMuted, size: 20),
          onPressed: onSkip,
          tooltip: 'Skip',
          style: IconButton.styleFrom(
            padding: const EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(NightshadeColors colors, ThemeData theme) {
    final targetDisplay = quickStartContext.targetName ??
        quickStartContext.sessionName ??
        'Session #${quickStartContext.sessionId}';
    final profileDisplay = quickStartContext.profileName ?? 'Unknown Profile';
    final sequenceDisplay = quickStartContext.sequenceName ?? 'No Sequence';

    return NightshadeCard(
      variant: CardVariant.elevated,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Target name - prominently displayed
          Row(
            children: [
              Icon(
                LucideIcons.target,
                color: colors.primary,
                size: NightshadeTokens.iconMd,
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  targetDisplay,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          const Divider(height: 1),
          const SizedBox(height: NightshadeTokens.spaceMd),

          // Session details grid
          _SessionDetailRow(
            icon: LucideIcons.settings2,
            label: 'Equipment Profile',
            value: profileDisplay,
            colors: colors,
            theme: theme,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          _SessionDetailRow(
            icon: LucideIcons.listOrdered,
            label: 'Sequence',
            value: sequenceDisplay,
            colors: colors,
            theme: theme,
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentSettingsCard(NightshadeColors colors, ThemeData theme) {
    final snapshot = quickStartContext.equipmentSnapshot;
    if (snapshot == null || !snapshot.hasEquipmentData) {
      return const SizedBox.shrink();
    }

    return NightshadeCard(
      variant: CardVariant.standard,
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.wrench,
                color: colors.textSecondary,
                size: NightshadeTokens.iconSm,
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Equipment Settings to Restore',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),

          // Equipment settings chips
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              if (snapshot.coolerTargetTemp != null)
                _EquipmentChip(
                  icon: LucideIcons.thermometer,
                  label:
                      '${snapshot.coolerTargetTemp!.toStringAsFixed(0)}\u00B0C',
                  colors: colors,
                ),
              if (snapshot.cameraGain != null)
                _EquipmentChip(
                  icon: LucideIcons.sliders,
                  label: 'Gain: ${snapshot.cameraGain}',
                  colors: colors,
                ),
              if (snapshot.cameraOffset != null)
                _EquipmentChip(
                  icon: LucideIcons.sliders,
                  label: 'Offset: ${snapshot.cameraOffset}',
                  colors: colors,
                ),
              if (snapshot.filterPosition != null)
                _EquipmentChip(
                  icon: LucideIcons.aperture,
                  label: 'Filter ${snapshot.filterPosition! + 1}',
                  colors: colors,
                ),
              if (snapshot.focuserPosition != null)
                _EquipmentChip(
                  icon: LucideIcons.focus,
                  label: '${snapshot.focuserPosition} steps',
                  colors: colors,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressInfo(NightshadeColors colors, ThemeData theme) {
    final frames = quickStartContext.completedFrames;
    final total = quickStartContext.totalFrames;
    final integration = quickStartContext.totalIntegrationHours;

    String progressText;
    if (frames > 0 && total > 0) {
      progressText =
          '$frames/$total frames captured, ${_formatIntegration(integration)} integration';
    } else if (frames > 0) {
      progressText =
          '$frames frames captured, ${_formatIntegration(integration)} integration';
    } else if (integration > 0) {
      progressText = '${_formatIntegration(integration)} integration';
    } else {
      progressText = 'No progress yet';
    }

    return Container(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.image,
            color: colors.primary,
            size: NightshadeTokens.iconMd,
          ),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Progress',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  progressText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext buildContext, NightshadeColors colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary action buttons
        Row(
          children: [
            Expanded(
              child: NightshadeButton(
                label: 'Start Fresh',
                icon: LucideIcons.refreshCw,
                variant: ButtonVariant.outline,
                size: ButtonSize.large,
                onPressed: onStartFresh,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Expanded(
              child: NightshadeButton(
                label: 'Resume Progress',
                icon: LucideIcons.play,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
                onPressed: onResumeProgress,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        // Skip button
        Center(
          child: NightshadeButton(
            onPressed: onSkip,
            label: 'Skip',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
        ),
      ],
    );
  }
}

/// A row showing a session detail with icon, label, and value.
class _SessionDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;
  final ThemeData theme;

  const _SessionDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: colors.textMuted,
          size: NightshadeTokens.iconSm,
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// A chip displaying an equipment setting with icon.
class _EquipmentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _EquipmentChip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        border: Border.all(
          color: colors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: NightshadeTokens.iconXs,
            color: colors.textSecondary,
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
