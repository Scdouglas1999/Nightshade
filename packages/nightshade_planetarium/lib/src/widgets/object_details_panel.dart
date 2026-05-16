import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../celestial_object.dart';
import '../astronomy/astronomy_calculations.dart';
import '../services/survey_image_service.dart';
import '../providers/planetarium_providers.dart';

/// Enhanced object details panel showing comprehensive information
class ObjectDetailsPanel extends ConsumerWidget {
  /// The celestial object to display
  final CelestialObject object;

  /// Background color
  final Color? backgroundColor;

  /// Text color
  final Color? textColor;

  /// Accent color
  final Color? accentColor;

  /// Whether to show the visibility graph
  final bool showVisibilityGraph;

  /// Callback when "Go To" is pressed
  final VoidCallback? onGoTo;

  /// Callback when "Add to Targets" is pressed
  final VoidCallback? onAddToTargets;

  /// Optional extra widget inserted before the action buttons (e.g. imaging history).
  final Widget? extraContent;

  /// Current cloud cover percentage (0-100). When provided, the altitude chart
  /// shows a background band: green (<20%), yellow (20-60%), red (>60%).
  final double? cloudCoverPercent;

  const ObjectDetailsPanel({
    super.key,
    required this.object,
    this.backgroundColor,
    this.textColor,
    this.accentColor,
    this.showVisibilityGraph = true,
    this.onGoTo,
    this.onAddToTargets,
    this.extraContent,
    this.cloudCoverPercent,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bgColor = backgroundColor ?? const Color(0xFF1A1A2E);
    final txtColor = textColor ?? Colors.white;
    final accent = accentColor ?? const Color(0xFF00E676);

    final location = ref.watch(observerLocationProvider);
    final obsTime = ref.watch(observationTimeProvider);

    // Calculate current altitude/azimuth
    final (alt, az) = AstronomyCalculations.objectAltAz(
      raDeg: object.coordinates.ra * 15, // Convert hours to degrees
      decDeg: object.coordinates.dec,
      dt: obsTime.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    // Calculate visibility score
    final visibilityScore = _calculateVisibilityScore(ref, alt);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: txtColor.withValues(alpha: 0.1)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with name, type, and optional thumbnail for DSOs
            if (object is DeepSkyObject)
              _buildHeaderWithThumbnail(
                  txtColor, accent, object as DeepSkyObject)
            else
              _buildHeader(txtColor, accent),
            const SizedBox(height: 12),

            // Visibility score indicator (new)
            Center(child: _buildVisibilityIndicator(visibilityScore)),
            const SizedBox(height: 12),

            // Quick stats bar (new)
            _buildQuickStats(ref, alt, txtColor),
            const SizedBox(height: 16),

            // Coordinates section
            _buildCoordinatesSection(txtColor),
            const SizedBox(height: 16),

            // Catalog IDs section
            _buildCatalogSection(txtColor, accent),
            const SizedBox(height: 16),

            // Physical properties section
            _buildPhysicalPropertiesSection(txtColor),
            const SizedBox(height: 16),

            // Current visibility section
            _buildVisibilitySection(alt, az, txtColor, accent),

            if (showVisibilityGraph) ...[
              const SizedBox(height: 16),
              // Visibility graph (altitude over time)
              _buildVisibilityGraph(ref, txtColor, accent),
              const SizedBox(height: 16),
              // Airmass chart
              _buildAirmassChart(ref, txtColor, accent),
            ],

            const SizedBox(height: 16),

            // Rise/Transit/Set times
            _buildRiseTransitSetSection(ref, txtColor),

            // Extra content slot (e.g. imaging history)
            if (extraContent != null) ...[
              const SizedBox(height: 16),
              extraContent!,
            ],

            const SizedBox(height: 16),

            // Action buttons
            _buildActionButtons(accent),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color txtColor, Color accent) {
    final iconData = _getObjectIcon();
    final typeColor = _getTypeColor();

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(iconData, color: typeColor, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                object.name,
                style: TextStyle(
                  color: txtColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getTypeString(),
                style: TextStyle(
                  color: typeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (object.magnitude != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: txtColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Mag ${object.magnitude!.toStringAsFixed(1)}',
              style: TextStyle(
                color: txtColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  /// Build header with thumbnail for DSOs
  Widget _buildHeaderWithThumbnail(
      Color txtColor, Color accent, DeepSkyObject dso) {
    final typeColor = _getTypeColor();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thumbnail
        _buildThumbnail(dso),
        const SizedBox(width: 12),
        // Name and details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                object.name,
                style: TextStyle(
                  color: txtColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _getTypeString(),
                style: TextStyle(
                  color: typeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              // Magnitude and size in a row
              Row(
                children: [
                  if (object.magnitude != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: txtColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Mag ${object.magnitude!.toStringAsFixed(1)}',
                        style: TextStyle(
                          color: txtColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  if (object.magnitude != null && dso.sizeString != null)
                    const SizedBox(width: 6),
                  if (dso.sizeString != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: txtColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        dso.sizeString!,
                        style: TextStyle(
                          color: txtColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoordinatesSection(Color txtColor) {
    final raHours = object.coordinates.ra.floor();
    final raMinutes = ((object.coordinates.ra - raHours) * 60).floor();
    final raSeconds =
        ((object.coordinates.ra - raHours - raMinutes / 60) * 3600)
            .toStringAsFixed(1);

    final decSign = object.coordinates.dec >= 0 ? '+' : '';
    final decDegrees = object.coordinates.dec.abs().floor();
    final decMinutes =
        ((object.coordinates.dec.abs() - decDegrees) * 60).floor();
    final decSeconds =
        ((object.coordinates.dec.abs() - decDegrees - decMinutes / 60) * 3600)
            .toStringAsFixed(0);

    final constellation = _getConstellation();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Coordinates',
          style: TextStyle(
            color: txtColor.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          'RA',
          '${raHours}h ${raMinutes}m ${raSeconds}s',
          txtColor,
        ),
        _buildInfoRow(
          'Dec',
          '$decSign$decDegrees° ${decMinutes}\' ${decSeconds}"',
          txtColor,
        ),
        if (constellation != null)
          _buildInfoRow('Constellation', constellation, txtColor),
      ],
    );
  }

  Widget _buildCatalogSection(Color txtColor, Color accent) {
    final catalogIds = _getCatalogIds();
    if (catalogIds.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Catalog Designations',
          style: TextStyle(
            color: txtColor.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: catalogIds.map((id) {
            final isMessier = id.startsWith('M');
            final isNgc = id.startsWith('NGC');
            final isIc = id.startsWith('IC');

            Color tagColor;
            if (isMessier) {
              tagColor = Colors.amber;
            } else if (isNgc) {
              tagColor = Colors.blue;
            } else if (isIc) {
              tagColor = Colors.purple;
            } else {
              tagColor = txtColor;
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: tagColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: tagColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                id,
                style: TextStyle(
                  color: tagColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPhysicalPropertiesSection(Color txtColor) {
    final properties = <Widget>[];

    if (object is DeepSkyObject) {
      final dso = object as DeepSkyObject;
      if (dso.sizeArcMin != null) {
        final sizeStr = dso.minorAxisArcMin != null
            ? '${dso.sizeArcMin!.toStringAsFixed(1)}\' × ${dso.minorAxisArcMin!.toStringAsFixed(1)}\''
            : '${dso.sizeArcMin!.toStringAsFixed(1)}\'';
        properties.add(_buildInfoRow('Size', sizeStr, txtColor));
      }
      if (dso.positionAngle != null) {
        properties.add(_buildInfoRow(
            'PA', '${dso.positionAngle!.toStringAsFixed(0)}°', txtColor));
      }
    }

    if (object is Star) {
      final star = object as Star;
      if (star.spectralType != null) {
        properties.add(_buildInfoRow('Spectral', star.spectralType!, txtColor));
      }
    }

    if (properties.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Physical Properties',
          style: TextStyle(
            color: txtColor.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...properties,
      ],
    );
  }

  Widget _buildVisibilitySection(
    double altitude,
    double azimuth,
    Color txtColor,
    Color accent,
  ) {
    final isVisible = altitude > 0;
    final statusColor = isVisible ? Colors.green : Colors.red;
    final statusText = isVisible ? 'Above Horizon' : 'Below Horizon';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Current Visibility',
              style: TextStyle(
                color: txtColor.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildInfoRow('Altitude', '${altitude.toStringAsFixed(1)}°', txtColor),
        _buildInfoRow('Azimuth', '${azimuth.toStringAsFixed(1)}°', txtColor),
      ],
    );
  }

  Widget _buildVisibilityGraph(WidgetRef ref, Color txtColor, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Altitude Over 24 Hours',
          style: TextStyle(
            color: txtColor.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 100,
          decoration: BoxDecoration(
            color: txtColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: CustomPaint(
            size: const Size(double.infinity, 100),
            painter: _AltitudeGraphPainter(
              object: object,
              ref: ref,
              lineColor: accent,
              gridColor: txtColor.withValues(alpha: 0.2),
              cloudCoverPercent: cloudCoverPercent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAirmassChart(WidgetRef ref, Color txtColor, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Airmass Over 24 Hours',
              style: TextStyle(
                color: txtColor.withValues(alpha: 0.7),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            // Legend
            _buildAirmassLegendDot(const Color(0xFF4CAF50), '< 1.5', txtColor),
            const SizedBox(width: 6),
            _buildAirmassLegendDot(const Color(0xFFFFC107), '1.5-2', txtColor),
            const SizedBox(width: 6),
            _buildAirmassLegendDot(const Color(0xFFF44336), '> 2.0', txtColor),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: txtColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: CustomPaint(
            size: const Size(double.infinity, 120),
            painter: _AirmassChartPainter(
              object: object,
              ref: ref,
              txtColor: txtColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAirmassLegendDot(Color color, String label, Color txtColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: txtColor.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildRiseTransitSetSection(WidgetRef ref, Color txtColor) {
    final location = ref.watch(observerLocationProvider);
    final obsTime = ref.watch(observationTimeProvider);
    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: object.coordinates.ra * 15,
      decDeg: object.coordinates.dec,
      date: obsTime.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    var riseText = _formatTime(visibility.riseTime);
    var transitText = _formatTime(visibility.transitTime);
    var setText = _formatTime(visibility.setTime);

    if (visibility.neverRises) {
      riseText = 'Never';
      setText = 'Never';
    } else if (visibility.isCircumpolar) {
      riseText = 'Always';
      setText = 'Always';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rise / Transit / Set',
          style: TextStyle(
            color: txtColor.withValues(alpha: 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildTimeColumn(LucideIcons.sunrise, 'Rise', riseText, txtColor),
            _buildTimeColumn(
              LucideIcons.arrowUp,
              'Transit',
              transitText,
              txtColor,
            ),
            _buildTimeColumn(LucideIcons.sunset, 'Set', setText, txtColor),
          ],
        ),
      ],
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTimeColumn(
      IconData icon, String label, String time, Color txtColor) {
    return Column(
      children: [
        Icon(icon, size: 16, color: txtColor.withValues(alpha: 0.7)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: txtColor.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
        Text(
          time,
          style: TextStyle(
            color: txtColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(Color accent) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: Icon(LucideIcons.crosshair, size: 16, color: accent),
            label: Text('Go To', style: TextStyle(color: accent)),
            onPressed: onGoTo,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Add Target'),
            onPressed: onAddToTargets,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, Color txtColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: txtColor.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: txtColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getObjectIcon() {
    if (object is Star) {
      return LucideIcons.sparkles;
    } else if (object is DeepSkyObject) {
      final dso = object as DeepSkyObject;
      return switch (dso.type) {
        DsoType.galaxy => LucideIcons.orbit,
        DsoType.nebula => LucideIcons.cloud,
        DsoType.openCluster => LucideIcons.asterisk,
        DsoType.globularCluster => LucideIcons.circle,
        DsoType.planetaryNebula => LucideIcons.circleSlash,
        _ => LucideIcons.star,
      };
    }
    return LucideIcons.star;
  }

  Color _getTypeColor() {
    if (object is Star) {
      return Colors.yellow;
    } else if (object is DeepSkyObject) {
      final dso = object as DeepSkyObject;
      return switch (dso.type) {
        DsoType.galaxy => Colors.purple,
        DsoType.nebula => Colors.red,
        DsoType.openCluster => Colors.blue,
        DsoType.globularCluster => Colors.orange,
        DsoType.planetaryNebula => Colors.cyan,
        _ => Colors.grey,
      };
    }
    return Colors.grey;
  }

  String _getTypeString() {
    if (object is Star) {
      return 'Star';
    } else if (object is DeepSkyObject) {
      final dso = object as DeepSkyObject;
      return switch (dso.type) {
        DsoType.galaxy => 'Galaxy',
        DsoType.nebula => 'Nebula',
        DsoType.openCluster => 'Open Cluster',
        DsoType.globularCluster => 'Globular Cluster',
        DsoType.planetaryNebula => 'Planetary Nebula',
        DsoType.supernova => 'Supernova Remnant',
        DsoType.starCloud => 'Star Cloud',
        DsoType.asterism => 'Asterism',
        _ => 'Deep Sky Object',
      };
    }
    return 'Celestial Object';
  }

  String? _getConstellation() {
    if (object is Star) {
      return (object as Star).constellation;
    } else if (object is DeepSkyObject) {
      return (object as DeepSkyObject).constellation;
    }
    return null;
  }

  List<String> _getCatalogIds() {
    final ids = <String>[object.id];
    if (object.name != object.id) {
      ids.add(object.name);
    }
    if (object is Star) {
      ids.addAll((object as Star).catalogIds);
    } else if (object is DeepSkyObject) {
      ids.addAll((object as DeepSkyObject).catalogIds);
    }
    return ids.toSet().toList(); // Remove duplicates
  }

  // ============================================================================
  // Thumbnail Widget
  // ============================================================================

  /// Build a survey thumbnail for DSOs with icon fallback on network/load errors.
  Widget _buildThumbnail(DeepSkyObject dso) {
    final request = SurveyImageRequest(
      raDeg: dso.coordinates.ra * 15.0,
      decDeg: dso.coordinates.dec,
      fovWidth: _thumbnailFovDeg(dso),
      fovHeight: _thumbnailFovDeg(dso),
      pixelWidth: 256,
      pixelHeight: 256,
      source: SurveySource.dss2Red,
    );

    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Image.network(
          request.aladinUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Icon(
                _getDsoIcon(dso.type),
                color: _getDsoColor(dso.type),
                size: 32,
              ),
            );
          },
        ),
      ),
    );
  }

  double _thumbnailFovDeg(DeepSkyObject dso) {
    final majorArcMin = dso.sizeArcMin;
    final minorArcMin = dso.minorAxisArcMin;
    final largestArcMin = math.max(majorArcMin ?? 0.0, minorArcMin ?? 0.0);
    if (largestArcMin <= 0) {
      return 1.5;
    }

    // Frame the target with margin while avoiding very small/very large cutouts.
    return (largestArcMin * 3.0 / 60.0).clamp(0.25, 3.0);
  }

  /// Get icon for DSO type (for thumbnail)
  IconData _getDsoIcon(DsoType type) {
    return switch (type) {
      DsoType.galaxy ||
      DsoType.galaxyPair ||
      DsoType.galaxyTriplet ||
      DsoType.galaxyGroup =>
        LucideIcons.orbit,
      DsoType.nebula ||
      DsoType.emissionNebula ||
      DsoType.reflectionNebula ||
      DsoType.darkNebula ||
      DsoType.hiiRegion =>
        LucideIcons.cloud,
      DsoType.openCluster ||
      DsoType.clusterWithNebulosity =>
        LucideIcons.asterisk,
      DsoType.globularCluster => LucideIcons.circle,
      DsoType.planetaryNebula => LucideIcons.circleSlash,
      DsoType.supernova => LucideIcons.zap,
      DsoType.starCloud => LucideIcons.sparkles,
      DsoType.asterism => LucideIcons.shapes,
      _ => LucideIcons.star,
    };
  }

  /// Get color for DSO type (for thumbnail)
  Color _getDsoColor(DsoType type) {
    return switch (type) {
      DsoType.galaxy ||
      DsoType.galaxyPair ||
      DsoType.galaxyTriplet ||
      DsoType.galaxyGroup =>
        Colors.purple,
      DsoType.nebula ||
      DsoType.emissionNebula ||
      DsoType.hiiRegion =>
        Colors.red,
      DsoType.reflectionNebula => Colors.blue,
      DsoType.darkNebula => Colors.grey,
      DsoType.openCluster || DsoType.clusterWithNebulosity => Colors.blue,
      DsoType.globularCluster => Colors.orange,
      DsoType.planetaryNebula => Colors.cyan,
      DsoType.supernova => Colors.amber,
      DsoType.starCloud => Colors.lightBlue,
      _ => Colors.grey,
    };
  }

  // ============================================================================
  // Task 2: Quick Stats Bar Widget
  // ============================================================================

  /// Build a quick stats bar showing altitude, transit time, and moon distance
  Widget _buildQuickStats(WidgetRef ref, double altitude, Color txtColor) {
    final location = ref.watch(observerLocationProvider);
    final obsTime = ref.watch(observationTimeProvider);

    // Calculate transit time
    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: object.coordinates.ra * 15,
      decDeg: object.coordinates.dec,
      date: obsTime.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    // Format transit time
    String transitTime = '--:--';
    if (visibility.transitTime != null) {
      final t = visibility.transitTime!;
      transitTime =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    // Calculate moon distance (angular separation from moon)
    final (moonRa, moonDec, _) =
        AstronomyCalculations.moonPosition(obsTime.time);
    final moonDist = AstronomyCalculations.angularSeparation(
      ra1Deg: object.coordinates.ra * 15,
      dec1Deg: object.coordinates.dec,
      ra2Deg: moonRa,
      dec2Deg: moonDec,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: txtColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            icon: LucideIcons.mountain,
            label: 'Alt',
            value: '${altitude.toStringAsFixed(0)}°',
            color: txtColor,
          ),
          _StatItem(
            icon: LucideIcons.clock,
            label: 'Transit',
            value: transitTime,
            color: txtColor,
          ),
          _StatItem(
            icon: LucideIcons.moon,
            label: 'Moon',
            value: '${moonDist.toStringAsFixed(0)}°',
            color: txtColor,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Task 3: Visibility Score Indicator
  // ============================================================================

  /// Calculate visibility score (0-100) based on altitude, moon phase, and twilight
  int _calculateVisibilityScore(WidgetRef ref, double altitude) {
    final obsTime = ref.watch(observationTimeProvider);
    final location = ref.watch(observerLocationProvider);

    // Start with base score of 0
    var score = 0.0;

    // Altitude score (0-40 points)
    // Objects below horizon get 0, objects at zenith get 40
    if (altitude > 0) {
      score += (altitude / 90) * 40;
    }

    // Moon phase score (0-30 points)
    // New moon = 30 points, Full moon = 0 points
    final moonIllumination =
        AstronomyCalculations.moonIllumination(obsTime.time);
    score += ((100 - moonIllumination) / 100) * 30;

    // Moon distance score (0-15 points)
    // Far from moon = 15 points, close to moon = 0 points
    final (moonRa, moonDec, _) =
        AstronomyCalculations.moonPosition(obsTime.time);
    final moonDist = AstronomyCalculations.angularSeparation(
      ra1Deg: object.coordinates.ra * 15,
      dec1Deg: object.coordinates.dec,
      ra2Deg: moonRa,
      dec2Deg: moonDec,
    );
    score += math.min(moonDist / 60, 1.0) * 15; // Max at 60 degrees

    // Twilight/darkness score (0-15 points)
    // Full darkness (sun < -18°) = 15 points
    final sunAlt = AstronomyCalculations.sunAltitude(
      dt: obsTime.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );
    if (sunAlt < -18) {
      score += 15; // Astronomical darkness
    } else if (sunAlt < -12) {
      score += 10; // Nautical twilight
    } else if (sunAlt < -6) {
      score += 5; // Civil twilight
    } else if (sunAlt < 0) {
      score += 2; // Just below horizon
    }
    // Daytime = 0 points

    return score.round().clamp(0, 100);
  }

  /// Build visibility score indicator widget
  Widget _buildVisibilityIndicator(int score) {
    final color = score >= 70
        ? Colors.green
        : score >= 40
            ? Colors.amber
            : Colors.red;
    final label = score >= 70
        ? 'Excellent'
        : score >= 40
            ? 'Fair'
            : 'Poor';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.eye, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            '$score - $label',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper widget for displaying a stat item in the quick stats bar
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color.withValues(alpha: 0.7)),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.5),
            fontSize: 10,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Paints the altitude graph with optional cloud cover background band.
class _AltitudeGraphPainter extends CustomPainter {
  final CelestialObject object;
  final WidgetRef ref;
  final Color lineColor;
  final Color gridColor;

  /// Current cloud cover percentage (0-100). When non-null, draws a
  /// semi-transparent background band across the chart:
  /// green (<20%), yellow (20-60%), red (>60%).
  final double? cloudCoverPercent;

  _AltitudeGraphPainter({
    required this.object,
    required this.ref,
    required this.lineColor,
    required this.gridColor,
    this.cloudCoverPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final location = ref.read(observerLocationProvider);
    final now = ref.read(observationTimeProvider).time;

    // Draw cloud cover background band (behind everything else)
    if (cloudCoverPercent != null) {
      final cc = cloudCoverPercent!;
      Color bandColor;
      if (cc < 20) {
        // Clear: green
        bandColor = const Color(0xFF4CAF50).withValues(alpha: 0.12);
      } else if (cc < 60) {
        // Partial: yellow/amber
        bandColor = const Color(0xFFFFC107).withValues(alpha: 0.12);
      } else {
        // Overcast: red
        bandColor = const Color(0xFFF44336).withValues(alpha: 0.12);
      }
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = bandColor,
      );

      // Draw a small cloud cover label in the top-right
      final ccLabel = '${cc.round()}% cloud';
      Color labelColor;
      if (cc < 20) {
        labelColor = const Color(0xFF4CAF50);
      } else if (cc < 60) {
        labelColor = const Color(0xFFFFC107);
      } else {
        labelColor = const Color(0xFFF44336);
      }
      final textPainter = TextPainter(
        text: TextSpan(
          text: ccLabel,
          style: TextStyle(
            color: labelColor.withValues(alpha: 0.7),
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(size.width - textPainter.width - 4, 2),
      );
    }

    // Draw grid
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    // Horizon line
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      gridPaint,
    );

    // Calculate altitudes over 24 hours
    final points = <Offset>[];
    for (int hour = 0; hour < 24; hour++) {
      final time = DateTime(now.year, now.month, now.day, hour);
      final (alt, _) = AstronomyCalculations.objectAltAz(
        raDeg: object.coordinates.ra * 15,
        decDeg: object.coordinates.dec,
        dt: time,
        latitudeDeg: location.latitude,
        longitudeDeg: location.longitude,
      );

      final x = (hour / 24) * size.width;
      final y = size.height / 2 - (alt / 90) * (size.height / 2);
      points.add(Offset(x, y.clamp(0, size.height)));
    }

    // Draw the altitude curve
    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }

      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawPath(path, linePaint);
    }

    // Draw current time indicator
    final currentHour = now.hour + now.minute / 60;
    final currentX = (currentHour / 24) * size.width;
    canvas.drawLine(
      Offset(currentX, 0),
      Offset(currentX, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _AltitudeGraphPainter oldDelegate) {
    return object != oldDelegate.object ||
        cloudCoverPercent != oldDelegate.cloudCoverPercent;
  }
}

/// Paints the airmass chart with color zones
/// Y-axis is inverted: 1.0 at top (best), higher values toward bottom (worse)
/// Color zones: green < 1.5, yellow 1.5-2.0, red > 2.0
class _AirmassChartPainter extends CustomPainter {
  final CelestialObject object;
  final WidgetRef ref;
  final Color txtColor;

  // Airmass display range: 1.0 (top) to 3.0 (bottom)
  static const double _minAirmass = 1.0;
  static const double _maxAirmass = 3.0;

  _AirmassChartPainter({
    required this.object,
    required this.ref,
    required this.txtColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final location = ref.read(observerLocationProvider);
    final now = ref.read(observationTimeProvider).time;

    final gridColor = txtColor.withValues(alpha: 0.15);
    final labelStyle = TextStyle(
      color: txtColor.withValues(alpha: 0.4),
      fontSize: 9,
    );

    // Chart margins for labels
    const leftMargin = 28.0;
    const rightMargin = 4.0;
    const topMargin = 4.0;
    const bottomMargin = 14.0;
    final chartWidth = size.width - leftMargin - rightMargin;
    final chartHeight = size.height - topMargin - bottomMargin;

    // Draw color zone backgrounds
    final greenZoneBottom = _airmassToY(1.5, chartHeight) + topMargin;
    final yellowZoneBottom = _airmassToY(2.0, chartHeight) + topMargin;

    // Green zone: 1.0 to 1.5
    canvas.drawRect(
      Rect.fromLTRB(leftMargin, topMargin, leftMargin + chartWidth, greenZoneBottom),
      Paint()..color = const Color(0xFF4CAF50).withValues(alpha: 0.08),
    );

    // Yellow zone: 1.5 to 2.0
    canvas.drawRect(
      Rect.fromLTRB(leftMargin, greenZoneBottom, leftMargin + chartWidth, yellowZoneBottom),
      Paint()..color = const Color(0xFFFFC107).withValues(alpha: 0.08),
    );

    // Red zone: 2.0 to 3.0
    canvas.drawRect(
      Rect.fromLTRB(leftMargin, yellowZoneBottom, leftMargin + chartWidth, topMargin + chartHeight),
      Paint()..color = const Color(0xFFF44336).withValues(alpha: 0.08),
    );

    // Draw horizontal grid lines at airmass values
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    for (final am in [1.0, 1.5, 2.0, 2.5, 3.0]) {
      final y = _airmassToY(am, chartHeight) + topMargin;
      canvas.drawLine(
        Offset(leftMargin, y),
        Offset(leftMargin + chartWidth, y),
        gridPaint,
      );

      // Y-axis label
      final tp = TextPainter(
        text: TextSpan(text: am.toStringAsFixed(1), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(leftMargin - tp.width - 4, y - tp.height / 2));
    }

    // Calculate airmass values over 24 hours (every 15 minutes for smoothness)
    final points = <Offset>[];
    final airmassValues = <double>[];
    double? bestAirmass;
    int? bestTimeMinute;

    for (int minute = 0; minute < 24 * 60; minute += 15) {
      final hour = minute ~/ 60;
      final min = minute % 60;
      final time = DateTime(now.year, now.month, now.day, hour, min);
      final (alt, _) = AstronomyCalculations.objectAltAz(
        raDeg: object.coordinates.ra * 15,
        decDeg: object.coordinates.dec,
        dt: time,
        latitudeDeg: location.latitude,
        longitudeDeg: location.longitude,
      );

      if (alt > 0) {
        final am = AstronomyCalculations.airmass(alt);
        final clampedAm = am.clamp(_minAirmass, _maxAirmass);
        final x = leftMargin + (minute / (24 * 60)) * chartWidth;
        final y = _airmassToY(clampedAm, chartHeight) + topMargin;
        points.add(Offset(x, y));
        airmassValues.add(am);

        if (bestAirmass == null || am < bestAirmass) {
          bestAirmass = am;
          bestTimeMinute = minute;
        }
      } else {
        // Object below horizon - break the line
        if (points.isNotEmpty) {
          _drawAirmassSegment(canvas, points, airmassValues, chartHeight, topMargin);
          points.clear();
          airmassValues.clear();
        }
      }
    }

    // Draw remaining points
    if (points.isNotEmpty) {
      _drawAirmassSegment(canvas, points, airmassValues, chartHeight, topMargin);
    }

    // Draw current time indicator
    final currentMinute = now.hour * 60 + now.minute;
    final currentX = leftMargin + (currentMinute / (24 * 60)) * chartWidth;
    canvas.drawLine(
      Offset(currentX, topMargin),
      Offset(currentX, topMargin + chartHeight),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Mark best observing window
    if (bestTimeMinute != null && bestAirmass != null && bestAirmass < _maxAirmass) {
      final bestX = leftMargin + (bestTimeMinute / (24 * 60)) * chartWidth;
      final bestY = _airmassToY(bestAirmass.clamp(_minAirmass, _maxAirmass), chartHeight) + topMargin;

      // Draw diamond marker
      final markerPath = Path()
        ..moveTo(bestX, bestY - 4)
        ..lineTo(bestX + 4, bestY)
        ..lineTo(bestX, bestY + 4)
        ..lineTo(bestX - 4, bestY)
        ..close();
      canvas.drawPath(
        markerPath,
        Paint()
          ..color = const Color(0xFF4CAF50)
          ..style = PaintingStyle.fill,
      );

      // Label "best" below marker
      final bestLabel = TextPainter(
        text: const TextSpan(
          text: 'best',
          style: TextStyle(
            color: Color(0xFF4CAF50),
            fontSize: 8,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final labelX = (bestX - bestLabel.width / 2).clamp(
        leftMargin,
        leftMargin + chartWidth - bestLabel.width,
      );
      bestLabel.paint(canvas, Offset(labelX, bestY + 6));
    }

    // Draw time labels at bottom
    for (final hour in [0, 6, 12, 18]) {
      final x = leftMargin + (hour / 24) * chartWidth;
      final label = '${hour.toString().padLeft(2, '0')}h';
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, topMargin + chartHeight + 2));
    }
  }

  /// Convert airmass value to Y pixel coordinate within the chart area
  double _airmassToY(double airmass, double chartHeight) {
    // Inverted: 1.0 at top, 3.0 at bottom
    final fraction = (airmass - _minAirmass) / (_maxAirmass - _minAirmass);
    return fraction * chartHeight;
  }

  /// Draw a segment of the airmass curve with color coding
  void _drawAirmassSegment(
    Canvas canvas,
    List<Offset> points,
    List<double> airmassValues,
    double chartHeight,
    double topMargin,
  ) {
    if (points.length < 2) return;

    // Draw line segments with colors based on airmass zone
    for (int i = 0; i < points.length - 1; i++) {
      final am = airmassValues[i];
      Color segmentColor;
      if (am < 1.5) {
        segmentColor = const Color(0xFF4CAF50); // Green
      } else if (am < 2.0) {
        segmentColor = const Color(0xFFFFC107); // Yellow
      } else {
        segmentColor = const Color(0xFFF44336); // Red
      }

      canvas.drawLine(
        points[i],
        points[i + 1],
        Paint()
          ..color = segmentColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AirmassChartPainter oldDelegate) {
    return object != oldDelegate.object;
  }
}
