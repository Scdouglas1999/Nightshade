part of '../status_bar.dart';

/// Small indicator showing temp comp status next to focus pill.
/// Only visible when the focuser is connected and has temperature data.
class _TempCompIndicator extends ConsumerWidget {
  final NightshadeColors colors;

  const _TempCompIndicator({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focuserState = ref.watch(focuserStateProvider);
    final focuserConnected =
        focuserState.connectionState == DeviceConnectionState.connected;

    // Only show when focuser is connected and reports temperature
    if (!focuserConnected || focuserState.temperature == null) {
      return const SizedBox.shrink();
    }

    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final tempCompEnabled = settings?.tempCompensation ?? false;

    final activeProfile = ref.watch(activeEquipmentProfileProvider);
    if (activeProfile == null) return const SizedBox.shrink();

    final profileId = activeProfile.id.toString();
    final focusService = ref.watch(focusModelServiceProvider);
    final profileData = focusService.getProfileData(profileId);
    final model = profileData?.temperatureModel;
    final hasReliableModel = model != null && model.isReliable;

    // Determine state
    Color indicatorColor;
    String tooltip;

    if (!tempCompEnabled) {
      indicatorColor = colors.textMuted;
      tooltip = 'Temp compensation disabled';
    } else if (!hasReliableModel) {
      indicatorColor = colors.warning;
      tooltip = model == null
          ? 'Temp comp enabled - no model data'
          : 'Temp comp enabled - model not yet reliable (R\u00B2=${model.rSquared.toStringAsFixed(2)})';
    } else {
      final prediction = focusService.predictFocusPosition(
        profileId: profileId,
        currentTemperature: focuserState.temperature!,
      );
      indicatorColor = colors.success;
      tooltip = prediction != null
          ? 'Temp comp active: ${model.slope.toStringAsFixed(1)} steps/\u00B0C, predicted ${prediction.position}'
          : 'Temp comp active: ${model.slope.toStringAsFixed(1)} steps/\u00B0C';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: NightshadeDecorations.tintedBadge(
          indicatorColor,
          borderRadius: NightshadeTokens.borderRadiusInline4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.thermometerSun, size: 10, color: indicatorColor),
            const SizedBox(width: 3),
            Text(
              'TC',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize9,
                fontWeight: FontWeight.w600,
                color: indicatorColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeDisplay extends ConsumerWidget {
  final DateTime now;
  final NightshadeColors colors;

  const _TimeDisplay({
    required this.now,
    required this.colors,
  });

  String _formatLST(double lstHours) {
    final h = lstHours.floor();
    final m = ((lstHours - h) * 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lst = ref.watch(localSiderealTimeProvider);
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Icon(
          NightshadeIcons.clock,
          size: 12,
          color: colors.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          timeStr,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: NightshadeDecorations.statusChip(
            colors.primary,
            borderRadius: NightshadeTokens.borderRadiusInline4,
            bordered: false,
          ),
          child: Text(
            'LST ${_formatLST(lst)}',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              fontWeight: FontWeight.w500,
              color: colors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
