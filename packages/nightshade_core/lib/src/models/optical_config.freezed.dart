// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'optical_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

OpticalConfig _$OpticalConfigFromJson(Map<String, dynamic> json) {
  return _OpticalConfig.fromJson(json);
}

/// @nodoc
mixin _$OpticalConfig {
  /// Name of the telescope/OTA
  String? get telescopeName => throw _privateConstructorUsedError;

  /// Focal length in millimeters
  double? get focalLength => throw _privateConstructorUsedError;

  /// Aperture in millimeters
  double? get aperture => throw _privateConstructorUsedError;

  /// Focal ratio (f/number), computed from focalLength/aperture if not set
  double? get focalRatio => throw _privateConstructorUsedError;

  /// Camera name
  String? get cameraName => throw _privateConstructorUsedError;

  /// Sensor width in pixels
  int? get sensorWidth => throw _privateConstructorUsedError;

  /// Sensor height in pixels
  int? get sensorHeight => throw _privateConstructorUsedError;

  /// Pixel size in microns
  double? get pixelSize => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $OpticalConfigCopyWith<OpticalConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OpticalConfigCopyWith<$Res> {
  factory $OpticalConfigCopyWith(
          OpticalConfig value, $Res Function(OpticalConfig) then) =
      _$OpticalConfigCopyWithImpl<$Res, OpticalConfig>;
  @useResult
  $Res call(
      {String? telescopeName,
      double? focalLength,
      double? aperture,
      double? focalRatio,
      String? cameraName,
      int? sensorWidth,
      int? sensorHeight,
      double? pixelSize});
}

/// @nodoc
class _$OpticalConfigCopyWithImpl<$Res, $Val extends OpticalConfig>
    implements $OpticalConfigCopyWith<$Res> {
  _$OpticalConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? telescopeName = freezed,
    Object? focalLength = freezed,
    Object? aperture = freezed,
    Object? focalRatio = freezed,
    Object? cameraName = freezed,
    Object? sensorWidth = freezed,
    Object? sensorHeight = freezed,
    Object? pixelSize = freezed,
  }) {
    return _then(_value.copyWith(
      telescopeName: freezed == telescopeName
          ? _value.telescopeName
          : telescopeName // ignore: cast_nullable_to_non_nullable
              as String?,
      focalLength: freezed == focalLength
          ? _value.focalLength
          : focalLength // ignore: cast_nullable_to_non_nullable
              as double?,
      aperture: freezed == aperture
          ? _value.aperture
          : aperture // ignore: cast_nullable_to_non_nullable
              as double?,
      focalRatio: freezed == focalRatio
          ? _value.focalRatio
          : focalRatio // ignore: cast_nullable_to_non_nullable
              as double?,
      cameraName: freezed == cameraName
          ? _value.cameraName
          : cameraName // ignore: cast_nullable_to_non_nullable
              as String?,
      sensorWidth: freezed == sensorWidth
          ? _value.sensorWidth
          : sensorWidth // ignore: cast_nullable_to_non_nullable
              as int?,
      sensorHeight: freezed == sensorHeight
          ? _value.sensorHeight
          : sensorHeight // ignore: cast_nullable_to_non_nullable
              as int?,
      pixelSize: freezed == pixelSize
          ? _value.pixelSize
          : pixelSize // ignore: cast_nullable_to_non_nullable
              as double?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$OpticalConfigImplCopyWith<$Res>
    implements $OpticalConfigCopyWith<$Res> {
  factory _$$OpticalConfigImplCopyWith(
          _$OpticalConfigImpl value, $Res Function(_$OpticalConfigImpl) then) =
      __$$OpticalConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String? telescopeName,
      double? focalLength,
      double? aperture,
      double? focalRatio,
      String? cameraName,
      int? sensorWidth,
      int? sensorHeight,
      double? pixelSize});
}

/// @nodoc
class __$$OpticalConfigImplCopyWithImpl<$Res>
    extends _$OpticalConfigCopyWithImpl<$Res, _$OpticalConfigImpl>
    implements _$$OpticalConfigImplCopyWith<$Res> {
  __$$OpticalConfigImplCopyWithImpl(
      _$OpticalConfigImpl _value, $Res Function(_$OpticalConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? telescopeName = freezed,
    Object? focalLength = freezed,
    Object? aperture = freezed,
    Object? focalRatio = freezed,
    Object? cameraName = freezed,
    Object? sensorWidth = freezed,
    Object? sensorHeight = freezed,
    Object? pixelSize = freezed,
  }) {
    return _then(_$OpticalConfigImpl(
      telescopeName: freezed == telescopeName
          ? _value.telescopeName
          : telescopeName // ignore: cast_nullable_to_non_nullable
              as String?,
      focalLength: freezed == focalLength
          ? _value.focalLength
          : focalLength // ignore: cast_nullable_to_non_nullable
              as double?,
      aperture: freezed == aperture
          ? _value.aperture
          : aperture // ignore: cast_nullable_to_non_nullable
              as double?,
      focalRatio: freezed == focalRatio
          ? _value.focalRatio
          : focalRatio // ignore: cast_nullable_to_non_nullable
              as double?,
      cameraName: freezed == cameraName
          ? _value.cameraName
          : cameraName // ignore: cast_nullable_to_non_nullable
              as String?,
      sensorWidth: freezed == sensorWidth
          ? _value.sensorWidth
          : sensorWidth // ignore: cast_nullable_to_non_nullable
              as int?,
      sensorHeight: freezed == sensorHeight
          ? _value.sensorHeight
          : sensorHeight // ignore: cast_nullable_to_non_nullable
              as int?,
      pixelSize: freezed == pixelSize
          ? _value.pixelSize
          : pixelSize // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$OpticalConfigImpl extends _OpticalConfig {
  const _$OpticalConfigImpl(
      {this.telescopeName,
      this.focalLength,
      this.aperture,
      this.focalRatio,
      this.cameraName,
      this.sensorWidth,
      this.sensorHeight,
      this.pixelSize})
      : super._();

  factory _$OpticalConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$OpticalConfigImplFromJson(json);

  /// Name of the telescope/OTA
  @override
  final String? telescopeName;

  /// Focal length in millimeters
  @override
  final double? focalLength;

  /// Aperture in millimeters
  @override
  final double? aperture;

  /// Focal ratio (f/number), computed from focalLength/aperture if not set
  @override
  final double? focalRatio;

  /// Camera name
  @override
  final String? cameraName;

  /// Sensor width in pixels
  @override
  final int? sensorWidth;

  /// Sensor height in pixels
  @override
  final int? sensorHeight;

  /// Pixel size in microns
  @override
  final double? pixelSize;

  @override
  String toString() {
    return 'OpticalConfig(telescopeName: $telescopeName, focalLength: $focalLength, aperture: $aperture, focalRatio: $focalRatio, cameraName: $cameraName, sensorWidth: $sensorWidth, sensorHeight: $sensorHeight, pixelSize: $pixelSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OpticalConfigImpl &&
            (identical(other.telescopeName, telescopeName) ||
                other.telescopeName == telescopeName) &&
            (identical(other.focalLength, focalLength) ||
                other.focalLength == focalLength) &&
            (identical(other.aperture, aperture) ||
                other.aperture == aperture) &&
            (identical(other.focalRatio, focalRatio) ||
                other.focalRatio == focalRatio) &&
            (identical(other.cameraName, cameraName) ||
                other.cameraName == cameraName) &&
            (identical(other.sensorWidth, sensorWidth) ||
                other.sensorWidth == sensorWidth) &&
            (identical(other.sensorHeight, sensorHeight) ||
                other.sensorHeight == sensorHeight) &&
            (identical(other.pixelSize, pixelSize) ||
                other.pixelSize == pixelSize));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, telescopeName, focalLength,
      aperture, focalRatio, cameraName, sensorWidth, sensorHeight, pixelSize);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$OpticalConfigImplCopyWith<_$OpticalConfigImpl> get copyWith =>
      __$$OpticalConfigImplCopyWithImpl<_$OpticalConfigImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OpticalConfigImplToJson(
      this,
    );
  }
}

abstract class _OpticalConfig extends OpticalConfig {
  const factory _OpticalConfig(
      {final String? telescopeName,
      final double? focalLength,
      final double? aperture,
      final double? focalRatio,
      final String? cameraName,
      final int? sensorWidth,
      final int? sensorHeight,
      final double? pixelSize}) = _$OpticalConfigImpl;
  const _OpticalConfig._() : super._();

  factory _OpticalConfig.fromJson(Map<String, dynamic> json) =
      _$OpticalConfigImpl.fromJson;

  @override

  /// Name of the telescope/OTA
  String? get telescopeName;
  @override

  /// Focal length in millimeters
  double? get focalLength;
  @override

  /// Aperture in millimeters
  double? get aperture;
  @override

  /// Focal ratio (f/number), computed from focalLength/aperture if not set
  double? get focalRatio;
  @override

  /// Camera name
  String? get cameraName;
  @override

  /// Sensor width in pixels
  int? get sensorWidth;
  @override

  /// Sensor height in pixels
  int? get sensorHeight;
  @override

  /// Pixel size in microns
  double? get pixelSize;
  @override
  @JsonKey(ignore: true)
  _$$OpticalConfigImplCopyWith<_$OpticalConfigImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
