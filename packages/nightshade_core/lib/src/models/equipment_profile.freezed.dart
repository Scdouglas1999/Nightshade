// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'equipment_profile.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

EquipmentProfile _$EquipmentProfileFromJson(Map<String, dynamic> json) {
  return _EquipmentProfile.fromJson(json);
}

/// @nodoc
mixin _$EquipmentProfile {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get cameraId => throw _privateConstructorUsedError;
  String? get mountId => throw _privateConstructorUsedError;
  String? get focuserId => throw _privateConstructorUsedError;
  String? get filterWheelId => throw _privateConstructorUsedError;
  String? get guiderId => throw _privateConstructorUsedError;
  String? get rotatorId => throw _privateConstructorUsedError;
  String? get domeId => throw _privateConstructorUsedError;
  String? get weatherId => throw _privateConstructorUsedError;
  String? get coverCalibratorId => throw _privateConstructorUsedError;
  double get telescopeFocalLength => throw _privateConstructorUsedError;
  double get telescopeAperture =>
      throw _privateConstructorUsedError; // Additional fields for compatibility with database model
  double get focalLength => throw _privateConstructorUsedError;
  double get aperture => throw _privateConstructorUsedError;
  double? get focalRatio => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError;
  bool get isActive =>
      throw _privateConstructorUsedError; // Equipment names for FITS headers
  String? get telescopeName => throw _privateConstructorUsedError;
  String? get cameraName =>
      throw _privateConstructorUsedError; // Camera pixel size in microns
  double? get pixelSize => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $EquipmentProfileCopyWith<EquipmentProfile> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EquipmentProfileCopyWith<$Res> {
  factory $EquipmentProfileCopyWith(
          EquipmentProfile value, $Res Function(EquipmentProfile) then) =
      _$EquipmentProfileCopyWithImpl<$Res, EquipmentProfile>;
  @useResult
  $Res call(
      {String id,
      String name,
      String? cameraId,
      String? mountId,
      String? focuserId,
      String? filterWheelId,
      String? guiderId,
      String? rotatorId,
      String? domeId,
      String? weatherId,
      String? coverCalibratorId,
      double telescopeFocalLength,
      double telescopeAperture,
      double focalLength,
      double aperture,
      double? focalRatio,
      DateTime? updatedAt,
      bool isActive,
      String? telescopeName,
      String? cameraName,
      double? pixelSize});
}

/// @nodoc
class _$EquipmentProfileCopyWithImpl<$Res, $Val extends EquipmentProfile>
    implements $EquipmentProfileCopyWith<$Res> {
  _$EquipmentProfileCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? cameraId = freezed,
    Object? mountId = freezed,
    Object? focuserId = freezed,
    Object? filterWheelId = freezed,
    Object? guiderId = freezed,
    Object? rotatorId = freezed,
    Object? domeId = freezed,
    Object? weatherId = freezed,
    Object? coverCalibratorId = freezed,
    Object? telescopeFocalLength = null,
    Object? telescopeAperture = null,
    Object? focalLength = null,
    Object? aperture = null,
    Object? focalRatio = freezed,
    Object? updatedAt = freezed,
    Object? isActive = null,
    Object? telescopeName = freezed,
    Object? cameraName = freezed,
    Object? pixelSize = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      cameraId: freezed == cameraId
          ? _value.cameraId
          : cameraId // ignore: cast_nullable_to_non_nullable
              as String?,
      mountId: freezed == mountId
          ? _value.mountId
          : mountId // ignore: cast_nullable_to_non_nullable
              as String?,
      focuserId: freezed == focuserId
          ? _value.focuserId
          : focuserId // ignore: cast_nullable_to_non_nullable
              as String?,
      filterWheelId: freezed == filterWheelId
          ? _value.filterWheelId
          : filterWheelId // ignore: cast_nullable_to_non_nullable
              as String?,
      guiderId: freezed == guiderId
          ? _value.guiderId
          : guiderId // ignore: cast_nullable_to_non_nullable
              as String?,
      rotatorId: freezed == rotatorId
          ? _value.rotatorId
          : rotatorId // ignore: cast_nullable_to_non_nullable
              as String?,
      domeId: freezed == domeId
          ? _value.domeId
          : domeId // ignore: cast_nullable_to_non_nullable
              as String?,
      weatherId: freezed == weatherId
          ? _value.weatherId
          : weatherId // ignore: cast_nullable_to_non_nullable
              as String?,
      coverCalibratorId: freezed == coverCalibratorId
          ? _value.coverCalibratorId
          : coverCalibratorId // ignore: cast_nullable_to_non_nullable
              as String?,
      telescopeFocalLength: null == telescopeFocalLength
          ? _value.telescopeFocalLength
          : telescopeFocalLength // ignore: cast_nullable_to_non_nullable
              as double,
      telescopeAperture: null == telescopeAperture
          ? _value.telescopeAperture
          : telescopeAperture // ignore: cast_nullable_to_non_nullable
              as double,
      focalLength: null == focalLength
          ? _value.focalLength
          : focalLength // ignore: cast_nullable_to_non_nullable
              as double,
      aperture: null == aperture
          ? _value.aperture
          : aperture // ignore: cast_nullable_to_non_nullable
              as double,
      focalRatio: freezed == focalRatio
          ? _value.focalRatio
          : focalRatio // ignore: cast_nullable_to_non_nullable
              as double?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
      telescopeName: freezed == telescopeName
          ? _value.telescopeName
          : telescopeName // ignore: cast_nullable_to_non_nullable
              as String?,
      cameraName: freezed == cameraName
          ? _value.cameraName
          : cameraName // ignore: cast_nullable_to_non_nullable
              as String?,
      pixelSize: freezed == pixelSize
          ? _value.pixelSize
          : pixelSize // ignore: cast_nullable_to_non_nullable
              as double?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$EquipmentProfileImplCopyWith<$Res>
    implements $EquipmentProfileCopyWith<$Res> {
  factory _$$EquipmentProfileImplCopyWith(_$EquipmentProfileImpl value,
          $Res Function(_$EquipmentProfileImpl) then) =
      __$$EquipmentProfileImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String? cameraId,
      String? mountId,
      String? focuserId,
      String? filterWheelId,
      String? guiderId,
      String? rotatorId,
      String? domeId,
      String? weatherId,
      String? coverCalibratorId,
      double telescopeFocalLength,
      double telescopeAperture,
      double focalLength,
      double aperture,
      double? focalRatio,
      DateTime? updatedAt,
      bool isActive,
      String? telescopeName,
      String? cameraName,
      double? pixelSize});
}

