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
  String? get description =>
      throw _privateConstructorUsedError; // Device identifiers
  String? get cameraId => throw _privateConstructorUsedError;
  String? get mountId => throw _privateConstructorUsedError;
  String? get focuserId => throw _privateConstructorUsedError;
  String? get filterWheelId => throw _privateConstructorUsedError;
  String? get guiderId => throw _privateConstructorUsedError;
  String? get rotatorId => throw _privateConstructorUsedError;
  String? get domeId => throw _privateConstructorUsedError;
  String? get weatherId => throw _privateConstructorUsedError;
  String? get coverCalibratorId =>
      throw _privateConstructorUsedError; // Optical setup
  double get focalLength => throw _privateConstructorUsedError;
  double get aperture => throw _privateConstructorUsedError;
  double? get focalRatio =>
      throw _privateConstructorUsedError; // Camera defaults
  int? get defaultGain => throw _privateConstructorUsedError;
  int? get defaultOffset => throw _privateConstructorUsedError;
  int get defaultBinX => throw _privateConstructorUsedError;
  int get defaultBinY => throw _privateConstructorUsedError;
  double? get defaultCoolingTemp => throw _privateConstructorUsedError;
  bool get coolOnConnect =>
      throw _privateConstructorUsedError; // Centering/plate-solve exposure default (seconds)
  double? get defaultCenteringExposure =>
      throw _privateConstructorUsedError; // Filter configuration (JSON-serialized in DB)
  String? get filterNames => throw _privateConstructorUsedError;
  String? get filterFocusOffsets =>
      throw _privateConstructorUsedError; // Meridian flip settings overrides (JSON)
  String? get meridianFlipOverrides =>
      throw _privateConstructorUsedError; // User-friendly device names
  String? get cameraName => throw _privateConstructorUsedError;
  String? get mountName => throw _privateConstructorUsedError;
  String? get focuserName => throw _privateConstructorUsedError;
  String? get filterWheelName => throw _privateConstructorUsedError;
  String? get guiderName => throw _privateConstructorUsedError;
  String? get rotatorName =>
      throw _privateConstructorUsedError; // Telescope/OTA information
  String? get telescopeName => throw _privateConstructorUsedError;
  double get telescopeFocalLength => throw _privateConstructorUsedError;
  double get telescopeAperture =>
      throw _privateConstructorUsedError; // Profile customization
  String? get profileIcon => throw _privateConstructorUsedError;
  int? get profileColor => throw _privateConstructorUsedError;
  int get sortOrder => throw _privateConstructorUsedError;
  bool get isDefault => throw _privateConstructorUsedError; // Timestamps
  DateTime? get createdAt => throw _privateConstructorUsedError;
  DateTime? get updatedAt => throw _privateConstructorUsedError; // State flags
  bool get isActive =>
      throw _privateConstructorUsedError; // Camera pixel size in microns (not in DB, used by bridge)
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
      String? description,
      String? cameraId,
      String? mountId,
      String? focuserId,
      String? filterWheelId,
      String? guiderId,
      String? rotatorId,
      String? domeId,
      String? weatherId,
      String? coverCalibratorId,
      double focalLength,
      double aperture,
      double? focalRatio,
      int? defaultGain,
      int? defaultOffset,
      int defaultBinX,
      int defaultBinY,
      double? defaultCoolingTemp,
      bool coolOnConnect,
      double? defaultCenteringExposure,
      String? filterNames,
      String? filterFocusOffsets,
      String? meridianFlipOverrides,
      String? cameraName,
      String? mountName,
      String? focuserName,
      String? filterWheelName,
      String? guiderName,
      String? rotatorName,
      String? telescopeName,
      double telescopeFocalLength,
      double telescopeAperture,
      String? profileIcon,
      int? profileColor,
      int sortOrder,
      bool isDefault,
      DateTime? createdAt,
      DateTime? updatedAt,
      bool isActive,
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
    Object? description = freezed,
    Object? cameraId = freezed,
    Object? mountId = freezed,
    Object? focuserId = freezed,
    Object? filterWheelId = freezed,
    Object? guiderId = freezed,
    Object? rotatorId = freezed,
    Object? domeId = freezed,
    Object? weatherId = freezed,
    Object? coverCalibratorId = freezed,
    Object? focalLength = null,
    Object? aperture = null,
    Object? focalRatio = freezed,
    Object? defaultGain = freezed,
    Object? defaultOffset = freezed,
    Object? defaultBinX = null,
    Object? defaultBinY = null,
    Object? defaultCoolingTemp = freezed,
    Object? coolOnConnect = null,
    Object? defaultCenteringExposure = freezed,
    Object? filterNames = freezed,
    Object? filterFocusOffsets = freezed,
    Object? meridianFlipOverrides = freezed,
    Object? cameraName = freezed,
    Object? mountName = freezed,
    Object? focuserName = freezed,
    Object? filterWheelName = freezed,
    Object? guiderName = freezed,
    Object? rotatorName = freezed,
    Object? telescopeName = freezed,
    Object? telescopeFocalLength = null,
    Object? telescopeAperture = null,
    Object? profileIcon = freezed,
    Object? profileColor = freezed,
    Object? sortOrder = null,
    Object? isDefault = null,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? isActive = null,
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
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
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
      defaultGain: freezed == defaultGain
          ? _value.defaultGain
          : defaultGain // ignore: cast_nullable_to_non_nullable
              as int?,
      defaultOffset: freezed == defaultOffset
          ? _value.defaultOffset
          : defaultOffset // ignore: cast_nullable_to_non_nullable
              as int?,
      defaultBinX: null == defaultBinX
          ? _value.defaultBinX
          : defaultBinX // ignore: cast_nullable_to_non_nullable
              as int,
      defaultBinY: null == defaultBinY
          ? _value.defaultBinY
          : defaultBinY // ignore: cast_nullable_to_non_nullable
              as int,
      defaultCoolingTemp: freezed == defaultCoolingTemp
          ? _value.defaultCoolingTemp
          : defaultCoolingTemp // ignore: cast_nullable_to_non_nullable
              as double?,
      coolOnConnect: null == coolOnConnect
          ? _value.coolOnConnect
          : coolOnConnect // ignore: cast_nullable_to_non_nullable
              as bool,
      defaultCenteringExposure: freezed == defaultCenteringExposure
          ? _value.defaultCenteringExposure
          : defaultCenteringExposure // ignore: cast_nullable_to_non_nullable
              as double?,
      filterNames: freezed == filterNames
          ? _value.filterNames
          : filterNames // ignore: cast_nullable_to_non_nullable
              as String?,
      filterFocusOffsets: freezed == filterFocusOffsets
          ? _value.filterFocusOffsets
          : filterFocusOffsets // ignore: cast_nullable_to_non_nullable
              as String?,
      meridianFlipOverrides: freezed == meridianFlipOverrides
          ? _value.meridianFlipOverrides
          : meridianFlipOverrides // ignore: cast_nullable_to_non_nullable
              as String?,
      cameraName: freezed == cameraName
          ? _value.cameraName
          : cameraName // ignore: cast_nullable_to_non_nullable
              as String?,
      mountName: freezed == mountName
          ? _value.mountName
          : mountName // ignore: cast_nullable_to_non_nullable
              as String?,
      focuserName: freezed == focuserName
          ? _value.focuserName
          : focuserName // ignore: cast_nullable_to_non_nullable
              as String?,
      filterWheelName: freezed == filterWheelName
          ? _value.filterWheelName
          : filterWheelName // ignore: cast_nullable_to_non_nullable
              as String?,
      guiderName: freezed == guiderName
          ? _value.guiderName
          : guiderName // ignore: cast_nullable_to_non_nullable
              as String?,
      rotatorName: freezed == rotatorName
          ? _value.rotatorName
          : rotatorName // ignore: cast_nullable_to_non_nullable
              as String?,
      telescopeName: freezed == telescopeName
          ? _value.telescopeName
          : telescopeName // ignore: cast_nullable_to_non_nullable
              as String?,
      telescopeFocalLength: null == telescopeFocalLength
          ? _value.telescopeFocalLength
          : telescopeFocalLength // ignore: cast_nullable_to_non_nullable
              as double,
      telescopeAperture: null == telescopeAperture
          ? _value.telescopeAperture
          : telescopeAperture // ignore: cast_nullable_to_non_nullable
              as double,
      profileIcon: freezed == profileIcon
          ? _value.profileIcon
          : profileIcon // ignore: cast_nullable_to_non_nullable
              as String?,
      profileColor: freezed == profileColor
          ? _value.profileColor
          : profileColor // ignore: cast_nullable_to_non_nullable
              as int?,
      sortOrder: null == sortOrder
          ? _value.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
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
      String? description,
      String? cameraId,
      String? mountId,
      String? focuserId,
      String? filterWheelId,
      String? guiderId,
      String? rotatorId,
      String? domeId,
      String? weatherId,
      String? coverCalibratorId,
      double focalLength,
      double aperture,
      double? focalRatio,
      int? defaultGain,
      int? defaultOffset,
      int defaultBinX,
      int defaultBinY,
      double? defaultCoolingTemp,
      bool coolOnConnect,
      double? defaultCenteringExposure,
      String? filterNames,
      String? filterFocusOffsets,
      String? meridianFlipOverrides,
      String? cameraName,
      String? mountName,
      String? focuserName,
      String? filterWheelName,
      String? guiderName,
      String? rotatorName,
      String? telescopeName,
      double telescopeFocalLength,
      double telescopeAperture,
      String? profileIcon,
      int? profileColor,
      int sortOrder,
      bool isDefault,
      DateTime? createdAt,
      DateTime? updatedAt,
      bool isActive,
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
    Object? description = freezed,
    Object? cameraId = freezed,
    Object? mountId = freezed,
    Object? focuserId = freezed,
    Object? filterWheelId = freezed,
    Object? guiderId = freezed,
    Object? rotatorId = freezed,
    Object? domeId = freezed,
    Object? weatherId = freezed,
    Object? coverCalibratorId = freezed,
    Object? focalLength = null,
    Object? aperture = null,
    Object? focalRatio = freezed,
    Object? defaultGain = freezed,
    Object? defaultOffset = freezed,
    Object? defaultBinX = null,
    Object? defaultBinY = null,
    Object? defaultCoolingTemp = freezed,
    Object? coolOnConnect = null,
    Object? defaultCenteringExposure = freezed,
    Object? filterNames = freezed,
    Object? filterFocusOffsets = freezed,
    Object? meridianFlipOverrides = freezed,
    Object? cameraName = freezed,
    Object? mountName = freezed,
    Object? focuserName = freezed,
    Object? filterWheelName = freezed,
    Object? guiderName = freezed,
    Object? rotatorName = freezed,
    Object? telescopeName = freezed,
    Object? telescopeFocalLength = null,
    Object? telescopeAperture = null,
    Object? profileIcon = freezed,
    Object? profileColor = freezed,
    Object? sortOrder = null,
    Object? isDefault = null,
    Object? createdAt = freezed,
    Object? updatedAt = freezed,
    Object? isActive = null,
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
      description: freezed == description
          ? _value.description
          : description // ignore: cast_nullable_to_non_nullable
              as String?,
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
      defaultGain: freezed == defaultGain
          ? _value.defaultGain
          : defaultGain // ignore: cast_nullable_to_non_nullable
              as int?,
      defaultOffset: freezed == defaultOffset
          ? _value.defaultOffset
          : defaultOffset // ignore: cast_nullable_to_non_nullable
              as int?,
      defaultBinX: null == defaultBinX
          ? _value.defaultBinX
          : defaultBinX // ignore: cast_nullable_to_non_nullable
              as int,
      defaultBinY: null == defaultBinY
          ? _value.defaultBinY
          : defaultBinY // ignore: cast_nullable_to_non_nullable
              as int,
      defaultCoolingTemp: freezed == defaultCoolingTemp
          ? _value.defaultCoolingTemp
          : defaultCoolingTemp // ignore: cast_nullable_to_non_nullable
              as double?,
      coolOnConnect: null == coolOnConnect
          ? _value.coolOnConnect
          : coolOnConnect // ignore: cast_nullable_to_non_nullable
              as bool,
      defaultCenteringExposure: freezed == defaultCenteringExposure
          ? _value.defaultCenteringExposure
          : defaultCenteringExposure // ignore: cast_nullable_to_non_nullable
              as double?,
      filterNames: freezed == filterNames
          ? _value.filterNames
          : filterNames // ignore: cast_nullable_to_non_nullable
              as String?,
      filterFocusOffsets: freezed == filterFocusOffsets
          ? _value.filterFocusOffsets
          : filterFocusOffsets // ignore: cast_nullable_to_non_nullable
              as String?,
      meridianFlipOverrides: freezed == meridianFlipOverrides
          ? _value.meridianFlipOverrides
          : meridianFlipOverrides // ignore: cast_nullable_to_non_nullable
              as String?,
      cameraName: freezed == cameraName
          ? _value.cameraName
          : cameraName // ignore: cast_nullable_to_non_nullable
              as String?,
      mountName: freezed == mountName
          ? _value.mountName
          : mountName // ignore: cast_nullable_to_non_nullable
              as String?,
      focuserName: freezed == focuserName
          ? _value.focuserName
          : focuserName // ignore: cast_nullable_to_non_nullable
              as String?,
      filterWheelName: freezed == filterWheelName
          ? _value.filterWheelName
          : filterWheelName // ignore: cast_nullable_to_non_nullable
              as String?,
      guiderName: freezed == guiderName
          ? _value.guiderName
          : guiderName // ignore: cast_nullable_to_non_nullable
              as String?,
      rotatorName: freezed == rotatorName
          ? _value.rotatorName
          : rotatorName // ignore: cast_nullable_to_non_nullable
              as String?,
      telescopeName: freezed == telescopeName
          ? _value.telescopeName
          : telescopeName // ignore: cast_nullable_to_non_nullable
              as String?,
      telescopeFocalLength: null == telescopeFocalLength
          ? _value.telescopeFocalLength
          : telescopeFocalLength // ignore: cast_nullable_to_non_nullable
              as double,
      telescopeAperture: null == telescopeAperture
          ? _value.telescopeAperture
          : telescopeAperture // ignore: cast_nullable_to_non_nullable
              as double,
      profileIcon: freezed == profileIcon
          ? _value.profileIcon
          : profileIcon // ignore: cast_nullable_to_non_nullable
              as String?,
      profileColor: freezed == profileColor
          ? _value.profileColor
          : profileColor // ignore: cast_nullable_to_non_nullable
              as int?,
      sortOrder: null == sortOrder
          ? _value.sortOrder
          : sortOrder // ignore: cast_nullable_to_non_nullable
              as int,
      isDefault: null == isDefault
          ? _value.isDefault
          : isDefault // ignore: cast_nullable_to_non_nullable
              as bool,
      createdAt: freezed == createdAt
          ? _value.createdAt
          : createdAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      updatedAt: freezed == updatedAt
          ? _value.updatedAt
          : updatedAt // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      isActive: null == isActive
          ? _value.isActive
          : isActive // ignore: cast_nullable_to_non_nullable
              as bool,
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
      this.description,
      this.cameraId,
      this.mountId,
      this.focuserId,
      this.filterWheelId,
      this.guiderId,
      this.rotatorId,
      this.domeId,
      this.weatherId,
      this.coverCalibratorId,
      this.focalLength = 0.0,
      this.aperture = 0.0,
      this.focalRatio,
      this.defaultGain,
      this.defaultOffset,
      this.defaultBinX = 1,
      this.defaultBinY = 1,
      this.defaultCoolingTemp,
      this.coolOnConnect = false,
      this.defaultCenteringExposure,
      this.filterNames,
      this.filterFocusOffsets,
      this.meridianFlipOverrides,
      this.cameraName,
      this.mountName,
      this.focuserName,
      this.filterWheelName,
      this.guiderName,
      this.rotatorName,
      this.telescopeName,
      this.telescopeFocalLength = 0.0,
      this.telescopeAperture = 0.0,
      this.profileIcon,
      this.profileColor,
      this.sortOrder = 0,
      this.isDefault = false,
      this.createdAt,
      this.updatedAt,
      this.isActive = false,
      this.pixelSize});

  factory _$EquipmentProfileImpl.fromJson(Map<String, dynamic> json) =>
      _$$EquipmentProfileImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? description;
