part of '../weather_screen.dart';

/// The page header: `cloud-sun` · "Weather" · safety chip · refresh · settings.
///
/// The chip rides in [PageHeader.actions] rather than beside the title because
/// `PageHeader` takes only a `String context` there; see notes.md deviation 1.
class _WeatherHeader extends StatelessWidget {
  final WeatherSafetyStatus status;
  final bool monitoring;
  final VoidCallback onRefresh;
  final VoidCallback onSettingsTap;
  final bool isLoading;

  const _WeatherHeader({
    required this.status,
    required this.monitoring,
    required this.onRefresh,
    required this.onSettingsTap,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: PageHeader(
        icon: NightshadeIcons.weather,
        title: 'Weather',
        actions: [
          // Flexible so the chip ellipsizes instead of pushing the header off
          // its own right edge: "Not monitored" plus two 32 px buttons plus the
          // title does not fit 360 px, and a header that overflows is worse
          // than a label that shortens.
          Flexible(
            child: NightshadeChip(
              label: weatherSafetyChipLabel(
                status: status,
                monitoring: monitoring,
              ),
              tone: weatherSafetyChipTone(
                status: status,
                monitoring: monitoring,
              ),
              dot: true,
            ),
          ),
          NightshadeIconButton(
            key: WeatherTutorialKeys.refreshBtn,
            icon: NightshadeIcons.refresh,
            tooltip: 'Refresh radar data',
            onPressed: isLoading ? null : onRefresh,
          ),
          NightshadeIconButton(
            icon: NightshadeIcons.settings,
            tooltip: 'Weather settings',
            onPressed: onSettingsTap,
          ),
        ],
      ),
    );
  }
}

/// The screen's ONE banner slot.
///
/// A stale fetch outranks a stranded auto-park policy: the first means the
/// numbers on screen may be wrong, the second means a policy will not fire.
/// Everything else the screen has to say about safety is said by the header
/// chip and the conditions HUD, so it never becomes a second banner.
class _WeatherBanner extends StatelessWidget {
  final bool showFetchFailure;
  final bool autoParkStranded;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  const _WeatherBanner({
    required this.showFetchFailure,
    required this.autoParkStranded,
    required this.onRetry,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    if (!showFetchFailure && !autoParkStranded) {
      return const SizedBox.shrink();
    }

    final banner = showFetchFailure
        ? NightshadeBanner(
            title: 'Weather data unavailable',
            message: 'Conditions may be out of date. Check your connection.',
            tone: BannerTone.error,
            action: NightshadeButton(
              label: 'Retry',
              variant: ButtonVariant.secondary,
              size: ButtonSize.small,
              onPressed: onRetry,
            ),
          )
        : NightshadeBanner(
            title: 'Auto-park will not fire',
            message: 'It also needs "Park on unsafe weather" in Automation '
                '& safety, which is off.',
            tone: BannerTone.warning,
            action: NightshadeButton(
              label: 'Open settings',
              variant: ButtonVariant.secondary,
              size: ButtonSize.small,
              onPressed: onOpenSettings,
            ),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NightshadeTokens.space2xl,
        NightshadeTokens.spaceMd,
        NightshadeTokens.space2xl,
        0,
      ),
      child: banner,
    );
  }
}

/// The radar control bar that floats over the bottom of the map.
///
/// One glass element carrying everything the loop needs: the satellite legend
/// (wide only), the transport and scrub track, the frame's time, the playback
/// speed, and a toggle that reveals the opacity and contrast sliders in place
/// rather than opening a fifth glass panel.
class _RadarControlBar extends StatelessWidget {
  /// Wide enough for the legend and one row of controls. Below it the legend
  /// goes and the readouts move under the transport.
  final bool wide;
  final List<RadarFrame> frames;
  final int currentIndex;
  final ValueChanged<int> onFrameChanged;
  final bool isPlaying;
  final VoidCallback onPlayPauseToggle;
  final double playbackSpeed;
  final ValueChanged<double> onSpeedChanged;
  final double opacity;
  final double contrast;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onContrastChanged;
  final bool displayControlsOpen;
  final VoidCallback onDisplayControlsToggle;