/// @nodoc
class __$$EquipmentProfileImplCopyWithImpl<$Res>
    extends _$EquipmentProfileCopyWithImpl<$Res, _$EquipmentProfileImpl>
    implements _$$EquipmentProfileImplCopyWith<$Res> {
  __$$EquipmentProfileImplCopyWithImpl(_$EquipmentProfileImpl _value,
      $Res Function(_$EquipmentProfileImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? cameraId = freezed,
    Object? mountId = freezed,
    Object? focuserId = freezed,
    Object? filterWheelId = freezed,
    Object? guiderId = freezed,
    Object? rotatorId = freezed,
    Object? domeId = freezed,
    Object? weatherId = freezed,
    Object? coverCalibratorId = freezed,
    Object? telescopeFocalLength = null,
    Object? telescopeAperture = null,
    Object? focalLength = null,
    Object? aperture = null,
    Object? focalRatio = freezed,
    Object? updatedAt = freezed,
    Object? isActive = null,
    Object? telescopeName = freezed,
    Object? cameraName = freezed,
    Object? pixelSize = freezed,
  }) {
    return _then(_$EquipmentProfileImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      cameraId: freezed == cameraId
          ? _value.cameraId
          : cameraId // ignore: cast_nullable_to_non_nullable
              as String?,
      mountId: freezed == mountId
          ? _value.mountId
          : mountId // ignore: cast_nullable_to_non_nullable
              as String?,
      focuserId: freezed == focuserId
          ? _value.focuserId
          : focuserId // ignore: cast_nullable_to_non_nullable
              as String?,
      filterWheelId: freezed == filterWheelId
          ? _value.filterWheelId
          : filterWheelId // ignore: cast_nullable_to_non_nullable
              as String?,
      guiderId: freezed == guiderId
          ? _value.guiderId
          : guiderId // ignore: cast_nullable_to_non_nullable
              as String?,
      rotatorId: freezed == rotatorId
          ? _value.rotatorId
          : rotatorId // ignore: cast_nullable_to_non_nullable
              as String?,
      domeId: freezed == domeId
          ? _value.domeId
          : domeId // ignore: cast_nullable_to_non_nullable
              as String?,
      weatherId: freezed == weatherId
          ? _value.weatherId
          : weatherId // ignore: cast_nullable_to_non_nullable
              as String?,
      coverCalibratorId: freezed == coverCalibratorId
          ? _value.coverCalibratorId
          : coverCalibratorId // ignore: cast_nullable_to_non_nullable
              as String?,
      telescopeFocalLength: null == telescopeFocalLength
          ? _value.telescopeFocalLength
          : telescopeFocalLength // ignore: cast_nullable_to_non_nullable
              as double,
      telescopeAperture: null == telescopeAperture
          ? _value.telescopeAperture
          : telescopeAperture // ignore: cast_nullable_to_non_nullable
              as double,
      focalLength: null == focalLength
          ? _value.focalLength
          : focalLength // ignore: cast_nullable_to_non_nullable
              as double,
      aperture: null == aperture
          ? _value.aperture
          : aperture // ignore: cast_nullable_to_non_nullable
              as double,
      focalRatio: freezed == focalRatio
          ? _value.focalRatio
          : focalRatio // ignore: cast_nullable_to_non_nullable
              as double?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
      telescopeName: freezed == telescopeName
          ? _value.telescopeName
          : telescopeName // ignore: cast_nullable_to_non_nullable
              as String?,
      cameraName: freezed == cameraName
          ? _value.cameraName
          : cameraName // ignore: cast_nullable_to_non_nullable
              as String?,
      pixelSize: freezed == pixelSize
          ? _value.pixelSize
          : pixelSize // ignore: cast_nullable_to_non_nullable
              as double?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$EquipmentProfileImpl implements _EquipmentProfile {
  const _$EquipmentProfileImpl(
      {required this.id,
      required this.name,
      this.cameraId,
      this.mountId,
      this.focuserId,
      this.filterWheelId,
      this.guiderId,
      this.rotatorId,
      this.domeId,
      this.weatherId,
      this.coverCalibratorId,
      this.telescopeFocalLength = 0.0,
      this.telescopeAperture = 0.0,
      this.focalLength = 0.0,
      this.aperture = 0.0,
      this.focalRatio,
      this.updatedAt,
      this.isActive = false,
      this.telescopeName,
      this.cameraName,
      this.pixelSize});

  factory _$EquipmentProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$EquipmentProfileImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? cameraId;
  @override
  final String? mountId;
  @override
  final String? focuserId;
  @override
  final String? filterWheelId;
  @override
  final String? guiderId;
  @override
  final String? rotatorId;
  @override
  final String? domeId;
  @override
  final String? weatherId;
  @override
  final String? coverCalibratorId;
  @override
  @JsonKey()
  final double telescopeFocalLength;
  @override
  @JsonKey()
  final double telescopeAperture;
// Additional fields for compatibility with database model
  @override
  @JsonKey()
  final double focalLength;
  @override
  @JsonKey()
  final double aperture;
  @override
  final double? focalRatio;
  @override
  final DateTime? updatedAt;
  @override
  @JsonKey()
  final bool isActive;
// Equipment names for FITS headers
  @override
  final String? telescopeName;
  @override
  final String? cameraName;
// Camera pixel size in microns
  @override
  final double? pixelSize;

  @override
  String toString() {
    return 'EquipmentProfile(id: $id, name: $name, cameraId: $cameraId, mountId: $mountId, focuserId: $focuserId, filterWheelId: $filterWheelId, guiderId: $guiderId, rotatorId: $rotatorId, domeId: $domeId, weatherId: $weatherId, coverCalibratorId: $coverCalibratorId, telescopeFocalLength: $telescopeFocalLength, telescopeAperture: $telescopeAperture, focalLength: $focalLength, aperture: $aperture, focalRatio: $focalRatio, updatedAt: $updatedAt, isActive: $isActive, telescopeName: $telescopeName, cameraName: $cameraName, pixelSize: $pixelSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EquipmentProfileImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.cameraId, cameraId) ||
                other.cameraId == cameraId) &&
            (identical(other.mountId, mountId) || other.mountId == mountId) &&
            (identical(other.focuserId, focuserId) ||
                other.focuserId == focuserId) &&
            (identical(other.filterWheelId, filterWheelId) ||
                other.filterWheelId == filterWheelId) &&
            (identical(other.guiderId, guiderId) ||
                other.guiderId == guiderId) &&
            (identical(other.rotatorId, rotatorId) ||
                other.rotatorId == rotatorId) &&
            (identical(other.domeId, domeId) || other.domeId == domeId) &&
            (identical(other.weatherId, weatherId) ||
                other.weatherId == weatherId) &&
            (identical(other.coverCalibratorId, coverCalibratorId) ||
                other.coverCalibratorId == coverCalibratorId) &&
            (identical(other.telescopeFocalLength, telescopeFocalLength) ||
                other.telescopeFocalLength == telescopeFocalLength) &&
            (identical(other.telescopeAperture, telescopeAperture) ||
                other.telescopeAperture == telescopeAperture) &&
            (identical(other.focalLength, focalLength) ||
                other.focalLength == focalLength) &&
            (identical(other.aperture, aperture) ||
                other.aperture == aperture) &&
            (identical(other.focalRatio, focalRatio) ||
                other.focalRatio == focalRatio) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive) &&
            (identical(other.telescopeName, telescopeName) ||
                other.telescopeName == telescopeName) &&
            (identical(other.cameraName, cameraName) ||
                other.cameraName == cameraName) &&
            (identical(other.pixelSize, pixelSize) ||
                other.pixelSize == pixelSize));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        name,
        cameraId,
        mountId,
        focuserId,
        filterWheelId,
        guiderId,
        rotatorId,
        domeId,
        weatherId,
        coverCalibratorId,
        telescopeFocalLength,
        telescopeAperture,
        focalLength,
        aperture,
        focalRatio,
        updatedAt,
        isActive,
        telescopeName,
        cameraName,
        pixelSize
      ]);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$EquipmentProfileImplCopyWith<_$EquipmentProfileImpl> get copyWith =>
      __$$EquipmentProfileImplCopyWithImpl<_$EquipmentProfileImpl>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$EquipmentProfileImplToJson(
      this,
    );
  }
}

