part of '../weather_screen.dart';

/// Header with title, refresh button, and settings access
class _WeatherHeader extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onRefresh;
  final VoidCallback onSettingsTap;
  final bool isLoading;

  const _WeatherHeader({
    required this.colors,
    required this.onRefresh,
    required this.onSettingsTap,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final isPhone = Responsive.isPhone(context);

    final refreshButton = IconButton(
      key: WeatherTutorialKeys.refreshBtn,
      onPressed: isLoading ? null : onRefresh,
      icon: isLoading
          ? SizedBox(
              width: NightshadeTokens.iconMd,
              height: NightshadeTokens.iconMd,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(colors.primary),
              ),
            )
          : const Icon(NightshadeIcons.refresh, size: NightshadeTokens.iconMd),
      color: colors.textSecondary,
      tooltip: 'Refresh radar data',
    );

    final settingsButton = IconButton(
      onPressed: onSettingsTap,
      icon: const Icon(NightshadeIcons.settings, size: NightshadeTokens.iconMd),
      color: colors.textSecondary,
      tooltip: 'Weather settings',
    );

    // Canonical screen chrome: title, subtitle, and trailing actions route
    // through the shared [ScreenHeader] (typography + divider from the design
    // system) instead of a hand-rolled title row. The top safe-area inset is
    // preserved by wrapping the header — the outer Scaffold only handles the
    // bottom inset.
    return SafeArea(
      bottom: false,
      child: ScreenHeader(
        icon: NightshadeIcons.rain,
        title: 'Weather Radar',
        subtitle: 'Live cloud tracking and safety monitoring',
        padding: EdgeInsets.symmetric(
          horizontal:
              isPhone ? NightshadeTokens.spaceLg : NightshadeTokens.space2xl,
          vertical: NightshadeTokens.spaceMd,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            refreshButton,
            settingsButton,
          ],
        ),
      ),
    );
  }
}

/// Combined radar controls row with opacity and contrast sliders
class _RadarControlsRow extends StatelessWidget {
  final NightshadeColors colors;
  final double opacity;
  final double contrast;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<double> onContrastChanged;

  const _RadarControlsRow({
    required this.colors,
    required this.opacity,
    required this.contrast,
    required this.onOpacityChanged,
    required this.onContrastChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Static controls panel routed through the design-system [NightshadeCard]
    // (subtle variant = surface background + token border) rather than a
    // hand-rolled Container(BoxDecoration). The responsive inset is preserved
    // via the card padding.
    return NightshadeCard(
      variant: CardVariant.subtle,
      padding: EdgeInsets.all(
        Responsive.isPhone(context)
            ? NightshadeTokens.spaceMd
            : NightshadeTokens.spaceLg,
      ),
      child: Column(
        children: [
          // Opacity slider
          _SliderRow(
            colors: colors,
            icon: NightshadeIcons.layers,
            label: 'Opacity',
            value: opacity,
            min: 0.0,
            max: 1.0,
            displayValue: '${(opacity * 100).toInt()}%',
            onChanged: onOpacityChanged,
          ),
          const SizedBox(height: 12),
          // Contrast slider
          _SliderRow(
            colors: colors,
            icon: LucideIcons.contrast,
            label: 'Contrast',
            value: contrast,
            min: 0.0,
            max: 2.5,
            displayValue: _getContrastLabel(contrast),
            onChanged: onContrastChanged,
          ),
        ],
      ),
    );
  }

  String _getContrastLabel(double value) {
    if (value <= 0.2) return 'Off';
    if (value <= 0.8) return 'Low';
    if (value <= 1.3) return 'Medium';
    if (value <= 1.8) return 'High';
    return 'Max';
  }
}

/// Individual slider row widget
class _SliderRow extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final String displayValue;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.displayValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: colors.textSecondary,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: colors.primary,
              inactiveTrackColor: colors.surfaceAlt,
              thumbColor: colors.primary,
              overlayColor: colors.primary.withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            displayValue,
            style: NightshadeTypography.labelSm
                .copyWith(color: colors.textPrimary),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

/// Content shown when location is not configured
class _NoLocationContent extends StatelessWidget {
  final NightshadeColors colors;

  const _NoLocationContent({required this.colors});

  @override
  Widget build(BuildContext context) {
    // Phone tier tightens the card's rhythm. Measured at 360x640 the desktop
    // spacing made this card 695dp tall, so the "Open Location Settings" CTA
    // landed at y=599 and its 48dp button clipped to a 41dp tap target at the
    // bottom edge — the only action on the screen, half off it. Scrolling did
    // not save it: nothing signals that the card continues below the fold.
    final isPhone = Responsive.isPhone(context);
    final cardPad = isPhone ? 20.0 : 32.0;
    final iconPad = isPhone ? 12.0 : 16.0;
    final gapLg = isPhone ? 16.0 : 24.0;
    final gapSm = isPhone ? 8.0 : 12.0;
    return SingleChildScrollView(
      // Scrollable so the centered card never overflows when a phone is held
      // in landscape and the viewport is short.
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogMaxWidth(context, 400),
          ),
          child: NightshadeCard(
            variant: CardVariant.subtle,
            borderRadius: NightshadeTokens.radiusInline8,
            padding: EdgeInsets.all(cardPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(iconPad),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    NightshadeIcons.location,
                    size: 48,
                    color: colors.warning,
                  ),
                ),
                SizedBox(height: gapLg),
                Text(
                  'Location Not Configured',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize20,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                SizedBox(height: gapSm),
                Text(
                  'Weather radar requires your observation location to display relevant data. Please configure your location in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize14,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: gapLg),
                NightshadeButton(
                  label: 'Open Location Settings',
                  icon: NightshadeIcons.location,
                  variant: ButtonVariant.primary,
                  onPressed: () => context.go('/settings?section=location'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsUnavailableContent extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onRetry;

  const _SettingsUnavailableContent({
    required this.colors,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogMaxWidth(context, 400)),
          child: NightshadeCard(
            variant: CardVariant.subtle,
            borderRadius: NightshadeTokens.radiusInline8,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.alertTriangle,
                  size: 44,
                  color: colors.error,
                ),
                const SizedBox(height: 20),
                Text(
                  'Weather Settings Unavailable',
                  textAlign: TextAlign.center,
                  style: NightshadeTypography.h5.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Nightshade could not load the observing location or weather '
                  'configuration. Weather conditions are unknown.',
                  textAlign: TextAlign.center,
                  style: NightshadeTypography.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                NightshadeButton(
                  label: 'Retry',
                  icon: NightshadeIcons.refresh,
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
