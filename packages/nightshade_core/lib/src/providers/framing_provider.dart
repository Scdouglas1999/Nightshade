import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_planetarium/src/catalogs/catalog_manager.dart'; // Explicit import to fix visibility issue

import '../database/database.dart';
import '../models/equipment/equipment_models.dart';
import '../models/target/target_models.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'equipment_provider.dart';

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

  /// Survey source for background image
  final SurveySource surveySource;

  /// Loaded survey image
  final Uint8List? surveyImageBytes;

  /// Decoded survey image for display
  final ui.Image? surveyImage;

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
    this.surveySource = SurveySource.dss2Red,
    this.surveyImageBytes,
    this.surveyImage,
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
    SurveySource? surveySource,
    Uint8List? surveyImageBytes,
    ui.Image? surveyImage,
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
  }) {
    return FramingState(
      target: clearTarget ? null : (target ?? this.target),
      surveySource: surveySource ?? this.surveySource,
      surveyImageBytes:
          clearImage ? null : (surveyImageBytes ?? this.surveyImageBytes),
      surveyImage: clearImage ? null : (surveyImage ?? this.surveyImage),
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
    final fovRad = 2 * _atan(sensorWidthMm / (2 * effectiveFocalLength));
    return fovRad * 180 / 3.14159265359;
  }

  /// FOV height in degrees
  double get fovHeightDeg {
    final fovRad = 2 * _atan(sensorHeightMm / (2 * effectiveFocalLength));
    return fovRad * 180 / 3.14159265359;
  }

  /// Image scale in arcsec/pixel
  double get imageScale {
    final pixelSizeMm = pixelSizeMicrons / 1000;
    return (pixelSizeMm / effectiveFocalLength) * 206265;
  }

  double get focalRatio => effectiveFocalLength / apertureMm;

  static double _atan(double x) {
    if (x.abs() < 1) {
      final x2 = x * x;
      return x *
          (1 -
              x2 *
                  (1 / 3 -
                      x2 * (1 / 5 - x2 * (1 / 7 - x2 * (1 / 9 - x2 / 11)))));
    } else {
      final sign = x.sign;
      return sign * (3.14159265359 / 2 - _atan(1 / x.abs()));
    }
  }
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

  FramingNotifier(this._ref) : super(const FramingState());

  /// Set the target by coordinates
  void setTargetCoordinates(double raHours, double decDegrees, {String? name}) {
    final target = FramingTarget(
      name: name ?? 'Custom Location',
      raHours: raHours,
      decDegrees: decDegrees,
    );
    state = state.copyWith(target: target, clearImage: true);
    loadSurveyImage();
  }

  /// Set the target from a catalog search result
  void setTarget(FramingTarget target) {
    state = state.copyWith(target: target, clearImage: true);
    loadSurveyImage();
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

  /// Set frame rotation
  void setRotation(double degrees) {
    state = state.copyWith(rotation: degrees % 360);
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

  /// Add to current pan
  void pan(double dx, double dy) {
    state = state.copyWith(
      panX: state.panX + dx,
      panY: state.panY + dy,
    );
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

  /// Load survey image from NASA SkyView or Aladin
  Future<void> loadSurveyImage() async {
    if (state.target == null) return;

    state = state.copyWith(isLoadingImage: true, imageError: null);

    try {
      // Get FOV to determine image size
      final equipmentFov = await _getCurrentFOV();

      // Use user's preview FOV, or equipment FOV if configured
      final previewFov = state.previewFovDegrees;
      final hasEquipment = equipmentFov != null;

      // Determine the actual FOV to fetch
      double requestWidth;
      double requestHeight;

      if (hasEquipment) {
        // If preview FOV is larger than equipment FOV, use preview FOV
        // Otherwise use equipment FOV with some context
        final equipmentWidth = equipmentFov.$1;
        final equipmentHeight = equipmentFov.$2;

        if (previewFov > equipmentWidth) {
          // User wants to see more context - use preview FOV
          requestWidth = previewFov;
          requestHeight = previewFov * (equipmentHeight / equipmentWidth);
        } else {
          // Use equipment FOV with 2.5x context
          requestWidth = equipmentWidth * 2.5;
          requestHeight = equipmentHeight * 2.5;
        }
      } else {
        // No equipment - use preview FOV
        requestWidth = previewFov;
        requestHeight = previewFov * 0.75; // Default 4:3 aspect
      }

      // Use Aladin HiPS2FITS service (more reliable than SkyView for images)
      final url = _buildAladinUrl(
        state.target!.raDegrees,
        state.target!.decDegrees,
        requestWidth,
        requestHeight,
        state.surveySource,
      );

      final client = http.Client();
      try {
        final response = await client.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;

          // Decode to ui.Image
          final completer = Completer<ui.Image>();
          ui.decodeImageFromList(bytes, (image) {
            completer.complete(image);
          });
          final image = await completer.future;

          if (!mounted) return;
          state = state.copyWith(
            surveyImageBytes: bytes,
            surveyImage: image,
            isLoadingImage: false,
          );
        } else {
          // Fallback to SkyView
          final skyViewUrl = _buildSkyViewUrl(
            state.target!.raDegrees,
            state.target!.decDegrees,
            requestWidth,
            requestHeight,
            state.surveySource,
          );

          final skyViewResponse = await client.get(Uri.parse(skyViewUrl));

          if (skyViewResponse.statusCode == 200) {
            final bytes = skyViewResponse.bodyBytes;
            final completer = Completer<ui.Image>();
            ui.decodeImageFromList(bytes, (image) {
              completer.complete(image);
            });
            final image = await completer.future;

            if (!mounted) return;
            state = state.copyWith(
              surveyImageBytes: bytes,
              surveyImage: image,
              isLoadingImage: false,
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
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoadingImage: false,
        imageError: 'Error: ${e.toString()}',
      );
    }
  }

  String _buildAladinUrl(
    double raDeg,
    double decDeg,
    double widthDeg,
    double heightDeg,
    SurveySource source,
  ) {
    final hipsId = _getHipsId(source);
    return 'https://alasky.cds.unistra.fr/hips-image-services/hips2fits'
        '?hips=$hipsId'
        '&ra=$raDeg'
        '&dec=$decDeg'
        '&fov=${widthDeg.toStringAsFixed(4)}'
        '&width=800'
        '&height=${(800 * heightDeg / widthDeg).round()}'
        '&format=jpg';
  }

  String _buildSkyViewUrl(
    double raDeg,
    double decDeg,
    double widthDeg,
    double heightDeg,
    SurveySource source,
  ) {
    final surveyId = _getSkyViewSurvey(source);
    return 'https://skyview.gsfc.nasa.gov/current/cgi/runquery.pl'
        '?Position=$raDeg,$decDeg'
        '&Survey=$surveyId'
        '&Pixels=800,${(800 * heightDeg / widthDeg).round()}'
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

    // Try to get from active equipment profile
    try {
      final profilesDao = _ref.read(equipmentProfilesDaoProvider);
      final profile = await profilesDao.getActiveProfile();

      if (profile != null && profile.focalLength > 0) {
        if (profile.cameraId == null || profile.cameraId!.isEmpty) {
          developer.log(
            'Cannot compute profile FOV for "${profile.name}" without a configured camera.',
            name: 'Framing',
            level: 900,
          );
          return null;
        }

        final cameraState = _ref.read(cameraStateProvider);
        if (cameraState.connectionState != DeviceConnectionState.connected) {
          developer.log(
            'Cannot compute profile FOV for "${profile.name}" because the camera is not connected.',
            name: 'Framing',
            level: 900,
          );
          return null;
        }

        final backend = _ref.read(backendProvider);
        final status = await backend.getCameraStatus(profile.cameraId!);
        if (status.sensorWidth <= 0 ||
            status.sensorHeight <= 0 ||
            status.pixelSizeX <= 0) {
          developer.log(
            'Camera status lacks sensor dimensions for "${profile.name}" (width=${status.sensorWidth}, height=${status.sensorHeight}, pixelSize=${status.pixelSizeX}).',
            name: 'Framing',
            level: 1000,
          );
          return null;
        }

        final sensorWidth = (status.sensorWidth * status.pixelSizeX) / 1000.0;
        final sensorHeight = (status.sensorHeight * status.pixelSizeY) / 1000.0;

        final fovWidthRad =
            2 * FramingEquipment._atan(sensorWidth / (2 * profile.focalLength));
        final fovHeightRad = 2 *
            FramingEquipment._atan(sensorHeight / (2 * profile.focalLength));

        return (
          fovWidthRad * 180 / 3.14159265359,
          fovHeightRad * 180 / 3.14159265359
        );
      }
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
        final decRad = centerDec * 3.14159265359 / 180;
        final cosDec = _cos(decRad);
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

  static double _cos(double x) {
    // Simple cosine approximation
    x = x % (2 * 3.14159265359);
    if (x < 0) x += 2 * 3.14159265359;

    final x2 = x * x;
    return 1 - x2 / 2 + x2 * x2 / 24 - x2 * x2 * x2 / 720;
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

    final targetsDao = _ref.read(targetsDaoProvider);

    await targetsDao.createTarget(TargetsCompanion.insert(
      name: state.target!.name,
      catalogId: Value(state.target!.catalogId),
      ra: state.target!.raHours,
      dec: state.target!.decDegrees,
      objectType: Value(state.target!.type?.name ?? 'other'),
      magnitude: Value(state.target!.magnitude),
      sizeArcmin: Value(state.target!.sizeArcmin),
      constellation: Value(state.target!.constellation),
    ));
  }

  /// Load the most recent target from database (if any)
  Future<void> loadMostRecentTarget() async {
    final targetsDao = _ref.read(targetsDaoProvider);
    final allTargets = await targetsDao.getAllTargets();

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

  // Get from active profile
  final profilesDao = ref.watch(equipmentProfilesDaoProvider);
  final profile = await profilesDao.getActiveProfile();

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
// TARGET SEARCH PROVIDER
// =============================================================================

/// State for target search
class TargetSearchState {
  final String query;
  final List<FramingTarget> results;
  final bool isSearching;
  final String? error;

  const TargetSearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
    this.error,
  });

  TargetSearchState copyWith({
    String? query,
    List<FramingTarget>? results,
    bool? isSearching,
    String? error,
  }) {
    return TargetSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      error: error,
    );
  }
}

class TargetSearchNotifier extends StateNotifier<TargetSearchState> {
  final Ref _ref;
  Timer? _debounceTimer;

  TargetSearchNotifier(this._ref) : super(const TargetSearchState());

  /// Search for targets
  void search(String query) {
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      state = const TargetSearchState();
      return;
    }

    state = state.copyWith(query: query, isSearching: true);

    // Debounce to avoid too many API calls
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final results = <FramingTarget>[];
    final seenIds = <String>{}; // To deduplicate results

    try {
      // 1. Search local user database (highest priority)
      final targetsDao = _ref.read(targetsDaoProvider);
      final localTargets = await targetsDao.searchTargets(query);

      for (final t in localTargets) {
        // Backward-compatibility: some older DB entries stored RA in degrees, not hours.
        final raHours = _normalizeRaHoursMaybeDegrees(t.ra);
        results.add(FramingTarget(
          name: t.name,
          catalogId: t.catalogId,
          raHours: raHours,
          decDegrees: t.dec,
          type: _parseTargetType(t.objectType),
          magnitude: t.magnitude,
          sizeArcmin: t.sizeArcmin,
          constellation: t.constellation,
        ));
        if (t.catalogId != null) seenIds.add(t.catalogId!);
      }

      // 2. Search Offline Catalogs (OpenNGC & HYG)
      try {
        final manager = CatalogManager.instance;
        if (manager.isInitialized) {
          final catalogResults = await manager.search(query);

          for (final r in catalogResults) {
            if (seenIds.contains(r.catalogId)) continue;

            results.add(FramingTarget(
              name: r.name,
              catalogId: r.catalogId,
              raHours: r.ra / 15.0, // Convert degrees to hours
              decDegrees: r.dec,
              type: _mapCatalogType(r.type),
              magnitude: r.magnitude,
              constellation: r.constellation,
            ));
            seenIds.add(r.catalogId);
          }
        }
      } catch (e) {
        developer.log('Catalog search error: $e', name: 'Framing', level: 1000);
      }

      // 3. Fallback to SIMBAD (Live Internet Search)
      if (results.isEmpty) {
        final simbadResults = await SimbadResolver.search(query);

        for (final r in simbadResults) {
          if (seenIds.contains(r.mainId)) continue;

          results.add(FramingTarget(
            name: r.mainId,
            catalogId: r.mainId,
            raHours: r.raHours,
            decDegrees: r.decDegrees,
            magnitude: r.magnitude,
            type: _parseTargetType(r.objectType) ?? TargetType.other,
          ));
          seenIds.add(r.mainId);
        }
      }

      state = TargetSearchState(
        query: query,
        results: results,
        isSearching: false,
      );
    } catch (e) {
      state = TargetSearchState(
        query: query,
        results: results,
        isSearching: false,
        error: e.toString(),
      );
    }
  }

  TargetType? _parseTargetType(String? type) {
    if (type == null) return null;
    try {
      return TargetType.values.firstWhere(
        (t) => t.name.toLowerCase() == type.toLowerCase(),
        orElse: () => TargetType.other,
      );
    } catch (error, stack) {
      developer.log(
        'Unrecognized target type "$type". Falling back to TargetType.other.',
        name: 'Framing',
        level: 900,
        error: error,
        stackTrace: stack,
      );
      return TargetType.other;
    }
  }

  TargetType _mapCatalogType(String? type) {
    if (type == null) return TargetType.other;
    final t = type.toLowerCase();
    if (t.contains('galaxy') || t == 'g') return TargetType.galaxy;
    if (t.contains('nebula') || t.contains('neb') || t == 'pn' || t == 'en')
      return TargetType.nebula;
    if (t.contains('cluster') || t == 'oc' || t == 'gc')
      return TargetType.cluster;
    if (t.contains('star') || t == '*') return TargetType.star;
    return TargetType.other;
  }

  void clear() {
    _debounceTimer?.cancel();
    state = const TargetSearchState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

final targetSearchProvider =
    StateNotifierProvider<TargetSearchNotifier, TargetSearchState>((ref) {
  return TargetSearchNotifier(ref);
});

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
