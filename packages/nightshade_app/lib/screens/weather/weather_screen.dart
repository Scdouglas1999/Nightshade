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

part 'weather_screen/header_and_radar_controls.dart';
part 'weather_screen/safety_and_settings.dart';
part 'weather_screen/cloud_and_hardware.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Animation state
  int _currentFrameIndex = 0;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  double _radarOpacity = 0.7;
  double _radarContrast = 1.5; // Default to moderate contrast enhancement
  bool _statusCardExpanded = true;

  // Refresh timer. Suspended when the app is backgrounded so a hidden window
  // doesn't keep hammering the radar API every five minutes (§4.33).
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _startRefreshTimer();

    // Initial fetch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshWeatherData();
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _refreshWeatherData();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_refreshTimer == null || !_refreshTimer!.isActive) {
        _startRefreshTimer();
        // Catch up immediately after resume so radar isn't stale.
        _refreshWeatherData();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    final colors = NightshadeColors.of(context);
    final weatherStatus = ref.watch(weatherStatusProvider);
    final appSettings = ref.watch(appSettingsProvider).valueOrNull;
    final motionAsync = ref.watch(analyzeCloudMotionProvider);
    final alertAsync = ref.watch(evaluateWeatherConditionsProvider);
    final cloudCoverAsync = ref.watch(cloudCoverPercentageProvider);
    final radarSource = ref.watch(radarSourceInfoProvider);

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
            // Phone landscape: enough width to put the map beside the data
            // column without forcing it. Drive purely off the region's own
            // constraints so embedded/rotated cases are correct.
            final isPhoneLandscape = constraints.maxWidth < 600 &&
                constraints.maxWidth > constraints.maxHeight &&
                constraints.maxWidth >= 560;

            return Scaffold(
              backgroundColor: colors.background,
              body: SafeArea(
                top: false,
                child: Column(
                  children: [
                    // Header
                    _WeatherHeader(
                      colors: colors,
                      onRefresh: _refreshWeatherData,
                      onSettingsTap: () =>
                          context.go('/settings?section=weather-safety'),
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
                              isPhoneLandscape,
                              latitude,
                              longitude,
                              alertRadiusKm,
                              radarFrames,
                              motionDirection,
                              motion,
                              alert,
                              weatherStatus,
                              cloudCoverAsync.valueOrNull,
                              radarSource,
                            )
                          : _NoLocationContent(colors: colors),
                    ),
                  ],
                ),
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
    bool isPhoneLandscape,
    double latitude,
    double longitude,
    double alertRadiusKm,
    List<RadarFrame> radarFrames,
    double? motionDirection,
    CloudMotion? motion,
    WeatherAlert? alert,
    WeatherStatus weatherStatus,
    double? cloudCoverPercent,
    RadarSourceInfo radarSource,
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
                              sourceName: radarSource.providerName,
                              fetchedAt: radarSource.fetchedAt,
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
      // Narrow/medium layout. Radar is constrained to a fixed height so data
      // cards are visible below; in phone landscape the map + controls sit
      // beside the scrolling data column instead of stacking.
      final radarHeight = isPhoneLandscape
          ? 0.0 // landscape: map fills the left pane height, no fixed box
          : isMedium
              ? 350.0
              : 280.0;

      final radarStack = Stack(
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
              sourceName: radarSource.providerName,
              fetchedAt: radarSource.fetchedAt,
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 8,
            child: SatelliteLegend(compact: true),
          ),
        ],
      );

      final scrubber = RadarTimelineScrubber(
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
      );

      final controlsRow = _RadarControlsRow(
        colors: colors,
        opacity: _radarOpacity,
        contrast: _radarContrast,
        onOpacityChanged: (value) {
          setState(() => _radarOpacity = value);
        },
        onContrastChanged: (value) {
          setState(() => _radarContrast = value);
        },
      );

      final dataCards = <Widget>[
        // Hardware sensors (priority - only shows if devices connected)
        _HardwareSensorsCard(colors: colors),
        const SizedBox(height: 16),
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
            setState(() => _statusCardExpanded = !_statusCardExpanded);
          },
        ),
        const SizedBox(height: 16),
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
      ];

      if (isPhoneLandscape) {
        // Map + radar controls on the left, scrolling data cards on the right.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                child: Column(
                  children: [
                    Expanded(child: radarStack),
                    const SizedBox(height: 12),
                    scrubber,
                    const SizedBox(height: 12),
                    controlsRow,
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                child: Column(children: dataCards),
              ),
            ),
          ],
        );
      }

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(height: radarHeight, child: radarStack),
            const SizedBox(height: 16),
            scrubber,
            const SizedBox(height: 16),
            controlsRow,
            const SizedBox(height: 24),
            ...dataCards,
            const SizedBox(height: 24),
          ],
        ),
      );
    }
  }
}
