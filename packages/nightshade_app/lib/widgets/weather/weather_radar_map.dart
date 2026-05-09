import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'location_marker.dart';
import 'motion_indicator.dart';

/// Weather radar map widget with base map and radar overlay.
///
/// Displays an interactive map with OpenStreetMap base tiles, radar overlay,
/// user location marker, alert radius circle, and optional cloud motion indicator.
/// Supports both compact (dashboard) and full-screen modes.
class WeatherRadarMap extends ConsumerStatefulWidget {
  /// Current radar frame to display
  final RadarFrame? currentFrame;

  /// User's latitude
  final double latitude;

  /// User's longitude
  final double longitude;

  /// Compact mode for dashboard widget
  final bool compact;

  /// Alert radius circle (km)
  final double alertRadiusKm;

  /// Radar tile opacity (0.0 - 1.0)
  final double radarOpacity;

  /// Contrast enhancement level (0.0 = none, 1.0 = moderate, 2.0 = high)
  /// Applied to radar/satellite tiles to improve visibility of cloud boundaries.
  final double contrastLevel;

  /// Cloud motion direction (degrees, 0=N, for indicator arrow)
  final double? motionDirection;

  /// Callback when map tapped (for navigation in compact mode)
  final VoidCallback? onTap;

  const WeatherRadarMap({
    super.key,
    this.currentFrame,
    required this.latitude,
    required this.longitude,
    this.compact = false,
    this.alertRadiusKm = 30.0,
    this.radarOpacity = 0.7,
    this.contrastLevel = 1.5,
    this.motionDirection,
    this.onTap,
  });

  @override
  ConsumerState<WeatherRadarMap> createState() => _WeatherRadarMapState();
}

class _WeatherRadarMapState extends ConsumerState<WeatherRadarMap> {
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Calculate initial zoom level to fit alert radius
  double _calculateInitialZoom() {
    // Approximate zoom level based on alert radius
    // Larger radius = zoom out more
    if (widget.alertRadiusKm <= 10) return 11.0;
    if (widget.alertRadiusKm <= 30) return 9.0;
    if (widget.alertRadiusKm <= 50) return 8.0;
    if (widget.alertRadiusKm <= 100) return 7.0;
    return 6.0;
  }

  /// Creates a color matrix for contrast enhancement.
  ///
  /// The contrast parameter controls the intensity:
  /// - 0.0 = no enhancement (identity matrix)
  /// - 1.0 = moderate enhancement (good for most conditions)
  /// - 2.0 = high enhancement (useful for subtle cloud features)
  ///
  /// This uses a standard contrast matrix formula that also slightly increases
  /// brightness in dark areas while compressing bright areas, making the
  /// distinction between clear sky and clouds more obvious.
  ColorFilter _buildContrastFilter(double contrast) {
    // Base contrast multiplier (1.0 = no change, higher = more contrast)
    // Using a sigmoid-like curve for natural-looking enhancement
    final contrastMultiplier = 1.0 + (contrast * 0.5);

    // Offset to adjust midpoint (negative pulls dark colors darker,
    // positive pulls bright colors brighter)
    final offset = -0.5 * (contrastMultiplier - 1.0) * 255;

    // Slight gamma-style boost to make clouds "pop" more
    // by adding extra brightness to already-bright pixels
    final brightBoost = contrast * 0.08;

    return ColorFilter.matrix(<double>[
      // Red channel: enhanced contrast + slight warm shift for clouds
      contrastMultiplier + brightBoost, 0, 0, 0, offset,
      // Green channel: enhanced contrast
      0, contrastMultiplier + brightBoost, 0, 0, offset,
      // Blue channel: enhanced contrast + cooler for clear sky depth
      0, 0, contrastMultiplier + brightBoost * 0.5, 0, offset,
      // Alpha channel: unchanged
      0, 0, 0, 1, 0,
    ]);
  }

  /// Wraps a tile widget with contrast enhancement and opacity.
  Widget _buildEnhancedTile(Widget tileWidget, double opacity, double contrast) {
    Widget result = tileWidget;

    // Apply contrast enhancement if enabled
    if (contrast > 0) {
      result = ColorFiltered(
        colorFilter: _buildContrastFilter(contrast),
        child: result,
      );
    }

    // Apply opacity
    if (opacity < 1.0) {
      result = Opacity(
        opacity: opacity,
        child: result,
      );
    }

    return result;
  }

