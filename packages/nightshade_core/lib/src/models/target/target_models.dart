import 'package:equatable/equatable.dart';

/// Target object type
enum TargetType {
  galaxy,
  nebula,
  cluster,
  star,
  planet,
  moon,
  comet,
  asteroid,
  other,
}

extension TargetTypeExtension on TargetType {
  String get displayName {
    switch (this) {
      case TargetType.galaxy: return 'Galaxy';
      case TargetType.nebula: return 'Nebula';
      case TargetType.cluster: return 'Cluster';
      case TargetType.star: return 'Star';
      case TargetType.planet: return 'Planet';
      case TargetType.moon: return 'Moon';
      case TargetType.comet: return 'Comet';
      case TargetType.asteroid: return 'Asteroid';
      case TargetType.other: return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case TargetType.galaxy: return 'galaxy';
      case TargetType.nebula: return 'cloud';
      case TargetType.cluster: return 'stars';
      case TargetType.star: return 'star';
      case TargetType.planet: return 'planet';
      case TargetType.moon: return 'moon';
      case TargetType.comet: return 'comet';
      case TargetType.asteroid: return 'rock';
      case TargetType.other: return 'sparkles';
    }
  }
}

/// A celestial target for imaging
class CelestialTarget extends Equatable {
  final int? id;
  final String name;
  final String? catalogId;
  final String? description;
  final double raHours;
  final double decDegrees;
  final TargetType objectType;
  final double? magnitude;
  final String? constellation;
  final double? sizeArcmin;
  final bool isFavorite;
  final int priority;
  final int capturedSubs;
  final double totalIntegrationSecs;
  final String? filterProgress; // JSON: {"L": 30, "R": 20, ...}
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CelestialTarget({
    this.id,
    required this.name,
    this.catalogId,
    this.description,
    required this.raHours,
    required this.decDegrees,
    this.objectType = TargetType.other,
    this.magnitude,
    this.constellation,
    this.sizeArcmin,
    this.isFavorite = false,
    this.priority = 0,
    this.capturedSubs = 0,
    this.totalIntegrationSecs = 0,
    this.filterProgress,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

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

  /// Format total integration time
  String get integrationFormatted {
    final hours = (totalIntegrationSecs / 3600).floor();
    final minutes = ((totalIntegrationSecs % 3600) / 60).floor();
    return '${hours}h ${minutes}m';
  }

  CelestialTarget copyWith({
    int? id,
    String? name,
    String? catalogId,
    String? description,
    double? raHours,
    double? decDegrees,
    TargetType? objectType,
    double? magnitude,
    String? constellation,
    double? sizeArcmin,
    bool? isFavorite,
    int? priority,
    int? capturedSubs,
    double? totalIntegrationSecs,
    String? filterProgress,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CelestialTarget(
      id: id ?? this.id,
      name: name ?? this.name,
      catalogId: catalogId ?? this.catalogId,
      description: description ?? this.description,
      raHours: raHours ?? this.raHours,
      decDegrees: decDegrees ?? this.decDegrees,
      objectType: objectType ?? this.objectType,
      magnitude: magnitude ?? this.magnitude,
      constellation: constellation ?? this.constellation,
      sizeArcmin: sizeArcmin ?? this.sizeArcmin,
      isFavorite: isFavorite ?? this.isFavorite,
      priority: priority ?? this.priority,
      capturedSubs: capturedSubs ?? this.capturedSubs,
      totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
      filterProgress: filterProgress ?? this.filterProgress,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    catalogId,
    description,
    raHours,
    decDegrees,
    objectType,
    magnitude,
    constellation,
    sizeArcmin,
    isFavorite,
    priority,
    capturedSubs,
    totalIntegrationSecs,
    filterProgress,
    notes,
    createdAt,
    updatedAt,
  ];
}

/// Visibility information for a target
class TargetVisibility {
  final CelestialTarget target;
  final double currentAltitude;
  final double currentAzimuth;
  final DateTime? riseTime;
  final DateTime? setTime;
  final DateTime? transitTime;
  final double transitAltitude;
  final bool isVisible;
  final bool isAboveHorizon;

  const TargetVisibility({
    required this.target,
    required this.currentAltitude,
    required this.currentAzimuth,
    this.riseTime,
    this.setTime,
    this.transitTime,
    required this.transitAltitude,
    required this.isVisible,
    required this.isAboveHorizon,
  });

  /// Time until target sets (or null if already set)
  Duration? get timeUntilSet {
    if (setTime == null) return null;
    final now = DateTime.now();
    if (setTime!.isBefore(now)) return null;
    return setTime!.difference(now);
  }

  /// Time until transit (or null if already passed)
  Duration? get timeUntilTransit {
    if (transitTime == null) return null;
    final now = DateTime.now();
    if (transitTime!.isBefore(now)) return null;
    return transitTime!.difference(now);
  }
}

/// Session plan with multiple targets
class SessionPlan extends Equatable {
  final String id;
  final String name;
  final DateTime planDate;
  final List<PlannedTarget> targets;
  final DateTime? createdAt;

  const SessionPlan({
    required this.id,
    required this.name,
    required this.planDate,
    required this.targets,
    this.createdAt,
  });

  @override
  List<Object?> get props => [id, name, planDate, targets, createdAt];
}

/// A target in a session plan with time allocation
class PlannedTarget extends Equatable {
  final CelestialTarget target;
  final DateTime? startTime;
  final DateTime? endTime;
  final Duration plannedDuration;
  final int plannedExposures;
  final String? notes;

  const PlannedTarget({
    required this.target,
    this.startTime,
    this.endTime,
    required this.plannedDuration,
    required this.plannedExposures,
    this.notes,
  });

  @override
  List<Object?> get props => [
    target,
    startTime,
    endTime,
    plannedDuration,
    plannedExposures,
    notes,
  ];
}