// Device identifiers
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
// Optical setup
  @override
  @JsonKey()
  final double focalLength;
  @override
  @JsonKey()
  final double aperture;
  @override
  final double? focalRatio;
// Camera defaults
  @override
  final int? defaultGain;
  @override
  final int? defaultOffset;
  @override
  @JsonKey()
  final int defaultBinX;
  @override
  @JsonKey()
  final int defaultBinY;
  @override
  final double? defaultCoolingTemp;
  @override
  @JsonKey()
  final bool coolOnConnect;
// Centering/plate-solve exposure default (seconds)
  @override
  final double? defaultCenteringExposure;
// Filter configuration (JSON-serialized in DB)
  @override
  final String? filterNames;
  @override
  final String? filterFocusOffsets;
// Meridian flip settings overrides (JSON)
  @override
  final String? meridianFlipOverrides;
// User-friendly device names
  @override
  final String? cameraName;
  @override
  final String? mountName;
  @override
  final String? focuserName;
  @override
  final String? filterWheelName;
  @override
  final String? guiderName;
  @override
  final String? rotatorName;
// Telescope/OTA information
  @override
  final String? telescopeName;
  @override
  @JsonKey()
  final double telescopeFocalLength;
  @override
  @JsonKey()
  final double telescopeAperture;