  /// Builds the appropriate tile layer based on the frame's tile type
  Widget _buildRadarTileLayer(RadarFrame frame, double opacity, double contrast) {
    // Create tile bounds from frame coverage to prevent NaN errors
    // when requesting tiles outside the provider's coverage area
    final tileBounds = LatLngBounds(
      LatLng(frame.south, frame.west),
      LatLng(frame.north, frame.east),
    );

    if (frame.tileType == RadarTileType.wms) {
      // WMS tile layer for NOAA/GOES satellite and similar services
      return TileLayer(
        wmsOptions: WMSTileLayerOptions(
          baseUrl: frame.tileUrlTemplate,
          layers: frame.wmsLayers != null ? [frame.wmsLayers!] : [],
          format: 'image/png',
          transparent: true,
          version: '1.1.1',
          crs: const Epsg3857(), // Web Mercator
          otherParameters: frame.wmsAdditionalOptions ?? {},
        ),
        tileBounds: tileBounds,
        evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        tileBuilder: (context, tileWidget, tile) {
          return _buildEnhancedTile(tileWidget, opacity, contrast);
        },
      );
    } else {
      // Standard XYZ tile layer for RainViewer and similar services
      return TileLayer(
        urlTemplate: frame.tileUrlTemplate,
        tileBounds: tileBounds,
        evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
        tileBuilder: (context, tileWidget, tile) {
          return _buildEnhancedTile(tileWidget, opacity, contrast);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>() ??
        NightshadeColors.dark;

    final userLocation = LatLng(widget.latitude, widget.longitude);

    // Build the map widget
    final mapWidget = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: userLocation,
        initialZoom: _calculateInitialZoom(),
        minZoom: 4.0,
        maxZoom: 15.0,
        interactionOptions: InteractionOptions(
          flags: widget.compact
              ? InteractiveFlag.none // Disable interaction in compact mode
              // Enable all interactions EXCEPT scroll wheel zoom, which would
              // capture scroll events from the parent ScrollView and prevent
              // the page from scrolling when the cursor is over the map.
              // Users can still zoom via pinch, double-tap, or the +/- buttons.
              : InteractiveFlag.all & ~InteractiveFlag.scrollWheelZoom,
        ),
        onTap: widget.onTap != null
            ? (_, __) => widget.onTap?.call()
            : null,
      ),
      children: [
        // Base map layer (dark theme)
        TileLayer(
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.nightshade.app',
          retinaMode: RetinaMode.isHighDensity(context),
          tileBuilder: (context, tileWidget, tile) {
            // Apply opacity to base map for better radar visibility
            return Opacity(
              opacity: 0.6,
              child: tileWidget,
            );
          },
        ),

        // Radar overlay layer - handles both XYZ and WMS tile types
        if (widget.currentFrame != null) ...[
          _buildRadarTileLayer(
            widget.currentFrame!,
            widget.radarOpacity,
            widget.contrastLevel,
          ),
        ],

        // Alert radius circle
        CircleLayer(
          circles: [
            CircleMarker(
              point: userLocation,
              radius: widget.alertRadiusKm * 1000, // Convert km to meters
              useRadiusInMeter: true,
              color: colors.warning.withValues(alpha: 0.08),
              borderColor: colors.warning.withValues(alpha: 0.4),
              borderStrokeWidth: 2.0,
            ),
          ],
        ),

        // User location marker
        MarkerLayer(
          markers: [
            Marker(
              point: userLocation,
              width: 40,
              height: 40,
              alignment: Alignment.center,
              child: LocationMarker(colors: colors),
            ),
          ],
        ),

        // Cloud motion indicator (if provided)
        if (widget.motionDirection != null)
          MarkerLayer(
            markers: [
              Marker(
                point: userLocation,
                width: 60,
                height: 60,
                alignment: Alignment.center,
                child: MotionIndicator(
                  directionDegrees: widget.motionDirection!,
                  colors: colors,
                ),
              ),
            ],
          ),
      ],
    );

    // Wrap with controls if not compact
    if (widget.compact) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: mapWidget,
      );
    }

    return Stack(
      children: [
        mapWidget,

        // Zoom controls
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomButton(
                icon: LucideIcons.plus,
                onPressed: () {
                  final currentZoom = _mapController.camera.zoom;
                  _mapController.move(
                    _mapController.camera.center,
                    math.min(currentZoom + 1, 15.0),
                  );
                },
                colors: colors,
              ),
              const SizedBox(height: 8),
              _ZoomButton(
                icon: LucideIcons.minus,
                onPressed: () {
                  final currentZoom = _mapController.camera.zoom;
                  _mapController.move(
                    _mapController.camera.center,
                    math.max(currentZoom - 1, 4.0),
                  );
                },
                colors: colors,
              ),
              const SizedBox(height: 8),
              _ZoomButton(
                icon: LucideIcons.locateFixed,
                onPressed: () {
                  _mapController.move(
                    userLocation,
                    _calculateInitialZoom(),
                  );
                },
                colors: colors,
              ),
            ],
          ),
        ),

        // Radar info overlay (top-left)
        if (widget.currentFrame != null)
          Positioned(
            left: 16,
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colors.border,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.currentFrame!.isForecast
                        ? LucideIcons.cloudRainWind
                        : LucideIcons.satellite,
                    size: 16,
                    color: widget.currentFrame!.isForecast
                        ? colors.info
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.currentFrame!.isForecast ? 'Forecast' : 'Live',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Zoom control button
class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final NightshadeColors colors;

  const _ZoomButton({
    required this.icon,
    required this.onPressed,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            border: Border.all(
              color: colors.border,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
