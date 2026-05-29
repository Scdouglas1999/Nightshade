import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../backend/network_backend.dart';
import '../database/database.dart';
import '../models/equipment/equipment_models.dart';
import '../models/framing_plate_scale.dart';
import '../models/planning/target_suggestion.dart';
import '../models/target/target_models.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'equipment_provider.dart';
import 'framing_image_cache_provider.dart';
import 'profiles_provider.dart';

// =============================================================================
// ASTRONOMY HTTP CLIENT
// =============================================================================

/// Shared HTTP client for astronomy server requests.
/// Uses standard certificate verification — no SSL bypass.

// =============================================================================
// FRAMING STATE
// =============================================================================

/// State of the framing assistant
class FramingState {
  /// Selected target information
  final FramingTarget? target;

  /// Rich planning source for [target], when the target came from Plan Tonight
  /// or suggestions. Preserved so Framing can round-trip into Smart Night
  /// sequence generation without degrading to name/coordinate-only metadata.
  final TargetSuggestion? sourceSuggestion;

  /// Survey source for background image
  final SurveySource surveySource;

  /// Loaded survey image
  final Uint8List? surveyImageBytes;

  /// Decoded survey image for display
  final ui.Image? surveyImage;

  /// Astrometric registration linkage for the currently-loaded survey image.
  ///
  /// Populated whenever a survey cutout is successfully loaded (from network or
  /// cache). It pairs the *angular field of view that was requested* with the
  /// *actual decoded pixel dimensions* of the returned image, which is the one
  /// authoritative scale every framing painter and gesture handler projects
  /// through (see [FramingPlateScale]). `null` whenever no image is loaded.
  final FramingPlateScale? plateScale;

  /// Is the survey image loading?
  final bool isLoadingImage;

  /// Error message if image failed to load
  final String? imageError;

  /// Frame rotation in degrees
  final double rotation;

  /// Zoom level (1.0 = 100%)
  final double zoom;

  /// Pan offset in pixels
  final double panX;
  final double panY;

  /// Display options
  final bool showGrid;
  final bool showLabels;
  final bool showCardinalDirections;

  /// Custom equipment (null = use active profile)
  final FramingEquipment? customEquipment;

  /// Whether we're using custom equipment vs profile
  final bool useCustomEquipment;

  /// User-specified preview FOV for browsing without equipment (degrees)
  final double previewFovDegrees;

  /// Equipment FOV overlay opacity (0.0-1.0) - used when preview > equipment FOV
  final double equipmentFovOverlayOpacity;

  /// Whether to show equipment FOV overlay when preview FOV is larger
  final bool showEquipmentFovOverlay;

  /// Whether mosaic mode is enabled
  final bool mosaicEnabled;

  /// Mosaic configuration
  final FramingMosaicConfig mosaicConfig;

  /// Generated mosaic panels (computed from config and target)
  final List<FramingMosaicPanel> mosaicPanels;

  /// Currently selected panel index (-1 = none)
  final int selectedPanelIndex;

  /// Whether to show panel numbers on the overlay
  final bool showPanelNumbers;

  /// Whether to highlight the capture sequence path
  final bool showSequencePath;

  /// Whether to show the optical config overlay panel on the framing canvas
  final bool showOpticalConfigPanel;

  const FramingState({
    this.target,
    this.sourceSuggestion,
    this.surveySource = SurveySource.dss2Red,
    this.surveyImageBytes,
    this.surveyImage,
    this.plateScale,
    this.isLoadingImage = false,
    this.imageError,
    this.rotation = 0,
    this.zoom = 1.0,
    this.panX = 0,
    this.panY = 0,
    this.showGrid = true,
    this.showLabels = true,
    this.showCardinalDirections = true,
    this.customEquipment,
    this.useCustomEquipment = false,
    this.previewFovDegrees = 2.0,
    this.equipmentFovOverlayOpacity = 0.3,
    this.showEquipmentFovOverlay = true,
    this.mosaicEnabled = false,
    this.mosaicConfig = const FramingMosaicConfig(),
    this.mosaicPanels = const [],
    this.selectedPanelIndex = -1,
    this.showPanelNumbers = true,
    this.showSequencePath = true,
    this.showOpticalConfigPanel = false,
  });

  FramingState copyWith({
    FramingTarget? target,
    TargetSuggestion? sourceSuggestion,
    SurveySource? surveySource,
    Uint8List? surveyImageBytes,
    ui.Image? surveyImage,
    FramingPlateScale? plateScale,
    bool? isLoadingImage,
    String? imageError,
    double? rotation,
    double? zoom,
    double? panX,
    double? panY,
    bool? showGrid,
    bool? showLabels,
    bool? showCardinalDirections,
    FramingEquipment? customEquipment,
    bool? useCustomEquipment,
    double? previewFovDegrees,
    double? equipmentFovOverlayOpacity,
    bool? showEquipmentFovOverlay,
    bool? mosaicEnabled,
    FramingMosaicConfig? mosaicConfig,
    List<FramingMosaicPanel>? mosaicPanels,
    int? selectedPanelIndex,
    bool? showPanelNumbers,
    bool? showSequencePath,
    bool? showOpticalConfigPanel,
    bool clearImage = false,
    bool clearTarget = false,
    bool clearSourceSuggestion = false,
  }) {
    return FramingState(
      target: clearTarget ? null : (target ?? this.target),
      sourceSuggestion: clearTarget || clearSourceSuggestion
          ? null
          : (sourceSuggestion ?? this.sourceSuggestion),
      surveySource: surveySource ?? this.surveySource,
      surveyImageBytes:
          clearImage ? null : (surveyImageBytes ?? this.surveyImageBytes),
      surveyImage: clearImage ? null : (surveyImage ?? this.surveyImage),
      plateScale: clearImage ? null : (plateScale ?? this.plateScale),
      isLoadingImage: isLoadingImage ?? this.isLoadingImage,
      imageError: clearImage ? null : imageError,
      rotation: rotation ?? this.rotation,
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      showGrid: showGrid ?? this.showGrid,
      showLabels: showLabels ?? this.showLabels,
      showCardinalDirections:
          showCardinalDirections ?? this.showCardinalDirections,
      customEquipment: customEquipment ?? this.customEquipment,
      useCustomEquipment: useCustomEquipment ?? this.useCustomEquipment,
      previewFovDegrees: previewFovDegrees ?? this.previewFovDegrees,
      equipmentFovOverlayOpacity:
          equipmentFovOverlayOpacity ?? this.equipmentFovOverlayOpacity,
      showEquipmentFovOverlay:
          showEquipmentFovOverlay ?? this.showEquipmentFovOverlay,
      mosaicEnabled: mosaicEnabled ?? this.mosaicEnabled,
      mosaicConfig: mosaicConfig ?? this.mosaicConfig,
      mosaicPanels: mosaicPanels ?? this.mosaicPanels,
      selectedPanelIndex: selectedPanelIndex ?? this.selectedPanelIndex,
      showPanelNumbers: showPanelNumbers ?? this.showPanelNumbers,
      showSequencePath: showSequencePath ?? this.showSequencePath,
      showOpticalConfigPanel:
          showOpticalConfigPanel ?? this.showOpticalConfigPanel,
    );
  }
}

/// Target information for framing
class FramingTarget {
  final String name;
  final String? catalogId;
  final double raHours;
  final double decDegrees;
  final TargetType? type;
  final double? magnitude;
  final double? sizeArcmin;
  final String? constellation;

  const FramingTarget({
    required this.name,
    this.catalogId,
    required this.raHours,
    required this.decDegrees,
    this.type,
    this.magnitude,
    this.sizeArcmin,
    this.constellation,
  });

  /// RA in degrees
  double get raDegrees => raHours * 15;

  /// Format RA as HH:MM:SS
  String get raFormatted {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    final seconds = (((raHours - hours) * 60 - minutes) * 60).round();
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  /// Format Dec as ±DD°MM'SS"
  String get decFormatted {
    final sign = decDegrees >= 0 ? '+' : '-';
    final absDec = decDegrees.abs();
    final degrees = absDec.floor();
    final minutes = ((absDec - degrees) * 60).floor();
    final seconds = (((absDec - degrees) * 60 - minutes) * 60).round();
    return '$sign${degrees.toString().padLeft(2, '0')}° ${minutes.toString().padLeft(2, '0')}\' ${seconds.toString().padLeft(2, '0')}"';
  }

  factory FramingTarget.fromCelestialTarget(CelestialTarget t) {
    return FramingTarget(
      name: t.name,
      catalogId: t.catalogId,
      raHours: t.raHours,
      decDegrees: t.decDegrees,
      type: t.objectType,
      magnitude: t.magnitude,
      sizeArcmin: t.sizeArcmin,
      constellation: t.constellation,
    );
  }
}

TargetType? _targetTypeFromSuggestion(String? objectType) {
  final normalized = objectType?.toLowerCase().trim();
  if (normalized == null || normalized.isEmpty) return null;
  if (normalized.contains('galaxy')) return TargetType.galaxy;
  if (normalized.contains('nebula')) return TargetType.nebula;
  if (normalized.contains('cluster')) return TargetType.cluster;
  if (normalized.contains('star')) return TargetType.star;
  if (normalized.contains('planet')) return TargetType.planet;
  if (normalized.contains('moon')) return TargetType.moon;
  if (normalized.contains('comet')) return TargetType.comet;
  if (normalized.contains('asteroid')) return TargetType.asteroid;
  return TargetType.other;
}

/// Custom equipment configuration for framing
class FramingEquipment {
  final String cameraName;
  final double sensorWidthMm;
  final double sensorHeightMm;
  final double pixelSizeMicrons;
  final int pixelsX;
  final int pixelsY;

