import 'dart:math' as math;
import '../models/sequence/sequence_models.dart';
import '../models/imaging/imaging_models.dart' show FrameType;
import 'package:uuid/uuid.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    show AstronomyCalculations;

/// Result of mosaic panel generation
class MosaicPanel {
  final double raHours;
  final double decDegrees;
  final int panelIndex;
  final int row;
  final int col;

  const MosaicPanel({
    required this.raHours,
    required this.decDegrees,
    required this.panelIndex,
    required this.row,
    required this.col,
  });

  @override
  String toString() =>
      'Panel $panelIndex [$row,$col]: RA=${raHours.toStringAsFixed(4)}h, Dec=${decDegrees.toStringAsFixed(4)}°';
}

/// Configuration for generating a mosaic
class MosaicConfig {
  final double centerRa;
  final double centerDec;
  final double panelWidthArcmin;
  final double panelHeightArcmin;
  final double overlapPercent;
  final double rotation;
  final int panelsHorizontal;
  final int panelsVertical;

  const MosaicConfig({
    required this.centerRa,
    required this.centerDec,
    required this.panelWidthArcmin,
    required this.panelHeightArcmin,
    this.overlapPercent = 10.0,
    this.rotation = 0.0,
    required this.panelsHorizontal,
    required this.panelsVertical,
  });

  int get totalPanels => panelsHorizontal * panelsVertical;

  double get totalAreaSquareDegrees {
    final widthDeg = (panelWidthArcmin * panelsHorizontal) / 60.0;
    final heightDeg = (panelHeightArcmin * panelsVertical) / 60.0;
    return widthDeg * heightDeg;
  }
}

/// Exposure settings for each panel
class MosaicExposureSettings {
  final double exposureSeconds;
  final int exposuresPerPanel;
  final String? filterName;
  final int? binning;
  final double? gain;
  final double? offset;

  const MosaicExposureSettings({
    required this.exposureSeconds,
    required this.exposuresPerPanel,
    this.filterName,
    this.binning,
    this.gain,
    this.offset,
  });
}

/// Options for mosaic sequence generation
class MosaicSequenceOptions {
  /// Use serpentine (snake) ordering to minimize slew distance
  final bool serpentineOrdering;

  /// Add autofocus before each panel
  final bool autofocusPerPanel;

  /// Autofocus interval (0 = every panel, 1 = every other panel, etc.)
  final int autofocusInterval;

  /// Add plate solving/centering after slew
  final bool centerAfterSlew;

  /// Add dithering between exposures
  final bool ditherBetweenExposures;

  /// Dither amount in pixels
  final double? ditherPixels;

  /// Minimum altitude constraint (degrees)
  final double? minAltitude;

  /// Maximum altitude constraint (degrees)
  final double? maxAltitude;

  const MosaicSequenceOptions({
    this.serpentineOrdering = true,
    this.autofocusPerPanel = false,
    this.autofocusInterval = 0,
    this.centerAfterSlew = true,
    this.ditherBetweenExposures = false,
    this.ditherPixels,
    this.minAltitude,
    this.maxAltitude,
  });
}

/// Validation result for a mosaic configuration
class MosaicValidation {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;

  const MosaicValidation({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
  });

  bool get hasWarnings => warnings.isNotEmpty;
}

/// Service for generating and managing mosaics
class MosaicService {
  const MosaicService();

  double _normalizeRaHours(double raHours) {
    var normalized = raHours % 24.0;
    if (normalized < 0) {
      normalized += 24.0;
    }
    return normalized;
  }

  /// Convert int binning to BinningMode enum
  BinningMode _intToBinningMode(int binning) {
    switch (binning) {
      case 1:
        return BinningMode.one;
      case 2:
        return BinningMode.two;
      case 3:
        return BinningMode.three;
      case 4:
        return BinningMode.four;
      default:
        return BinningMode.one;
    }
  }

