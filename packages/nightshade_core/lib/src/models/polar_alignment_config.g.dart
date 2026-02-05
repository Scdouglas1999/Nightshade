// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'polar_alignment_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$PolarAlignmentConfigImpl _$$PolarAlignmentConfigImplFromJson(
        Map<String, dynamic> json) =>
    _$PolarAlignmentConfigImpl(
      exposureTime: (json['exposureTime'] as num?)?.toDouble() ?? 5.0,
      stepSize: (json['stepSize'] as num?)?.toDouble() ?? 15.0,
      binning: (json['binning'] as num?)?.toInt() ?? 2,
      isNorth: json['isNorth'] as bool? ?? true,
      manualRotation: json['manualRotation'] as bool? ?? false,
      rotateEast: json['rotateEast'] as bool? ?? true,
      solveTimeout: (json['solveTimeout'] as num?)?.toDouble() ?? 30.0,
      autoCompleteThreshold:
          (json['autoCompleteThreshold'] as num?)?.toDouble() ?? 30.0,
      startFromCurrent: json['startFromCurrent'] as bool? ?? true,
      gain: (json['gain'] as num?)?.toInt(),
      offset: (json['offset'] as num?)?.toInt(),
    );

Map<String, dynamic> _$$PolarAlignmentConfigImplToJson(
        _$PolarAlignmentConfigImpl instance) =>
    <String, dynamic>{
      'exposureTime': instance.exposureTime,
      'stepSize': instance.stepSize,
      'binning': instance.binning,
      'isNorth': instance.isNorth,
      'manualRotation': instance.manualRotation,
      'rotateEast': instance.rotateEast,
      'solveTimeout': instance.solveTimeout,
      'autoCompleteThreshold': instance.autoCompleteThreshold,
      'startFromCurrent': instance.startFromCurrent,
      'gain': instance.gain,
      'offset': instance.offset,
    };

_$PolarAlignmentErrorImpl _$$PolarAlignmentErrorImplFromJson(
        Map<String, dynamic> json) =>
    _$PolarAlignmentErrorImpl(
      azimuthError: (json['azimuthError'] as num).toDouble(),
      altitudeError: (json['altitudeError'] as num).toDouble(),
      totalError: (json['totalError'] as num).toDouble(),
      currentRa: (json['currentRa'] as num).toDouble(),
      currentDec: (json['currentDec'] as num).toDouble(),
      targetRa: (json['targetRa'] as num).toDouble(),
      targetDec: (json['targetDec'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );

Map<String, dynamic> _$$PolarAlignmentErrorImplToJson(
        _$PolarAlignmentErrorImpl instance) =>
    <String, dynamic>{
      'azimuthError': instance.azimuthError,
      'altitudeError': instance.altitudeError,
      'totalError': instance.totalError,
      'currentRa': instance.currentRa,
      'currentDec': instance.currentDec,
      'targetRa': instance.targetRa,
      'targetDec': instance.targetDec,
      'timestamp': instance.timestamp.toIso8601String(),
    };

_$PolarAlignmentStateImpl _$$PolarAlignmentStateImplFromJson(
        Map<String, dynamic> json) =>
    _$PolarAlignmentStateImpl(
      phase: $enumDecodeNullable(_$PolarAlignPhaseEnumMap, json['phase']) ??
          PolarAlignPhase.idle,
      currentPoint: (json['currentPoint'] as num?)?.toInt() ?? 0,
      statusMessage:
          json['statusMessage'] as String? ?? 'Ready to start polar alignment',
      currentError: json['currentError'] == null
          ? null
          : PolarAlignmentError.fromJson(
              json['currentError'] as Map<String, dynamic>),
      initialError: json['initialError'] == null
          ? null
          : PolarAlignmentError.fromJson(
              json['initialError'] as Map<String, dynamic>),
      imageData: const NullableUint8ListConverter()
          .fromJson(json['imageData'] as List<int>?),
      imageWidth: (json['imageWidth'] as num?)?.toInt(),
      imageHeight: (json['imageHeight'] as num?)?.toInt(),
      solvedRa: (json['solvedRa'] as num?)?.toDouble(),
      solvedDec: (json['solvedDec'] as num?)?.toDouble(),
      errorMessage: json['errorMessage'] as String?,
      config: json['config'] == null
          ? null
          : PolarAlignmentConfig.fromJson(
              json['config'] as Map<String, dynamic>),
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
    );

Map<String, dynamic> _$$PolarAlignmentStateImplToJson(
        _$PolarAlignmentStateImpl instance) =>
    <String, dynamic>{
      'phase': _$PolarAlignPhaseEnumMap[instance.phase]!,
      'currentPoint': instance.currentPoint,
      'statusMessage': instance.statusMessage,
      'currentError': instance.currentError,
      'initialError': instance.initialError,
      'imageData':
          const NullableUint8ListConverter().toJson(instance.imageData),
      'imageWidth': instance.imageWidth,
      'imageHeight': instance.imageHeight,
      'solvedRa': instance.solvedRa,
      'solvedDec': instance.solvedDec,
      'errorMessage': instance.errorMessage,
      'config': instance.config,
      'startedAt': instance.startedAt?.toIso8601String(),
    };

const _$PolarAlignPhaseEnumMap = {
  PolarAlignPhase.idle: 'idle',
  PolarAlignPhase.measuring: 'measuring',
  PolarAlignPhase.adjusting: 'adjusting',
  PolarAlignPhase.complete: 'complete',
  PolarAlignPhase.error: 'error',
};

_$PolarAlignmentResultImpl _$$PolarAlignmentResultImplFromJson(
        Map<String, dynamic> json) =>
    _$PolarAlignmentResultImpl(
      initialError: PolarAlignmentError.fromJson(
          json['initialError'] as Map<String, dynamic>),
      finalError: PolarAlignmentError.fromJson(
          json['finalError'] as Map<String, dynamic>),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: DateTime.parse(json['completedAt'] as String),
      config:
          PolarAlignmentConfig.fromJson(json['config'] as Map<String, dynamic>),
      autoCompleted: json['autoCompleted'] as bool? ?? false,
      equipmentProfileId: json['equipmentProfileId'] as String?,
    );

Map<String, dynamic> _$$PolarAlignmentResultImplToJson(
        _$PolarAlignmentResultImpl instance) =>
    <String, dynamic>{
      'initialError': instance.initialError,
      'finalError': instance.finalError,
      'startedAt': instance.startedAt.toIso8601String(),
      'completedAt': instance.completedAt.toIso8601String(),
      'config': instance.config,
      'autoCompleted': instance.autoCompleted,
      'equipmentProfileId': instance.equipmentProfileId,
    };