  final String telescopeName;
  final double focalLengthMm;
  final double apertureMm;

  final double focalReducer;

  const FramingEquipment({
    required this.cameraName,
    required this.sensorWidthMm,
    required this.sensorHeightMm,
    required this.pixelSizeMicrons,
    required this.pixelsX,
    required this.pixelsY,
    required this.telescopeName,
    required this.focalLengthMm,
    required this.apertureMm,
    this.focalReducer = 1.0,
  });

  double get effectiveFocalLength => focalLengthMm * focalReducer;

  /// FOV width in degrees
  double get fovWidthDeg {
    final fovRad = 2 * math.atan(sensorWidthMm / (2 * effectiveFocalLength));
    return fovRad * 180 / math.pi;
  }

  /// FOV height in degrees
  double get fovHeightDeg {
    final fovRad = 2 * math.atan(sensorHeightMm / (2 * effectiveFocalLength));
    return fovRad * 180 / math.pi;
  }

  /// Image scale in arcsec/pixel
  double get imageScale {
    final pixelSizeMm = pixelSizeMicrons / 1000;
    return (pixelSizeMm / effectiveFocalLength) * 206265;
  }

  double get focalRatio => effectiveFocalLength / apertureMm;
}

/// Survey image sources
enum SurveySource {
  dss2Red('DSS2 Red', 'DSS2R'),
  dss2Blue('DSS2 Blue', 'DSS2B'),
  dss2IR('DSS2 IR', 'DSS2IR'),
  sdss('SDSS Color', 'SDSSg'),
  twomassJ('2MASS J', '2MASSJ'),
  twomassH('2MASS H', '2MASSH'),
  twomassK('2MASS K', '2MASSK'),
  wise12('WISE 12μm', 'WISE12');

  final String displayName;
  final String surveyCode;

  const SurveySource(this.displayName, this.surveyCode);
}

// =============================================================================
// MOSAIC SUPPORT
// =============================================================================

/// Configuration for a mosaic pattern in the framing assistant.
///
/// Distinct from `MosaicConfig` in `services/mosaic_service.dart`, which
/// describes mosaic geometry in arcminutes/degrees for sequence generation.
/// This UI-facing version is grid-based (columns/rows/overlapPercent).
class FramingMosaicConfig {
  /// Number of horizontal panels
  final int columns;

  /// Number of vertical panels
  final int rows;

  /// Overlap percentage between panels (0-50%)
  final double overlapPercent;

  /// Whether to use a serpentine (snake) capture pattern
  final bool serpentine;

  /// Starting corner for capture sequence
  final MosaicStartCorner startCorner;

  /// Custom panel rotation for each panel (null = use global rotation)
  final double? panelRotation;

  const FramingMosaicConfig({
    this.columns = 2,
    this.rows = 2,
    this.overlapPercent = 15.0,
    this.serpentine = true,
    this.startCorner = MosaicStartCorner.topLeft,
    this.panelRotation,
  });

  FramingMosaicConfig copyWith({
    int? columns,
    int? rows,
    double? overlapPercent,
    bool? serpentine,
    MosaicStartCorner? startCorner,
    double? panelRotation,
  }) {
    return FramingMosaicConfig(
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      overlapPercent: overlapPercent ?? this.overlapPercent,
      serpentine: serpentine ?? this.serpentine,
      startCorner: startCorner ?? this.startCorner,
      panelRotation: panelRotation ?? this.panelRotation,
    );
  }

  /// Total number of panels
  int get totalPanels => columns * rows;

  /// Effective FOV multiplier accounting for overlap
  double get effectiveWidthMultiplier =>
      columns - (columns - 1) * (overlapPercent / 100);
  double get effectiveHeightMultiplier =>
      rows - (rows - 1) * (overlapPercent / 100);
}

/// Starting corner for mosaic capture
enum MosaicStartCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

/// Individual panel in a framing-assistant mosaic.
///
/// Distinct from `MosaicPanel` in `services/mosaic_service.dart`, which is the
/// service-layer geometry representation used by `MosaicService`.
class FramingMosaicPanel {
  /// Panel index (0-based, in capture order)
  final int index;

  /// Grid column (0-based)
  final int column;

  /// Grid row (0-based)
  final int row;

  /// Center RA in hours
  final double centerRaHours;

  /// Center Dec in degrees
  final double centerDecDegrees;

  /// Panel name (e.g., "Panel 1 (0,0)")
  final String name;

  /// Whether this panel has been captured
  final bool isCaptured;

  const FramingMosaicPanel({
    required this.index,
    required this.column,
    required this.row,
    required this.centerRaHours,
    required this.centerDecDegrees,
    required this.name,
    this.isCaptured = false,
  });

  FramingMosaicPanel copyWith({
    int? index,
    int? column,
    int? row,
    double? centerRaHours,
    double? centerDecDegrees,
    String? name,
    bool? isCaptured,
  }) {
    return FramingMosaicPanel(
      index: index ?? this.index,
      column: column ?? this.column,
      row: row ?? this.row,
      centerRaHours: centerRaHours ?? this.centerRaHours,
      centerDecDegrees: centerDecDegrees ?? this.centerDecDegrees,
      name: name ?? this.name,
      isCaptured: isCaptured ?? this.isCaptured,
    );
  }

  /// Format center RA as HH:MM:SS
  String get raFormatted {
    final hours = centerRaHours.floor();
    final minutes = ((centerRaHours - hours) * 60).floor();
    final seconds = (((centerRaHours - hours) * 60 - minutes) * 60).round();
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  /// Format center Dec as ±DD°MM'SS"
  String get decFormatted {
    final sign = centerDecDegrees >= 0 ? '+' : '-';
    final absDec = centerDecDegrees.abs();
    final degrees = absDec.floor();
    final minutes = ((absDec - degrees) * 60).floor();
    final seconds = (((absDec - degrees) * 60 - minutes) * 60).round();
    return '$sign${degrees.toString().padLeft(2, '0')}° ${minutes.toString().padLeft(2, '0')}\' ${seconds.toString().padLeft(2, '0')}"';
  }
}

// =============================================================================
// FRAMING STATE NOTIFIER
// =============================================================================

class FramingNotifier extends StateNotifier<FramingState> {
  final Ref _ref;
  static const _surveyImageTimeout = Duration(seconds: 30);

  /// Pixel width of the survey cutout to request when the canvas size is not
  /// yet known (first load before any layout pass). Once the canvas has been
  /// measured, the request resolution tracks the canvas width (see
  /// [_requestPixelWidthFor]) so the imagery stays crisp on wide displays.
  static const int _defaultRequestPixelWidth = 800;

  /// Hard cap on the requested cutout pixel width. Bounds the network payload
  /// and decode cost even on ultra-wide canvases.
  static const int _maxRequestPixelWidth = 2048;

  /// Fractional canvas-width change required before a resize triggers a
  /// higher-resolution survey re-fetch. A resize that grows the canvas by less
  /// than this is absorbed by the existing cutout (scaled up by the painter)
  /// rather than hammering the survey servers on every drag of the splitter.
  static const double _resizeRefetchGrowthFraction = 0.25;

  /// The canvas width (logical px) the currently-loaded cutout was sized for.
  /// Drives the resize-reload decision in [onCanvasResized]; reset to `null`
  /// whenever the image is cleared so the next load re-establishes it.
  double? _cutoutCanvasWidthPx;

  FramingNotifier(this._ref) : super(const FramingState());

