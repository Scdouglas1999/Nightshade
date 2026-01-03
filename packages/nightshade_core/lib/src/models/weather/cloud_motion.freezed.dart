// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'cloud_motion.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

CloudMotion _$CloudMotionFromJson(Map<String, dynamic> json) {
  return _CloudMotion.fromJson(json);
}

/// @nodoc
mixin _$CloudMotion {
  /// Cloud movement speed in km/h
  double get speedKmh => throw _privateConstructorUsedError;

  /// Direction clouds are moving FROM (0-360, 0=N, 90=E, 180=S, 270=W)
  double get directionDegrees => throw _privateConstructorUsedError;

  /// Time until clouds reach user location (null if moving away)
  Duration? get etaToLocation => throw _privateConstructorUsedError;

  /// Current distance of nearest significant clouds in kilometers
  double get distanceKm => throw _privateConstructorUsedError;

  /// When this analysis was performed
  DateTime get calculatedAt => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $CloudMotionCopyWith<CloudMotion> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CloudMotionCopyWith<$Res> {
  factory $CloudMotionCopyWith(
          CloudMotion value, $Res Function(CloudMotion) then) =
      _$CloudMotionCopyWithImpl<$Res, CloudMotion>;
  @useResult
  $Res call(
      {double speedKmh,
      double directionDegrees,
      Duration? etaToLocation,
      double distanceKm,
      DateTime calculatedAt});
}

/// @nodoc
class _$CloudMotionCopyWithImpl<$Res, $Val extends CloudMotion>
    implements $CloudMotionCopyWith<$Res> {
  _$CloudMotionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? speedKmh = null,
    Object? directionDegrees = null,
    Object? etaToLocation = freezed,
    Object? distanceKm = null,
    Object? calculatedAt = null,
  }) {
    return _then(_value.copyWith(
      speedKmh: null == speedKmh
          ? _value.speedKmh
          : speedKmh // ignore: cast_nullable_to_non_nullable
              as double,
      directionDegrees: null == directionDegrees
          ? _value.directionDegrees
          : directionDegrees // ignore: cast_nullable_to_non_nullable
              as double,
      etaToLocation: freezed == etaToLocation
          ? _value.etaToLocation
          : etaToLocation // ignore: cast_nullable_to_non_nullable
              as Duration?,
      distanceKm: null == distanceKm
          ? _value.distanceKm
          : distanceKm // ignore: cast_nullable_to_non_nullable
              as double,
      calculatedAt: null == calculatedAt
          ? _value.calculatedAt
          : calculatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$CloudMotionImplCopyWith<$Res>
    implements $CloudMotionCopyWith<$Res> {
  factory _$$CloudMotionImplCopyWith(
          _$CloudMotionImpl value, $Res Function(_$CloudMotionImpl) then) =
      __$$CloudMotionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {double speedKmh,
      double directionDegrees,
      Duration? etaToLocation,
      double distanceKm,
      DateTime calculatedAt});
}

/// @nodoc
class __$$CloudMotionImplCopyWithImpl<$Res>
    extends _$CloudMotionCopyWithImpl<$Res, _$CloudMotionImpl>
    implements _$$CloudMotionImplCopyWith<$Res> {
  __$$CloudMotionImplCopyWithImpl(
      _$CloudMotionImpl _value, $Res Function(_$CloudMotionImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? speedKmh = null,
    Object? directionDegrees = null,
    Object? etaToLocation = freezed,
    Object? distanceKm = null,
    Object? calculatedAt = null,
  }) {
    return _then(_$CloudMotionImpl(
      speedKmh: null == speedKmh
          ? _value.speedKmh
          : speedKmh // ignore: cast_nullable_to_non_nullable
              as double,
      directionDegrees: null == directionDegrees
          ? _value.directionDegrees
          : directionDegrees // ignore: cast_nullable_to_non_nullable
              as double,
      etaToLocation: freezed == etaToLocation
          ? _value.etaToLocation
          : etaToLocation // ignore: cast_nullable_to_non_nullable
              as Duration?,
      distanceKm: null == distanceKm
          ? _value.distanceKm
          : distanceKm // ignore: cast_nullable_to_non_nullable
              as double,
      calculatedAt: null == calculatedAt
          ? _value.calculatedAt
          : calculatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$CloudMotionImpl implements _CloudMotion {
  const _$CloudMotionImpl(
      {required this.speedKmh,
      required this.directionDegrees,
      this.etaToLocation,
      required this.distanceKm,
      required this.calculatedAt});

  factory _$CloudMotionImpl.fromJson(Map<String, dynamic> json) =>
      _$$CloudMotionImplFromJson(json);

  /// Cloud movement speed in km/h
  @override
  final double speedKmh;

  /// Direction clouds are moving FROM (0-360, 0=N, 90=E, 180=S, 270=W)
  @override
  final double directionDegrees;

  /// Time until clouds reach user location (null if moving away)
  @override
  final Duration? etaToLocation;

  /// Current distance of nearest significant clouds in kilometers
  @override
  final double distanceKm;

  /// When this analysis was performed
  @override
  final DateTime calculatedAt;

  @override
  String toString() {
    return 'CloudMotion(speedKmh: $speedKmh, directionDegrees: $directionDegrees, etaToLocation: $etaToLocation, distanceKm: $distanceKm, calculatedAt: $calculatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CloudMotionImpl &&
            (identical(other.speedKmh, speedKmh) ||
                other.speedKmh == speedKmh) &&
            (identical(other.directionDegrees, directionDegrees) ||
                other.directionDegrees == directionDegrees) &&
            (identical(other.etaToLocation, etaToLocation) ||
                other.etaToLocation == etaToLocation) &&
            (identical(other.distanceKm, distanceKm) ||
                other.distanceKm == distanceKm) &&
            (identical(other.calculatedAt, calculatedAt) ||
                other.calculatedAt == calculatedAt));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, speedKmh, directionDegrees,
      etaToLocation, distanceKm, calculatedAt);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$CloudMotionImplCopyWith<_$CloudMotionImpl> get copyWith =>
      __$$CloudMotionImplCopyWithImpl<_$CloudMotionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CloudMotionImplToJson(
      this,
    );
  }
}

abstract class _CloudMotion implements CloudMotion {
  const factory _CloudMotion(
      {required final double speedKmh,
      required final double directionDegrees,
      final Duration? etaToLocation,
      required final double distanceKm,
      required final DateTime calculatedAt}) = _$CloudMotionImpl;

  factory _CloudMotion.fromJson(Map<String, dynamic> json) =
      _$CloudMotionImpl.fromJson;

  @override

  /// Cloud movement speed in km/h
  double get speedKmh;
  @override

  /// Direction clouds are moving FROM (0-360, 0=N, 90=E, 180=S, 270=W)
  double get directionDegrees;
  @override

  /// Time until clouds reach user location (null if moving away)
  Duration? get etaToLocation;
  @override

  /// Current distance of nearest significant clouds in kilometers
  double get distanceKm;
  @override

  /// When this analysis was performed
  DateTime get calculatedAt;
  @override
  @JsonKey(ignore: true)
  _$$CloudMotionImplCopyWith<_$CloudMotionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
