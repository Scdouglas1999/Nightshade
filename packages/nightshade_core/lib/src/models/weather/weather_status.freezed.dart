// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'weather_status.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WeatherStatus _$WeatherStatusFromJson(Map<String, dynamic> json) {
  return _WeatherStatus.fromJson(json);
}

/// @nodoc
mixin _$WeatherStatus {
  /// Current alert level
  AlertLevel get currentLevel => throw _privateConstructorUsedError;

  /// Active alert (null if no alert)
  WeatherAlert? get activeAlert => throw _privateConstructorUsedError;

  /// Cloud motion analysis
  CloudMotion? get motion => throw _privateConstructorUsedError;

  /// Radar frames for animation
  List<RadarFrame> get radarFrames => throw _privateConstructorUsedError;

  /// Current frame index in animation
  int get currentFrameIndex => throw _privateConstructorUsedError;

  /// When this status was last updated
  DateTime get lastUpdate => throw _privateConstructorUsedError;

  /// Whether data is currently loading
  bool get isLoading => throw _privateConstructorUsedError;

  /// Error message if update failed
  String? get errorMessage => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $WeatherStatusCopyWith<WeatherStatus> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WeatherStatusCopyWith<$Res> {
  factory $WeatherStatusCopyWith(
          WeatherStatus value, $Res Function(WeatherStatus) then) =
      _$WeatherStatusCopyWithImpl<$Res, WeatherStatus>;
  @useResult
  $Res call(
      {AlertLevel currentLevel,
      WeatherAlert? activeAlert,
      CloudMotion? motion,
      List<RadarFrame> radarFrames,
      int currentFrameIndex,
      DateTime lastUpdate,
      bool isLoading,
      String? errorMessage});

  $WeatherAlertCopyWith<$Res>? get activeAlert;
  $CloudMotionCopyWith<$Res>? get motion;
}

/// @nodoc
class _$WeatherStatusCopyWithImpl<$Res, $Val extends WeatherStatus>
    implements $WeatherStatusCopyWith<$Res> {
  _$WeatherStatusCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentLevel = null,
    Object? activeAlert = freezed,
    Object? motion = freezed,
    Object? radarFrames = null,
    Object? currentFrameIndex = null,
    Object? lastUpdate = null,
    Object? isLoading = null,
    Object? errorMessage = freezed,
  }) {
    return _then(_value.copyWith(
      currentLevel: null == currentLevel
          ? _value.currentLevel
          : currentLevel // ignore: cast_nullable_to_non_nullable
              as AlertLevel,
      activeAlert: freezed == activeAlert
          ? _value.activeAlert
          : activeAlert // ignore: cast_nullable_to_non_nullable
              as WeatherAlert?,
      motion: freezed == motion
          ? _value.motion
          : motion // ignore: cast_nullable_to_non_nullable
              as CloudMotion?,
      radarFrames: null == radarFrames
          ? _value.radarFrames
          : radarFrames // ignore: cast_nullable_to_non_nullable
              as List<RadarFrame>,
      currentFrameIndex: null == currentFrameIndex
          ? _value.currentFrameIndex
          : currentFrameIndex // ignore: cast_nullable_to_non_nullable
              as int,
      lastUpdate: null == lastUpdate
          ? _value.lastUpdate
          : lastUpdate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }

  @override
  @pragma('vm:prefer-inline')
  $WeatherAlertCopyWith<$Res>? get activeAlert {
    if (_value.activeAlert == null) {
      return null;
    }

    return $WeatherAlertCopyWith<$Res>(_value.activeAlert!, (value) {
      return _then(_value.copyWith(activeAlert: value) as $Val);
    });
  }

  @override
  @pragma('vm:prefer-inline')
  $CloudMotionCopyWith<$Res>? get motion {
    if (_value.motion == null) {
      return null;
    }

    return $CloudMotionCopyWith<$Res>(_value.motion!, (value) {
      return _then(_value.copyWith(motion: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$WeatherStatusImplCopyWith<$Res>
    implements $WeatherStatusCopyWith<$Res> {
  factory _$$WeatherStatusImplCopyWith(
          _$WeatherStatusImpl value, $Res Function(_$WeatherStatusImpl) then) =
      __$$WeatherStatusImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {AlertLevel currentLevel,
      WeatherAlert? activeAlert,
      CloudMotion? motion,
      List<RadarFrame> radarFrames,
      int currentFrameIndex,
      DateTime lastUpdate,
      bool isLoading,
      String? errorMessage});

  @override
  $WeatherAlertCopyWith<$Res>? get activeAlert;
  @override
  $CloudMotionCopyWith<$Res>? get motion;
}

/// @nodoc
class __$$WeatherStatusImplCopyWithImpl<$Res>
    extends _$WeatherStatusCopyWithImpl<$Res, _$WeatherStatusImpl>
    implements _$$WeatherStatusImplCopyWith<$Res> {
  __$$WeatherStatusImplCopyWithImpl(
      _$WeatherStatusImpl _value, $Res Function(_$WeatherStatusImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentLevel = null,
    Object? activeAlert = freezed,
    Object? motion = freezed,
    Object? radarFrames = null,
    Object? currentFrameIndex = null,
    Object? lastUpdate = null,
    Object? isLoading = null,
    Object? errorMessage = freezed,
  }) {
    return _then(_$WeatherStatusImpl(
      currentLevel: null == currentLevel
          ? _value.currentLevel
          : currentLevel // ignore: cast_nullable_to_non_nullable
              as AlertLevel,
      activeAlert: freezed == activeAlert
          ? _value.activeAlert
          : activeAlert // ignore: cast_nullable_to_non_nullable
              as WeatherAlert?,
      motion: freezed == motion
          ? _value.motion
          : motion // ignore: cast_nullable_to_non_nullable
              as CloudMotion?,
      radarFrames: null == radarFrames
          ? _value._radarFrames
          : radarFrames // ignore: cast_nullable_to_non_nullable
              as List<RadarFrame>,
      currentFrameIndex: null == currentFrameIndex
          ? _value.currentFrameIndex
          : currentFrameIndex // ignore: cast_nullable_to_non_nullable
              as int,
      lastUpdate: null == lastUpdate
          ? _value.lastUpdate
          : lastUpdate // ignore: cast_nullable_to_non_nullable
              as DateTime,
      isLoading: null == isLoading
          ? _value.isLoading
          : isLoading // ignore: cast_nullable_to_non_nullable
              as bool,
      errorMessage: freezed == errorMessage
          ? _value.errorMessage
          : errorMessage // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WeatherStatusImpl implements _WeatherStatus {
  const _$WeatherStatusImpl(
      {this.currentLevel = AlertLevel.clear,
      this.activeAlert,
      this.motion,
      final List<RadarFrame> radarFrames = const [],
      this.currentFrameIndex = 0,
      required this.lastUpdate,
      this.isLoading = false,
      this.errorMessage})
      : _radarFrames = radarFrames;

  factory _$WeatherStatusImpl.fromJson(Map<String, dynamic> json) =>
      _$$WeatherStatusImplFromJson(json);

  /// Current alert level
  @override
  @JsonKey()
  final AlertLevel currentLevel;

  /// Active alert (null if no alert)
  @override
  final WeatherAlert? activeAlert;

  /// Cloud motion analysis
  @override
  final CloudMotion? motion;

  /// Radar frames for animation
  final List<RadarFrame> _radarFrames;

  /// Radar frames for animation
  @override
  @JsonKey()
  List<RadarFrame> get radarFrames {
    if (_radarFrames is EqualUnmodifiableListView) return _radarFrames;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_radarFrames);
  }

  /// Current frame index in animation
  @override
  @JsonKey()
  final int currentFrameIndex;

  /// When this status was last updated
  @override
  final DateTime lastUpdate;

  /// Whether data is currently loading
  @override
  @JsonKey()
  final bool isLoading;

  /// Error message if update failed
  @override
  final String? errorMessage;

  @override
  String toString() {
    return 'WeatherStatus(currentLevel: $currentLevel, activeAlert: $activeAlert, motion: $motion, radarFrames: $radarFrames, currentFrameIndex: $currentFrameIndex, lastUpdate: $lastUpdate, isLoading: $isLoading, errorMessage: $errorMessage)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WeatherStatusImpl &&
            (identical(other.currentLevel, currentLevel) ||
                other.currentLevel == currentLevel) &&
            (identical(other.activeAlert, activeAlert) ||
                other.activeAlert == activeAlert) &&
            (identical(other.motion, motion) || other.motion == motion) &&
            const DeepCollectionEquality()
                .equals(other._radarFrames, _radarFrames) &&
            (identical(other.currentFrameIndex, currentFrameIndex) ||
                other.currentFrameIndex == currentFrameIndex) &&
            (identical(other.lastUpdate, lastUpdate) ||
                other.lastUpdate == lastUpdate) &&
            (identical(other.isLoading, isLoading) ||
                other.isLoading == isLoading) &&
            (identical(other.errorMessage, errorMessage) ||
                other.errorMessage == errorMessage));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      currentLevel,
      activeAlert,
      motion,
      const DeepCollectionEquality().hash(_radarFrames),
      currentFrameIndex,
      lastUpdate,
      isLoading,
      errorMessage);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WeatherStatusImplCopyWith<_$WeatherStatusImpl> get copyWith =>
      __$$WeatherStatusImplCopyWithImpl<_$WeatherStatusImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WeatherStatusImplToJson(
      this,
    );
  }
}

abstract class _WeatherStatus implements WeatherStatus {
  const factory _WeatherStatus(
      {final AlertLevel currentLevel,
      final WeatherAlert? activeAlert,
      final CloudMotion? motion,
      final List<RadarFrame> radarFrames,
      final int currentFrameIndex,
      required final DateTime lastUpdate,
      final bool isLoading,
      final String? errorMessage}) = _$WeatherStatusImpl;

  factory _WeatherStatus.fromJson(Map<String, dynamic> json) =
      _$WeatherStatusImpl.fromJson;

  @override

  /// Current alert level
  AlertLevel get currentLevel;
  @override

  /// Active alert (null if no alert)
  WeatherAlert? get activeAlert;
  @override

  /// Cloud motion analysis
  CloudMotion? get motion;
  @override

  /// Radar frames for animation
  List<RadarFrame> get radarFrames;
  @override

  /// Current frame index in animation
  int get currentFrameIndex;
  @override

  /// When this status was last updated
  DateTime get lastUpdate;
  @override

  /// Whether data is currently loading
  bool get isLoading;
  @override

  /// Error message if update failed
  String? get errorMessage;
  @override
  @JsonKey(ignore: true)
  _$$WeatherStatusImplCopyWith<_$WeatherStatusImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
