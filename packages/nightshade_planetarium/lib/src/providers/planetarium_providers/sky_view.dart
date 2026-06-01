part of '../planetarium_providers.dart';

// ============================================================================
// Sky View State Provider
// ============================================================================

class SkyViewNotifier extends StateNotifier<SkyViewState> {
  SkyViewNotifier()
      : super(const SkyViewState(
          centerRA: 0,
          centerDec: 0,
          fieldOfView: 60,
        ));

  void setCenter(double ra, double dec) {
    state = state.copyWith(
      centerRA: ra.clamp(0, 24),
      centerDec: dec.clamp(-90, 90),
    );
  }

  void setFieldOfView(double fov) {
    state = state.copyWith(fieldOfView: fov.clamp(1, 180));
  }

  void setRotation(double rotation) {
    state = state.copyWith(rotation: rotation % 360);
  }

  void setProjection(SkyProjection projection) {
    state = state.copyWith(projection: projection);
  }

  void zoomIn({Offset? mousePosition, Size? viewSize}) {
    if (mousePosition != null && viewSize != null) {
      _zoomAtPosition(mousePosition, viewSize, 1.5);
    } else {
      state =
          state.copyWith(fieldOfView: (state.fieldOfView / 1.5).clamp(1, 180));
    }
  }

  void zoomOut({Offset? mousePosition, Size? viewSize}) {
    if (mousePosition != null && viewSize != null) {
      _zoomAtPosition(mousePosition, viewSize, 1 / 1.5);
    } else {
      state =
          state.copyWith(fieldOfView: (state.fieldOfView * 1.5).clamp(1, 180));
    }
  }

  /// Zoom at a specific screen position, keeping that position fixed
  void _zoomAtPosition(Offset mousePosition, Size viewSize, double zoomFactor) {
    // Get the celestial coordinate at the mouse position before zoom
    final coordBefore = _screenToCelestial(mousePosition, viewSize);
    if (coordBefore == null) {
      // Fallback to center zoom if conversion fails
      state = state.copyWith(
          fieldOfView: (state.fieldOfView / zoomFactor).clamp(1, 180));
      return;
    }

    // Apply zoom
    final oldFOV = state.fieldOfView;
    final newFOV = (oldFOV / zoomFactor).clamp(1.0, 180.0);
    state = state.copyWith(fieldOfView: newFOV);

    // Get the celestial coordinate at the same screen position after zoom
    final coordAfter = _screenToCelestial(mousePosition, viewSize);
    if (coordAfter == null) return;

    // Calculate the offset needed to keep the mouse position pointing at the same celestial coordinate
    final dRA = coordBefore.ra - coordAfter.ra;
    final dDec = coordBefore.dec - coordAfter.dec;

    // Adjust center to compensate
    var newRA = state.centerRA + dRA;
    if (newRA < 0) newRA += 24;
    if (newRA >= 24) newRA -= 24;

    state = state.copyWith(
      centerRA: newRA,
      centerDec: (state.centerDec + dDec).clamp(-90, 90),
    );
  }

  /// Convert screen position to celestial coordinates
  CelestialCoordinate? _screenToCelestial(Offset position, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale =
        math.min(size.width, size.height) / 2 / (state.fieldOfView / 2);

    // Offset from center in screen pixels
    final dx = -(position.dx - center.dx) / scale;
    final dy = -(position.dy - center.dy) / scale;

    // Reverse rotation
    final rotRad = -state.rotation * math.pi / 180;
    final x = dx * math.cos(rotRad) - dy * math.sin(rotRad);
    final y = dx * math.sin(rotRad) + dy * math.cos(rotRad);

    // Convert to RA/Dec (inverse of stereographic projection)
    final centerRaDeg = state.centerRA * 15;
    final centerDecDeg = state.centerDec;

    final xRad = x * math.pi / 180;
    final yRad = y * math.pi / 180;
    final centerRaRad = centerRaDeg * math.pi / 180;
    final centerDecRad = centerDecDeg * math.pi / 180;

    final rho = math.sqrt(xRad * xRad + yRad * yRad);
    if (rho < 0.0001) {
      return CelestialCoordinate(ra: state.centerRA, dec: state.centerDec);
    }

    final c = 2 * math.atan(rho / 2);
    final sinc = math.sin(c);
    final cosc = math.cos(c);

    final dec = math.asin(cosc * math.sin(centerDecRad) +
        yRad * sinc * math.cos(centerDecRad) / rho);
    final ra = centerRaRad +
        math.atan2(
          xRad * sinc,
          rho * math.cos(centerDecRad) * cosc -
              yRad * math.sin(centerDecRad) * sinc,
        );

    var raHours = (ra * 180 / math.pi / 15).toDouble();
    if (raHours < 0) raHours += 24;
    if (raHours >= 24) raHours -= 24;

    final decDeg = (dec * 180 / math.pi).toDouble();

    return CelestialCoordinate(ra: raHours, dec: decDeg.clamp(-90, 90));
  }

  void pan(double dRA, double dDec) {
    var newRA = state.centerRA + dRA;
    if (newRA < 0) newRA += 24;
    if (newRA >= 24) newRA -= 24;

    state = state.copyWith(
      centerRA: newRA,
      centerDec: (state.centerDec + dDec).clamp(-90, 90),
    );
  }

  void lookAt(CelestialCoordinate coord) {
    state = state.copyWith(centerRA: coord.ra, centerDec: coord.dec);
  }
}

final skyViewStateProvider =
    StateNotifierProvider<SkyViewNotifier, SkyViewState>((ref) {
  return SkyViewNotifier();
});

/// Computed provider for current view center in horizontal coordinates
/// Returns (azimuth, altitude) in degrees
/// Uses minute precision to avoid excessive rebuilds from per-second time updates.
final viewCenterAltAzProvider = Provider<(double, double)>((ref) {
  final viewState = ref.watch(skyViewStateProvider);
  final location = ref.watch(observerLocationProvider);
  final time =
      ref.watch(_currentMinuteProvider); // Use minute precision instead

  // Convert view center (RA/Dec) to Alt/Az
  final lst = AstronomyCalculations.localSiderealTime(time, location.longitude);

  final (alt, az) = AstronomyCalculations.equatorialToHorizontal(
    raDeg: viewState.centerRA * 15, // Convert hours to degrees
    decDeg: viewState.centerDec,
    latitudeDeg: location.latitude,
    lstHours: lst,
  );

  return (az, alt);
});