  /// Generate mosaic panels from configuration
  ///
  /// Returns a list of panel coordinates calculated using pure Dart spherical geometry.
  /// This implementation is driver-agnostic and works for both local and remote clients.
  List<MosaicPanel> generatePanels(MosaicConfig config) {
    final panels = <MosaicPanel>[];
    
    // Calculate effective step sizes accounting for overlap
    final overlapFactor = 1.0 - (config.overlapPercent / 100.0);
    final effectiveWidthArcmin = config.panelWidthArcmin * overlapFactor;
    final effectiveHeightArcmin = config.panelHeightArcmin * overlapFactor;
    
    // Convert arcmin to degrees for calculations
    final stepDecDeg = effectiveHeightArcmin / 60.0;
    final stepRaDeg = effectiveWidthArcmin / 60.0;
    
    // Calculate center offsets (for centering the grid on the target)
    final halfHorizontal = (config.panelsHorizontal - 1) / 2.0;
    final halfVertical = (config.panelsVertical - 1) / 2.0;
    
    // Pre-calculate rotation if needed
    final rotationRad = config.rotation * 3.141592653589793 / 180.0;
    final cosRot = rotationRad == 0 ? 1.0 : _cos(rotationRad);
    final sinRot = rotationRad == 0 ? 0.0 : _sin(rotationRad);
    
    // RA compression factor at target declination (cos(dec) correction)
    final decRad = config.centerDec * 3.141592653589793 / 180.0;
    final raCompressionFactor = _cos(decRad);
    
    int panelIndex = 0;
    for (int row = 0; row < config.panelsVertical; row++) {
      for (int col = 0; col < config.panelsHorizontal; col++) {
        // Calculate offset from center in grid coordinates
        final colOffset = col - halfHorizontal;
        final rowOffset = row - halfVertical;
        
        // Apply rotation to get delta in degrees
        double dRaDeg, dDecDeg;
        if (config.rotation != 0) {
          // Rotate the offset
          dRaDeg = colOffset * stepRaDeg * cosRot - rowOffset * stepDecDeg * sinRot;
          dDecDeg = colOffset * stepRaDeg * sinRot + rowOffset * stepDecDeg * cosRot;
        } else {
          dRaDeg = colOffset * stepRaDeg;
          dDecDeg = rowOffset * stepDecDeg;
        }
        
        // Apply RA compression correction (RA spans more degrees near poles)
        final raAdjustDeg = raCompressionFactor > 0.001 
            ? dRaDeg / raCompressionFactor 
            : dRaDeg;
        
        // Convert RA offset from degrees to hours (15 degrees = 1 hour)
        final raHours = _normalizeRaHours(config.centerRa + (raAdjustDeg / 15.0));
        final decDegrees = config.centerDec + dDecDeg;
        
        panels.add(MosaicPanel(
          raHours: raHours,
          decDegrees: decDegrees,
          panelIndex: panelIndex++,
          row: row,
          col: col,
        ));
      }
    }
    
    return panels;
  }

  /// Cosine using dart:math for accuracy
  double _cos(double radians) => math.cos(radians);

  /// Sine using dart:math for accuracy
  double _sin(double radians) => math.sin(radians);

  /// Calculate total mosaic area in square degrees (pure Dart implementation)
  double calculateMosaicArea(MosaicConfig config) {
    // Total width and height in arcminutes
    final totalWidthArcmin = config.panelWidthArcmin * config.panelsHorizontal;
    final totalHeightArcmin = config.panelHeightArcmin * config.panelsVertical;
    
    // Convert to degrees and calculate area
    final widthDeg = totalWidthArcmin / 60.0;
    final heightDeg = totalHeightArcmin / 60.0;
    
    return widthDeg * heightDeg;
  }

  /// Estimate total imaging time in seconds (pure Dart implementation)
  double estimateMosaicTime(
    MosaicConfig config,
    MosaicExposureSettings exposure, {
    double overheadPerPanelSecs = 60.0,
  }) {
    // Total time = panels * (exposures per panel * exposure time + overhead)
    final exposureTimePerPanel = exposure.exposuresPerPanel * exposure.exposureSeconds;
    final totalTimePerPanel = exposureTimePerPanel + overheadPerPanelSecs;
    return config.totalPanels * totalTimePerPanel;
  }

  /// Validate mosaic configuration
  MosaicValidation validateMosaic(MosaicConfig config) {
    final errors = <String>[];
    final warnings = <String>[];

    // Validate panel dimensions
    if (config.panelWidthArcmin <= 0 || config.panelHeightArcmin <= 0) {
      errors.add('Panel dimensions must be positive');
    }

    if (config.panelWidthArcmin > 360 * 60 || config.panelHeightArcmin > 360 * 60) {
      errors.add('Panel dimensions exceed 360 degrees');
    }

    // Validate grid size
    if (config.panelsHorizontal < 1 || config.panelsVertical < 1) {
      errors.add('Grid size must be at least 1x1');
    }

    if (config.panelsHorizontal > 20 || config.panelsVertical > 20) {
      warnings.add('Large mosaics (>20 panels per dimension) may take very long');
    }

    // Validate coordinates
    if (config.centerRa < 0 || config.centerRa >= 24) {
      errors.add('Right Ascension must be between 0 and 24 hours');
    }

    if (config.centerDec < -90 || config.centerDec > 90) {
      errors.add('Declination must be between -90 and 90 degrees');
    }

    // Validate overlap
    if (config.overlapPercent < 0 || config.overlapPercent > 100) {
      errors.add('Overlap must be between 0 and 100 percent');
    }

    if (config.overlapPercent < 5) {
      warnings.add('Low overlap (<5%) may cause stitching issues');
    }

    if (config.overlapPercent > 50) {
      warnings.add('High overlap (>50%) wastes imaging time');
    }

    // Check total panel count
    if (config.totalPanels > 100) {
      warnings.add('More than 100 panels will take multiple nights to complete');
    }

    // Check if target is near celestial poles
    if (config.centerDec.abs() > 80) {
      warnings.add('Targets near celestial poles may have distorted panel layout');
    }

    return MosaicValidation(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
    );
  }

