part of '../centering_service.dart';

/// Right ascension returned by the plate solver, in **degrees**, converted
/// to the app-canonical **hours** the rest of the centering pipeline uses.
///
/// This is the fix for the 2026-06-04 full-night-audit "slew & center never
/// converges" bug. `PlateSolveResult.ra` arrives in degrees: the Rust
/// `PlateSolveResult.ra` is documented "Solved RA in degrees" and reads FITS
/// `CRVAL1` (degrees) verbatim, and the network host forwards that same
/// value unchanged. Every other RA in this service is in hours — the slew
/// target (`slewMountToCoordinates` expects hours), the mount sync
/// (`syncMountToCoordinates` expects hours), `mountState.ra` (ASCOM
/// `RightAscension`, hours) and the `CenteringStatus.solvedRa` contract
/// ("hours"). Normalising once here keeps the offset math, the sync-to-
/// solved-position slew, and the status display all consistent. Without
/// this, the solved RA was 15× the target RA's frame, so the offset never
/// fell below tolerance and the loop ran out its iterations.
double _solvedRaHours(double solvedRaDegrees) {
  return solvedRaDegrees / 15.0;
}

/// Wrap an RA in **hours** into [0, 24) so an offset correction across 0h
/// stays a legal slew target.
double _normalizedRaHours(double raHours) {
  final wrapped = raHours % 24.0;
  return wrapped < 0 ? wrapped + 24.0 : wrapped;
}

/// Clamp a Dec in **degrees** to the legal [-90, 90] range.
double _clampedDecDegrees(double decDegrees) {
  return decDegrees.clamp(-90.0, 90.0);
}

/// Calculate angular separation between two celestial coordinates in
/// arcseconds, using the haversine formula for great-circle distance.
///
/// Both [targetRa] and [solvedRa] are in **hours** here (the solver's
/// degrees value is normalised to hours via [_solvedRaHours] before it
/// reaches this method); [targetDec]/[solvedDec] are in degrees.
double _calculateOffset(
  double targetRa,
  double targetDec,
  double solvedRa,
  double solvedDec,
) {
  // Convert RA from hours to radians (both operands are in hours).
  final ra1 = targetRa * 15.0 * math.pi / 180.0; // hours -> degrees -> radians
  final ra2 = solvedRa * 15.0 * math.pi / 180.0;

  // Convert Dec from degrees to radians
  final dec1 = targetDec * math.pi / 180.0;
  final dec2 = solvedDec * math.pi / 180.0;

  // Haversine formula for great circle distance
  final deltaRa = ra2 - ra1;
  final deltaDec = dec2 - dec1;

  final a =
      math.pow(math.sin(deltaDec / 2), 2) +
      math.cos(dec1) * math.cos(dec2) * math.pow(math.sin(deltaRa / 2), 2);
  final c = 2 * math.asin(math.sqrt(a));

  // Convert radians to arcseconds
  final offsetRadians = c;
  final offsetDegrees = offsetRadians * 180.0 / math.pi;
  final offsetArcsec = offsetDegrees * 3600.0;

  return offsetArcsec;
}