  /// The cutout pixel width to request for a canvas of [canvasWidthLogicalPx]
  /// logical pixels.
  ///
  /// We request roughly one survey pixel per logical canvas pixel (clamped to
  /// [_maxRequestPixelWidth]) so the fit-to-canvas draw does not visibly
  /// upscale the imagery. With no measured canvas yet we fall back to
  /// [_defaultRequestPixelWidth].
  int _requestPixelWidthFor(double? canvasWidthLogicalPx) {
    if (canvasWidthLogicalPx == null || canvasWidthLogicalPx <= 0) {
      return _defaultRequestPixelWidth;
    }
    return canvasWidthLogicalPx
        .ceil()
        .clamp(_defaultRequestPixelWidth, _maxRequestPixelWidth);
  }

  /// React to the framing canvas being resized.
  ///
  /// C9's plate-scale-aware reload: when the canvas grows enough that the
  /// loaded cutout would be upscaled past [_resizeRefetchGrowthFraction], we
  /// re-fetch a higher-resolution cutout sized to the new canvas so the survey
  /// imagery stays sharp. Shrinking the canvas, or a not-yet-loaded image, is a
  /// no-op (the existing cutout already over-covers a smaller canvas).
  void onCanvasResized(ui.Size canvasSize) {
    final width = canvasSize.width;
    if (width <= 0 || state.target == null || state.surveyImage == null) {
      return;
    }
    final last = _cutoutCanvasWidthPx;
    if (last == null) {
      _cutoutCanvasWidthPx = width;
      return;
    }
    if (width <= last * (1.0 + _resizeRefetchGrowthFraction)) {
      // Growth within tolerance (or a shrink): keep the existing cutout.
      return;
    }
    // Avoid re-fetching past the resolution cap — once we are already at the
    // max cutout width, a larger canvas cannot get any sharper.
    if (_requestPixelWidthFor(last) >= _maxRequestPixelWidth &&
        _requestPixelWidthFor(width) >= _maxRequestPixelWidth) {
      _cutoutCanvasWidthPx = width;
      return;
    }
    _cutoutCanvasWidthPx = width;
    loadSurveyImage(canvasWidthLogicalPx: width);
  }

  /// Set the target by coordinates
  void setTargetCoordinates(
    double raHours,
    double decDegrees, {
    String? name,
    bool fromRemoteSync = false,
  }) {
    final targetName = name ?? 'Custom Location';
    final target = FramingTarget(
      name: targetName,
      raHours: raHours,
      decDegrees: decDegrees,
    );
    state = state.copyWith(
      target: target,
      clearImage: true,
      clearSourceSuggestion: true,
    );
    loadSurveyImage();

    if (fromRemoteSync) {
      return;
    }

    final backend = _ref.read(backendProvider);
    if (backend is NetworkBackend) {
      unawaited(_pushTargetToHost(
        backend,
        raHours: raHours,
        decDegrees: decDegrees,
        name: targetName,
      ));
    }
  }

  /// Set the target from a planner/suggestion result while keeping the full
  /// source suggestion around for Smart Night sequence generation.
  void setTargetSuggestion(TargetSuggestion suggestion) {
    final target = FramingTarget(
      name: suggestion.targetName,
      catalogId: suggestion.catalogId,
      raHours: suggestion.raHours,
      decDegrees: suggestion.decDegrees,
      type: _targetTypeFromSuggestion(suggestion.objectType),
      magnitude: suggestion.magnitude,
      sizeArcmin: suggestion.sizeArcmin,
      constellation: suggestion.constellation,
    );
    state = state.copyWith(
      target: target,
      sourceSuggestion: suggestion,
      clearImage: true,
    );
    loadSurveyImage();
  }

