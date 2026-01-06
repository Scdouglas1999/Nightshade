// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meridian_flip_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$MeridianFlipStartingImpl _$$MeridianFlipStartingImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipStartingImpl(
      targetName: json['targetName'] as String,
      fromPierSide: $enumDecode(_$PierSideEnumMap, json['fromPierSide']),
      hourAngle: (json['hourAngle'] as num).toDouble(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipStartingImplToJson(
        _$MeridianFlipStartingImpl instance) =>
    <String, dynamic>{
      'targetName': instance.targetName,
      'fromPierSide': _$PierSideEnumMap[instance.fromPierSide]!,
      'hourAngle': instance.hourAngle,
      'runtimeType': instance.$type,
    };

const _$PierSideEnumMap = {
  PierSide.east: 'east',
  PierSide.west: 'west',
  PierSide.unknown: 'unknown',
};

_$MeridianFlipStepStartedImpl _$$MeridianFlipStepStartedImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipStepStartedImpl(
      step: $enumDecode(_$FlipStepEnumMap, json['step']),
      stepIndex: (json['stepIndex'] as num).toInt(),
      totalSteps: (json['totalSteps'] as num).toInt(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipStepStartedImplToJson(
        _$MeridianFlipStepStartedImpl instance) =>
    <String, dynamic>{
      'step': _$FlipStepEnumMap[instance.step]!,
      'stepIndex': instance.stepIndex,
      'totalSteps': instance.totalSteps,
      'runtimeType': instance.$type,
    };

const _$FlipStepEnumMap = {
  FlipStep.pausingGuider: 'pausingGuider',
  FlipStep.stoppingTracking: 'stoppingTracking',
  FlipStep.slewingToTarget: 'slewingToTarget',
  FlipStep.verifyingPierSide: 'verifyingPierSide',
  FlipStep.resumingTracking: 'resumingTracking',
  FlipStep.plateSolvingAndCentering: 'plateSolvingAndCentering',
  FlipStep.refocusing: 'refocusing',
  FlipStep.resumingGuider: 'resumingGuider',
  FlipStep.settling: 'settling',
};

_$MeridianFlipStepCompletedImpl _$$MeridianFlipStepCompletedImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipStepCompletedImpl(
      step: $enumDecode(_$FlipStepEnumMap, json['step']),
      durationSecs: (json['durationSecs'] as num?)?.toDouble(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipStepCompletedImplToJson(
        _$MeridianFlipStepCompletedImpl instance) =>
    <String, dynamic>{
      'step': _$FlipStepEnumMap[instance.step]!,
      'durationSecs': instance.durationSecs,
      'runtimeType': instance.$type,
    };

_$MeridianFlipStepFailedImpl _$$MeridianFlipStepFailedImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipStepFailedImpl(
      step: $enumDecode(_$FlipStepEnumMap, json['step']),
      error: json['error'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipStepFailedImplToJson(
        _$MeridianFlipStepFailedImpl instance) =>
    <String, dynamic>{
      'step': _$FlipStepEnumMap[instance.step]!,
      'error': instance.error,
      'runtimeType': instance.$type,
    };

_$MeridianFlipProgressImpl _$$MeridianFlipProgressImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipProgressImpl(
      percent: (json['percent'] as num).toInt(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipProgressImplToJson(
        _$MeridianFlipProgressImpl instance) =>
    <String, dynamic>{
      'percent': instance.percent,
      'runtimeType': instance.$type,
    };

_$MeridianFlipRetryScheduledImpl _$$MeridianFlipRetryScheduledImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipRetryScheduledImpl(
      attempt: (json['attempt'] as num).toInt(),
      maxAttempts: (json['maxAttempts'] as num).toInt(),
      delaySecs: (json['delaySecs'] as num).toDouble(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipRetryScheduledImplToJson(
        _$MeridianFlipRetryScheduledImpl instance) =>
    <String, dynamic>{
      'attempt': instance.attempt,
      'maxAttempts': instance.maxAttempts,
      'delaySecs': instance.delaySecs,
      'runtimeType': instance.$type,
    };

_$MeridianFlipCompletedImpl _$$MeridianFlipCompletedImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipCompletedImpl(
      newPierSide: $enumDecode(_$PierSideEnumMap, json['newPierSide']),
      durationSecs: (json['durationSecs'] as num).toDouble(),
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipCompletedImplToJson(
        _$MeridianFlipCompletedImpl instance) =>
    <String, dynamic>{
      'newPierSide': _$PierSideEnumMap[instance.newPierSide]!,
      'durationSecs': instance.durationSecs,
      'runtimeType': instance.$type,
    };

_$MeridianFlipFailedImpl _$$MeridianFlipFailedImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipFailedImpl(
      error: json['error'] as String,
      actionTaken: json['actionTaken'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipFailedImplToJson(
        _$MeridianFlipFailedImpl instance) =>
    <String, dynamic>{
      'error': instance.error,
      'actionTaken': instance.actionTaken,
      'runtimeType': instance.$type,
    };

_$MeridianFlipAbortedImpl _$$MeridianFlipAbortedImplFromJson(
        Map<String, dynamic> json) =>
    _$MeridianFlipAbortedImpl(
      reason: json['reason'] as String,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MeridianFlipAbortedImplToJson(
        _$MeridianFlipAbortedImpl instance) =>
    <String, dynamic>{
      'reason': instance.reason,
      'runtimeType': instance.$type,
    };
