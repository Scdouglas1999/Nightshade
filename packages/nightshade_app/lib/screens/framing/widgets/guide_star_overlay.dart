// The framing "guide-star finder" overlay (Phase G quick win).
//
// Drop it into the framing canvas `Stack` above the FOV reticle. When the
// `Guide Stars` toggle is on and a target is framed, it highlights the bright
// (V < 10) catalog stars inside the imaging FOV that an autoguider could lock
// onto, drawn co-registered with the survey background / FOV reticle through the
// SAME [FramingSkyProjection] every other framing layer uses.
//
// It is fully self-contained, mirroring [HipsTileLayer]: it measures its own
// canvas with a [LayoutBuilder], reads framing state from the provider, resolves
// the FOV from the equipment profile (falling back to the preview FOV when no
// equipment is configured), loads the nearby bright stars from the shared HYG
// [starCatalogProvider], runs the pure [findGuideStarCandidates] finder, and
// paints the markers. It adds no parameters to [FramingCanvas] and is wrapped in
// an [IgnorePointer] so pan / rotate gestures fall through to the canvas beneath.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
// The pure guide-star finder + the shared framing projection live in
// nightshade_core's models layer and are intentionally not surfaced through the
// public barrel (app->core src-model types, the same convention the framing
// painters / canvas use for FramingPlateScale).
// ignore: implementation_imports
import 'package:nightshade_core/src/models/framing_guide_star.dart';
// ignore: implementation_imports
import 'package:nightshade_core/src/models/framing_hips_projection.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../painters/guide_star_overlay_painter.dart';

/// Magnitude ceiling for a usable guide star (V < 10 is bright enough for a
/// guide camera to centroid reliably).
const double _guideStarMagnitudeLimit = 10.0;

/// Cone-search query key for [_nearbyGuideStarsProvider]: the FOV center plus a
/// search radius. Equality is value-based so panning a target keeps the same
/// catalog query (and cache) while the projection re-places the markers.
class _GuideStarConeKey {
  final double raHours;
  final double decDegrees;
  final double radiusDegrees;

  const _GuideStarConeKey({
    required this.raHours,
    required this.decDegrees,
    required this.radiusDegrees,
  });

  @override
  bool operator ==(Object other) =>
      other is _GuideStarConeKey &&
      other.raHours == raHours &&
      other.decDegrees == decDegrees &&
      other.radiusDegrees == radiusDegrees;

  @override
  int get hashCode => Object.hash(raHours, decDegrees, radiusDegrees);
}

/// Loads the bright (V < 10) catalog stars within [key]'s cone around the FOV
/// center from the shared HYG star catalog. The pure finder then narrows these
/// to the ones actually inside the FOV rectangle; the cone is the cheap coarse
/// pass so the whole catalog is never projected per frame.
final _nearbyGuideStarsProvider =
    FutureProvider.family<List<GuideStarInput>, _GuideStarConeKey>(
        (ref, key) async {
  final catalog = ref.watch(starCatalogProvider);
  final stars = await catalog.getStarsNear(
    CelestialCoordinate(ra: key.raHours, dec: key.decDegrees),
    key.radiusDegrees,
    maxMagnitude: _guideStarMagnitudeLimit,
  );
  return [
    for (final star in stars)
      GuideStarInput(
        id: star.id,
        name: star.name,
        raHours: star.coordinates.ra,
        decDegrees: star.coordinates.dec,
        magnitude: star.magnitude,
      ),
  ];
});

/// The framing guide-star finder overlay widget.
class GuideStarOverlay extends ConsumerWidget {
  /// FOV width in degrees of the imaging frame the candidates must fall in.
  final double fovWidthDeg;

  /// FOV height in degrees of the imaging frame.
  final double fovHeightDeg;

  const GuideStarOverlay({
    super.key,
    required this.fovWidthDeg,
    required this.fovHeightDeg,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final framingState = ref.watch(framingProvider);
    final target = framingState.target;
    if (!framingState.showGuideStars || target == null) {
      return const SizedBox.expand();
    }
    if (fovWidthDeg <= 0 || fovHeightDeg <= 0) {
      return const SizedBox.expand();
    }

    final colors = NightshadeColors.of(context);

    // Search a cone comfortably larger than the FOV diagonal so a star near a
    // corner is never missed by the coarse pass; the finder does the exact
    // inside-FOV test.
    final coneRadius = _coneRadiusDegrees(fovWidthDeg, fovHeightDeg);
    final coneKey = _GuideStarConeKey(
      raHours: target.raHours,
      decDegrees: target.decDegrees,
      radiusDegrees: coneRadius,
    );
    final starsAsync = ref.watch(_nearbyGuideStarsProvider(coneKey));
    final stars = starsAsync.valueOrNull;
    if (stars == null || stars.isEmpty) {
      // Loading or no bright stars in range: paint nothing (never-blank canvas
      // shows through). Errors surface through the FutureProvider.
      return const SizedBox.expand();
    }

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canvasSize = constraints.biggest;
          if (canvasSize.isEmpty) return const SizedBox.expand();

          final view = FramingProjectionView(
            plateScale: framingState.plateScale,
            previewFovDegrees: framingState.previewFovDegrees,
            centerRaHours: target.raHours,
            centerDecDegrees: target.decDegrees,
            zoom: framingState.zoom,
            panX: framingState.panX,
            panY: framingState.panY,
            rotationDegrees: framingState.rotation,
          );
          final projection = FramingSkyProjection.fromView(canvasSize, view);

          final candidates = findGuideStarCandidates(
            projection: projection,
            stars: stars,
            query: GuideStarQuery(
              maxMagnitude: _guideStarMagnitudeLimit,
              fovWidthDeg: fovWidthDeg,
              fovHeightDeg: fovHeightDeg,
            ),
          );
          if (candidates.isEmpty) return const SizedBox.expand();

          return CustomPaint(
            size: Size.infinite,
            painter: GuideStarOverlayPainter(
              candidates: candidates,
              colors: colors,
            ),
          );
        },
      ),
    );
  }

  /// Cone-search radius (degrees) covering the FOV plus margin: half the FOV
  /// diagonal times 1.2 so corner stars are always included by the coarse pass.
  static double _coneRadiusDegrees(double widthDeg, double heightDeg) {
    final halfDiagonal =
        0.5 * math.sqrt(widthDeg * widthDeg + heightDeg * heightDeg);
    return halfDiagonal * 1.2;
  }
}
