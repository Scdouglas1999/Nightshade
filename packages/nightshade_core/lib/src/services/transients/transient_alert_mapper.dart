import '../../database/database.dart' show TransientDetectionRow;
import '../../models/alerts/transient_alert.dart';
import 'transient_candidate.dart';

/// Bridges a Pillar B ("First Light") [TransientDetectionRow] into the shared
/// [TransientAlert] model so a self-discovered transient flows through the same
/// alert surfaces (badge, dropdown, transients screen) as AAVSO / TNS alerts.
///
/// The detection's residual shape-class maps onto the alert taxonomy: a moving
/// streak → asteroid, a clean unnamed point source → supernova-like (the most
/// urgent "go look now" tier), a named brightening → variable star / nova. The
/// alert id is namespaced (`firstlight:<rowId>`) so its acknowledged/dismissed
/// state persists distinctly from external alerts and never collides with them.
TransientAlert transientAlertFromDetection(TransientDetectionRow detection) {
  final kind = TransientKind.fromWire(detection.kind);
  final type = _typeForKind(kind, hasMatch: detection.catalogMatch != null);
  final raHours = (detection.raDeg % 360.0) / 15.0;

  final name = detection.catalogMatch ?? _provisionalName(detection);
  final magnitude = detection.deltaMag?.abs();

  return TransientAlert(
    id: 'firstlight:${detection.id}',
    name: name,
    type: type,
    raHours: raHours < 0 ? raHours + 24.0 : raHours,
    decDegrees: detection.decDeg,
    magnitude: magnitude,
    discoveryTime: detection.detectedAt,
    lastUpdated: detection.detectedAt,
    source: TransientSource.manual,
    // Higher confidence → higher priority (lower number). Clamp to [1, 10].
    priority: (1 + ((1.0 - detection.confidence) * 9).round()).clamp(1, 10),
    classification: detection.catalogMatch == null
        ? 'Unconfirmed — possible new transient'
        : 'Brightening of ${detection.catalogMatch}',
    notes:
        'Nightshade First Light difference-image detection. '
        'Tile ${detection.tileId}, SNR ${detection.snr.toStringAsFixed(1)}, '
        'kind ${detection.kind}.',
    state: detection.dismissed
        ? TransientAlertState.dismissed
        : (detection.reviewed
              ? TransientAlertState.acknowledged
              : TransientAlertState.newAlert),
  );
}

TransientType _typeForKind(TransientKind kind, {required bool hasMatch}) {
  switch (kind) {
    case TransientKind.movingStreak:
      return TransientType.asteroid;
    case TransientKind.newSource:
      // A clean, unnamed newcomer is treated as the supernova-like top tier.
      return hasMatch ? TransientType.variableStar : TransientType.supernova;
    case TransientKind.pointBrightening:
      return hasMatch ? TransientType.variableStar : TransientType.nova;
    case TransientKind.dipole:
      return TransientType.other;
  }
}

String _provisionalName(TransientDetectionRow detection) {
  final raH = (detection.raDeg % 360.0) / 15.0;
  final sign = detection.decDeg < 0 ? '-' : '+';
  return 'NS J'
      '${raH.toStringAsFixed(2)}'
      '$sign${detection.decDeg.abs().toStringAsFixed(1)}';
}