// Profile customization
  @override
  final String? profileIcon;
  @override
  final int? profileColor;
  @override
  @JsonKey()
  final int sortOrder;
  @override
  @JsonKey()
  final bool isDefault;
// Timestamps
  @override
  final DateTime? createdAt;
  @override
  final DateTime? updatedAt;
// State flags
  @override
  @JsonKey()
  final bool isActive;
// Camera pixel size in microns (not in DB, used by bridge)
  @override
  final double? pixelSize;

  @override
  String toString() {
    return 'EquipmentProfile(id: $id, name: $name, description: $description, cameraId: $cameraId, mountId: $mountId, focuserId: $focuserId, filterWheelId: $filterWheelId, guiderId: $guiderId, rotatorId: $rotatorId, domeId: $domeId, weatherId: $weatherId, coverCalibratorId: $coverCalibratorId, focalLength: $focalLength, aperture: $aperture, focalRatio: $focalRatio, defaultGain: $defaultGain, defaultOffset: $defaultOffset, defaultBinX: $defaultBinX, defaultBinY: $defaultBinY, defaultCoolingTemp: $defaultCoolingTemp, coolOnConnect: $coolOnConnect, defaultCenteringExposure: $defaultCenteringExposure, filterNames: $filterNames, filterFocusOffsets: $filterFocusOffsets, meridianFlipOverrides: $meridianFlipOverrides, cameraName: $cameraName, mountName: $mountName, focuserName: $focuserName, filterWheelName: $filterWheelName, guiderName: $guiderName, rotatorName: $rotatorName, telescopeName: $telescopeName, telescopeFocalLength: $telescopeFocalLength, telescopeAperture: $telescopeAperture, profileIcon: $profileIcon, profileColor: $profileColor, sortOrder: $sortOrder, isDefault: $isDefault, createdAt: $createdAt, updatedAt: $updatedAt, isActive: $isActive, pixelSize: $pixelSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EquipmentProfileImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.description, description) ||
                other.description == description) &&
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
            (identical(other.focalLength, focalLength) ||
                other.focalLength == focalLength) &&
            (identical(other.aperture, aperture) ||
                other.aperture == aperture) &&
            (identical(other.focalRatio, focalRatio) ||
                other.focalRatio == focalRatio) &&
            (identical(other.defaultGain, defaultGain) ||
                other.defaultGain == defaultGain) &&
            (identical(other.defaultOffset, defaultOffset) ||
                other.defaultOffset == defaultOffset) &&
            (identical(other.defaultBinX, defaultBinX) ||
                other.defaultBinX == defaultBinX) &&
            (identical(other.defaultBinY, defaultBinY) ||
                other.defaultBinY == defaultBinY) &&
            (identical(other.defaultCoolingTemp, defaultCoolingTemp) ||
                other.defaultCoolingTemp == defaultCoolingTemp) &&
            (identical(other.coolOnConnect, coolOnConnect) ||
                other.coolOnConnect == coolOnConnect) &&
            (identical(other.defaultCenteringExposure, defaultCenteringExposure) ||
                other.defaultCenteringExposure == defaultCenteringExposure) &&
            (identical(other.filterNames, filterNames) ||
                other.filterNames == filterNames) &&
            (identical(other.filterFocusOffsets, filterFocusOffsets) ||
                other.filterFocusOffsets == filterFocusOffsets) &&
            (identical(other.meridianFlipOverrides, meridianFlipOverrides) ||
                other.meridianFlipOverrides == meridianFlipOverrides) &&
            (identical(other.cameraName, cameraName) ||
                other.cameraName == cameraName) &&
            (identical(other.mountName, mountName) ||
                other.mountName == mountName) &&
            (identical(other.focuserName, focuserName) ||
                other.focuserName == focuserName) &&
            (identical(other.filterWheelName, filterWheelName) ||
                other.filterWheelName == filterWheelName) &&
            (identical(other.guiderName, guiderName) ||
                other.guiderName == guiderName) &&
            (identical(other.rotatorName, rotatorName) ||
                other.rotatorName == rotatorName) &&
            (identical(other.telescopeName, telescopeName) ||
                other.telescopeName == telescopeName) &&
            (identical(other.telescopeFocalLength, telescopeFocalLength) ||
                other.telescopeFocalLength == telescopeFocalLength) &&
            (identical(other.telescopeAperture, telescopeAperture) ||
                other.telescopeAperture == telescopeAperture) &&
            (identical(other.profileIcon, profileIcon) ||
                other.profileIcon == profileIcon) &&
            (identical(other.profileColor, profileColor) ||
                other.profileColor == profileColor) &&
            (identical(other.sortOrder, sortOrder) ||
                other.sortOrder == sortOrder) &&
            (identical(other.isDefault, isDefault) ||
                other.isDefault == isDefault) &&
            (identical(other.createdAt, createdAt) ||
                other.createdAt == createdAt) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt) &&
            (identical(other.isActive, isActive) ||
                other.isActive == isActive) &&
            (identical(other.pixelSize, pixelSize) ||
                other.pixelSize == pixelSize));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hashAll([
        runtimeType,
        id,
        name,
        description,
        cameraId,
        mountId,
        focuserId,
        filterWheelId,
        guiderId,
        rotatorId,
        domeId,
        weatherId,
        coverCalibratorId,
        focalLength,
        aperture,
        focalRatio,
        defaultGain,
        defaultOffset,
        defaultBinX,
        defaultBinY,
        defaultCoolingTemp,
        coolOnConnect,
        defaultCenteringExposure,
        filterNames,
        filterFocusOffsets,
        meridianFlipOverrides,
        cameraName,
        mountName,
        focuserName,
        filterWheelName,
        guiderName,
        rotatorName,
        telescopeName,
        telescopeFocalLength,
        telescopeAperture,
        profileIcon,
        profileColor,
        sortOrder,
        isDefault,
        createdAt,
        updatedAt,
        isActive,
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
      final String? description,
      final String? cameraId,
      final String? mountId,
      final String? focuserId,
      final String? filterWheelId,
      final String? guiderId,
      final String? rotatorId,
      final String? domeId,
      final String? weatherId,
      final String? coverCalibratorId,
      final double focalLength,
      final double aperture,
      final double? focalRatio,
      final int? defaultGain,
      final int? defaultOffset,
      final int defaultBinX,
      final int defaultBinY,
      final double? defaultCoolingTemp,
      final bool coolOnConnect,
      final double? defaultCenteringExposure,
      final String? filterNames,
      final String? filterFocusOffsets,
      final String? meridianFlipOverrides,
      final String? cameraName,
      final String? mountName,
      final String? focuserName,
      final String? filterWheelName,
      final String? guiderName,
      final String? rotatorName,
      final String? telescopeName,
      final double telescopeFocalLength,
      final double telescopeAperture,
      final String? profileIcon,
      final int? profileColor,
      final int sortOrder,
      final bool isDefault,
      final DateTime? createdAt,
      final DateTime? updatedAt,
      final bool isActive,
      final double? pixelSize}) = _$EquipmentProfileImpl;

  factory _EquipmentProfile.fromJson(Map<String, dynamic> json) =
      _$EquipmentProfileImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get description;
  @override // Device identifiers
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
  @override // Optical setup
  double get focalLength;
  @override
  double get aperture;
  @override
  double? get focalRatio;
  @override // Camera defaults
  int? get defaultGain;
  @override
  int? get defaultOffset;
  @override
  int get defaultBinX;
  @override
  int get defaultBinY;
  @override
  double? get defaultCoolingTemp;
  @override
  bool get coolOnConnect;
  @override // Centering/plate-solve exposure default (seconds)
  double? get defaultCenteringExposure;
  @override // Filter configuration (JSON-serialized in DB)
  String? get filterNames;
  @override
  String? get filterFocusOffsets;
  @override // Meridian flip settings overrides (JSON)
  String? get meridianFlipOverrides;
  @override // User-friendly device names
  String? get cameraName;
  @override
  String? get mountName;
  @override
  String? get focuserName;
  @override
  String? get filterWheelName;
  @override
  String? get guiderName;
  @override
  String? get rotatorName;
  @override // Telescope/OTA information
  String? get telescopeName;
  @override
  double get telescopeFocalLength;
  @override
  double get telescopeAperture;
  @override // Profile customization
  String? get profileIcon;
  @override
  int? get profileColor;
  @override
  int get sortOrder;
  @override
  bool get isDefault;
  @override // Timestamps
  DateTime? get createdAt;
  @override
  DateTime? get updatedAt;
  @override // State flags
  bool get isActive;
  @override // Camera pixel size in microns (not in DB, used by bridge)
  double? get pixelSize;
  @override
  @JsonKey(ignore: true)
  _$$EquipmentProfileImplCopyWith<_$EquipmentProfileImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
