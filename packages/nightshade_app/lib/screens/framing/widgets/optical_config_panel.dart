import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Panel that displays optical configuration from the active equipment profile.
/// Shows telescope specs, camera specs, FOV, and image scale.
/// Allows switching between profiles directly from the framing screen.
/// Can be dismissed via the close button; state is stored in FramingState.
class OpticalConfigPanel extends ConsumerWidget {
  const OpticalConfigPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Watch optical config from provider
    final opticalConfig = ref.watch(opticalConfigProvider);
    final activeProfile = ref.watch(activeEquipmentProfileProvider);

    return Container(
      width: 260,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with close button
          Row(
            children: [
              Icon(LucideIcons.aperture, size: 14, color: colors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'OPTICAL CONFIG',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                height: 24,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 14,
                  tooltip: 'Hide optical config panel',
                  icon: Icon(LucideIcons.x, size: 14, color: colors.textMuted),
                  onPressed: () {
                    ref
                        .read(framingProvider.notifier)
                        .setOpticalConfigPanelVisible(false);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Content based on whether config exists
          if (opticalConfig == null || !_hasValidConfig(opticalConfig))
            _buildMissingConfigState(context, colors, activeProfile)
          else
            _buildConfigDisplay(
                context, colors, opticalConfig, activeProfile, ref),
        ],
      ),
    );
  }

  bool _hasValidConfig(OpticalConfig config) {
    return config.focalLength != null && config.focalLength! > 0;
  }

  Widget _buildMissingConfigState(
    BuildContext context,
    NightshadeColors colors,
    EquipmentProfileModel? activeProfile,
  ) {
    return Column(
      children: [
        Icon(
          LucideIcons.alertTriangle,
          size: 32,
          color: colors.warning,
        ),
        const SizedBox(height: 12),
        Text(
          activeProfile == null
              ? 'No equipment profile'
              : 'No optical configuration',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          activeProfile == null
              ? 'Create and activate an equipment profile to see your field of view.'
              : 'Set up your telescope and camera to see accurate field of view.',
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        NightshadeButton(
          label: 'Configure in Equipment',
          icon: LucideIcons.settings2,
          variant: ButtonVariant.outline,
          size: ButtonSize.small,
          onPressed: () => context.go('/equipment'),
        ),
      ],
    );
  }

  Widget _buildConfigDisplay(
    BuildContext context,
    NightshadeColors colors,
    OpticalConfig config,
    EquipmentProfileModel? profile,
    WidgetRef ref,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Telescope info
        if (config.telescopeName != null) ...[
          Row(
            children: [
              const Text('\u{1F52D}', style: TextStyle(fontSize: 14)), // Telescope emoji
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  config.telescopeName!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],

        // Optical specs
        Text(
          _formatOpticalSpecs(config),
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),

        const SizedBox(height: 12),

        // Camera info
        if (config.cameraName != null) ...[
          Row(
            children: [
              const Text('\u{1F4F7}', style: TextStyle(fontSize: 14)), // Camera emoji
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  config.cameraName!,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],

        // Sensor specs
        if (config.sensorWidth != null && config.sensorHeight != null)
          Text(
            _formatSensorSpecs(config),
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),

        const SizedBox(height: 16),
        Divider(color: colors.border, height: 1),
        const SizedBox(height: 12),

        // FOV and Scale
        _buildMetricRow(
          'FOV',
          config.fovString ?? '---',
          colors,
        ),
        const SizedBox(height: 8),
        _buildMetricRow(
          'Scale',
          config.scaleString ?? '---',
          colors,
        ),

        const SizedBox(height: 16),

        // Profile switcher
        _ProfileSwitcher(currentProfile: profile),
      ],
    );
  }

  String _formatOpticalSpecs(OpticalConfig config) {
    final parts = <String>[];
    if (config.focalLength != null) {
      parts.add('${config.focalLength!.toStringAsFixed(0)}mm');
    }
    final fRatio = config.computedFocalRatio;
    if (fRatio != null) {
      parts.add('f/${fRatio.toStringAsFixed(1)}');
    }
    if (config.aperture != null) {
      parts.add('@ ${config.aperture!.toStringAsFixed(0)}mm');
    }
    return parts.join(' ');
  }

  String _formatSensorSpecs(OpticalConfig config) {
    final dims = '${config.sensorWidth} \u00D7 ${config.sensorHeight} px';
    if (config.pixelSize != null) {
      return '$dims (${config.pixelSize!.toStringAsFixed(2)}\u00B5m)';
    }
    return dims;
  }

  Widget _buildMetricRow(String label, String value, NightshadeColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _ProfileSwitcher extends ConsumerWidget {
  final EquipmentProfileModel? currentProfile;

  const _ProfileSwitcher({this.currentProfile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final profilesAsync = ref.watch(allProfilesProvider);

    return profilesAsync.when(
      data: (profiles) {
        if (profiles.isEmpty) {
          return const SizedBox.shrink();
        }

        return PopupMenuButton<int>(
          tooltip: 'Switch equipment profile',
          offset: const Offset(0, 40),
          color: colors.surfaceAlt,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: colors.border),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    currentProfile?.name ?? 'Select Profile',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
              ],
            ),
          ),
          itemBuilder: (context) => profiles.map((profile) {
            final isSelected = profile.id == currentProfile?.id;
            return PopupMenuItem<int>(
              value: profile.id,
              child: Row(
                children: [
                  if (isSelected)
                    Icon(LucideIcons.check, size: 14, color: colors.success)
                  else
                    const SizedBox(width: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      profile.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? colors.textPrimary
                            : colors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (profile.isActive)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 9,
                          color: colors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
          onSelected: (profileId) async {
            final dao = ref.read(equipmentProfilesDaoProvider);
            await dao.setActiveProfile(profileId);
          },
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(colors.textMuted),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading...',
              style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
      error: (error, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: colors.error.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle, size: 12, color: colors.error),
            const SizedBox(width: 8),
            Text(
              'Error loading profiles',
              style: TextStyle(
                fontSize: 12,
                color: colors.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
