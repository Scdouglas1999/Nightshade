import 'dart:convert';

import 'quick_start_service.dart';

class SessionHandoffBundle {
  final String version;
  final DateTime exportedAt;
  final int sessionId;
  final String? sessionName;
  final String? targetName;
  final double? targetRa;
  final double? targetDec;
  final int completedFrames;
  final int totalFrames;
  final double totalIntegrationHours;
  final EquipmentSnapshot? equipmentSnapshot;
  final String? sequenceName;

  const SessionHandoffBundle({
    required this.version,
    required this.exportedAt,
    required this.sessionId,
    required this.sessionName,
    required this.targetName,
    required this.targetRa,
    required this.targetDec,
    required this.completedFrames,
    required this.totalFrames,
    required this.totalIntegrationHours,
    required this.equipmentSnapshot,
    required this.sequenceName,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'exportedAt': exportedAt.toIso8601String(),
      'sessionId': sessionId,
      'sessionName': sessionName,
      'targetName': targetName,
      'targetRa': targetRa,
      'targetDec': targetDec,
      'completedFrames': completedFrames,
      'totalFrames': totalFrames,
      'totalIntegrationHours': totalIntegrationHours,
      'equipmentSnapshot': equipmentSnapshot?.toJson(),
      'sequenceName': sequenceName,
    };
  }

  factory SessionHandoffBundle.fromJson(Map<String, dynamic> json) {
    return SessionHandoffBundle(
      version: json['version'] as String? ?? '1',
      exportedAt: DateTime.parse(json['exportedAt'] as String),
      sessionId: json['sessionId'] as int,
      sessionName: json['sessionName'] as String?,
      targetName: json['targetName'] as String?,
      targetRa: (json['targetRa'] as num?)?.toDouble(),
      targetDec: (json['targetDec'] as num?)?.toDouble(),
      completedFrames: json['completedFrames'] as int? ?? 0,
      totalFrames: json['totalFrames'] as int? ?? 0,
      totalIntegrationHours: (json['totalIntegrationHours'] as num?)?.toDouble() ?? 0,
      equipmentSnapshot: json['equipmentSnapshot'] is Map<String, dynamic>
          ? EquipmentSnapshot.fromJson(json['equipmentSnapshot'] as Map<String, dynamic>)
          : null,
      sequenceName: json['sequenceName'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  factory SessionHandoffBundle.decode(String jsonText) {
    return SessionHandoffBundle.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);
  }
}

/// Serializes the current session state so another device can resume it.
class SessionHandoffService {
  const SessionHandoffService();

  SessionHandoffBundle exportBundle(QuickStartContext context) {
    return SessionHandoffBundle(
      version: '1',
      exportedAt: DateTime.now(),
      sessionId: context.sessionId,
      sessionName: context.sessionName,
      targetName: context.targetName,
      targetRa: context.targetRa,
      targetDec: context.targetDec,
      completedFrames: context.completedFrames,
      totalFrames: context.totalFrames,
      totalIntegrationHours: context.totalIntegrationHours,
      equipmentSnapshot: context.equipmentSnapshot,
      sequenceName: context.sequenceName,
    );
  }

  String describe(SessionHandoffBundle bundle) {
    final buffer = StringBuffer();
    buffer.write(bundle.sessionName ?? 'Session ${bundle.sessionId}');
    if (bundle.targetName != null) {
      buffer.write(' on ${bundle.targetName}');
    }
    if (bundle.totalFrames > 0) {
      buffer.write(' (${bundle.completedFrames}/${bundle.totalFrames} frames)');
    }
    if (bundle.totalIntegrationHours > 0) {
      buffer.write(' ${bundle.totalIntegrationHours.toStringAsFixed(1)}h integrated');
    }
    return buffer.toString();
  }
}