  /// Create a sequence from mosaic panels
  ///
  /// Generates a complete imaging sequence with target groups for each panel
  Map<String, SequenceNode> createMosaicSequence({
    required String mosaicName,
    required MosaicConfig config,
    required MosaicExposureSettings exposure,
    MosaicSequenceOptions options = const MosaicSequenceOptions(),
  }) {
    final panels = generatePanels(config);
    final nodes = <String, SequenceNode>{};
    final uuid = const Uuid();

    // Reorder panels if using serpentine ordering
    final orderedPanels = options.serpentineOrdering
        ? _applySerpentineOrdering(panels, config.panelsHorizontal)
        : panels;

    // Create target group nodes for each panel
    final targetGroupIds = <String>[];

    for (var i = 0; i < orderedPanels.length; i++) {
      final panel = orderedPanels[i];
      final targetGroupId = uuid.v4();
      final childIds = <String>[];

      // Add autofocus if enabled and at the right interval
      if (options.autofocusPerPanel &&
          (options.autofocusInterval == 0 || i % (options.autofocusInterval + 1) == 0)) {
        final autofocusId = uuid.v4();
        childIds.add(autofocusId);
        nodes[autofocusId] = AutofocusNode(
          id: autofocusId,
          name: 'Autofocus',
          parentId: targetGroupId,
          orderIndex: childIds.length - 1,
        );
      }

      // Add slew instruction
      final slewId = uuid.v4();
      childIds.add(slewId);
      nodes[slewId] = SlewNode(
        id: slewId,
        name: 'Slew to Panel ${panel.panelIndex + 1}',
        useTargetCoords: false,
        customRa: panel.raHours,
        customDec: panel.decDegrees,
        parentId: targetGroupId,
        orderIndex: childIds.length - 1,
      );

      // Add centering if enabled
      if (options.centerAfterSlew) {
        final centerId = uuid.v4();
        childIds.add(centerId);
        nodes[centerId] = CenterNode(
          id: centerId,
          name: 'Center',
          parentId: targetGroupId,
          orderIndex: childIds.length - 1,
        );
      }

      // Create exposure loop
      final loopId = uuid.v4();
      childIds.add(loopId);

      // Create exposure node
      final exposureId = uuid.v4();
      final exposureChildIds = <String>[exposureId];

      // Add dither if enabled
      if (options.ditherBetweenExposures) {
        final ditherId = uuid.v4();
        exposureChildIds.add(ditherId);
        nodes[ditherId] = DitherNode(
          id: ditherId,
          name: 'Dither',
          parentId: loopId,
          orderIndex: 1,
          pixels: options.ditherPixels ?? 3.0,
        );
      }

      nodes[exposureId] = ExposureNode(
        id: exposureId,
        name: 'Expose',
        durationSecs: exposure.exposureSeconds,
        count: 1, // Loop handles the repetition
        frameType: FrameType.light,
        filter: exposure.filterName,
        binning: exposure.binning != null ? _intToBinningMode(exposure.binning!) : BinningMode.one,
        gain: exposure.gain?.toInt(),
        offset: exposure.offset?.toInt(),
        parentId: loopId,
        orderIndex: 0,
      );

      nodes[loopId] = LoopNode(
        id: loopId,
        name: 'Exposure Loop',
        conditionType: LoopConditionType.count,
        repeatCount: exposure.exposuresPerPanel,
        childIds: exposureChildIds,
        parentId: targetGroupId,
        orderIndex: childIds.length - 1,
      );

      // Create target header
      nodes[targetGroupId] = TargetHeaderNode(
        id: targetGroupId,
        name: 'Panel ${panel.panelIndex + 1} [${panel.row},${panel.col}]',
        targetName: '$mosaicName Panel ${panel.panelIndex + 1}',
        raHours: panel.raHours,
        decDegrees: panel.decDegrees,
        rotation: config.rotation != 0.0 ? config.rotation : null,
        priority: i,
        minAltitude: options.minAltitude,
        maxAltitude: options.maxAltitude,
        childIds: childIds,
        orderIndex: i,
      );

      targetGroupIds.add(targetGroupId);
    }

    // Create root instruction set containing all target groups
    final rootId = uuid.v4();
    nodes[rootId] = InstructionSetNode(
      id: rootId,
      name: mosaicName,
      childIds: targetGroupIds,
    );

    return nodes;
  }

