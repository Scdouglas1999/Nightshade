import 'dart:convert';

import 'package:equatable/equatable.dart';

/// Kinds of hard constraints applied to a target.
///
/// The scheduler refuses to select a target whose hard constraints are
/// violated at the current evaluation time, regardless of score.
enum TargetConstraintKind {
  /// A wall-clock time window during which imaging is permitted.
  /// Example: image NGC 7000 only between 22:00 and 02:00 local time.
  timeWindow,

  /// A maximum moon illumination fraction (0..1) above which the target
  /// is skipped. Example: image M42 only when moon < 0.30 illuminated.
  moonIlluminationMax,

  /// A reference to a horizon profile id; the target is rejected if its
  /// current altitude is below the profile's value at the target's azimuth.
  customHorizon,
}

/// Inclusive-exclusive local time window expressed as hh:mm.
///
/// startMinutes and endMinutes are minutes-since-midnight in local time
/// (0..1440). If endMinutes < startMinutes the window crosses midnight
/// (e.g. start=22:00, end=02:00 => window is 22:00–02:00 next day).
class TargetTimeWindow extends Equatable {
  final int startMinutes;
  final int endMinutes;

  const TargetTimeWindow({
    required this.startMinutes,
    required this.endMinutes,
  });

  /// Returns true if [localTime] (HH:MM in local clock) falls inside the
  /// window. Wrap-around (midnight-crossing) windows are handled.
  bool containsLocal(DateTime localTime) {
    final mins = localTime.hour * 60 + localTime.minute;
    if (endMinutes >= startMinutes) {
      return mins >= startMinutes && mins < endMinutes;
    }
    return mins >= startMinutes || mins < endMinutes;
  }

  Map<String, dynamic> toJson() => {
        'start_minutes': startMinutes,
        'end_minutes': endMinutes,
      };

  static TargetTimeWindow fromJson(Map<String, dynamic> json) {
    return TargetTimeWindow(
      startMinutes: json['start_minutes'] as int,
      endMinutes: json['end_minutes'] as int,
    );
  }

  @override
  List<Object?> get props => [startMinutes, endMinutes];
}

/// A single hard constraint attached to a target.
///
/// Only the field matching [kind] should be populated; the others are null.
/// Serialized to the database as JSON in the `payload_json` column so we
/// can add more constraint kinds without a schema change.
class TargetConstraint extends Equatable {
  /// Database row id; null for transient instances not yet persisted.
  final int? id;

  /// FK to targets.id.
  final int targetId;

  final TargetConstraintKind kind;

  final TargetTimeWindow? timeWindow;

  final double? moonIlluminationMax;

  /// Reference to HorizonProfiles.id (resolved against the same database).
  final int? customHorizonId;

  /// If false, the constraint exists but is not evaluated. Useful for
  /// preserving operator state across nights without deleting rows.
  final bool enabled;

  const TargetConstraint({
    this.id,
    required this.targetId,
    required this.kind,
    this.timeWindow,
    this.moonIlluminationMax,
    this.customHorizonId,
    this.enabled = true,
  });

  TargetConstraint copyWith({
    int? id,
    int? targetId,
    TargetConstraintKind? kind,
    TargetTimeWindow? timeWindow,
    double? moonIlluminationMax,
    int? customHorizonId,
    bool? enabled,
  }) {
    return TargetConstraint(
      id: id ?? this.id,
      targetId: targetId ?? this.targetId,
      kind: kind ?? this.kind,
      timeWindow: timeWindow ?? this.timeWindow,
      moonIlluminationMax: moonIlluminationMax ?? this.moonIlluminationMax,
      customHorizonId: customHorizonId ?? this.customHorizonId,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Serialize the kind-specific payload to a JSON string for storage in
  /// the `payload_json` column.
  String encodePayload() {
    switch (kind) {
      case TargetConstraintKind.timeWindow:
        if (timeWindow == null) {
          throw StateError('timeWindow constraint missing timeWindow value');
        }
        return jsonEncode(timeWindow!.toJson());
      case TargetConstraintKind.moonIlluminationMax:
        if (moonIlluminationMax == null) {
          throw StateError(
              'moonIlluminationMax constraint missing moonIlluminationMax value');
        }
        return jsonEncode({'max': moonIlluminationMax});
      case TargetConstraintKind.customHorizon:
        if (customHorizonId == null) {
          throw StateError(
              'customHorizon constraint missing customHorizonId value');
        }
        return jsonEncode({'profile_id': customHorizonId});
    }
  }

  /// Reconstruct a constraint from a database row.
  static TargetConstraint fromRow({
    required int id,
    required int targetId,
    required String kindName,
    required String payloadJson,
    required bool enabled,
  }) {
    final kind = TargetConstraintKind.values.firstWhere(
      (k) => k.name == kindName,
      orElse: () => throw StateError('Unknown constraint kind: $kindName'),
    );
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
    switch (kind) {
      case TargetConstraintKind.timeWindow:
        return TargetConstraint(
          id: id,
          targetId: targetId,
          kind: kind,
          timeWindow: TargetTimeWindow.fromJson(payload),
          enabled: enabled,
        );
      case TargetConstraintKind.moonIlluminationMax:
        return TargetConstraint(
          id: id,
          targetId: targetId,
          kind: kind,
          moonIlluminationMax: (payload['max'] as num).toDouble(),
          enabled: enabled,
        );
      case TargetConstraintKind.customHorizon:
        return TargetConstraint(
          id: id,
          targetId: targetId,
          kind: kind,
          customHorizonId: payload['profile_id'] as int,
          enabled: enabled,
        );
    }
  }

  @override
  List<Object?> get props => [
        id,
        targetId,
        kind,
        timeWindow,
        moonIlluminationMax,
        customHorizonId,
        enabled,
      ];
}