  Future<void> _pushTargetToHost(
    NetworkBackend backend, {
    required double raHours,
    required double decDegrees,
    required String name,
  }) async {
    try {
      await backend.framingSetTarget(
        ra: raHours,
        dec: decDegrees,
        name: name,
      );
    } catch (e, stackTrace) {
      developer.log(
        'Failed to push framing target to host: $e',
        name: 'FramingNotifier',
        level: 1000,
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Set the target from a catalog search result
  void setTarget(FramingTarget target) {
    state = state.copyWith(target: target, clearImage: true);
    loadSurveyImage();

    final backend = _ref.read(backendProvider);
    if (backend is NetworkBackend) {
      unawaited(_pushTargetToHost(
        backend,
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        name: target.name,
      ));
    }
  }

  /// Clear the current target
  void clearTarget() {
    state = state.copyWith(clearTarget: true, clearImage: true);
  }

  /// Set the survey source
  void setSurveySource(SurveySource source) {
    state = state.copyWith(surveySource: source, clearImage: true);
    if (state.target != null) {
      loadSurveyImage();
    }
  }

  /// Set frame rotation, normalized to the canonical [-180, 180) domain.
  ///
  /// The on-canvas rotation handle reports angles via `atan2`, which can fall
  /// anywhere in (-180, 180], and a wrapping `% 360` would push values into
  /// (180, 360). The paired rotation `Slider` is declared `min: -180, max: 180`
  /// and asserts `min <= value <= max`, so the rotation domain must agree:
  /// wrap into [-180, 180) here so the gesture and the slider never desync (and
  /// the slider can never be handed an out-of-range value).
  void setRotation(double degrees) {
    var normalized = degrees % 360;
    if (normalized >= 180) {
      normalized -= 360;
    } else if (normalized < -180) {
      normalized += 360;
    }
    state = state.copyWith(rotation: normalized);
  }

  /// Set zoom level
  void setZoom(double zoom) {
    state = state.copyWith(zoom: zoom.clamp(0.25, 4.0));
  }

  /// Zoom in
  void zoomIn() {
    setZoom(state.zoom * 1.25);
  }

  /// Zoom out
  void zoomOut() {
    setZoom(state.zoom / 1.25);
  }

  /// Reset zoom and pan
  void resetView() {
    state = state.copyWith(zoom: 1.0, panX: 0, panY: 0);
  }

  /// Set pan offset
  void setPan(double x, double y) {
    state = state.copyWith(panX: x, panY: y);
  }

  /// Accumulated pan, as a fraction of the survey FOV width, at which the view
  /// has drifted far enough from the fetched cutout's center that we re-fetch a
  /// fresh cutout centered on the new look-direction. Beyond this the existing
  /// survey background no longer covers what the user is looking at.
  static const double _panRefetchFovFraction = 0.35;

  /// Add to the current pan offset (in logical canvas pixels).
  ///
  /// Most pans are a pure display transform. However, once the accumulated pan
  /// has dragged the view center more than [_panRefetchFovFraction] of the
  /// survey FOV away from the fetched cutout's center, the on-screen background
  /// no longer covers the look-direction, so we recompute a new sky center and
  /// re-fetch a cutout there (resetting pan to zero).
  ///
  /// The pan delta is converted to an angular displacement through the loaded
  /// [FramingPlateScale]: `degrees = pan_px / pixelsPerDegree`, exactly as the
  /// painters and gesture math do. [canvasSize] is the logical size of the
  /// framing canvas the pan was measured against — it is required because the
  /// pan deltas are in *drawn* canvas pixels, whose relationship to sky degrees
  /// depends on the canvas geometry and current zoom (a small cached cutout and
  /// a large network cutout fill the canvas at very different native-pixel
  /// densities, so the native image pixel width is *not* a valid substitute).
  void pan(double dx, double dy, {required ui.Size canvasSize}) {
    final newPanX = state.panX + dx;
    final newPanY = state.panY + dy;
    state = state.copyWith(panX: newPanX, panY: newPanY);

    final scale = state.plateScale;
    final target = state.target;
    if (scale == null || target == null) return;

    // Convert the accumulated pan (drawn canvas pixels) to an angular
    // displacement through the plate scale's authoritative on-screen mapping at
    // the current zoom. This is the same px-per-degree the survey painter and
    // FOV reticle use, so the re-fetch threshold tracks what the user actually
    // sees regardless of the cutout's native pixel size.
    final pxPerDeg = scale.pixelsPerDegree(canvasSize, state.zoom);
    if (pxPerDeg <= 0) return;
    final degreesMovedX = newPanX / pxPerDeg;
    final degreesMovedY = newPanY / pxPerDeg;

    final thresholdDeg = scale.surveyFovWidthDeg * _panRefetchFovFraction;
    final movedDeg =
        math.sqrt(degreesMovedX * degreesMovedX + degreesMovedY * degreesMovedY);
    if (movedDeg <= thresholdDeg) return;

    // The view has drifted past the margin: recompute a new sky center using a
    // real spherical offset (RA scaled by 1/cos(dec)), mirroring the mosaic
    // panel math, then re-fetch a cutout there and reset the pan.
    _recenterFromPan(
      target: target,
      raDisplacementDeg: degreesMovedX,
      decDisplacementDeg: degreesMovedY,
    );
  }

  /// Recompute the target center after a pan past the re-fetch margin and load
  /// a fresh survey cutout there.
  ///
  /// Screen convention: dragging the background to the right (+pan x) reveals
  /// sky to the *west*, so the look-direction RA decreases; dragging down
  /// (+pan y) reveals sky to the *north*, so the look-direction Dec increases.
  /// RA offset is divided by cos(dec) so a fixed on-screen pan corresponds to a
  /// smaller absolute RA step near the celestial poles — the same cos(dec)
  /// scaling used by [_recalculateMosaicPanels].
  void _recenterFromPan({
    required FramingTarget target,
    required double raDisplacementDeg,
    required double decDisplacementDeg,
  }) {
    final decRad = target.decDegrees * math.pi / 180;
    final cosDec = math.cos(decRad);
    final safeCosDec = cosDec.abs() > 0.01 ? cosDec : (cosDec.isNegative ? -0.01 : 0.01);

    final raOffsetHours = (-raDisplacementDeg / 15.0) / safeCosDec;
    final decOffsetDeg = decDisplacementDeg;

    var newRaHours = (target.raHours + raOffsetHours) % 24.0;
    if (newRaHours < 0) newRaHours += 24.0;
    final newDecDegrees = (target.decDegrees + decOffsetDeg).clamp(-90.0, 90.0);

    final recentered = FramingTarget(
      name: target.name,
      catalogId: target.catalogId,
      raHours: newRaHours,
      decDegrees: newDecDegrees,
      type: target.type,
      magnitude: target.magnitude,
      sizeArcmin: target.sizeArcmin,
      constellation: target.constellation,
    );

    state = state.copyWith(
      target: recentered,
      panX: 0,
      panY: 0,
      clearImage: true,
    );
    loadSurveyImage();
  }

  /// Toggle grid display
  void toggleGrid() {
    state = state.copyWith(showGrid: !state.showGrid);
  }

  /// Toggle labels display
  void toggleLabels() {
    state = state.copyWith(showLabels: !state.showLabels);
  }

  /// Toggle cardinal directions
  void toggleCardinalDirections() {
    state =
        state.copyWith(showCardinalDirections: !state.showCardinalDirections);
  }

  /// Toggle optical config panel visibility
  void toggleOpticalConfigPanel() {
    state =
        state.copyWith(showOpticalConfigPanel: !state.showOpticalConfigPanel);
  }

  /// Set optical config panel visibility
  void setOpticalConfigPanelVisible(bool visible) {
    state = state.copyWith(showOpticalConfigPanel: visible);
  }

  /// Set custom equipment
  void setCustomEquipment(FramingEquipment equipment) {
    state =
        state.copyWith(customEquipment: equipment, useCustomEquipment: true);
  }

  /// Use equipment from active profile
  void useProfileEquipment() {
    state = state.copyWith(useCustomEquipment: false);
  }

  /// Set preview FOV for browsing without equipment
  void setPreviewFov(double degrees) {
    state = state.copyWith(
        previewFovDegrees: degrees.clamp(0.1, 20.0), clearImage: true);
    if (state.target != null) {
      loadSurveyImage();
    }
  }

  /// Set equipment FOV overlay opacity
  void setEquipmentFovOverlayOpacity(double opacity) {
    state = state.copyWith(equipmentFovOverlayOpacity: opacity.clamp(0.0, 1.0));
  }

  /// Toggle equipment FOV overlay visibility
  void toggleEquipmentFovOverlay() {
    state =
        state.copyWith(showEquipmentFovOverlay: !state.showEquipmentFovOverlay);
  }

  /// Load survey image, preferring an offline cache, then network.
  ///
  /// Order of operations (offline-first):
  ///  1. Compute the angular FOV to request for the current target/equipment.
  ///  2. Probe the on-disk framing cache. A cached snapshot is served only when
  ///     both the image file *and* the FOV companion sidecar (written by a
  ///     previous successful fetch — see [_fovSidecarPath]) are present. Without
  ///     a stored FOV we cannot reconstruct the [FramingPlateScale] registration
  ///     linkage, so the entry is treated as a miss and we fetch over the
  ///     network instead (never a silent, scale-less fallback).
  ///  3. Fetch from Aladin HiPS2FITS, falling back to NASA SkyView.
  ///
  /// On any successful load the decoded image is paired with the requested FOV
  /// into a [FramingPlateScale] — the single source of truth the framing
  /// painters and gesture handlers project through. If both the cache and both
  /// network endpoints fail the existing surfaced [FramingState.imageError] is
  /// preserved (errors are a feature; no silent fallback).
  /// Load the survey cutout for the current target.
  ///
  /// [canvasWidthLogicalPx], when supplied, sizes the requested cutout's pixel
  /// resolution to the canvas so wide displays get sharp imagery (see
  /// [_requestPixelWidthFor]); when omitted the last-known canvas width — or the
  /// default — is used. The angular field of view is independent of this and is
  /// resolved from the target + equipment via [_computeRequestFov].
  Future<void> loadSurveyImage({double? canvasWidthLogicalPx}) async {
    if (state.target == null) return;

    state = state.copyWith(isLoadingImage: true, imageError: null);

    final target = state.target!;
    final source = state.surveySource;
    final effectiveCanvasWidth = canvasWidthLogicalPx ?? _cutoutCanvasWidthPx;
    if (effectiveCanvasWidth != null && effectiveCanvasWidth > 0) {
      _cutoutCanvasWidthPx = effectiveCanvasWidth;
    }
    final requestPixelWidth = _requestPixelWidthFor(effectiveCanvasWidth);

    try {
      final (requestWidth, requestHeight) = await _computeRequestFov();

      // ---- OFFLINE-FIRST: serve a pinned cache entry when available. --------
      final served = await _tryServeFromCache(
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        source: source,
      );
      if (served) return;

      // ---- NETWORK: Aladin HiPS2FITS primary, NASA SkyView fallback. -------
      final url = _buildAladinUrl(
        target.raDegrees,
        target.decDegrees,
        requestWidth,
        requestHeight,
        source,
        requestPixelWidth,
      );

      final client = http.Client();
      try {
        http.Response? response;
        try {
          response = await client.get(Uri.parse(url)).timeout(
                _surveyImageTimeout,
                onTimeout: () => throw TimeoutException(
                  'Aladin survey image fetch timed out',
                  _surveyImageTimeout,
                ),
              );
        } catch (e) {
          developer.log(
            'FramingProvider: Aladin survey fetch failed, trying SkyView: $e',
            name: 'FramingProvider',
            level: 900,
            error: e,
          );
        }

        if (response != null && response.statusCode == 200) {
          await _applyFetchedImage(
            bytes: response.bodyBytes,
            raHours: target.raHours,
            decDegrees: target.decDegrees,
            source: source,
            requestWidth: requestWidth,
            requestHeight: requestHeight,
          );
        } else {
          // Fallback to SkyView
          final skyViewUrl = _buildSkyViewUrl(
            target.raDegrees,
            target.decDegrees,
            requestWidth,
            requestHeight,
            source,
            requestPixelWidth,
          );

          final skyViewResponse =
              await client.get(Uri.parse(skyViewUrl)).timeout(
                    _surveyImageTimeout,
                    onTimeout: () => throw TimeoutException(
                      'SkyView survey image fetch timed out',
                      _surveyImageTimeout,
                    ),
                  );

          if (skyViewResponse.statusCode == 200) {
            await _applyFetchedImage(
              bytes: skyViewResponse.bodyBytes,
              raHours: target.raHours,
              decDegrees: target.decDegrees,
              source: source,
              requestWidth: requestWidth,
              requestHeight: requestHeight,
            );
          } else {
            if (!mounted) return;
            state = state.copyWith(
              isLoadingImage: false,
              imageError: 'Failed to load survey image',
            );
          }
        }
      } finally {
        client.close();
      }
    } on TimeoutException catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingImage: false,
        imageError: 'Survey image fetch timed out - retry?',
      );
      developer.log(
        'FramingProvider: ${e.message}',
        name: 'FramingProvider',
        level: 900,
        error: e,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingImage: false,
        imageError: 'Error: ${e.toString()}',
      );
    }
  }

  /// Resolve the angular field of view (width, height) in degrees to request
  /// for the current target and equipment configuration.
  Future<(double, double)> _computeRequestFov() async {
    final equipmentFov = await _getCurrentFOV();
    final previewFov = state.previewFovDegrees;

    if (equipmentFov != null) {
      final equipmentWidth = equipmentFov.$1;
      final equipmentHeight = equipmentFov.$2;

      if (previewFov > equipmentWidth) {
        // User wants to see more context - use preview FOV.
        return (previewFov, previewFov * (equipmentHeight / equipmentWidth));
      }
      // Use equipment FOV with 2.5x context.
      return (equipmentWidth * 2.5, equipmentHeight * 2.5);
    }

    // No equipment - use preview FOV at the default 4:3 aspect.
    return (previewFov, previewFov * 0.75);
  }

  /// Decode [bytes], publish the image plus its [FramingPlateScale], and record
  /// the requested FOV alongside any pinned cache entry so a future offline load
  /// can reconstruct the same registration linkage.
  Future<void> _applyFetchedImage({
    required Uint8List bytes,
    required double raHours,
    required double decDegrees,
    required SurveySource source,
    required double requestWidth,
    required double requestHeight,
  }) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    final image = await completer.future;

    // Persist the request FOV into the cache metadata sidecar (when a pinned
    // snapshot exists) so offline-first can rebuild the plate scale without a
    // network round-trip.
    await _recordRequestFov(
      raHours: raHours,
      decDegrees: decDegrees,
      source: source,
      fovWidthDeg: requestWidth,
      fovHeightDeg: requestHeight,
    );

    if (!mounted) return;
    state = state.copyWith(
      surveyImageBytes: bytes,
      surveyImage: image,
      plateScale: FramingPlateScale(
        surveyFovWidthDeg: requestWidth,
        surveyFovHeightDeg: requestHeight,
        imagePixelWidth: image.width,
        imagePixelHeight: image.height,
      ),
      isLoadingImage: false,
    );
  }

