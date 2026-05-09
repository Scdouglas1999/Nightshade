// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'polar_alignment_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

PolarAlignmentConfig _$PolarAlignmentConfigFromJson(Map<String, dynamic> json) {
  return _PolarAlignmentConfig.fromJson(json);
}

/// @nodoc
mixin _$PolarAlignmentConfig {
  /// Exposure time in seconds for each measurement image
  double get exposureTime => throw _privateConstructorUsedError;

  /// Step size in degrees for mount rotation between measurements
  double get stepSize => throw _privateConstructorUsedError;

  /// Camera binning (1, 2, 3, 4)
  int get binning => throw _privateConstructorUsedError;

  /// Whether observing from northern hemisphere
  bool get isNorth => throw _privateConstructorUsedError;

  /// Whether to use manual rotation (user rotates mount) vs automatic slewing
  bool get manualRotation => throw _privateConstructorUsedError;

  /// Direction to rotate (true = east, false = west) for auto rotation
  bool get rotateEast => throw _privateConstructorUsedError;

  /// Timeout in seconds for plate solve attempts
  double get solveTimeout => throw _privateConstructorUsedError;

  /// Total error threshold in arcseconds to consider alignment complete
  /// When error drops below this value, auto-complete can be triggered
  double get autoCompleteThreshold => throw _privateConstructorUsedError;

  /// Whether to start from current mount position or slew to pole first
  bool get startFromCurrent => throw _privateConstructorUsedError;

  /// Camera gain (null = use camera default)
  int? get gain => throw _privateConstructorUsedError;

  /// Camera offset (null = use camera default)
  int? get offset => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PolarAlignmentConfigCopyWith<PolarAlignmentConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PolarAlignmentConfigCopyWith<$Res> {
  factory $PolarAlignmentConfigCopyWith(PolarAlignmentConfig value,
          $Res Function(PolarAlignmentConfig) then) =
      _$PolarAlignmentConfigCopyWithImpl<$Res, PolarAlignmentConfig>;
  @useResult
  $Res call(
      {double exposureTime,
      double stepSize,
      int binning,
      bool isNorth,
      bool manualRotation,
      bool rotateEast,
      double solveTimeout,
      double autoCompleteThreshold,
      bool startFromCurrent,
      int? gain,
      int? offset});
}

/// @nodoc
class _$PolarAlignmentConfigCopyWithImpl<$Res,
        $Val extends PolarAlignmentConfig>
    implements $PolarAlignmentConfigCopyWith<$Res> {
  _$PolarAlignmentConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exposureTime = null,
    Object? stepSize = null,
    Object? binning = null,
    Object? isNorth = null,
    Object? manualRotation = null,
    Object? rotateEast = null,
    Object? solveTimeout = null,
    Object? autoCompleteThreshold = null,
    Object? startFromCurrent = null,
    Object? gain = freezed,
    Object? offset = freezed,
  }) {
    return _then(_value.copyWith(
      exposureTime: null == exposureTime
          ? _value.exposureTime
          : exposureTime // ignore: cast_nullable_to_non_nullable
              as double,
      stepSize: null == stepSize
          ? _value.stepSize
          : stepSize // ignore: cast_nullable_to_non_nullable
              as double,
      binning: null == binning
          ? _value.binning
          : binning // ignore: cast_nullable_to_non_nullable
              as int,
      isNorth: null == isNorth
          ? _value.isNorth
          : isNorth // ignore: cast_nullable_to_non_nullable
              as bool,
      manualRotation: null == manualRotation
          ? _value.manualRotation
          : manualRotation // ignore: cast_nullable_to_non_nullable
              as bool,
      rotateEast: null == rotateEast
          ? _value.rotateEast
          : rotateEast // ignore: cast_nullable_to_non_nullable
              as bool,
      solveTimeout: null == solveTimeout
          ? _value.solveTimeout
          : solveTimeout // ignore: cast_nullable_to_non_nullable
              as double,
      autoCompleteThreshold: null == autoCompleteThreshold
          ? _value.autoCompleteThreshold
          : autoCompleteThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      startFromCurrent: null == startFromCurrent
          ? _value.startFromCurrent
          : startFromCurrent // ignore: cast_nullable_to_non_nullable
              as bool,
      gain: freezed == gain
          ? _value.gain
          : gain // ignore: cast_nullable_to_non_nullable
              as int?,
      offset: freezed == offset
          ? _value.offset
          : offset // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PolarAlignmentConfigImplCopyWith<$Res>
    implements $PolarAlignmentConfigCopyWith<$Res> {
  factory _$$PolarAlignmentConfigImplCopyWith(_$PolarAlignmentConfigImpl value,
          $Res Function(_$PolarAlignmentConfigImpl) then) =
      __$$PolarAlignmentConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double exposureTime,
      double stepSize,
      int binning,
      bool isNorth,
      bool manualRotation,
      bool rotateEast,
      double solveTimeout,
      double autoCompleteThreshold,
      bool startFromCurrent,
      int? gain,
      int? offset});
}

/// @nodoc
class __$$PolarAlignmentConfigImplCopyWithImpl<$Res>
    extends _$PolarAlignmentConfigCopyWithImpl<$Res, _$PolarAlignmentConfigImpl>
    implements _$$PolarAlignmentConfigImplCopyWith<$Res> {
  __$$PolarAlignmentConfigImplCopyWithImpl(_$PolarAlignmentConfigImpl _value,
      $Res Function(_$PolarAlignmentConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? exposureTime = null,
    Object? stepSize = null,
    Object? binning = null,
    Object? isNorth = null,
    Object? manualRotation = null,
    Object? rotateEast = null,
    Object? solveTimeout = null,
    Object? autoCompleteThreshold = null,
    Object? startFromCurrent = null,
    Object? gain = freezed,
    Object? offset = freezed,
  }) {
    return _then(_$PolarAlignmentConfigImpl(
      exposureTime: null == exposureTime
          ? _value.exposureTime
          : exposureTime // ignore: cast_nullable_to_non_nullable
              as double,
      stepSize: null == stepSize
          ? _value.stepSize
          : stepSize // ignore: cast_nullable_to_non_nullable
              as double,
      binning: null == binning
          ? _value.binning
          : binning // ignore: cast_nullable_to_non_nullable
              as int,
      isNorth: null == isNorth
          ? _value.isNorth
          : isNorth // ignore: cast_nullable_to_non_nullable
              as bool,
      manualRotation: null == manualRotation
          ? _value.manualRotation
          : manualRotation // ignore: cast_nullable_to_non_nullable
              as bool,
      rotateEast: null == rotateEast
          ? _value.rotateEast
          : rotateEast // ignore: cast_nullable_to_non_nullable
              as bool,
      solveTimeout: null == solveTimeout
          ? _value.solveTimeout
          : solveTimeout // ignore: cast_nullable_to_non_nullable
              as double,
      autoCompleteThreshold: null == autoCompleteThreshold
          ? _value.autoCompleteThreshold
          : autoCompleteThreshold // ignore: cast_nullable_to_non_nullable
              as double,
      startFromCurrent: null == startFromCurrent
          ? _value.startFromCurrent
          : startFromCurrent // ignore: cast_nullable_to_non_nullable
              as bool,
      gain: freezed == gain
          ? _value.gain
          : gain // ignore: cast_nullable_to_non_nullable
              as int?,
      offset: freezed == offset
          ? _value.offset
          : offset // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PolarAlignmentConfigImpl extends _PolarAlignmentConfig {
  const _$PolarAlignmentConfigImpl(
      {this.exposureTime = 5.0,
      this.stepSize = 15.0,
      this.binning = 2,
      this.isNorth = true,
      this.manualRotation = false,
      this.rotateEast = true,
      this.solveTimeout = 30.0,
      this.autoCompleteThreshold = 30.0,
      this.startFromCurrent = true,
      this.gain,
      this.offset})
      : super._();

  factory _$PolarAlignmentConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$PolarAlignmentConfigImplFromJson(json);

  /// Exposure time in seconds for each measurement image
  @override
  @JsonKey()
  final double exposureTime;

  /// Step size in degrees for mount rotation between measurements
  @override
  @JsonKey()
  final double stepSize;

  /// Camera binning (1, 2, 3, 4)
  @override
  @JsonKey()
  final int binning;

  /// Whether observing from northern hemisphere
  @override
  @JsonKey()
  final bool isNorth;

  /// Whether to use manual rotation (user rotates mount) vs automatic slewing
  @override
  @JsonKey()
  final bool manualRotation;

  /// Direction to rotate (true = east, false = west) for auto rotation
  @override
  @JsonKey()
  final bool rotateEast;

  /// Timeout in seconds for plate solve attempts
  @override
  @JsonKey()
  final double solveTimeout;

  /// Total error threshold in arcseconds to consider alignment complete
  /// When error drops below this value, auto-complete can be triggered
  @override
  @JsonKey()
  final double autoCompleteThreshold;

  /// Whether to start from current mount position or slew to pole first
  @override
  @JsonKey()
  final bool startFromCurrent;

  /// Camera gain (null = use camera default)
  @override
  final int? gain;

  /// Camera offset (null = use camera default)
  @override
  final int? offset;

  @override
  String toString() {
    return 'PolarAlignmentConfig(exposureTime: $exposureTime, stepSize: $stepSize, binning: $binning, isNorth: $isNorth, manualRotation: $manualRotation, rotateEast: $rotateEast, solveTimeout: $solveTimeout, autoCompleteThreshold: $autoCompleteThreshold, startFromCurrent: $startFromCurrent, gain: $gain, offset: $offset)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PolarAlignmentConfigImpl &&
            (identical(other.exposureTime, exposureTime) ||
                other.exposureTime == exposureTime) &&
            (identical(other.stepSize, stepSize) ||
                other.stepSize == stepSize) &&
            (identical(other.binning, binning) || other.binning == binning) &&
            (identical(other.isNorth, isNorth) || other.isNorth == isNorth) &&
            (identical(other.manualRotation, manualRotation) ||
                other.manualRotation == manualRotation) &&
            (identical(other.rotateEast, rotateEast) ||
                other.rotateEast == rotateEast) &&
            (identical(other.solveTimeout, solveTimeout) ||
                other.solveTimeout == solveTimeout) &&
            (identical(other.autoCompleteThreshold, autoCompleteThreshold) ||
                other.autoCompleteThreshold == autoCompleteThreshold) &&
            (identical(other.startFromCurrent, startFromCurrent) ||
                other.startFromCurrent == startFromCurrent) &&
            (identical(other.gain, gain) || other.gain == gain) &&
            (identical(other.offset, offset) || other.offset == offset));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      exposureTime,
      stepSize,
      binning,
      isNorth,
      manualRotation,
      rotateEast,
      solveTimeout,
      autoCompleteThreshold,
      startFromCurrent,
      gain,
      offset);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PolarAlignmentConfigImplCopyWith<_$PolarAlignmentConfigImpl>
      get copyWith =>
          __$$PolarAlignmentConfigImplCopyWithImpl<_$PolarAlignmentConfigImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PolarAlignmentConfigImplToJson(
      this,
    );
  }
}

abstract class _PolarAlignmentConfig extends PolarAlignmentConfig {
  const factory _PolarAlignmentConfig(
      {final double exposureTime,
      final double stepSize,
      final int binning,
      final bool isNorth,
      final bool manualRotation,
      final bool rotateEast,
      final double solveTimeout,
      final double autoCompleteThreshold,
      final bool startFromCurrent,
      final int? gain,
      final int? offset}) = _$PolarAlignmentConfigImpl;
  const _PolarAlignmentConfig._() : super._();

  factory _PolarAlignmentConfig.fromJson(Map<String, dynamic> json) =
      _$PolarAlignmentConfigImpl.fromJson;

  @override

  /// Exposure time in seconds for each measurement image
  double get exposureTime;
  @override

  /// Step size in degrees for mount rotation between measurements
  double get stepSize;
  @override

  /// Camera binning (1, 2, 3, 4)
  int get binning;
  @override

  /// Whether observing from northern hemisphere
  bool get isNorth;
  @override

  /// Whether to use manual rotation (user rotates mount) vs automatic slewing
  bool get manualRotation;
  @override

  /// Direction to rotate (true = east, false = west) for auto rotation
  bool get rotateEast;
  @override

  /// Timeout in seconds for plate solve attempts
  double get solveTimeout;
  @override

  /// Total error threshold in arcseconds to consider alignment complete
  /// When error drops below this value, auto-complete can be triggered
  double get autoCompleteThreshold;
  @override

  /// Whether to start from current mount position or slew to pole first
  bool get startFromCurrent;
  @override

  /// Camera gain (null = use camera default)
  int? get gain;
  @override

  /// Camera offset (null = use camera default)
  int? get offset;
  @override
  @JsonKey(ignore: true)
  _$$PolarAlignmentConfigImplCopyWith<_$PolarAlignmentConfigImpl>
      get copyWith => throw _privateConstructorUsedError;
}

PolarAlignmentError _$PolarAlignmentErrorFromJson(Map<String, dynamic> json) {
  return _PolarAlignmentError.fromJson(json);
}

/// @nodoc
mixin _$PolarAlignmentError {
  /// Azimuth error in arcseconds (positive = east)
  double get azimuthError => throw _privateConstructorUsedError;

  /// Altitude error in arcseconds (positive = above pole)
  double get altitudeError => throw _privateConstructorUsedError;

  /// Total error in arcseconds (pythagorean combination)
  double get totalError => throw _privateConstructorUsedError;

  /// Current RA position (degrees)
  double get currentRa => throw _privateConstructorUsedError;

  /// Current Dec position (degrees)
  double get currentDec => throw _privateConstructorUsedError;

  /// Target RA for perfect alignment (degrees)
  double get targetRa => throw _privateConstructorUsedError;

  /// Target Dec for perfect alignment (degrees)
  double get targetDec => throw _privateConstructorUsedError;

  /// When this measurement was taken
  DateTime get timestamp => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PolarAlignmentErrorCopyWith<PolarAlignmentError> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PolarAlignmentErrorCopyWith<$Res> {
  factory $PolarAlignmentErrorCopyWith(
          PolarAlignmentError value, $Res Function(PolarAlignmentError) then) =
      _$PolarAlignmentErrorCopyWithImpl<$Res, PolarAlignmentError>;
  @useResult
  $Res call(
      {double azimuthError,
      double altitudeError,
      double totalError,
      double currentRa,
      double currentDec,
      double targetRa,
      double targetDec,
      DateTime timestamp});
}

/// @nodoc
class _$PolarAlignmentErrorCopyWithImpl<$Res, $Val extends PolarAlignmentError>
    implements $PolarAlignmentErrorCopyWith<$Res> {
  _$PolarAlignmentErrorCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? azimuthError = null,
    Object? altitudeError = null,
    Object? totalError = null,
    Object? currentRa = null,
    Object? currentDec = null,
    Object? targetRa = null,
    Object? targetDec = null,
    Object? timestamp = null,
  }) {
    return _then(_value.copyWith(
      azimuthError: null == azimuthError
          ? _value.azimuthError
          : azimuthError // ignore: cast_nullable_to_non_nullable
              as double,
      altitudeError: null == altitudeError
          ? _value.altitudeError
          : altitudeError // ignore: cast_nullable_to_non_nullable
              as double,
      totalError: null == totalError
          ? _value.totalError
          : totalError // ignore: cast_nullable_to_non_nullable
              as double,
      currentRa: null == currentRa
          ? _value.currentRa
          : currentRa // ignore: cast_nullable_to_non_nullable
              as double,
      currentDec: null == currentDec
          ? _value.currentDec
          : currentDec // ignore: cast_nullable_to_non_nullable
              as double,
      targetRa: null == targetRa
          ? _value.targetRa
          : targetRa // ignore: cast_nullable_to_non_nullable
              as double,
      targetDec: null == targetDec
          ? _value.targetDec
          : targetDec // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$PolarAlignmentErrorImplCopyWith<$Res>
    implements $PolarAlignmentErrorCopyWith<$Res> {
  factory _$$PolarAlignmentErrorImplCopyWith(_$PolarAlignmentErrorImpl value,
          $Res Function(_$PolarAlignmentErrorImpl) then) =
      __$$PolarAlignmentErrorImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double azimuthError,
      double altitudeError,
      double totalError,
      double currentRa,
      double currentDec,
      double targetRa,
      double targetDec,
      DateTime timestamp});
}

/// @nodoc
class __$$PolarAlignmentErrorImplCopyWithImpl<$Res>
    extends _$PolarAlignmentErrorCopyWithImpl<$Res, _$PolarAlignmentErrorImpl>
    implements _$$PolarAlignmentErrorImplCopyWith<$Res> {
  __$$PolarAlignmentErrorImplCopyWithImpl(_$PolarAlignmentErrorImpl _value,
      $Res Function(_$PolarAlignmentErrorImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? azimuthError = null,
    Object? altitudeError = null,
    Object? totalError = null,
    Object? currentRa = null,
    Object? currentDec = null,
    Object? targetRa = null,
    Object? targetDec = null,
    Object? timestamp = null,
  }) {
    return _then(_$PolarAlignmentErrorImpl(
      azimuthError: null == azimuthError
          ? _value.azimuthError
          : azimuthError // ignore: cast_nullable_to_non_nullable
              as double,
      altitudeError: null == altitudeError
          ? _value.altitudeError
          : altitudeError // ignore: cast_nullable_to_non_nullable
              as double,
      totalError: null == totalError
          ? _value.totalError
          : totalError // ignore: cast_nullable_to_non_nullable
              as double,
      currentRa: null == currentRa
          ? _value.currentRa
          : currentRa // ignore: cast_nullable_to_non_nullable
              as double,
      currentDec: null == currentDec
          ? _value.currentDec
          : currentDec // ignore: cast_nullable_to_non_nullable
              as double,
      targetRa: null == targetRa
          ? _value.targetRa
          : targetRa // ignore: cast_nullable_to_non_nullable
              as double,
      targetDec: null == targetDec
          ? _value.targetDec
          : targetDec // ignore: cast_nullable_to_non_nullable
              as double,
      timestamp: null == timestamp
          ? _value.timestamp
          : timestamp // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PolarAlignmentErrorImpl extends _PolarAlignmentError {
  const _$PolarAlignmentErrorImpl(
      {required this.azimuthError,
      required this.altitudeError,
      required this.totalError,
      required this.currentRa,
      required this.currentDec,
      required this.targetRa,
      required this.targetDec,
      required this.timestamp})
      : super._();

  factory _$PolarAlignmentErrorImpl.fromJson(Map<String, dynamic> json) =>
      _$$PolarAlignmentErrorImplFromJson(json);

  /// Azimuth error in arcseconds (positive = east)
  @override
  final double azimuthError;

  /// Altitude error in arcseconds (positive = above pole)
  @override
  final double altitudeError;

  /// Total error in arcseconds (pythagorean combination)
  @override
  final double totalError;

  /// Current RA position (degrees)
  @override
  final double currentRa;

  /// Current Dec position (degrees)
  @override
  final double currentDec;

  /// Target RA for perfect alignment (degrees)
  @override
  final double targetRa;

  /// Target Dec for perfect alignment (degrees)
  @override
  final double targetDec;

  /// When this measurement was taken
  @override
  final DateTime timestamp;

  @override
  String toString() {
    return 'PolarAlignmentError(azimuthError: $azimuthError, altitudeError: $altitudeError, totalError: $totalError, currentRa: $currentRa, currentDec: $currentDec, targetRa: $targetRa, targetDec: $targetDec, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PolarAlignmentErrorImpl &&
            (identical(other.azimuthError, azimuthError) ||
                other.azimuthError == azimuthError) &&
            (identical(other.altitudeError, altitudeError) ||
                other.altitudeError == altitudeError) &&
            (identical(other.totalError, totalError) ||
                other.totalError == totalError) &&
            (identical(other.currentRa, currentRa) ||
                other.currentRa == currentRa) &&
            (identical(other.currentDec, currentDec) ||
                other.currentDec == currentDec) &&
            (identical(other.targetRa, targetRa) ||
                other.targetRa == targetRa) &&
            (identical(other.targetDec, targetDec) ||
                other.targetDec == targetDec) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, azimuthError, altitudeError,
      totalError, currentRa, currentDec, targetRa, targetDec, timestamp);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PolarAlignmentErrorImplCopyWith<_$PolarAlignmentErrorImpl> get copyWith =>
      __$$PolarAlignmentErrorImplCopyWithImpl<_$PolarAlignmentErrorImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PolarAlignmentErrorImplToJson(
      this,
    );
  }
}

abstract class _PolarAlignmentError extends PolarAlignmentError {
  const factory _PolarAlignmentError(
      {required final double azimuthError,
      required final double altitudeError,
      required final double totalError,
      required final double currentRa,
      required final double currentDec,
      required final double targetRa,
      required final double targetDec,
      required final DateTime timestamp}) = _$PolarAlignmentErrorImpl;
  const _PolarAlignmentError._() : super._();

  factory _PolarAlignmentError.fromJson(Map<String, dynamic> json) =
      _$PolarAlignmentErrorImpl.fromJson;

  @override

  /// Azimuth error in arcseconds (positive = east)
  double get azimuthError;
  @override

  /// Altitude error in arcseconds (positive = above pole)
  double get altitudeError;
  @override

  /// Total error in arcseconds (pythagorean combination)
  double get totalError;
  @override

  /// Current RA position (degrees)
  double get currentRa;
  @override

  /// Current Dec position (degrees)
  double get currentDec;
  @override

  /// Target RA for perfect alignment (degrees)
  double get targetRa;
  @override

  /// Target Dec for perfect alignment (degrees)
  double get targetDec;
  @override

  /// When this measurement was taken
  DateTime get timestamp;
  @override
  @JsonKey(ignore: true)
  _$$PolarAlignmentErrorImplCopyWith<_$PolarAlignmentErrorImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PolarAlignmentState _$PolarAlignmentStateFromJson(Map<String, dynamic> json) {
  return _PolarAlignmentState.fromJson(json);
}

/// @nodoc
mixin _$PolarAlignmentState {
  /// Current phase of alignment
  PolarAlignPhase get phase => throw _privateConstructorUsedError;

  /// Current measurement point (1-3 during measuring, 0 during adjusting)
  int get currentPoint => throw _privateConstructorUsedError;

  /// Status message to display to user
  String get statusMessage => throw _privateConstructorUsedError;

  /// Current error measurements (null if not yet calculated)
  PolarAlignmentError? get currentError => throw _privateConstructorUsedError;

  /// Initial error when adjustment phase started (for progress tracking)
  PolarAlignmentError? get initialError => throw _privateConstructorUsedError;

  /// Most recent captured image (JPEG bytes for display)
  @NullableUint8ListConverter()
  Uint8List? get imageData => throw _privateConstructorUsedError;

  /// Image width
  int? get imageWidth => throw _privateConstructorUsedError;

  /// Image height
  int? get imageHeight => throw _privateConstructorUsedError;

  /// Solved RA from last image (degrees)
  double? get solvedRa => throw _privateConstructorUsedError;

  /// Solved Dec from last image (degrees)
  double? get solvedDec => throw _privateConstructorUsedError;

  /// Error message if phase is error
  String? get errorMessage => throw _privateConstructorUsedError;

  /// Configuration used for this alignment run
  PolarAlignmentConfig? get config => throw _privateConstructorUsedError;

  /// When alignment started
  DateTime? get startedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PolarAlignmentStateCopyWith<PolarAlignmentState> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PolarAlignmentStateCopyWith<$Res> {
  factory $PolarAlignmentStateCopyWith(
          PolarAlignmentState value, $Res Function(PolarAlignmentState) then) =
      _$PolarAlignmentStateCopyWithImpl<$Res, PolarAlignmentState>;
  @useResult
  $Res call(
      {PolarAlignPhase phase,
      int currentPoint,
      String statusMessage,
      PolarAlignmentError? currentError,
      PolarAlignmentError? initialError,
      @NullableUint8ListConverter() Uint8List? imageData,
      int? imageWidth,
      int? imageHeight,
      double? solvedRa,
      double? solvedDec,
      String? errorMessage,
      PolarAlignmentConfig? config,
      DateTime? startedAt});

  $PolarAlignmentErrorCopyWith<$Res>? get currentError;
  $PolarAlignmentErrorCopyWith<$Res>? get initialError;
  $PolarAlignmentConfigCopyWith<$Res>? get config;
}

/// @nodoc
class _$PolarAlignmentStateCopyWithImpl<$Res, $Val extends PolarAlignmentState>
    implements $PolarAlignmentStateCopyWith<$Res> {
  _$PolarAlignmentStateCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? phase = null,
    Object? currentPoint = null,
    Object? statusMessage = null,
    Object? currentError = freezed,
    Object? initialError = freezed,
    Object? imageData = freezed,
    Object? imageWidth = freezed,
    Object? imageHeight = freezed,
    Object? solvedRa = freezed,
    Object? solvedDec = freezed,
    Object? errorMessage = freezed,
    Object? config = freezed,
    Object? startedAt = freezed,
  }) {
    return _then(_value.copyWith(
      phase: null == phase
          ? _value.phase
          : phase // ignore: cast_nullable_to_non_nullable
              as PolarAlignPhase,
      currentPoint: null == currentPoint
          ? _value.currentPoint
          : currentPoint // ignore: cast_nullable_to_non_nullable
              as int,
      statusMessage: null == statusMessage
          ? _value.statusMessage
          : statusMessage // ignore: cast_nullable_to_non_nullable
              as String,
      currentError: freezed == currentError
          ? _value.currentError
          : currentError // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentError?,
      initialError: freezed == initialError
          ? _value.initialError
          : initialError // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentError?,
      imageData: freezed == imageData
          ? _value.imageData
          : imageData // ignore: cast_nullable_to_non_nullable
              as Uint8List?,
      imageWidth: freezed == imageWidth
          ? _value.imageWidth
          : imageWidth // ignore: cast_nullable_to_non_nullable
              as int?,
      imageHeight: freezed == imageHeight
          ? _value.imageHeight
          : imageHeight // ignore: cast_nullable_to_non_nullable
              as int?,
      solvedRa: freezed == solvedRa
          ? _value.solvedRa
          : solvedRa // ignore: cast_nullable_to_non_nullable
              as double?,
      solvedDec: freezed == solvedDec
          ? _value.solvedDec
          : solvedDec // ignore: cast_nullable_to_non_nullable
              as double?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      config: freezed == config
          ? _value.config
          : config // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentConfig?,
      startedAt: freezed == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $PolarAlignmentErrorCopyWith<$Res>? get currentError {
    if (_value.currentError == null) {
      return null;
    }

    return $PolarAlignmentErrorCopyWith<$Res>(_value.currentError!, (value) {
      return _then(_value.copyWith(currentError: value) as $Val);
    });
  }

  @override
  @pragma('vm:prefer-inline')
  $PolarAlignmentErrorCopyWith<$Res>? get initialError {
    if (_value.initialError == null) {
      return null;
    }

    return $PolarAlignmentErrorCopyWith<$Res>(_value.initialError!, (value) {
      return _then(_value.copyWith(initialError: value) as $Val);
    });
  }

  @override
  @pragma('vm:prefer-inline')
  $PolarAlignmentConfigCopyWith<$Res>? get config {
    if (_value.config == null) {
      return null;
    }

    return $PolarAlignmentConfigCopyWith<$Res>(_value.config!, (value) {
      return _then(_value.copyWith(config: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$PolarAlignmentStateImplCopyWith<$Res>
    implements $PolarAlignmentStateCopyWith<$Res> {
  factory _$$PolarAlignmentStateImplCopyWith(_$PolarAlignmentStateImpl value,
          $Res Function(_$PolarAlignmentStateImpl) then) =
      __$$PolarAlignmentStateImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {PolarAlignPhase phase,
      int currentPoint,
      String statusMessage,
      PolarAlignmentError? currentError,
      PolarAlignmentError? initialError,
      @NullableUint8ListConverter() Uint8List? imageData,
      int? imageWidth,
      int? imageHeight,
      double? solvedRa,
      double? solvedDec,
      String? errorMessage,
      PolarAlignmentConfig? config,
      DateTime? startedAt});

  @override
  $PolarAlignmentErrorCopyWith<$Res>? get currentError;
  @override
  $PolarAlignmentErrorCopyWith<$Res>? get initialError;
  @override
  $PolarAlignmentConfigCopyWith<$Res>? get config;
}

/// @nodoc
class __$$PolarAlignmentStateImplCopyWithImpl<$Res>
    extends _$PolarAlignmentStateCopyWithImpl<$Res, _$PolarAlignmentStateImpl>
    implements _$$PolarAlignmentStateImplCopyWith<$Res> {
  __$$PolarAlignmentStateImplCopyWithImpl(_$PolarAlignmentStateImpl _value,
      $Res Function(_$PolarAlignmentStateImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? phase = null,
    Object? currentPoint = null,
    Object? statusMessage = null,
    Object? currentError = freezed,
    Object? initialError = freezed,
    Object? imageData = freezed,
    Object? imageWidth = freezed,
    Object? imageHeight = freezed,
    Object? solvedRa = freezed,
    Object? solvedDec = freezed,
    Object? errorMessage = freezed,
    Object? config = freezed,
    Object? startedAt = freezed,
  }) {
    return _then(_$PolarAlignmentStateImpl(
      phase: null == phase
          ? _value.phase
          : phase // ignore: cast_nullable_to_non_nullable
              as PolarAlignPhase,
      currentPoint: null == currentPoint
          ? _value.currentPoint
          : currentPoint // ignore: cast_nullable_to_non_nullable
              as int,
      statusMessage: null == statusMessage
          ? _value.statusMessage
          : statusMessage // ignore: cast_nullable_to_non_nullable
              as String,
      currentError: freezed == currentError
          ? _value.currentError
          : currentError // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentError?,
      initialError: freezed == initialError
          ? _value.initialError
          : initialError // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentError?,
      imageData: freezed == imageData
          ? _value.imageData
          : imageData // ignore: cast_nullable_to_non_nullable
              as Uint8List?,
      imageWidth: freezed == imageWidth
          ? _value.imageWidth
          : imageWidth // ignore: cast_nullable_to_non_nullable
              as int?,
      imageHeight: freezed == imageHeight
          ? _value.imageHeight
          : imageHeight // ignore: cast_nullable_to_non_nullable
              as int?,
      solvedRa: freezed == solvedRa
          ? _value.solvedRa
          : solvedRa // ignore: cast_nullable_to_non_nullable
              as double?,
      solvedDec: freezed == solvedDec
          ? _value.solvedDec
          : solvedDec // ignore: cast_nullable_to_non_nullable
              as double?,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
      config: freezed == config
          ? _value.config
          : config // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentConfig?,
      startedAt: freezed == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PolarAlignmentStateImpl extends _PolarAlignmentState {
  const _$PolarAlignmentStateImpl(
      {this.phase = PolarAlignPhase.idle,
      this.currentPoint = 0,
      this.statusMessage = 'Ready to start polar alignment',
      this.currentError,
      this.initialError,
      @NullableUint8ListConverter() this.imageData,
      this.imageWidth,
      this.imageHeight,
      this.solvedRa,
      this.solvedDec,
      this.errorMessage,
      this.config,
      this.startedAt})
      : super._();

  factory _$PolarAlignmentStateImpl.fromJson(Map<String, dynamic> json) =>
      _$$PolarAlignmentStateImplFromJson(json);

  /// Current phase of alignment
  @override
  @JsonKey()
  final PolarAlignPhase phase;

  /// Current measurement point (1-3 during measuring, 0 during adjusting)
  @override
  @JsonKey()
  final int currentPoint;

  /// Status message to display to user
  @override
  @JsonKey()
  final String statusMessage;

  /// Current error measurements (null if not yet calculated)
  @override
  final PolarAlignmentError? currentError;

  /// Initial error when adjustment phase started (for progress tracking)
  @override
  final PolarAlignmentError? initialError;

  /// Most recent captured image (JPEG bytes for display)
  @override
  @NullableUint8ListConverter()
  final Uint8List? imageData;

  /// Image width
  @override
  final int? imageWidth;

  /// Image height
  @override
  final int? imageHeight;

  /// Solved RA from last image (degrees)
  @override
  final double? solvedRa;

  /// Solved Dec from last image (degrees)
  @override
  final double? solvedDec;

  /// Error message if phase is error
  @override
  final String? errorMessage;

  /// Configuration used for this alignment run
  @override
  final PolarAlignmentConfig? config;

  /// When alignment started
  @override
  final DateTime? startedAt;

  @override
  String toString() {
    return 'PolarAlignmentState(phase: $phase, currentPoint: $currentPoint, statusMessage: $statusMessage, currentError: $currentError, initialError: $initialError, imageData: $imageData, imageWidth: $imageWidth, imageHeight: $imageHeight, solvedRa: $solvedRa, solvedDec: $solvedDec, errorMessage: $errorMessage, config: $config, startedAt: $startedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PolarAlignmentStateImpl &&
            (identical(other.phase, phase) || other.phase == phase) &&
            (identical(other.currentPoint, currentPoint) ||
                other.currentPoint == currentPoint) &&
            (identical(other.statusMessage, statusMessage) ||
                other.statusMessage == statusMessage) &&
            (identical(other.currentError, currentError) ||
                other.currentError == currentError) &&
            (identical(other.initialError, initialError) ||
                other.initialError == initialError) &&
            const DeepCollectionEquality().equals(other.imageData, imageData) &&
            (identical(other.imageWidth, imageWidth) ||
                other.imageWidth == imageWidth) &&
            (identical(other.imageHeight, imageHeight) ||
                other.imageHeight == imageHeight) &&
            (identical(other.solvedRa, solvedRa) ||
                other.solvedRa == solvedRa) &&
            (identical(other.solvedDec, solvedDec) ||
                other.solvedDec == solvedDec) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage) &&
            (identical(other.config, config) || other.config == config) &&
            (identical(other.startedAt, startedAt) ||
                other.startedAt == startedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      phase,
      currentPoint,
      statusMessage,
      currentError,
      initialError,
      const DeepCollectionEquality().hash(imageData),
      imageWidth,
      imageHeight,
      solvedRa,
      solvedDec,
      errorMessage,
      config,
      startedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PolarAlignmentStateImplCopyWith<_$PolarAlignmentStateImpl> get copyWith =>
      __$$PolarAlignmentStateImplCopyWithImpl<_$PolarAlignmentStateImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PolarAlignmentStateImplToJson(
      this,
    );
  }
}

abstract class _PolarAlignmentState extends PolarAlignmentState {
  const factory _PolarAlignmentState(
      {final PolarAlignPhase phase,
      final int currentPoint,
      final String statusMessage,
      final PolarAlignmentError? currentError,
      final PolarAlignmentError? initialError,
      @NullableUint8ListConverter() final Uint8List? imageData,
      final int? imageWidth,
      final int? imageHeight,
      final double? solvedRa,
      final double? solvedDec,
      final String? errorMessage,
      final PolarAlignmentConfig? config,
      final DateTime? startedAt}) = _$PolarAlignmentStateImpl;
  const _PolarAlignmentState._() : super._();

  factory _PolarAlignmentState.fromJson(Map<String, dynamic> json) =
      _$PolarAlignmentStateImpl.fromJson;

  @override

  /// Current phase of alignment
  PolarAlignPhase get phase;
  @override

  /// Current measurement point (1-3 during measuring, 0 during adjusting)
  int get currentPoint;
  @override

  /// Status message to display to user
  String get statusMessage;
  @override

  /// Current error measurements (null if not yet calculated)
  PolarAlignmentError? get currentError;
  @override

  /// Initial error when adjustment phase started (for progress tracking)
  PolarAlignmentError? get initialError;
  @override

  /// Most recent captured image (JPEG bytes for display)
  @NullableUint8ListConverter()
  Uint8List? get imageData;
  @override

  /// Image width
  int? get imageWidth;
  @override

  /// Image height
  int? get imageHeight;
  @override

  /// Solved RA from last image (degrees)
  double? get solvedRa;
  @override

  /// Solved Dec from last image (degrees)
  double? get solvedDec;
  @override

  /// Error message if phase is error
  String? get errorMessage;
  @override

  /// Configuration used for this alignment run
  PolarAlignmentConfig? get config;
  @override

  /// When alignment started
  DateTime? get startedAt;
  @override
  @JsonKey(ignore: true)
  _$$PolarAlignmentStateImplCopyWith<_$PolarAlignmentStateImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

PolarAlignmentResult _$PolarAlignmentResultFromJson(Map<String, dynamic> json) {
  return _PolarAlignmentResult.fromJson(json);
}

/// @nodoc
mixin _$PolarAlignmentResult {
  /// Initial error at start of adjustment phase
  PolarAlignmentError get initialError => throw _privateConstructorUsedError;

  /// Final error when alignment completed or stopped
  PolarAlignmentError get finalError => throw _privateConstructorUsedError;

  /// When alignment started
  DateTime get startedAt => throw _privateConstructorUsedError;

  /// When alignment completed
  DateTime get completedAt => throw _privateConstructorUsedError;

  /// Configuration used for this alignment
  PolarAlignmentConfig get config => throw _privateConstructorUsedError;

  /// Whether alignment was auto-completed (reached threshold)
  bool get autoCompleted => throw _privateConstructorUsedError;

  /// Equipment profile ID used (for history tracking)
  int? get equipmentProfileId => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PolarAlignmentResultCopyWith<PolarAlignmentResult> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PolarAlignmentResultCopyWith<$Res> {
  factory $PolarAlignmentResultCopyWith(PolarAlignmentResult value,
          $Res Function(PolarAlignmentResult) then) =
      _$PolarAlignmentResultCopyWithImpl<$Res, PolarAlignmentResult>;
  @useResult
  $Res call(
      {PolarAlignmentError initialError,
      PolarAlignmentError finalError,
      DateTime startedAt,
      DateTime completedAt,
      PolarAlignmentConfig config,
      bool autoCompleted,
      int? equipmentProfileId});

  $PolarAlignmentErrorCopyWith<$Res> get initialError;
  $PolarAlignmentErrorCopyWith<$Res> get finalError;
  $PolarAlignmentConfigCopyWith<$Res> get config;
}

/// @nodoc
class _$PolarAlignmentResultCopyWithImpl<$Res,
        $Val extends PolarAlignmentResult>
    implements $PolarAlignmentResultCopyWith<$Res> {
  _$PolarAlignmentResultCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? initialError = null,
    Object? finalError = null,
    Object? startedAt = null,
    Object? completedAt = null,
    Object? config = null,
    Object? autoCompleted = null,
    Object? equipmentProfileId = freezed,
  }) {
    return _then(_value.copyWith(
      initialError: null == initialError
          ? _value.initialError
          : initialError // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentError,
      finalError: null == finalError
          ? _value.finalError
          : finalError // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentError,
      startedAt: null == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      completedAt: null == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      config: null == config
          ? _value.config
          : config // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentConfig,
      autoCompleted: null == autoCompleted
          ? _value.autoCompleted
          : autoCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      equipmentProfileId: freezed == equipmentProfileId
          ? _value.equipmentProfileId
          : equipmentProfileId // ignore: cast_nullable_to_non_nullable
              as int?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $PolarAlignmentErrorCopyWith<$Res> get initialError {
    return $PolarAlignmentErrorCopyWith<$Res>(_value.initialError, (value) {
      return _then(_value.copyWith(initialError: value) as $Val);
    });
  }

  @override
  @pragma('vm:prefer-inline')
  $PolarAlignmentErrorCopyWith<$Res> get finalError {
    return $PolarAlignmentErrorCopyWith<$Res>(_value.finalError, (value) {
      return _then(_value.copyWith(finalError: value) as $Val);
    });
  }

  @override
  @pragma('vm:prefer-inline')
  $PolarAlignmentConfigCopyWith<$Res> get config {
    return $PolarAlignmentConfigCopyWith<$Res>(_value.config, (value) {
      return _then(_value.copyWith(config: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$PolarAlignmentResultImplCopyWith<$Res>
    implements $PolarAlignmentResultCopyWith<$Res> {
  factory _$$PolarAlignmentResultImplCopyWith(_$PolarAlignmentResultImpl value,
          $Res Function(_$PolarAlignmentResultImpl) then) =
      __$$PolarAlignmentResultImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {PolarAlignmentError initialError,
      PolarAlignmentError finalError,
      DateTime startedAt,
      DateTime completedAt,
      PolarAlignmentConfig config,
      bool autoCompleted,
      int? equipmentProfileId});

  @override
  $PolarAlignmentErrorCopyWith<$Res> get initialError;
  @override
  $PolarAlignmentErrorCopyWith<$Res> get finalError;
  @override
  $PolarAlignmentConfigCopyWith<$Res> get config;
}

/// @nodoc
class __$$PolarAlignmentResultImplCopyWithImpl<$Res>
    extends _$PolarAlignmentResultCopyWithImpl<$Res, _$PolarAlignmentResultImpl>
    implements _$$PolarAlignmentResultImplCopyWith<$Res> {
  __$$PolarAlignmentResultImplCopyWithImpl(_$PolarAlignmentResultImpl _value,
      $Res Function(_$PolarAlignmentResultImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? initialError = null,
    Object? finalError = null,
    Object? startedAt = null,
    Object? completedAt = null,
    Object? config = null,
    Object? autoCompleted = null,
    Object? equipmentProfileId = freezed,
  }) {
    return _then(_$PolarAlignmentResultImpl(
      initialError: null == initialError
          ? _value.initialError
          : initialError // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentError,
      finalError: null == finalError
          ? _value.finalError
          : finalError // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentError,
      startedAt: null == startedAt
          ? _value.startedAt
          : startedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      completedAt: null == completedAt
          ? _value.completedAt
          : completedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
      config: null == config
          ? _value.config
          : config // ignore: cast_nullable_to_non_nullable
              as PolarAlignmentConfig,
      autoCompleted: null == autoCompleted
          ? _value.autoCompleted
          : autoCompleted // ignore: cast_nullable_to_non_nullable
              as bool,
      equipmentProfileId: freezed == equipmentProfileId
          ? _value.equipmentProfileId
          : equipmentProfileId // ignore: cast_nullable_to_non_nullable
              as int?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$PolarAlignmentResultImpl extends _PolarAlignmentResult {
  const _$PolarAlignmentResultImpl(
      {required this.initialError,
      required this.finalError,
      required this.startedAt,
      required this.completedAt,
      required this.config,
      this.autoCompleted = false,
      this.equipmentProfileId})
      : super._();

  factory _$PolarAlignmentResultImpl.fromJson(Map<String, dynamic> json) =>
      _$$PolarAlignmentResultImplFromJson(json);

  /// Initial error at start of adjustment phase
  @override
  final PolarAlignmentError initialError;

  /// Final error when alignment completed or stopped
  @override
  final PolarAlignmentError finalError;

  /// When alignment started
  @override
  final DateTime startedAt;

  /// When alignment completed
  @override
  final DateTime completedAt;

  /// Configuration used for this alignment
  @override
  final PolarAlignmentConfig config;

  /// Whether alignment was auto-completed (reached threshold)
  @override
  @JsonKey()
  final bool autoCompleted;

  /// Equipment profile ID used (for history tracking)
  @override
  final int? equipmentProfileId;

  @override
  String toString() {
    return 'PolarAlignmentResult(initialError: $initialError, finalError: $finalError, startedAt: $startedAt, completedAt: $completedAt, config: $config, autoCompleted: $autoCompleted, equipmentProfileId: $equipmentProfileId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PolarAlignmentResultImpl &&
            (identical(other.initialError, initialError) ||
                other.initialError == initialError) &&
            (identical(other.finalError, finalError) ||
                other.finalError == finalError) &&
            (identical(other.startedAt, startedAt) ||
                other.startedAt == startedAt) &&
            (identical(other.completedAt, completedAt) ||
                other.completedAt == completedAt) &&
            (identical(other.config, config) || other.config == config) &&
            (identical(other.autoCompleted, autoCompleted) ||
                other.autoCompleted == autoCompleted) &&
            (identical(other.equipmentProfileId, equipmentProfileId) ||
                other.equipmentProfileId == equipmentProfileId));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, initialError, finalError,
      startedAt, completedAt, config, autoCompleted, equipmentProfileId);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$PolarAlignmentResultImplCopyWith<_$PolarAlignmentResultImpl>
      get copyWith =>
          __$$PolarAlignmentResultImplCopyWithImpl<_$PolarAlignmentResultImpl>(
              this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$PolarAlignmentResultImplToJson(
      this,
    );
  }
}

abstract class _PolarAlignmentResult extends PolarAlignmentResult {
  const factory _PolarAlignmentResult(
      {required final PolarAlignmentError initialError,
      required final PolarAlignmentError finalError,
      required final DateTime startedAt,
      required final DateTime completedAt,
      required final PolarAlignmentConfig config,
      final bool autoCompleted,
      final int? equipmentProfileId}) = _$PolarAlignmentResultImpl;
  const _PolarAlignmentResult._() : super._();

  factory _PolarAlignmentResult.fromJson(Map<String, dynamic> json) =
      _$PolarAlignmentResultImpl.fromJson;

  @override

  /// Initial error at start of adjustment phase
  PolarAlignmentError get initialError;
  @override

  /// Final error when alignment completed or stopped
  PolarAlignmentError get finalError;
  @override

  /// When alignment started
  DateTime get startedAt;
  @override

  /// When alignment completed
  DateTime get completedAt;
  @override

  /// Configuration used for this alignment
  PolarAlignmentConfig get config;
  @override

  /// Whether alignment was auto-completed (reached threshold)
  bool get autoCompleted;
  @override

  /// Equipment profile ID used (for history tracking)
  int? get equipmentProfileId;
  @override
  @JsonKey(ignore: true)
  _$$PolarAlignmentResultImplCopyWith<_$PolarAlignmentResultImpl>
      get copyWith => throw _privateConstructorUsedError;
}
