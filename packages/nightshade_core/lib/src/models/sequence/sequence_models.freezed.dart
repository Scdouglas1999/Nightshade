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

AdaptiveExposureConfig _$AdaptiveExposureConfigFromJson(
    Map<String, dynamic> json) {
  return _AdaptiveExposureConfig.fromJson(json);
}

/// @nodoc
mixin _$AdaptiveExposureConfig {
  /// Target SNR (informational; the current adapter scales by sky-
  /// background flux ratio rather than aiming at a numeric target).
  double get targetSnr => throw _privateConstructorUsedError;

  /// Sky brightness in mag/arcsec² that the node's configured nominal
  /// exposure is calibrated for.
  double get referenceSkyBrightnessMag => throw _privateConstructorUsedError;

  /// Global minimum exposure clamp (seconds).
  double get minExposureSecs => throw _privateConstructorUsedError;

  /// Global maximum exposure clamp (seconds).
  double get maxExposureSecs => throw _privateConstructorUsedError;

  /// Per-filter enable map. Filter name -> bool. Empty => apply globally.
  Map<String, bool> get perFilterEnabled => throw _privateConstructorUsedError;

  /// Per-filter minimum exposure overrides (seconds).
  Map<String, double> get perFilterMinSecs =>
      throw _privateConstructorUsedError;

  /// Per-filter maximum exposure overrides (seconds).
  Map<String, double> get perFilterMaxSecs =>
      throw _privateConstructorUsedError;

  /// Global enable toggle. When false the whole config is a no-op
  /// regardless of per-filter map content.
  bool get enabled => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AdaptiveExposureConfigCopyWith<AdaptiveExposureConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AdaptiveExposureConfigCopyWith<$Res> {
  factory $AdaptiveExposureConfigCopyWith(AdaptiveExposureConfig value,
          $Res Function(AdaptiveExposureConfig) then) =
      _$AdaptiveExposureConfigCopyWithImpl<$Res, AdaptiveExposureConfig>;
  @useResult
  $Res call(
      {double targetSnr,
      double referenceSkyBrightnessMag,
      double minExposureSecs,
      double maxExposureSecs,
      Map<String, bool> perFilterEnabled,
      Map<String, double> perFilterMinSecs,
      Map<String, double> perFilterMaxSecs,
      bool enabled});
}

/// @nodoc
class _$AdaptiveExposureConfigCopyWithImpl<$Res,
        $Val extends AdaptiveExposureConfig>
    implements $AdaptiveExposureConfigCopyWith<$Res> {
  _$AdaptiveExposureConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? targetSnr = null,
    Object? referenceSkyBrightnessMag = null,
    Object? minExposureSecs = null,
    Object? maxExposureSecs = null,
    Object? perFilterEnabled = null,
    Object? perFilterMinSecs = null,
    Object? perFilterMaxSecs = null,
    Object? enabled = null,
  }) {
    return _then(_value.copyWith(
      targetSnr: null == targetSnr
          ? _value.targetSnr
          : targetSnr // ignore: cast_nullable_to_non_nullable
              as double,
      referenceSkyBrightnessMag: null == referenceSkyBrightnessMag
          ? _value.referenceSkyBrightnessMag
          : referenceSkyBrightnessMag // ignore: cast_nullable_to_non_nullable
              as double,
      minExposureSecs: null == minExposureSecs
          ? _value.minExposureSecs
          : minExposureSecs // ignore: cast_nullable_to_non_nullable
              as double,
      maxExposureSecs: null == maxExposureSecs
          ? _value.maxExposureSecs
          : maxExposureSecs // ignore: cast_nullable_to_non_nullable
              as double,
      perFilterEnabled: null == perFilterEnabled
          ? _value.perFilterEnabled
          : perFilterEnabled // ignore: cast_nullable_to_non_nullable
              as Map<String, bool>,
      perFilterMinSecs: null == perFilterMinSecs
          ? _value.perFilterMinSecs
          : perFilterMinSecs // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      perFilterMaxSecs: null == perFilterMaxSecs
          ? _value.perFilterMaxSecs
          : perFilterMaxSecs // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AdaptiveExposureConfigImplCopyWith<$Res>
    implements $AdaptiveExposureConfigCopyWith<$Res> {
  factory _$$AdaptiveExposureConfigImplCopyWith(
          _$AdaptiveExposureConfigImpl value,
          $Res Function(_$AdaptiveExposureConfigImpl) then) =
      __$$AdaptiveExposureConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double targetSnr,
      double referenceSkyBrightnessMag,
      double minExposureSecs,
      double maxExposureSecs,
      Map<String, bool> perFilterEnabled,
      Map<String, double> perFilterMinSecs,
      Map<String, double> perFilterMaxSecs,
      bool enabled});
}

/// @nodoc
class __$$AdaptiveExposureConfigImplCopyWithImpl<$Res>
    extends _$AdaptiveExposureConfigCopyWithImpl<$Res,
        _$AdaptiveExposureConfigImpl>
    implements _$$AdaptiveExposureConfigImplCopyWith<$Res> {
  __$$AdaptiveExposureConfigImplCopyWithImpl(
      _$AdaptiveExposureConfigImpl _value,
      $Res Function(_$AdaptiveExposureConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? targetSnr = null,
    Object? referenceSkyBrightnessMag = null,
    Object? minExposureSecs = null,
    Object? maxExposureSecs = null,
    Object? perFilterEnabled = null,
    Object? perFilterMinSecs = null,
    Object? perFilterMaxSecs = null,
    Object? enabled = null,
  }) {
    return _then(_$AdaptiveExposureConfigImpl(
      targetSnr: null == targetSnr
          ? _value.targetSnr
          : targetSnr // ignore: cast_nullable_to_non_nullable
              as double,
      referenceSkyBrightnessMag: null == referenceSkyBrightnessMag
          ? _value.referenceSkyBrightnessMag
          : referenceSkyBrightnessMag // ignore: cast_nullable_to_non_nullable
              as double,
      minExposureSecs: null == minExposureSecs
          ? _value.minExposureSecs
          : minExposureSecs // ignore: cast_nullable_to_non_nullable
              as double,
      maxExposureSecs: null == maxExposureSecs
          ? _value.maxExposureSecs
          : maxExposureSecs // ignore: cast_nullable_to_non_nullable
              as double,
      perFilterEnabled: null == perFilterEnabled
          ? _value._perFilterEnabled
          : perFilterEnabled // ignore: cast_nullable_to_non_nullable
              as Map<String, bool>,
      perFilterMinSecs: null == perFilterMinSecs
          ? _value._perFilterMinSecs
          : perFilterMinSecs // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      perFilterMaxSecs: null == perFilterMaxSecs
          ? _value._perFilterMaxSecs
          : perFilterMaxSecs // ignore: cast_nullable_to_non_nullable
              as Map<String, double>,
      enabled: null == enabled
          ? _value.enabled
          : enabled // ignore: cast_nullable_to_non_nullable
              as bool,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _$AdaptiveExposureConfigImpl extends _AdaptiveExposureConfig {
  const _$AdaptiveExposureConfigImpl(
      {this.targetSnr = 30.0,
      this.referenceSkyBrightnessMag = 21.5,
      this.minExposureSecs = 5.0,
      this.maxExposureSecs = 600.0,
      final Map<String, bool> perFilterEnabled = const <String, bool>{},
      final Map<String, double> perFilterMinSecs = const <String, double>{},
      final Map<String, double> perFilterMaxSecs = const <String, double>{},
      this.enabled = true})
      : _perFilterEnabled = perFilterEnabled,
        _perFilterMinSecs = perFilterMinSecs,
        _perFilterMaxSecs = perFilterMaxSecs,
        super._();

  factory _$AdaptiveExposureConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$AdaptiveExposureConfigImplFromJson(json);

  /// Target SNR (informational; the current adapter scales by sky-
  /// background flux ratio rather than aiming at a numeric target).
  @override
  @JsonKey()
  final double targetSnr;

  /// Sky brightness in mag/arcsec² that the node's configured nominal
  /// exposure is calibrated for.
  @override
  @JsonKey()
  final double referenceSkyBrightnessMag;

  /// Global minimum exposure clamp (seconds).
  @override
  @JsonKey()
  final double minExposureSecs;

  /// Global maximum exposure clamp (seconds).
  @override
  @JsonKey()
  final double maxExposureSecs;

  /// Per-filter enable map. Filter name -> bool. Empty => apply globally.
  final Map<String, bool> _perFilterEnabled;

  /// Per-filter enable map. Filter name -> bool. Empty => apply globally.
  @override
  @JsonKey()
  Map<String, bool> get perFilterEnabled {
    if (_perFilterEnabled is EqualUnmodifiableMapView) return _perFilterEnabled;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_perFilterEnabled);
  }

  /// Per-filter minimum exposure overrides (seconds).
  final Map<String, double> _perFilterMinSecs;

  /// Per-filter minimum exposure overrides (seconds).
  @override
  @JsonKey()
  Map<String, double> get perFilterMinSecs {
    if (_perFilterMinSecs is EqualUnmodifiableMapView) return _perFilterMinSecs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_perFilterMinSecs);
  }

  /// Per-filter maximum exposure overrides (seconds).
  final Map<String, double> _perFilterMaxSecs;

  /// Per-filter maximum exposure overrides (seconds).
  @override
  @JsonKey()
  Map<String, double> get perFilterMaxSecs {
    if (_perFilterMaxSecs is EqualUnmodifiableMapView) return _perFilterMaxSecs;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_perFilterMaxSecs);
  }

  /// Global enable toggle. When false the whole config is a no-op
  /// regardless of per-filter map content.
  @override
  @JsonKey()
  final bool enabled;

  @override
  String toString() {
    return 'AdaptiveExposureConfig(targetSnr: $targetSnr, referenceSkyBrightnessMag: $referenceSkyBrightnessMag, minExposureSecs: $minExposureSecs, maxExposureSecs: $maxExposureSecs, perFilterEnabled: $perFilterEnabled, perFilterMinSecs: $perFilterMinSecs, perFilterMaxSecs: $perFilterMaxSecs, enabled: $enabled)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AdaptiveExposureConfigImpl &&
            (identical(other.targetSnr, targetSnr) ||
                other.targetSnr == targetSnr) &&
            (identical(other.referenceSkyBrightnessMag,
                    referenceSkyBrightnessMag) ||
                other.referenceSkyBrightnessMag == referenceSkyBrightnessMag) &&
            (identical(other.minExposureSecs, minExposureSecs) ||
                other.minExposureSecs == minExposureSecs) &&
            (identical(other.maxExposureSecs, maxExposureSecs) ||
                other.maxExposureSecs == maxExposureSecs) &&
            const DeepCollectionEquality()
                .equals(other._perFilterEnabled, _perFilterEnabled) &&
            const DeepCollectionEquality()
                .equals(other._perFilterMinSecs, _perFilterMinSecs) &&
            const DeepCollectionEquality()
                .equals(other._perFilterMaxSecs, _perFilterMaxSecs) &&
            (identical(other.enabled, enabled) || other.enabled == enabled));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      targetSnr,
      referenceSkyBrightnessMag,
      minExposureSecs,
      maxExposureSecs,
      const DeepCollectionEquality().hash(_perFilterEnabled),
      const DeepCollectionEquality().hash(_perFilterMinSecs),
      const DeepCollectionEquality().hash(_perFilterMaxSecs),
      enabled);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AdaptiveExposureConfigImplCopyWith<_$AdaptiveExposureConfigImpl>
      get copyWith => __$$AdaptiveExposureConfigImplCopyWithImpl<
          _$AdaptiveExposureConfigImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AdaptiveExposureConfigImplToJson(
      this,
    );
  }
}

