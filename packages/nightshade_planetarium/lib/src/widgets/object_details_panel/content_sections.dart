part of '../object_details_panel.dart';

extension _ObjectDetailsPanelContentSections on ObjectDetailsPanel {
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
    Color txtColor,
    Color accent,
    DeepSkyObject dso,
  ) {
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
                        horizontal: 6,
                        vertical: 2,
                      ),
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
                        horizontal: 6,
                        vertical: 2,
                      ),
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
    final decMinutes = ((object.coordinates.dec.abs() - decDegrees) * 60)
        .floor();
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
          '$decSign$decDegrees° $decMinutes\' $decSeconds"',
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
        properties.add(
          _buildInfoRow(
            'PA',
            '${dso.positionAngle!.toStringAsFixed(0)}°',
            txtColor,
          ),
        );
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
              // Watch (not read): if the user changes their effective
              // horizon mid-session the painter must rebuild — passing
              // the value as a constructor field combined with
              // shouldRepaint comparing it gives Flutter the trigger.
              effectiveHorizonDeg: ref.watch(
                planetariumEffectiveHorizonDegProvider,
              ),
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
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: txtColor.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  Widget _buildRiseTransitSetSection(WidgetRef ref, Color txtColor) {
    final location = ref.watch(observerLocationProvider);
    final obsTime = ref.watch(observationTimeProvider);
    // Rise/set computed against the user's effective
    // horizon (e.g. 20° to clear trees), not the mathematical 0°. The same
    // value drives the Run Dashboard time-to-set stat so the two surfaces
    // agree to the second.
    final horizonDeg = ref.watch(planetariumEffectiveHorizonDegProvider);
    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: object.coordinates.ra * 15,
      decDeg: object.coordinates.dec,
      date: obsTime.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
      minAltitude: horizonDeg,
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

    // Label hint: when the user has set a non-zero horizon, surface it so
    // the displayed times aren't mistaken for the mathematical horizon.
    final headerLabel = horizonDeg > 0
        ? 'Rise / Transit / Set (≥${horizonDeg.toStringAsFixed(0)}°)'
        : 'Rise / Transit / Set';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          headerLabel,
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
    IconData icon,
    String label,
    String time,
    Color txtColor,
  ) {
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
    // Second row of "act on this target from the sky" actions, shown only when
    // the host wired the callbacks (Frame target → Framing screen, Add to
    // sequence → add-to-sequence flow). Styled to mirror the primary row: a
    // ghost OutlinedButton paired with a FilledButton accent.
    final hasFrame = onFrameTarget != null;
    final hasAddToSequence = onAddToSequence != null;

    return Column(
      children: [
        Row(
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
        ),
        if (hasFrame || hasAddToSequence) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (hasFrame)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(LucideIcons.scan, size: 16, color: accent),
                    label: Text(
                      'Frame target',
                      style: TextStyle(color: accent),
                    ),
                    onPressed: onFrameTarget,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accent.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              if (hasFrame && hasAddToSequence) const SizedBox(width: 12),
              if (hasAddToSequence)
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(LucideIcons.listPlus, size: 16, color: accent),
                    label: Text(
                      'Add to sequence',
                      style: TextStyle(color: accent),
                    ),
                    onPressed: onAddToSequence,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accent.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
            ],
          ),
        ],
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
      DsoType.galaxyGroup => LucideIcons.orbit,
      DsoType.nebula ||
      DsoType.emissionNebula ||
      DsoType.reflectionNebula ||
      DsoType.darkNebula ||
      DsoType.hiiRegion => LucideIcons.cloud,
      DsoType.openCluster ||
      DsoType.clusterWithNebulosity => LucideIcons.asterisk,
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
      DsoType.galaxyGroup => Colors.purple,
      DsoType.nebula ||
      DsoType.emissionNebula ||
      DsoType.hiiRegion => Colors.red,
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
    final (moonRa, moonDec, _) = AstronomyCalculations.moonPosition(
      obsTime.time,
    );
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
    final moonIllumination = AstronomyCalculations.moonIllumination(
      obsTime.time,
    );
    score += ((100 - moonIllumination) / 100) * 30;

    // Moon distance score (0-15 points)
    // Far from moon = 15 points, close to moon = 0 points
    final (moonRa, moonDec, _) = AstronomyCalculations.moonPosition(
      obsTime.time,
    );
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
