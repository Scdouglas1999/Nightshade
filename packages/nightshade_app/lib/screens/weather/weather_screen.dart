import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../widgets/weather/weather_radar_map.dart';
import '../../widgets/weather/radar_timeline_scrubber.dart';
import '../../widgets/weather/weather_status_card.dart';
import '../../widgets/weather/satellite_legend.dart';
import '../../widgets/tutorial_keys/weather_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';

/// Full weather monitoring screen with radar map, timeline, and status display.
///
/// Provides comprehensive weather monitoring capabilities including:
/// - Live radar imagery with animated playback
/// - Cloud motion tracking and ETA predictions
/// - Alert status and notifications
/// - Weather safety settings access
class WeatherScreen extends ConsumerStatefulWidget {
  const WeatherScreen({super.key});

  @override
  ConsumerState<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends ConsumerState<WeatherScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Animation state
  int _currentFrameIndex = 0;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  double _radarOpacity = 0.7;
  double _radarContrast = 1.5; // Default to moderate contrast enhancement
  bool _statusCardExpanded = true;

  // Refresh timer
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    // Start auto-refresh timer (every 5 minutes)
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _refreshWeatherData();
    });

    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshWeatherData();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refreshWeatherData() {
    // Invalidate the radar frames provider to trigger a fresh fetch
    ref.invalidate(weatherRadarFramesProvider);
    // Also refresh motion analysis and alert evaluation
    ref.invalidate(analyzeCloudMotionProvider);
    ref.invalidate(evaluateWeatherConditionsProvider);
    // Refresh cloud cover percentage
    ref.invalidate(cloudCoverPercentageProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final weatherStatus = ref.watch(weatherStatusProvider);
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    final motionAsync = ref.watch(analyzeCloudMotionProvider);
    final alertAsync = ref.watch(evaluateWeatherConditionsProvider);
    final cloudCoverAsync = ref.watch(cloudCoverPercentageProvider);

    // Get location from settings
    final latitude = appSettings?.latitude ?? 0.0;
    final longitude = appSettings?.longitude ?? 0.0;
    final hasLocation = !(latitude == 0.0 && longitude == 0.0);

    // Get weather settings for alert radius
    final weatherSettings = ref.watch(weatherSettingsProvider);
    final alertRadiusKm = weatherSettings.triggerDistanceKm;

    // Get radar frames
    final radarFrames = weatherStatus.radarFrames;

    // Get motion direction for indicator
    final motion = motionAsync.valueOrNull;
    final motionDirection = motion?.directionDegrees;

    // Get current alert
    final alert = alertAsync.valueOrNull;

    return ContextualTourPrompt(
      screenId: 'weather',
      tourCategory: TutorialCategory.weatherTour,
      title: 'Weather Tour',
      description:
          'Learn how to monitor weather conditions for your imaging sessions.',
      durationMinutes: 2,
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide =
                constraints.maxWidth > NightshadeTokens.breakpointDesktopLg;
            final isMedium =
                constraints.maxWidth > NightshadeTokens.breakpointTablet;

            return Scaffold(
              backgroundColor: colors.background,
              body: Column(
                children: [
                  // Header
                  _WeatherHeader(
                    colors: colors,
                    onRefresh: _refreshWeatherData,
                    onSettingsTap: () => context.go('/settings'),
                    isLoading: weatherStatus.isLoading,
                  ),

                  // Main content
                  Expanded(
                    child: hasLocation
                        ? _buildMainContent(
                            context,
                            colors,
                            isWide,
                            isMedium,
                            latitude,
                            longitude,
                            alertRadiusKm,
                            radarFrames,
                            motionDirection,
                            motion,
                            alert,
                            weatherStatus,
                            cloudCoverAsync.valueOrNull,
                          )
                        : _NoLocationContent(colors: colors),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMainContent(
    BuildContext context,
    NightshadeColors colors,
    bool isWide,
    bool isMedium,
    double latitude,
    double longitude,
    double alertRadiusKm,
    List<RadarFrame> radarFrames,
    double? motionDirection,
    CloudMotion? motion,
    WeatherAlert? alert,
    WeatherStatus weatherStatus,
    double? cloudCoverPercent,
  ) {
    // Clamp frame index to valid range
    final validFrameIndex = radarFrames.isEmpty
        ? 0
        : _currentFrameIndex.clamp(0, radarFrames.length - 1);

    final currentFrame =
        radarFrames.isEmpty ? null : radarFrames[validFrameIndex];

    if (isWide) {
      // Wide layout: radar and controls on left, data cards on right.
      // Both columns scroll independently. Radar is constrained to a
      // max height (500px) so it doesn't fill the entire window.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: Radar + controls (scrollable)
          Expanded(
            flex: 7,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Map with legend overlay - constrained height
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 500,
                      minHeight: 300,
                    ),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: WeatherRadarMap(
                              key: WeatherTutorialKeys.radarMap,
                              currentFrame: currentFrame,
                              latitude: latitude,
                              longitude: longitude,
                              alertRadiusKm: alertRadiusKm,
                              radarOpacity: _radarOpacity,
                              contrastLevel: _radarContrast,
                              motionDirection: motionDirection,
                            ),
                          ),
                          // Satellite legend overlay (bottom-left)
                          const Positioned(
                            left: 16,
                            bottom: 16,
                            child: SatelliteLegend(compact: true),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Timeline scrubber
                  RadarTimelineScrubber(
                    key: WeatherTutorialKeys.timeline,
                    frames: radarFrames,
                    currentIndex: validFrameIndex,
                    onFrameChanged: (index) {
                      setState(() => _currentFrameIndex = index);
                    },
                    isPlaying: _isPlaying,
                    onPlayPauseToggle: () {
                      setState(() => _isPlaying = !_isPlaying);
                    },
                    playbackSpeed: _playbackSpeed,
                    onSpeedChanged: (speed) {
                      setState(() => _playbackSpeed = speed);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Opacity and contrast sliders
                  _RadarControlsRow(
                    colors: colors,
                    opacity: _radarOpacity,
                    contrast: _radarContrast,
                    onOpacityChanged: (value) {
                      setState(() => _radarOpacity = value);
                    },
                    onContrastChanged: (value) {
                      setState(() => _radarContrast = value);
                    },
                  ),
                ],
              ),
            ),
          ),

          // Divider
          Container(
            width: 1,
            color: colors.border,
          ),

          // Right column: Data cards (scrollable)
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Hardware sensors at top (priority)
                  _HardwareSensorsCard(colors: colors),
                  const SizedBox(height: 16),
                  // Cloud cover indicator
                  _CloudCoverCard(
                    cloudCoverPercent: cloudCoverPercent,
                    colors: colors,
                  ),
                  const SizedBox(height: 16),
                  WeatherStatusCard(
                    key: WeatherTutorialKeys.statusCard,
                    alert: alert,
                    motion: motion,
                    lastUpdate: weatherStatus.lastUpdate,
                    expanded: _statusCardExpanded,
                    onExpandToggle: () {
                      setState(
                          () => _statusCardExpanded = !_statusCardExpanded);
                    },
                  ),
                  const SizedBox(height: 16),
                  _WeatherSafetyCard(colors: colors),
                  const SizedBox(height: 16),
                  _WeatherSettingsCard(colors: colors),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      // Narrow/medium layout: stacked vertically, all in one scroll view.
      // Radar is constrained to a fixed height so data cards are visible below.
      final radarHeight = isMedium ? 350.0 : 280.0;

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Map with legend overlay - constrained to fixed height
            SizedBox(
              height: radarHeight,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: WeatherRadarMap(
                      key: WeatherTutorialKeys.radarMap,
                      currentFrame: currentFrame,
                      latitude: latitude,
                      longitude: longitude,
                      alertRadiusKm: alertRadiusKm,
                      radarOpacity: _radarOpacity,
                      contrastLevel: _radarContrast,
                      motionDirection: motionDirection,
                    ),
                  ),
                  // Satellite legend overlay
                  const Positioned(
                    left: 8,
                    bottom: 8,
                    child: SatelliteLegend(compact: true),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Timeline scrubber
            RadarTimelineScrubber(
              key: WeatherTutorialKeys.timeline,
              frames: radarFrames,
              currentIndex: validFrameIndex,
              onFrameChanged: (index) {
                setState(() => _currentFrameIndex = index);
              },
              isPlaying: _isPlaying,
              onPlayPauseToggle: () {
                setState(() => _isPlaying = !_isPlaying);
              },
              playbackSpeed: _playbackSpeed,
              onSpeedChanged: (speed) {
                setState(() => _playbackSpeed = speed);
              },
            ),

            const SizedBox(height: 16),

            // Opacity and contrast sliders
            _RadarControlsRow(
              colors: colors,
              opacity: _radarOpacity,
              contrast: _radarContrast,
              onOpacityChanged: (value) {
                setState(() => _radarOpacity = value);
              },
              onContrastChanged: (value) {
                setState(() => _radarContrast = value);
              },
            ),

            const SizedBox(height: 24),

            // Hardware sensors (priority - only shows if devices connected)
            _HardwareSensorsCard(colors: colors),
            const SizedBox(height: 16),

            // Cloud cover card
            _CloudCoverCard(
              cloudCoverPercent: cloudCoverPercent,
              colors: colors,
            ),

            const SizedBox(height: 16),

            // Status card
            WeatherStatusCard(
              key: WeatherTutorialKeys.statusCard,
              alert: alert,
              motion: motion,
              lastUpdate: weatherStatus.lastUpdate,
              expanded: _statusCardExpanded,
              onExpandToggle: () {
                setState(() => _statusCardExpanded = !_statusCardExpanded);
              },
            ),

            const SizedBox(height: 16),

            // Safety and settings cards in row on medium screens
            if (isMedium)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _WeatherSafetyCard(colors: colors)),
                  const SizedBox(width: 16),
                  Expanded(child: _WeatherSettingsCard(colors: colors)),
                ],
              )
            else ...[
              _WeatherSafetyCard(colors: colors),
              const SizedBox(height: 16),
              _WeatherSettingsCard(colors: colors),
            ],

            const SizedBox(height: 24),
          ],
        ),
      );
    }
  }
}

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.info.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              LucideIcons.cloudRain,
              size: 20,
              color: colors.info,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Weather Radar',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                'Live cloud tracking and safety monitoring',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Refresh button
          IconButton(
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
          ),
          const SizedBox(width: 8),
          // Settings button
          IconButton(
            onPressed: onSettingsTap,
            icon: const Icon(LucideIcons.settings, size: 20),
            color: colors.textSecondary,
            tooltip: 'Weather settings',
          ),
        ],
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
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
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
                color: colors.warning.withValues(alpha: 0.1),
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
              label: 'Open Settings',
              icon: LucideIcons.settings,
              variant: ButtonVariant.primary,
              onPressed: () => context.go('/settings'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weather safety status card with snooze controls
class _WeatherSafetyCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _WeatherSafetyCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safetyState = ref.watch(weatherSafetyProvider);
    final isSafe = safetyState.isSafe;
    final status = safetyState.status;
    final snoozeUntil = safetyState.snoozeUntil;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSafe
                      ? colors.success.withValues(alpha: 0.1)
                      : colors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isSafe ? LucideIcons.shieldCheck : LucideIcons.shieldAlert,
                  size: 16,
                  color: isSafe ? colors.success : colors.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Safety Status',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      _getStatusText(status, snoozeUntil),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (status == WeatherSafetyStatus.unsafe ||
              status == WeatherSafetyStatus.snoozed) ...[
            const SizedBox(height: 16),
            if (status == WeatherSafetyStatus.snoozed)
              NightshadeButton(
                label: 'Cancel Snooze',
                icon: LucideIcons.bellOff,
                variant: ButtonVariant.outline,
                onPressed: () {
                  ref.read(weatherSafetyProvider.notifier).cancelSnooze();
                },
              )
            else
              Row(
                children: [
                  Expanded(
                    child: NightshadeButton(
                      label: 'Snooze 15m',
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: () {
                        ref
                            .read(weatherSafetyProvider.notifier)
                            .snooze(const Duration(minutes: 15));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NightshadeButton(
                      label: 'Snooze 30m',
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: () {
                        ref
                            .read(weatherSafetyProvider.notifier)
                            .snooze(const Duration(minutes: 30));
                      },
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  String _getStatusText(WeatherSafetyStatus status, DateTime? snoozeUntil) {
    switch (status) {
      case WeatherSafetyStatus.safe:
        return 'Conditions safe for imaging';
      case WeatherSafetyStatus.unsafe:
        return 'Unsafe conditions detected';
      case WeatherSafetyStatus.snoozed:
        if (snoozeUntil != null) {
          final remaining = snoozeUntil.difference(DateTime.now());
          final minutes = remaining.inMinutes;
          return 'Snoozed for $minutes more minutes';
        }
        return 'Alerts snoozed';
    }
  }
}

/// Weather settings quick access card
class _WeatherSettingsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _WeatherSettingsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(weatherSettingsProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.sliders,
                  size: 16,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Current Settings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingRow(
            key: WeatherTutorialKeys.alertRadius,
            label: 'Alert Radius',
            value: '${settings.triggerDistanceKm.toInt()} km',
            colors: colors,
          ),
          _SettingRow(
            label: 'Density Threshold',
            value: '${settings.cloudDensityThreshold.toInt()}%',
            colors: colors,
          ),
          _SettingRow(
            label: 'Lead Time',
            value: '${settings.leadTimeMinutes} min',
            colors: colors,
          ),
          _SettingRow(
            label: 'Auto-Park',
            value: settings.autoParkEnabled ? 'Enabled' : 'Disabled',
            colors: colors,
            valueColor:
                settings.autoParkEnabled ? colors.success : colors.textMuted,
          ),
          _SettingRow(
            label: 'Auto-Resume',
            value: settings.autoResumeEnabled ? 'Enabled' : 'Disabled',
            colors: colors,
            valueColor:
                settings.autoResumeEnabled ? colors.success : colors.textMuted,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

/// Single setting row display
class _SettingRow extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? valueColor;
  final bool isLast;

  const _SettingRow({
    super.key,
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colors.border.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: valueColor ?? colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Cloud cover percentage display card
class _CloudCoverCard extends StatelessWidget {
  final double? cloudCoverPercent;
  final NightshadeColors colors;

  const _CloudCoverCard({
    required this.cloudCoverPercent,
    required this.colors,
  });

  Color _getCloudCoverColor(double percent) {
    if (percent <= 20) return colors.success;
    if (percent <= 40) return const Color(0xFF22C55E); // Green
    if (percent <= 60) return colors.warning;
    if (percent <= 80) return const Color(0xFFFB923C); // Orange
    return colors.error;
  }

  String _getCloudCoverLabel(double percent) {
    if (percent <= 10) return 'Clear';
    if (percent <= 25) return 'Mostly Clear';
    if (percent <= 50) return 'Partly Cloudy';
    if (percent <= 75) return 'Mostly Cloudy';
    if (percent <= 90) return 'Cloudy';
    return 'Overcast';
  }

  IconData _getCloudCoverIcon(double percent) {
    if (percent <= 20) return LucideIcons.sun;
    if (percent <= 50) return LucideIcons.cloudSun;
    if (percent <= 80) return LucideIcons.cloud;
    return LucideIcons.cloudFog;
  }

  @override
  Widget build(BuildContext context) {
    final percent = cloudCoverPercent ?? 0.0;
    final coverColor = _getCloudCoverColor(percent);
    final label = _getCloudCoverLabel(percent);
    final icon = _getCloudCoverIcon(percent);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: coverColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 24,
              color: coverColor,
            ),
          ),
          const SizedBox(width: 16),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cloud Cover',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      cloudCoverPercent != null ? '${percent.toInt()}%' : '--',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: coverColor,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Progress indicator
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: percent / 100,
                  strokeWidth: 6,
                  backgroundColor: colors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(coverColor),
                ),
                Text(
                  cloudCoverPercent != null ? '${percent.toInt()}' : '--',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hardware weather and safety device sensors card
/// Displays readings from connected hardware devices prominently
class _HardwareSensorsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _HardwareSensorsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherState = ref.watch(weatherStateProvider);
    final safetyState = ref.watch(safetyMonitorStateProvider);

    final hasWeatherDevice =
        weatherState.connectionState == DeviceConnectionState.connected;
    final hasSafetyDevice =
        safetyState.connectionState == DeviceConnectionState.connected;

    // Don't show if no hardware devices connected
    if (!hasWeatherDevice && !hasSafetyDevice) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.surface,
            colors.primary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.cpu,
                  size: 16,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hardware Sensors',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Live readings from connected devices',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Safety monitor status (priority)
          if (hasSafetyDevice) ...[
            _SensorRow(
              colors: colors,
              icon: safetyState.isSafe
                  ? LucideIcons.shieldCheck
                  : LucideIcons.shieldAlert,
              label: 'Safety Monitor',
              value: safetyState.isSafe ? 'SAFE' : 'UNSAFE',
              valueColor: safetyState.isSafe ? colors.success : colors.error,
              deviceName: safetyState.deviceName,
            ),
            if (hasWeatherDevice) const SizedBox(height: 12),
          ],

          // Weather device readings
          if (hasWeatherDevice) ...[
            if (weatherState.temperature != null)
              _SensorRow(
                colors: colors,
                icon: LucideIcons.thermometer,
                label: 'Temperature',
                value: '${weatherState.temperature!.toStringAsFixed(1)}°C',
              ),
            if (weatherState.humidity != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.droplets,
                label: 'Humidity',
                value: '${weatherState.humidity!.toStringAsFixed(0)}%',
                valueColor: weatherState.humidity! > 80 ? colors.warning : null,
              ),
            ],
            if (weatherState.dewPoint != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.droplet,
                label: 'Dew Point',
                value: '${weatherState.dewPoint!.toStringAsFixed(1)}°C',
              ),
            ],
            if (weatherState.windSpeed != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.wind,
                label: 'Wind Speed',
                value: '${weatherState.windSpeed!.toStringAsFixed(1)} m/s',
                valueColor:
                    weatherState.windSpeed! > 15 ? colors.warning : null,
              ),
            ],
            if (weatherState.cloudCover != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.cloud,
                label: 'Cloud Cover',
                value: '${weatherState.cloudCover!.toStringAsFixed(0)}%',
                valueColor:
                    weatherState.cloudCover! > 60 ? colors.warning : null,
              ),
            ],
            if (weatherState.skyQuality != null) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.sparkles,
                label: 'Sky Quality',
                value:
                    '${weatherState.skyQuality!.toStringAsFixed(2)} mag/arcsec²',
              ),
            ],
            if (weatherState.rainRate != null &&
                weatherState.rainRate! > 0) ...[
              const SizedBox(height: 8),
              _SensorRow(
                colors: colors,
                icon: LucideIcons.cloudRain,
                label: 'Rain',
                value: '${weatherState.rainRate!.toStringAsFixed(1)} mm/hr',
                valueColor: colors.error,
              ),
            ],
          ],

          // Last updated
          if (weatherState.lastUpdated != null) ...[
            const SizedBox(height: 12),
            Text(
              'Last updated: ${_formatTime(weatherState.lastUpdated!)}',
              style: TextStyle(
                fontSize: 10,
                color: colors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

/// Single sensor reading row
class _SensorRow extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final String? deviceName;

  const _SensorRow({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.deviceName,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
              if (deviceName != null)
                Text(
                  deviceName!,
                  style: TextStyle(
                    fontSize: 9,
                    color: colors.textSecondary.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