  /// Apply serpentine (snake) ordering to panels to minimize slew distance
  ///
  /// Instead of always going left-to-right, alternate:
  /// Row 0: left -> right
  /// Row 1: right -> left
  /// Row 2: left -> right
  /// etc.
  List<MosaicPanel> _applySerpentineOrdering(
    List<MosaicPanel> panels,
    int panelsHorizontal,
  ) {
    // Group panels by row
    final rowMap = <int, List<MosaicPanel>>{};
    for (final panel in panels) {
      rowMap.putIfAbsent(panel.row, () => []).add(panel);
    }

    // Sort each row by column
    for (final row in rowMap.values) {
      row.sort((a, b) => a.col.compareTo(b.col));
    }

    // Build serpentine ordered list
    final result = <MosaicPanel>[];
    final sortedRows = rowMap.keys.toList()..sort();

    for (var i = 0; i < sortedRows.length; i++) {
      final row = sortedRows[i];
      final rowPanels = rowMap[row]!;

      // Reverse every other row
      if (i.isOdd) {
        result.addAll(rowPanels.reversed);
      } else {
        result.addAll(rowPanels);
      }
    }

    return result;
  }

  /// Calculate altitude for a given RA/Dec at a specific time and location
  ///
  /// Uses proper astronomical formulas via AstronomyCalculations:
  /// - Converts RA/Dec to Alt/Az using observer location and time
  /// - Accounts for local sidereal time
  /// - Returns altitude in degrees
  double calculateAltitude({
    required double raHours,
    required double decDegrees,
    required DateTime time,
    required double observerLatitude,
    required double observerLongitude,
  }) {
    // Convert RA from hours to degrees for the astronomy calculations
    final raDeg = raHours * 15.0;

    // Calculate local sidereal time at the observer's location
    final lst = AstronomyCalculations.localSiderealTime(time, observerLongitude);

    // Convert equatorial coordinates (RA/Dec) to horizontal coordinates (Alt/Az)
    final (altitude, _) = AstronomyCalculations.equatorialToHorizontal(
      raDeg: raDeg,
      decDeg: decDegrees,
      latitudeDeg: observerLatitude,
      lstHours: lst,
    );

    return altitude;
  }

  /// Check visibility window for mosaic panels
  ///
  /// Returns warnings if any panels will be below minimum altitude
  List<String> checkVisibilityConstraints({
    required MosaicConfig config,
    required DateTime startTime,
    required double observerLatitude,
    required double observerLongitude,
    double? minAltitude,
  }) {
    final warnings = <String>[];

    if (minAltitude != null) {
      // Generate panels to check
      final panels = generatePanels(config);

      // Check altitude for each panel
      final belowMinPanels = <int>[];
      for (final panel in panels) {
        final altitude = calculateAltitude(
          raHours: panel.raHours,
          decDegrees: panel.decDegrees,
          time: startTime,
          observerLatitude: observerLatitude,
          observerLongitude: observerLongitude,
        );

        if (altitude < minAltitude) {
          belowMinPanels.add(panel.panelIndex + 1); // 1-indexed for display
        }
      }

      // Add warning if any panels are below minimum
      if (belowMinPanels.isNotEmpty) {
        if (belowMinPanels.length == panels.length) {
          warnings.add(
            'All panels will be below minimum altitude '
            '($minAltitude°) at start time',
          );
        } else if (belowMinPanels.length > panels.length ~/ 2) {
          warnings.add(
            'Most panels (${belowMinPanels.length}/${panels.length}) will be '
            'below minimum altitude ($minAltitude°) at start time',
          );
        } else {
          warnings.add(
            'Some panels (${belowMinPanels.length}/${panels.length}) will be '
            'below minimum altitude ($minAltitude°) at start time: '
            'Panels ${belowMinPanels.take(5).join(", ")}'
            '${belowMinPanels.length > 5 ? "..." : ""}',
          );
        }
      }
    }

    return warnings;
  }
}
