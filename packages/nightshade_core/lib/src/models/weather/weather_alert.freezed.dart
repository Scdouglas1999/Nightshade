// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'weather_alert.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

WeatherAlert _$WeatherAlertFromJson(Map<String, dynamic> json) {
  return _WeatherAlert.fromJson(json);
}

/// @nodoc
mixin _$WeatherAlert {
  /// Alert severity level
  AlertLevel get level => throw _privateConstructorUsedError;

  /// Human-readable alert text
  String get message => throw _privateConstructorUsedError;

  /// When clouds expected (null if clear/watch)
  DateTime? get eta => throw _privateConstructorUsedError;

  /// Cloud density percentage (0-100)
  double get cloudDensityPercent => throw _privateConstructorUsedError;

  /// Distance to threatening clouds in kilometers
  double get distanceKm => throw _privateConstructorUsedError;

  /// When this alert was generated
  DateTime get generatedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $WeatherAlertCopyWith<WeatherAlert> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WeatherAlertCopyWith<$Res> {
  factory $WeatherAlertCopyWith(
          WeatherAlert value, $Res Function(WeatherAlert) then) =
      _$WeatherAlertCopyWithImpl<$Res, WeatherAlert>;
  @useResult
  $Res call(
      {AlertLevel level,
      String message,
      DateTime? eta,
      double cloudDensityPercent,
      double distanceKm,
      DateTime generatedAt});
}

/// @nodoc
class _$WeatherAlertCopyWithImpl<$Res, $Val extends WeatherAlert>
    implements $WeatherAlertCopyWith<$Res> {
  _$WeatherAlertCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? level = null,
    Object? message = null,
    Object? eta = freezed,
    Object? cloudDensityPercent = null,
    Object? distanceKm = null,
    Object? generatedAt = null,
  }) {
    return _then(_value.copyWith(
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as AlertLevel,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      eta: freezed == eta
          ? _value.eta
          : eta // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      cloudDensityPercent: null == cloudDensityPercent
          ? _value.cloudDensityPercent
          : cloudDensityPercent // ignore: cast_nullable_to_non_nullable
              as double,
      distanceKm: null == distanceKm
          ? _value.distanceKm
          : distanceKm // ignore: cast_nullable_to_non_nullable
              as double,
      generatedAt: null == generatedAt
          ? _value.generatedAt
          : generatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$WeatherAlertImplCopyWith<$Res>
    implements $WeatherAlertCopyWith<$Res> {
  factory _$$WeatherAlertImplCopyWith(
          _$WeatherAlertImpl value, $Res Function(_$WeatherAlertImpl) then) =
      __$$WeatherAlertImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {AlertLevel level,
      String message,
      DateTime? eta,
      double cloudDensityPercent,
      double distanceKm,
      DateTime generatedAt});
}

/// @nodoc
class __$$WeatherAlertImplCopyWithImpl<$Res>
    extends _$WeatherAlertCopyWithImpl<$Res, _$WeatherAlertImpl>
    implements _$$WeatherAlertImplCopyWith<$Res> {
  __$$WeatherAlertImplCopyWithImpl(
      _$WeatherAlertImpl _value, $Res Function(_$WeatherAlertImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? level = null,
    Object? message = null,
    Object? eta = freezed,
    Object? cloudDensityPercent = null,
    Object? distanceKm = null,
    Object? generatedAt = null,
  }) {
    return _then(_$WeatherAlertImpl(
      level: null == level
          ? _value.level
          : level // ignore: cast_nullable_to_non_nullable
              as AlertLevel,
      message: null == message
          ? _value.message
          : message // ignore: cast_nullable_to_non_nullable
              as String,
      eta: freezed == eta
          ? _value.eta
          : eta // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      cloudDensityPercent: null == cloudDensityPercent
          ? _value.cloudDensityPercent
          : cloudDensityPercent // ignore: cast_nullable_to_non_nullable
              as double,
      distanceKm: null == distanceKm
          ? _value.distanceKm
          : distanceKm // ignore: cast_nullable_to_non_nullable
              as double,
      generatedAt: null == generatedAt
          ? _value.generatedAt
          : generatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$WeatherAlertImpl implements _WeatherAlert {
  const _$WeatherAlertImpl(
      {required this.level,
      required this.message,
      this.eta,
      required this.cloudDensityPercent,
      required this.distanceKm,
      required this.generatedAt});

  factory _$WeatherAlertImpl.fromJson(Map<String, dynamic> json) =>
      _$$WeatherAlertImplFromJson(json);

  /// Alert severity level
  @override
  final AlertLevel level;

  /// Human-readable alert text
  @override
  final String message;

  /// When clouds expected (null if clear/watch)
  @override
  final DateTime? eta;

  /// Cloud density percentage (0-100)
  @override
  final double cloudDensityPercent;

  /// Distance to threatening clouds in kilometers
  @override
  final double distanceKm;

  /// When this alert was generated
  @override
  final DateTime generatedAt;

  @override
  String toString() {
    return 'WeatherAlert(level: $level, message: $message, eta: $eta, cloudDensityPercent: $cloudDensityPercent, distanceKm: $distanceKm, generatedAt: $generatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WeatherAlertImpl &&
            (identical(other.level, level) || other.level == level) &&
            (identical(other.message, message) || other.message == message) &&
            (identical(other.eta, eta) || other.eta == eta) &&
            (identical(other.cloudDensityPercent, cloudDensityPercent) ||
                other.cloudDensityPercent == cloudDensityPercent) &&
            (identical(other.distanceKm, distanceKm) ||
                other.distanceKm == distanceKm) &&
            (identical(other.generatedAt, generatedAt) ||
                other.generatedAt == generatedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, level, message, eta,
      cloudDensityPercent, distanceKm, generatedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$WeatherAlertImplCopyWith<_$WeatherAlertImpl> get copyWith =>
      __$$WeatherAlertImplCopyWithImpl<_$WeatherAlertImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$WeatherAlertImplToJson(
      this,
    );
  }
}

abstract class _WeatherAlert implements WeatherAlert {
  const factory _WeatherAlert(
      {required final AlertLevel level,
      required final String message,
      final DateTime? eta,
      required final double cloudDensityPercent,
      required final double distanceKm,
      required final DateTime generatedAt}) = _$WeatherAlertImpl;

  factory _WeatherAlert.fromJson(Map<String, dynamic> json) =
      _$WeatherAlertImpl.fromJson;

  @override

  /// Alert severity level
  AlertLevel get level;
  @override

  /// Human-readable alert text
  String get message;
  @override

  /// When clouds expected (null if clear/watch)
  DateTime? get eta;
  @override

  /// Cloud density percentage (0-100)
  double get cloudDensityPercent;
  @override

  /// Distance to threatening clouds in kilometers
  double get distanceKm;
  @override

  /// When this alert was generated
  DateTime get generatedAt;
  @override
  @JsonKey(ignore: true)
  _$$WeatherAlertImplCopyWith<_$WeatherAlertImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