abstract class _AdaptiveExposureConfig extends AdaptiveExposureConfig {
  const factory _AdaptiveExposureConfig(
      {final double targetSnr,
      final double referenceSkyBrightnessMag,
      final double minExposureSecs,
      final double maxExposureSecs,
      final Map<String, bool> perFilterEnabled,
      final Map<String, double> perFilterMinSecs,
      final Map<String, double> perFilterMaxSecs,
      final bool enabled}) = _$AdaptiveExposureConfigImpl;
  const _AdaptiveExposureConfig._() : super._();

  factory _AdaptiveExposureConfig.fromJson(Map<String, dynamic> json) =
      _$AdaptiveExposureConfigImpl.fromJson;

  @override

  /// Target SNR (informational; the current adapter scales by sky-
  /// background flux ratio rather than aiming at a numeric target).
  double get targetSnr;
  @override

  /// Sky brightness in mag/arcsec² that the node's configured nominal
  /// exposure is calibrated for.
  double get referenceSkyBrightnessMag;
  @override

  /// Global minimum exposure clamp (seconds).
  double get minExposureSecs;
  @override

  /// Global maximum exposure clamp (seconds).
  double get maxExposureSecs;
  @override

  /// Per-filter enable map. Filter name -> bool. Empty => apply globally.
  Map<String, bool> get perFilterEnabled;
  @override

  /// Per-filter minimum exposure overrides (seconds).
  Map<String, double> get perFilterMinSecs;
  @override

  /// Per-filter maximum exposure overrides (seconds).
  Map<String, double> get perFilterMaxSecs;
  @override

  /// Global enable toggle. When false the whole config is a no-op
  /// regardless of per-filter map content.
  bool get enabled;
  @override
  @JsonKey(ignore: true)
  _$$AdaptiveExposureConfigImplCopyWith<_$AdaptiveExposureConfigImpl>
      get copyWith => throw _privateConstructorUsedError;
}

BrightnessTierPreferences _$BrightnessTierPreferencesFromJson(
    Map<String, dynamic> json) {
  return _BrightnessTierPreferences.fromJson(json);
}

