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
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(colors.primary),
              ),
            )
          : const Icon(LucideIcons.refreshCw, size: 20),
      color: colors.textSecondary,
      tooltip: 'Refresh radar data',
    );

    final settingsButton = IconButton(
      onPressed: onSettingsTap,
      icon: const Icon(LucideIcons.settings, size: 20),
      color: colors.textSecondary,
      tooltip: 'Weather settings',
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isPhone ? 16 : 24, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: NightshadeDecorations.tintedBadge(
                colors.info,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                LucideIcons.cloudRain,
                size: 20,
                color: colors.info,
              ),
            ),
            const SizedBox(width: 12),
            // Title block flexes so it never pushes the action buttons off
            // the edge on a narrow phone.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Weather Radar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isPhone ? 18 : 20,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    'Live cloud tracking and safety monitoring',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          // Opacity slider
          _SliderRow(
            colors: colors,
            icon: LucideIcons.layers,
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
              fontSize: 12,
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
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
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
    return SingleChildScrollView(
      // Scrollable so the centered card never overflows when a phone is held
      // in landscape and the viewport is short.
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogMaxWidth(context, 400),
          ),
          child: Container(
            padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.mapPin,
                  size: 48,
                  color: colors.warning,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Location Not Configured',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Weather radar requires your observation location to display relevant data. Please configure your location in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              NightshadeButton(
                label: 'Open Weather Settings',
                icon: LucideIcons.cloudSun,
                variant: ButtonVariant.primary,
                onPressed: () => context.go('/settings?section=weather-safety'),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