abstract class _EquipmentProfile implements EquipmentProfile {
  const factory _EquipmentProfile(
      {required final String id,
      required final String name,
      final String? cameraId,
      final String? mountId,
      final String? focuserId,
      final String? filterWheelId,
      final String? guiderId,
      final String? rotatorId,
      final String? domeId,
      final String? weatherId,
      final String? coverCalibratorId,
      final double telescopeFocalLength,
      final double telescopeAperture,
      final double focalLength,
      final double aperture,
      final double? focalRatio,
      final DateTime? updatedAt,
      final bool isActive,
      final String? telescopeName,
      final String? cameraName,
      final double? pixelSize}) = _$EquipmentProfileImpl;

  factory _EquipmentProfile.fromJson(Map<String, dynamic> json) =
      _$EquipmentProfileImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get cameraId;
  @override
  String? get mountId;
  @override
  String? get focuserId;
  @override
  String? get filterWheelId;
  @override
  String? get guiderId;
  @override
  String? get rotatorId;
  @override
  String? get domeId;
  @override
  String? get weatherId;
  @override
  String? get coverCalibratorId;
  @override
  double get telescopeFocalLength;
  @override
  double get telescopeAperture;
  @override // Additional fields for compatibility with database model
  double get focalLength;
  @override
  double get aperture;
  @override
  double? get focalRatio;
  @override
  DateTime? get updatedAt;
  @override
  bool get isActive;
  @override // Equipment names for FITS headers
  String? get telescopeName;
  @override
  String? get cameraName;
  @override // Camera pixel size in microns
  double? get pixelSize;
  @override
  @JsonKey(ignore: true)
  _$$EquipmentProfileImplCopyWith<_$EquipmentProfileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
