/// PHD2 guiding status types.

/// PHD2 guiding status
class Phd2Status {
  /// Current PHD2 state (Stopped, Guiding, Calibrating, etc.)
  final String state;

  /// Whether connected to PHD2
  final bool connected;

  /// RMS error in RA (arcseconds)
  final double rmsRa;

  /// RMS error in Dec (arcseconds)
  final double rmsDec;

  /// Total RMS error (arcseconds)
  final double rmsTotal;

  /// Signal-to-noise ratio of guide star
  final double snr;

  /// Mass of the guide star (brightness indicator)
  final double starMass;

  /// Average guide star distance from lock position (pixels)
  final double avgDistance;

  const Phd2Status({
    required this.state,
    required this.connected,
    this.rmsRa = 0.0,
    this.rmsDec = 0.0,
    this.rmsTotal = 0.0,
    this.snr = 0.0,
    this.starMass = 0.0,
    this.avgDistance = 0.0,
  });

  /// Create from JSON (for network transport)
  factory Phd2Status.fromJson(Map<String, dynamic> json) {
    return Phd2Status(
      state: json['state'] as String,
      connected: json['connected'] as bool,
      rmsRa: (json['rmsRa'] as num?)?.toDouble() ?? 0.0,
      rmsDec: (json['rmsDec'] as num?)?.toDouble() ?? 0.0,
      rmsTotal: (json['rmsTotal'] as num?)?.toDouble() ?? 0.0,
      snr: (json['snr'] as num?)?.toDouble() ?? 0.0,
      starMass: (json['starMass'] as num?)?.toDouble() ?? 0.0,
      avgDistance: (json['avgDistance'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Convert to JSON (for network transport)
  Map<String, dynamic> toJson() => {
        'state': state,
        'connected': connected,
        'rmsRa': rmsRa,
        'rmsDec': rmsDec,
        'rmsTotal': rmsTotal,
        'snr': snr,
        'starMass': starMass,
        'avgDistance': avgDistance,
      };

  /// Check if PHD2 is actively guiding
  bool get isGuiding => state == 'Guiding';

  /// Check if PHD2 is calibrating
  bool get isCalibrating => state == 'Calibrating';

  /// Check if guiding is stopped
  bool get isStopped => state == 'Stopped';
}