  const _RadarControlBar({
    required this.wide,
    required this.frames,
    required this.currentIndex,
    required this.onFrameChanged,
    required this.isPlaying,
    required this.onPlayPauseToggle,
    required this.playbackSpeed,
    required this.onSpeedChanged,
    required this.opacity,
    required this.contrast,
    required this.onOpacityChanged,
    required this.onContrastChanged,
    required this.displayControlsOpen,
    required this.onDisplayControlsToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (wide) ...[
              const SatelliteLegend(compact: true),
              const SizedBox(width: NightshadeTokens.spaceLg),
            ],
            Expanded(
              child: RadarTimelineScrubber(
                key: WeatherTutorialKeys.timeline,
                frames: frames,
                currentIndex: currentIndex,
                onFrameChanged: onFrameChanged,
                isPlaying: isPlaying,
                onPlayPauseToggle: onPlayPauseToggle,
                playbackSpeed: playbackSpeed,
                onSpeedChanged: onSpeedChanged,
                stacked: !wide,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            NightshadeIconButton(
              icon: NightshadeIcons.sliders,
              tooltip: 'Radar display',
              size: IconButtonSize.sm,
              selected: displayControlsOpen,
              onPressed: onDisplayControlsToggle,
            ),
          ],
        ),
        if (displayControlsOpen) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          _RadarSliderRow(
            icon: NightshadeIcons.layers,
            label: 'Opacity',
            value: opacity,
            min: 0.0,
            max: 1.0,
            displayValue: '${(opacity * 100).toInt()}%',
            onChanged: onOpacityChanged,
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          _RadarSliderRow(
            icon: LucideIcons.contrast,
            label: 'Contrast',
            value: contrast,
            min: 0.0,
            max: 2.5,
            displayValue: _contrastLabel(contrast),
            onChanged: onContrastChanged,
          ),
        ],
      ],
    );
  }

  static String _contrastLabel(double value) {
    if (value <= 0.2) return 'Off';
    if (value <= 0.8) return 'Low';
    if (value <= 1.3) return 'Medium';
    if (value <= 1.8) return 'High';
    return 'Max';
  }
}

/// One labelled slider inside the control bar.
class _RadarSliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const _RadarSliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayValue,
    required this.onChanged,
  });

  /// Label column, wide enough for "Contrast" at `bodySm`.
  static const double _labelWidth = 68;

  /// Value column, wide enough for "100%" and "Medium".
  static const double _valueWidth = 56;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      children: [
        Icon(icon, size: NightshadeTokens.iconSm, color: colors.textMuted),
        const SizedBox(width: NightshadeTokens.spaceSm),
        SizedBox(
          width: _labelWidth,
          child: Text(
            label,
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: NightshadeSlider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        SizedBox(
          width: _valueWidth,
          child: Text(
            displayValue,
            textAlign: TextAlign.end,
            style: NightshadeTypography.readoutSm.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The single loading pattern for this screen.
class _WeatherLoadingBody extends StatelessWidget {
  const _WeatherLoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

/// No observing site: the radar is the only thing that needs one.
///
/// A connected weather station or safety monitor reports without knowing where
/// it is, and hiding those readings behind a location setting they have nothing
/// to do with was the 2026-07-29 defect this layout keeps fixed. So the empty
/// state owns the body and the sensors follow only when a device is actually
/// connected.
class _NoLocationBody extends ConsumerWidget {
  const _NoLocationBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final hasSensors = ref.watch(weatherStateProvider).connectionState ==
            DeviceConnectionState.connected ||
        ref.watch(safetyMonitorStateProvider).connectionState ==
            DeviceConnectionState.connected;

    return Padding(
      padding: const EdgeInsets.all(NightshadeTokens.space2xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: NightshadeDecorations.well(colors),
              child: Center(
                child: EmptyState(
                  icon: NightshadeIcons.location,
                  title: 'No observing site',
                  body: 'Radar needs to know where you are before it can show '
                      'the sky above you.',
                  action: NightshadeButton(
                    label: 'Set your location',
                    variant: ButtonVariant.secondary,
                    size: ButtonSize.small,
                    onPressed: () => context.go('/settings?section=location'),
                  ),
                ),
              ),
            ),
          ),
          if (hasSensors) ...[
            const SizedBox(height: NightshadeTokens.spaceLg),
            const NightshadePanel(
              head: PanelHead(
                icon: NightshadeIcons.weather,
                label: 'Conditions',
              ),
              child: _WeatherConditions(
                alert: null,
                motion: null,
                lastUpdate: null,
                cloudCoverPercent: null,
                alertRadiusKm: null,
                expanded: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The settings store could not be read, so no verdict can be trusted.
class _SettingsUnavailableBody extends StatelessWidget {
  final VoidCallback onRetry;

  const _SettingsUnavailableBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: NightshadeIcons.warning,
        title: 'Weather settings unavailable',
        body: 'The observing location and weather configuration could not be '
            'loaded, so conditions are unknown.',
        action: NightshadeButton(
          label: 'Retry',
          icon: NightshadeIcons.refresh,
          variant: ButtonVariant.secondary,
          size: ButtonSize.small,
          onPressed: onRetry,
        ),
      ),
    );
  }
}
