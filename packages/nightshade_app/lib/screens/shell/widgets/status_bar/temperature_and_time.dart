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

/// Whether the operator has actually given us an observing site.
///
/// 0/0 is the app's documented "not set" sentinel — see `locationSyncProvider`,
/// which deliberately refuses to guess a site. Every location-driven surface is
/// supposed to have an honest empty state for it.
@visibleForTesting
bool siteLocationIsSet(double latitude, double longitude) =>
    latitude != 0.0 || longitude != 0.0;

/// The LST chip's text.
///
/// `lstHours` is null when there is no site to compute it for.
///
/// The chip used to render the raw [localSiderealTimeProvider] value
/// unconditionally, and that provider's observer defaults to **Los Angeles**
/// (`PlanetariumObserver`), while `locationSyncProvider` only pushes the real
/// site once one is configured — and its two paths disagree about the 0/0
/// sentinel, so an unconfigured rig showed either LA's or Greenwich's sidereal
/// time depending on load order. A precise "LST 21:14" for a site the operator
/// never gave is worse than no LST: sidereal time is exactly what you read to
/// decide what is transiting.
@visibleForTesting
String formatLstChip(double? lstHours) {
  if (lstHours == null) return 'LST --:--';
  // Normalized to [0, 24) upstream; fold defensively so a bad input can never
  // render as "-1:-30".
  var hours = lstHours % 24;
  if (hours < 0) hours += 24;
  final h = hours.floor();
  final m = ((hours - h) * 60).floor();
  return 'LST ${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

class _TimeDisplay extends ConsumerWidget {
  final DateTime now;
  final NightshadeColors colors;

  const _TimeDisplay({
    required this.now,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final siteIsSet = settings != null &&
        siteLocationIsSet(settings.latitude, settings.longitude);
    // Only read the LST once we know whose LST it is.
    final lst = siteIsSet ? ref.watch(localSiderealTimeProvider) : null;
    final lstTooltip = settings == null
        ? 'Loading your observing site…'
        : siteIsSet
            ? 'Local sidereal time at your observing site'
            : 'No observing site set — sidereal time is unknown. '
                'Set it in Settings → Location.';
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
        Tooltip(
          message: lstTooltip,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: NightshadeDecorations.statusChip(
              // An unknown LST must not wear the confident accent colour.
              lst == null ? colors.textMuted : colors.primary,
              borderRadius: NightshadeTokens.borderRadiusInline4,
              bordered: false,
            ),
            child: Text(
              formatLstChip(lst),
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize10,
                fontWeight: FontWeight.w500,
                color: lst == null ? colors.textMuted : colors.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