/// @nodoc
mixin _$BrightnessTierPreferences {
  double get faintMinScore => throw _privateConstructorUsedError;
  double get mediumMinScore => throw _privateConstructorUsedError;
  double get brightMinScore => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $BrightnessTierPreferencesCopyWith<BrightnessTierPreferences> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BrightnessTierPreferencesCopyWith<$Res> {
  factory $BrightnessTierPreferencesCopyWith(BrightnessTierPreferences value,
          $Res Function(BrightnessTierPreferences) then) =
      _$BrightnessTierPreferencesCopyWithImpl<$Res, BrightnessTierPreferences>;
  @useResult
  $Res call(
      {double faintMinScore, double mediumMinScore, double brightMinScore});
}

/// @nodoc
class _$BrightnessTierPreferencesCopyWithImpl<$Res,
        $Val extends BrightnessTierPreferences>
    implements $BrightnessTierPreferencesCopyWith<$Res> {
  _$BrightnessTierPreferencesCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? faintMinScore = null,
    Object? mediumMinScore = null,
    Object? brightMinScore = null,
  }) {
    return _then(_value.copyWith(
      faintMinScore: null == faintMinScore
          ? _value.faintMinScore
          : faintMinScore // ignore: cast_nullable_to_non_nullable
              as double,
      mediumMinScore: null == mediumMinScore
          ? _value.mediumMinScore
          : mediumMinScore // ignore: cast_nullable_to_non_nullable
              as double,
      brightMinScore: null == brightMinScore
          ? _value.brightMinScore
          : brightMinScore // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$BrightnessTierPreferencesImplCopyWith<$Res>
    implements $BrightnessTierPreferencesCopyWith<$Res> {
  factory _$$BrightnessTierPreferencesImplCopyWith(
          _$BrightnessTierPreferencesImpl value,
          $Res Function(_$BrightnessTierPreferencesImpl) then) =
      __$$BrightnessTierPreferencesImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double faintMinScore, double mediumMinScore, double brightMinScore});
}

/// @nodoc
class __$$BrightnessTierPreferencesImplCopyWithImpl<$Res>
    extends _$BrightnessTierPreferencesCopyWithImpl<$Res,
        _$BrightnessTierPreferencesImpl>
    implements _$$BrightnessTierPreferencesImplCopyWith<$Res> {
  __$$BrightnessTierPreferencesImplCopyWithImpl(
      _$BrightnessTierPreferencesImpl _value,
      $Res Function(_$BrightnessTierPreferencesImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? faintMinScore = null,
    Object? mediumMinScore = null,
    Object? brightMinScore = null,
  }) {
    return _then(_$BrightnessTierPreferencesImpl(
      faintMinScore: null == faintMinScore
          ? _value.faintMinScore
          : faintMinScore // ignore: cast_nullable_to_non_nullable
              as double,
      mediumMinScore: null == mediumMinScore
          ? _value.mediumMinScore
          : mediumMinScore // ignore: cast_nullable_to_non_nullable
              as double,
      brightMinScore: null == brightMinScore
          ? _value.brightMinScore
          : brightMinScore // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _$BrightnessTierPreferencesImpl extends _BrightnessTierPreferences {
  const _$BrightnessTierPreferencesImpl(
      {this.faintMinScore = 70.0,
      this.mediumMinScore = 50.0,
      this.brightMinScore = 30.0})
      : super._();

  factory _$BrightnessTierPreferencesImpl.fromJson(Map<String, dynamic> json) =>
      _$$BrightnessTierPreferencesImplFromJson(json);

  @override
  @JsonKey()
  final double faintMinScore;
  @override
  @JsonKey()
  final double mediumMinScore;
  @override
  @JsonKey()
  final double brightMinScore;

  @override
  String toString() {
    return 'BrightnessTierPreferences(faintMinScore: $faintMinScore, mediumMinScore: $mediumMinScore, brightMinScore: $brightMinScore)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BrightnessTierPreferencesImpl &&
            (identical(other.faintMinScore, faintMinScore) ||
                other.faintMinScore == faintMinScore) &&
            (identical(other.mediumMinScore, mediumMinScore) ||
                other.mediumMinScore == mediumMinScore) &&
            (identical(other.brightMinScore, brightMinScore) ||
                other.brightMinScore == brightMinScore));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, faintMinScore, mediumMinScore, brightMinScore);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$BrightnessTierPreferencesImplCopyWith<_$BrightnessTierPreferencesImpl>
      get copyWith => __$$BrightnessTierPreferencesImplCopyWithImpl<
          _$BrightnessTierPreferencesImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$BrightnessTierPreferencesImplToJson(
      this,
    );
  }
}

abstract class _BrightnessTierPreferences extends BrightnessTierPreferences {
  const factory _BrightnessTierPreferences(
      {final double faintMinScore,
      final double mediumMinScore,
      final double brightMinScore}) = _$BrightnessTierPreferencesImpl;
  const _BrightnessTierPreferences._() : super._();

  factory _BrightnessTierPreferences.fromJson(Map<String, dynamic> json) =
      _$BrightnessTierPreferencesImpl.fromJson;

  @override
  double get faintMinScore;
  @override
  double get mediumMinScore;
  @override
  double get brightMinScore;
  @override
  @JsonKey(ignore: true)
  _$$BrightnessTierPreferencesImplCopyWith<_$BrightnessTierPreferencesImpl>
      get copyWith => throw _privateConstructorUsedError;
}

ConditionsScoreWeights _$ConditionsScoreWeightsFromJson(
    Map<String, dynamic> json) {
  return _ConditionsScoreWeights.fromJson(json);
}

/// @nodoc
mixin _$ConditionsScoreWeights {
  double get transparencyWeight => throw _privateConstructorUsedError;
  double get seeingWeight => throw _privateConstructorUsedError;
  double get cloudWeight => throw _privateConstructorUsedError;
  double get windWeight => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ConditionsScoreWeightsCopyWith<ConditionsScoreWeights> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConditionsScoreWeightsCopyWith<$Res> {
  factory $ConditionsScoreWeightsCopyWith(ConditionsScoreWeights value,
          $Res Function(ConditionsScoreWeights) then) =
      _$ConditionsScoreWeightsCopyWithImpl<$Res, ConditionsScoreWeights>;
  @useResult
  $Res call(
      {double transparencyWeight,
      double seeingWeight,
      double cloudWeight,
      double windWeight});
}

/// @nodoc
class _$ConditionsScoreWeightsCopyWithImpl<$Res,
        $Val extends ConditionsScoreWeights>
    implements $ConditionsScoreWeightsCopyWith<$Res> {
  _$ConditionsScoreWeightsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? transparencyWeight = null,
    Object? seeingWeight = null,
    Object? cloudWeight = null,
    Object? windWeight = null,
  }) {
    return _then(_value.copyWith(
      transparencyWeight: null == transparencyWeight
          ? _value.transparencyWeight
          : transparencyWeight // ignore: cast_nullable_to_non_nullable
              as double,
      seeingWeight: null == seeingWeight
          ? _value.seeingWeight
          : seeingWeight // ignore: cast_nullable_to_non_nullable
              as double,
      cloudWeight: null == cloudWeight
          ? _value.cloudWeight
          : cloudWeight // ignore: cast_nullable_to_non_nullable
              as double,
      windWeight: null == windWeight
          ? _value.windWeight
          : windWeight // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ConditionsScoreWeightsImplCopyWith<$Res>
    implements $ConditionsScoreWeightsCopyWith<$Res> {
  factory _$$ConditionsScoreWeightsImplCopyWith(
          _$ConditionsScoreWeightsImpl value,
          $Res Function(_$ConditionsScoreWeightsImpl) then) =
      __$$ConditionsScoreWeightsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double transparencyWeight,
      double seeingWeight,
      double cloudWeight,
      double windWeight});
}

/// @nodoc
class __$$ConditionsScoreWeightsImplCopyWithImpl<$Res>
    extends _$ConditionsScoreWeightsCopyWithImpl<$Res,
        _$ConditionsScoreWeightsImpl>
    implements _$$ConditionsScoreWeightsImplCopyWith<$Res> {
  __$$ConditionsScoreWeightsImplCopyWithImpl(
      _$ConditionsScoreWeightsImpl _value,
      $Res Function(_$ConditionsScoreWeightsImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? transparencyWeight = null,
    Object? seeingWeight = null,
    Object? cloudWeight = null,
    Object? windWeight = null,
  }) {
    return _then(_$ConditionsScoreWeightsImpl(
      transparencyWeight: null == transparencyWeight
          ? _value.transparencyWeight
          : transparencyWeight // ignore: cast_nullable_to_non_nullable
              as double,
      seeingWeight: null == seeingWeight
          ? _value.seeingWeight
          : seeingWeight // ignore: cast_nullable_to_non_nullable
              as double,
      cloudWeight: null == cloudWeight
          ? _value.cloudWeight
          : cloudWeight // ignore: cast_nullable_to_non_nullable
              as double,
      windWeight: null == windWeight
          ? _value.windWeight
          : windWeight // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _$ConditionsScoreWeightsImpl extends _ConditionsScoreWeights {
  const _$ConditionsScoreWeightsImpl(
      {this.transparencyWeight = 0.4,
      this.seeingWeight = 0.25,
      this.cloudWeight = 0.25,
      this.windWeight = 0.1})
      : super._();

  factory _$ConditionsScoreWeightsImpl.fromJson(Map<String, dynamic> json) =>
      _$$ConditionsScoreWeightsImplFromJson(json);

  @override
  @JsonKey()
  final double transparencyWeight;
  @override
  @JsonKey()
  final double seeingWeight;
  @override
  @JsonKey()
  final double cloudWeight;
  @override
  @JsonKey()
  final double windWeight;

  @override
  String toString() {
    return 'ConditionsScoreWeights(transparencyWeight: $transparencyWeight, seeingWeight: $seeingWeight, cloudWeight: $cloudWeight, windWeight: $windWeight)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConditionsScoreWeightsImpl &&
            (identical(other.transparencyWeight, transparencyWeight) ||
                other.transparencyWeight == transparencyWeight) &&
            (identical(other.seeingWeight, seeingWeight) ||
                other.seeingWeight == seeingWeight) &&
            (identical(other.cloudWeight, cloudWeight) ||
                other.cloudWeight == cloudWeight) &&
            (identical(other.windWeight, windWeight) ||
                other.windWeight == windWeight));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, transparencyWeight, seeingWeight, cloudWeight, windWeight);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ConditionsScoreWeightsImplCopyWith<_$ConditionsScoreWeightsImpl>
      get copyWith => __$$ConditionsScoreWeightsImplCopyWithImpl<
          _$ConditionsScoreWeightsImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ConditionsScoreWeightsImplToJson(
      this,
    );
  }
}

abstract class _ConditionsScoreWeights extends ConditionsScoreWeights {
  const factory _ConditionsScoreWeights(
      {final double transparencyWeight,
      final double seeingWeight,
      final double cloudWeight,
      final double windWeight}) = _$ConditionsScoreWeightsImpl;
  const _ConditionsScoreWeights._() : super._();

  factory _ConditionsScoreWeights.fromJson(Map<String, dynamic> json) =
      _$ConditionsScoreWeightsImpl.fromJson;

  @override
  double get transparencyWeight;
  @override
  double get seeingWeight;
  @override
  double get cloudWeight;
  @override
  double get windWeight;
  @override
  @JsonKey(ignore: true)
  _$$ConditionsScoreWeightsImplCopyWith<_$ConditionsScoreWeightsImpl>
      get copyWith => throw _privateConstructorUsedError;
}

ConditionsScore _$ConditionsScoreFromJson(Map<String, dynamic> json) {
  return _ConditionsScore.fromJson(json);
}

/// @nodoc
mixin _$ConditionsScore {
  double get score => throw _privateConstructorUsedError;
  double? get transparencyScore => throw _privateConstructorUsedError;
  double? get seeingScore => throw _privateConstructorUsedError;
  double? get cloudScore => throw _privateConstructorUsedError;
  double? get windScore => throw _privateConstructorUsedError;
  ConditionsScoreWeights get weights =>
      throw _privateConstructorUsedError; // `generated_unix_secs` (int seconds) on the wire. The Rust side uses
// `serde_with::TimestampSeconds<i64>`. PHASE-2-NOTE: The pre-freezed
// fromJson fell back to `0` (epoch) on missing field; the freezed
// form makes the field required, which is strictly stricter (errors
// are a feature). The Rust producer always emits this field, so
// production traffic is unaffected; only synthetic JSON missing the
// key will now throw — matching CLAUDE.md's "silent fallback hides
// bugs" policy. Phase 1's contract tests always provide the key.
  @JsonKey(name: 'generated_unix_secs')
  @UnixSecsDateTimeConverter()
  DateTime get generatedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ConditionsScoreCopyWith<ConditionsScore> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConditionsScoreCopyWith<$Res> {
  factory $ConditionsScoreCopyWith(
          ConditionsScore value, $Res Function(ConditionsScore) then) =
      _$ConditionsScoreCopyWithImpl<$Res, ConditionsScore>;
  @useResult
  $Res call(
      {double score,
      double? transparencyScore,
      double? seeingScore,
      double? cloudScore,
      double? windScore,
      ConditionsScoreWeights weights,
      @JsonKey(name: 'generated_unix_secs')
      @UnixSecsDateTimeConverter()
      DateTime generatedAt});

  $ConditionsScoreWeightsCopyWith<$Res> get weights;
}

/// @nodoc
class _$ConditionsScoreCopyWithImpl<$Res, $Val extends ConditionsScore>
    implements $ConditionsScoreCopyWith<$Res> {
  _$ConditionsScoreCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? score = null,
    Object? transparencyScore = freezed,
    Object? seeingScore = freezed,
    Object? cloudScore = freezed,
    Object? windScore = freezed,
    Object? weights = null,
    Object? generatedAt = null,
  }) {
    return _then(_value.copyWith(
      score: null == score
          ? _value.score
          : score // ignore: cast_nullable_to_non_nullable
              as double,
      transparencyScore: freezed == transparencyScore
          ? _value.transparencyScore
          : transparencyScore // ignore: cast_nullable_to_non_nullable
              as double?,
      seeingScore: freezed == seeingScore
          ? _value.seeingScore
          : seeingScore // ignore: cast_nullable_to_non_nullable
              as double?,
      cloudScore: freezed == cloudScore
          ? _value.cloudScore
          : cloudScore // ignore: cast_nullable_to_non_nullable
              as double?,
      windScore: freezed == windScore
          ? _value.windScore
          : windScore // ignore: cast_nullable_to_non_nullable
              as double?,
      weights: null == weights
          ? _value.weights
          : weights // ignore: cast_nullable_to_non_nullable
              as ConditionsScoreWeights,
      generatedAt: null == generatedAt
          ? _value.generatedAt
          : generatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $ConditionsScoreWeightsCopyWith<$Res> get weights {
    return $ConditionsScoreWeightsCopyWith<$Res>(_value.weights, (value) {
      return _then(_value.copyWith(weights: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ConditionsScoreImplCopyWith<$Res>
    implements $ConditionsScoreCopyWith<$Res> {
  factory _$$ConditionsScoreImplCopyWith(_$ConditionsScoreImpl value,
          $Res Function(_$ConditionsScoreImpl) then) =
      __$$ConditionsScoreImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double score,
      double? transparencyScore,
      double? seeingScore,
      double? cloudScore,
      double? windScore,
      ConditionsScoreWeights weights,
      @JsonKey(name: 'generated_unix_secs')
      @UnixSecsDateTimeConverter()
      DateTime generatedAt});

  @override
  $ConditionsScoreWeightsCopyWith<$Res> get weights;
}

/// @nodoc
class __$$ConditionsScoreImplCopyWithImpl<$Res>
    extends _$ConditionsScoreCopyWithImpl<$Res, _$ConditionsScoreImpl>
    implements _$$ConditionsScoreImplCopyWith<$Res> {
  __$$ConditionsScoreImplCopyWithImpl(
      _$ConditionsScoreImpl _value, $Res Function(_$ConditionsScoreImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? score = null,
    Object? transparencyScore = freezed,
    Object? seeingScore = freezed,
    Object? cloudScore = freezed,
    Object? windScore = freezed,
    Object? weights = null,
    Object? generatedAt = null,
  }) {
    return _then(_$ConditionsScoreImpl(
      score: null == score
          ? _value.score
          : score // ignore: cast_nullable_to_non_nullable
              as double,
      transparencyScore: freezed == transparencyScore
          ? _value.transparencyScore
          : transparencyScore // ignore: cast_nullable_to_non_nullable
              as double?,
      seeingScore: freezed == seeingScore
          ? _value.seeingScore
          : seeingScore // ignore: cast_nullable_to_non_nullable
              as double?,
      cloudScore: freezed == cloudScore
          ? _value.cloudScore
          : cloudScore // ignore: cast_nullable_to_non_nullable
              as double?,
      windScore: freezed == windScore
          ? _value.windScore
          : windScore // ignore: cast_nullable_to_non_nullable
              as double?,
      weights: null == weights
          ? _value.weights
          : weights // ignore: cast_nullable_to_non_nullable
              as ConditionsScoreWeights,
      generatedAt: null == generatedAt
          ? _value.generatedAt
          : generatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake, explicitToJson: true)
class _$ConditionsScoreImpl extends _ConditionsScore {
  const _$ConditionsScoreImpl(
      {required this.score,
      this.transparencyScore,
      this.seeingScore,
      this.cloudScore,
      this.windScore,
      this.weights = const ConditionsScoreWeights(),
      @JsonKey(name: 'generated_unix_secs')
      @UnixSecsDateTimeConverter()
      required this.generatedAt})
      : super._();

  factory _$ConditionsScoreImpl.fromJson(Map<String, dynamic> json) =>
      _$$ConditionsScoreImplFromJson(json);

  @override
  final double score;
  @override
  final double? transparencyScore;
  @override
  final double? seeingScore;
  @override
  final double? cloudScore;
  @override
  final double? windScore;
  @override
  @JsonKey()
  final ConditionsScoreWeights weights;
// `generated_unix_secs` (int seconds) on the wire. The Rust side uses
// `serde_with::TimestampSeconds<i64>`. PHASE-2-NOTE: The pre-freezed
// fromJson fell back to `0` (epoch) on missing field; the freezed
// form makes the field required, which is strictly stricter (errors
// are a feature). The Rust producer always emits this field, so
// production traffic is unaffected; only synthetic JSON missing the
// key will now throw — matching CLAUDE.md's "silent fallback hides
// bugs" policy. Phase 1's contract tests always provide the key.
  @override
  @JsonKey(name: 'generated_unix_secs')
  @UnixSecsDateTimeConverter()
  final DateTime generatedAt;

  @override
  String toString() {
    return 'ConditionsScore(score: $score, transparencyScore: $transparencyScore, seeingScore: $seeingScore, cloudScore: $cloudScore, windScore: $windScore, weights: $weights, generatedAt: $generatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConditionsScoreImpl &&
            (identical(other.score, score) || other.score == score) &&
            (identical(other.transparencyScore, transparencyScore) ||
                other.transparencyScore == transparencyScore) &&
            (identical(other.seeingScore, seeingScore) ||
                other.seeingScore == seeingScore) &&
            (identical(other.cloudScore, cloudScore) ||
                other.cloudScore == cloudScore) &&
            (identical(other.windScore, windScore) ||
                other.windScore == windScore) &&
            (identical(other.weights, weights) || other.weights == weights) &&
            (identical(other.generatedAt, generatedAt) ||
                other.generatedAt == generatedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, score, transparencyScore,
      seeingScore, cloudScore, windScore, weights, generatedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ConditionsScoreImplCopyWith<_$ConditionsScoreImpl> get copyWith =>
      __$$ConditionsScoreImplCopyWithImpl<_$ConditionsScoreImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ConditionsScoreImplToJson(
      this,
    );
  }
}

abstract class _ConditionsScore extends ConditionsScore {
  const factory _ConditionsScore(
      {required final double score,
      final double? transparencyScore,
      final double? seeingScore,
      final double? cloudScore,
      final double? windScore,
      final ConditionsScoreWeights weights,
      @JsonKey(name: 'generated_unix_secs')
      @UnixSecsDateTimeConverter()
      required final DateTime generatedAt}) = _$ConditionsScoreImpl;
  const _ConditionsScore._() : super._();

  factory _ConditionsScore.fromJson(Map<String, dynamic> json) =
      _$ConditionsScoreImpl.fromJson;

  @override
  double get score;
  @override
  double? get transparencyScore;
  @override
  double? get seeingScore;
  @override
  double? get cloudScore;
  @override
  double? get windScore;
  @override
  ConditionsScoreWeights get weights;
  @override // `generated_unix_secs` (int seconds) on the wire. The Rust side uses
// `serde_with::TimestampSeconds<i64>`. PHASE-2-NOTE: The pre-freezed
// fromJson fell back to `0` (epoch) on missing field; the freezed
// form makes the field required, which is strictly stricter (errors
// are a feature). The Rust producer always emits this field, so
// production traffic is unaffected; only synthetic JSON missing the
// key will now throw — matching CLAUDE.md's "silent fallback hides
// bugs" policy. Phase 1's contract tests always provide the key.
  @JsonKey(name: 'generated_unix_secs')
  @UnixSecsDateTimeConverter()
  DateTime get generatedAt;
  @override
  @JsonKey(ignore: true)
  _$$ConditionsScoreImplCopyWith<_$ConditionsScoreImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

AdaptiveSwapRuntimeState _$AdaptiveSwapRuntimeStateFromJson(
    Map<String, dynamic> json) {
  return _AdaptiveSwapRuntimeState.fromJson(json);
}

/// @nodoc
mixin _$AdaptiveSwapRuntimeState {
  String? get currentTargetId => throw _privateConstructorUsedError;
  String? get currentTier => throw _privateConstructorUsedError;
  String? get lastDecisionKind => throw _privateConstructorUsedError;
  String? get lastDecisionReason =>
      throw _privateConstructorUsedError; // `last_swap_unix_secs` (nullable int seconds). When `null`, the
// JSON field is present-with-null (not omitted) — Phase 1's
// `null_last_swap_serialises_as_null_field` contract test pins this.
  @JsonKey(name: 'last_swap_unix_secs')
  @NullableUnixSecsDateTimeConverter()
  DateTime? get lastSwapAt => throw _privateConstructorUsedError;
  String? get lastSwapFromTargetId => throw _privateConstructorUsedError;
  String? get lastSwapToTargetId => throw _privateConstructorUsedError;
  double? get lastObservedScore => throw _privateConstructorUsedError;
  double? get configuredThreshold => throw _privateConstructorUsedError;
  double get configuredHysteresisSecs => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AdaptiveSwapRuntimeStateCopyWith<AdaptiveSwapRuntimeState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AdaptiveSwapRuntimeStateCopyWith<$Res> {
  factory $AdaptiveSwapRuntimeStateCopyWith(AdaptiveSwapRuntimeState value,
          $Res Function(AdaptiveSwapRuntimeState) then) =
      _$AdaptiveSwapRuntimeStateCopyWithImpl<$Res, AdaptiveSwapRuntimeState>;
  @useResult
  $Res call(
      {String? currentTargetId,
      String? currentTier,
      String? lastDecisionKind,
      String? lastDecisionReason,
      @JsonKey(name: 'last_swap_unix_secs')
      @NullableUnixSecsDateTimeConverter()
      DateTime? lastSwapAt,
      String? lastSwapFromTargetId,
      String? lastSwapToTargetId,
      double? lastObservedScore,
      double? configuredThreshold,
      double configuredHysteresisSecs});
}

/// @nodoc
class _$AdaptiveSwapRuntimeStateCopyWithImpl<$Res,
        $Val extends AdaptiveSwapRuntimeState>
    implements $AdaptiveSwapRuntimeStateCopyWith<$Res> {
  _$AdaptiveSwapRuntimeStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentTargetId = freezed,
    Object? currentTier = freezed,
    Object? lastDecisionKind = freezed,
    Object? lastDecisionReason = freezed,
    Object? lastSwapAt = freezed,
    Object? lastSwapFromTargetId = freezed,
    Object? lastSwapToTargetId = freezed,
    Object? lastObservedScore = freezed,
    Object? configuredThreshold = freezed,
    Object? configuredHysteresisSecs = null,
  }) {
    return _then(_value.copyWith(
      currentTargetId: freezed == currentTargetId
          ? _value.currentTargetId
          : currentTargetId // ignore: cast_nullable_to_non_nullable
              as String?,
      currentTier: freezed == currentTier
          ? _value.currentTier
          : currentTier // ignore: cast_nullable_to_non_nullable
              as String?,
      lastDecisionKind: freezed == lastDecisionKind
          ? _value.lastDecisionKind
          : lastDecisionKind // ignore: cast_nullable_to_non_nullable
              as String?,
      lastDecisionReason: freezed == lastDecisionReason
          ? _value.lastDecisionReason
          : lastDecisionReason // ignore: cast_nullable_to_non_nullable
              as String?,
      lastSwapAt: freezed == lastSwapAt
          ? _value.lastSwapAt
          : lastSwapAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastSwapFromTargetId: freezed == lastSwapFromTargetId
          ? _value.lastSwapFromTargetId
          : lastSwapFromTargetId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastSwapToTargetId: freezed == lastSwapToTargetId
          ? _value.lastSwapToTargetId
          : lastSwapToTargetId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastObservedScore: freezed == lastObservedScore
          ? _value.lastObservedScore
          : lastObservedScore // ignore: cast_nullable_to_non_nullable
              as double?,
      configuredThreshold: freezed == configuredThreshold
          ? _value.configuredThreshold
          : configuredThreshold // ignore: cast_nullable_to_non_nullable
              as double?,
      configuredHysteresisSecs: null == configuredHysteresisSecs
          ? _value.configuredHysteresisSecs
          : configuredHysteresisSecs // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$AdaptiveSwapRuntimeStateImplCopyWith<$Res>
    implements $AdaptiveSwapRuntimeStateCopyWith<$Res> {
  factory _$$AdaptiveSwapRuntimeStateImplCopyWith(
          _$AdaptiveSwapRuntimeStateImpl value,
          $Res Function(_$AdaptiveSwapRuntimeStateImpl) then) =
      __$$AdaptiveSwapRuntimeStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String? currentTargetId,
      String? currentTier,
      String? lastDecisionKind,
      String? lastDecisionReason,
      @JsonKey(name: 'last_swap_unix_secs')
      @NullableUnixSecsDateTimeConverter()
      DateTime? lastSwapAt,
      String? lastSwapFromTargetId,
      String? lastSwapToTargetId,
      double? lastObservedScore,
      double? configuredThreshold,
      double configuredHysteresisSecs});
}

/// @nodoc
class __$$AdaptiveSwapRuntimeStateImplCopyWithImpl<$Res>
    extends _$AdaptiveSwapRuntimeStateCopyWithImpl<$Res,
        _$AdaptiveSwapRuntimeStateImpl>
    implements _$$AdaptiveSwapRuntimeStateImplCopyWith<$Res> {
  __$$AdaptiveSwapRuntimeStateImplCopyWithImpl(
      _$AdaptiveSwapRuntimeStateImpl _value,
      $Res Function(_$AdaptiveSwapRuntimeStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentTargetId = freezed,
    Object? currentTier = freezed,
    Object? lastDecisionKind = freezed,
    Object? lastDecisionReason = freezed,
    Object? lastSwapAt = freezed,
    Object? lastSwapFromTargetId = freezed,
    Object? lastSwapToTargetId = freezed,
    Object? lastObservedScore = freezed,
    Object? configuredThreshold = freezed,
    Object? configuredHysteresisSecs = null,
  }) {
    return _then(_$AdaptiveSwapRuntimeStateImpl(
      currentTargetId: freezed == currentTargetId
          ? _value.currentTargetId
          : currentTargetId // ignore: cast_nullable_to_non_nullable
              as String?,
      currentTier: freezed == currentTier
          ? _value.currentTier
          : currentTier // ignore: cast_nullable_to_non_nullable
              as String?,
      lastDecisionKind: freezed == lastDecisionKind
          ? _value.lastDecisionKind
          : lastDecisionKind // ignore: cast_nullable_to_non_nullable
              as String?,
      lastDecisionReason: freezed == lastDecisionReason
          ? _value.lastDecisionReason
          : lastDecisionReason // ignore: cast_nullable_to_non_nullable
              as String?,
      lastSwapAt: freezed == lastSwapAt
          ? _value.lastSwapAt
          : lastSwapAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      lastSwapFromTargetId: freezed == lastSwapFromTargetId
          ? _value.lastSwapFromTargetId
          : lastSwapFromTargetId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastSwapToTargetId: freezed == lastSwapToTargetId
          ? _value.lastSwapToTargetId
          : lastSwapToTargetId // ignore: cast_nullable_to_non_nullable
              as String?,
      lastObservedScore: freezed == lastObservedScore
          ? _value.lastObservedScore
          : lastObservedScore // ignore: cast_nullable_to_non_nullable
              as double?,
      configuredThreshold: freezed == configuredThreshold
          ? _value.configuredThreshold
          : configuredThreshold // ignore: cast_nullable_to_non_nullable
              as double?,
      configuredHysteresisSecs: null == configuredHysteresisSecs
          ? _value.configuredHysteresisSecs
          : configuredHysteresisSecs // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: true)
class _$AdaptiveSwapRuntimeStateImpl extends _AdaptiveSwapRuntimeState {
  const _$AdaptiveSwapRuntimeStateImpl(
      {this.currentTargetId,
      this.currentTier,
      this.lastDecisionKind,
      this.lastDecisionReason,
      @JsonKey(name: 'last_swap_unix_secs')
      @NullableUnixSecsDateTimeConverter()
      this.lastSwapAt,
      this.lastSwapFromTargetId,
      this.lastSwapToTargetId,
      this.lastObservedScore,
      this.configuredThreshold,
      this.configuredHysteresisSecs = 180.0})
      : super._();

  factory _$AdaptiveSwapRuntimeStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$AdaptiveSwapRuntimeStateImplFromJson(json);

  @override
  final String? currentTargetId;
  @override
  final String? currentTier;
  @override
  final String? lastDecisionKind;
  @override
  final String? lastDecisionReason;
// `last_swap_unix_secs` (nullable int seconds). When `null`, the
// JSON field is present-with-null (not omitted) — Phase 1's
// `null_last_swap_serialises_as_null_field` contract test pins this.
  @override
  @JsonKey(name: 'last_swap_unix_secs')
  @NullableUnixSecsDateTimeConverter()
  final DateTime? lastSwapAt;
  @override
  final String? lastSwapFromTargetId;
  @override
  final String? lastSwapToTargetId;
  @override
  final double? lastObservedScore;
  @override
  final double? configuredThreshold;
  @override
  @JsonKey()
  final double configuredHysteresisSecs;

  @override
  String toString() {
    return 'AdaptiveSwapRuntimeState(currentTargetId: $currentTargetId, currentTier: $currentTier, lastDecisionKind: $lastDecisionKind, lastDecisionReason: $lastDecisionReason, lastSwapAt: $lastSwapAt, lastSwapFromTargetId: $lastSwapFromTargetId, lastSwapToTargetId: $lastSwapToTargetId, lastObservedScore: $lastObservedScore, configuredThreshold: $configuredThreshold, configuredHysteresisSecs: $configuredHysteresisSecs)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AdaptiveSwapRuntimeStateImpl &&
            (identical(other.currentTargetId, currentTargetId) ||
                other.currentTargetId == currentTargetId) &&
            (identical(other.currentTier, currentTier) ||
                other.currentTier == currentTier) &&
            (identical(other.lastDecisionKind, lastDecisionKind) ||
                other.lastDecisionKind == lastDecisionKind) &&
            (identical(other.lastDecisionReason, lastDecisionReason) ||
                other.lastDecisionReason == lastDecisionReason) &&
            (identical(other.lastSwapAt, lastSwapAt) ||
                other.lastSwapAt == lastSwapAt) &&
            (identical(other.lastSwapFromTargetId, lastSwapFromTargetId) ||
                other.lastSwapFromTargetId == lastSwapFromTargetId) &&
            (identical(other.lastSwapToTargetId, lastSwapToTargetId) ||
                other.lastSwapToTargetId == lastSwapToTargetId) &&
            (identical(other.lastObservedScore, lastObservedScore) ||
                other.lastObservedScore == lastObservedScore) &&
            (identical(other.configuredThreshold, configuredThreshold) ||
                other.configuredThreshold == configuredThreshold) &&
            (identical(
                    other.configuredHysteresisSecs, configuredHysteresisSecs) ||
                other.configuredHysteresisSecs == configuredHysteresisSecs));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      currentTargetId,
      currentTier,
      lastDecisionKind,
      lastDecisionReason,
      lastSwapAt,
      lastSwapFromTargetId,
      lastSwapToTargetId,
      lastObservedScore,
      configuredThreshold,
      configuredHysteresisSecs);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AdaptiveSwapRuntimeStateImplCopyWith<_$AdaptiveSwapRuntimeStateImpl>
      get copyWith => __$$AdaptiveSwapRuntimeStateImplCopyWithImpl<
          _$AdaptiveSwapRuntimeStateImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AdaptiveSwapRuntimeStateImplToJson(
      this,
    );
  }
}

abstract class _AdaptiveSwapRuntimeState extends AdaptiveSwapRuntimeState {
  const factory _AdaptiveSwapRuntimeState(
      {final String? currentTargetId,
      final String? currentTier,
      final String? lastDecisionKind,
      final String? lastDecisionReason,
      @JsonKey(name: 'last_swap_unix_secs')
      @NullableUnixSecsDateTimeConverter()
      final DateTime? lastSwapAt,
      final String? lastSwapFromTargetId,
      final String? lastSwapToTargetId,
      final double? lastObservedScore,
      final double? configuredThreshold,
      final double configuredHysteresisSecs}) = _$AdaptiveSwapRuntimeStateImpl;
  const _AdaptiveSwapRuntimeState._() : super._();

  factory _AdaptiveSwapRuntimeState.fromJson(Map<String, dynamic> json) =
      _$AdaptiveSwapRuntimeStateImpl.fromJson;

  @override
  String? get currentTargetId;
  @override
  String? get currentTier;
  @override
  String? get lastDecisionKind;
  @override
  String? get lastDecisionReason;
  @override // `last_swap_unix_secs` (nullable int seconds). When `null`, the
// JSON field is present-with-null (not omitted) — Phase 1's
// `null_last_swap_serialises_as_null_field` contract test pins this.
  @JsonKey(name: 'last_swap_unix_secs')
  @NullableUnixSecsDateTimeConverter()
  DateTime? get lastSwapAt;
  @override
  String? get lastSwapFromTargetId;
  @override
  String? get lastSwapToTargetId;
  @override
  double? get lastObservedScore;
  @override
  double? get configuredThreshold;
  @override
  double get configuredHysteresisSecs;
  @override
  @JsonKey(ignore: true)
  _$$AdaptiveSwapRuntimeStateImplCopyWith<_$AdaptiveSwapRuntimeStateImpl>
      get copyWith => throw _privateConstructorUsedError;
}

AdaptiveSwapSnapshot _$AdaptiveSwapSnapshotFromJson(Map<String, dynamic> json) {
  return _AdaptiveSwapSnapshot.fromJson(json);
}

/// @nodoc
mixin _$AdaptiveSwapSnapshot {
  ConditionsScore? get score =>
      throw _privateConstructorUsedError; // Default empty state used when the JSON payload is missing
// `state` entirely (Phase 1's
// `from_json_treats_missing_state_as_default_state` contract test).
  AdaptiveSwapRuntimeState get state => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $AdaptiveSwapSnapshotCopyWith<AdaptiveSwapSnapshot> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $AdaptiveSwapSnapshotCopyWith<$Res> {
  factory $AdaptiveSwapSnapshotCopyWith(AdaptiveSwapSnapshot value,
          $Res Function(AdaptiveSwapSnapshot) then) =
      _$AdaptiveSwapSnapshotCopyWithImpl<$Res, AdaptiveSwapSnapshot>;
  @useResult
  $Res call({ConditionsScore? score, AdaptiveSwapRuntimeState state});

  $ConditionsScoreCopyWith<$Res>? get score;
  $AdaptiveSwapRuntimeStateCopyWith<$Res> get state;
}

/// @nodoc
class _$AdaptiveSwapSnapshotCopyWithImpl<$Res,
        $Val extends AdaptiveSwapSnapshot>
    implements $AdaptiveSwapSnapshotCopyWith<$Res> {
  _$AdaptiveSwapSnapshotCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? score = freezed,
    Object? state = null,
  }) {
    return _then(_value.copyWith(
      score: freezed == score
          ? _value.score
          : score // ignore: cast_nullable_to_non_nullable
              as ConditionsScore?,
      state: null == state
          ? _value.state
          : state // ignore: cast_nullable_to_non_nullable
              as AdaptiveSwapRuntimeState,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $ConditionsScoreCopyWith<$Res>? get score {
    if (_value.score == null) {
      return null;
    }

    return $ConditionsScoreCopyWith<$Res>(_value.score!, (value) {
      return _then(_value.copyWith(score: value) as $Val);
    });
  }

  @override
  @pragma('vm:prefer-inline')
  $AdaptiveSwapRuntimeStateCopyWith<$Res> get state {
    return $AdaptiveSwapRuntimeStateCopyWith<$Res>(_value.state, (value) {
      return _then(_value.copyWith(state: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$AdaptiveSwapSnapshotImplCopyWith<$Res>
    implements $AdaptiveSwapSnapshotCopyWith<$Res> {
  factory _$$AdaptiveSwapSnapshotImplCopyWith(_$AdaptiveSwapSnapshotImpl value,
          $Res Function(_$AdaptiveSwapSnapshotImpl) then) =
      __$$AdaptiveSwapSnapshotImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({ConditionsScore? score, AdaptiveSwapRuntimeState state});

  @override
  $ConditionsScoreCopyWith<$Res>? get score;
  @override
  $AdaptiveSwapRuntimeStateCopyWith<$Res> get state;
}

/// @nodoc
class __$$AdaptiveSwapSnapshotImplCopyWithImpl<$Res>
    extends _$AdaptiveSwapSnapshotCopyWithImpl<$Res, _$AdaptiveSwapSnapshotImpl>
    implements _$$AdaptiveSwapSnapshotImplCopyWith<$Res> {
  __$$AdaptiveSwapSnapshotImplCopyWithImpl(_$AdaptiveSwapSnapshotImpl _value,
      $Res Function(_$AdaptiveSwapSnapshotImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? score = freezed,
    Object? state = null,
  }) {
    return _then(_$AdaptiveSwapSnapshotImpl(
      score: freezed == score
          ? _value.score
          : score // ignore: cast_nullable_to_non_nullable
              as ConditionsScore?,
      state: null == state
          ? _value.state
          : state // ignore: cast_nullable_to_non_nullable
              as AdaptiveSwapRuntimeState,
    ));
  }
}

/// @nodoc

@JsonSerializable(explicitToJson: true)
class _$AdaptiveSwapSnapshotImpl implements _AdaptiveSwapSnapshot {
  const _$AdaptiveSwapSnapshotImpl(
      {this.score, this.state = const AdaptiveSwapRuntimeState()});

  factory _$AdaptiveSwapSnapshotImpl.fromJson(Map<String, dynamic> json) =>
      _$$AdaptiveSwapSnapshotImplFromJson(json);

  @override
  final ConditionsScore? score;
// Default empty state used when the JSON payload is missing
// `state` entirely (Phase 1's
// `from_json_treats_missing_state_as_default_state` contract test).
  @override
  @JsonKey()
  final AdaptiveSwapRuntimeState state;

  @override
  String toString() {
    return 'AdaptiveSwapSnapshot(score: $score, state: $state)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$AdaptiveSwapSnapshotImpl &&
            (identical(other.score, score) || other.score == score) &&
            (identical(other.state, state) || other.state == state));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, score, state);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$AdaptiveSwapSnapshotImplCopyWith<_$AdaptiveSwapSnapshotImpl>
      get copyWith =>
          __$$AdaptiveSwapSnapshotImplCopyWithImpl<_$AdaptiveSwapSnapshotImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$AdaptiveSwapSnapshotImplToJson(
      this,
    );
  }
}

abstract class _AdaptiveSwapSnapshot implements AdaptiveSwapSnapshot {
  const factory _AdaptiveSwapSnapshot(
      {final ConditionsScore? score,
      final AdaptiveSwapRuntimeState state}) = _$AdaptiveSwapSnapshotImpl;

  factory _AdaptiveSwapSnapshot.fromJson(Map<String, dynamic> json) =
      _$AdaptiveSwapSnapshotImpl.fromJson;

  @override
  ConditionsScore? get score;
  @override // Default empty state used when the JSON payload is missing
// `state` entirely (Phase 1's
// `from_json_treats_missing_state_as_default_state` contract test).
  AdaptiveSwapRuntimeState get state;
  @override
  @JsonKey(ignore: true)
  _$$AdaptiveSwapSnapshotImplCopyWith<_$AdaptiveSwapSnapshotImpl>
      get copyWith => throw _privateConstructorUsedError;
}

FilterPlan _$FilterPlanFromJson(Map<String, dynamic> json) {
  return _FilterPlan.fromJson(json);
}

/// @nodoc
mixin _$FilterPlan {
  /// Filter wheel slot name (e.g. "L", "Ha"). Matched against the
  /// connected filter wheel's name list when [filterIndex] is null.
  String get filterName => throw _privateConstructorUsedError;

  /// 0-based filter wheel index. Preferred over [filterName] for
  /// reliability — matches `ExposureNode.filterIndex` / Rust
  /// `FilterConfig::filter_index`.
  int? get filterIndex => throw _privateConstructorUsedError;

  /// Total number of exposures to take for this filter.
  int get count => throw _privateConstructorUsedError;

  /// Sub-exposure duration in seconds.
  double get durationSecs => throw _privateConstructorUsedError;

  /// Optional gain override. null means "use camera/profile default".
  int? get gain => throw _privateConstructorUsedError;

  /// Optional offset override.
  int? get offset => throw _privateConstructorUsedError;

  /// Binning for this filter. Defaults to 1x1.
  @BinningModeJsonConverter()
  BinningMode get binning => throw _privateConstructorUsedError;

  /// Per-plan dither cadence (every N frames). null disables dithering for
  /// this filter regardless of any global default. 0 is treated as "no
  /// dither" — matches `ExposureNode.ditherEvery`.
  int? get ditherEvery => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $FilterPlanCopyWith<FilterPlan> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FilterPlanCopyWith<$Res> {
  factory $FilterPlanCopyWith(
          FilterPlan value, $Res Function(FilterPlan) then) =
      _$FilterPlanCopyWithImpl<$Res, FilterPlan>;
  @useResult
  $Res call(
      {String filterName,
      int? filterIndex,
      int count,
      double durationSecs,
      int? gain,
      int? offset,
      @BinningModeJsonConverter() BinningMode binning,
      int? ditherEvery});
}

/// @nodoc
class _$FilterPlanCopyWithImpl<$Res, $Val extends FilterPlan>
    implements $FilterPlanCopyWith<$Res> {
  _$FilterPlanCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? filterName = null,
    Object? filterIndex = freezed,
    Object? count = null,
    Object? durationSecs = null,
    Object? gain = freezed,
    Object? offset = freezed,
    Object? binning = null,
    Object? ditherEvery = freezed,
  }) {
    return _then(_value.copyWith(
      filterName: null == filterName
          ? _value.filterName
          : filterName // ignore: cast_nullable_to_non_nullable
              as String,
      filterIndex: freezed == filterIndex
          ? _value.filterIndex
          : filterIndex // ignore: cast_nullable_to_non_nullable
              as int?,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
      durationSecs: null == durationSecs
          ? _value.durationSecs
          : durationSecs // ignore: cast_nullable_to_non_nullable
              as double,
      gain: freezed == gain
          ? _value.gain
          : gain // ignore: cast_nullable_to_non_nullable
              as int?,
      offset: freezed == offset
          ? _value.offset
          : offset // ignore: cast_nullable_to_non_nullable
              as int?,
      binning: null == binning
          ? _value.binning
          : binning // ignore: cast_nullable_to_non_nullable
              as BinningMode,
      ditherEvery: freezed == ditherEvery
          ? _value.ditherEvery
          : ditherEvery // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$FilterPlanImplCopyWith<$Res>
    implements $FilterPlanCopyWith<$Res> {
  factory _$$FilterPlanImplCopyWith(
          _$FilterPlanImpl value, $Res Function(_$FilterPlanImpl) then) =
      __$$FilterPlanImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String filterName,
      int? filterIndex,
      int count,
      double durationSecs,
      int? gain,
      int? offset,
      @BinningModeJsonConverter() BinningMode binning,
      int? ditherEvery});
}

/// @nodoc
class __$$FilterPlanImplCopyWithImpl<$Res>
    extends _$FilterPlanCopyWithImpl<$Res, _$FilterPlanImpl>
    implements _$$FilterPlanImplCopyWith<$Res> {
  __$$FilterPlanImplCopyWithImpl(
      _$FilterPlanImpl _value, $Res Function(_$FilterPlanImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? filterName = null,
    Object? filterIndex = freezed,
    Object? count = null,
    Object? durationSecs = null,
    Object? gain = freezed,
    Object? offset = freezed,
    Object? binning = null,
    Object? ditherEvery = freezed,
  }) {
    return _then(_$FilterPlanImpl(
      filterName: null == filterName
          ? _value.filterName
          : filterName // ignore: cast_nullable_to_non_nullable
              as String,
      filterIndex: freezed == filterIndex
          ? _value.filterIndex
          : filterIndex // ignore: cast_nullable_to_non_nullable
              as int?,
      count: null == count
          ? _value.count
          : count // ignore: cast_nullable_to_non_nullable
              as int,
      durationSecs: null == durationSecs
          ? _value.durationSecs
          : durationSecs // ignore: cast_nullable_to_non_nullable
              as double,
      gain: freezed == gain
          ? _value.gain
          : gain // ignore: cast_nullable_to_non_nullable
              as int?,
      offset: freezed == offset
          ? _value.offset
          : offset // ignore: cast_nullable_to_non_nullable
              as int?,
      binning: null == binning
          ? _value.binning
          : binning // ignore: cast_nullable_to_non_nullable
              as BinningMode,
      ditherEvery: freezed == ditherEvery
          ? _value.ditherEvery
          : ditherEvery // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: true)
class _$FilterPlanImpl extends _FilterPlan {
  const _$FilterPlanImpl(
      {this.filterName = '',
      this.filterIndex,
      this.count = 10,
      this.durationSecs = 60.0,
      this.gain,
      this.offset,
      @BinningModeJsonConverter() this.binning = BinningMode.one,
      this.ditherEvery})
      : super._();

  factory _$FilterPlanImpl.fromJson(Map<String, dynamic> json) =>
      _$$FilterPlanImplFromJson(json);

  /// Filter wheel slot name (e.g. "L", "Ha"). Matched against the
  /// connected filter wheel's name list when [filterIndex] is null.
  @override
  @JsonKey()
  final String filterName;

  /// 0-based filter wheel index. Preferred over [filterName] for
  /// reliability — matches `ExposureNode.filterIndex` / Rust
  /// `FilterConfig::filter_index`.
  @override
  final int? filterIndex;

  /// Total number of exposures to take for this filter.
  @override
  @JsonKey()
  final int count;

  /// Sub-exposure duration in seconds.
  @override
  @JsonKey()
  final double durationSecs;

  /// Optional gain override. null means "use camera/profile default".
  @override
  final int? gain;

  /// Optional offset override.
  @override
  final int? offset;

  /// Binning for this filter. Defaults to 1x1.
  @override
  @JsonKey()
  @BinningModeJsonConverter()
  final BinningMode binning;

  /// Per-plan dither cadence (every N frames). null disables dithering for
  /// this filter regardless of any global default. 0 is treated as "no
  /// dither" — matches `ExposureNode.ditherEvery`.
  @override
  final int? ditherEvery;

  @override
  String toString() {
    return 'FilterPlan(filterName: $filterName, filterIndex: $filterIndex, count: $count, durationSecs: $durationSecs, gain: $gain, offset: $offset, binning: $binning, ditherEvery: $ditherEvery)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FilterPlanImpl &&
            (identical(other.filterName, filterName) ||
                other.filterName == filterName) &&
            (identical(other.filterIndex, filterIndex) ||
                other.filterIndex == filterIndex) &&
            (identical(other.count, count) || other.count == count) &&
            (identical(other.durationSecs, durationSecs) ||
                other.durationSecs == durationSecs) &&
            (identical(other.gain, gain) || other.gain == gain) &&
            (identical(other.offset, offset) || other.offset == offset) &&
            (identical(other.binning, binning) || other.binning == binning) &&
            (identical(other.ditherEvery, ditherEvery) ||
                other.ditherEvery == ditherEvery));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, filterName, filterIndex, count,
      durationSecs, gain, offset, binning, ditherEvery);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$FilterPlanImplCopyWith<_$FilterPlanImpl> get copyWith =>
      __$$FilterPlanImplCopyWithImpl<_$FilterPlanImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$FilterPlanImplToJson(
      this,
    );
  }
}

abstract class _FilterPlan extends FilterPlan {
  const factory _FilterPlan(
      {final String filterName,
      final int? filterIndex,
      final int count,
      final double durationSecs,
      final int? gain,
      final int? offset,
      @BinningModeJsonConverter() final BinningMode binning,
      final int? ditherEvery}) = _$FilterPlanImpl;
  const _FilterPlan._() : super._();

  factory _FilterPlan.fromJson(Map<String, dynamic> json) =
      _$FilterPlanImpl.fromJson;

  @override

  /// Filter wheel slot name (e.g. "L", "Ha"). Matched against the
  /// connected filter wheel's name list when [filterIndex] is null.
  String get filterName;
  @override

  /// 0-based filter wheel index. Preferred over [filterName] for
  /// reliability — matches `ExposureNode.filterIndex` / Rust
  /// `FilterConfig::filter_index`.
  int? get filterIndex;
  @override

  /// Total number of exposures to take for this filter.
  int get count;
  @override

  /// Sub-exposure duration in seconds.
  double get durationSecs;
  @override

  /// Optional gain override. null means "use camera/profile default".
  int? get gain;
  @override

  /// Optional offset override.
  int? get offset;
  @override

  /// Binning for this filter. Defaults to 1x1.
  @BinningModeJsonConverter()
  BinningMode get binning;
  @override

  /// Per-plan dither cadence (every N frames). null disables dithering for
  /// this filter regardless of any global default. 0 is treated as "no
  /// dither" — matches `ExposureNode.ditherEvery`.
  int? get ditherEvery;
  @override
  @JsonKey(ignore: true)
  _$$FilterPlanImplCopyWith<_$FilterPlanImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PhotometryQualityGates _$PhotometryQualityGatesFromJson(
    Map<String, dynamic> json) {
  return _PhotometryQualityGates.fromJson(json);
}

/// @nodoc
mixin _$PhotometryQualityGates {
  /// Minimum target SNR. AAVSO research-grade default is 50.
  double get minSnr => throw _privateConstructorUsedError;

  /// Maximum acceptable FWHM in arcseconds. Default 5".
  double get maxFwhmArcsec => throw _privateConstructorUsedError;

  /// When true, frames where any reference star failed to extract are
  /// rejected.
  bool get requireAllRefsVisible => throw _privateConstructorUsedError;

  /// Maximum airmass. AAVSO Bright Star Monitor cut-off ≈ 2.5.
  double get maxAirmass => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PhotometryQualityGatesCopyWith<PhotometryQualityGates> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PhotometryQualityGatesCopyWith<$Res> {
  factory $PhotometryQualityGatesCopyWith(PhotometryQualityGates value,
          $Res Function(PhotometryQualityGates) then) =
      _$PhotometryQualityGatesCopyWithImpl<$Res, PhotometryQualityGates>;
  @useResult
  $Res call(
      {double minSnr,
      double maxFwhmArcsec,
      bool requireAllRefsVisible,
      double maxAirmass});
}

/// @nodoc
class _$PhotometryQualityGatesCopyWithImpl<$Res,
        $Val extends PhotometryQualityGates>
    implements $PhotometryQualityGatesCopyWith<$Res> {
  _$PhotometryQualityGatesCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minSnr = null,
    Object? maxFwhmArcsec = null,
    Object? requireAllRefsVisible = null,
    Object? maxAirmass = null,
  }) {
    return _then(_value.copyWith(
      minSnr: null == minSnr
          ? _value.minSnr
          : minSnr // ignore: cast_nullable_to_non_nullable
              as double,
      maxFwhmArcsec: null == maxFwhmArcsec
          ? _value.maxFwhmArcsec
          : maxFwhmArcsec // ignore: cast_nullable_to_non_nullable
              as double,
      requireAllRefsVisible: null == requireAllRefsVisible
          ? _value.requireAllRefsVisible
          : requireAllRefsVisible // ignore: cast_nullable_to_non_nullable
              as bool,
      maxAirmass: null == maxAirmass
          ? _value.maxAirmass
          : maxAirmass // ignore: cast_nullable_to_non_nullable
              as double,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PhotometryQualityGatesImplCopyWith<$Res>
    implements $PhotometryQualityGatesCopyWith<$Res> {
  factory _$$PhotometryQualityGatesImplCopyWith(
          _$PhotometryQualityGatesImpl value,
          $Res Function(_$PhotometryQualityGatesImpl) then) =
      __$$PhotometryQualityGatesImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double minSnr,
      double maxFwhmArcsec,
      bool requireAllRefsVisible,
      double maxAirmass});
}

/// @nodoc
class __$$PhotometryQualityGatesImplCopyWithImpl<$Res>
    extends _$PhotometryQualityGatesCopyWithImpl<$Res,
        _$PhotometryQualityGatesImpl>
    implements _$$PhotometryQualityGatesImplCopyWith<$Res> {
  __$$PhotometryQualityGatesImplCopyWithImpl(
      _$PhotometryQualityGatesImpl _value,
      $Res Function(_$PhotometryQualityGatesImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? minSnr = null,
    Object? maxFwhmArcsec = null,
    Object? requireAllRefsVisible = null,
    Object? maxAirmass = null,
  }) {
    return _then(_$PhotometryQualityGatesImpl(
      minSnr: null == minSnr
          ? _value.minSnr
          : minSnr // ignore: cast_nullable_to_non_nullable
              as double,
      maxFwhmArcsec: null == maxFwhmArcsec
          ? _value.maxFwhmArcsec
          : maxFwhmArcsec // ignore: cast_nullable_to_non_nullable
              as double,
      requireAllRefsVisible: null == requireAllRefsVisible
          ? _value.requireAllRefsVisible
          : requireAllRefsVisible // ignore: cast_nullable_to_non_nullable
              as bool,
      maxAirmass: null == maxAirmass
          ? _value.maxAirmass
          : maxAirmass // ignore: cast_nullable_to_non_nullable
              as double,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _$PhotometryQualityGatesImpl implements _PhotometryQualityGates {
  const _$PhotometryQualityGatesImpl(
      {this.minSnr = 50.0,
      this.maxFwhmArcsec = 5.0,
      this.requireAllRefsVisible = true,
      this.maxAirmass = 2.5});

  factory _$PhotometryQualityGatesImpl.fromJson(Map<String, dynamic> json) =>
      _$$PhotometryQualityGatesImplFromJson(json);

  /// Minimum target SNR. AAVSO research-grade default is 50.
  @override
  @JsonKey()
  final double minSnr;

  /// Maximum acceptable FWHM in arcseconds. Default 5".
  @override
  @JsonKey()
  final double maxFwhmArcsec;

  /// When true, frames where any reference star failed to extract are
  /// rejected.
  @override
  @JsonKey()
  final bool requireAllRefsVisible;

  /// Maximum airmass. AAVSO Bright Star Monitor cut-off ≈ 2.5.
  @override
  @JsonKey()
  final double maxAirmass;

  @override
  String toString() {
    return 'PhotometryQualityGates(minSnr: $minSnr, maxFwhmArcsec: $maxFwhmArcsec, requireAllRefsVisible: $requireAllRefsVisible, maxAirmass: $maxAirmass)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PhotometryQualityGatesImpl &&
            (identical(other.minSnr, minSnr) || other.minSnr == minSnr) &&
            (identical(other.maxFwhmArcsec, maxFwhmArcsec) ||
                other.maxFwhmArcsec == maxFwhmArcsec) &&
            (identical(other.requireAllRefsVisible, requireAllRefsVisible) ||
                other.requireAllRefsVisible == requireAllRefsVisible) &&
            (identical(other.maxAirmass, maxAirmass) ||
                other.maxAirmass == maxAirmass));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType, minSnr, maxFwhmArcsec, requireAllRefsVisible, maxAirmass);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PhotometryQualityGatesImplCopyWith<_$PhotometryQualityGatesImpl>
      get copyWith => __$$PhotometryQualityGatesImplCopyWithImpl<
          _$PhotometryQualityGatesImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PhotometryQualityGatesImplToJson(
      this,
    );
  }
}

abstract class _PhotometryQualityGates implements PhotometryQualityGates {
  const factory _PhotometryQualityGates(
      {final double minSnr,
      final double maxFwhmArcsec,
      final bool requireAllRefsVisible,
      final double maxAirmass}) = _$PhotometryQualityGatesImpl;

  factory _PhotometryQualityGates.fromJson(Map<String, dynamic> json) =
      _$PhotometryQualityGatesImpl.fromJson;

  @override

  /// Minimum target SNR. AAVSO research-grade default is 50.
  double get minSnr;
  @override

  /// Maximum acceptable FWHM in arcseconds. Default 5".
  double get maxFwhmArcsec;
  @override

  /// When true, frames where any reference star failed to extract are
  /// rejected.
  bool get requireAllRefsVisible;
  @override

  /// Maximum airmass. AAVSO Bright Star Monitor cut-off ≈ 2.5.
  double get maxAirmass;
  @override
  @JsonKey(ignore: true)
  _$$PhotometryQualityGatesImplCopyWith<_$PhotometryQualityGatesImpl>
      get copyWith => throw _privateConstructorUsedError;
}

TransparencyBackupPlan _$TransparencyBackupPlanFromJson(
    Map<String, dynamic> json) {
  return _TransparencyBackupPlan.fromJson(json);
}

/// @nodoc
mixin _$TransparencyBackupPlan {
  /// Filter to switch to when transparency drops (e.g. `"Lum"`).
  String? get backupFilter => throw _privateConstructorUsedError;

  /// Sequence node id to skip to when transparency drops.
  String? get backupTargetId => throw _privateConstructorUsedError;

  /// Optional human-readable description surfaced in the UI / logs.
  String? get description => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $TransparencyBackupPlanCopyWith<TransparencyBackupPlan> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TransparencyBackupPlanCopyWith<$Res> {
  factory $TransparencyBackupPlanCopyWith(TransparencyBackupPlan value,
          $Res Function(TransparencyBackupPlan) then) =
      _$TransparencyBackupPlanCopyWithImpl<$Res, TransparencyBackupPlan>;
  @useResult
  $Res call(
      {String? backupFilter, String? backupTargetId, String? description});
}

/// @nodoc
class _$TransparencyBackupPlanCopyWithImpl<$Res,
        $Val extends TransparencyBackupPlan>
    implements $TransparencyBackupPlanCopyWith<$Res> {
  _$TransparencyBackupPlanCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? backupFilter = freezed,
    Object? backupTargetId = freezed,
    Object? description = freezed,
  }) {
    return _then(_value.copyWith(
      backupFilter: freezed == backupFilter
          ? _value.backupFilter
          : backupFilter // ignore: cast_nullable_to_non_nullable
              as String?,
      backupTargetId: freezed == backupTargetId
          ? _value.backupTargetId
          : backupTargetId // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$TransparencyBackupPlanImplCopyWith<$Res>
    implements $TransparencyBackupPlanCopyWith<$Res> {
  factory _$$TransparencyBackupPlanImplCopyWith(
          _$TransparencyBackupPlanImpl value,
          $Res Function(_$TransparencyBackupPlanImpl) then) =
      __$$TransparencyBackupPlanImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String? backupFilter, String? backupTargetId, String? description});
}

/// @nodoc
class __$$TransparencyBackupPlanImplCopyWithImpl<$Res>
    extends _$TransparencyBackupPlanCopyWithImpl<$Res,
        _$TransparencyBackupPlanImpl>
    implements _$$TransparencyBackupPlanImplCopyWith<$Res> {
  __$$TransparencyBackupPlanImplCopyWithImpl(
      _$TransparencyBackupPlanImpl _value,
      $Res Function(_$TransparencyBackupPlanImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? backupFilter = freezed,
    Object? backupTargetId = freezed,
    Object? description = freezed,
  }) {
    return _then(_$TransparencyBackupPlanImpl(
      backupFilter: freezed == backupFilter
          ? _value.backupFilter
          : backupFilter // ignore: cast_nullable_to_non_nullable
              as String?,
      backupTargetId: freezed == backupTargetId
          ? _value.backupTargetId
          : backupTargetId // ignore: cast_nullable_to_non_nullable
              as String?,
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake, includeIfNull: true)
class _$TransparencyBackupPlanImpl extends _TransparencyBackupPlan {
  const _$TransparencyBackupPlanImpl(
      {this.backupFilter, this.backupTargetId, this.description})
      : super._();

  factory _$TransparencyBackupPlanImpl.fromJson(Map<String, dynamic> json) =>
      _$$TransparencyBackupPlanImplFromJson(json);

  /// Filter to switch to when transparency drops (e.g. `"Lum"`).
  @override
  final String? backupFilter;

  /// Sequence node id to skip to when transparency drops.
  @override
  final String? backupTargetId;

  /// Optional human-readable description surfaced in the UI / logs.
  @override
  final String? description;

  @override
  String toString() {
    return 'TransparencyBackupPlan(backupFilter: $backupFilter, backupTargetId: $backupTargetId, description: $description)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TransparencyBackupPlanImpl &&
            (identical(other.backupFilter, backupFilter) ||
                other.backupFilter == backupFilter) &&
            (identical(other.backupTargetId, backupTargetId) ||
                other.backupTargetId == backupTargetId) &&
            (identical(other.description, description) ||
                other.description == description));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode =>
      Object.hash(runtimeType, backupFilter, backupTargetId, description);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$TransparencyBackupPlanImplCopyWith<_$TransparencyBackupPlanImpl>
      get copyWith => __$$TransparencyBackupPlanImplCopyWithImpl<
          _$TransparencyBackupPlanImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$TransparencyBackupPlanImplToJson(
      this,
    );
  }
}

abstract class _TransparencyBackupPlan extends TransparencyBackupPlan {
  const factory _TransparencyBackupPlan(
      {final String? backupFilter,
      final String? backupTargetId,
      final String? description}) = _$TransparencyBackupPlanImpl;
  const _TransparencyBackupPlan._() : super._();

  factory _TransparencyBackupPlan.fromJson(Map<String, dynamic> json) =
      _$TransparencyBackupPlanImpl.fromJson;

  @override

  /// Filter to switch to when transparency drops (e.g. `"Lum"`).
  String? get backupFilter;
  @override

  /// Sequence node id to skip to when transparency drops.
  String? get backupTargetId;
  @override

  /// Optional human-readable description surfaced in the UI / logs.
  String? get description;
  @override
  @JsonKey(ignore: true)
  _$$TransparencyBackupPlanImplCopyWith<_$TransparencyBackupPlanImpl>
      get copyWith => throw _privateConstructorUsedError;
}
