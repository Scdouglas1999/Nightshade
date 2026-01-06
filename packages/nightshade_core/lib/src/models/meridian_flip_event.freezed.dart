// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'meridian_flip_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

MeridianFlipEvent _$MeridianFlipEventFromJson(Map<String, dynamic> json) {
  switch (json['runtimeType']) {
    case 'starting':
      return MeridianFlipStarting.fromJson(json);
    case 'stepStarted':
      return MeridianFlipStepStarted.fromJson(json);
    case 'stepCompleted':
      return MeridianFlipStepCompleted.fromJson(json);
    case 'stepFailed':
      return MeridianFlipStepFailed.fromJson(json);
    case 'progress':
      return MeridianFlipProgress.fromJson(json);
    case 'retryScheduled':
      return MeridianFlipRetryScheduled.fromJson(json);
    case 'completed':
      return MeridianFlipCompleted.fromJson(json);
    case 'failed':
      return MeridianFlipFailed.fromJson(json);
    case 'aborted':
      return MeridianFlipAborted.fromJson(json);

    default:
      throw CheckedFromJsonException(json, 'runtimeType', 'MeridianFlipEvent',
          'Invalid union type "${json['runtimeType']}"!');
  }
}

/// @nodoc
mixin _$MeridianFlipEvent {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) =>
      throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) =>
      throw _privateConstructorUsedError;
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MeridianFlipEventCopyWith<$Res> {
  factory $MeridianFlipEventCopyWith(
          MeridianFlipEvent value, $Res Function(MeridianFlipEvent) then) =
      _$MeridianFlipEventCopyWithImpl<$Res, MeridianFlipEvent>;
}

/// @nodoc
class _$MeridianFlipEventCopyWithImpl<$Res, $Val extends MeridianFlipEvent>
    implements $MeridianFlipEventCopyWith<$Res> {
  _$MeridianFlipEventCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;
}

/// @nodoc
abstract class _$$MeridianFlipStartingImplCopyWith<$Res> {
  factory _$$MeridianFlipStartingImplCopyWith(_$MeridianFlipStartingImpl value,
          $Res Function(_$MeridianFlipStartingImpl) then) =
      __$$MeridianFlipStartingImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String targetName, PierSide fromPierSide, double hourAngle});
}