  /// Attempt to serve a pinned survey snapshot from the on-disk cache.
  ///
  /// Returns `true` (and updates state with the decoded image + plate scale)
  /// only when both the cached image file and its FOV companion sidecar exist.
  /// A miss — including the case where the sidecar is absent and the recorded
  /// FOV cannot be recovered — returns `false` so the caller falls through to
  /// the network. Any IO/decode error is surfaced via [developer.log] and also
  /// returns `false` rather than masking a real fetch failure.
  Future<bool> _tryServeFromCache({
    required double raHours,
    required double decDegrees,
    required SurveySource source,
  }) async {
    try {
      // Probe the cache through the single offline-first read API so the
      // notifier, the family provider's consumers, and any test override all
      // share one read path (and one overridable cache-dir configuration).
      // `refresh` (not `read`) forces a fresh disk probe so a snapshot pinned
      // since the last load is seen rather than a memoized miss.
      final file = await _ref.refresh(
        cachedSurveyImageFileProvider((
          raHours: raHours,
          decDegrees: decDegrees,
          source: source,
        )).future,
      );
      if (file == null) return false;

      final fov = await _readRequestFov(
        raHours: raHours,
        decDegrees: decDegrees,
        source: source,
      );
      if (fov == null) {
        // Image is cached but the meta sidecar carries no stored FOV: rebuilding
        // the registration linkage would be guesswork, so treat as a miss and
        // refetch (which will then record the FOV into the sidecar).
        return false;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return false;

      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      final image = await completer.future;

      if (!mounted) return true;
      state = state.copyWith(
        surveyImageBytes: bytes,
        surveyImage: image,
        plateScale: FramingPlateScale(
          surveyFovWidthDeg: fov.$1,
          surveyFovHeightDeg: fov.$2,
          imagePixelWidth: image.width,
          imagePixelHeight: image.height,
        ),
        isLoadingImage: false,
      );
      return true;
    } catch (e, stack) {
      developer.log(
        'FramingProvider: offline cache read failed; falling back to network: $e',
        name: 'FramingProvider',
        level: 900,
        error: e,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// Absolute path of the cache metadata sidecar for a survey snapshot.
  ///
  /// This mirrors the framing cache service's own convention
  /// (`<imagePath>.meta.json`) so the FOV is stored *inside the meta already
  /// written* by [FramingImageCacheService.saveSurveyImage] rather than in a
  /// separate file. Reusing the same sidecar means `listCachedImages` (which
  /// already filters `.meta.json`) does not surface a phantom cache entry.
  Future<String> _metaSidecarPath({
    required double raHours,
    required double decDegrees,
    required SurveySource source,
  }) async {
    final cache = _ref.read(framingImageCacheServiceProvider);
    final imagePath = await cache.resolvePath(
      raHours: raHours,
      decDegrees: decDegrees,
      source: source,
    );
    return '$imagePath.meta.json';
  }

  /// Record the requested FOV into the cache metadata sidecar so a later offline
  /// load can rebuild the plate scale.
  ///
  /// Read-modify-write: it only augments a sidecar the cache service already
  /// wrote (i.e. an image the user pinned). When no sidecar exists there is no
  /// pinned image to register against, so there is nothing to record and the
  /// method is a no-op. Best-effort: a write failure is logged (errors are a
  /// feature) but never fails the network load — the in-memory image is good.
  Future<void> _recordRequestFov({
    required double raHours,
    required double decDegrees,
    required SurveySource source,
    required double fovWidthDeg,
    required double fovHeightDeg,
  }) async {
    try {
      final path = await _metaSidecarPath(
        raHours: raHours,
        decDegrees: decDegrees,
        source: source,
      );
      final file = File(path);
      if (!await file.exists()) {
        // No pinned snapshot to register against; nothing to record.
        return;
      }
      final decoded = jsonDecode(await file.readAsString());
      final meta = decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
      meta['fovWidthDeg'] = fovWidthDeg;
      meta['fovHeightDeg'] = fovHeightDeg;
      await file.writeAsString(jsonEncode(meta), flush: true);
    } catch (e, stack) {
      developer.log(
        'FramingProvider: failed to record request FOV in cache metadata: $e',
        name: 'FramingProvider',
        level: 900,
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Read back the requested FOV recorded by [_recordRequestFov] from the cache
  /// metadata sidecar, or `null` when no sidecar exists or it lacks a valid FOV.
  Future<(double, double)?> _readRequestFov({
    required double raHours,
    required double decDegrees,
    required SurveySource source,
  }) async {
    final path = await _metaSidecarPath(
      raHours: raHours,
      decDegrees: decDegrees,
      source: source,
    );
    final file = File(path);
    if (!await file.exists()) return null;

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    final width = (decoded['fovWidthDeg'] as num?)?.toDouble();
    final height = (decoded['fovHeightDeg'] as num?)?.toDouble();
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return (width, height);
  }

  String _buildAladinUrl(
    double raDeg,
    double decDeg,
    double widthDeg,
    double heightDeg,
    SurveySource source,
    int pixelWidth,
  ) {
    final hipsId = _getHipsId(source);
    final pixelHeight = (pixelWidth * heightDeg / widthDeg).round();
    return 'https://alasky.cds.unistra.fr/hips-image-services/hips2fits'
        '?hips=$hipsId'
        '&ra=$raDeg'
        '&dec=$decDeg'
        '&fov=${widthDeg.toStringAsFixed(4)}'
        '&width=$pixelWidth'
        '&height=$pixelHeight'
        '&format=jpg';
  }

  String _buildSkyViewUrl(
    double raDeg,
    double decDeg,
    double widthDeg,
    double heightDeg,
    SurveySource source,
    int pixelWidth,
  ) {
    final surveyId = _getSkyViewSurvey(source);
    final pixelHeight = (pixelWidth * heightDeg / widthDeg).round();
    return 'https://skyview.gsfc.nasa.gov/current/cgi/runquery.pl'
        '?Position=$raDeg,$decDeg'
        '&Survey=$surveyId'
        '&Pixels=$pixelWidth,$pixelHeight'
        '&Size=${widthDeg.toStringAsFixed(4)},${heightDeg.toStringAsFixed(4)}'
        '&Return=JPEG'
        '&Projection=Tan'
        '&Coordinates=J2000';
  }

  String _getHipsId(SurveySource source) {
    switch (source) {
      case SurveySource.dss2Red:
        return 'CDS/P/DSS2/red';
      case SurveySource.dss2Blue:
        return 'CDS/P/DSS2/blue';
      case SurveySource.dss2IR:
        return 'CDS/P/DSS2/NIR';
      case SurveySource.sdss:
        return 'CDS/P/SDSS9/color';
      case SurveySource.twomassJ:
        return 'CDS/P/2MASS/J';
      case SurveySource.twomassH:
        return 'CDS/P/2MASS/H';
      case SurveySource.twomassK:
        return 'CDS/P/2MASS/K';
      case SurveySource.wise12:
        return 'CDS/P/WISE/W3';
    }
  }

  String _getSkyViewSurvey(SurveySource source) {
    switch (source) {
      case SurveySource.dss2Red:
        return 'DSS2R';
      case SurveySource.dss2Blue:
        return 'DSS2B';
      case SurveySource.dss2IR:
        return 'DSS2IR';
      case SurveySource.sdss:
        return 'SDSSg';
      case SurveySource.twomassJ:
        return '2MASSJ';
      case SurveySource.twomassH:
        return '2MASSH';
      case SurveySource.twomassK:
        return '2MASSK';
      case SurveySource.wise12:
        return 'WISE 12';
    }
  }

  Future<(double, double)?> _getCurrentFOV() async {
    if (state.useCustomEquipment && state.customEquipment != null) {
      return (
        state.customEquipment!.fovWidthDeg,
        state.customEquipment!.fovHeightDeg
      );
    }

    // Delegate profile FOV math to the canonical OpticalConfig.fieldOfView,
    // which derives sensor dimensions from the active profile + connected
    // camera capabilities. This replaces the hand-rolled Taylor-series atan
    // approximation and keeps a single source of truth for FOV across the app.
    try {
      final optical = _ref.read(opticalConfigProvider);
      if (optical == null) {
        return null;
      }
      final fov = optical.fieldOfView;
      if (fov == null) {
        developer.log(
          'Cannot compute profile FOV: optical config lacks focal length or '
          'camera sensor specs (focalLength=${optical.focalLength}, '
          'sensorWidth=${optical.sensorWidth}, sensorHeight=${optical.sensorHeight}, '
          'pixelSize=${optical.pixelSize}).',
          name: 'Framing',
          level: 900,
        );
        return null;
      }
      return fov;
    } catch (error, stack) {
      developer.log(
        'Failed to compute framing FOV from active profile.',
        name: 'Framing',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
    }

    return null;
  }

  // ===========================================================================
  // MOSAIC METHODS
  // ===========================================================================

  /// Enable or disable mosaic mode
  void setMosaicEnabled(bool enabled) {
    state = state.copyWith(mosaicEnabled: enabled);
    if (enabled) {
      _recalculateMosaicPanels();
    } else {
      state = state.copyWith(mosaicPanels: [], selectedPanelIndex: -1);
    }
  }

  /// Update mosaic configuration
  void setMosaicConfig(FramingMosaicConfig config) {
    state = state.copyWith(mosaicConfig: config);
    if (state.mosaicEnabled) {
      _recalculateMosaicPanels();
    }
  }

  /// Set number of mosaic columns
  void setMosaicColumns(int columns) {
    setMosaicConfig(state.mosaicConfig.copyWith(columns: columns.clamp(1, 10)));
  }

  /// Set number of mosaic rows
  void setMosaicRows(int rows) {
    setMosaicConfig(state.mosaicConfig.copyWith(rows: rows.clamp(1, 10)));
  }

  /// Set mosaic overlap percentage
  void setMosaicOverlap(double percent) {
    setMosaicConfig(
        state.mosaicConfig.copyWith(overlapPercent: percent.clamp(0, 50)));
  }

  /// Toggle serpentine capture pattern
  void toggleSerpentine() {
    setMosaicConfig(state.mosaicConfig
        .copyWith(serpentine: !state.mosaicConfig.serpentine));
  }

  /// Set mosaic start corner
  void setMosaicStartCorner(MosaicStartCorner corner) {
    setMosaicConfig(state.mosaicConfig.copyWith(startCorner: corner));
  }

  /// Select a panel by index
  void selectPanel(int index) {
    state = state.copyWith(selectedPanelIndex: index);
  }

  /// Toggle panel number visibility
  void togglePanelNumbers() {
    state = state.copyWith(showPanelNumbers: !state.showPanelNumbers);
  }

  /// Toggle sequence path visibility
  void toggleSequencePath() {
    state = state.copyWith(showSequencePath: !state.showSequencePath);
  }

  /// Recalculate mosaic panels based on current target and equipment FOV
  Future<void> _recalculateMosaicPanels() async {
    if (state.target == null) {
      state = state.copyWith(mosaicPanels: []);
      return;
    }

    final fov = await _getCurrentFOV();
    if (fov == null) {
      state = state.copyWith(mosaicPanels: []);
      return;
    }

    final (fovWidth, fovHeight) = fov;
    final config = state.mosaicConfig;

    // Calculate step size accounting for overlap
    final overlapFactor = 1 - (config.overlapPercent / 100);
    final stepWidthDeg = fovWidth * overlapFactor;
    final stepHeightDeg = fovHeight * overlapFactor;

    // Calculate the total extent of the mosaic
    final totalWidthDeg = fovWidth + (config.columns - 1) * stepWidthDeg;
    final totalHeightDeg = fovHeight + (config.rows - 1) * stepHeightDeg;

    // Center coordinates
    final centerRa = state.target!.raHours;
    final centerDec = state.target!.decDegrees;

    // Calculate starting corner offset from center
    final startRaOffset = -totalWidthDeg / 2 + fovWidth / 2;
    final startDecOffset = totalHeightDeg / 2 - fovHeight / 2;

    // Generate panels in capture order
    final panels = <FramingMosaicPanel>[];
    int panelIndex = 0;

    for (int row = 0; row < config.rows; row++) {
      final actualRow = _getActualRow(row, config);

      for (int col = 0; col < config.columns; col++) {
        final actualCol = _getActualCol(col, row, config);

        // Calculate panel center RA/Dec
        // Note: RA offset needs to account for declination (cos(dec) factor)
        final decRad = centerDec * math.pi / 180;
        final cosDec = math.cos(decRad);
        final raOffsetHours = (startRaOffset + actualCol * stepWidthDeg) /
            15 /
            (cosDec.abs() > 0.01 ? cosDec : 0.01);
        final decOffsetDeg = startDecOffset - actualRow * stepHeightDeg;

        final panelRa = (centerRa + raOffsetHours) % 24;
        final panelDec = (centerDec + decOffsetDeg).clamp(-90.0, 90.0);

        panels.add(FramingMosaicPanel(
          index: panelIndex,
          column: actualCol,
          row: actualRow,
          centerRaHours: panelRa,
          centerDecDegrees: panelDec,
          name: 'Panel ${panelIndex + 1} ($actualCol,$actualRow)',
        ));

        panelIndex++;
      }
    }

    state = state.copyWith(mosaicPanels: panels);
  }

  int _getActualRow(int row, FramingMosaicConfig config) {
    final flipVertical = config.startCorner == MosaicStartCorner.bottomLeft ||
        config.startCorner == MosaicStartCorner.bottomRight;
    return flipVertical ? (config.rows - 1 - row) : row;
  }

  int _getActualCol(int col, int row, FramingMosaicConfig config) {
    final flipHorizontal = config.startCorner == MosaicStartCorner.topRight ||
        config.startCorner == MosaicStartCorner.bottomRight;
    final baseCol = flipHorizontal ? (config.columns - 1 - col) : col;

    // Apply serpentine pattern (reverse direction on odd rows)
    if (config.serpentine && row % 2 == 1) {
      return config.columns - 1 - baseCol;
    }
    return baseCol;
  }

  /// Recalculate panels when target or equipment changes
  void recalculateMosaicIfNeeded() {
    if (state.mosaicEnabled) {
      _recalculateMosaicPanels();
    }
  }

  /// Get mosaic total coverage info
  (double widthDeg, double heightDeg) getMosaicCoverage() {
    final config = state.mosaicConfig;
    final baseWidthDeg =
        state.customEquipment?.fovWidthDeg ?? state.previewFovDegrees;
    final baseHeightDeg = state.customEquipment?.fovHeightDeg ??
        (state.surveyImage != null && state.surveyImage!.width > 0
            ? state.previewFovDegrees *
                (state.surveyImage!.height / state.surveyImage!.width)
            : state.previewFovDegrees);
    return (
      config.effectiveWidthMultiplier * baseWidthDeg,
      config.effectiveHeightMultiplier * baseHeightDeg,
    );
  }

  /// Save target to database
  Future<void> saveTarget() async {
    if (state.target == null) return;

    final target = state.target!;
    final backend = _ref.read(backendProvider);
    if (backend is NetworkBackend) {
      await backend.createTarget({
        'name': target.name,
        if (target.catalogId != null) 'catalogId': target.catalogId,
        'ra': target.raHours,
        'dec': target.decDegrees,
        'objectType': target.type?.name ?? 'other',
        if (target.magnitude != null) 'magnitude': target.magnitude,
        if (target.sizeArcmin != null) 'sizeArcmin': target.sizeArcmin,
        if (target.constellation != null) 'constellation': target.constellation,
      });
      return;
    }

    final targetsDao = _ref.read(targetsDaoProvider);

    await targetsDao.createTarget(TargetsCompanion.insert(
      name: target.name,
      catalogId: Value(target.catalogId),
      ra: target.raHours,
      dec: target.decDegrees,
      objectType: Value(target.type?.name ?? 'other'),
      magnitude: Value(target.magnitude),
      sizeArcmin: Value(target.sizeArcmin),
      constellation: Value(target.constellation),
    ));
  }

  /// Load the most recent target from database (if any)
  Future<void> loadMostRecentTarget() async {
    final backend = _ref.read(backendProvider);
    final List<Target> allTargets;
    if (backend is NetworkBackend) {
      final remoteTargets = await backend.getAllTargets();
      allTargets = remoteTargets.map((json) {
        return Target(
          id: json['id'] as int,
          name: json['name'] as String? ?? 'Untitled target',
          catalogId: json['catalogId'] as String?,
          objectType: json['objectType'] as String?,
          ra: (json['ra'] as num?)?.toDouble() ?? 0.0,
          dec: (json['dec'] as num?)?.toDouble() ?? 0.0,
          positionAngle: (json['positionAngle'] as num?)?.toDouble(),
          magnitude: (json['magnitude'] as num?)?.toDouble(),
          constellation: json['constellation'] as String?,
          sizeArcmin: (json['sizeArcmin'] as num?)?.toDouble(),
          minAltitude: (json['minAltitude'] as num?)?.toDouble() ?? 30.0,
          priority: json['priority'] as int? ?? 5,
          totalPlannedSubs: json['totalPlannedSubs'] as int? ?? 0,
          capturedSubs: json['capturedSubs'] as int? ?? 0,
          totalIntegrationSecs:
              (json['totalIntegrationSecs'] as num?)?.toDouble() ?? 0.0,
          goalIntegrationSecs:
              (json['goalIntegrationSecs'] as num?)?.toDouble() ?? 0.0,
          filterProgress: json['filterProgress'] as String?,
          notes: json['notes'] as String?,
          createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
          isFavorite: json['isFavorite'] as bool? ?? false,
        );
      }).toList();
    } else {
      final targetsDao = _ref.read(targetsDaoProvider);
      allTargets = await targetsDao.getAllTargets();
    }

    if (allTargets.isEmpty) return;

    // Sort by updatedAt descending to get the most recent
    allTargets.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final mostRecent = allTargets.first;

    // Convert database target to FramingTarget
    final target = FramingTarget(
      name: mostRecent.name,
      catalogId: mostRecent.catalogId,
      // Backward-compatibility: older DB entries may have stored RA in degrees, not hours.
      raHours: _normalizeRaHoursMaybeDegrees(mostRecent.ra),
      decDegrees: mostRecent.dec,
      type: mostRecent.objectType != null
          ? TargetType.values.firstWhere(
              (t) => t.name == mostRecent.objectType,
              orElse: () => TargetType.other,
            )
          : null,
      magnitude: mostRecent.magnitude,
      sizeArcmin: mostRecent.sizeArcmin,
      constellation: mostRecent.constellation,
    );

    setTarget(target);
  }
}

final framingProvider =
    StateNotifierProvider<FramingNotifier, FramingState>((ref) {
  return FramingNotifier(ref);
});

double _normalizeRaHoursMaybeDegrees(double ra) {
  if (ra.isNaN || ra.isInfinite) return ra;

  // Normal case: already in hours.
  if (ra >= 0.0 && ra < 24.0) return ra;

  // Legacy bug / external sources: treat as degrees and convert to hours.
  var deg = ra % 360.0;
  if (deg < 0.0) deg += 360.0;
  return deg / 15.0;
}

// =============================================================================
// COMPUTED FOV PROVIDER
// =============================================================================

/// Equipment status for framing
enum EquipmentStatus {
  /// No equipment profile configured
  noProfile,

  /// Profile exists but no focal length configured
  noFocalLength,

  /// Profile exists but camera sensor specs not configured
  noCameraSpecs,

  /// Equipment is properly configured
  ready,
}

/// Result of checking equipment for framing
class FramingEquipmentResult {
  final EquipmentStatus status;
  final FramingEquipment? equipment;
  final String? profileName;
  final String? message;

  const FramingEquipmentResult({
    required this.status,
    this.equipment,
    this.profileName,
    this.message,
  });

  bool get isReady => status == EquipmentStatus.ready && equipment != null;
}

/// Provides calculated FOV from current equipment profile or custom settings
final framingFOVProvider = FutureProvider<FramingEquipmentResult>((ref) async {
  final framingState = ref.watch(framingProvider);

  // If using custom equipment, return it directly
  if (framingState.useCustomEquipment && framingState.customEquipment != null) {
    return FramingEquipmentResult(
      status: EquipmentStatus.ready,
      equipment: framingState.customEquipment,
      profileName: 'Custom Equipment',
    );
  }

  // Get from active profile (host-authoritative when paired).
  final profile = ref.watch(activeEquipmentProfileProvider);

  // Check if profile exists
  if (profile == null) {
    return const FramingEquipmentResult(
      status: EquipmentStatus.noProfile,
      message:
          'No equipment profile selected. Create and activate a profile in Settings → Equipment to enable framing.',
    );
  }

  // Check if focal length is configured
  if (profile.focalLength <= 0) {
    return FramingEquipmentResult(
      status: EquipmentStatus.noFocalLength,
      profileName: profile.name,
      message:
          'Optical specs not configured. Set the focal length in your equipment profile "${profile.name}" to enable FOV preview.',
    );
  }

  // Profile has basic optical data - we can calculate FOV
  // Check camera state early so we can use the friendly device name
  final cameraState = ref.watch(cameraStateProvider);

  // Use friendly name from profile first, then connected camera's device name,
  // then fall back to device ID extraction
  final cameraName = profile.cameraName ??
      (cameraState.connectionState == DeviceConnectionState.connected &&
              cameraState.deviceName != null
          ? cameraState.deviceName!
          : (profile.cameraId != null
              ? _extractDeviceName(profile.cameraId!)
              : 'Unknown Camera'));

  final telescopeName = profile.telescopeName ?? profile.name;

  // Require real camera sensor specs; do not approximate with guessed defaults.
  double? sensorWidthMm;
  double? sensorHeightMm;
  double? pixelSizeMicrons;
  int? pixelsX;
  int? pixelsY;
  String? cameraMessage;
  if (profile.cameraId != null &&
      cameraState.connectionState == DeviceConnectionState.connected) {
    try {
      // Query camera status via backend (works with both local and remote)
      final backend = ref.watch(backendProvider);
      final status = await backend.getCameraStatus(profile.cameraId!);

      // Use actual sensor dimensions from connected camera
      // Now returns typed CameraStatus from all backends
      if (status.sensorWidth > 0 && status.sensorHeight > 0) {
        pixelsX = status.sensorWidth;
        pixelsY = status.sensorHeight;
        pixelSizeMicrons = status.pixelSizeX;

        // Calculate sensor physical size from pixel count and pixel size
        sensorWidthMm = (pixelsX * pixelSizeMicrons) / 1000;
        sensorHeightMm = (pixelsY * status.pixelSizeY) / 1000;

        cameraMessage = null; // No message needed - using real data
      } else {
        cameraMessage =
            'Camera is connected but did not report valid sensor dimensions.';
      }
    } catch (e) {
      cameraMessage = 'Could not query camera specs: $e';
    }
  } else if (profile.cameraId == null) {
    cameraMessage =
        'Camera is not configured for this profile. Configure and connect a camera to enable FOV.';
  } else {
    cameraMessage = 'Camera is not connected. Connect it to compute FOV.';
  }

  if (sensorWidthMm == null ||
      sensorHeightMm == null ||
      pixelSizeMicrons == null ||
      pixelsX == null ||
      pixelsY == null) {
    return FramingEquipmentResult(
      status: EquipmentStatus.noCameraSpecs,
      profileName: profile.name,
      message: cameraMessage ??
          'Camera sensor dimensions are unavailable. Connect camera hardware to compute FOV.',
    );
  }

  return FramingEquipmentResult(
    status: EquipmentStatus.ready,
    profileName: profile.name,
    equipment: FramingEquipment(
      cameraName: cameraName,
      sensorWidthMm: sensorWidthMm,
      sensorHeightMm: sensorHeightMm,
      pixelSizeMicrons: pixelSizeMicrons,
      pixelsX: pixelsX,
      pixelsY: pixelsY,
      telescopeName: telescopeName,
      focalLengthMm: profile.focalLength,
      apertureMm:
          profile.aperture > 0 ? profile.aperture : profile.focalLength / 8,
    ),
    message: cameraMessage,
  );
});

/// Extract a human-readable device name from a raw device identifier.
///
/// Handles several formats:
/// - ASCOM IDs: "ASCOM.Simulator.Camera" -> "Camera"
/// - Native IDs: "zwo:native:0" -> "ZWO #0"
/// - Plain names are returned as-is.
String _extractDeviceName(String deviceId) {
  // ASCOM IDs are typically like "ASCOM.Simulator.Camera" or just a name
  if (deviceId.contains('.')) {
    final parts = deviceId.split('.');
    return parts.length > 1 ? parts.last : deviceId;
  }
  // Native driver IDs use colon separator: "vendor:driver:index"
  if (deviceId.contains(':')) {
    final parts = deviceId.split(':');
    if (parts.length >= 3) {
      final vendor = parts[0].toUpperCase();
      final index = parts[2];
      return '$vendor #$index';
    }
    // Fallback for 2-part colon IDs
    return parts[0].toUpperCase();
  }
  return deviceId;
}

// =============================================================================
// SIMBAD NAME RESOLVER
// =============================================================================

/// Resolved object from SIMBAD
class SimbadResult {
  final String mainId;
  final double raHours;
  final double decDegrees;
  final String objectType;
  final double? magnitude;
  final List<String> aliases;

  const SimbadResult({
    required this.mainId,
    required this.raHours,
    required this.decDegrees,
    required this.objectType,
    this.magnitude,
    this.aliases = const [],
  });
}

/// Resolves object names via SIMBAD API
class SimbadResolver {
  static const _baseUrl = 'https://simbad.cds.unistra.fr/simbad/sim-id';

  /// Resolve an object name to coordinates
  static Future<SimbadResult?> resolve(String name) async {
    try {
      final url = '$_baseUrl?Ident=${Uri.encodeComponent(name)}'
          '&output.format=votable'
          '&output.params=main_id,ra,dec,otype,flux(V)';

      final client = http.Client();
      try {
        final response = await client.get(Uri.parse(url));

        if (response.statusCode != 200) return null;

        // Parse the simple VOTable response
        final body = response.body;

        // Extract RA and Dec from response
        final raMatch = RegExp(r'<TD>(\d+\.\d+)</TD>').firstMatch(body);
        final decMatch = RegExp(
          r'<TD>([+-]?\d+\.\d+)</TD>',
          caseSensitive: false,
        ).firstMatch(body);

        if (raMatch == null || decMatch == null) {
          // Try TAP query instead
          return await _resolveTAP(name);
        }

        final raDeg = double.parse(raMatch.group(1)!);
        final decDeg = double.parse(decMatch.group(1)!);

        return SimbadResult(
          mainId: name,
          raHours: raDeg / 15,
          decDegrees: decDeg,
          objectType: 'Unknown',
        );
      } finally {
        client.close();
      }
    } catch (error, stack) {
      developer.log(
        'SIMBAD primary resolver failed for "$name"; trying TAP fallback.',
        name: 'Framing',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
      return _resolveTAP(name);
    }
  }

  /// Alternative TAP query resolution
  static Future<SimbadResult?> _resolveTAP(String name) async {
    try {
      final query = '''
        SELECT TOP 1 main_id, ra, dec, otype_txt, flux
        FROM basic JOIN flux ON oid = oidref
        WHERE main_id = '\${name.toUpperCase()}'
        OR main_id LIKE '%${name.toUpperCase()}%'
      ''';

      final url = 'https://simbad.cds.unistra.fr/simbad/sim-tap/sync'
          '?request=doQuery'
          '&lang=adql'
          '&format=json'
          '&query=${Uri.encodeComponent(query)}';

      final client = http.Client();
      try {
        final response = await client.get(Uri.parse(url));

        if (response.statusCode != 200) return null;

        final json = jsonDecode(response.body);
        final data = json['data'] as List?;

        if (data == null || data.isEmpty) return null;

        final row = data[0] as List;

        return SimbadResult(
          mainId: row[0] as String,
          raHours: (row[1] as num).toDouble() / 15,
          decDegrees: (row[2] as num).toDouble(),
          objectType: row[3] as String? ?? 'Unknown',
          magnitude: row.length > 4 ? (row[4] as num?)?.toDouble() : null,
        );
      } finally {
        client.close();
      }
    } catch (error, stack) {
      developer.log(
        'SIMBAD TAP resolver failed for "$name".',
        name: 'Framing',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Search for objects matching a query
  static Future<List<SimbadResult>> search(String query) async {
    if (query.isEmpty || query.length < 2) return [];

    try {
      final tapQuery = '''
        SELECT TOP 20 main_id, ra, dec, otype_txt
        FROM basic
        WHERE main_id LIKE '${query.toUpperCase()}%'
        OR main_id LIKE '%${query.toUpperCase()}%'
        ORDER BY CASE WHEN main_id = '${query.toUpperCase()}' THEN 0 ELSE 1 END, main_id
      ''';

      final url = 'https://simbad.cds.unistra.fr/simbad/sim-tap/sync'
          '?request=doQuery'
          '&lang=adql'
          '&format=json'
          '&query=${Uri.encodeComponent(tapQuery)}';

      final client = http.Client();
      try {
        final response = await client.get(Uri.parse(url));

        if (response.statusCode != 200) return [];

        final json = jsonDecode(response.body);
        final data = json['data'] as List?;

        if (data == null) return [];

        return data.map((row) {
          final r = row as List;
          return SimbadResult(
            mainId: r[0] as String,
            raHours: (r[1] as num).toDouble() / 15,
            decDegrees: (r[2] as num).toDouble(),
            objectType: r[3] as String? ?? 'Unknown',
          );
        }).toList();
      } finally {
        client.close();
      }
    } catch (error, stack) {
      developer.log(
        'SIMBAD search failed for "$query".',
        name: 'Framing',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
      return [];
    }
  }
}

// =============================================================================
// TARGET SEARCH PROVIDER — REMOVED 2026-05-16 (audit §2.5).
//
// The duplicate `TargetSearchState` / `TargetSearchNotifier` / `targetSearchProvider`
// previously lived here. The screen-local autoDispose version at
// `packages/nightshade_app/lib/screens/framing/framing_search_provider.dart`
// is the canonical implementation. Every importer of `nightshade_core` had to
// `hide TargetSearchState, targetSearchProvider` to avoid the symbol collision;
// removing the duplicate eliminates that workaround.
// =============================================================================

// =============================================================================
// COORDINATE CONVERSION UTILITIES
// =============================================================================

class CoordinateUtils {
  /// Parse RA from string (supports HH:MM:SS, HHhMMmSSs, decimal hours/degrees)
  static double? parseRA(String input) {
    var cleaned = input.trim().toLowerCase();

    // Check for explicit units
    bool isDegrees = false;
    if (cleaned.endsWith('d') ||
        cleaned.endsWith('deg') ||
        cleaned.endsWith('°')) {
      isDegrees = true;
      cleaned = cleaned.replaceAll(RegExp(r'[d°]|deg'), '').trim();
    } else if (cleaned.endsWith('h')) {
      cleaned = cleaned.replaceAll('h', '').trim();
    }

    // Try decimal first
    final decimal = double.tryParse(cleaned);
    if (decimal != null) {
      if (isDegrees) {
        return decimal / 15;
      }

      // Heuristic for unitless numbers
      if (decimal > 24) {
        // Probably degrees
        return decimal / 15;
      }
      return decimal;
    }

    // Try HMS format
    final hmsRegex = RegExp(r"(\d+)[h:\s]+(\d+)[m:\s']+(\d+\.?\d*)[s:\s]*");
    final hmsMatch = hmsRegex.firstMatch(cleaned);
    if (hmsMatch != null) {
      final h = int.parse(hmsMatch.group(1)!);
      final m = int.parse(hmsMatch.group(2)!);
      final s = double.parse(hmsMatch.group(3)!);
      return h + m / 60 + s / 3600;
    }

    return null;
  }

  /// Parse Dec from string (supports ±DD:MM:SS, ±DD°MM'SS", decimal)
  static double? parseDec(String input) {
    final cleaned = input.trim();

    // Try decimal first
    final decimal = double.tryParse(cleaned);
    if (decimal != null) return decimal;

    // Try DMS format
    final dmsRegex = RegExp(r"([+-])?(\d+)[°:\s]+(\d+)[':\s]+(\d+\.?\d*)");
    final dmsMatch = dmsRegex.firstMatch(cleaned);
    if (dmsMatch != null) {
      final sign = dmsMatch.group(1) == '-' ? -1 : 1;
      final d = int.parse(dmsMatch.group(2)!);
      final m = int.parse(dmsMatch.group(3)!);
      final s = double.parse(dmsMatch.group(4)!);
      return sign * (d + m / 60 + s / 3600);
    }

    return null;
  }

  /// Format RA as HH:MM:SS
  static String formatRA(double raHours) {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    final seconds = (((raHours - hours) * 60 - minutes) * 60);
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toStringAsFixed(1)}s';
  }

  /// Format Dec as ±DD°MM'SS"
  static String formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final absDec = decDegrees.abs();
    final degrees = absDec.floor();
    final minutes = ((absDec - degrees) * 60).floor();
    final seconds = ((absDec - degrees) * 60 - minutes) * 60;
    return '$sign${degrees.toString().padLeft(2, '0')}° ${minutes.toString().padLeft(2, '0')}\' ${seconds.toStringAsFixed(1)}"';
  }
}
