// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sequence_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

/// @nodoc
mixin _$SequenceOverheadConfig {
  /// Time for a slew operation (seconds)
  double get slewSecs => throw _privateConstructorUsedError;

  /// Time for an autofocus run (seconds)
  double get autofocusSecs => throw _privateConstructorUsedError;

  /// Time for a filter wheel change (seconds)
  double get filterChangeSecs => throw _privateConstructorUsedError;

  /// Time for a dither + settle cycle (seconds)
  double get ditherSecs => throw _privateConstructorUsedError;

  /// Time for a meridian flip including re-centering (seconds)
  double get meridianFlipSecs => throw _privateConstructorUsedError;

  /// Time for guide acquisition and settle (seconds)
  double get guideAcquireSecs => throw _privateConstructorUsedError;

  /// Time for a plate solve (seconds)
  double get plateSolveSecs => throw _privateConstructorUsedError;

  /// Time for camera cool-down (seconds)
  double get coolingSecs => throw _privateConstructorUsedError;

  /// Time for camera warm-up (seconds)
  double get warmingSecs => throw _privateConstructorUsedError;

  /// Per-exposure download overhead (seconds)
  double get downloadOverheadPerExposureSecs =>
      throw _privateConstructorUsedError;

  /// Time for cover calibrator open/close (seconds)
  double get coverMoveSecs => throw _privateConstructorUsedError;

  /// Time for center target operation (plate solve + slew iterations) (seconds)
  double get centerTargetSecs => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $SequenceOverheadConfigCopyWith<SequenceOverheadConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SequenceOverheadConfigCopyWith<$Res> {
  factory $SequenceOverheadConfigCopyWith(SequenceOverheadConfig value,
          $Res Function(SequenceOverheadConfig) then) =
      _$SequenceOverheadConfigCopyWithImpl<$Res, SequenceOverheadConfig>;
  @useResult
  $Res call(
      {double slewSecs,
      double autofocusSecs,
      double filterChangeSecs,
      double ditherSecs,
      double meridianFlipSecs,
      double guideAcquireSecs,
      double plateSolveSecs,
      double coolingSecs,
      double warmingSecs,
      double downloadOverheadPerExposureSecs,
      double coverMoveSecs,
      double centerTargetSecs});
}

/// @nodoc
class _$SequenceOverheadConfigCopyWithImpl<$Res,
        $Val extends SequenceOverheadConfig>
    implements $SequenceOverheadConfigCopyWith<$Res> {
  _$SequenceOverheadConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? slewSecs = null,
    Object? autofocusSecs = null,
    Object? filterChangeSecs = null,
    Object? ditherSecs = null,
    Object? meridianFlipSecs = null,
    Object? guideAcquireSecs = null,
    Object? plateSolveSecs = null,
    Object? coolingSecs = null,
    Object? warmingSecs = null,
    Object? downloadOverheadPerExposureSecs = null,
    Object? coverMoveSecs = null,
    Object? centerTargetSecs = null,
  }) {
    return _then(_value.copyWith(
      slewSecs: null == slewSecs
          ? _value.slewSecs
          : slewSecs // ignore: cast_nullable_to_non_nullable
              as double,
      autofocusSecs: null == autofocusSecs
          ? _value.autofocusSecs
          : autofocusSecs // ignore: cast_nullable_to_non_nullable
              as double,
      filterChangeSecs: null == filterChangeSecs
          ? _value.filterChangeSecs
          : filterChangeSecs // ignore: cast_nullable_to_non_nullable
              as double,
      ditherSecs: null == ditherSecs
          ? _value.ditherSecs
          : ditherSecs // ignore: cast_nullable_to_non_nullable
              as double,
      meridianFlipSecs: null == meridianFlipSecs
          ? _value.meridianFlipSecs
          : meridianFlipSecs // ignore: cast_nullable_to_non_nullable
              as double,
      guideAcquireSecs: null == guideAcquireSecs
          ? _value.guideAcquireSecs
          : guideAcquireSecs // ignore: cast_nullable_to_non_nullable
              as double,
      plateSolveSecs: null == plateSolveSecs
          ? _value.plateSolveSecs
          : plateSolveSecs // ignore: cast_nullable_to_non_nullable
              as double,
      coolingSecs: null == coolingSecs
          ? _value.coolingSecs
          : coolingSecs // ignore: cast_nullable_to_non_nullable
              as double,
      warmingSecs: null == warmingSecs
          ? _value.warmingSecs
          : warmingSecs // ignore: cast_nullable_to_non_nullable
              as double,
      downloadOverheadPerExposureSecs: null == downloadOverheadPerExposureSecs
          ? _value.downloadOverheadPerExposureSecs
          : downloadOverheadPerExposureSecs // ignore: cast_nullable_to_non_nullable
              as double,
      coverMoveSecs: null == coverMoveSecs
          ? _value.coverMoveSecs
          : coverMoveSecs // ignore: cast_nullable_to_non_nullable
              as double,
      centerTargetSecs: null == centerTargetSecs
          ? _value.centerTargetSecs
          : centerTargetSecs // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SequenceOverheadConfigImplCopyWith<$Res>
    implements $SequenceOverheadConfigCopyWith<$Res> {
  factory _$$SequenceOverheadConfigImplCopyWith(
          _$SequenceOverheadConfigImpl value,
          $Res Function(_$SequenceOverheadConfigImpl) then) =
      __$$SequenceOverheadConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double slewSecs,
      double autofocusSecs,
      double filterChangeSecs,
      double ditherSecs,
      double meridianFlipSecs,
      double guideAcquireSecs,
      double plateSolveSecs,
      double coolingSecs,
      double warmingSecs,
      double downloadOverheadPerExposureSecs,
      double coverMoveSecs,
      double centerTargetSecs});
}

/// @nodoc
class __$$SequenceOverheadConfigImplCopyWithImpl<$Res>
    extends _$SequenceOverheadConfigCopyWithImpl<$Res,
        _$SequenceOverheadConfigImpl>
    implements _$$SequenceOverheadConfigImplCopyWith<$Res> {
  __$$SequenceOverheadConfigImplCopyWithImpl(
      _$SequenceOverheadConfigImpl _value,
      $Res Function(_$SequenceOverheadConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? slewSecs = null,
    Object? autofocusSecs = null,
    Object? filterChangeSecs = null,
    Object? ditherSecs = null,
    Object? meridianFlipSecs = null,
    Object? guideAcquireSecs = null,
    Object? plateSolveSecs = null,
    Object? coolingSecs = null,
    Object? warmingSecs = null,
    Object? downloadOverheadPerExposureSecs = null,
    Object? coverMoveSecs = null,
    Object? centerTargetSecs = null,
  }) {
    return _then(_$SequenceOverheadConfigImpl(
      slewSecs: null == slewSecs
          ? _value.slewSecs
          : slewSecs // ignore: cast_nullable_to_non_nullable
              as double,
      autofocusSecs: null == autofocusSecs
          ? _value.autofocusSecs
          : autofocusSecs // ignore: cast_nullable_to_non_nullable
              as double,
      filterChangeSecs: null == filterChangeSecs
          ? _value.filterChangeSecs
          : filterChangeSecs // ignore: cast_nullable_to_non_nullable
              as double,
      ditherSecs: null == ditherSecs
          ? _value.ditherSecs
          : ditherSecs // ignore: cast_nullable_to_non_nullable
              as double,
      meridianFlipSecs: null == meridianFlipSecs
          ? _value.meridianFlipSecs
          : meridianFlipSecs // ignore: cast_nullable_to_non_nullable
              as double,
      guideAcquireSecs: null == guideAcquireSecs
          ? _value.guideAcquireSecs
          : guideAcquireSecs // ignore: cast_nullable_to_non_nullable
              as double,
      plateSolveSecs: null == plateSolveSecs
          ? _value.plateSolveSecs
          : plateSolveSecs // ignore: cast_nullable_to_non_nullable
              as double,
      coolingSecs: null == coolingSecs
          ? _value.coolingSecs
          : coolingSecs // ignore: cast_nullable_to_non_nullable
              as double,
      warmingSecs: null == warmingSecs
          ? _value.warmingSecs
          : warmingSecs // ignore: cast_nullable_to_non_nullable
              as double,
      downloadOverheadPerExposureSecs: null == downloadOverheadPerExposureSecs
          ? _value.downloadOverheadPerExposureSecs
          : downloadOverheadPerExposureSecs // ignore: cast_nullable_to_non_nullable
              as double,
      coverMoveSecs: null == coverMoveSecs
          ? _value.coverMoveSecs
          : coverMoveSecs // ignore: cast_nullable_to_non_nullable
              as double,
      centerTargetSecs: null == centerTargetSecs
          ? _value.centerTargetSecs
          : centerTargetSecs // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc

class _$SequenceOverheadConfigImpl implements _SequenceOverheadConfig {
  const _$SequenceOverheadConfigImpl(
      {this.slewSecs = 30.0,
      this.autofocusSecs = 180.0,
      this.filterChangeSecs = 10.0,
      this.ditherSecs = 15.0,
      this.meridianFlipSecs = 300.0,
      this.guideAcquireSecs = 30.0,
      this.plateSolveSecs = 15.0,
      this.coolingSecs = 600.0,
      this.warmingSecs = 300.0,
      this.downloadOverheadPerExposureSecs = 3.0,
      this.coverMoveSecs = 30.0,
      this.centerTargetSecs = 45.0});

  /// Time for a slew operation (seconds)
  @override
  @JsonKey()
  final double slewSecs;

  /// Time for an autofocus run (seconds)
  @override
  @JsonKey()
  final double autofocusSecs;

  /// Time for a filter wheel change (seconds)
  @override
  @JsonKey()
  final double filterChangeSecs;

  /// Time for a dither + settle cycle (seconds)
  @override
  @JsonKey()
  final double ditherSecs;

  /// Time for a meridian flip including re-centering (seconds)
  @override
  @JsonKey()
  final double meridianFlipSecs;

  /// Time for guide acquisition and settle (seconds)
  @override
  @JsonKey()
  final double guideAcquireSecs;

  /// Time for a plate solve (seconds)
  @override
  @JsonKey()
  final double plateSolveSecs;

  /// Time for camera cool-down (seconds)
  @override
  @JsonKey()
  final double coolingSecs;

  /// Time for camera warm-up (seconds)
  @override
  @JsonKey()
  final double warmingSecs;

  /// Per-exposure download overhead (seconds)
  @override
  @JsonKey()
  final double downloadOverheadPerExposureSecs;

  /// Time for cover calibrator open/close (seconds)
  @override
  @JsonKey()
  final double coverMoveSecs;

  /// Time for center target operation (plate solve + slew iterations) (seconds)
  @override
  @JsonKey()
  final double centerTargetSecs;

  @override
  String toString() {
    return 'SequenceOverheadConfig(slewSecs: $slewSecs, autofocusSecs: $autofocusSecs, filterChangeSecs: $filterChangeSecs, ditherSecs: $ditherSecs, meridianFlipSecs: $meridianFlipSecs, guideAcquireSecs: $guideAcquireSecs, plateSolveSecs: $plateSolveSecs, coolingSecs: $coolingSecs, warmingSecs: $warmingSecs, downloadOverheadPerExposureSecs: $downloadOverheadPerExposureSecs, coverMoveSecs: $coverMoveSecs, centerTargetSecs: $centerTargetSecs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SequenceOverheadConfigImpl &&
            (identical(other.slewSecs, slewSecs) ||
                other.slewSecs == slewSecs) &&
            (identical(other.autofocusSecs, autofocusSecs) ||
                other.autofocusSecs == autofocusSecs) &&
            (identical(other.filterChangeSecs, filterChangeSecs) ||
                other.filterChangeSecs == filterChangeSecs) &&
            (identical(other.ditherSecs, ditherSecs) ||
                other.ditherSecs == ditherSecs) &&
            (identical(other.meridianFlipSecs, meridianFlipSecs) ||
                other.meridianFlipSecs == meridianFlipSecs) &&
            (identical(other.guideAcquireSecs, guideAcquireSecs) ||
                other.guideAcquireSecs == guideAcquireSecs) &&
            (identical(other.plateSolveSecs, plateSolveSecs) ||
                other.plateSolveSecs == plateSolveSecs) &&
            (identical(other.coolingSecs, coolingSecs) ||
                other.coolingSecs == coolingSecs) &&
            (identical(other.warmingSecs, warmingSecs) ||
                other.warmingSecs == warmingSecs) &&
            (identical(other.downloadOverheadPerExposureSecs,
                    downloadOverheadPerExposureSecs) ||
                other.downloadOverheadPerExposureSecs ==
                    downloadOverheadPerExposureSecs) &&
            (identical(other.coverMoveSecs, coverMoveSecs) ||
                other.coverMoveSecs == coverMoveSecs) &&
            (identical(other.centerTargetSecs, centerTargetSecs) ||
                other.centerTargetSecs == centerTargetSecs));
  }

  @override
  int get hashCode => Object.hash(
      runtimeType,
      slewSecs,
      autofocusSecs,
      filterChangeSecs,
      ditherSecs,
      meridianFlipSecs,
      guideAcquireSecs,
      plateSolveSecs,
      coolingSecs,
      warmingSecs,
      downloadOverheadPerExposureSecs,
      coverMoveSecs,
      centerTargetSecs);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SequenceOverheadConfigImplCopyWith<_$SequenceOverheadConfigImpl>
      get copyWith => __$$SequenceOverheadConfigImplCopyWithImpl<
          _$SequenceOverheadConfigImpl>(this, _$identity);
}

abstract class _SequenceOverheadConfig implements SequenceOverheadConfig {
  const factory _SequenceOverheadConfig(
      {final double slewSecs,
      final double autofocusSecs,
      final double filterChangeSecs,
      final double ditherSecs,
      final double meridianFlipSecs,
      final double guideAcquireSecs,
      final double plateSolveSecs,
      final double coolingSecs,
      final double warmingSecs,
      final double downloadOverheadPerExposureSecs,
      final double coverMoveSecs,
      final double centerTargetSecs}) = _$SequenceOverheadConfigImpl;

  @override

  /// Time for a slew operation (seconds)
  double get slewSecs;
  @override

  /// Time for an autofocus run (seconds)
  double get autofocusSecs;
  @override

  /// Time for a filter wheel change (seconds)
  double get filterChangeSecs;
  @override

  /// Time for a dither + settle cycle (seconds)
  double get ditherSecs;
  @override

  /// Time for a meridian flip including re-centering (seconds)
  double get meridianFlipSecs;
  @override

  /// Time for guide acquisition and settle (seconds)
  double get guideAcquireSecs;
  @override

  /// Time for a plate solve (seconds)
  double get plateSolveSecs;
  @override

  /// Time for camera cool-down (seconds)
  double get coolingSecs;
  @override

  /// Time for camera warm-up (seconds)
  double get warmingSecs;
  @override

  /// Per-exposure download overhead (seconds)
  double get downloadOverheadPerExposureSecs;
  @override

  /// Time for cover calibrator open/close (seconds)
  double get coverMoveSecs;
  @override

  /// Time for center target operation (plate solve + slew iterations) (seconds)
  double get centerTargetSecs;
  @override
  @JsonKey(ignore: true)
  _$$SequenceOverheadConfigImplCopyWith<_$SequenceOverheadConfigImpl>
      get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SequenceEstimate {
  /// Estimated total integration time in seconds (pure shutter-open time)
  double get estimatedSecs => throw _privateConstructorUsedError;

  /// Estimated total overhead time in seconds (slews, AF, dithers, etc.)
  double get overheadSecs => throw _privateConstructorUsedError;

  /// Time for a single iteration (useful for unbounded loops)
  double get singleIterationSecs => throw _privateConstructorUsedError;

  /// Whether the sequence contains unbounded loops (forever, whileDark, etc.)
  bool get isUnbounded => throw _privateConstructorUsedError;

  /// For untilTime loops, the target end time
  DateTime? get untilTime => throw _privateConstructorUsedError;

  /// For unbounded loops, the condition type
  LoopConditionType? get conditionType => throw _privateConstructorUsedError;

  @JsonKey(ignore: true)
  $SequenceEstimateCopyWith<SequenceEstimate> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SequenceEstimateCopyWith<$Res> {
  factory $SequenceEstimateCopyWith(
          SequenceEstimate value, $Res Function(SequenceEstimate) then) =
      _$SequenceEstimateCopyWithImpl<$Res, SequenceEstimate>;
  @useResult
  $Res call(
      {double estimatedSecs,
      double overheadSecs,
      double singleIterationSecs,
      bool isUnbounded,
      DateTime? untilTime,
      LoopConditionType? conditionType});
}

/// @nodoc
class _$SequenceEstimateCopyWithImpl<$Res, $Val extends SequenceEstimate>
    implements $SequenceEstimateCopyWith<$Res> {
  _$SequenceEstimateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? estimatedSecs = null,
    Object? overheadSecs = null,
    Object? singleIterationSecs = null,
    Object? isUnbounded = null,
    Object? untilTime = freezed,
    Object? conditionType = freezed,
  }) {
    return _then(_value.copyWith(
      estimatedSecs: null == estimatedSecs
          ? _value.estimatedSecs
          : estimatedSecs // ignore: cast_nullable_to_non_nullable
              as double,
      overheadSecs: null == overheadSecs
          ? _value.overheadSecs
          : overheadSecs // ignore: cast_nullable_to_non_nullable
              as double,
      singleIterationSecs: null == singleIterationSecs
          ? _value.singleIterationSecs
          : singleIterationSecs // ignore: cast_nullable_to_non_nullable
              as double,
      isUnbounded: null == isUnbounded
          ? _value.isUnbounded
          : isUnbounded // ignore: cast_nullable_to_non_nullable
              as bool,
      untilTime: freezed == untilTime
          ? _value.untilTime
          : untilTime // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      conditionType: freezed == conditionType
          ? _value.conditionType
          : conditionType // ignore: cast_nullable_to_non_nullable
              as LoopConditionType?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$SequenceEstimateImplCopyWith<$Res>
    implements $SequenceEstimateCopyWith<$Res> {
  factory _$$SequenceEstimateImplCopyWith(_$SequenceEstimateImpl value,
          $Res Function(_$SequenceEstimateImpl) then) =
      __$$SequenceEstimateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double estimatedSecs,
      double overheadSecs,
      double singleIterationSecs,
      bool isUnbounded,
      DateTime? untilTime,
      LoopConditionType? conditionType});
}

/// @nodoc
class __$$SequenceEstimateImplCopyWithImpl<$Res>
    extends _$SequenceEstimateCopyWithImpl<$Res, _$SequenceEstimateImpl>
    implements _$$SequenceEstimateImplCopyWith<$Res> {
  __$$SequenceEstimateImplCopyWithImpl(_$SequenceEstimateImpl _value,
      $Res Function(_$SequenceEstimateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? estimatedSecs = null,
    Object? overheadSecs = null,
    Object? singleIterationSecs = null,
    Object? isUnbounded = null,
    Object? untilTime = freezed,
    Object? conditionType = freezed,
  }) {
    return _then(_$SequenceEstimateImpl(
      estimatedSecs: null == estimatedSecs
          ? _value.estimatedSecs
          : estimatedSecs // ignore: cast_nullable_to_non_nullable
              as double,
      overheadSecs: null == overheadSecs
          ? _value.overheadSecs
          : overheadSecs // ignore: cast_nullable_to_non_nullable
              as double,
      singleIterationSecs: null == singleIterationSecs
          ? _value.singleIterationSecs
          : singleIterationSecs // ignore: cast_nullable_to_non_nullable
              as double,
      isUnbounded: null == isUnbounded
          ? _value.isUnbounded
          : isUnbounded // ignore: cast_nullable_to_non_nullable
              as bool,
      untilTime: freezed == untilTime
          ? _value.untilTime
          : untilTime // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      conditionType: freezed == conditionType
          ? _value.conditionType
          : conditionType // ignore: cast_nullable_to_non_nullable
              as LoopConditionType?,
    ));
  }
}

/// @nodoc

class _$SequenceEstimateImpl extends _SequenceEstimate {
  const _$SequenceEstimateImpl(
      {required this.estimatedSecs,
      this.overheadSecs = 0.0,
      required this.singleIterationSecs,
      required this.isUnbounded,
      this.untilTime,
      this.conditionType})
      : super._();

  /// Estimated total integration time in seconds (pure shutter-open time)
  @override
  final double estimatedSecs;

  /// Estimated total overhead time in seconds (slews, AF, dithers, etc.)
  @override
  @JsonKey()
  final double overheadSecs;

  /// Time for a single iteration (useful for unbounded loops)
  @override
  final double singleIterationSecs;

  /// Whether the sequence contains unbounded loops (forever, whileDark, etc.)
  @override
  final bool isUnbounded;

  /// For untilTime loops, the target end time
  @override
  final DateTime? untilTime;

  /// For unbounded loops, the condition type
  @override
  final LoopConditionType? conditionType;

  @override
  String toString() {
    return 'SequenceEstimate(estimatedSecs: $estimatedSecs, overheadSecs: $overheadSecs, singleIterationSecs: $singleIterationSecs, isUnbounded: $isUnbounded, untilTime: $untilTime, conditionType: $conditionType)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SequenceEstimateImpl &&
            (identical(other.estimatedSecs, estimatedSecs) ||
                other.estimatedSecs == estimatedSecs) &&
            (identical(other.overheadSecs, overheadSecs) ||
                other.overheadSecs == overheadSecs) &&
            (identical(other.singleIterationSecs, singleIterationSecs) ||
                other.singleIterationSecs == singleIterationSecs) &&
            (identical(other.isUnbounded, isUnbounded) ||
                other.isUnbounded == isUnbounded) &&
            (identical(other.untilTime, untilTime) ||
                other.untilTime == untilTime) &&
            (identical(other.conditionType, conditionType) ||
                other.conditionType == conditionType));
  }

  @override
  int get hashCode => Object.hash(runtimeType, estimatedSecs, overheadSecs,
      singleIterationSecs, isUnbounded, untilTime, conditionType);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$SequenceEstimateImplCopyWith<_$SequenceEstimateImpl> get copyWith =>
      __$$SequenceEstimateImplCopyWithImpl<_$SequenceEstimateImpl>(
          this, _$identity);
}

abstract class _SequenceEstimate extends SequenceEstimate {
  const factory _SequenceEstimate(
      {required final double estimatedSecs,
      final double overheadSecs,
      required final double singleIterationSecs,
      required final bool isUnbounded,
      final DateTime? untilTime,
      final LoopConditionType? conditionType}) = _$SequenceEstimateImpl;
  const _SequenceEstimate._() : super._();

  @override

  /// Estimated total integration time in seconds (pure shutter-open time)
  double get estimatedSecs;
  @override

  /// Estimated total overhead time in seconds (slews, AF, dithers, etc.)
  double get overheadSecs;
  @override

  /// Time for a single iteration (useful for unbounded loops)
  double get singleIterationSecs;
  @override

  /// Whether the sequence contains unbounded loops (forever, whileDark, etc.)
  bool get isUnbounded;
  @override

  /// For untilTime loops, the target end time
  DateTime? get untilTime;
  @override

  /// For unbounded loops, the condition type
  LoopConditionType? get conditionType;
  @override
  @JsonKey(ignore: true)
  _$$SequenceEstimateImplCopyWith<_$SequenceEstimateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

MosaicPanelInfo _$MosaicPanelInfoFromJson(Map<String, dynamic> json) {
  return _MosaicPanelInfo.fromJson(json);
}

/// @nodoc
mixin _$MosaicPanelInfo {
  String get mosaicName => throw _privateConstructorUsedError;
  int get panelIndex => throw _privateConstructorUsedError;
  int get totalPanels => throw _privateConstructorUsedError;
  int get row => throw _privateConstructorUsedError;
  int get column => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $MosaicPanelInfoCopyWith<MosaicPanelInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MosaicPanelInfoCopyWith<$Res> {
  factory $MosaicPanelInfoCopyWith(
          MosaicPanelInfo value, $Res Function(MosaicPanelInfo) then) =
      _$MosaicPanelInfoCopyWithImpl<$Res, MosaicPanelInfo>;
  @useResult
  $Res call(
      {String mosaicName,
      int panelIndex,
      int totalPanels,
      int row,
      int column});
}

/// @nodoc
class _$MosaicPanelInfoCopyWithImpl<$Res, $Val extends MosaicPanelInfo>
    implements $MosaicPanelInfoCopyWith<$Res> {
  _$MosaicPanelInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mosaicName = null,
    Object? panelIndex = null,
    Object? totalPanels = null,
    Object? row = null,
    Object? column = null,
  }) {
    return _then(_value.copyWith(
      mosaicName: null == mosaicName
          ? _value.mosaicName
          : mosaicName // ignore: cast_nullable_to_non_nullable
              as String,
      panelIndex: null == panelIndex
          ? _value.panelIndex
          : panelIndex // ignore: cast_nullable_to_non_nullable
              as int,
      totalPanels: null == totalPanels
          ? _value.totalPanels
          : totalPanels // ignore: cast_nullable_to_non_nullable
              as int,
      row: null == row
          ? _value.row
          : row // ignore: cast_nullable_to_non_nullable
              as int,
      column: null == column
          ? _value.column
          : column // ignore: cast_nullable_to_non_nullable
              as int,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$MosaicPanelInfoImplCopyWith<$Res>
    implements $MosaicPanelInfoCopyWith<$Res> {
  factory _$$MosaicPanelInfoImplCopyWith(_$MosaicPanelInfoImpl value,
          $Res Function(_$MosaicPanelInfoImpl) then) =
      __$$MosaicPanelInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String mosaicName,
      int panelIndex,
      int totalPanels,
      int row,
      int column});
}

/// @nodoc
class __$$MosaicPanelInfoImplCopyWithImpl<$Res>
    extends _$MosaicPanelInfoCopyWithImpl<$Res, _$MosaicPanelInfoImpl>
    implements _$$MosaicPanelInfoImplCopyWith<$Res> {
  __$$MosaicPanelInfoImplCopyWithImpl(
      _$MosaicPanelInfoImpl _value, $Res Function(_$MosaicPanelInfoImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? mosaicName = null,
    Object? panelIndex = null,
    Object? totalPanels = null,
    Object? row = null,
    Object? column = null,
  }) {
    return _then(_$MosaicPanelInfoImpl(
      mosaicName: null == mosaicName
          ? _value.mosaicName
          : mosaicName // ignore: cast_nullable_to_non_nullable
              as String,
      panelIndex: null == panelIndex
          ? _value.panelIndex
          : panelIndex // ignore: cast_nullable_to_non_nullable
              as int,
      totalPanels: null == totalPanels
          ? _value.totalPanels
          : totalPanels // ignore: cast_nullable_to_non_nullable
              as int,
      row: null == row
          ? _value.row
          : row // ignore: cast_nullable_to_non_nullable
              as int,
      column: null == column
          ? _value.column
          : column // ignore: cast_nullable_to_non_nullable
              as int,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _$MosaicPanelInfoImpl extends _MosaicPanelInfo {
  const _$MosaicPanelInfoImpl(
      {required this.mosaicName,
      required this.panelIndex,
      required this.totalPanels,
      required this.row,
      required this.column})
      : super._();

  factory _$MosaicPanelInfoImpl.fromJson(Map<String, dynamic> json) =>
      _$$MosaicPanelInfoImplFromJson(json);

  @override
  final String mosaicName;
  @override
  final int panelIndex;
  @override
  final int totalPanels;
  @override
  final int row;
  @override
  final int column;

  @override
  String toString() {
    return 'MosaicPanelInfo(mosaicName: $mosaicName, panelIndex: $panelIndex, totalPanels: $totalPanels, row: $row, column: $column)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MosaicPanelInfoImpl &&
            (identical(other.mosaicName, mosaicName) ||
                other.mosaicName == mosaicName) &&
            (identical(other.panelIndex, panelIndex) ||
                other.panelIndex == panelIndex) &&
            (identical(other.totalPanels, totalPanels) ||
                other.totalPanels == totalPanels) &&
            (identical(other.row, row) || other.row == row) &&
            (identical(other.column, column) || other.column == column));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, mosaicName, panelIndex, totalPanels, row, column);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$MosaicPanelInfoImplCopyWith<_$MosaicPanelInfoImpl> get copyWith =>
      __$$MosaicPanelInfoImplCopyWithImpl<_$MosaicPanelInfoImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$MosaicPanelInfoImplToJson(
      this,
    );
  }
}

abstract class _MosaicPanelInfo extends MosaicPanelInfo {
  const factory _MosaicPanelInfo(
      {required final String mosaicName,
      required final int panelIndex,
      required final int totalPanels,
      required final int row,
      required final int column}) = _$MosaicPanelInfoImpl;
  const _MosaicPanelInfo._() : super._();

  factory _MosaicPanelInfo.fromJson(Map<String, dynamic> json) =
      _$MosaicPanelInfoImpl.fromJson;

  @override
  String get mosaicName;
  @override
  int get panelIndex;
  @override
  int get totalPanels;
  @override
  int get row;
  @override
  int get column;
  @override
  @JsonKey(ignore: true)
  _$$MosaicPanelInfoImplCopyWith<_$MosaicPanelInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