/// @nodoc
class __$$MeridianFlipStartingImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res, _$MeridianFlipStartingImpl>
    implements _$$MeridianFlipStartingImplCopyWith<$Res> {
  __$$MeridianFlipStartingImplCopyWithImpl(_$MeridianFlipStartingImpl _value,
      $Res Function(_$MeridianFlipStartingImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? targetName = null,
    Object? fromPierSide = null,
    Object? hourAngle = null,
  }) {
    return _then(_$MeridianFlipStartingImpl(
      targetName: null == targetName
          ? _value.targetName
          : targetName // ignore: cast_nullable_to_non_nullable
              as String,
      fromPierSide: null == fromPierSide
          ? _value.fromPierSide
          : fromPierSide // ignore: cast_nullable_to_non_nullable
              as PierSide,
      hourAngle: null == hourAngle
          ? _value.hourAngle
          : hourAngle // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipStartingImpl implements MeridianFlipStarting {
  const _$MeridianFlipStartingImpl(
      {required this.targetName,
      required this.fromPierSide,
      required this.hourAngle,
      final String? $type})
      : $type = $type ?? 'starting';

  factory _$MeridianFlipStartingImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipStartingImplFromJson(json);

  @override
  final String targetName;
  @override
  final PierSide fromPierSide;
  @override
  final double hourAngle;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.starting(targetName: $targetName, fromPierSide: $fromPierSide, hourAngle: $hourAngle)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipStartingImpl &&
            (identical(other.targetName, targetName) ||
                other.targetName == targetName) &&
            (identical(other.fromPierSide, fromPierSide) ||
                other.fromPierSide == fromPierSide) &&
            (identical(other.hourAngle, hourAngle) ||
                other.hourAngle == hourAngle));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, targetName, fromPierSide, hourAngle);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipStartingImplCopyWith<_$MeridianFlipStartingImpl>
      get copyWith =>
          __$$MeridianFlipStartingImplCopyWithImpl<_$MeridianFlipStartingImpl>(
              this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return starting(targetName, fromPierSide, hourAngle);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return starting?.call(targetName, fromPierSide, hourAngle);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (starting != null) {
      return starting(targetName, fromPierSide, hourAngle);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return starting(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return starting?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (starting != null) {
      return starting(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipStartingImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipStarting implements MeridianFlipEvent {
  const factory MeridianFlipStarting(
      {required final String targetName,
      required final PierSide fromPierSide,
      required final double hourAngle}) = _$MeridianFlipStartingImpl;

  factory MeridianFlipStarting.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipStartingImpl.fromJson;

  String get targetName;
  PierSide get fromPierSide;
  double get hourAngle;
  @JsonKey(ignore: true)
  _$$MeridianFlipStartingImplCopyWith<_$MeridianFlipStartingImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MeridianFlipStepStartedImplCopyWith<$Res> {
  factory _$$MeridianFlipStepStartedImplCopyWith(
          _$MeridianFlipStepStartedImpl value,
          $Res Function(_$MeridianFlipStepStartedImpl) then) =
      __$$MeridianFlipStepStartedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({FlipStep step, int stepIndex, int totalSteps});
}

/// @nodoc
class __$$MeridianFlipStepStartedImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res, _$MeridianFlipStepStartedImpl>
    implements _$$MeridianFlipStepStartedImplCopyWith<$Res> {
  __$$MeridianFlipStepStartedImplCopyWithImpl(
      _$MeridianFlipStepStartedImpl _value,
      $Res Function(_$MeridianFlipStepStartedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? step = null,
    Object? stepIndex = null,
    Object? totalSteps = null,
  }) {
    return _then(_$MeridianFlipStepStartedImpl(
      step: null == step
          ? _value.step
          : step // ignore: cast_nullable_to_non_nullable
              as FlipStep,
      stepIndex: null == stepIndex
          ? _value.stepIndex
          : stepIndex // ignore: cast_nullable_to_non_nullable
              as int,
      totalSteps: null == totalSteps
          ? _value.totalSteps
          : totalSteps // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipStepStartedImpl implements MeridianFlipStepStarted {
  const _$MeridianFlipStepStartedImpl(
      {required this.step,
      required this.stepIndex,
      required this.totalSteps,
      final String? $type})
      : $type = $type ?? 'stepStarted';

  factory _$MeridianFlipStepStartedImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipStepStartedImplFromJson(json);

  @override
  final FlipStep step;
  @override
  final int stepIndex;
  @override
  final int totalSteps;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.stepStarted(step: $step, stepIndex: $stepIndex, totalSteps: $totalSteps)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipStepStartedImpl &&
            (identical(other.step, step) || other.step == step) &&
            (identical(other.stepIndex, stepIndex) ||
                other.stepIndex == stepIndex) &&
            (identical(other.totalSteps, totalSteps) ||
                other.totalSteps == totalSteps));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, step, stepIndex, totalSteps);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipStepStartedImplCopyWith<_$MeridianFlipStepStartedImpl>
      get copyWith => __$$MeridianFlipStepStartedImplCopyWithImpl<
          _$MeridianFlipStepStartedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return stepStarted(step, stepIndex, totalSteps);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return stepStarted?.call(step, stepIndex, totalSteps);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (stepStarted != null) {
      return stepStarted(step, stepIndex, totalSteps);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return stepStarted(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return stepStarted?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (stepStarted != null) {
      return stepStarted(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipStepStartedImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipStepStarted implements MeridianFlipEvent {
  const factory MeridianFlipStepStarted(
      {required final FlipStep step,
      required final int stepIndex,
      required final int totalSteps}) = _$MeridianFlipStepStartedImpl;

  factory MeridianFlipStepStarted.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipStepStartedImpl.fromJson;

  FlipStep get step;
  int get stepIndex;
  int get totalSteps;
  @JsonKey(ignore: true)
  _$$MeridianFlipStepStartedImplCopyWith<_$MeridianFlipStepStartedImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MeridianFlipStepCompletedImplCopyWith<$Res> {
  factory _$$MeridianFlipStepCompletedImplCopyWith(
          _$MeridianFlipStepCompletedImpl value,
          $Res Function(_$MeridianFlipStepCompletedImpl) then) =
      __$$MeridianFlipStepCompletedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({FlipStep step, double? durationSecs});
}

/// @nodoc
class __$$MeridianFlipStepCompletedImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res,
        _$MeridianFlipStepCompletedImpl>
    implements _$$MeridianFlipStepCompletedImplCopyWith<$Res> {
  __$$MeridianFlipStepCompletedImplCopyWithImpl(
      _$MeridianFlipStepCompletedImpl _value,
      $Res Function(_$MeridianFlipStepCompletedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? step = null,
    Object? durationSecs = freezed,
  }) {
    return _then(_$MeridianFlipStepCompletedImpl(
      step: null == step
          ? _value.step
          : step // ignore: cast_nullable_to_non_nullable
              as FlipStep,
      durationSecs: freezed == durationSecs
          ? _value.durationSecs
          : durationSecs // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipStepCompletedImpl implements MeridianFlipStepCompleted {
  const _$MeridianFlipStepCompletedImpl(
      {required this.step, this.durationSecs, final String? $type})
      : $type = $type ?? 'stepCompleted';

  factory _$MeridianFlipStepCompletedImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipStepCompletedImplFromJson(json);

  @override
  final FlipStep step;
  @override
  final double? durationSecs;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.stepCompleted(step: $step, durationSecs: $durationSecs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipStepCompletedImpl &&
            (identical(other.step, step) || other.step == step) &&
            (identical(other.durationSecs, durationSecs) ||
                other.durationSecs == durationSecs));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, step, durationSecs);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipStepCompletedImplCopyWith<_$MeridianFlipStepCompletedImpl>
      get copyWith => __$$MeridianFlipStepCompletedImplCopyWithImpl<
          _$MeridianFlipStepCompletedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return stepCompleted(step, durationSecs);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return stepCompleted?.call(step, durationSecs);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (stepCompleted != null) {
      return stepCompleted(step, durationSecs);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return stepCompleted(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return stepCompleted?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (stepCompleted != null) {
      return stepCompleted(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipStepCompletedImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipStepCompleted implements MeridianFlipEvent {
  const factory MeridianFlipStepCompleted(
      {required final FlipStep step,
      final double? durationSecs}) = _$MeridianFlipStepCompletedImpl;

  factory MeridianFlipStepCompleted.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipStepCompletedImpl.fromJson;

  FlipStep get step;
  double? get durationSecs;
  @JsonKey(ignore: true)
  _$$MeridianFlipStepCompletedImplCopyWith<_$MeridianFlipStepCompletedImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MeridianFlipStepFailedImplCopyWith<$Res> {
  factory _$$MeridianFlipStepFailedImplCopyWith(
          _$MeridianFlipStepFailedImpl value,
          $Res Function(_$MeridianFlipStepFailedImpl) then) =
      __$$MeridianFlipStepFailedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({FlipStep step, String error});
}

/// @nodoc
class __$$MeridianFlipStepFailedImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res, _$MeridianFlipStepFailedImpl>
    implements _$$MeridianFlipStepFailedImplCopyWith<$Res> {
  __$$MeridianFlipStepFailedImplCopyWithImpl(
      _$MeridianFlipStepFailedImpl _value,
      $Res Function(_$MeridianFlipStepFailedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? step = null,
    Object? error = null,
  }) {
    return _then(_$MeridianFlipStepFailedImpl(
      step: null == step
          ? _value.step
          : step // ignore: cast_nullable_to_non_nullable
              as FlipStep,
      error: null == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipStepFailedImpl implements MeridianFlipStepFailed {
  const _$MeridianFlipStepFailedImpl(
      {required this.step, required this.error, final String? $type})
      : $type = $type ?? 'stepFailed';

  factory _$MeridianFlipStepFailedImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipStepFailedImplFromJson(json);

  @override
  final FlipStep step;
  @override
  final String error;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.stepFailed(step: $step, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipStepFailedImpl &&
            (identical(other.step, step) || other.step == step) &&
            (identical(other.error, error) || other.error == error));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, step, error);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipStepFailedImplCopyWith<_$MeridianFlipStepFailedImpl>
      get copyWith => __$$MeridianFlipStepFailedImplCopyWithImpl<
          _$MeridianFlipStepFailedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return stepFailed(step, error);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return stepFailed?.call(step, error);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (stepFailed != null) {
      return stepFailed(step, error);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return stepFailed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return stepFailed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (stepFailed != null) {
      return stepFailed(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipStepFailedImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipStepFailed implements MeridianFlipEvent {
  const factory MeridianFlipStepFailed(
      {required final FlipStep step,
      required final String error}) = _$MeridianFlipStepFailedImpl;

  factory MeridianFlipStepFailed.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipStepFailedImpl.fromJson;

  FlipStep get step;
  String get error;
  @JsonKey(ignore: true)
  _$$MeridianFlipStepFailedImplCopyWith<_$MeridianFlipStepFailedImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MeridianFlipProgressImplCopyWith<$Res> {
  factory _$$MeridianFlipProgressImplCopyWith(_$MeridianFlipProgressImpl value,
          $Res Function(_$MeridianFlipProgressImpl) then) =
      __$$MeridianFlipProgressImplCopyWithImpl<$Res>;
  @useResult
  $Res call({int percent});
}

/// @nodoc
class __$$MeridianFlipProgressImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res, _$MeridianFlipProgressImpl>
    implements _$$MeridianFlipProgressImplCopyWith<$Res> {
  __$$MeridianFlipProgressImplCopyWithImpl(_$MeridianFlipProgressImpl _value,
      $Res Function(_$MeridianFlipProgressImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? percent = null,
  }) {
    return _then(_$MeridianFlipProgressImpl(
      percent: null == percent
          ? _value.percent
          : percent // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipProgressImpl implements MeridianFlipProgress {
  const _$MeridianFlipProgressImpl({required this.percent, final String? $type})
      : $type = $type ?? 'progress';

  factory _$MeridianFlipProgressImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipProgressImplFromJson(json);

  @override
  final int percent;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.progress(percent: $percent)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipProgressImpl &&
            (identical(other.percent, percent) || other.percent == percent));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, percent);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipProgressImplCopyWith<_$MeridianFlipProgressImpl>
      get copyWith =>
          __$$MeridianFlipProgressImplCopyWithImpl<_$MeridianFlipProgressImpl>(
              this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return progress(percent);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return progress?.call(percent);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (progress != null) {
      return progress(percent);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return progress(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return progress?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (progress != null) {
      return progress(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipProgressImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipProgress implements MeridianFlipEvent {
  const factory MeridianFlipProgress({required final int percent}) =
      _$MeridianFlipProgressImpl;

  factory MeridianFlipProgress.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipProgressImpl.fromJson;

  int get percent;
  @JsonKey(ignore: true)
  _$$MeridianFlipProgressImplCopyWith<_$MeridianFlipProgressImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MeridianFlipRetryScheduledImplCopyWith<$Res> {
  factory _$$MeridianFlipRetryScheduledImplCopyWith(
          _$MeridianFlipRetryScheduledImpl value,
          $Res Function(_$MeridianFlipRetryScheduledImpl) then) =
      __$$MeridianFlipRetryScheduledImplCopyWithImpl<$Res>;
  @useResult
  $Res call({int attempt, int maxAttempts, double delaySecs});
}

/// @nodoc
class __$$MeridianFlipRetryScheduledImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res,
        _$MeridianFlipRetryScheduledImpl>
    implements _$$MeridianFlipRetryScheduledImplCopyWith<$Res> {
  __$$MeridianFlipRetryScheduledImplCopyWithImpl(
      _$MeridianFlipRetryScheduledImpl _value,
      $Res Function(_$MeridianFlipRetryScheduledImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? attempt = null,
    Object? maxAttempts = null,
    Object? delaySecs = null,
  }) {
    return _then(_$MeridianFlipRetryScheduledImpl(
      attempt: null == attempt
          ? _value.attempt
          : attempt // ignore: cast_nullable_to_non_nullable
              as int,
      maxAttempts: null == maxAttempts
          ? _value.maxAttempts
          : maxAttempts // ignore: cast_nullable_to_non_nullable
              as int,
      delaySecs: null == delaySecs
          ? _value.delaySecs
          : delaySecs // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipRetryScheduledImpl implements MeridianFlipRetryScheduled {
  const _$MeridianFlipRetryScheduledImpl(
      {required this.attempt,
      required this.maxAttempts,
      required this.delaySecs,
      final String? $type})
      : $type = $type ?? 'retryScheduled';

  factory _$MeridianFlipRetryScheduledImpl.fromJson(
          Map<String, dynamic> json) =>
      _$$MeridianFlipRetryScheduledImplFromJson(json);

  @override
  final int attempt;
  @override
  final int maxAttempts;
  @override
  final double delaySecs;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.retryScheduled(attempt: $attempt, maxAttempts: $maxAttempts, delaySecs: $delaySecs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipRetryScheduledImpl &&
            (identical(other.attempt, attempt) || other.attempt == attempt) &&
            (identical(other.maxAttempts, maxAttempts) ||
                other.maxAttempts == maxAttempts) &&
            (identical(other.delaySecs, delaySecs) ||
                other.delaySecs == delaySecs));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, attempt, maxAttempts, delaySecs);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipRetryScheduledImplCopyWith<_$MeridianFlipRetryScheduledImpl>
      get copyWith => __$$MeridianFlipRetryScheduledImplCopyWithImpl<
          _$MeridianFlipRetryScheduledImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return retryScheduled(attempt, maxAttempts, delaySecs);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return retryScheduled?.call(attempt, maxAttempts, delaySecs);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (retryScheduled != null) {
      return retryScheduled(attempt, maxAttempts, delaySecs);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return retryScheduled(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return retryScheduled?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (retryScheduled != null) {
      return retryScheduled(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipRetryScheduledImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipRetryScheduled implements MeridianFlipEvent {
  const factory MeridianFlipRetryScheduled(
      {required final int attempt,
      required final int maxAttempts,
      required final double delaySecs}) = _$MeridianFlipRetryScheduledImpl;

  factory MeridianFlipRetryScheduled.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipRetryScheduledImpl.fromJson;

  int get attempt;
  int get maxAttempts;
  double get delaySecs;
  @JsonKey(ignore: true)
  _$$MeridianFlipRetryScheduledImplCopyWith<_$MeridianFlipRetryScheduledImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MeridianFlipCompletedImplCopyWith<$Res> {
  factory _$$MeridianFlipCompletedImplCopyWith(
          _$MeridianFlipCompletedImpl value,
          $Res Function(_$MeridianFlipCompletedImpl) then) =
      __$$MeridianFlipCompletedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({PierSide newPierSide, double durationSecs});
}

/// @nodoc
class __$$MeridianFlipCompletedImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res, _$MeridianFlipCompletedImpl>
    implements _$$MeridianFlipCompletedImplCopyWith<$Res> {
  __$$MeridianFlipCompletedImplCopyWithImpl(_$MeridianFlipCompletedImpl _value,
      $Res Function(_$MeridianFlipCompletedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? newPierSide = null,
    Object? durationSecs = null,
  }) {
    return _then(_$MeridianFlipCompletedImpl(
      newPierSide: null == newPierSide
          ? _value.newPierSide
          : newPierSide // ignore: cast_nullable_to_non_nullable
              as PierSide,
      durationSecs: null == durationSecs
          ? _value.durationSecs
          : durationSecs // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipCompletedImpl implements MeridianFlipCompleted {
  const _$MeridianFlipCompletedImpl(
      {required this.newPierSide,
      required this.durationSecs,
      final String? $type})
      : $type = $type ?? 'completed';

  factory _$MeridianFlipCompletedImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipCompletedImplFromJson(json);

  @override
  final PierSide newPierSide;
  @override
  final double durationSecs;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.completed(newPierSide: $newPierSide, durationSecs: $durationSecs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipCompletedImpl &&
            (identical(other.newPierSide, newPierSide) ||
                other.newPierSide == newPierSide) &&
            (identical(other.durationSecs, durationSecs) ||
                other.durationSecs == durationSecs));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, newPierSide, durationSecs);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipCompletedImplCopyWith<_$MeridianFlipCompletedImpl>
      get copyWith => __$$MeridianFlipCompletedImplCopyWithImpl<
          _$MeridianFlipCompletedImpl>(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return completed(newPierSide, durationSecs);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return completed?.call(newPierSide, durationSecs);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed(newPierSide, durationSecs);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return completed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return completed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (completed != null) {
      return completed(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipCompletedImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipCompleted implements MeridianFlipEvent {
  const factory MeridianFlipCompleted(
      {required final PierSide newPierSide,
      required final double durationSecs}) = _$MeridianFlipCompletedImpl;

  factory MeridianFlipCompleted.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipCompletedImpl.fromJson;

  PierSide get newPierSide;
  double get durationSecs;
  @JsonKey(ignore: true)
  _$$MeridianFlipCompletedImplCopyWith<_$MeridianFlipCompletedImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MeridianFlipFailedImplCopyWith<$Res> {
  factory _$$MeridianFlipFailedImplCopyWith(_$MeridianFlipFailedImpl value,
          $Res Function(_$MeridianFlipFailedImpl) then) =
      __$$MeridianFlipFailedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String error, String actionTaken});
}

/// @nodoc
class __$$MeridianFlipFailedImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res, _$MeridianFlipFailedImpl>
    implements _$$MeridianFlipFailedImplCopyWith<$Res> {
  __$$MeridianFlipFailedImplCopyWithImpl(_$MeridianFlipFailedImpl _value,
      $Res Function(_$MeridianFlipFailedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? error = null,
    Object? actionTaken = null,
  }) {
    return _then(_$MeridianFlipFailedImpl(
      error: null == error
          ? _value.error
          : error // ignore: cast_nullable_to_non_nullable
              as String,
      actionTaken: null == actionTaken
          ? _value.actionTaken
          : actionTaken // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipFailedImpl implements MeridianFlipFailed {
  const _$MeridianFlipFailedImpl(
      {required this.error, required this.actionTaken, final String? $type})
      : $type = $type ?? 'failed';

  factory _$MeridianFlipFailedImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipFailedImplFromJson(json);

  @override
  final String error;
  @override
  final String actionTaken;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.failed(error: $error, actionTaken: $actionTaken)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipFailedImpl &&
            (identical(other.error, error) || other.error == error) &&
            (identical(other.actionTaken, actionTaken) ||
                other.actionTaken == actionTaken));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, error, actionTaken);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipFailedImplCopyWith<_$MeridianFlipFailedImpl> get copyWith =>
      __$$MeridianFlipFailedImplCopyWithImpl<_$MeridianFlipFailedImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return failed(error, actionTaken);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return failed?.call(error, actionTaken);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (failed != null) {
      return failed(error, actionTaken);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return failed(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return failed?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (failed != null) {
      return failed(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipFailedImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipFailed implements MeridianFlipEvent {
  const factory MeridianFlipFailed(
      {required final String error,
      required final String actionTaken}) = _$MeridianFlipFailedImpl;

  factory MeridianFlipFailed.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipFailedImpl.fromJson;

  String get error;
  String get actionTaken;
  @JsonKey(ignore: true)
  _$$MeridianFlipFailedImplCopyWith<_$MeridianFlipFailedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MeridianFlipAbortedImplCopyWith<$Res> {
  factory _$$MeridianFlipAbortedImplCopyWith(_$MeridianFlipAbortedImpl value,
          $Res Function(_$MeridianFlipAbortedImpl) then) =
      __$$MeridianFlipAbortedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String reason});
}

/// @nodoc
class __$$MeridianFlipAbortedImplCopyWithImpl<$Res>
    extends _$MeridianFlipEventCopyWithImpl<$Res, _$MeridianFlipAbortedImpl>
    implements _$$MeridianFlipAbortedImplCopyWith<$Res> {
  __$$MeridianFlipAbortedImplCopyWithImpl(_$MeridianFlipAbortedImpl _value,
      $Res Function(_$MeridianFlipAbortedImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? reason = null,
  }) {
    return _then(_$MeridianFlipAbortedImpl(
      reason: null == reason
          ? _value.reason
          : reason // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$MeridianFlipAbortedImpl implements MeridianFlipAborted {
  const _$MeridianFlipAbortedImpl({required this.reason, final String? $type})
      : $type = $type ?? 'aborted';

  factory _$MeridianFlipAbortedImpl.fromJson(Map<String, dynamic> json) =>
      _$$MeridianFlipAbortedImplFromJson(json);

  @override
  final String reason;

  @JsonKey(name: 'runtimeType')
  final String $type;

  @override
  String toString() {
    return 'MeridianFlipEvent.aborted(reason: $reason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MeridianFlipAbortedImpl &&
            (identical(other.reason, reason) || other.reason == reason));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, reason);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MeridianFlipAbortedImplCopyWith<_$MeridianFlipAbortedImpl> get copyWith =>
      __$$MeridianFlipAbortedImplCopyWithImpl<_$MeridianFlipAbortedImpl>(
          this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)
        starting,
    required TResult Function(FlipStep step, int stepIndex, int totalSteps)
        stepStarted,
    required TResult Function(FlipStep step, double? durationSecs)
        stepCompleted,
    required TResult Function(FlipStep step, String error) stepFailed,
    required TResult Function(int percent) progress,
    required TResult Function(int attempt, int maxAttempts, double delaySecs)
        retryScheduled,
    required TResult Function(PierSide newPierSide, double durationSecs)
        completed,
    required TResult Function(String error, String actionTaken) failed,
    required TResult Function(String reason) aborted,
  }) {
    return aborted(reason);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult? Function(FlipStep step, int stepIndex, int totalSteps)?
        stepStarted,
    TResult? Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult? Function(FlipStep step, String error)? stepFailed,
    TResult? Function(int percent)? progress,
    TResult? Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult? Function(PierSide newPierSide, double durationSecs)? completed,
    TResult? Function(String error, String actionTaken)? failed,
    TResult? Function(String reason)? aborted,
  }) {
    return aborted?.call(reason);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(
            String targetName, PierSide fromPierSide, double hourAngle)?
        starting,
    TResult Function(FlipStep step, int stepIndex, int totalSteps)? stepStarted,
    TResult Function(FlipStep step, double? durationSecs)? stepCompleted,
    TResult Function(FlipStep step, String error)? stepFailed,
    TResult Function(int percent)? progress,
    TResult Function(int attempt, int maxAttempts, double delaySecs)?
        retryScheduled,
    TResult Function(PierSide newPierSide, double durationSecs)? completed,
    TResult Function(String error, String actionTaken)? failed,
    TResult Function(String reason)? aborted,
    required TResult orElse(),
  }) {
    if (aborted != null) {
      return aborted(reason);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MeridianFlipStarting value) starting,
    required TResult Function(MeridianFlipStepStarted value) stepStarted,
    required TResult Function(MeridianFlipStepCompleted value) stepCompleted,
    required TResult Function(MeridianFlipStepFailed value) stepFailed,
    required TResult Function(MeridianFlipProgress value) progress,
    required TResult Function(MeridianFlipRetryScheduled value) retryScheduled,
    required TResult Function(MeridianFlipCompleted value) completed,
    required TResult Function(MeridianFlipFailed value) failed,
    required TResult Function(MeridianFlipAborted value) aborted,
  }) {
    return aborted(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MeridianFlipStarting value)? starting,
    TResult? Function(MeridianFlipStepStarted value)? stepStarted,
    TResult? Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult? Function(MeridianFlipStepFailed value)? stepFailed,
    TResult? Function(MeridianFlipProgress value)? progress,
    TResult? Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult? Function(MeridianFlipCompleted value)? completed,
    TResult? Function(MeridianFlipFailed value)? failed,
    TResult? Function(MeridianFlipAborted value)? aborted,
  }) {
    return aborted?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MeridianFlipStarting value)? starting,
    TResult Function(MeridianFlipStepStarted value)? stepStarted,
    TResult Function(MeridianFlipStepCompleted value)? stepCompleted,
    TResult Function(MeridianFlipStepFailed value)? stepFailed,
    TResult Function(MeridianFlipProgress value)? progress,
    TResult Function(MeridianFlipRetryScheduled value)? retryScheduled,
    TResult Function(MeridianFlipCompleted value)? completed,
    TResult Function(MeridianFlipFailed value)? failed,
    TResult Function(MeridianFlipAborted value)? aborted,
    required TResult orElse(),
  }) {
    if (aborted != null) {
      return aborted(this);
    }
    return orElse();
  }

  @override
  Map<String, dynamic> toJson() {
    return _$$MeridianFlipAbortedImplToJson(
      this,
    );
  }
}

abstract class MeridianFlipAborted implements MeridianFlipEvent {
  const factory MeridianFlipAborted({required final String reason}) =
      _$MeridianFlipAbortedImpl;

  factory MeridianFlipAborted.fromJson(Map<String, dynamic> json) =
      _$MeridianFlipAbortedImpl.fromJson;

  String get reason;
  @JsonKey(ignore: true)
  _$$MeridianFlipAbortedImplCopyWith<_$MeridianFlipAbortedImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
