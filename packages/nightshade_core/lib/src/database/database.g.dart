// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $EquipmentProfilesTable extends EquipmentProfiles
    with TableInfo<$EquipmentProfilesTable, EquipmentProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EquipmentProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 100),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cameraIdMeta =
      const VerificationMeta('cameraId');
  @override
  late final GeneratedColumn<String> cameraId = GeneratedColumn<String>(
      'camera_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _mountIdMeta =
      const VerificationMeta('mountId');
  @override
  late final GeneratedColumn<String> mountId = GeneratedColumn<String>(
      'mount_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _focuserIdMeta =
      const VerificationMeta('focuserId');
  @override
  late final GeneratedColumn<String> focuserId = GeneratedColumn<String>(
      'focuser_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _filterWheelIdMeta =
      const VerificationMeta('filterWheelId');
  @override
  late final GeneratedColumn<String> filterWheelId = GeneratedColumn<String>(
      'filter_wheel_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _guiderIdMeta =
      const VerificationMeta('guiderId');
  @override
  late final GeneratedColumn<String> guiderId = GeneratedColumn<String>(
      'guider_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _rotatorIdMeta =
      const VerificationMeta('rotatorId');
  @override
  late final GeneratedColumn<String> rotatorId = GeneratedColumn<String>(
      'rotator_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _domeIdMeta = const VerificationMeta('domeId');
  @override
  late final GeneratedColumn<String> domeId = GeneratedColumn<String>(
      'dome_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _weatherIdMeta =
      const VerificationMeta('weatherId');
  @override
  late final GeneratedColumn<String> weatherId = GeneratedColumn<String>(
      'weather_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _coverCalibratorIdMeta =
      const VerificationMeta('coverCalibratorId');
  @override
  late final GeneratedColumn<String> coverCalibratorId =
      GeneratedColumn<String>('cover_calibrator_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _focalLengthMeta =
      const VerificationMeta('focalLength');
  @override
  late final GeneratedColumn<double> focalLength = GeneratedColumn<double>(
      'focal_length', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _apertureMeta =
      const VerificationMeta('aperture');
  @override
  late final GeneratedColumn<double> aperture = GeneratedColumn<double>(
      'aperture', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0.0));
  static const VerificationMeta _focalRatioMeta =
      const VerificationMeta('focalRatio');
  @override
  late final GeneratedColumn<double> focalRatio = GeneratedColumn<double>(
      'focal_ratio', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _defaultGainMeta =
      const VerificationMeta('defaultGain');
  @override
  late final GeneratedColumn<int> defaultGain = GeneratedColumn<int>(
      'default_gain', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _defaultOffsetMeta =
      const VerificationMeta('defaultOffset');
  @override
  late final GeneratedColumn<int> defaultOffset = GeneratedColumn<int>(
      'default_offset', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _defaultBinXMeta =
      const VerificationMeta('defaultBinX');
  @override
  late final GeneratedColumn<int> defaultBinX = GeneratedColumn<int>(
      'default_bin_x', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _defaultBinYMeta =
      const VerificationMeta('defaultBinY');
  @override
  late final GeneratedColumn<int> defaultBinY = GeneratedColumn<int>(
      'default_bin_y', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _defaultCoolingTempMeta =
      const VerificationMeta('defaultCoolingTemp');
  @override
  late final GeneratedColumn<double> defaultCoolingTemp =
      GeneratedColumn<double>('default_cooling_temp', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _filterNamesMeta =
      const VerificationMeta('filterNames');
  @override
  late final GeneratedColumn<String> filterNames = GeneratedColumn<String>(
      'filter_names', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _filterFocusOffsetsMeta =
      const VerificationMeta('filterFocusOffsets');
  @override
  late final GeneratedColumn<String> filterFocusOffsets =
      GeneratedColumn<String>('filter_focus_offsets', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _meridianFlipOverridesMeta =
      const VerificationMeta('meridianFlipOverrides');
  @override
  late final GeneratedColumn<String> meridianFlipOverrides =
      GeneratedColumn<String>('meridian_flip_overrides', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cameraNameMeta =
      const VerificationMeta('cameraName');
  @override
  late final GeneratedColumn<String> cameraName = GeneratedColumn<String>(
      'camera_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _mountNameMeta =
      const VerificationMeta('mountName');
  @override
  late final GeneratedColumn<String> mountName = GeneratedColumn<String>(
      'mount_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _focuserNameMeta =
      const VerificationMeta('focuserName');
  @override
  late final GeneratedColumn<String> focuserName = GeneratedColumn<String>(
      'focuser_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _filterWheelNameMeta =
      const VerificationMeta('filterWheelName');
  @override
  late final GeneratedColumn<String> filterWheelName = GeneratedColumn<String>(
      'filter_wheel_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _guiderNameMeta =
      const VerificationMeta('guiderName');
  @override
  late final GeneratedColumn<String> guiderName = GeneratedColumn<String>(
      'guider_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _rotatorNameMeta =
      const VerificationMeta('rotatorName');
  @override
  late final GeneratedColumn<String> rotatorName = GeneratedColumn<String>(
      'rotator_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _telescopeNameMeta =
      const VerificationMeta('telescopeName');
  @override
  late final GeneratedColumn<String> telescopeName = GeneratedColumn<String>(
      'telescope_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _telescopeFocalLengthMeta =
      const VerificationMeta('telescopeFocalLength');
  @override
  late final GeneratedColumn<double> telescopeFocalLength =
      GeneratedColumn<double>('telescope_focal_length', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _telescopeApertureMeta =
      const VerificationMeta('telescopeAperture');
  @override
  late final GeneratedColumn<double> telescopeAperture =
      GeneratedColumn<double>('telescope_aperture', aliasedName, true,
          type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _profileIconMeta =
      const VerificationMeta('profileIcon');
  @override
  late final GeneratedColumn<String> profileIcon = GeneratedColumn<String>(
      'profile_icon', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _profileColorMeta =
      const VerificationMeta('profileColor');
  @override
  late final GeneratedColumn<int> profileColor = GeneratedColumn<int>(
      'profile_color', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isDefaultMeta =
      const VerificationMeta('isDefault');
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
      'is_default', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_default" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
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
        isActive
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'equipment_profiles';
  @override
  VerificationContext validateIntegrity(Insertable<EquipmentProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('camera_id')) {
      context.handle(_cameraIdMeta,
          cameraId.isAcceptableOrUnknown(data['camera_id']!, _cameraIdMeta));
    }
    if (data.containsKey('mount_id')) {
      context.handle(_mountIdMeta,
          mountId.isAcceptableOrUnknown(data['mount_id']!, _mountIdMeta));
    }
    if (data.containsKey('focuser_id')) {
      context.handle(_focuserIdMeta,
          focuserId.isAcceptableOrUnknown(data['focuser_id']!, _focuserIdMeta));
    }
    if (data.containsKey('filter_wheel_id')) {
      context.handle(
          _filterWheelIdMeta,
          filterWheelId.isAcceptableOrUnknown(
              data['filter_wheel_id']!, _filterWheelIdMeta));
    }
    if (data.containsKey('guider_id')) {
      context.handle(_guiderIdMeta,
          guiderId.isAcceptableOrUnknown(data['guider_id']!, _guiderIdMeta));
    }
    if (data.containsKey('rotator_id')) {
      context.handle(_rotatorIdMeta,
          rotatorId.isAcceptableOrUnknown(data['rotator_id']!, _rotatorIdMeta));
    }
    if (data.containsKey('dome_id')) {
      context.handle(_domeIdMeta,
          domeId.isAcceptableOrUnknown(data['dome_id']!, _domeIdMeta));
    }
    if (data.containsKey('weather_id')) {
      context.handle(_weatherIdMeta,
          weatherId.isAcceptableOrUnknown(data['weather_id']!, _weatherIdMeta));
    }
    if (data.containsKey('cover_calibrator_id')) {
      context.handle(
          _coverCalibratorIdMeta,
          coverCalibratorId.isAcceptableOrUnknown(
              data['cover_calibrator_id']!, _coverCalibratorIdMeta));
    }
    if (data.containsKey('focal_length')) {
      context.handle(
          _focalLengthMeta,
          focalLength.isAcceptableOrUnknown(
              data['focal_length']!, _focalLengthMeta));
    }
    if (data.containsKey('aperture')) {
      context.handle(_apertureMeta,
          aperture.isAcceptableOrUnknown(data['aperture']!, _apertureMeta));
    }
    if (data.containsKey('focal_ratio')) {
      context.handle(
          _focalRatioMeta,
          focalRatio.isAcceptableOrUnknown(
              data['focal_ratio']!, _focalRatioMeta));
    }
    if (data.containsKey('default_gain')) {
      context.handle(
          _defaultGainMeta,
          defaultGain.isAcceptableOrUnknown(
              data['default_gain']!, _defaultGainMeta));
    }
    if (data.containsKey('default_offset')) {
      context.handle(
          _defaultOffsetMeta,
          defaultOffset.isAcceptableOrUnknown(
              data['default_offset']!, _defaultOffsetMeta));
    }
    if (data.containsKey('default_bin_x')) {
      context.handle(
          _defaultBinXMeta,
          defaultBinX.isAcceptableOrUnknown(
              data['default_bin_x']!, _defaultBinXMeta));
    }
    if (data.containsKey('default_bin_y')) {
      context.handle(
          _defaultBinYMeta,
          defaultBinY.isAcceptableOrUnknown(
              data['default_bin_y']!, _defaultBinYMeta));
    }
    if (data.containsKey('default_cooling_temp')) {
      context.handle(
          _defaultCoolingTempMeta,
          defaultCoolingTemp.isAcceptableOrUnknown(
              data['default_cooling_temp']!, _defaultCoolingTempMeta));
    }
    if (data.containsKey('filter_names')) {
      context.handle(
          _filterNamesMeta,
          filterNames.isAcceptableOrUnknown(
              data['filter_names']!, _filterNamesMeta));
    }
    if (data.containsKey('filter_focus_offsets')) {
      context.handle(
          _filterFocusOffsetsMeta,
          filterFocusOffsets.isAcceptableOrUnknown(
              data['filter_focus_offsets']!, _filterFocusOffsetsMeta));
    }
    if (data.containsKey('meridian_flip_overrides')) {
      context.handle(
          _meridianFlipOverridesMeta,
          meridianFlipOverrides.isAcceptableOrUnknown(
              data['meridian_flip_overrides']!, _meridianFlipOverridesMeta));
    }
    if (data.containsKey('camera_name')) {
      context.handle(
          _cameraNameMeta,
          cameraName.isAcceptableOrUnknown(
              data['camera_name']!, _cameraNameMeta));
    }
    if (data.containsKey('mount_name')) {
      context.handle(_mountNameMeta,
          mountName.isAcceptableOrUnknown(data['mount_name']!, _mountNameMeta));
    }
    if (data.containsKey('focuser_name')) {
      context.handle(
          _focuserNameMeta,
          focuserName.isAcceptableOrUnknown(
              data['focuser_name']!, _focuserNameMeta));
    }
    if (data.containsKey('filter_wheel_name')) {
      context.handle(
          _filterWheelNameMeta,
          filterWheelName.isAcceptableOrUnknown(
              data['filter_wheel_name']!, _filterWheelNameMeta));
    }
    if (data.containsKey('guider_name')) {
      context.handle(
          _guiderNameMeta,
          guiderName.isAcceptableOrUnknown(
              data['guider_name']!, _guiderNameMeta));
    }
    if (data.containsKey('rotator_name')) {
      context.handle(
          _rotatorNameMeta,
          rotatorName.isAcceptableOrUnknown(
              data['rotator_name']!, _rotatorNameMeta));
    }
    if (data.containsKey('telescope_name')) {
      context.handle(
          _telescopeNameMeta,
          telescopeName.isAcceptableOrUnknown(
              data['telescope_name']!, _telescopeNameMeta));
    }
    if (data.containsKey('telescope_focal_length')) {
      context.handle(
          _telescopeFocalLengthMeta,
          telescopeFocalLength.isAcceptableOrUnknown(
              data['telescope_focal_length']!, _telescopeFocalLengthMeta));
    }
    if (data.containsKey('telescope_aperture')) {
      context.handle(
          _telescopeApertureMeta,
          telescopeAperture.isAcceptableOrUnknown(
              data['telescope_aperture']!, _telescopeApertureMeta));
    }
    if (data.containsKey('profile_icon')) {
      context.handle(
          _profileIconMeta,
          profileIcon.isAcceptableOrUnknown(
              data['profile_icon']!, _profileIconMeta));
    }
    if (data.containsKey('profile_color')) {
      context.handle(
          _profileColorMeta,
          profileColor.isAcceptableOrUnknown(
              data['profile_color']!, _profileColorMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
    }
    if (data.containsKey('is_default')) {
      context.handle(_isDefaultMeta,
          isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EquipmentProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EquipmentProfile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      cameraId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}camera_id']),
      mountId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mount_id']),
      focuserId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}focuser_id']),
      filterWheelId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filter_wheel_id']),
      guiderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}guider_id']),
      rotatorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rotator_id']),
      domeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}dome_id']),
      weatherId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}weather_id']),
      coverCalibratorId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}cover_calibrator_id']),
      focalLength: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}focal_length'])!,
      aperture: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}aperture'])!,
      focalRatio: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}focal_ratio']),
      defaultGain: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}default_gain']),
      defaultOffset: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}default_offset']),
      defaultBinX: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}default_bin_x'])!,
      defaultBinY: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}default_bin_y'])!,
      defaultCoolingTemp: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}default_cooling_temp']),
      filterNames: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filter_names']),
      filterFocusOffsets: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}filter_focus_offsets']),
      meridianFlipOverrides: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}meridian_flip_overrides']),
      cameraName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}camera_name']),
      mountName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mount_name']),
      focuserName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}focuser_name']),
      filterWheelName: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}filter_wheel_name']),
      guiderName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}guider_name']),
      rotatorName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}rotator_name']),
      telescopeName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}telescope_name']),
      telescopeFocalLength: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}telescope_focal_length']),
      telescopeAperture: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}telescope_aperture']),
      profileIcon: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}profile_icon']),
      profileColor: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}profile_color']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
      isDefault: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_default'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
    );
  }

  @override
  $EquipmentProfilesTable createAlias(String alias) {
    return $EquipmentProfilesTable(attachedDatabase, alias);
  }
}

class EquipmentProfile extends DataClass
    implements Insertable<EquipmentProfile> {
  final int id;
  final String name;
  final String? description;
  final String? cameraId;
  final String? mountId;
  final String? focuserId;
  final String? filterWheelId;
  final String? guiderId;
  final String? rotatorId;
  final String? domeId;
  final String? weatherId;
  final String? coverCalibratorId;
  final double focalLength;
  final double aperture;
  final double? focalRatio;
  final int? defaultGain;
  final int? defaultOffset;
  final int defaultBinX;
  final int defaultBinY;
  final double? defaultCoolingTemp;
  final String? filterNames;
  final String? filterFocusOffsets;
  final String? meridianFlipOverrides;
  final String? cameraName;
  final String? mountName;
  final String? focuserName;
  final String? filterWheelName;
  final String? guiderName;
  final String? rotatorName;
  final String? telescopeName;
  final double? telescopeFocalLength;
  final double? telescopeAperture;
  final String? profileIcon;
  final int? profileColor;
  final int sortOrder;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  const EquipmentProfile(
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
      required this.focalLength,
      required this.aperture,
      this.focalRatio,
      this.defaultGain,
      this.defaultOffset,
      required this.defaultBinX,
      required this.defaultBinY,
      this.defaultCoolingTemp,
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
      this.telescopeFocalLength,
      this.telescopeAperture,
      this.profileIcon,
      this.profileColor,
      required this.sortOrder,
      required this.isDefault,
      required this.createdAt,
      required this.updatedAt,
      required this.isActive});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || cameraId != null) {
      map['camera_id'] = Variable<String>(cameraId);
    }
    if (!nullToAbsent || mountId != null) {
      map['mount_id'] = Variable<String>(mountId);
    }
    if (!nullToAbsent || focuserId != null) {
      map['focuser_id'] = Variable<String>(focuserId);
    }
    if (!nullToAbsent || filterWheelId != null) {
      map['filter_wheel_id'] = Variable<String>(filterWheelId);
    }
    if (!nullToAbsent || guiderId != null) {
      map['guider_id'] = Variable<String>(guiderId);
    }
    if (!nullToAbsent || rotatorId != null) {
      map['rotator_id'] = Variable<String>(rotatorId);
    }
    if (!nullToAbsent || domeId != null) {
      map['dome_id'] = Variable<String>(domeId);
    }
    if (!nullToAbsent || weatherId != null) {
      map['weather_id'] = Variable<String>(weatherId);
    }
    if (!nullToAbsent || coverCalibratorId != null) {
      map['cover_calibrator_id'] = Variable<String>(coverCalibratorId);
    }
    map['focal_length'] = Variable<double>(focalLength);
    map['aperture'] = Variable<double>(aperture);
    if (!nullToAbsent || focalRatio != null) {
      map['focal_ratio'] = Variable<double>(focalRatio);
    }
    if (!nullToAbsent || defaultGain != null) {
      map['default_gain'] = Variable<int>(defaultGain);
    }
    if (!nullToAbsent || defaultOffset != null) {
      map['default_offset'] = Variable<int>(defaultOffset);
    }
    map['default_bin_x'] = Variable<int>(defaultBinX);
    map['default_bin_y'] = Variable<int>(defaultBinY);
    if (!nullToAbsent || defaultCoolingTemp != null) {
      map['default_cooling_temp'] = Variable<double>(defaultCoolingTemp);
    }
    if (!nullToAbsent || filterNames != null) {
      map['filter_names'] = Variable<String>(filterNames);
    }
    if (!nullToAbsent || filterFocusOffsets != null) {
      map['filter_focus_offsets'] = Variable<String>(filterFocusOffsets);
    }
    if (!nullToAbsent || meridianFlipOverrides != null) {
      map['meridian_flip_overrides'] = Variable<String>(meridianFlipOverrides);
    }
    if (!nullToAbsent || cameraName != null) {
      map['camera_name'] = Variable<String>(cameraName);
    }
    if (!nullToAbsent || mountName != null) {
      map['mount_name'] = Variable<String>(mountName);
    }
    if (!nullToAbsent || focuserName != null) {
      map['focuser_name'] = Variable<String>(focuserName);
    }
    if (!nullToAbsent || filterWheelName != null) {
      map['filter_wheel_name'] = Variable<String>(filterWheelName);
    }
    if (!nullToAbsent || guiderName != null) {
      map['guider_name'] = Variable<String>(guiderName);
    }
    if (!nullToAbsent || rotatorName != null) {
      map['rotator_name'] = Variable<String>(rotatorName);
    }
    if (!nullToAbsent || telescopeName != null) {
      map['telescope_name'] = Variable<String>(telescopeName);
    }
    if (!nullToAbsent || telescopeFocalLength != null) {
      map['telescope_focal_length'] = Variable<double>(telescopeFocalLength);
    }
    if (!nullToAbsent || telescopeAperture != null) {
      map['telescope_aperture'] = Variable<double>(telescopeAperture);
    }
    if (!nullToAbsent || profileIcon != null) {
      map['profile_icon'] = Variable<String>(profileIcon);
    }
    if (!nullToAbsent || profileColor != null) {
      map['profile_color'] = Variable<int>(profileColor);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_default'] = Variable<bool>(isDefault);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  EquipmentProfilesCompanion toCompanion(bool nullToAbsent) {
    return EquipmentProfilesCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      cameraId: cameraId == null && nullToAbsent
          ? const Value.absent()
          : Value(cameraId),
      mountId: mountId == null && nullToAbsent
          ? const Value.absent()
          : Value(mountId),
      focuserId: focuserId == null && nullToAbsent
          ? const Value.absent()
          : Value(focuserId),
      filterWheelId: filterWheelId == null && nullToAbsent
          ? const Value.absent()
          : Value(filterWheelId),
      guiderId: guiderId == null && nullToAbsent
          ? const Value.absent()
          : Value(guiderId),
      rotatorId: rotatorId == null && nullToAbsent
          ? const Value.absent()
          : Value(rotatorId),
      domeId:
          domeId == null && nullToAbsent ? const Value.absent() : Value(domeId),
      weatherId: weatherId == null && nullToAbsent
          ? const Value.absent()
          : Value(weatherId),
      coverCalibratorId: coverCalibratorId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverCalibratorId),
      focalLength: Value(focalLength),
      aperture: Value(aperture),
      focalRatio: focalRatio == null && nullToAbsent
          ? const Value.absent()
          : Value(focalRatio),
      defaultGain: defaultGain == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultGain),
      defaultOffset: defaultOffset == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultOffset),
      defaultBinX: Value(defaultBinX),
      defaultBinY: Value(defaultBinY),
      defaultCoolingTemp: defaultCoolingTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(defaultCoolingTemp),
      filterNames: filterNames == null && nullToAbsent
          ? const Value.absent()
          : Value(filterNames),
      filterFocusOffsets: filterFocusOffsets == null && nullToAbsent
          ? const Value.absent()
          : Value(filterFocusOffsets),
      meridianFlipOverrides: meridianFlipOverrides == null && nullToAbsent
          ? const Value.absent()
          : Value(meridianFlipOverrides),
      cameraName: cameraName == null && nullToAbsent
          ? const Value.absent()
          : Value(cameraName),
      mountName: mountName == null && nullToAbsent
          ? const Value.absent()
          : Value(mountName),
      focuserName: focuserName == null && nullToAbsent
          ? const Value.absent()
          : Value(focuserName),
      filterWheelName: filterWheelName == null && nullToAbsent
          ? const Value.absent()
          : Value(filterWheelName),
      guiderName: guiderName == null && nullToAbsent
          ? const Value.absent()
          : Value(guiderName),
      rotatorName: rotatorName == null && nullToAbsent
          ? const Value.absent()
          : Value(rotatorName),
      telescopeName: telescopeName == null && nullToAbsent
          ? const Value.absent()
          : Value(telescopeName),
      telescopeFocalLength: telescopeFocalLength == null && nullToAbsent
          ? const Value.absent()
          : Value(telescopeFocalLength),
      telescopeAperture: telescopeAperture == null && nullToAbsent
          ? const Value.absent()
          : Value(telescopeAperture),
      profileIcon: profileIcon == null && nullToAbsent
          ? const Value.absent()
          : Value(profileIcon),
      profileColor: profileColor == null && nullToAbsent
          ? const Value.absent()
          : Value(profileColor),
      sortOrder: Value(sortOrder),
      isDefault: Value(isDefault),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isActive: Value(isActive),
    );
  }

  factory EquipmentProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EquipmentProfile(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      cameraId: serializer.fromJson<String?>(json['cameraId']),
      mountId: serializer.fromJson<String?>(json['mountId']),
      focuserId: serializer.fromJson<String?>(json['focuserId']),
      filterWheelId: serializer.fromJson<String?>(json['filterWheelId']),
      guiderId: serializer.fromJson<String?>(json['guiderId']),
      rotatorId: serializer.fromJson<String?>(json['rotatorId']),
      domeId: serializer.fromJson<String?>(json['domeId']),
      weatherId: serializer.fromJson<String?>(json['weatherId']),
      coverCalibratorId:
          serializer.fromJson<String?>(json['coverCalibratorId']),
      focalLength: serializer.fromJson<double>(json['focalLength']),
      aperture: serializer.fromJson<double>(json['aperture']),
      focalRatio: serializer.fromJson<double?>(json['focalRatio']),
      defaultGain: serializer.fromJson<int?>(json['defaultGain']),
      defaultOffset: serializer.fromJson<int?>(json['defaultOffset']),
      defaultBinX: serializer.fromJson<int>(json['defaultBinX']),
      defaultBinY: serializer.fromJson<int>(json['defaultBinY']),
      defaultCoolingTemp:
          serializer.fromJson<double?>(json['defaultCoolingTemp']),
      filterNames: serializer.fromJson<String?>(json['filterNames']),
      filterFocusOffsets:
          serializer.fromJson<String?>(json['filterFocusOffsets']),
      meridianFlipOverrides:
          serializer.fromJson<String?>(json['meridianFlipOverrides']),
      cameraName: serializer.fromJson<String?>(json['cameraName']),
      mountName: serializer.fromJson<String?>(json['mountName']),
      focuserName: serializer.fromJson<String?>(json['focuserName']),
      filterWheelName: serializer.fromJson<String?>(json['filterWheelName']),
      guiderName: serializer.fromJson<String?>(json['guiderName']),
      rotatorName: serializer.fromJson<String?>(json['rotatorName']),
      telescopeName: serializer.fromJson<String?>(json['telescopeName']),
      telescopeFocalLength:
          serializer.fromJson<double?>(json['telescopeFocalLength']),
      telescopeAperture:
          serializer.fromJson<double?>(json['telescopeAperture']),
      profileIcon: serializer.fromJson<String?>(json['profileIcon']),
      profileColor: serializer.fromJson<int?>(json['profileColor']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'cameraId': serializer.toJson<String?>(cameraId),
      'mountId': serializer.toJson<String?>(mountId),
      'focuserId': serializer.toJson<String?>(focuserId),
      'filterWheelId': serializer.toJson<String?>(filterWheelId),
      'guiderId': serializer.toJson<String?>(guiderId),
      'rotatorId': serializer.toJson<String?>(rotatorId),
      'domeId': serializer.toJson<String?>(domeId),
      'weatherId': serializer.toJson<String?>(weatherId),
      'coverCalibratorId': serializer.toJson<String?>(coverCalibratorId),
      'focalLength': serializer.toJson<double>(focalLength),
      'aperture': serializer.toJson<double>(aperture),
      'focalRatio': serializer.toJson<double?>(focalRatio),
      'defaultGain': serializer.toJson<int?>(defaultGain),
      'defaultOffset': serializer.toJson<int?>(defaultOffset),
      'defaultBinX': serializer.toJson<int>(defaultBinX),
      'defaultBinY': serializer.toJson<int>(defaultBinY),
      'defaultCoolingTemp': serializer.toJson<double?>(defaultCoolingTemp),
      'filterNames': serializer.toJson<String?>(filterNames),
      'filterFocusOffsets': serializer.toJson<String?>(filterFocusOffsets),
      'meridianFlipOverrides':
          serializer.toJson<String?>(meridianFlipOverrides),
      'cameraName': serializer.toJson<String?>(cameraName),
      'mountName': serializer.toJson<String?>(mountName),
      'focuserName': serializer.toJson<String?>(focuserName),
      'filterWheelName': serializer.toJson<String?>(filterWheelName),
      'guiderName': serializer.toJson<String?>(guiderName),
      'rotatorName': serializer.toJson<String?>(rotatorName),
      'telescopeName': serializer.toJson<String?>(telescopeName),
      'telescopeFocalLength': serializer.toJson<double?>(telescopeFocalLength),
      'telescopeAperture': serializer.toJson<double?>(telescopeAperture),
      'profileIcon': serializer.toJson<String?>(profileIcon),
      'profileColor': serializer.toJson<int?>(profileColor),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isDefault': serializer.toJson<bool>(isDefault),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  EquipmentProfile copyWith(
          {int? id,
          String? name,
          Value<String?> description = const Value.absent(),
          Value<String?> cameraId = const Value.absent(),
          Value<String?> mountId = const Value.absent(),
          Value<String?> focuserId = const Value.absent(),
          Value<String?> filterWheelId = const Value.absent(),
          Value<String?> guiderId = const Value.absent(),
          Value<String?> rotatorId = const Value.absent(),
          Value<String?> domeId = const Value.absent(),
          Value<String?> weatherId = const Value.absent(),
          Value<String?> coverCalibratorId = const Value.absent(),
          double? focalLength,
          double? aperture,
          Value<double?> focalRatio = const Value.absent(),
          Value<int?> defaultGain = const Value.absent(),
          Value<int?> defaultOffset = const Value.absent(),
          int? defaultBinX,
          int? defaultBinY,
          Value<double?> defaultCoolingTemp = const Value.absent(),
          Value<String?> filterNames = const Value.absent(),
          Value<String?> filterFocusOffsets = const Value.absent(),
          Value<String?> meridianFlipOverrides = const Value.absent(),
          Value<String?> cameraName = const Value.absent(),
          Value<String?> mountName = const Value.absent(),
          Value<String?> focuserName = const Value.absent(),
          Value<String?> filterWheelName = const Value.absent(),
          Value<String?> guiderName = const Value.absent(),
          Value<String?> rotatorName = const Value.absent(),
          Value<String?> telescopeName = const Value.absent(),
          Value<double?> telescopeFocalLength = const Value.absent(),
          Value<double?> telescopeAperture = const Value.absent(),
          Value<String?> profileIcon = const Value.absent(),
          Value<int?> profileColor = const Value.absent(),
          int? sortOrder,
          bool? isDefault,
          DateTime? createdAt,
          DateTime? updatedAt,
          bool? isActive}) =>
      EquipmentProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description.present ? description.value : this.description,
        cameraId: cameraId.present ? cameraId.value : this.cameraId,
        mountId: mountId.present ? mountId.value : this.mountId,
        focuserId: focuserId.present ? focuserId.value : this.focuserId,
        filterWheelId:
            filterWheelId.present ? filterWheelId.value : this.filterWheelId,
        guiderId: guiderId.present ? guiderId.value : this.guiderId,
        rotatorId: rotatorId.present ? rotatorId.value : this.rotatorId,
        domeId: domeId.present ? domeId.value : this.domeId,
        weatherId: weatherId.present ? weatherId.value : this.weatherId,
        coverCalibratorId: coverCalibratorId.present
            ? coverCalibratorId.value
            : this.coverCalibratorId,
        focalLength: focalLength ?? this.focalLength,
        aperture: aperture ?? this.aperture,
        focalRatio: focalRatio.present ? focalRatio.value : this.focalRatio,
        defaultGain: defaultGain.present ? defaultGain.value : this.defaultGain,
        defaultOffset:
            defaultOffset.present ? defaultOffset.value : this.defaultOffset,
        defaultBinX: defaultBinX ?? this.defaultBinX,
        defaultBinY: defaultBinY ?? this.defaultBinY,
        defaultCoolingTemp: defaultCoolingTemp.present
            ? defaultCoolingTemp.value
            : this.defaultCoolingTemp,
        filterNames: filterNames.present ? filterNames.value : this.filterNames,
        filterFocusOffsets: filterFocusOffsets.present
            ? filterFocusOffsets.value
            : this.filterFocusOffsets,
        meridianFlipOverrides: meridianFlipOverrides.present
            ? meridianFlipOverrides.value
            : this.meridianFlipOverrides,
        cameraName: cameraName.present ? cameraName.value : this.cameraName,
        mountName: mountName.present ? mountName.value : this.mountName,
        focuserName: focuserName.present ? focuserName.value : this.focuserName,
        filterWheelName: filterWheelName.present
            ? filterWheelName.value
            : this.filterWheelName,
        guiderName: guiderName.present ? guiderName.value : this.guiderName,
        rotatorName: rotatorName.present ? rotatorName.value : this.rotatorName,
        telescopeName:
            telescopeName.present ? telescopeName.value : this.telescopeName,
        telescopeFocalLength: telescopeFocalLength.present
            ? telescopeFocalLength.value
            : this.telescopeFocalLength,
        telescopeAperture: telescopeAperture.present
            ? telescopeAperture.value
            : this.telescopeAperture,
        profileIcon: profileIcon.present ? profileIcon.value : this.profileIcon,
        profileColor:
            profileColor.present ? profileColor.value : this.profileColor,
        sortOrder: sortOrder ?? this.sortOrder,
        isDefault: isDefault ?? this.isDefault,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isActive: isActive ?? this.isActive,
      );
  EquipmentProfile copyWithCompanion(EquipmentProfilesCompanion data) {
    return EquipmentProfile(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      cameraId: data.cameraId.present ? data.cameraId.value : this.cameraId,
      mountId: data.mountId.present ? data.mountId.value : this.mountId,
      focuserId: data.focuserId.present ? data.focuserId.value : this.focuserId,
      filterWheelId: data.filterWheelId.present
          ? data.filterWheelId.value
          : this.filterWheelId,
      guiderId: data.guiderId.present ? data.guiderId.value : this.guiderId,
      rotatorId: data.rotatorId.present ? data.rotatorId.value : this.rotatorId,
      domeId: data.domeId.present ? data.domeId.value : this.domeId,
      weatherId: data.weatherId.present ? data.weatherId.value : this.weatherId,
      coverCalibratorId: data.coverCalibratorId.present
          ? data.coverCalibratorId.value
          : this.coverCalibratorId,
      focalLength:
          data.focalLength.present ? data.focalLength.value : this.focalLength,
      aperture: data.aperture.present ? data.aperture.value : this.aperture,
      focalRatio:
          data.focalRatio.present ? data.focalRatio.value : this.focalRatio,
      defaultGain:
          data.defaultGain.present ? data.defaultGain.value : this.defaultGain,
      defaultOffset: data.defaultOffset.present
          ? data.defaultOffset.value
          : this.defaultOffset,
      defaultBinX:
          data.defaultBinX.present ? data.defaultBinX.value : this.defaultBinX,
      defaultBinY:
          data.defaultBinY.present ? data.defaultBinY.value : this.defaultBinY,
      defaultCoolingTemp: data.defaultCoolingTemp.present
          ? data.defaultCoolingTemp.value
          : this.defaultCoolingTemp,
      filterNames:
          data.filterNames.present ? data.filterNames.value : this.filterNames,
      filterFocusOffsets: data.filterFocusOffsets.present
          ? data.filterFocusOffsets.value
          : this.filterFocusOffsets,
      meridianFlipOverrides: data.meridianFlipOverrides.present
          ? data.meridianFlipOverrides.value
          : this.meridianFlipOverrides,
      cameraName:
          data.cameraName.present ? data.cameraName.value : this.cameraName,
      mountName: data.mountName.present ? data.mountName.value : this.mountName,
      focuserName:
          data.focuserName.present ? data.focuserName.value : this.focuserName,
      filterWheelName: data.filterWheelName.present
          ? data.filterWheelName.value
          : this.filterWheelName,
      guiderName:
          data.guiderName.present ? data.guiderName.value : this.guiderName,
      rotatorName:
          data.rotatorName.present ? data.rotatorName.value : this.rotatorName,
      telescopeName: data.telescopeName.present
          ? data.telescopeName.value
          : this.telescopeName,
      telescopeFocalLength: data.telescopeFocalLength.present
          ? data.telescopeFocalLength.value
          : this.telescopeFocalLength,
      telescopeAperture: data.telescopeAperture.present
          ? data.telescopeAperture.value
          : this.telescopeAperture,
      profileIcon:
          data.profileIcon.present ? data.profileIcon.value : this.profileIcon,
      profileColor: data.profileColor.present
          ? data.profileColor.value
          : this.profileColor,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EquipmentProfile(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('cameraId: $cameraId, ')
          ..write('mountId: $mountId, ')
          ..write('focuserId: $focuserId, ')
          ..write('filterWheelId: $filterWheelId, ')
          ..write('guiderId: $guiderId, ')
          ..write('rotatorId: $rotatorId, ')
          ..write('domeId: $domeId, ')
          ..write('weatherId: $weatherId, ')
          ..write('coverCalibratorId: $coverCalibratorId, ')
          ..write('focalLength: $focalLength, ')
          ..write('aperture: $aperture, ')
          ..write('focalRatio: $focalRatio, ')
          ..write('defaultGain: $defaultGain, ')
          ..write('defaultOffset: $defaultOffset, ')
          ..write('defaultBinX: $defaultBinX, ')
          ..write('defaultBinY: $defaultBinY, ')
          ..write('defaultCoolingTemp: $defaultCoolingTemp, ')
          ..write('filterNames: $filterNames, ')
          ..write('filterFocusOffsets: $filterFocusOffsets, ')
          ..write('meridianFlipOverrides: $meridianFlipOverrides, ')
          ..write('cameraName: $cameraName, ')
          ..write('mountName: $mountName, ')
          ..write('focuserName: $focuserName, ')
          ..write('filterWheelName: $filterWheelName, ')
          ..write('guiderName: $guiderName, ')
          ..write('rotatorName: $rotatorName, ')
          ..write('telescopeName: $telescopeName, ')
          ..write('telescopeFocalLength: $telescopeFocalLength, ')
          ..write('telescopeAperture: $telescopeAperture, ')
          ..write('profileIcon: $profileIcon, ')
          ..write('profileColor: $profileColor, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
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
        isActive
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EquipmentProfile &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.cameraId == this.cameraId &&
          other.mountId == this.mountId &&
          other.focuserId == this.focuserId &&
          other.filterWheelId == this.filterWheelId &&
          other.guiderId == this.guiderId &&
          other.rotatorId == this.rotatorId &&
          other.domeId == this.domeId &&
          other.weatherId == this.weatherId &&
          other.coverCalibratorId == this.coverCalibratorId &&
          other.focalLength == this.focalLength &&
          other.aperture == this.aperture &&
          other.focalRatio == this.focalRatio &&
          other.defaultGain == this.defaultGain &&
          other.defaultOffset == this.defaultOffset &&
          other.defaultBinX == this.defaultBinX &&
          other.defaultBinY == this.defaultBinY &&
          other.defaultCoolingTemp == this.defaultCoolingTemp &&
          other.filterNames == this.filterNames &&
          other.filterFocusOffsets == this.filterFocusOffsets &&
          other.meridianFlipOverrides == this.meridianFlipOverrides &&
          other.cameraName == this.cameraName &&
          other.mountName == this.mountName &&
          other.focuserName == this.focuserName &&
          other.filterWheelName == this.filterWheelName &&
          other.guiderName == this.guiderName &&
          other.rotatorName == this.rotatorName &&
          other.telescopeName == this.telescopeName &&
          other.telescopeFocalLength == this.telescopeFocalLength &&
          other.telescopeAperture == this.telescopeAperture &&
          other.profileIcon == this.profileIcon &&
          other.profileColor == this.profileColor &&
          other.sortOrder == this.sortOrder &&
          other.isDefault == this.isDefault &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isActive == this.isActive);
}

class EquipmentProfilesCompanion extends UpdateCompanion<EquipmentProfile> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> cameraId;
  final Value<String?> mountId;
  final Value<String?> focuserId;
  final Value<String?> filterWheelId;
  final Value<String?> guiderId;
  final Value<String?> rotatorId;
  final Value<String?> domeId;
  final Value<String?> weatherId;
  final Value<String?> coverCalibratorId;
  final Value<double> focalLength;
  final Value<double> aperture;
  final Value<double?> focalRatio;
  final Value<int?> defaultGain;
  final Value<int?> defaultOffset;
  final Value<int> defaultBinX;
  final Value<int> defaultBinY;
  final Value<double?> defaultCoolingTemp;
  final Value<String?> filterNames;
  final Value<String?> filterFocusOffsets;
  final Value<String?> meridianFlipOverrides;
  final Value<String?> cameraName;
  final Value<String?> mountName;
  final Value<String?> focuserName;
  final Value<String?> filterWheelName;
  final Value<String?> guiderName;
  final Value<String?> rotatorName;
  final Value<String?> telescopeName;
  final Value<double?> telescopeFocalLength;
  final Value<double?> telescopeAperture;
  final Value<String?> profileIcon;
  final Value<int?> profileColor;
  final Value<int> sortOrder;
  final Value<bool> isDefault;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isActive;
  const EquipmentProfilesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.cameraId = const Value.absent(),
    this.mountId = const Value.absent(),
    this.focuserId = const Value.absent(),
    this.filterWheelId = const Value.absent(),
    this.guiderId = const Value.absent(),
    this.rotatorId = const Value.absent(),
    this.domeId = const Value.absent(),
    this.weatherId = const Value.absent(),
    this.coverCalibratorId = const Value.absent(),
    this.focalLength = const Value.absent(),
    this.aperture = const Value.absent(),
    this.focalRatio = const Value.absent(),
    this.defaultGain = const Value.absent(),
    this.defaultOffset = const Value.absent(),
    this.defaultBinX = const Value.absent(),
    this.defaultBinY = const Value.absent(),
    this.defaultCoolingTemp = const Value.absent(),
    this.filterNames = const Value.absent(),
    this.filterFocusOffsets = const Value.absent(),
    this.meridianFlipOverrides = const Value.absent(),
    this.cameraName = const Value.absent(),
    this.mountName = const Value.absent(),
    this.focuserName = const Value.absent(),
    this.filterWheelName = const Value.absent(),
    this.guiderName = const Value.absent(),
    this.rotatorName = const Value.absent(),
    this.telescopeName = const Value.absent(),
    this.telescopeFocalLength = const Value.absent(),
    this.telescopeAperture = const Value.absent(),
    this.profileIcon = const Value.absent(),
    this.profileColor = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isActive = const Value.absent(),
  });
  EquipmentProfilesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.cameraId = const Value.absent(),
    this.mountId = const Value.absent(),
    this.focuserId = const Value.absent(),
    this.filterWheelId = const Value.absent(),
    this.guiderId = const Value.absent(),
    this.rotatorId = const Value.absent(),
    this.domeId = const Value.absent(),
    this.weatherId = const Value.absent(),
    this.coverCalibratorId = const Value.absent(),
    this.focalLength = const Value.absent(),
    this.aperture = const Value.absent(),
    this.focalRatio = const Value.absent(),
    this.defaultGain = const Value.absent(),
    this.defaultOffset = const Value.absent(),
    this.defaultBinX = const Value.absent(),
    this.defaultBinY = const Value.absent(),
    this.defaultCoolingTemp = const Value.absent(),
    this.filterNames = const Value.absent(),
    this.filterFocusOffsets = const Value.absent(),
    this.meridianFlipOverrides = const Value.absent(),
    this.cameraName = const Value.absent(),
    this.mountName = const Value.absent(),
    this.focuserName = const Value.absent(),
    this.filterWheelName = const Value.absent(),
    this.guiderName = const Value.absent(),
    this.rotatorName = const Value.absent(),
    this.telescopeName = const Value.absent(),
    this.telescopeFocalLength = const Value.absent(),
    this.telescopeAperture = const Value.absent(),
    this.profileIcon = const Value.absent(),
    this.profileColor = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isActive = const Value.absent(),
  }) : name = Value(name);
  static Insertable<EquipmentProfile> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? cameraId,
    Expression<String>? mountId,
    Expression<String>? focuserId,
    Expression<String>? filterWheelId,
    Expression<String>? guiderId,
    Expression<String>? rotatorId,
    Expression<String>? domeId,
    Expression<String>? weatherId,
    Expression<String>? coverCalibratorId,
    Expression<double>? focalLength,
    Expression<double>? aperture,
    Expression<double>? focalRatio,
    Expression<int>? defaultGain,
    Expression<int>? defaultOffset,
    Expression<int>? defaultBinX,
    Expression<int>? defaultBinY,
    Expression<double>? defaultCoolingTemp,
    Expression<String>? filterNames,
    Expression<String>? filterFocusOffsets,
    Expression<String>? meridianFlipOverrides,
    Expression<String>? cameraName,
    Expression<String>? mountName,
    Expression<String>? focuserName,
    Expression<String>? filterWheelName,
    Expression<String>? guiderName,
    Expression<String>? rotatorName,
    Expression<String>? telescopeName,
    Expression<double>? telescopeFocalLength,
    Expression<double>? telescopeAperture,
    Expression<String>? profileIcon,
    Expression<int>? profileColor,
    Expression<int>? sortOrder,
    Expression<bool>? isDefault,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isActive,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (cameraId != null) 'camera_id': cameraId,
      if (mountId != null) 'mount_id': mountId,
      if (focuserId != null) 'focuser_id': focuserId,
      if (filterWheelId != null) 'filter_wheel_id': filterWheelId,
      if (guiderId != null) 'guider_id': guiderId,
      if (rotatorId != null) 'rotator_id': rotatorId,
      if (domeId != null) 'dome_id': domeId,
      if (weatherId != null) 'weather_id': weatherId,
      if (coverCalibratorId != null) 'cover_calibrator_id': coverCalibratorId,
      if (focalLength != null) 'focal_length': focalLength,
      if (aperture != null) 'aperture': aperture,
      if (focalRatio != null) 'focal_ratio': focalRatio,
      if (defaultGain != null) 'default_gain': defaultGain,
      if (defaultOffset != null) 'default_offset': defaultOffset,
      if (defaultBinX != null) 'default_bin_x': defaultBinX,
      if (defaultBinY != null) 'default_bin_y': defaultBinY,
      if (defaultCoolingTemp != null)
        'default_cooling_temp': defaultCoolingTemp,
      if (filterNames != null) 'filter_names': filterNames,
      if (filterFocusOffsets != null)
        'filter_focus_offsets': filterFocusOffsets,
      if (meridianFlipOverrides != null)
        'meridian_flip_overrides': meridianFlipOverrides,
      if (cameraName != null) 'camera_name': cameraName,
      if (mountName != null) 'mount_name': mountName,
      if (focuserName != null) 'focuser_name': focuserName,
      if (filterWheelName != null) 'filter_wheel_name': filterWheelName,
      if (guiderName != null) 'guider_name': guiderName,
      if (rotatorName != null) 'rotator_name': rotatorName,
      if (telescopeName != null) 'telescope_name': telescopeName,
      if (telescopeFocalLength != null)
        'telescope_focal_length': telescopeFocalLength,
      if (telescopeAperture != null) 'telescope_aperture': telescopeAperture,
      if (profileIcon != null) 'profile_icon': profileIcon,
      if (profileColor != null) 'profile_color': profileColor,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isDefault != null) 'is_default': isDefault,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isActive != null) 'is_active': isActive,
    });
  }

  EquipmentProfilesCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String?>? description,
      Value<String?>? cameraId,
      Value<String?>? mountId,
      Value<String?>? focuserId,
      Value<String?>? filterWheelId,
      Value<String?>? guiderId,
      Value<String?>? rotatorId,
      Value<String?>? domeId,
      Value<String?>? weatherId,
      Value<String?>? coverCalibratorId,
      Value<double>? focalLength,
      Value<double>? aperture,
      Value<double?>? focalRatio,
      Value<int?>? defaultGain,
      Value<int?>? defaultOffset,
      Value<int>? defaultBinX,
      Value<int>? defaultBinY,
      Value<double?>? defaultCoolingTemp,
      Value<String?>? filterNames,
      Value<String?>? filterFocusOffsets,
      Value<String?>? meridianFlipOverrides,
      Value<String?>? cameraName,
      Value<String?>? mountName,
      Value<String?>? focuserName,
      Value<String?>? filterWheelName,
      Value<String?>? guiderName,
      Value<String?>? rotatorName,
      Value<String?>? telescopeName,
      Value<double?>? telescopeFocalLength,
      Value<double?>? telescopeAperture,
      Value<String?>? profileIcon,
      Value<int?>? profileColor,
      Value<int>? sortOrder,
      Value<bool>? isDefault,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<bool>? isActive}) {
    return EquipmentProfilesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      cameraId: cameraId ?? this.cameraId,
      mountId: mountId ?? this.mountId,
      focuserId: focuserId ?? this.focuserId,
      filterWheelId: filterWheelId ?? this.filterWheelId,
      guiderId: guiderId ?? this.guiderId,
      rotatorId: rotatorId ?? this.rotatorId,
      domeId: domeId ?? this.domeId,
      weatherId: weatherId ?? this.weatherId,
      coverCalibratorId: coverCalibratorId ?? this.coverCalibratorId,
      focalLength: focalLength ?? this.focalLength,
      aperture: aperture ?? this.aperture,
      focalRatio: focalRatio ?? this.focalRatio,
      defaultGain: defaultGain ?? this.defaultGain,
      defaultOffset: defaultOffset ?? this.defaultOffset,
      defaultBinX: defaultBinX ?? this.defaultBinX,
      defaultBinY: defaultBinY ?? this.defaultBinY,
      defaultCoolingTemp: defaultCoolingTemp ?? this.defaultCoolingTemp,
      filterNames: filterNames ?? this.filterNames,
      filterFocusOffsets: filterFocusOffsets ?? this.filterFocusOffsets,
      meridianFlipOverrides:
          meridianFlipOverrides ?? this.meridianFlipOverrides,
      cameraName: cameraName ?? this.cameraName,
      mountName: mountName ?? this.mountName,
      focuserName: focuserName ?? this.focuserName,
      filterWheelName: filterWheelName ?? this.filterWheelName,
      guiderName: guiderName ?? this.guiderName,
      rotatorName: rotatorName ?? this.rotatorName,
      telescopeName: telescopeName ?? this.telescopeName,
      telescopeFocalLength: telescopeFocalLength ?? this.telescopeFocalLength,
      telescopeAperture: telescopeAperture ?? this.telescopeAperture,
      profileIcon: profileIcon ?? this.profileIcon,
      profileColor: profileColor ?? this.profileColor,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (cameraId.present) {
      map['camera_id'] = Variable<String>(cameraId.value);
    }
    if (mountId.present) {
      map['mount_id'] = Variable<String>(mountId.value);
    }
    if (focuserId.present) {
      map['focuser_id'] = Variable<String>(focuserId.value);
    }
    if (filterWheelId.present) {
      map['filter_wheel_id'] = Variable<String>(filterWheelId.value);
    }
    if (guiderId.present) {
      map['guider_id'] = Variable<String>(guiderId.value);
    }
    if (rotatorId.present) {
      map['rotator_id'] = Variable<String>(rotatorId.value);
    }
    if (domeId.present) {
      map['dome_id'] = Variable<String>(domeId.value);
    }
    if (weatherId.present) {
      map['weather_id'] = Variable<String>(weatherId.value);
    }
    if (coverCalibratorId.present) {
      map['cover_calibrator_id'] = Variable<String>(coverCalibratorId.value);
    }
    if (focalLength.present) {
      map['focal_length'] = Variable<double>(focalLength.value);
    }
    if (aperture.present) {
      map['aperture'] = Variable<double>(aperture.value);
    }
    if (focalRatio.present) {
      map['focal_ratio'] = Variable<double>(focalRatio.value);
    }
    if (defaultGain.present) {
      map['default_gain'] = Variable<int>(defaultGain.value);
    }
    if (defaultOffset.present) {
      map['default_offset'] = Variable<int>(defaultOffset.value);
    }
    if (defaultBinX.present) {
      map['default_bin_x'] = Variable<int>(defaultBinX.value);
    }
    if (defaultBinY.present) {
      map['default_bin_y'] = Variable<int>(defaultBinY.value);
    }
    if (defaultCoolingTemp.present) {
      map['default_cooling_temp'] = Variable<double>(defaultCoolingTemp.value);
    }
    if (filterNames.present) {
      map['filter_names'] = Variable<String>(filterNames.value);
    }
    if (filterFocusOffsets.present) {
      map['filter_focus_offsets'] = Variable<String>(filterFocusOffsets.value);
    }
    if (meridianFlipOverrides.present) {
      map['meridian_flip_overrides'] =
          Variable<String>(meridianFlipOverrides.value);
    }
    if (cameraName.present) {
      map['camera_name'] = Variable<String>(cameraName.value);
    }
    if (mountName.present) {
      map['mount_name'] = Variable<String>(mountName.value);
    }
    if (focuserName.present) {
      map['focuser_name'] = Variable<String>(focuserName.value);
    }
    if (filterWheelName.present) {
      map['filter_wheel_name'] = Variable<String>(filterWheelName.value);
    }
    if (guiderName.present) {
      map['guider_name'] = Variable<String>(guiderName.value);
    }
    if (rotatorName.present) {
      map['rotator_name'] = Variable<String>(rotatorName.value);
    }
    if (telescopeName.present) {
      map['telescope_name'] = Variable<String>(telescopeName.value);
    }
    if (telescopeFocalLength.present) {
      map['telescope_focal_length'] =
          Variable<double>(telescopeFocalLength.value);
    }
    if (telescopeAperture.present) {
      map['telescope_aperture'] = Variable<double>(telescopeAperture.value);
    }
    if (profileIcon.present) {
      map['profile_icon'] = Variable<String>(profileIcon.value);
    }
    if (profileColor.present) {
      map['profile_color'] = Variable<int>(profileColor.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EquipmentProfilesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('cameraId: $cameraId, ')
          ..write('mountId: $mountId, ')
          ..write('focuserId: $focuserId, ')
          ..write('filterWheelId: $filterWheelId, ')
          ..write('guiderId: $guiderId, ')
          ..write('rotatorId: $rotatorId, ')
          ..write('domeId: $domeId, ')
          ..write('weatherId: $weatherId, ')
          ..write('coverCalibratorId: $coverCalibratorId, ')
          ..write('focalLength: $focalLength, ')
          ..write('aperture: $aperture, ')
          ..write('focalRatio: $focalRatio, ')
          ..write('defaultGain: $defaultGain, ')
          ..write('defaultOffset: $defaultOffset, ')
          ..write('defaultBinX: $defaultBinX, ')
          ..write('defaultBinY: $defaultBinY, ')
          ..write('defaultCoolingTemp: $defaultCoolingTemp, ')
          ..write('filterNames: $filterNames, ')
          ..write('filterFocusOffsets: $filterFocusOffsets, ')
          ..write('meridianFlipOverrides: $meridianFlipOverrides, ')
          ..write('cameraName: $cameraName, ')
          ..write('mountName: $mountName, ')
          ..write('focuserName: $focuserName, ')
          ..write('filterWheelName: $filterWheelName, ')
          ..write('guiderName: $guiderName, ')
          ..write('rotatorName: $rotatorName, ')
          ..write('telescopeName: $telescopeName, ')
          ..write('telescopeFocalLength: $telescopeFocalLength, ')
          ..write('telescopeAperture: $telescopeAperture, ')
          ..write('profileIcon: $profileIcon, ')
          ..write('profileColor: $profileColor, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isDefault: $isDefault, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }
}

class $TargetsTable extends Targets with TableInfo<$TargetsTable, Target> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TargetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _catalogIdMeta =
      const VerificationMeta('catalogId');
  @override
  late final GeneratedColumn<String> catalogId = GeneratedColumn<String>(
      'catalog_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _objectTypeMeta =
      const VerificationMeta('objectType');
  @override
  late final GeneratedColumn<String> objectType = GeneratedColumn<String>(
      'object_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _raMeta = const VerificationMeta('ra');
  @override
  late final GeneratedColumn<double> ra = GeneratedColumn<double>(
      'ra', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _decMeta = const VerificationMeta('dec');
  @override
  late final GeneratedColumn<double> dec = GeneratedColumn<double>(
      'dec', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _positionAngleMeta =
      const VerificationMeta('positionAngle');
  @override
  late final GeneratedColumn<double> positionAngle = GeneratedColumn<double>(
      'position_angle', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _magnitudeMeta =
      const VerificationMeta('magnitude');
  @override
  late final GeneratedColumn<double> magnitude = GeneratedColumn<double>(
      'magnitude', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _constellationMeta =
      const VerificationMeta('constellation');
  @override
  late final GeneratedColumn<String> constellation = GeneratedColumn<String>(
      'constellation', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sizeArcminMeta =
      const VerificationMeta('sizeArcmin');
  @override
  late final GeneratedColumn<double> sizeArcmin = GeneratedColumn<double>(
      'size_arcmin', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _minAltitudeMeta =
      const VerificationMeta('minAltitude');
  @override
  late final GeneratedColumn<double> minAltitude = GeneratedColumn<double>(
      'min_altitude', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(30.0));
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<int> priority = GeneratedColumn<int>(
      'priority', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(5));
  static const VerificationMeta _totalPlannedSubsMeta =
      const VerificationMeta('totalPlannedSubs');
  @override
  late final GeneratedColumn<int> totalPlannedSubs = GeneratedColumn<int>(
      'total_planned_subs', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _capturedSubsMeta =
      const VerificationMeta('capturedSubs');
  @override
  late final GeneratedColumn<int> capturedSubs = GeneratedColumn<int>(
      'captured_subs', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalIntegrationSecsMeta =
      const VerificationMeta('totalIntegrationSecs');
  @override
  late final GeneratedColumn<double> totalIntegrationSecs =
      GeneratedColumn<double>('total_integration_secs', aliasedName, false,
          type: DriftSqlType.double,
          requiredDuringInsert: false,
          defaultValue: const Constant(0.0));
  static const VerificationMeta _filterProgressMeta =
      const VerificationMeta('filterProgress');
  @override
  late final GeneratedColumn<String> filterProgress = GeneratedColumn<String>(
      'filter_progress', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _isFavoriteMeta =
      const VerificationMeta('isFavorite');
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
      'is_favorite', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_favorite" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        catalogId,
        objectType,
        ra,
        dec,
        positionAngle,
        magnitude,
        constellation,
        sizeArcmin,
        minAltitude,
        priority,
        totalPlannedSubs,
        capturedSubs,
        totalIntegrationSecs,
        filterProgress,
        notes,
        createdAt,
        updatedAt,
        isFavorite
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'targets';
  @override
  VerificationContext validateIntegrity(Insertable<Target> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('catalog_id')) {
      context.handle(_catalogIdMeta,
          catalogId.isAcceptableOrUnknown(data['catalog_id']!, _catalogIdMeta));
    }
    if (data.containsKey('object_type')) {
      context.handle(
          _objectTypeMeta,
          objectType.isAcceptableOrUnknown(
              data['object_type']!, _objectTypeMeta));
    }
    if (data.containsKey('ra')) {
      context.handle(_raMeta, ra.isAcceptableOrUnknown(data['ra']!, _raMeta));
    } else if (isInserting) {
      context.missing(_raMeta);
    }
    if (data.containsKey('dec')) {
      context.handle(
          _decMeta, dec.isAcceptableOrUnknown(data['dec']!, _decMeta));
    } else if (isInserting) {
      context.missing(_decMeta);
    }
    if (data.containsKey('position_angle')) {
      context.handle(
          _positionAngleMeta,
          positionAngle.isAcceptableOrUnknown(
              data['position_angle']!, _positionAngleMeta));
    }
    if (data.containsKey('magnitude')) {
      context.handle(_magnitudeMeta,
          magnitude.isAcceptableOrUnknown(data['magnitude']!, _magnitudeMeta));
    }
    if (data.containsKey('constellation')) {
      context.handle(
          _constellationMeta,
          constellation.isAcceptableOrUnknown(
              data['constellation']!, _constellationMeta));
    }
    if (data.containsKey('size_arcmin')) {
      context.handle(
          _sizeArcminMeta,
          sizeArcmin.isAcceptableOrUnknown(
              data['size_arcmin']!, _sizeArcminMeta));
    }
    if (data.containsKey('min_altitude')) {
      context.handle(
          _minAltitudeMeta,
          minAltitude.isAcceptableOrUnknown(
              data['min_altitude']!, _minAltitudeMeta));
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    if (data.containsKey('total_planned_subs')) {
      context.handle(
          _totalPlannedSubsMeta,
          totalPlannedSubs.isAcceptableOrUnknown(
              data['total_planned_subs']!, _totalPlannedSubsMeta));
    }
    if (data.containsKey('captured_subs')) {
      context.handle(
          _capturedSubsMeta,
          capturedSubs.isAcceptableOrUnknown(
              data['captured_subs']!, _capturedSubsMeta));
    }
    if (data.containsKey('total_integration_secs')) {
      context.handle(
          _totalIntegrationSecsMeta,
          totalIntegrationSecs.isAcceptableOrUnknown(
              data['total_integration_secs']!, _totalIntegrationSecsMeta));
    }
    if (data.containsKey('filter_progress')) {
      context.handle(
          _filterProgressMeta,
          filterProgress.isAcceptableOrUnknown(
              data['filter_progress']!, _filterProgressMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
          _isFavoriteMeta,
          isFavorite.isAcceptableOrUnknown(
              data['is_favorite']!, _isFavoriteMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Target map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Target(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      catalogId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}catalog_id']),
      objectType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}object_type']),
      ra: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}ra'])!,
      dec: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}dec'])!,
      positionAngle: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}position_angle']),
      magnitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}magnitude']),
      constellation: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}constellation']),
      sizeArcmin: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}size_arcmin']),
      minAltitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}min_altitude'])!,
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}priority'])!,
      totalPlannedSubs: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}total_planned_subs'])!,
      capturedSubs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}captured_subs'])!,
      totalIntegrationSecs: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}total_integration_secs'])!,
      filterProgress: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filter_progress']),
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      isFavorite: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_favorite'])!,
    );
  }

  @override
  $TargetsTable createAlias(String alias) {
    return $TargetsTable(attachedDatabase, alias);
  }
}

class Target extends DataClass implements Insertable<Target> {
  final int id;
  final String name;
  final String? catalogId;
  final String? objectType;
  final double ra;
  final double dec;
  final double? positionAngle;
  final double? magnitude;
  final String? constellation;
  final double? sizeArcmin;
  final double minAltitude;
  final int priority;
  final int totalPlannedSubs;
  final int capturedSubs;
  final double totalIntegrationSecs;
  final String? filterProgress;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  const Target(
      {required this.id,
      required this.name,
      this.catalogId,
      this.objectType,
      required this.ra,
      required this.dec,
      this.positionAngle,
      this.magnitude,
      this.constellation,
      this.sizeArcmin,
      required this.minAltitude,
      required this.priority,
      required this.totalPlannedSubs,
      required this.capturedSubs,
      required this.totalIntegrationSecs,
      this.filterProgress,
      this.notes,
      required this.createdAt,
      required this.updatedAt,
      required this.isFavorite});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || catalogId != null) {
      map['catalog_id'] = Variable<String>(catalogId);
    }
    if (!nullToAbsent || objectType != null) {
      map['object_type'] = Variable<String>(objectType);
    }
    map['ra'] = Variable<double>(ra);
    map['dec'] = Variable<double>(dec);
    if (!nullToAbsent || positionAngle != null) {
      map['position_angle'] = Variable<double>(positionAngle);
    }
    if (!nullToAbsent || magnitude != null) {
      map['magnitude'] = Variable<double>(magnitude);
    }
    if (!nullToAbsent || constellation != null) {
      map['constellation'] = Variable<String>(constellation);
    }
    if (!nullToAbsent || sizeArcmin != null) {
      map['size_arcmin'] = Variable<double>(sizeArcmin);
    }
    map['min_altitude'] = Variable<double>(minAltitude);
    map['priority'] = Variable<int>(priority);
    map['total_planned_subs'] = Variable<int>(totalPlannedSubs);
    map['captured_subs'] = Variable<int>(capturedSubs);
    map['total_integration_secs'] = Variable<double>(totalIntegrationSecs);
    if (!nullToAbsent || filterProgress != null) {
      map['filter_progress'] = Variable<String>(filterProgress);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_favorite'] = Variable<bool>(isFavorite);
    return map;
  }

  TargetsCompanion toCompanion(bool nullToAbsent) {
    return TargetsCompanion(
      id: Value(id),
      name: Value(name),
      catalogId: catalogId == null && nullToAbsent
          ? const Value.absent()
          : Value(catalogId),
      objectType: objectType == null && nullToAbsent
          ? const Value.absent()
          : Value(objectType),
      ra: Value(ra),
      dec: Value(dec),
      positionAngle: positionAngle == null && nullToAbsent
          ? const Value.absent()
          : Value(positionAngle),
      magnitude: magnitude == null && nullToAbsent
          ? const Value.absent()
          : Value(magnitude),
      constellation: constellation == null && nullToAbsent
          ? const Value.absent()
          : Value(constellation),
      sizeArcmin: sizeArcmin == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeArcmin),
      minAltitude: Value(minAltitude),
      priority: Value(priority),
      totalPlannedSubs: Value(totalPlannedSubs),
      capturedSubs: Value(capturedSubs),
      totalIntegrationSecs: Value(totalIntegrationSecs),
      filterProgress: filterProgress == null && nullToAbsent
          ? const Value.absent()
          : Value(filterProgress),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isFavorite: Value(isFavorite),
    );
  }

  factory Target.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Target(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      catalogId: serializer.fromJson<String?>(json['catalogId']),
      objectType: serializer.fromJson<String?>(json['objectType']),
      ra: serializer.fromJson<double>(json['ra']),
      dec: serializer.fromJson<double>(json['dec']),
      positionAngle: serializer.fromJson<double?>(json['positionAngle']),
      magnitude: serializer.fromJson<double?>(json['magnitude']),
      constellation: serializer.fromJson<String?>(json['constellation']),
      sizeArcmin: serializer.fromJson<double?>(json['sizeArcmin']),
      minAltitude: serializer.fromJson<double>(json['minAltitude']),
      priority: serializer.fromJson<int>(json['priority']),
      totalPlannedSubs: serializer.fromJson<int>(json['totalPlannedSubs']),
      capturedSubs: serializer.fromJson<int>(json['capturedSubs']),
      totalIntegrationSecs:
          serializer.fromJson<double>(json['totalIntegrationSecs']),
      filterProgress: serializer.fromJson<String?>(json['filterProgress']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'catalogId': serializer.toJson<String?>(catalogId),
      'objectType': serializer.toJson<String?>(objectType),
      'ra': serializer.toJson<double>(ra),
      'dec': serializer.toJson<double>(dec),
      'positionAngle': serializer.toJson<double?>(positionAngle),
      'magnitude': serializer.toJson<double?>(magnitude),
      'constellation': serializer.toJson<String?>(constellation),
      'sizeArcmin': serializer.toJson<double?>(sizeArcmin),
      'minAltitude': serializer.toJson<double>(minAltitude),
      'priority': serializer.toJson<int>(priority),
      'totalPlannedSubs': serializer.toJson<int>(totalPlannedSubs),
      'capturedSubs': serializer.toJson<int>(capturedSubs),
      'totalIntegrationSecs': serializer.toJson<double>(totalIntegrationSecs),
      'filterProgress': serializer.toJson<String?>(filterProgress),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isFavorite': serializer.toJson<bool>(isFavorite),
    };
  }

  Target copyWith(
          {int? id,
          String? name,
          Value<String?> catalogId = const Value.absent(),
          Value<String?> objectType = const Value.absent(),
          double? ra,
          double? dec,
          Value<double?> positionAngle = const Value.absent(),
          Value<double?> magnitude = const Value.absent(),
          Value<String?> constellation = const Value.absent(),
          Value<double?> sizeArcmin = const Value.absent(),
          double? minAltitude,
          int? priority,
          int? totalPlannedSubs,
          int? capturedSubs,
          double? totalIntegrationSecs,
          Value<String?> filterProgress = const Value.absent(),
          Value<String?> notes = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt,
          bool? isFavorite}) =>
      Target(
        id: id ?? this.id,
        name: name ?? this.name,
        catalogId: catalogId.present ? catalogId.value : this.catalogId,
        objectType: objectType.present ? objectType.value : this.objectType,
        ra: ra ?? this.ra,
        dec: dec ?? this.dec,
        positionAngle:
            positionAngle.present ? positionAngle.value : this.positionAngle,
        magnitude: magnitude.present ? magnitude.value : this.magnitude,
        constellation:
            constellation.present ? constellation.value : this.constellation,
        sizeArcmin: sizeArcmin.present ? sizeArcmin.value : this.sizeArcmin,
        minAltitude: minAltitude ?? this.minAltitude,
        priority: priority ?? this.priority,
        totalPlannedSubs: totalPlannedSubs ?? this.totalPlannedSubs,
        capturedSubs: capturedSubs ?? this.capturedSubs,
        totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
        filterProgress:
            filterProgress.present ? filterProgress.value : this.filterProgress,
        notes: notes.present ? notes.value : this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isFavorite: isFavorite ?? this.isFavorite,
      );
  Target copyWithCompanion(TargetsCompanion data) {
    return Target(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      catalogId: data.catalogId.present ? data.catalogId.value : this.catalogId,
      objectType:
          data.objectType.present ? data.objectType.value : this.objectType,
      ra: data.ra.present ? data.ra.value : this.ra,
      dec: data.dec.present ? data.dec.value : this.dec,
      positionAngle: data.positionAngle.present
          ? data.positionAngle.value
          : this.positionAngle,
      magnitude: data.magnitude.present ? data.magnitude.value : this.magnitude,
      constellation: data.constellation.present
          ? data.constellation.value
          : this.constellation,
      sizeArcmin:
          data.sizeArcmin.present ? data.sizeArcmin.value : this.sizeArcmin,
      minAltitude:
          data.minAltitude.present ? data.minAltitude.value : this.minAltitude,
      priority: data.priority.present ? data.priority.value : this.priority,
      totalPlannedSubs: data.totalPlannedSubs.present
          ? data.totalPlannedSubs.value
          : this.totalPlannedSubs,
      capturedSubs: data.capturedSubs.present
          ? data.capturedSubs.value
          : this.capturedSubs,
      totalIntegrationSecs: data.totalIntegrationSecs.present
          ? data.totalIntegrationSecs.value
          : this.totalIntegrationSecs,
      filterProgress: data.filterProgress.present
          ? data.filterProgress.value
          : this.filterProgress,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isFavorite:
          data.isFavorite.present ? data.isFavorite.value : this.isFavorite,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Target(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('catalogId: $catalogId, ')
          ..write('objectType: $objectType, ')
          ..write('ra: $ra, ')
          ..write('dec: $dec, ')
          ..write('positionAngle: $positionAngle, ')
          ..write('magnitude: $magnitude, ')
          ..write('constellation: $constellation, ')
          ..write('sizeArcmin: $sizeArcmin, ')
          ..write('minAltitude: $minAltitude, ')
          ..write('priority: $priority, ')
          ..write('totalPlannedSubs: $totalPlannedSubs, ')
          ..write('capturedSubs: $capturedSubs, ')
          ..write('totalIntegrationSecs: $totalIntegrationSecs, ')
          ..write('filterProgress: $filterProgress, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isFavorite: $isFavorite')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      catalogId,
      objectType,
      ra,
      dec,
      positionAngle,
      magnitude,
      constellation,
      sizeArcmin,
      minAltitude,
      priority,
      totalPlannedSubs,
      capturedSubs,
      totalIntegrationSecs,
      filterProgress,
      notes,
      createdAt,
      updatedAt,
      isFavorite);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Target &&
          other.id == this.id &&
          other.name == this.name &&
          other.catalogId == this.catalogId &&
          other.objectType == this.objectType &&
          other.ra == this.ra &&
          other.dec == this.dec &&
          other.positionAngle == this.positionAngle &&
          other.magnitude == this.magnitude &&
          other.constellation == this.constellation &&
          other.sizeArcmin == this.sizeArcmin &&
          other.minAltitude == this.minAltitude &&
          other.priority == this.priority &&
          other.totalPlannedSubs == this.totalPlannedSubs &&
          other.capturedSubs == this.capturedSubs &&
          other.totalIntegrationSecs == this.totalIntegrationSecs &&
          other.filterProgress == this.filterProgress &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isFavorite == this.isFavorite);
}

class TargetsCompanion extends UpdateCompanion<Target> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> catalogId;
  final Value<String?> objectType;
  final Value<double> ra;
  final Value<double> dec;
  final Value<double?> positionAngle;
  final Value<double?> magnitude;
  final Value<String?> constellation;
  final Value<double?> sizeArcmin;
  final Value<double> minAltitude;
  final Value<int> priority;
  final Value<int> totalPlannedSubs;
  final Value<int> capturedSubs;
  final Value<double> totalIntegrationSecs;
  final Value<String?> filterProgress;
  final Value<String?> notes;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isFavorite;
  const TargetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.catalogId = const Value.absent(),
    this.objectType = const Value.absent(),
    this.ra = const Value.absent(),
    this.dec = const Value.absent(),
    this.positionAngle = const Value.absent(),
    this.magnitude = const Value.absent(),
    this.constellation = const Value.absent(),
    this.sizeArcmin = const Value.absent(),
    this.minAltitude = const Value.absent(),
    this.priority = const Value.absent(),
    this.totalPlannedSubs = const Value.absent(),
    this.capturedSubs = const Value.absent(),
    this.totalIntegrationSecs = const Value.absent(),
    this.filterProgress = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isFavorite = const Value.absent(),
  });
  TargetsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.catalogId = const Value.absent(),
    this.objectType = const Value.absent(),
    required double ra,
    required double dec,
    this.positionAngle = const Value.absent(),
    this.magnitude = const Value.absent(),
    this.constellation = const Value.absent(),
    this.sizeArcmin = const Value.absent(),
    this.minAltitude = const Value.absent(),
    this.priority = const Value.absent(),
    this.totalPlannedSubs = const Value.absent(),
    this.capturedSubs = const Value.absent(),
    this.totalIntegrationSecs = const Value.absent(),
    this.filterProgress = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isFavorite = const Value.absent(),
  })  : name = Value(name),
        ra = Value(ra),
        dec = Value(dec);
  static Insertable<Target> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? catalogId,
    Expression<String>? objectType,
    Expression<double>? ra,
    Expression<double>? dec,
    Expression<double>? positionAngle,
    Expression<double>? magnitude,
    Expression<String>? constellation,
    Expression<double>? sizeArcmin,
    Expression<double>? minAltitude,
    Expression<int>? priority,
    Expression<int>? totalPlannedSubs,
    Expression<int>? capturedSubs,
    Expression<double>? totalIntegrationSecs,
    Expression<String>? filterProgress,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isFavorite,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (catalogId != null) 'catalog_id': catalogId,
      if (objectType != null) 'object_type': objectType,
      if (ra != null) 'ra': ra,
      if (dec != null) 'dec': dec,
      if (positionAngle != null) 'position_angle': positionAngle,
      if (magnitude != null) 'magnitude': magnitude,
      if (constellation != null) 'constellation': constellation,
      if (sizeArcmin != null) 'size_arcmin': sizeArcmin,
      if (minAltitude != null) 'min_altitude': minAltitude,
      if (priority != null) 'priority': priority,
      if (totalPlannedSubs != null) 'total_planned_subs': totalPlannedSubs,
      if (capturedSubs != null) 'captured_subs': capturedSubs,
      if (totalIntegrationSecs != null)
        'total_integration_secs': totalIntegrationSecs,
      if (filterProgress != null) 'filter_progress': filterProgress,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isFavorite != null) 'is_favorite': isFavorite,
    });
  }

  TargetsCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String?>? catalogId,
      Value<String?>? objectType,
      Value<double>? ra,
      Value<double>? dec,
      Value<double?>? positionAngle,
      Value<double?>? magnitude,
      Value<String?>? constellation,
      Value<double?>? sizeArcmin,
      Value<double>? minAltitude,
      Value<int>? priority,
      Value<int>? totalPlannedSubs,
      Value<int>? capturedSubs,
      Value<double>? totalIntegrationSecs,
      Value<String?>? filterProgress,
      Value<String?>? notes,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<bool>? isFavorite}) {
    return TargetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      catalogId: catalogId ?? this.catalogId,
      objectType: objectType ?? this.objectType,
      ra: ra ?? this.ra,
      dec: dec ?? this.dec,
      positionAngle: positionAngle ?? this.positionAngle,
      magnitude: magnitude ?? this.magnitude,
      constellation: constellation ?? this.constellation,
      sizeArcmin: sizeArcmin ?? this.sizeArcmin,
      minAltitude: minAltitude ?? this.minAltitude,
      priority: priority ?? this.priority,
      totalPlannedSubs: totalPlannedSubs ?? this.totalPlannedSubs,
      capturedSubs: capturedSubs ?? this.capturedSubs,
      totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
      filterProgress: filterProgress ?? this.filterProgress,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (catalogId.present) {
      map['catalog_id'] = Variable<String>(catalogId.value);
    }
    if (objectType.present) {
      map['object_type'] = Variable<String>(objectType.value);
    }
    if (ra.present) {
      map['ra'] = Variable<double>(ra.value);
    }
    if (dec.present) {
      map['dec'] = Variable<double>(dec.value);
    }
    if (positionAngle.present) {
      map['position_angle'] = Variable<double>(positionAngle.value);
    }
    if (magnitude.present) {
      map['magnitude'] = Variable<double>(magnitude.value);
    }
    if (constellation.present) {
      map['constellation'] = Variable<String>(constellation.value);
    }
    if (sizeArcmin.present) {
      map['size_arcmin'] = Variable<double>(sizeArcmin.value);
    }
    if (minAltitude.present) {
      map['min_altitude'] = Variable<double>(minAltitude.value);
    }
    if (priority.present) {
      map['priority'] = Variable<int>(priority.value);
    }
    if (totalPlannedSubs.present) {
      map['total_planned_subs'] = Variable<int>(totalPlannedSubs.value);
    }
    if (capturedSubs.present) {
      map['captured_subs'] = Variable<int>(capturedSubs.value);
    }
    if (totalIntegrationSecs.present) {
      map['total_integration_secs'] =
          Variable<double>(totalIntegrationSecs.value);
    }
    if (filterProgress.present) {
      map['filter_progress'] = Variable<String>(filterProgress.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TargetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('catalogId: $catalogId, ')
          ..write('objectType: $objectType, ')
          ..write('ra: $ra, ')
          ..write('dec: $dec, ')
          ..write('positionAngle: $positionAngle, ')
          ..write('magnitude: $magnitude, ')
          ..write('constellation: $constellation, ')
          ..write('sizeArcmin: $sizeArcmin, ')
          ..write('minAltitude: $minAltitude, ')
          ..write('priority: $priority, ')
          ..write('totalPlannedSubs: $totalPlannedSubs, ')
          ..write('capturedSubs: $capturedSubs, ')
          ..write('totalIntegrationSecs: $totalIntegrationSecs, ')
          ..write('filterProgress: $filterProgress, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isFavorite: $isFavorite')
          ..write(')'))
        .toString();
  }
}

class $SequencesTable extends Sequences
    with TableInfo<$SequencesTable, Sequence> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SequencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      additionalChecks:
          GeneratedColumn.checkTextLength(minTextLength: 1, maxTextLength: 200),
      type: DriftSqlType.string,
      requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _rootNodeIdMeta =
      const VerificationMeta('rootNodeId');
  @override
  late final GeneratedColumn<String> rootNodeId = GeneratedColumn<String>(
      'root_node_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _estimatedDurationMinsMeta =
      const VerificationMeta('estimatedDurationMins');
  @override
  late final GeneratedColumn<int> estimatedDurationMins = GeneratedColumn<int>(
      'estimated_duration_mins', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _isTemplateMeta =
      const VerificationMeta('isTemplate');
  @override
  late final GeneratedColumn<bool> isTemplate = GeneratedColumn<bool>(
      'is_template', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_template" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        description,
        rootNodeId,
        estimatedDurationMins,
        createdAt,
        updatedAt,
        isTemplate
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sequences';
  @override
  VerificationContext validateIntegrity(Insertable<Sequence> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('root_node_id')) {
      context.handle(
          _rootNodeIdMeta,
          rootNodeId.isAcceptableOrUnknown(
              data['root_node_id']!, _rootNodeIdMeta));
    }
    if (data.containsKey('estimated_duration_mins')) {
      context.handle(
          _estimatedDurationMinsMeta,
          estimatedDurationMins.isAcceptableOrUnknown(
              data['estimated_duration_mins']!, _estimatedDurationMinsMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    if (data.containsKey('is_template')) {
      context.handle(
          _isTemplateMeta,
          isTemplate.isAcceptableOrUnknown(
              data['is_template']!, _isTemplateMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Sequence map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sequence(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      rootNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}root_node_id']),
      estimatedDurationMins: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}estimated_duration_mins'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
      isTemplate: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_template'])!,
    );
  }

  @override
  $SequencesTable createAlias(String alias) {
    return $SequencesTable(attachedDatabase, alias);
  }
}

class Sequence extends DataClass implements Insertable<Sequence> {
  final int id;
  final String name;
  final String? description;
  final String? rootNodeId;
  final int estimatedDurationMins;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isTemplate;
  const Sequence(
      {required this.id,
      required this.name,
      this.description,
      this.rootNodeId,
      required this.estimatedDurationMins,
      required this.createdAt,
      required this.updatedAt,
      required this.isTemplate});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || rootNodeId != null) {
      map['root_node_id'] = Variable<String>(rootNodeId);
    }
    map['estimated_duration_mins'] = Variable<int>(estimatedDurationMins);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_template'] = Variable<bool>(isTemplate);
    return map;
  }

  SequencesCompanion toCompanion(bool nullToAbsent) {
    return SequencesCompanion(
      id: Value(id),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      rootNodeId: rootNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(rootNodeId),
      estimatedDurationMins: Value(estimatedDurationMins),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      isTemplate: Value(isTemplate),
    );
  }

  factory Sequence.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sequence(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      rootNodeId: serializer.fromJson<String?>(json['rootNodeId']),
      estimatedDurationMins:
          serializer.fromJson<int>(json['estimatedDurationMins']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isTemplate: serializer.fromJson<bool>(json['isTemplate']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'rootNodeId': serializer.toJson<String?>(rootNodeId),
      'estimatedDurationMins': serializer.toJson<int>(estimatedDurationMins),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isTemplate': serializer.toJson<bool>(isTemplate),
    };
  }

  Sequence copyWith(
          {int? id,
          String? name,
          Value<String?> description = const Value.absent(),
          Value<String?> rootNodeId = const Value.absent(),
          int? estimatedDurationMins,
          DateTime? createdAt,
          DateTime? updatedAt,
          bool? isTemplate}) =>
      Sequence(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description.present ? description.value : this.description,
        rootNodeId: rootNodeId.present ? rootNodeId.value : this.rootNodeId,
        estimatedDurationMins:
            estimatedDurationMins ?? this.estimatedDurationMins,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isTemplate: isTemplate ?? this.isTemplate,
      );
  Sequence copyWithCompanion(SequencesCompanion data) {
    return Sequence(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      description:
          data.description.present ? data.description.value : this.description,
      rootNodeId:
          data.rootNodeId.present ? data.rootNodeId.value : this.rootNodeId,
      estimatedDurationMins: data.estimatedDurationMins.present
          ? data.estimatedDurationMins.value
          : this.estimatedDurationMins,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isTemplate:
          data.isTemplate.present ? data.isTemplate.value : this.isTemplate,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sequence(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('rootNodeId: $rootNodeId, ')
          ..write('estimatedDurationMins: $estimatedDurationMins, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isTemplate: $isTemplate')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, description, rootNodeId,
      estimatedDurationMins, createdAt, updatedAt, isTemplate);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sequence &&
          other.id == this.id &&
          other.name == this.name &&
          other.description == this.description &&
          other.rootNodeId == this.rootNodeId &&
          other.estimatedDurationMins == this.estimatedDurationMins &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.isTemplate == this.isTemplate);
}

class SequencesCompanion extends UpdateCompanion<Sequence> {
  final Value<int> id;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> rootNodeId;
  final Value<int> estimatedDurationMins;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> isTemplate;
  const SequencesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.rootNodeId = const Value.absent(),
    this.estimatedDurationMins = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isTemplate = const Value.absent(),
  });
  SequencesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.description = const Value.absent(),
    this.rootNodeId = const Value.absent(),
    this.estimatedDurationMins = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isTemplate = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Sequence> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? rootNodeId,
    Expression<int>? estimatedDurationMins,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isTemplate,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (rootNodeId != null) 'root_node_id': rootNodeId,
      if (estimatedDurationMins != null)
        'estimated_duration_mins': estimatedDurationMins,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isTemplate != null) 'is_template': isTemplate,
    });
  }

  SequencesCompanion copyWith(
      {Value<int>? id,
      Value<String>? name,
      Value<String?>? description,
      Value<String?>? rootNodeId,
      Value<int>? estimatedDurationMins,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<bool>? isTemplate}) {
    return SequencesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      rootNodeId: rootNodeId ?? this.rootNodeId,
      estimatedDurationMins:
          estimatedDurationMins ?? this.estimatedDurationMins,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isTemplate: isTemplate ?? this.isTemplate,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (rootNodeId.present) {
      map['root_node_id'] = Variable<String>(rootNodeId.value);
    }
    if (estimatedDurationMins.present) {
      map['estimated_duration_mins'] =
          Variable<int>(estimatedDurationMins.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isTemplate.present) {
      map['is_template'] = Variable<bool>(isTemplate.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SequencesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('rootNodeId: $rootNodeId, ')
          ..write('estimatedDurationMins: $estimatedDurationMins, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isTemplate: $isTemplate')
          ..write(')'))
        .toString();
  }
}

class $ImagingSessionsTable extends ImagingSessions
    with TableInfo<$ImagingSessionsTable, ImagingSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImagingSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _profileIdMeta =
      const VerificationMeta('profileId');
  @override
  late final GeneratedColumn<int> profileId = GeneratedColumn<int>(
      'profile_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES equipment_profiles (id)'));
  static const VerificationMeta _targetIdMeta =
      const VerificationMeta('targetId');
  @override
  late final GeneratedColumn<int> targetId = GeneratedColumn<int>(
      'target_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES targets (id)'));
  static const VerificationMeta _startTimeMeta =
      const VerificationMeta('startTime');
  @override
  late final GeneratedColumn<DateTime> startTime = GeneratedColumn<DateTime>(
      'start_time', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _endTimeMeta =
      const VerificationMeta('endTime');
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
      'end_time', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _totalExposuresMeta =
      const VerificationMeta('totalExposures');
  @override
  late final GeneratedColumn<int> totalExposures = GeneratedColumn<int>(
      'total_exposures', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _successfulExposuresMeta =
      const VerificationMeta('successfulExposures');
  @override
  late final GeneratedColumn<int> successfulExposures = GeneratedColumn<int>(
      'successful_exposures', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _failedExposuresMeta =
      const VerificationMeta('failedExposures');
  @override
  late final GeneratedColumn<int> failedExposures = GeneratedColumn<int>(
      'failed_exposures', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _totalIntegrationSecsMeta =
      const VerificationMeta('totalIntegrationSecs');
  @override
  late final GeneratedColumn<double> totalIntegrationSecs =
      GeneratedColumn<double>('total_integration_secs', aliasedName, false,
          type: DriftSqlType.double,
          requiredDuringInsert: false,
          defaultValue: const Constant(0.0));
  static const VerificationMeta _avgTemperatureMeta =
      const VerificationMeta('avgTemperature');
  @override
  late final GeneratedColumn<double> avgTemperature = GeneratedColumn<double>(
      'avg_temperature', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _avgHumidityMeta =
      const VerificationMeta('avgHumidity');
  @override
  late final GeneratedColumn<double> avgHumidity = GeneratedColumn<double>(
      'avg_humidity', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _avgSeeingMeta =
      const VerificationMeta('avgSeeing');
  @override
  late final GeneratedColumn<double> avgSeeing = GeneratedColumn<double>(
      'avg_seeing', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _avgHfrMeta = const VerificationMeta('avgHfr');
  @override
  late final GeneratedColumn<double> avgHfr = GeneratedColumn<double>(
      'avg_hfr', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _avgGuidingRmsMeta =
      const VerificationMeta('avgGuidingRms');
  @override
  late final GeneratedColumn<double> avgGuidingRms = GeneratedColumn<double>(
      'avg_guiding_rms', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _autofocusCountMeta =
      const VerificationMeta('autofocusCount');
  @override
  late final GeneratedColumn<int> autofocusCount = GeneratedColumn<int>(
      'autofocus_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('completed'));
  static const VerificationMeta _sequenceIdMeta =
      const VerificationMeta('sequenceId');
  @override
  late final GeneratedColumn<int> sequenceId = GeneratedColumn<int>(
      'sequence_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sequences (id)'));
  static const VerificationMeta _equipmentSnapshotMeta =
      const VerificationMeta('equipmentSnapshot');
  @override
  late final GeneratedColumn<String> equipmentSnapshot =
      GeneratedColumn<String>('equipment_snapshot', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        profileId,
        targetId,
        startTime,
        endTime,
        totalExposures,
        successfulExposures,
        failedExposures,
        totalIntegrationSecs,
        avgTemperature,
        avgHumidity,
        avgSeeing,
        avgHfr,
        avgGuidingRms,
        autofocusCount,
        notes,
        status,
        sequenceId,
        equipmentSnapshot
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imaging_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<ImagingSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('profile_id')) {
      context.handle(_profileIdMeta,
          profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta));
    }
    if (data.containsKey('target_id')) {
      context.handle(_targetIdMeta,
          targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta));
    }
    if (data.containsKey('start_time')) {
      context.handle(_startTimeMeta,
          startTime.isAcceptableOrUnknown(data['start_time']!, _startTimeMeta));
    } else if (isInserting) {
      context.missing(_startTimeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(_endTimeMeta,
          endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta));
    }
    if (data.containsKey('total_exposures')) {
      context.handle(
          _totalExposuresMeta,
          totalExposures.isAcceptableOrUnknown(
              data['total_exposures']!, _totalExposuresMeta));
    }
    if (data.containsKey('successful_exposures')) {
      context.handle(
          _successfulExposuresMeta,
          successfulExposures.isAcceptableOrUnknown(
              data['successful_exposures']!, _successfulExposuresMeta));
    }
    if (data.containsKey('failed_exposures')) {
      context.handle(
          _failedExposuresMeta,
          failedExposures.isAcceptableOrUnknown(
              data['failed_exposures']!, _failedExposuresMeta));
    }
    if (data.containsKey('total_integration_secs')) {
      context.handle(
          _totalIntegrationSecsMeta,
          totalIntegrationSecs.isAcceptableOrUnknown(
              data['total_integration_secs']!, _totalIntegrationSecsMeta));
    }
    if (data.containsKey('avg_temperature')) {
      context.handle(
          _avgTemperatureMeta,
          avgTemperature.isAcceptableOrUnknown(
              data['avg_temperature']!, _avgTemperatureMeta));
    }
    if (data.containsKey('avg_humidity')) {
      context.handle(
          _avgHumidityMeta,
          avgHumidity.isAcceptableOrUnknown(
              data['avg_humidity']!, _avgHumidityMeta));
    }
    if (data.containsKey('avg_seeing')) {
      context.handle(_avgSeeingMeta,
          avgSeeing.isAcceptableOrUnknown(data['avg_seeing']!, _avgSeeingMeta));
    }
    if (data.containsKey('avg_hfr')) {
      context.handle(_avgHfrMeta,
          avgHfr.isAcceptableOrUnknown(data['avg_hfr']!, _avgHfrMeta));
    }
    if (data.containsKey('avg_guiding_rms')) {
      context.handle(
          _avgGuidingRmsMeta,
          avgGuidingRms.isAcceptableOrUnknown(
              data['avg_guiding_rms']!, _avgGuidingRmsMeta));
    }
    if (data.containsKey('autofocus_count')) {
      context.handle(
          _autofocusCountMeta,
          autofocusCount.isAcceptableOrUnknown(
              data['autofocus_count']!, _autofocusCountMeta));
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('sequence_id')) {
      context.handle(
          _sequenceIdMeta,
          sequenceId.isAcceptableOrUnknown(
              data['sequence_id']!, _sequenceIdMeta));
    }
    if (data.containsKey('equipment_snapshot')) {
      context.handle(
          _equipmentSnapshotMeta,
          equipmentSnapshot.isAcceptableOrUnknown(
              data['equipment_snapshot']!, _equipmentSnapshotMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImagingSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImagingSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name']),
      profileId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}profile_id']),
      targetId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}target_id']),
      startTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}start_time'])!,
      endTime: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}end_time']),
      totalExposures: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_exposures'])!,
      successfulExposures: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}successful_exposures'])!,
      failedExposures: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}failed_exposures'])!,
      totalIntegrationSecs: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}total_integration_secs'])!,
      avgTemperature: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}avg_temperature']),
      avgHumidity: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}avg_humidity']),
      avgSeeing: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}avg_seeing']),
      avgHfr: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}avg_hfr']),
      avgGuidingRms: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}avg_guiding_rms']),
      autofocusCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}autofocus_count'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      sequenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sequence_id']),
      equipmentSnapshot: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}equipment_snapshot']),
    );
  }

  @override
  $ImagingSessionsTable createAlias(String alias) {
    return $ImagingSessionsTable(attachedDatabase, alias);
  }
}

class ImagingSession extends DataClass implements Insertable<ImagingSession> {
  final int id;
  final String? name;
  final int? profileId;
  final int? targetId;
  final DateTime startTime;
  final DateTime? endTime;
  final int totalExposures;
  final int successfulExposures;
  final int failedExposures;
  final double totalIntegrationSecs;
  final double? avgTemperature;
  final double? avgHumidity;
  final double? avgSeeing;
  final double? avgHfr;
  final double? avgGuidingRms;
  final int autofocusCount;
  final String? notes;
  final String status;
  final int? sequenceId;
  final String? equipmentSnapshot;
  const ImagingSession(
      {required this.id,
      this.name,
      this.profileId,
      this.targetId,
      required this.startTime,
      this.endTime,
      required this.totalExposures,
      required this.successfulExposures,
      required this.failedExposures,
      required this.totalIntegrationSecs,
      this.avgTemperature,
      this.avgHumidity,
      this.avgSeeing,
      this.avgHfr,
      this.avgGuidingRms,
      required this.autofocusCount,
      this.notes,
      required this.status,
      this.sequenceId,
      this.equipmentSnapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || profileId != null) {
      map['profile_id'] = Variable<int>(profileId);
    }
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<int>(targetId);
    }
    map['start_time'] = Variable<DateTime>(startTime);
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<DateTime>(endTime);
    }
    map['total_exposures'] = Variable<int>(totalExposures);
    map['successful_exposures'] = Variable<int>(successfulExposures);
    map['failed_exposures'] = Variable<int>(failedExposures);
    map['total_integration_secs'] = Variable<double>(totalIntegrationSecs);
    if (!nullToAbsent || avgTemperature != null) {
      map['avg_temperature'] = Variable<double>(avgTemperature);
    }
    if (!nullToAbsent || avgHumidity != null) {
      map['avg_humidity'] = Variable<double>(avgHumidity);
    }
    if (!nullToAbsent || avgSeeing != null) {
      map['avg_seeing'] = Variable<double>(avgSeeing);
    }
    if (!nullToAbsent || avgHfr != null) {
      map['avg_hfr'] = Variable<double>(avgHfr);
    }
    if (!nullToAbsent || avgGuidingRms != null) {
      map['avg_guiding_rms'] = Variable<double>(avgGuidingRms);
    }
    map['autofocus_count'] = Variable<int>(autofocusCount);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || sequenceId != null) {
      map['sequence_id'] = Variable<int>(sequenceId);
    }
    if (!nullToAbsent || equipmentSnapshot != null) {
      map['equipment_snapshot'] = Variable<String>(equipmentSnapshot);
    }
    return map;
  }

  ImagingSessionsCompanion toCompanion(bool nullToAbsent) {
    return ImagingSessionsCompanion(
      id: Value(id),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      profileId: profileId == null && nullToAbsent
          ? const Value.absent()
          : Value(profileId),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      startTime: Value(startTime),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      totalExposures: Value(totalExposures),
      successfulExposures: Value(successfulExposures),
      failedExposures: Value(failedExposures),
      totalIntegrationSecs: Value(totalIntegrationSecs),
      avgTemperature: avgTemperature == null && nullToAbsent
          ? const Value.absent()
          : Value(avgTemperature),
      avgHumidity: avgHumidity == null && nullToAbsent
          ? const Value.absent()
          : Value(avgHumidity),
      avgSeeing: avgSeeing == null && nullToAbsent
          ? const Value.absent()
          : Value(avgSeeing),
      avgHfr:
          avgHfr == null && nullToAbsent ? const Value.absent() : Value(avgHfr),
      avgGuidingRms: avgGuidingRms == null && nullToAbsent
          ? const Value.absent()
          : Value(avgGuidingRms),
      autofocusCount: Value(autofocusCount),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      status: Value(status),
      sequenceId: sequenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(sequenceId),
      equipmentSnapshot: equipmentSnapshot == null && nullToAbsent
          ? const Value.absent()
          : Value(equipmentSnapshot),
    );
  }

  factory ImagingSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImagingSession(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String?>(json['name']),
      profileId: serializer.fromJson<int?>(json['profileId']),
      targetId: serializer.fromJson<int?>(json['targetId']),
      startTime: serializer.fromJson<DateTime>(json['startTime']),
      endTime: serializer.fromJson<DateTime?>(json['endTime']),
      totalExposures: serializer.fromJson<int>(json['totalExposures']),
      successfulExposures:
          serializer.fromJson<int>(json['successfulExposures']),
      failedExposures: serializer.fromJson<int>(json['failedExposures']),
      totalIntegrationSecs:
          serializer.fromJson<double>(json['totalIntegrationSecs']),
      avgTemperature: serializer.fromJson<double?>(json['avgTemperature']),
      avgHumidity: serializer.fromJson<double?>(json['avgHumidity']),
      avgSeeing: serializer.fromJson<double?>(json['avgSeeing']),
      avgHfr: serializer.fromJson<double?>(json['avgHfr']),
      avgGuidingRms: serializer.fromJson<double?>(json['avgGuidingRms']),
      autofocusCount: serializer.fromJson<int>(json['autofocusCount']),
      notes: serializer.fromJson<String?>(json['notes']),
      status: serializer.fromJson<String>(json['status']),
      sequenceId: serializer.fromJson<int?>(json['sequenceId']),
      equipmentSnapshot:
          serializer.fromJson<String?>(json['equipmentSnapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String?>(name),
      'profileId': serializer.toJson<int?>(profileId),
      'targetId': serializer.toJson<int?>(targetId),
      'startTime': serializer.toJson<DateTime>(startTime),
      'endTime': serializer.toJson<DateTime?>(endTime),
      'totalExposures': serializer.toJson<int>(totalExposures),
      'successfulExposures': serializer.toJson<int>(successfulExposures),
      'failedExposures': serializer.toJson<int>(failedExposures),
      'totalIntegrationSecs': serializer.toJson<double>(totalIntegrationSecs),
      'avgTemperature': serializer.toJson<double?>(avgTemperature),
      'avgHumidity': serializer.toJson<double?>(avgHumidity),
      'avgSeeing': serializer.toJson<double?>(avgSeeing),
      'avgHfr': serializer.toJson<double?>(avgHfr),
      'avgGuidingRms': serializer.toJson<double?>(avgGuidingRms),
      'autofocusCount': serializer.toJson<int>(autofocusCount),
      'notes': serializer.toJson<String?>(notes),
      'status': serializer.toJson<String>(status),
      'sequenceId': serializer.toJson<int?>(sequenceId),
      'equipmentSnapshot': serializer.toJson<String?>(equipmentSnapshot),
    };
  }

  ImagingSession copyWith(
          {int? id,
          Value<String?> name = const Value.absent(),
          Value<int?> profileId = const Value.absent(),
          Value<int?> targetId = const Value.absent(),
          DateTime? startTime,
          Value<DateTime?> endTime = const Value.absent(),
          int? totalExposures,
          int? successfulExposures,
          int? failedExposures,
          double? totalIntegrationSecs,
          Value<double?> avgTemperature = const Value.absent(),
          Value<double?> avgHumidity = const Value.absent(),
          Value<double?> avgSeeing = const Value.absent(),
          Value<double?> avgHfr = const Value.absent(),
          Value<double?> avgGuidingRms = const Value.absent(),
          int? autofocusCount,
          Value<String?> notes = const Value.absent(),
          String? status,
          Value<int?> sequenceId = const Value.absent(),
          Value<String?> equipmentSnapshot = const Value.absent()}) =>
      ImagingSession(
        id: id ?? this.id,
        name: name.present ? name.value : this.name,
        profileId: profileId.present ? profileId.value : this.profileId,
        targetId: targetId.present ? targetId.value : this.targetId,
        startTime: startTime ?? this.startTime,
        endTime: endTime.present ? endTime.value : this.endTime,
        totalExposures: totalExposures ?? this.totalExposures,
        successfulExposures: successfulExposures ?? this.successfulExposures,
        failedExposures: failedExposures ?? this.failedExposures,
        totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
        avgTemperature:
            avgTemperature.present ? avgTemperature.value : this.avgTemperature,
        avgHumidity: avgHumidity.present ? avgHumidity.value : this.avgHumidity,
        avgSeeing: avgSeeing.present ? avgSeeing.value : this.avgSeeing,
        avgHfr: avgHfr.present ? avgHfr.value : this.avgHfr,
        avgGuidingRms:
            avgGuidingRms.present ? avgGuidingRms.value : this.avgGuidingRms,
        autofocusCount: autofocusCount ?? this.autofocusCount,
        notes: notes.present ? notes.value : this.notes,
        status: status ?? this.status,
        sequenceId: sequenceId.present ? sequenceId.value : this.sequenceId,
        equipmentSnapshot: equipmentSnapshot.present
            ? equipmentSnapshot.value
            : this.equipmentSnapshot,
      );
  ImagingSession copyWithCompanion(ImagingSessionsCompanion data) {
    return ImagingSession(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      startTime: data.startTime.present ? data.startTime.value : this.startTime,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      totalExposures: data.totalExposures.present
          ? data.totalExposures.value
          : this.totalExposures,
      successfulExposures: data.successfulExposures.present
          ? data.successfulExposures.value
          : this.successfulExposures,
      failedExposures: data.failedExposures.present
          ? data.failedExposures.value
          : this.failedExposures,
      totalIntegrationSecs: data.totalIntegrationSecs.present
          ? data.totalIntegrationSecs.value
          : this.totalIntegrationSecs,
      avgTemperature: data.avgTemperature.present
          ? data.avgTemperature.value
          : this.avgTemperature,
      avgHumidity:
          data.avgHumidity.present ? data.avgHumidity.value : this.avgHumidity,
      avgSeeing: data.avgSeeing.present ? data.avgSeeing.value : this.avgSeeing,
      avgHfr: data.avgHfr.present ? data.avgHfr.value : this.avgHfr,
      avgGuidingRms: data.avgGuidingRms.present
          ? data.avgGuidingRms.value
          : this.avgGuidingRms,
      autofocusCount: data.autofocusCount.present
          ? data.autofocusCount.value
          : this.autofocusCount,
      notes: data.notes.present ? data.notes.value : this.notes,
      status: data.status.present ? data.status.value : this.status,
      sequenceId:
          data.sequenceId.present ? data.sequenceId.value : this.sequenceId,
      equipmentSnapshot: data.equipmentSnapshot.present
          ? data.equipmentSnapshot.value
          : this.equipmentSnapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImagingSession(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('profileId: $profileId, ')
          ..write('targetId: $targetId, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('totalExposures: $totalExposures, ')
          ..write('successfulExposures: $successfulExposures, ')
          ..write('failedExposures: $failedExposures, ')
          ..write('totalIntegrationSecs: $totalIntegrationSecs, ')
          ..write('avgTemperature: $avgTemperature, ')
          ..write('avgHumidity: $avgHumidity, ')
          ..write('avgSeeing: $avgSeeing, ')
          ..write('avgHfr: $avgHfr, ')
          ..write('avgGuidingRms: $avgGuidingRms, ')
          ..write('autofocusCount: $autofocusCount, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('sequenceId: $sequenceId, ')
          ..write('equipmentSnapshot: $equipmentSnapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      name,
      profileId,
      targetId,
      startTime,
      endTime,
      totalExposures,
      successfulExposures,
      failedExposures,
      totalIntegrationSecs,
      avgTemperature,
      avgHumidity,
      avgSeeing,
      avgHfr,
      avgGuidingRms,
      autofocusCount,
      notes,
      status,
      sequenceId,
      equipmentSnapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImagingSession &&
          other.id == this.id &&
          other.name == this.name &&
          other.profileId == this.profileId &&
          other.targetId == this.targetId &&
          other.startTime == this.startTime &&
          other.endTime == this.endTime &&
          other.totalExposures == this.totalExposures &&
          other.successfulExposures == this.successfulExposures &&
          other.failedExposures == this.failedExposures &&
          other.totalIntegrationSecs == this.totalIntegrationSecs &&
          other.avgTemperature == this.avgTemperature &&
          other.avgHumidity == this.avgHumidity &&
          other.avgSeeing == this.avgSeeing &&
          other.avgHfr == this.avgHfr &&
          other.avgGuidingRms == this.avgGuidingRms &&
          other.autofocusCount == this.autofocusCount &&
          other.notes == this.notes &&
          other.status == this.status &&
          other.sequenceId == this.sequenceId &&
          other.equipmentSnapshot == this.equipmentSnapshot);
}

class ImagingSessionsCompanion extends UpdateCompanion<ImagingSession> {
  final Value<int> id;
  final Value<String?> name;
  final Value<int?> profileId;
  final Value<int?> targetId;
  final Value<DateTime> startTime;
  final Value<DateTime?> endTime;
  final Value<int> totalExposures;
  final Value<int> successfulExposures;
  final Value<int> failedExposures;
  final Value<double> totalIntegrationSecs;
  final Value<double?> avgTemperature;
  final Value<double?> avgHumidity;
  final Value<double?> avgSeeing;
  final Value<double?> avgHfr;
  final Value<double?> avgGuidingRms;
  final Value<int> autofocusCount;
  final Value<String?> notes;
  final Value<String> status;
  final Value<int?> sequenceId;
  final Value<String?> equipmentSnapshot;
  const ImagingSessionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.profileId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.startTime = const Value.absent(),
    this.endTime = const Value.absent(),
    this.totalExposures = const Value.absent(),
    this.successfulExposures = const Value.absent(),
    this.failedExposures = const Value.absent(),
    this.totalIntegrationSecs = const Value.absent(),
    this.avgTemperature = const Value.absent(),
    this.avgHumidity = const Value.absent(),
    this.avgSeeing = const Value.absent(),
    this.avgHfr = const Value.absent(),
    this.avgGuidingRms = const Value.absent(),
    this.autofocusCount = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.sequenceId = const Value.absent(),
    this.equipmentSnapshot = const Value.absent(),
  });
  ImagingSessionsCompanion.insert({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.profileId = const Value.absent(),
    this.targetId = const Value.absent(),
    required DateTime startTime,
    this.endTime = const Value.absent(),
    this.totalExposures = const Value.absent(),
    this.successfulExposures = const Value.absent(),
    this.failedExposures = const Value.absent(),
    this.totalIntegrationSecs = const Value.absent(),
    this.avgTemperature = const Value.absent(),
    this.avgHumidity = const Value.absent(),
    this.avgSeeing = const Value.absent(),
    this.avgHfr = const Value.absent(),
    this.avgGuidingRms = const Value.absent(),
    this.autofocusCount = const Value.absent(),
    this.notes = const Value.absent(),
    this.status = const Value.absent(),
    this.sequenceId = const Value.absent(),
    this.equipmentSnapshot = const Value.absent(),
  }) : startTime = Value(startTime);
  static Insertable<ImagingSession> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? profileId,
    Expression<int>? targetId,
    Expression<DateTime>? startTime,
    Expression<DateTime>? endTime,
    Expression<int>? totalExposures,
    Expression<int>? successfulExposures,
    Expression<int>? failedExposures,
    Expression<double>? totalIntegrationSecs,
    Expression<double>? avgTemperature,
    Expression<double>? avgHumidity,
    Expression<double>? avgSeeing,
    Expression<double>? avgHfr,
    Expression<double>? avgGuidingRms,
    Expression<int>? autofocusCount,
    Expression<String>? notes,
    Expression<String>? status,
    Expression<int>? sequenceId,
    Expression<String>? equipmentSnapshot,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (profileId != null) 'profile_id': profileId,
      if (targetId != null) 'target_id': targetId,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (totalExposures != null) 'total_exposures': totalExposures,
      if (successfulExposures != null)
        'successful_exposures': successfulExposures,
      if (failedExposures != null) 'failed_exposures': failedExposures,
      if (totalIntegrationSecs != null)
        'total_integration_secs': totalIntegrationSecs,
      if (avgTemperature != null) 'avg_temperature': avgTemperature,
      if (avgHumidity != null) 'avg_humidity': avgHumidity,
      if (avgSeeing != null) 'avg_seeing': avgSeeing,
      if (avgHfr != null) 'avg_hfr': avgHfr,
      if (avgGuidingRms != null) 'avg_guiding_rms': avgGuidingRms,
      if (autofocusCount != null) 'autofocus_count': autofocusCount,
      if (notes != null) 'notes': notes,
      if (status != null) 'status': status,
      if (sequenceId != null) 'sequence_id': sequenceId,
      if (equipmentSnapshot != null) 'equipment_snapshot': equipmentSnapshot,
    });
  }

  ImagingSessionsCompanion copyWith(
      {Value<int>? id,
      Value<String?>? name,
      Value<int?>? profileId,
      Value<int?>? targetId,
      Value<DateTime>? startTime,
      Value<DateTime?>? endTime,
      Value<int>? totalExposures,
      Value<int>? successfulExposures,
      Value<int>? failedExposures,
      Value<double>? totalIntegrationSecs,
      Value<double?>? avgTemperature,
      Value<double?>? avgHumidity,
      Value<double?>? avgSeeing,
      Value<double?>? avgHfr,
      Value<double?>? avgGuidingRms,
      Value<int>? autofocusCount,
      Value<String?>? notes,
      Value<String>? status,
      Value<int?>? sequenceId,
      Value<String?>? equipmentSnapshot}) {
    return ImagingSessionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      profileId: profileId ?? this.profileId,
      targetId: targetId ?? this.targetId,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      totalExposures: totalExposures ?? this.totalExposures,
      successfulExposures: successfulExposures ?? this.successfulExposures,
      failedExposures: failedExposures ?? this.failedExposures,
      totalIntegrationSecs: totalIntegrationSecs ?? this.totalIntegrationSecs,
      avgTemperature: avgTemperature ?? this.avgTemperature,
      avgHumidity: avgHumidity ?? this.avgHumidity,
      avgSeeing: avgSeeing ?? this.avgSeeing,
      avgHfr: avgHfr ?? this.avgHfr,
      avgGuidingRms: avgGuidingRms ?? this.avgGuidingRms,
      autofocusCount: autofocusCount ?? this.autofocusCount,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      sequenceId: sequenceId ?? this.sequenceId,
      equipmentSnapshot: equipmentSnapshot ?? this.equipmentSnapshot,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<int>(profileId.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<int>(targetId.value);
    }
    if (startTime.present) {
      map['start_time'] = Variable<DateTime>(startTime.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (totalExposures.present) {
      map['total_exposures'] = Variable<int>(totalExposures.value);
    }
    if (successfulExposures.present) {
      map['successful_exposures'] = Variable<int>(successfulExposures.value);
    }
    if (failedExposures.present) {
      map['failed_exposures'] = Variable<int>(failedExposures.value);
    }
    if (totalIntegrationSecs.present) {
      map['total_integration_secs'] =
          Variable<double>(totalIntegrationSecs.value);
    }
    if (avgTemperature.present) {
      map['avg_temperature'] = Variable<double>(avgTemperature.value);
    }
    if (avgHumidity.present) {
      map['avg_humidity'] = Variable<double>(avgHumidity.value);
    }
    if (avgSeeing.present) {
      map['avg_seeing'] = Variable<double>(avgSeeing.value);
    }
    if (avgHfr.present) {
      map['avg_hfr'] = Variable<double>(avgHfr.value);
    }
    if (avgGuidingRms.present) {
      map['avg_guiding_rms'] = Variable<double>(avgGuidingRms.value);
    }
    if (autofocusCount.present) {
      map['autofocus_count'] = Variable<int>(autofocusCount.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (sequenceId.present) {
      map['sequence_id'] = Variable<int>(sequenceId.value);
    }
    if (equipmentSnapshot.present) {
      map['equipment_snapshot'] = Variable<String>(equipmentSnapshot.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImagingSessionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('profileId: $profileId, ')
          ..write('targetId: $targetId, ')
          ..write('startTime: $startTime, ')
          ..write('endTime: $endTime, ')
          ..write('totalExposures: $totalExposures, ')
          ..write('successfulExposures: $successfulExposures, ')
          ..write('failedExposures: $failedExposures, ')
          ..write('totalIntegrationSecs: $totalIntegrationSecs, ')
          ..write('avgTemperature: $avgTemperature, ')
          ..write('avgHumidity: $avgHumidity, ')
          ..write('avgSeeing: $avgSeeing, ')
          ..write('avgHfr: $avgHfr, ')
          ..write('avgGuidingRms: $avgGuidingRms, ')
          ..write('autofocusCount: $autofocusCount, ')
          ..write('notes: $notes, ')
          ..write('status: $status, ')
          ..write('sequenceId: $sequenceId, ')
          ..write('equipmentSnapshot: $equipmentSnapshot')
          ..write(')'))
        .toString();
  }
}

class $SequenceNodesTable extends SequenceNodes
    with TableInfo<$SequenceNodesTable, SequenceNode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SequenceNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
      'node_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sequenceIdMeta =
      const VerificationMeta('sequenceId');
  @override
  late final GeneratedColumn<int> sequenceId = GeneratedColumn<int>(
      'sequence_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES sequences (id) ON DELETE CASCADE'));
  static const VerificationMeta _targetIdMeta =
      const VerificationMeta('targetId');
  @override
  late final GeneratedColumn<int> targetId = GeneratedColumn<int>(
      'target_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES targets (id) ON DELETE SET NULL'));
  static const VerificationMeta _nodeTypeMeta =
      const VerificationMeta('nodeType');
  @override
  late final GeneratedColumn<String> nodeType = GeneratedColumn<String>(
      'node_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _specificTypeMeta =
      const VerificationMeta('specificType');
  @override
  late final GeneratedColumn<String> specificType = GeneratedColumn<String>(
      'specific_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _propertiesMeta =
      const VerificationMeta('properties');
  @override
  late final GeneratedColumn<String> properties = GeneratedColumn<String>(
      'properties', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('{}'));
  static const VerificationMeta _recoveryConfigMeta =
      const VerificationMeta('recoveryConfig');
  @override
  late final GeneratedColumn<String> recoveryConfig = GeneratedColumn<String>(
      'recovery_config', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _parentNodeIdMeta =
      const VerificationMeta('parentNodeId');
  @override
  late final GeneratedColumn<String> parentNodeId = GeneratedColumn<String>(
      'parent_node_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _orderIndexMeta =
      const VerificationMeta('orderIndex');
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
      'order_index', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isEnabledMeta =
      const VerificationMeta('isEnabled');
  @override
  late final GeneratedColumn<bool> isEnabled = GeneratedColumn<bool>(
      'is_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        nodeId,
        sequenceId,
        targetId,
        nodeType,
        specificType,
        name,
        properties,
        recoveryConfig,
        parentNodeId,
        orderIndex,
        isEnabled
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sequence_nodes';
  @override
  VerificationContext validateIntegrity(Insertable<SequenceNode> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('node_id')) {
      context.handle(_nodeIdMeta,
          nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta));
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('sequence_id')) {
      context.handle(
          _sequenceIdMeta,
          sequenceId.isAcceptableOrUnknown(
              data['sequence_id']!, _sequenceIdMeta));
    } else if (isInserting) {
      context.missing(_sequenceIdMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(_targetIdMeta,
          targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta));
    }
    if (data.containsKey('node_type')) {
      context.handle(_nodeTypeMeta,
          nodeType.isAcceptableOrUnknown(data['node_type']!, _nodeTypeMeta));
    } else if (isInserting) {
      context.missing(_nodeTypeMeta);
    }
    if (data.containsKey('specific_type')) {
      context.handle(
          _specificTypeMeta,
          specificType.isAcceptableOrUnknown(
              data['specific_type']!, _specificTypeMeta));
    } else if (isInserting) {
      context.missing(_specificTypeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('properties')) {
      context.handle(
          _propertiesMeta,
          properties.isAcceptableOrUnknown(
              data['properties']!, _propertiesMeta));
    }
    if (data.containsKey('recovery_config')) {
      context.handle(
          _recoveryConfigMeta,
          recoveryConfig.isAcceptableOrUnknown(
              data['recovery_config']!, _recoveryConfigMeta));
    }
    if (data.containsKey('parent_node_id')) {
      context.handle(
          _parentNodeIdMeta,
          parentNodeId.isAcceptableOrUnknown(
              data['parent_node_id']!, _parentNodeIdMeta));
    }
    if (data.containsKey('order_index')) {
      context.handle(
          _orderIndexMeta,
          orderIndex.isAcceptableOrUnknown(
              data['order_index']!, _orderIndexMeta));
    }
    if (data.containsKey('is_enabled')) {
      context.handle(_isEnabledMeta,
          isEnabled.isAcceptableOrUnknown(data['is_enabled']!, _isEnabledMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SequenceNode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SequenceNode(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      nodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}node_id'])!,
      sequenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sequence_id'])!,
      targetId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}target_id']),
      nodeType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}node_type'])!,
      specificType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}specific_type'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      properties: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}properties'])!,
      recoveryConfig: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}recovery_config']),
      parentNodeId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_node_id']),
      orderIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}order_index'])!,
      isEnabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_enabled'])!,
    );
  }

  @override
  $SequenceNodesTable createAlias(String alias) {
    return $SequenceNodesTable(attachedDatabase, alias);
  }
}

class SequenceNode extends DataClass implements Insertable<SequenceNode> {
  final int id;
  final String nodeId;
  final int sequenceId;
  final int? targetId;
  final String nodeType;
  final String specificType;
  final String name;
  final String properties;
  final String? recoveryConfig;
  final String? parentNodeId;
  final int orderIndex;
  final bool isEnabled;
  const SequenceNode(
      {required this.id,
      required this.nodeId,
      required this.sequenceId,
      this.targetId,
      required this.nodeType,
      required this.specificType,
      required this.name,
      required this.properties,
      this.recoveryConfig,
      this.parentNodeId,
      required this.orderIndex,
      required this.isEnabled});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['node_id'] = Variable<String>(nodeId);
    map['sequence_id'] = Variable<int>(sequenceId);
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<int>(targetId);
    }
    map['node_type'] = Variable<String>(nodeType);
    map['specific_type'] = Variable<String>(specificType);
    map['name'] = Variable<String>(name);
    map['properties'] = Variable<String>(properties);
    if (!nullToAbsent || recoveryConfig != null) {
      map['recovery_config'] = Variable<String>(recoveryConfig);
    }
    if (!nullToAbsent || parentNodeId != null) {
      map['parent_node_id'] = Variable<String>(parentNodeId);
    }
    map['order_index'] = Variable<int>(orderIndex);
    map['is_enabled'] = Variable<bool>(isEnabled);
    return map;
  }

  SequenceNodesCompanion toCompanion(bool nullToAbsent) {
    return SequenceNodesCompanion(
      id: Value(id),
      nodeId: Value(nodeId),
      sequenceId: Value(sequenceId),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      nodeType: Value(nodeType),
      specificType: Value(specificType),
      name: Value(name),
      properties: Value(properties),
      recoveryConfig: recoveryConfig == null && nullToAbsent
          ? const Value.absent()
          : Value(recoveryConfig),
      parentNodeId: parentNodeId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentNodeId),
      orderIndex: Value(orderIndex),
      isEnabled: Value(isEnabled),
    );
  }

  factory SequenceNode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SequenceNode(
      id: serializer.fromJson<int>(json['id']),
      nodeId: serializer.fromJson<String>(json['nodeId']),
      sequenceId: serializer.fromJson<int>(json['sequenceId']),
      targetId: serializer.fromJson<int?>(json['targetId']),
      nodeType: serializer.fromJson<String>(json['nodeType']),
      specificType: serializer.fromJson<String>(json['specificType']),
      name: serializer.fromJson<String>(json['name']),
      properties: serializer.fromJson<String>(json['properties']),
      recoveryConfig: serializer.fromJson<String?>(json['recoveryConfig']),
      parentNodeId: serializer.fromJson<String?>(json['parentNodeId']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      isEnabled: serializer.fromJson<bool>(json['isEnabled']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'nodeId': serializer.toJson<String>(nodeId),
      'sequenceId': serializer.toJson<int>(sequenceId),
      'targetId': serializer.toJson<int?>(targetId),
      'nodeType': serializer.toJson<String>(nodeType),
      'specificType': serializer.toJson<String>(specificType),
      'name': serializer.toJson<String>(name),
      'properties': serializer.toJson<String>(properties),
      'recoveryConfig': serializer.toJson<String?>(recoveryConfig),
      'parentNodeId': serializer.toJson<String?>(parentNodeId),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'isEnabled': serializer.toJson<bool>(isEnabled),
    };
  }

  SequenceNode copyWith(
          {int? id,
          String? nodeId,
          int? sequenceId,
          Value<int?> targetId = const Value.absent(),
          String? nodeType,
          String? specificType,
          String? name,
          String? properties,
          Value<String?> recoveryConfig = const Value.absent(),
          Value<String?> parentNodeId = const Value.absent(),
          int? orderIndex,
          bool? isEnabled}) =>
      SequenceNode(
        id: id ?? this.id,
        nodeId: nodeId ?? this.nodeId,
        sequenceId: sequenceId ?? this.sequenceId,
        targetId: targetId.present ? targetId.value : this.targetId,
        nodeType: nodeType ?? this.nodeType,
        specificType: specificType ?? this.specificType,
        name: name ?? this.name,
        properties: properties ?? this.properties,
        recoveryConfig:
            recoveryConfig.present ? recoveryConfig.value : this.recoveryConfig,
        parentNodeId:
            parentNodeId.present ? parentNodeId.value : this.parentNodeId,
        orderIndex: orderIndex ?? this.orderIndex,
        isEnabled: isEnabled ?? this.isEnabled,
      );
  SequenceNode copyWithCompanion(SequenceNodesCompanion data) {
    return SequenceNode(
      id: data.id.present ? data.id.value : this.id,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      sequenceId:
          data.sequenceId.present ? data.sequenceId.value : this.sequenceId,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      nodeType: data.nodeType.present ? data.nodeType.value : this.nodeType,
      specificType: data.specificType.present
          ? data.specificType.value
          : this.specificType,
      name: data.name.present ? data.name.value : this.name,
      properties:
          data.properties.present ? data.properties.value : this.properties,
      recoveryConfig: data.recoveryConfig.present
          ? data.recoveryConfig.value
          : this.recoveryConfig,
      parentNodeId: data.parentNodeId.present
          ? data.parentNodeId.value
          : this.parentNodeId,
      orderIndex:
          data.orderIndex.present ? data.orderIndex.value : this.orderIndex,
      isEnabled: data.isEnabled.present ? data.isEnabled.value : this.isEnabled,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SequenceNode(')
          ..write('id: $id, ')
          ..write('nodeId: $nodeId, ')
          ..write('sequenceId: $sequenceId, ')
          ..write('targetId: $targetId, ')
          ..write('nodeType: $nodeType, ')
          ..write('specificType: $specificType, ')
          ..write('name: $name, ')
          ..write('properties: $properties, ')
          ..write('recoveryConfig: $recoveryConfig, ')
          ..write('parentNodeId: $parentNodeId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('isEnabled: $isEnabled')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      nodeId,
      sequenceId,
      targetId,
      nodeType,
      specificType,
      name,
      properties,
      recoveryConfig,
      parentNodeId,
      orderIndex,
      isEnabled);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SequenceNode &&
          other.id == this.id &&
          other.nodeId == this.nodeId &&
          other.sequenceId == this.sequenceId &&
          other.targetId == this.targetId &&
          other.nodeType == this.nodeType &&
          other.specificType == this.specificType &&
          other.name == this.name &&
          other.properties == this.properties &&
          other.recoveryConfig == this.recoveryConfig &&
          other.parentNodeId == this.parentNodeId &&
          other.orderIndex == this.orderIndex &&
          other.isEnabled == this.isEnabled);
}

class SequenceNodesCompanion extends UpdateCompanion<SequenceNode> {
  final Value<int> id;
  final Value<String> nodeId;
  final Value<int> sequenceId;
  final Value<int?> targetId;
  final Value<String> nodeType;
  final Value<String> specificType;
  final Value<String> name;
  final Value<String> properties;
  final Value<String?> recoveryConfig;
  final Value<String?> parentNodeId;
  final Value<int> orderIndex;
  final Value<bool> isEnabled;
  const SequenceNodesCompanion({
    this.id = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.sequenceId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.nodeType = const Value.absent(),
    this.specificType = const Value.absent(),
    this.name = const Value.absent(),
    this.properties = const Value.absent(),
    this.recoveryConfig = const Value.absent(),
    this.parentNodeId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.isEnabled = const Value.absent(),
  });
  SequenceNodesCompanion.insert({
    this.id = const Value.absent(),
    required String nodeId,
    required int sequenceId,
    this.targetId = const Value.absent(),
    required String nodeType,
    required String specificType,
    required String name,
    this.properties = const Value.absent(),
    this.recoveryConfig = const Value.absent(),
    this.parentNodeId = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.isEnabled = const Value.absent(),
  })  : nodeId = Value(nodeId),
        sequenceId = Value(sequenceId),
        nodeType = Value(nodeType),
        specificType = Value(specificType),
        name = Value(name);
  static Insertable<SequenceNode> custom({
    Expression<int>? id,
    Expression<String>? nodeId,
    Expression<int>? sequenceId,
    Expression<int>? targetId,
    Expression<String>? nodeType,
    Expression<String>? specificType,
    Expression<String>? name,
    Expression<String>? properties,
    Expression<String>? recoveryConfig,
    Expression<String>? parentNodeId,
    Expression<int>? orderIndex,
    Expression<bool>? isEnabled,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nodeId != null) 'node_id': nodeId,
      if (sequenceId != null) 'sequence_id': sequenceId,
      if (targetId != null) 'target_id': targetId,
      if (nodeType != null) 'node_type': nodeType,
      if (specificType != null) 'specific_type': specificType,
      if (name != null) 'name': name,
      if (properties != null) 'properties': properties,
      if (recoveryConfig != null) 'recovery_config': recoveryConfig,
      if (parentNodeId != null) 'parent_node_id': parentNodeId,
      if (orderIndex != null) 'order_index': orderIndex,
      if (isEnabled != null) 'is_enabled': isEnabled,
    });
  }

  SequenceNodesCompanion copyWith(
      {Value<int>? id,
      Value<String>? nodeId,
      Value<int>? sequenceId,
      Value<int?>? targetId,
      Value<String>? nodeType,
      Value<String>? specificType,
      Value<String>? name,
      Value<String>? properties,
      Value<String?>? recoveryConfig,
      Value<String?>? parentNodeId,
      Value<int>? orderIndex,
      Value<bool>? isEnabled}) {
    return SequenceNodesCompanion(
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      sequenceId: sequenceId ?? this.sequenceId,
      targetId: targetId ?? this.targetId,
      nodeType: nodeType ?? this.nodeType,
      specificType: specificType ?? this.specificType,
      name: name ?? this.name,
      properties: properties ?? this.properties,
      recoveryConfig: recoveryConfig ?? this.recoveryConfig,
      parentNodeId: parentNodeId ?? this.parentNodeId,
      orderIndex: orderIndex ?? this.orderIndex,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (sequenceId.present) {
      map['sequence_id'] = Variable<int>(sequenceId.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<int>(targetId.value);
    }
    if (nodeType.present) {
      map['node_type'] = Variable<String>(nodeType.value);
    }
    if (specificType.present) {
      map['specific_type'] = Variable<String>(specificType.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (properties.present) {
      map['properties'] = Variable<String>(properties.value);
    }
    if (recoveryConfig.present) {
      map['recovery_config'] = Variable<String>(recoveryConfig.value);
    }
    if (parentNodeId.present) {
      map['parent_node_id'] = Variable<String>(parentNodeId.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (isEnabled.present) {
      map['is_enabled'] = Variable<bool>(isEnabled.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SequenceNodesCompanion(')
          ..write('id: $id, ')
          ..write('nodeId: $nodeId, ')
          ..write('sequenceId: $sequenceId, ')
          ..write('targetId: $targetId, ')
          ..write('nodeType: $nodeType, ')
          ..write('specificType: $specificType, ')
          ..write('name: $name, ')
          ..write('properties: $properties, ')
          ..write('recoveryConfig: $recoveryConfig, ')
          ..write('parentNodeId: $parentNodeId, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('isEnabled: $isEnabled')
          ..write(')'))
        .toString();
  }
}

class $SequenceCheckpointsTable extends SequenceCheckpoints
    with TableInfo<$SequenceCheckpointsTable, SequenceCheckpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SequenceCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sequenceIdMeta =
      const VerificationMeta('sequenceId');
  @override
  late final GeneratedColumn<int> sequenceId = GeneratedColumn<int>(
      'sequence_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES sequences (id) ON DELETE CASCADE'));
  static const VerificationMeta _currentNodeIdMeta =
      const VerificationMeta('currentNodeId');
  @override
  late final GeneratedColumn<String> currentNodeId = GeneratedColumn<String>(
      'current_node_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _stateJsonMeta =
      const VerificationMeta('stateJson');
  @override
  late final GeneratedColumn<String> stateJson = GeneratedColumn<String>(
      'state_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _completedFramesMeta =
      const VerificationMeta('completedFrames');
  @override
  late final GeneratedColumn<int> completedFrames = GeneratedColumn<int>(
      'completed_frames', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _totalFramesMeta =
      const VerificationMeta('totalFrames');
  @override
  late final GeneratedColumn<int> totalFrames = GeneratedColumn<int>(
      'total_frames', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _currentTargetIndexMeta =
      const VerificationMeta('currentTargetIndex');
  @override
  late final GeneratedColumn<int> currentTargetIndex = GeneratedColumn<int>(
      'current_target_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _checkpointedAtMeta =
      const VerificationMeta('checkpointedAt');
  @override
  late final GeneratedColumn<DateTime> checkpointedAt =
      GeneratedColumn<DateTime>('checkpointed_at', aliasedName, false,
          type: DriftSqlType.dateTime,
          requiredDuringInsert: false,
          defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        sequenceId,
        currentNodeId,
        stateJson,
        completedFrames,
        totalFrames,
        currentTargetIndex,
        checkpointedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sequence_checkpoints';
  @override
  VerificationContext validateIntegrity(Insertable<SequenceCheckpoint> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sequence_id')) {
      context.handle(
          _sequenceIdMeta,
          sequenceId.isAcceptableOrUnknown(
              data['sequence_id']!, _sequenceIdMeta));
    }
    if (data.containsKey('current_node_id')) {
      context.handle(
          _currentNodeIdMeta,
          currentNodeId.isAcceptableOrUnknown(
              data['current_node_id']!, _currentNodeIdMeta));
    } else if (isInserting) {
      context.missing(_currentNodeIdMeta);
    }
    if (data.containsKey('state_json')) {
      context.handle(_stateJsonMeta,
          stateJson.isAcceptableOrUnknown(data['state_json']!, _stateJsonMeta));
    } else if (isInserting) {
      context.missing(_stateJsonMeta);
    }
    if (data.containsKey('completed_frames')) {
      context.handle(
          _completedFramesMeta,
          completedFrames.isAcceptableOrUnknown(
              data['completed_frames']!, _completedFramesMeta));
    } else if (isInserting) {
      context.missing(_completedFramesMeta);
    }
    if (data.containsKey('total_frames')) {
      context.handle(
          _totalFramesMeta,
          totalFrames.isAcceptableOrUnknown(
              data['total_frames']!, _totalFramesMeta));
    } else if (isInserting) {
      context.missing(_totalFramesMeta);
    }
    if (data.containsKey('current_target_index')) {
      context.handle(
          _currentTargetIndexMeta,
          currentTargetIndex.isAcceptableOrUnknown(
              data['current_target_index']!, _currentTargetIndexMeta));
    } else if (isInserting) {
      context.missing(_currentTargetIndexMeta);
    }
    if (data.containsKey('checkpointed_at')) {
      context.handle(
          _checkpointedAtMeta,
          checkpointedAt.isAcceptableOrUnknown(
              data['checkpointed_at']!, _checkpointedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sequenceId};
  @override
  SequenceCheckpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SequenceCheckpoint(
      sequenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sequence_id'])!,
      currentNodeId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}current_node_id'])!,
      stateJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state_json'])!,
      completedFrames: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}completed_frames'])!,
      totalFrames: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_frames'])!,
      currentTargetIndex: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}current_target_index'])!,
      checkpointedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}checkpointed_at'])!,
    );
  }

  @override
  $SequenceCheckpointsTable createAlias(String alias) {
    return $SequenceCheckpointsTable(attachedDatabase, alias);
  }
}

class SequenceCheckpoint extends DataClass
    implements Insertable<SequenceCheckpoint> {
  final int sequenceId;
  final String currentNodeId;
  final String stateJson;
  final int completedFrames;
  final int totalFrames;
  final int currentTargetIndex;
  final DateTime checkpointedAt;
  const SequenceCheckpoint(
      {required this.sequenceId,
      required this.currentNodeId,
      required this.stateJson,
      required this.completedFrames,
      required this.totalFrames,
      required this.currentTargetIndex,
      required this.checkpointedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sequence_id'] = Variable<int>(sequenceId);
    map['current_node_id'] = Variable<String>(currentNodeId);
    map['state_json'] = Variable<String>(stateJson);
    map['completed_frames'] = Variable<int>(completedFrames);
    map['total_frames'] = Variable<int>(totalFrames);
    map['current_target_index'] = Variable<int>(currentTargetIndex);
    map['checkpointed_at'] = Variable<DateTime>(checkpointedAt);
    return map;
  }

  SequenceCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return SequenceCheckpointsCompanion(
      sequenceId: Value(sequenceId),
      currentNodeId: Value(currentNodeId),
      stateJson: Value(stateJson),
      completedFrames: Value(completedFrames),
      totalFrames: Value(totalFrames),
      currentTargetIndex: Value(currentTargetIndex),
      checkpointedAt: Value(checkpointedAt),
    );
  }

  factory SequenceCheckpoint.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SequenceCheckpoint(
      sequenceId: serializer.fromJson<int>(json['sequenceId']),
      currentNodeId: serializer.fromJson<String>(json['currentNodeId']),
      stateJson: serializer.fromJson<String>(json['stateJson']),
      completedFrames: serializer.fromJson<int>(json['completedFrames']),
      totalFrames: serializer.fromJson<int>(json['totalFrames']),
      currentTargetIndex: serializer.fromJson<int>(json['currentTargetIndex']),
      checkpointedAt: serializer.fromJson<DateTime>(json['checkpointedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sequenceId': serializer.toJson<int>(sequenceId),
      'currentNodeId': serializer.toJson<String>(currentNodeId),
      'stateJson': serializer.toJson<String>(stateJson),
      'completedFrames': serializer.toJson<int>(completedFrames),
      'totalFrames': serializer.toJson<int>(totalFrames),
      'currentTargetIndex': serializer.toJson<int>(currentTargetIndex),
      'checkpointedAt': serializer.toJson<DateTime>(checkpointedAt),
    };
  }

  SequenceCheckpoint copyWith(
          {int? sequenceId,
          String? currentNodeId,
          String? stateJson,
          int? completedFrames,
          int? totalFrames,
          int? currentTargetIndex,
          DateTime? checkpointedAt}) =>
      SequenceCheckpoint(
        sequenceId: sequenceId ?? this.sequenceId,
        currentNodeId: currentNodeId ?? this.currentNodeId,
        stateJson: stateJson ?? this.stateJson,
        completedFrames: completedFrames ?? this.completedFrames,
        totalFrames: totalFrames ?? this.totalFrames,
        currentTargetIndex: currentTargetIndex ?? this.currentTargetIndex,
        checkpointedAt: checkpointedAt ?? this.checkpointedAt,
      );
  SequenceCheckpoint copyWithCompanion(SequenceCheckpointsCompanion data) {
    return SequenceCheckpoint(
      sequenceId:
          data.sequenceId.present ? data.sequenceId.value : this.sequenceId,
      currentNodeId: data.currentNodeId.present
          ? data.currentNodeId.value
          : this.currentNodeId,
      stateJson: data.stateJson.present ? data.stateJson.value : this.stateJson,
      completedFrames: data.completedFrames.present
          ? data.completedFrames.value
          : this.completedFrames,
      totalFrames:
          data.totalFrames.present ? data.totalFrames.value : this.totalFrames,
      currentTargetIndex: data.currentTargetIndex.present
          ? data.currentTargetIndex.value
          : this.currentTargetIndex,
      checkpointedAt: data.checkpointedAt.present
          ? data.checkpointedAt.value
          : this.checkpointedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SequenceCheckpoint(')
          ..write('sequenceId: $sequenceId, ')
          ..write('currentNodeId: $currentNodeId, ')
          ..write('stateJson: $stateJson, ')
          ..write('completedFrames: $completedFrames, ')
          ..write('totalFrames: $totalFrames, ')
          ..write('currentTargetIndex: $currentTargetIndex, ')
          ..write('checkpointedAt: $checkpointedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sequenceId, currentNodeId, stateJson,
      completedFrames, totalFrames, currentTargetIndex, checkpointedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SequenceCheckpoint &&
          other.sequenceId == this.sequenceId &&
          other.currentNodeId == this.currentNodeId &&
          other.stateJson == this.stateJson &&
          other.completedFrames == this.completedFrames &&
          other.totalFrames == this.totalFrames &&
          other.currentTargetIndex == this.currentTargetIndex &&
          other.checkpointedAt == this.checkpointedAt);
}

class SequenceCheckpointsCompanion extends UpdateCompanion<SequenceCheckpoint> {
  final Value<int> sequenceId;
  final Value<String> currentNodeId;
  final Value<String> stateJson;
  final Value<int> completedFrames;
  final Value<int> totalFrames;
  final Value<int> currentTargetIndex;
  final Value<DateTime> checkpointedAt;
  const SequenceCheckpointsCompanion({
    this.sequenceId = const Value.absent(),
    this.currentNodeId = const Value.absent(),
    this.stateJson = const Value.absent(),
    this.completedFrames = const Value.absent(),
    this.totalFrames = const Value.absent(),
    this.currentTargetIndex = const Value.absent(),
    this.checkpointedAt = const Value.absent(),
  });
  SequenceCheckpointsCompanion.insert({
    this.sequenceId = const Value.absent(),
    required String currentNodeId,
    required String stateJson,
    required int completedFrames,
    required int totalFrames,
    required int currentTargetIndex,
    this.checkpointedAt = const Value.absent(),
  })  : currentNodeId = Value(currentNodeId),
        stateJson = Value(stateJson),
        completedFrames = Value(completedFrames),
        totalFrames = Value(totalFrames),
        currentTargetIndex = Value(currentTargetIndex);
  static Insertable<SequenceCheckpoint> custom({
    Expression<int>? sequenceId,
    Expression<String>? currentNodeId,
    Expression<String>? stateJson,
    Expression<int>? completedFrames,
    Expression<int>? totalFrames,
    Expression<int>? currentTargetIndex,
    Expression<DateTime>? checkpointedAt,
  }) {
    return RawValuesInsertable({
      if (sequenceId != null) 'sequence_id': sequenceId,
      if (currentNodeId != null) 'current_node_id': currentNodeId,
      if (stateJson != null) 'state_json': stateJson,
      if (completedFrames != null) 'completed_frames': completedFrames,
      if (totalFrames != null) 'total_frames': totalFrames,
      if (currentTargetIndex != null)
        'current_target_index': currentTargetIndex,
      if (checkpointedAt != null) 'checkpointed_at': checkpointedAt,
    });
  }

  SequenceCheckpointsCompanion copyWith(
      {Value<int>? sequenceId,
      Value<String>? currentNodeId,
      Value<String>? stateJson,
      Value<int>? completedFrames,
      Value<int>? totalFrames,
      Value<int>? currentTargetIndex,
      Value<DateTime>? checkpointedAt}) {
    return SequenceCheckpointsCompanion(
      sequenceId: sequenceId ?? this.sequenceId,
      currentNodeId: currentNodeId ?? this.currentNodeId,
      stateJson: stateJson ?? this.stateJson,
      completedFrames: completedFrames ?? this.completedFrames,
      totalFrames: totalFrames ?? this.totalFrames,
      currentTargetIndex: currentTargetIndex ?? this.currentTargetIndex,
      checkpointedAt: checkpointedAt ?? this.checkpointedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sequenceId.present) {
      map['sequence_id'] = Variable<int>(sequenceId.value);
    }
    if (currentNodeId.present) {
      map['current_node_id'] = Variable<String>(currentNodeId.value);
    }
    if (stateJson.present) {
      map['state_json'] = Variable<String>(stateJson.value);
    }
    if (completedFrames.present) {
      map['completed_frames'] = Variable<int>(completedFrames.value);
    }
    if (totalFrames.present) {
      map['total_frames'] = Variable<int>(totalFrames.value);
    }
    if (currentTargetIndex.present) {
      map['current_target_index'] = Variable<int>(currentTargetIndex.value);
    }
    if (checkpointedAt.present) {
      map['checkpointed_at'] = Variable<DateTime>(checkpointedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SequenceCheckpointsCompanion(')
          ..write('sequenceId: $sequenceId, ')
          ..write('currentNodeId: $currentNodeId, ')
          ..write('stateJson: $stateJson, ')
          ..write('completedFrames: $completedFrames, ')
          ..write('totalFrames: $totalFrames, ')
          ..write('currentTargetIndex: $currentTargetIndex, ')
          ..write('checkpointedAt: $checkpointedAt')
          ..write(')'))
        .toString();
  }
}

class $CapturedImagesTable extends CapturedImages
    with TableInfo<$CapturedImagesTable, CapturedImage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CapturedImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileNameMeta =
      const VerificationMeta('fileName');
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
      'file_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileFormatMeta =
      const VerificationMeta('fileFormat');
  @override
  late final GeneratedColumn<String> fileFormat = GeneratedColumn<String>(
      'file_format', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('fits'));
  static const VerificationMeta _fileSizeMeta =
      const VerificationMeta('fileSize');
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
      'file_size', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sessionIdMeta =
      const VerificationMeta('sessionId');
  @override
  late final GeneratedColumn<int> sessionId = GeneratedColumn<int>(
      'session_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES imaging_sessions (id) ON DELETE CASCADE'));
  static const VerificationMeta _targetIdMeta =
      const VerificationMeta('targetId');
  @override
  late final GeneratedColumn<int> targetId = GeneratedColumn<int>(
      'target_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES targets (id) ON DELETE SET NULL'));
  static const VerificationMeta _frameTypeMeta =
      const VerificationMeta('frameType');
  @override
  late final GeneratedColumn<String> frameType = GeneratedColumn<String>(
      'frame_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('light'));
  static const VerificationMeta _exposureDurationMeta =
      const VerificationMeta('exposureDuration');
  @override
  late final GeneratedColumn<double> exposureDuration = GeneratedColumn<double>(
      'exposure_duration', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _gainMeta = const VerificationMeta('gain');
  @override
  late final GeneratedColumn<int> gain = GeneratedColumn<int>(
      'gain', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _offsetMeta = const VerificationMeta('offset');
  @override
  late final GeneratedColumn<int> offset = GeneratedColumn<int>(
      'offset', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _binXMeta = const VerificationMeta('binX');
  @override
  late final GeneratedColumn<int> binX = GeneratedColumn<int>(
      'bin_x', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _binYMeta = const VerificationMeta('binY');
  @override
  late final GeneratedColumn<int> binY = GeneratedColumn<int>(
      'bin_y', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _filterMeta = const VerificationMeta('filter');
  @override
  late final GeneratedColumn<String> filter = GeneratedColumn<String>(
      'filter', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sensorTempMeta =
      const VerificationMeta('sensorTemp');
  @override
  late final GeneratedColumn<double> sensorTemp = GeneratedColumn<double>(
      'sensor_temp', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _coolerPowerMeta =
      const VerificationMeta('coolerPower');
  @override
  late final GeneratedColumn<double> coolerPower = GeneratedColumn<double>(
      'cooler_power', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _hfrMeta = const VerificationMeta('hfr');
  @override
  late final GeneratedColumn<double> hfr = GeneratedColumn<double>(
      'hfr', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _starCountMeta =
      const VerificationMeta('starCount');
  @override
  late final GeneratedColumn<int> starCount = GeneratedColumn<int>(
      'star_count', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _backgroundMeta =
      const VerificationMeta('background');
  @override
  late final GeneratedColumn<double> background = GeneratedColumn<double>(
      'background', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _noiseMeta = const VerificationMeta('noise');
  @override
  late final GeneratedColumn<double> noise = GeneratedColumn<double>(
      'noise', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _qualityScoreMeta =
      const VerificationMeta('qualityScore');
  @override
  late final GeneratedColumn<double> qualityScore = GeneratedColumn<double>(
      'quality_score', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _guidingRmsRaMeta =
      const VerificationMeta('guidingRmsRa');
  @override
  late final GeneratedColumn<double> guidingRmsRa = GeneratedColumn<double>(
      'guiding_rms_ra', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _guidingRmsDecMeta =
      const VerificationMeta('guidingRmsDec');
  @override
  late final GeneratedColumn<double> guidingRmsDec = GeneratedColumn<double>(
      'guiding_rms_dec', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _guidingRmsTotalMeta =
      const VerificationMeta('guidingRmsTotal');
  @override
  late final GeneratedColumn<double> guidingRmsTotal = GeneratedColumn<double>(
      'guiding_rms_total', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _mountRaMeta =
      const VerificationMeta('mountRa');
  @override
  late final GeneratedColumn<double> mountRa = GeneratedColumn<double>(
      'mount_ra', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _mountDecMeta =
      const VerificationMeta('mountDec');
  @override
  late final GeneratedColumn<double> mountDec = GeneratedColumn<double>(
      'mount_dec', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _mountAltitudeMeta =
      const VerificationMeta('mountAltitude');
  @override
  late final GeneratedColumn<double> mountAltitude = GeneratedColumn<double>(
      'mount_altitude', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _mountAzimuthMeta =
      const VerificationMeta('mountAzimuth');
  @override
  late final GeneratedColumn<double> mountAzimuth = GeneratedColumn<double>(
      'mount_azimuth', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _pierSideMeta =
      const VerificationMeta('pierSide');
  @override
  late final GeneratedColumn<String> pierSide = GeneratedColumn<String>(
      'pier_side', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _focuserPositionMeta =
      const VerificationMeta('focuserPosition');
  @override
  late final GeneratedColumn<int> focuserPosition = GeneratedColumn<int>(
      'focuser_position', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _focuserTempMeta =
      const VerificationMeta('focuserTemp');
  @override
  late final GeneratedColumn<double> focuserTemp = GeneratedColumn<double>(
      'focuser_temp', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _rotatorAngleMeta =
      const VerificationMeta('rotatorAngle');
  @override
  late final GeneratedColumn<double> rotatorAngle = GeneratedColumn<double>(
      'rotator_angle', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _isPlateSolvedMeta =
      const VerificationMeta('isPlateSolved');
  @override
  late final GeneratedColumn<bool> isPlateSolved = GeneratedColumn<bool>(
      'is_plate_solved', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_plate_solved" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _solvedRaMeta =
      const VerificationMeta('solvedRa');
  @override
  late final GeneratedColumn<double> solvedRa = GeneratedColumn<double>(
      'solved_ra', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _solvedDecMeta =
      const VerificationMeta('solvedDec');
  @override
  late final GeneratedColumn<double> solvedDec = GeneratedColumn<double>(
      'solved_dec', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _solvedRotationMeta =
      const VerificationMeta('solvedRotation');
  @override
  late final GeneratedColumn<double> solvedRotation = GeneratedColumn<double>(
      'solved_rotation', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _solvedPixelScaleMeta =
      const VerificationMeta('solvedPixelScale');
  @override
  late final GeneratedColumn<double> solvedPixelScale = GeneratedColumn<double>(
      'solved_pixel_scale', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _capturedAtMeta =
      const VerificationMeta('capturedAt');
  @override
  late final GeneratedColumn<DateTime> capturedAt = GeneratedColumn<DateTime>(
      'captured_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _isAcceptedMeta =
      const VerificationMeta('isAccepted');
  @override
  late final GeneratedColumn<bool> isAccepted = GeneratedColumn<bool>(
      'is_accepted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_accepted" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _rejectionReasonMeta =
      const VerificationMeta('rejectionReason');
  @override
  late final GeneratedColumn<String> rejectionReason = GeneratedColumn<String>(
      'rejection_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        filePath,
        fileName,
        fileFormat,
        fileSize,
        sessionId,
        targetId,
        frameType,
        exposureDuration,
        gain,
        offset,
        binX,
        binY,
        filter,
        sensorTemp,
        coolerPower,
        hfr,
        starCount,
        background,
        noise,
        qualityScore,
        guidingRmsRa,
        guidingRmsDec,
        guidingRmsTotal,
        mountRa,
        mountDec,
        mountAltitude,
        mountAzimuth,
        pierSide,
        focuserPosition,
        focuserTemp,
        rotatorAngle,
        isPlateSolved,
        solvedRa,
        solvedDec,
        solvedRotation,
        solvedPixelScale,
        capturedAt,
        createdAt,
        isAccepted,
        rejectionReason
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'captured_images';
  @override
  VerificationContext validateIntegrity(Insertable<CapturedImage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(_fileNameMeta,
          fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta));
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('file_format')) {
      context.handle(
          _fileFormatMeta,
          fileFormat.isAcceptableOrUnknown(
              data['file_format']!, _fileFormatMeta));
    }
    if (data.containsKey('file_size')) {
      context.handle(_fileSizeMeta,
          fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(_sessionIdMeta,
          sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta));
    }
    if (data.containsKey('target_id')) {
      context.handle(_targetIdMeta,
          targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta));
    }
    if (data.containsKey('frame_type')) {
      context.handle(_frameTypeMeta,
          frameType.isAcceptableOrUnknown(data['frame_type']!, _frameTypeMeta));
    }
    if (data.containsKey('exposure_duration')) {
      context.handle(
          _exposureDurationMeta,
          exposureDuration.isAcceptableOrUnknown(
              data['exposure_duration']!, _exposureDurationMeta));
    } else if (isInserting) {
      context.missing(_exposureDurationMeta);
    }
    if (data.containsKey('gain')) {
      context.handle(
          _gainMeta, gain.isAcceptableOrUnknown(data['gain']!, _gainMeta));
    }
    if (data.containsKey('offset')) {
      context.handle(_offsetMeta,
          offset.isAcceptableOrUnknown(data['offset']!, _offsetMeta));
    }
    if (data.containsKey('bin_x')) {
      context.handle(
          _binXMeta, binX.isAcceptableOrUnknown(data['bin_x']!, _binXMeta));
    }
    if (data.containsKey('bin_y')) {
      context.handle(
          _binYMeta, binY.isAcceptableOrUnknown(data['bin_y']!, _binYMeta));
    }
    if (data.containsKey('filter')) {
      context.handle(_filterMeta,
          filter.isAcceptableOrUnknown(data['filter']!, _filterMeta));
    }
    if (data.containsKey('sensor_temp')) {
      context.handle(
          _sensorTempMeta,
          sensorTemp.isAcceptableOrUnknown(
              data['sensor_temp']!, _sensorTempMeta));
    }
    if (data.containsKey('cooler_power')) {
      context.handle(
          _coolerPowerMeta,
          coolerPower.isAcceptableOrUnknown(
              data['cooler_power']!, _coolerPowerMeta));
    }
    if (data.containsKey('hfr')) {
      context.handle(
          _hfrMeta, hfr.isAcceptableOrUnknown(data['hfr']!, _hfrMeta));
    }
    if (data.containsKey('star_count')) {
      context.handle(_starCountMeta,
          starCount.isAcceptableOrUnknown(data['star_count']!, _starCountMeta));
    }
    if (data.containsKey('background')) {
      context.handle(
          _backgroundMeta,
          background.isAcceptableOrUnknown(
              data['background']!, _backgroundMeta));
    }
    if (data.containsKey('noise')) {
      context.handle(
          _noiseMeta, noise.isAcceptableOrUnknown(data['noise']!, _noiseMeta));
    }
    if (data.containsKey('quality_score')) {
      context.handle(
          _qualityScoreMeta,
          qualityScore.isAcceptableOrUnknown(
              data['quality_score']!, _qualityScoreMeta));
    }
    if (data.containsKey('guiding_rms_ra')) {
      context.handle(
          _guidingRmsRaMeta,
          guidingRmsRa.isAcceptableOrUnknown(
              data['guiding_rms_ra']!, _guidingRmsRaMeta));
    }
    if (data.containsKey('guiding_rms_dec')) {
      context.handle(
          _guidingRmsDecMeta,
          guidingRmsDec.isAcceptableOrUnknown(
              data['guiding_rms_dec']!, _guidingRmsDecMeta));
    }
    if (data.containsKey('guiding_rms_total')) {
      context.handle(
          _guidingRmsTotalMeta,
          guidingRmsTotal.isAcceptableOrUnknown(
              data['guiding_rms_total']!, _guidingRmsTotalMeta));
    }
    if (data.containsKey('mount_ra')) {
      context.handle(_mountRaMeta,
          mountRa.isAcceptableOrUnknown(data['mount_ra']!, _mountRaMeta));
    }
    if (data.containsKey('mount_dec')) {
      context.handle(_mountDecMeta,
          mountDec.isAcceptableOrUnknown(data['mount_dec']!, _mountDecMeta));
    }
    if (data.containsKey('mount_altitude')) {
      context.handle(
          _mountAltitudeMeta,
          mountAltitude.isAcceptableOrUnknown(
              data['mount_altitude']!, _mountAltitudeMeta));
    }
    if (data.containsKey('mount_azimuth')) {
      context.handle(
          _mountAzimuthMeta,
          mountAzimuth.isAcceptableOrUnknown(
              data['mount_azimuth']!, _mountAzimuthMeta));
    }
    if (data.containsKey('pier_side')) {
      context.handle(_pierSideMeta,
          pierSide.isAcceptableOrUnknown(data['pier_side']!, _pierSideMeta));
    }
    if (data.containsKey('focuser_position')) {
      context.handle(
          _focuserPositionMeta,
          focuserPosition.isAcceptableOrUnknown(
              data['focuser_position']!, _focuserPositionMeta));
    }
    if (data.containsKey('focuser_temp')) {
      context.handle(
          _focuserTempMeta,
          focuserTemp.isAcceptableOrUnknown(
              data['focuser_temp']!, _focuserTempMeta));
    }
    if (data.containsKey('rotator_angle')) {
      context.handle(
          _rotatorAngleMeta,
          rotatorAngle.isAcceptableOrUnknown(
              data['rotator_angle']!, _rotatorAngleMeta));
    }
    if (data.containsKey('is_plate_solved')) {
      context.handle(
          _isPlateSolvedMeta,
          isPlateSolved.isAcceptableOrUnknown(
              data['is_plate_solved']!, _isPlateSolvedMeta));
    }
    if (data.containsKey('solved_ra')) {
      context.handle(_solvedRaMeta,
          solvedRa.isAcceptableOrUnknown(data['solved_ra']!, _solvedRaMeta));
    }
    if (data.containsKey('solved_dec')) {
      context.handle(_solvedDecMeta,
          solvedDec.isAcceptableOrUnknown(data['solved_dec']!, _solvedDecMeta));
    }
    if (data.containsKey('solved_rotation')) {
      context.handle(
          _solvedRotationMeta,
          solvedRotation.isAcceptableOrUnknown(
              data['solved_rotation']!, _solvedRotationMeta));
    }
    if (data.containsKey('solved_pixel_scale')) {
      context.handle(
          _solvedPixelScaleMeta,
          solvedPixelScale.isAcceptableOrUnknown(
              data['solved_pixel_scale']!, _solvedPixelScaleMeta));
    }
    if (data.containsKey('captured_at')) {
      context.handle(
          _capturedAtMeta,
          capturedAt.isAcceptableOrUnknown(
              data['captured_at']!, _capturedAtMeta));
    } else if (isInserting) {
      context.missing(_capturedAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('is_accepted')) {
      context.handle(
          _isAcceptedMeta,
          isAccepted.isAcceptableOrUnknown(
              data['is_accepted']!, _isAcceptedMeta));
    }
    if (data.containsKey('rejection_reason')) {
      context.handle(
          _rejectionReasonMeta,
          rejectionReason.isAcceptableOrUnknown(
              data['rejection_reason']!, _rejectionReasonMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CapturedImage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CapturedImage(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      fileName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_name'])!,
      fileFormat: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_format'])!,
      fileSize: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}file_size']),
      sessionId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}session_id']),
      targetId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}target_id']),
      frameType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}frame_type'])!,
      exposureDuration: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}exposure_duration'])!,
      gain: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}gain']),
      offset: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}offset']),
      binX: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bin_x'])!,
      binY: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bin_y'])!,
      filter: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filter']),
      sensorTemp: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}sensor_temp']),
      coolerPower: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}cooler_power']),
      hfr: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}hfr']),
      starCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}star_count']),
      background: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}background']),
      noise: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}noise']),
      qualityScore: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}quality_score']),
      guidingRmsRa: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}guiding_rms_ra']),
      guidingRmsDec: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}guiding_rms_dec']),
      guidingRmsTotal: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}guiding_rms_total']),
      mountRa: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}mount_ra']),
      mountDec: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}mount_dec']),
      mountAltitude: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}mount_altitude']),
      mountAzimuth: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}mount_azimuth']),
      pierSide: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pier_side']),
      focuserPosition: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}focuser_position']),
      focuserTemp: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}focuser_temp']),
      rotatorAngle: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}rotator_angle']),
      isPlateSolved: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_plate_solved'])!,
      solvedRa: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}solved_ra']),
      solvedDec: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}solved_dec']),
      solvedRotation: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}solved_rotation']),
      solvedPixelScale: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}solved_pixel_scale']),
      capturedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}captured_at'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      isAccepted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_accepted'])!,
      rejectionReason: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}rejection_reason']),
    );
  }

  @override
  $CapturedImagesTable createAlias(String alias) {
    return $CapturedImagesTable(attachedDatabase, alias);
  }
}

class CapturedImage extends DataClass implements Insertable<CapturedImage> {
  final int id;
  final String filePath;
  final String fileName;
  final String fileFormat;
  final int? fileSize;
  final int? sessionId;
  final int? targetId;
  final String frameType;
  final double exposureDuration;
  final int? gain;
  final int? offset;
  final int binX;
  final int binY;
  final String? filter;
  final double? sensorTemp;
  final double? coolerPower;
  final double? hfr;
  final int? starCount;
  final double? background;
  final double? noise;
  final double? qualityScore;
  final double? guidingRmsRa;
  final double? guidingRmsDec;
  final double? guidingRmsTotal;
  final double? mountRa;
  final double? mountDec;
  final double? mountAltitude;
  final double? mountAzimuth;
  final String? pierSide;
  final int? focuserPosition;
  final double? focuserTemp;
  final double? rotatorAngle;
  final bool isPlateSolved;
  final double? solvedRa;
  final double? solvedDec;
  final double? solvedRotation;
  final double? solvedPixelScale;
  final DateTime capturedAt;
  final DateTime createdAt;
  final bool isAccepted;
  final String? rejectionReason;
  const CapturedImage(
      {required this.id,
      required this.filePath,
      required this.fileName,
      required this.fileFormat,
      this.fileSize,
      this.sessionId,
      this.targetId,
      required this.frameType,
      required this.exposureDuration,
      this.gain,
      this.offset,
      required this.binX,
      required this.binY,
      this.filter,
      this.sensorTemp,
      this.coolerPower,
      this.hfr,
      this.starCount,
      this.background,
      this.noise,
      this.qualityScore,
      this.guidingRmsRa,
      this.guidingRmsDec,
      this.guidingRmsTotal,
      this.mountRa,
      this.mountDec,
      this.mountAltitude,
      this.mountAzimuth,
      this.pierSide,
      this.focuserPosition,
      this.focuserTemp,
      this.rotatorAngle,
      required this.isPlateSolved,
      this.solvedRa,
      this.solvedDec,
      this.solvedRotation,
      this.solvedPixelScale,
      required this.capturedAt,
      required this.createdAt,
      required this.isAccepted,
      this.rejectionReason});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['file_path'] = Variable<String>(filePath);
    map['file_name'] = Variable<String>(fileName);
    map['file_format'] = Variable<String>(fileFormat);
    if (!nullToAbsent || fileSize != null) {
      map['file_size'] = Variable<int>(fileSize);
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<int>(sessionId);
    }
    if (!nullToAbsent || targetId != null) {
      map['target_id'] = Variable<int>(targetId);
    }
    map['frame_type'] = Variable<String>(frameType);
    map['exposure_duration'] = Variable<double>(exposureDuration);
    if (!nullToAbsent || gain != null) {
      map['gain'] = Variable<int>(gain);
    }
    if (!nullToAbsent || offset != null) {
      map['offset'] = Variable<int>(offset);
    }
    map['bin_x'] = Variable<int>(binX);
    map['bin_y'] = Variable<int>(binY);
    if (!nullToAbsent || filter != null) {
      map['filter'] = Variable<String>(filter);
    }
    if (!nullToAbsent || sensorTemp != null) {
      map['sensor_temp'] = Variable<double>(sensorTemp);
    }
    if (!nullToAbsent || coolerPower != null) {
      map['cooler_power'] = Variable<double>(coolerPower);
    }
    if (!nullToAbsent || hfr != null) {
      map['hfr'] = Variable<double>(hfr);
    }
    if (!nullToAbsent || starCount != null) {
      map['star_count'] = Variable<int>(starCount);
    }
    if (!nullToAbsent || background != null) {
      map['background'] = Variable<double>(background);
    }
    if (!nullToAbsent || noise != null) {
      map['noise'] = Variable<double>(noise);
    }
    if (!nullToAbsent || qualityScore != null) {
      map['quality_score'] = Variable<double>(qualityScore);
    }
    if (!nullToAbsent || guidingRmsRa != null) {
      map['guiding_rms_ra'] = Variable<double>(guidingRmsRa);
    }
    if (!nullToAbsent || guidingRmsDec != null) {
      map['guiding_rms_dec'] = Variable<double>(guidingRmsDec);
    }
    if (!nullToAbsent || guidingRmsTotal != null) {
      map['guiding_rms_total'] = Variable<double>(guidingRmsTotal);
    }
    if (!nullToAbsent || mountRa != null) {
      map['mount_ra'] = Variable<double>(mountRa);
    }
    if (!nullToAbsent || mountDec != null) {
      map['mount_dec'] = Variable<double>(mountDec);
    }
    if (!nullToAbsent || mountAltitude != null) {
      map['mount_altitude'] = Variable<double>(mountAltitude);
    }
    if (!nullToAbsent || mountAzimuth != null) {
      map['mount_azimuth'] = Variable<double>(mountAzimuth);
    }
    if (!nullToAbsent || pierSide != null) {
      map['pier_side'] = Variable<String>(pierSide);
    }
    if (!nullToAbsent || focuserPosition != null) {
      map['focuser_position'] = Variable<int>(focuserPosition);
    }
    if (!nullToAbsent || focuserTemp != null) {
      map['focuser_temp'] = Variable<double>(focuserTemp);
    }
    if (!nullToAbsent || rotatorAngle != null) {
      map['rotator_angle'] = Variable<double>(rotatorAngle);
    }
    map['is_plate_solved'] = Variable<bool>(isPlateSolved);
    if (!nullToAbsent || solvedRa != null) {
      map['solved_ra'] = Variable<double>(solvedRa);
    }
    if (!nullToAbsent || solvedDec != null) {
      map['solved_dec'] = Variable<double>(solvedDec);
    }
    if (!nullToAbsent || solvedRotation != null) {
      map['solved_rotation'] = Variable<double>(solvedRotation);
    }
    if (!nullToAbsent || solvedPixelScale != null) {
      map['solved_pixel_scale'] = Variable<double>(solvedPixelScale);
    }
    map['captured_at'] = Variable<DateTime>(capturedAt);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_accepted'] = Variable<bool>(isAccepted);
    if (!nullToAbsent || rejectionReason != null) {
      map['rejection_reason'] = Variable<String>(rejectionReason);
    }
    return map;
  }

  CapturedImagesCompanion toCompanion(bool nullToAbsent) {
    return CapturedImagesCompanion(
      id: Value(id),
      filePath: Value(filePath),
      fileName: Value(fileName),
      fileFormat: Value(fileFormat),
      fileSize: fileSize == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSize),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      targetId: targetId == null && nullToAbsent
          ? const Value.absent()
          : Value(targetId),
      frameType: Value(frameType),
      exposureDuration: Value(exposureDuration),
      gain: gain == null && nullToAbsent ? const Value.absent() : Value(gain),
      offset:
          offset == null && nullToAbsent ? const Value.absent() : Value(offset),
      binX: Value(binX),
      binY: Value(binY),
      filter:
          filter == null && nullToAbsent ? const Value.absent() : Value(filter),
      sensorTemp: sensorTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(sensorTemp),
      coolerPower: coolerPower == null && nullToAbsent
          ? const Value.absent()
          : Value(coolerPower),
      hfr: hfr == null && nullToAbsent ? const Value.absent() : Value(hfr),
      starCount: starCount == null && nullToAbsent
          ? const Value.absent()
          : Value(starCount),
      background: background == null && nullToAbsent
          ? const Value.absent()
          : Value(background),
      noise:
          noise == null && nullToAbsent ? const Value.absent() : Value(noise),
      qualityScore: qualityScore == null && nullToAbsent
          ? const Value.absent()
          : Value(qualityScore),
      guidingRmsRa: guidingRmsRa == null && nullToAbsent
          ? const Value.absent()
          : Value(guidingRmsRa),
      guidingRmsDec: guidingRmsDec == null && nullToAbsent
          ? const Value.absent()
          : Value(guidingRmsDec),
      guidingRmsTotal: guidingRmsTotal == null && nullToAbsent
          ? const Value.absent()
          : Value(guidingRmsTotal),
      mountRa: mountRa == null && nullToAbsent
          ? const Value.absent()
          : Value(mountRa),
      mountDec: mountDec == null && nullToAbsent
          ? const Value.absent()
          : Value(mountDec),
      mountAltitude: mountAltitude == null && nullToAbsent
          ? const Value.absent()
          : Value(mountAltitude),
      mountAzimuth: mountAzimuth == null && nullToAbsent
          ? const Value.absent()
          : Value(mountAzimuth),
      pierSide: pierSide == null && nullToAbsent
          ? const Value.absent()
          : Value(pierSide),
      focuserPosition: focuserPosition == null && nullToAbsent
          ? const Value.absent()
          : Value(focuserPosition),
      focuserTemp: focuserTemp == null && nullToAbsent
          ? const Value.absent()
          : Value(focuserTemp),
      rotatorAngle: rotatorAngle == null && nullToAbsent
          ? const Value.absent()
          : Value(rotatorAngle),
      isPlateSolved: Value(isPlateSolved),
      solvedRa: solvedRa == null && nullToAbsent
          ? const Value.absent()
          : Value(solvedRa),
      solvedDec: solvedDec == null && nullToAbsent
          ? const Value.absent()
          : Value(solvedDec),
      solvedRotation: solvedRotation == null && nullToAbsent
          ? const Value.absent()
          : Value(solvedRotation),
      solvedPixelScale: solvedPixelScale == null && nullToAbsent
          ? const Value.absent()
          : Value(solvedPixelScale),
      capturedAt: Value(capturedAt),
      createdAt: Value(createdAt),
      isAccepted: Value(isAccepted),
      rejectionReason: rejectionReason == null && nullToAbsent
          ? const Value.absent()
          : Value(rejectionReason),
    );
  }

  factory CapturedImage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CapturedImage(
      id: serializer.fromJson<int>(json['id']),
      filePath: serializer.fromJson<String>(json['filePath']),
      fileName: serializer.fromJson<String>(json['fileName']),
      fileFormat: serializer.fromJson<String>(json['fileFormat']),
      fileSize: serializer.fromJson<int?>(json['fileSize']),
      sessionId: serializer.fromJson<int?>(json['sessionId']),
      targetId: serializer.fromJson<int?>(json['targetId']),
      frameType: serializer.fromJson<String>(json['frameType']),
      exposureDuration: serializer.fromJson<double>(json['exposureDuration']),
      gain: serializer.fromJson<int?>(json['gain']),
      offset: serializer.fromJson<int?>(json['offset']),
      binX: serializer.fromJson<int>(json['binX']),
      binY: serializer.fromJson<int>(json['binY']),
      filter: serializer.fromJson<String?>(json['filter']),
      sensorTemp: serializer.fromJson<double?>(json['sensorTemp']),
      coolerPower: serializer.fromJson<double?>(json['coolerPower']),
      hfr: serializer.fromJson<double?>(json['hfr']),
      starCount: serializer.fromJson<int?>(json['starCount']),
      background: serializer.fromJson<double?>(json['background']),
      noise: serializer.fromJson<double?>(json['noise']),
      qualityScore: serializer.fromJson<double?>(json['qualityScore']),
      guidingRmsRa: serializer.fromJson<double?>(json['guidingRmsRa']),
      guidingRmsDec: serializer.fromJson<double?>(json['guidingRmsDec']),
      guidingRmsTotal: serializer.fromJson<double?>(json['guidingRmsTotal']),
      mountRa: serializer.fromJson<double?>(json['mountRa']),
      mountDec: serializer.fromJson<double?>(json['mountDec']),
      mountAltitude: serializer.fromJson<double?>(json['mountAltitude']),
      mountAzimuth: serializer.fromJson<double?>(json['mountAzimuth']),
      pierSide: serializer.fromJson<String?>(json['pierSide']),
      focuserPosition: serializer.fromJson<int?>(json['focuserPosition']),
      focuserTemp: serializer.fromJson<double?>(json['focuserTemp']),
      rotatorAngle: serializer.fromJson<double?>(json['rotatorAngle']),
      isPlateSolved: serializer.fromJson<bool>(json['isPlateSolved']),
      solvedRa: serializer.fromJson<double?>(json['solvedRa']),
      solvedDec: serializer.fromJson<double?>(json['solvedDec']),
      solvedRotation: serializer.fromJson<double?>(json['solvedRotation']),
      solvedPixelScale: serializer.fromJson<double?>(json['solvedPixelScale']),
      capturedAt: serializer.fromJson<DateTime>(json['capturedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isAccepted: serializer.fromJson<bool>(json['isAccepted']),
      rejectionReason: serializer.fromJson<String?>(json['rejectionReason']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'filePath': serializer.toJson<String>(filePath),
      'fileName': serializer.toJson<String>(fileName),
      'fileFormat': serializer.toJson<String>(fileFormat),
      'fileSize': serializer.toJson<int?>(fileSize),
      'sessionId': serializer.toJson<int?>(sessionId),
      'targetId': serializer.toJson<int?>(targetId),
      'frameType': serializer.toJson<String>(frameType),
      'exposureDuration': serializer.toJson<double>(exposureDuration),
      'gain': serializer.toJson<int?>(gain),
      'offset': serializer.toJson<int?>(offset),
      'binX': serializer.toJson<int>(binX),
      'binY': serializer.toJson<int>(binY),
      'filter': serializer.toJson<String?>(filter),
      'sensorTemp': serializer.toJson<double?>(sensorTemp),
      'coolerPower': serializer.toJson<double?>(coolerPower),
      'hfr': serializer.toJson<double?>(hfr),
      'starCount': serializer.toJson<int?>(starCount),
      'background': serializer.toJson<double?>(background),
      'noise': serializer.toJson<double?>(noise),
      'qualityScore': serializer.toJson<double?>(qualityScore),
      'guidingRmsRa': serializer.toJson<double?>(guidingRmsRa),
      'guidingRmsDec': serializer.toJson<double?>(guidingRmsDec),
      'guidingRmsTotal': serializer.toJson<double?>(guidingRmsTotal),
      'mountRa': serializer.toJson<double?>(mountRa),
      'mountDec': serializer.toJson<double?>(mountDec),
      'mountAltitude': serializer.toJson<double?>(mountAltitude),
      'mountAzimuth': serializer.toJson<double?>(mountAzimuth),
      'pierSide': serializer.toJson<String?>(pierSide),
      'focuserPosition': serializer.toJson<int?>(focuserPosition),
      'focuserTemp': serializer.toJson<double?>(focuserTemp),
      'rotatorAngle': serializer.toJson<double?>(rotatorAngle),
      'isPlateSolved': serializer.toJson<bool>(isPlateSolved),
      'solvedRa': serializer.toJson<double?>(solvedRa),
      'solvedDec': serializer.toJson<double?>(solvedDec),
      'solvedRotation': serializer.toJson<double?>(solvedRotation),
      'solvedPixelScale': serializer.toJson<double?>(solvedPixelScale),
      'capturedAt': serializer.toJson<DateTime>(capturedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isAccepted': serializer.toJson<bool>(isAccepted),
      'rejectionReason': serializer.toJson<String?>(rejectionReason),
    };
  }

  CapturedImage copyWith(
          {int? id,
          String? filePath,
          String? fileName,
          String? fileFormat,
          Value<int?> fileSize = const Value.absent(),
          Value<int?> sessionId = const Value.absent(),
          Value<int?> targetId = const Value.absent(),
          String? frameType,
          double? exposureDuration,
          Value<int?> gain = const Value.absent(),
          Value<int?> offset = const Value.absent(),
          int? binX,
          int? binY,
          Value<String?> filter = const Value.absent(),
          Value<double?> sensorTemp = const Value.absent(),
          Value<double?> coolerPower = const Value.absent(),
          Value<double?> hfr = const Value.absent(),
          Value<int?> starCount = const Value.absent(),
          Value<double?> background = const Value.absent(),
          Value<double?> noise = const Value.absent(),
          Value<double?> qualityScore = const Value.absent(),
          Value<double?> guidingRmsRa = const Value.absent(),
          Value<double?> guidingRmsDec = const Value.absent(),
          Value<double?> guidingRmsTotal = const Value.absent(),
          Value<double?> mountRa = const Value.absent(),
          Value<double?> mountDec = const Value.absent(),
          Value<double?> mountAltitude = const Value.absent(),
          Value<double?> mountAzimuth = const Value.absent(),
          Value<String?> pierSide = const Value.absent(),
          Value<int?> focuserPosition = const Value.absent(),
          Value<double?> focuserTemp = const Value.absent(),
          Value<double?> rotatorAngle = const Value.absent(),
          bool? isPlateSolved,
          Value<double?> solvedRa = const Value.absent(),
          Value<double?> solvedDec = const Value.absent(),
          Value<double?> solvedRotation = const Value.absent(),
          Value<double?> solvedPixelScale = const Value.absent(),
          DateTime? capturedAt,
          DateTime? createdAt,
          bool? isAccepted,
          Value<String?> rejectionReason = const Value.absent()}) =>
      CapturedImage(
        id: id ?? this.id,
        filePath: filePath ?? this.filePath,
        fileName: fileName ?? this.fileName,
        fileFormat: fileFormat ?? this.fileFormat,
        fileSize: fileSize.present ? fileSize.value : this.fileSize,
        sessionId: sessionId.present ? sessionId.value : this.sessionId,
        targetId: targetId.present ? targetId.value : this.targetId,
        frameType: frameType ?? this.frameType,
        exposureDuration: exposureDuration ?? this.exposureDuration,
        gain: gain.present ? gain.value : this.gain,
        offset: offset.present ? offset.value : this.offset,
        binX: binX ?? this.binX,
        binY: binY ?? this.binY,
        filter: filter.present ? filter.value : this.filter,
        sensorTemp: sensorTemp.present ? sensorTemp.value : this.sensorTemp,
        coolerPower: coolerPower.present ? coolerPower.value : this.coolerPower,
        hfr: hfr.present ? hfr.value : this.hfr,
        starCount: starCount.present ? starCount.value : this.starCount,
        background: background.present ? background.value : this.background,
        noise: noise.present ? noise.value : this.noise,
        qualityScore:
            qualityScore.present ? qualityScore.value : this.qualityScore,
        guidingRmsRa:
            guidingRmsRa.present ? guidingRmsRa.value : this.guidingRmsRa,
        guidingRmsDec:
            guidingRmsDec.present ? guidingRmsDec.value : this.guidingRmsDec,
        guidingRmsTotal: guidingRmsTotal.present
            ? guidingRmsTotal.value
            : this.guidingRmsTotal,
        mountRa: mountRa.present ? mountRa.value : this.mountRa,
        mountDec: mountDec.present ? mountDec.value : this.mountDec,
        mountAltitude:
            mountAltitude.present ? mountAltitude.value : this.mountAltitude,
        mountAzimuth:
            mountAzimuth.present ? mountAzimuth.value : this.mountAzimuth,
        pierSide: pierSide.present ? pierSide.value : this.pierSide,
        focuserPosition: focuserPosition.present
            ? focuserPosition.value
            : this.focuserPosition,
        focuserTemp: focuserTemp.present ? focuserTemp.value : this.focuserTemp,
        rotatorAngle:
            rotatorAngle.present ? rotatorAngle.value : this.rotatorAngle,
        isPlateSolved: isPlateSolved ?? this.isPlateSolved,
        solvedRa: solvedRa.present ? solvedRa.value : this.solvedRa,
        solvedDec: solvedDec.present ? solvedDec.value : this.solvedDec,
        solvedRotation:
            solvedRotation.present ? solvedRotation.value : this.solvedRotation,
        solvedPixelScale: solvedPixelScale.present
            ? solvedPixelScale.value
            : this.solvedPixelScale,
        capturedAt: capturedAt ?? this.capturedAt,
        createdAt: createdAt ?? this.createdAt,
        isAccepted: isAccepted ?? this.isAccepted,
        rejectionReason: rejectionReason.present
            ? rejectionReason.value
            : this.rejectionReason,
      );
  CapturedImage copyWithCompanion(CapturedImagesCompanion data) {
    return CapturedImage(
      id: data.id.present ? data.id.value : this.id,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileFormat:
          data.fileFormat.present ? data.fileFormat.value : this.fileFormat,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      frameType: data.frameType.present ? data.frameType.value : this.frameType,
      exposureDuration: data.exposureDuration.present
          ? data.exposureDuration.value
          : this.exposureDuration,
      gain: data.gain.present ? data.gain.value : this.gain,
      offset: data.offset.present ? data.offset.value : this.offset,
      binX: data.binX.present ? data.binX.value : this.binX,
      binY: data.binY.present ? data.binY.value : this.binY,
      filter: data.filter.present ? data.filter.value : this.filter,
      sensorTemp:
          data.sensorTemp.present ? data.sensorTemp.value : this.sensorTemp,
      coolerPower:
          data.coolerPower.present ? data.coolerPower.value : this.coolerPower,
      hfr: data.hfr.present ? data.hfr.value : this.hfr,
      starCount: data.starCount.present ? data.starCount.value : this.starCount,
      background:
          data.background.present ? data.background.value : this.background,
      noise: data.noise.present ? data.noise.value : this.noise,
      qualityScore: data.qualityScore.present
          ? data.qualityScore.value
          : this.qualityScore,
      guidingRmsRa: data.guidingRmsRa.present
          ? data.guidingRmsRa.value
          : this.guidingRmsRa,
      guidingRmsDec: data.guidingRmsDec.present
          ? data.guidingRmsDec.value
          : this.guidingRmsDec,
      guidingRmsTotal: data.guidingRmsTotal.present
          ? data.guidingRmsTotal.value
          : this.guidingRmsTotal,
      mountRa: data.mountRa.present ? data.mountRa.value : this.mountRa,
      mountDec: data.mountDec.present ? data.mountDec.value : this.mountDec,
      mountAltitude: data.mountAltitude.present
          ? data.mountAltitude.value
          : this.mountAltitude,
      mountAzimuth: data.mountAzimuth.present
          ? data.mountAzimuth.value
          : this.mountAzimuth,
      pierSide: data.pierSide.present ? data.pierSide.value : this.pierSide,
      focuserPosition: data.focuserPosition.present
          ? data.focuserPosition.value
          : this.focuserPosition,
      focuserTemp:
          data.focuserTemp.present ? data.focuserTemp.value : this.focuserTemp,
      rotatorAngle: data.rotatorAngle.present
          ? data.rotatorAngle.value
          : this.rotatorAngle,
      isPlateSolved: data.isPlateSolved.present
          ? data.isPlateSolved.value
          : this.isPlateSolved,
      solvedRa: data.solvedRa.present ? data.solvedRa.value : this.solvedRa,
      solvedDec: data.solvedDec.present ? data.solvedDec.value : this.solvedDec,
      solvedRotation: data.solvedRotation.present
          ? data.solvedRotation.value
          : this.solvedRotation,
      solvedPixelScale: data.solvedPixelScale.present
          ? data.solvedPixelScale.value
          : this.solvedPixelScale,
      capturedAt:
          data.capturedAt.present ? data.capturedAt.value : this.capturedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isAccepted:
          data.isAccepted.present ? data.isAccepted.value : this.isAccepted,
      rejectionReason: data.rejectionReason.present
          ? data.rejectionReason.value
          : this.rejectionReason,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CapturedImage(')
          ..write('id: $id, ')
          ..write('filePath: $filePath, ')
          ..write('fileName: $fileName, ')
          ..write('fileFormat: $fileFormat, ')
          ..write('fileSize: $fileSize, ')
          ..write('sessionId: $sessionId, ')
          ..write('targetId: $targetId, ')
          ..write('frameType: $frameType, ')
          ..write('exposureDuration: $exposureDuration, ')
          ..write('gain: $gain, ')
          ..write('offset: $offset, ')
          ..write('binX: $binX, ')
          ..write('binY: $binY, ')
          ..write('filter: $filter, ')
          ..write('sensorTemp: $sensorTemp, ')
          ..write('coolerPower: $coolerPower, ')
          ..write('hfr: $hfr, ')
          ..write('starCount: $starCount, ')
          ..write('background: $background, ')
          ..write('noise: $noise, ')
          ..write('qualityScore: $qualityScore, ')
          ..write('guidingRmsRa: $guidingRmsRa, ')
          ..write('guidingRmsDec: $guidingRmsDec, ')
          ..write('guidingRmsTotal: $guidingRmsTotal, ')
          ..write('mountRa: $mountRa, ')
          ..write('mountDec: $mountDec, ')
          ..write('mountAltitude: $mountAltitude, ')
          ..write('mountAzimuth: $mountAzimuth, ')
          ..write('pierSide: $pierSide, ')
          ..write('focuserPosition: $focuserPosition, ')
          ..write('focuserTemp: $focuserTemp, ')
          ..write('rotatorAngle: $rotatorAngle, ')
          ..write('isPlateSolved: $isPlateSolved, ')
          ..write('solvedRa: $solvedRa, ')
          ..write('solvedDec: $solvedDec, ')
          ..write('solvedRotation: $solvedRotation, ')
          ..write('solvedPixelScale: $solvedPixelScale, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('isAccepted: $isAccepted, ')
          ..write('rejectionReason: $rejectionReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        filePath,
        fileName,
        fileFormat,
        fileSize,
        sessionId,
        targetId,
        frameType,
        exposureDuration,
        gain,
        offset,
        binX,
        binY,
        filter,
        sensorTemp,
        coolerPower,
        hfr,
        starCount,
        background,
        noise,
        qualityScore,
        guidingRmsRa,
        guidingRmsDec,
        guidingRmsTotal,
        mountRa,
        mountDec,
        mountAltitude,
        mountAzimuth,
        pierSide,
        focuserPosition,
        focuserTemp,
        rotatorAngle,
        isPlateSolved,
        solvedRa,
        solvedDec,
        solvedRotation,
        solvedPixelScale,
        capturedAt,
        createdAt,
        isAccepted,
        rejectionReason
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CapturedImage &&
          other.id == this.id &&
          other.filePath == this.filePath &&
          other.fileName == this.fileName &&
          other.fileFormat == this.fileFormat &&
          other.fileSize == this.fileSize &&
          other.sessionId == this.sessionId &&
          other.targetId == this.targetId &&
          other.frameType == this.frameType &&
          other.exposureDuration == this.exposureDuration &&
          other.gain == this.gain &&
          other.offset == this.offset &&
          other.binX == this.binX &&
          other.binY == this.binY &&
          other.filter == this.filter &&
          other.sensorTemp == this.sensorTemp &&
          other.coolerPower == this.coolerPower &&
          other.hfr == this.hfr &&
          other.starCount == this.starCount &&
          other.background == this.background &&
          other.noise == this.noise &&
          other.qualityScore == this.qualityScore &&
          other.guidingRmsRa == this.guidingRmsRa &&
          other.guidingRmsDec == this.guidingRmsDec &&
          other.guidingRmsTotal == this.guidingRmsTotal &&
          other.mountRa == this.mountRa &&
          other.mountDec == this.mountDec &&
          other.mountAltitude == this.mountAltitude &&
          other.mountAzimuth == this.mountAzimuth &&
          other.pierSide == this.pierSide &&
          other.focuserPosition == this.focuserPosition &&
          other.focuserTemp == this.focuserTemp &&
          other.rotatorAngle == this.rotatorAngle &&
          other.isPlateSolved == this.isPlateSolved &&
          other.solvedRa == this.solvedRa &&
          other.solvedDec == this.solvedDec &&
          other.solvedRotation == this.solvedRotation &&
          other.solvedPixelScale == this.solvedPixelScale &&
          other.capturedAt == this.capturedAt &&
          other.createdAt == this.createdAt &&
          other.isAccepted == this.isAccepted &&
          other.rejectionReason == this.rejectionReason);
}

class CapturedImagesCompanion extends UpdateCompanion<CapturedImage> {
  final Value<int> id;
  final Value<String> filePath;
  final Value<String> fileName;
  final Value<String> fileFormat;
  final Value<int?> fileSize;
  final Value<int?> sessionId;
  final Value<int?> targetId;
  final Value<String> frameType;
  final Value<double> exposureDuration;
  final Value<int?> gain;
  final Value<int?> offset;
  final Value<int> binX;
  final Value<int> binY;
  final Value<String?> filter;
  final Value<double?> sensorTemp;
  final Value<double?> coolerPower;
  final Value<double?> hfr;
  final Value<int?> starCount;
  final Value<double?> background;
  final Value<double?> noise;
  final Value<double?> qualityScore;
  final Value<double?> guidingRmsRa;
  final Value<double?> guidingRmsDec;
  final Value<double?> guidingRmsTotal;
  final Value<double?> mountRa;
  final Value<double?> mountDec;
  final Value<double?> mountAltitude;
  final Value<double?> mountAzimuth;
  final Value<String?> pierSide;
  final Value<int?> focuserPosition;
  final Value<double?> focuserTemp;
  final Value<double?> rotatorAngle;
  final Value<bool> isPlateSolved;
  final Value<double?> solvedRa;
  final Value<double?> solvedDec;
  final Value<double?> solvedRotation;
  final Value<double?> solvedPixelScale;
  final Value<DateTime> capturedAt;
  final Value<DateTime> createdAt;
  final Value<bool> isAccepted;
  final Value<String?> rejectionReason;
  const CapturedImagesCompanion({
    this.id = const Value.absent(),
    this.filePath = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileFormat = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.frameType = const Value.absent(),
    this.exposureDuration = const Value.absent(),
    this.gain = const Value.absent(),
    this.offset = const Value.absent(),
    this.binX = const Value.absent(),
    this.binY = const Value.absent(),
    this.filter = const Value.absent(),
    this.sensorTemp = const Value.absent(),
    this.coolerPower = const Value.absent(),
    this.hfr = const Value.absent(),
    this.starCount = const Value.absent(),
    this.background = const Value.absent(),
    this.noise = const Value.absent(),
    this.qualityScore = const Value.absent(),
    this.guidingRmsRa = const Value.absent(),
    this.guidingRmsDec = const Value.absent(),
    this.guidingRmsTotal = const Value.absent(),
    this.mountRa = const Value.absent(),
    this.mountDec = const Value.absent(),
    this.mountAltitude = const Value.absent(),
    this.mountAzimuth = const Value.absent(),
    this.pierSide = const Value.absent(),
    this.focuserPosition = const Value.absent(),
    this.focuserTemp = const Value.absent(),
    this.rotatorAngle = const Value.absent(),
    this.isPlateSolved = const Value.absent(),
    this.solvedRa = const Value.absent(),
    this.solvedDec = const Value.absent(),
    this.solvedRotation = const Value.absent(),
    this.solvedPixelScale = const Value.absent(),
    this.capturedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isAccepted = const Value.absent(),
    this.rejectionReason = const Value.absent(),
  });
  CapturedImagesCompanion.insert({
    this.id = const Value.absent(),
    required String filePath,
    required String fileName,
    this.fileFormat = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.targetId = const Value.absent(),
    this.frameType = const Value.absent(),
    required double exposureDuration,
    this.gain = const Value.absent(),
    this.offset = const Value.absent(),
    this.binX = const Value.absent(),
    this.binY = const Value.absent(),
    this.filter = const Value.absent(),
    this.sensorTemp = const Value.absent(),
    this.coolerPower = const Value.absent(),
    this.hfr = const Value.absent(),
    this.starCount = const Value.absent(),
    this.background = const Value.absent(),
    this.noise = const Value.absent(),
    this.qualityScore = const Value.absent(),
    this.guidingRmsRa = const Value.absent(),
    this.guidingRmsDec = const Value.absent(),
    this.guidingRmsTotal = const Value.absent(),
    this.mountRa = const Value.absent(),
    this.mountDec = const Value.absent(),
    this.mountAltitude = const Value.absent(),
    this.mountAzimuth = const Value.absent(),
    this.pierSide = const Value.absent(),
    this.focuserPosition = const Value.absent(),
    this.focuserTemp = const Value.absent(),
    this.rotatorAngle = const Value.absent(),
    this.isPlateSolved = const Value.absent(),
    this.solvedRa = const Value.absent(),
    this.solvedDec = const Value.absent(),
    this.solvedRotation = const Value.absent(),
    this.solvedPixelScale = const Value.absent(),
    required DateTime capturedAt,
    this.createdAt = const Value.absent(),
    this.isAccepted = const Value.absent(),
    this.rejectionReason = const Value.absent(),
  })  : filePath = Value(filePath),
        fileName = Value(fileName),
        exposureDuration = Value(exposureDuration),
        capturedAt = Value(capturedAt);
  static Insertable<CapturedImage> custom({
    Expression<int>? id,
    Expression<String>? filePath,
    Expression<String>? fileName,
    Expression<String>? fileFormat,
    Expression<int>? fileSize,
    Expression<int>? sessionId,
    Expression<int>? targetId,
    Expression<String>? frameType,
    Expression<double>? exposureDuration,
    Expression<int>? gain,
    Expression<int>? offset,
    Expression<int>? binX,
    Expression<int>? binY,
    Expression<String>? filter,
    Expression<double>? sensorTemp,
    Expression<double>? coolerPower,
    Expression<double>? hfr,
    Expression<int>? starCount,
    Expression<double>? background,
    Expression<double>? noise,
    Expression<double>? qualityScore,
    Expression<double>? guidingRmsRa,
    Expression<double>? guidingRmsDec,
    Expression<double>? guidingRmsTotal,
    Expression<double>? mountRa,
    Expression<double>? mountDec,
    Expression<double>? mountAltitude,
    Expression<double>? mountAzimuth,
    Expression<String>? pierSide,
    Expression<int>? focuserPosition,
    Expression<double>? focuserTemp,
    Expression<double>? rotatorAngle,
    Expression<bool>? isPlateSolved,
    Expression<double>? solvedRa,
    Expression<double>? solvedDec,
    Expression<double>? solvedRotation,
    Expression<double>? solvedPixelScale,
    Expression<DateTime>? capturedAt,
    Expression<DateTime>? createdAt,
    Expression<bool>? isAccepted,
    Expression<String>? rejectionReason,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (filePath != null) 'file_path': filePath,
      if (fileName != null) 'file_name': fileName,
      if (fileFormat != null) 'file_format': fileFormat,
      if (fileSize != null) 'file_size': fileSize,
      if (sessionId != null) 'session_id': sessionId,
      if (targetId != null) 'target_id': targetId,
      if (frameType != null) 'frame_type': frameType,
      if (exposureDuration != null) 'exposure_duration': exposureDuration,
      if (gain != null) 'gain': gain,
      if (offset != null) 'offset': offset,
      if (binX != null) 'bin_x': binX,
      if (binY != null) 'bin_y': binY,
      if (filter != null) 'filter': filter,
      if (sensorTemp != null) 'sensor_temp': sensorTemp,
      if (coolerPower != null) 'cooler_power': coolerPower,
      if (hfr != null) 'hfr': hfr,
      if (starCount != null) 'star_count': starCount,
      if (background != null) 'background': background,
      if (noise != null) 'noise': noise,
      if (qualityScore != null) 'quality_score': qualityScore,
      if (guidingRmsRa != null) 'guiding_rms_ra': guidingRmsRa,
      if (guidingRmsDec != null) 'guiding_rms_dec': guidingRmsDec,
      if (guidingRmsTotal != null) 'guiding_rms_total': guidingRmsTotal,
      if (mountRa != null) 'mount_ra': mountRa,
      if (mountDec != null) 'mount_dec': mountDec,
      if (mountAltitude != null) 'mount_altitude': mountAltitude,
      if (mountAzimuth != null) 'mount_azimuth': mountAzimuth,
      if (pierSide != null) 'pier_side': pierSide,
      if (focuserPosition != null) 'focuser_position': focuserPosition,
      if (focuserTemp != null) 'focuser_temp': focuserTemp,
      if (rotatorAngle != null) 'rotator_angle': rotatorAngle,
      if (isPlateSolved != null) 'is_plate_solved': isPlateSolved,
      if (solvedRa != null) 'solved_ra': solvedRa,
      if (solvedDec != null) 'solved_dec': solvedDec,
      if (solvedRotation != null) 'solved_rotation': solvedRotation,
      if (solvedPixelScale != null) 'solved_pixel_scale': solvedPixelScale,
      if (capturedAt != null) 'captured_at': capturedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (isAccepted != null) 'is_accepted': isAccepted,
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
    });
  }

  CapturedImagesCompanion copyWith(
      {Value<int>? id,
      Value<String>? filePath,
      Value<String>? fileName,
      Value<String>? fileFormat,
      Value<int?>? fileSize,
      Value<int?>? sessionId,
      Value<int?>? targetId,
      Value<String>? frameType,
      Value<double>? exposureDuration,
      Value<int?>? gain,
      Value<int?>? offset,
      Value<int>? binX,
      Value<int>? binY,
      Value<String?>? filter,
      Value<double?>? sensorTemp,
      Value<double?>? coolerPower,
      Value<double?>? hfr,
      Value<int?>? starCount,
      Value<double?>? background,
      Value<double?>? noise,
      Value<double?>? qualityScore,
      Value<double?>? guidingRmsRa,
      Value<double?>? guidingRmsDec,
      Value<double?>? guidingRmsTotal,
      Value<double?>? mountRa,
      Value<double?>? mountDec,
      Value<double?>? mountAltitude,
      Value<double?>? mountAzimuth,
      Value<String?>? pierSide,
      Value<int?>? focuserPosition,
      Value<double?>? focuserTemp,
      Value<double?>? rotatorAngle,
      Value<bool>? isPlateSolved,
      Value<double?>? solvedRa,
      Value<double?>? solvedDec,
      Value<double?>? solvedRotation,
      Value<double?>? solvedPixelScale,
      Value<DateTime>? capturedAt,
      Value<DateTime>? createdAt,
      Value<bool>? isAccepted,
      Value<String?>? rejectionReason}) {
    return CapturedImagesCompanion(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      fileFormat: fileFormat ?? this.fileFormat,
      fileSize: fileSize ?? this.fileSize,
      sessionId: sessionId ?? this.sessionId,
      targetId: targetId ?? this.targetId,
      frameType: frameType ?? this.frameType,
      exposureDuration: exposureDuration ?? this.exposureDuration,
      gain: gain ?? this.gain,
      offset: offset ?? this.offset,
      binX: binX ?? this.binX,
      binY: binY ?? this.binY,
      filter: filter ?? this.filter,
      sensorTemp: sensorTemp ?? this.sensorTemp,
      coolerPower: coolerPower ?? this.coolerPower,
      hfr: hfr ?? this.hfr,
      starCount: starCount ?? this.starCount,
      background: background ?? this.background,
      noise: noise ?? this.noise,
      qualityScore: qualityScore ?? this.qualityScore,
      guidingRmsRa: guidingRmsRa ?? this.guidingRmsRa,
      guidingRmsDec: guidingRmsDec ?? this.guidingRmsDec,
      guidingRmsTotal: guidingRmsTotal ?? this.guidingRmsTotal,
      mountRa: mountRa ?? this.mountRa,
      mountDec: mountDec ?? this.mountDec,
      mountAltitude: mountAltitude ?? this.mountAltitude,
      mountAzimuth: mountAzimuth ?? this.mountAzimuth,
      pierSide: pierSide ?? this.pierSide,
      focuserPosition: focuserPosition ?? this.focuserPosition,
      focuserTemp: focuserTemp ?? this.focuserTemp,
      rotatorAngle: rotatorAngle ?? this.rotatorAngle,
      isPlateSolved: isPlateSolved ?? this.isPlateSolved,
      solvedRa: solvedRa ?? this.solvedRa,
      solvedDec: solvedDec ?? this.solvedDec,
      solvedRotation: solvedRotation ?? this.solvedRotation,
      solvedPixelScale: solvedPixelScale ?? this.solvedPixelScale,
      capturedAt: capturedAt ?? this.capturedAt,
      createdAt: createdAt ?? this.createdAt,
      isAccepted: isAccepted ?? this.isAccepted,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileFormat.present) {
      map['file_format'] = Variable<String>(fileFormat.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<int>(sessionId.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<int>(targetId.value);
    }
    if (frameType.present) {
      map['frame_type'] = Variable<String>(frameType.value);
    }
    if (exposureDuration.present) {
      map['exposure_duration'] = Variable<double>(exposureDuration.value);
    }
    if (gain.present) {
      map['gain'] = Variable<int>(gain.value);
    }
    if (offset.present) {
      map['offset'] = Variable<int>(offset.value);
    }
    if (binX.present) {
      map['bin_x'] = Variable<int>(binX.value);
    }
    if (binY.present) {
      map['bin_y'] = Variable<int>(binY.value);
    }
    if (filter.present) {
      map['filter'] = Variable<String>(filter.value);
    }
    if (sensorTemp.present) {
      map['sensor_temp'] = Variable<double>(sensorTemp.value);
    }
    if (coolerPower.present) {
      map['cooler_power'] = Variable<double>(coolerPower.value);
    }
    if (hfr.present) {
      map['hfr'] = Variable<double>(hfr.value);
    }
    if (starCount.present) {
      map['star_count'] = Variable<int>(starCount.value);
    }
    if (background.present) {
      map['background'] = Variable<double>(background.value);
    }
    if (noise.present) {
      map['noise'] = Variable<double>(noise.value);
    }
    if (qualityScore.present) {
      map['quality_score'] = Variable<double>(qualityScore.value);
    }
    if (guidingRmsRa.present) {
      map['guiding_rms_ra'] = Variable<double>(guidingRmsRa.value);
    }
    if (guidingRmsDec.present) {
      map['guiding_rms_dec'] = Variable<double>(guidingRmsDec.value);
    }
    if (guidingRmsTotal.present) {
      map['guiding_rms_total'] = Variable<double>(guidingRmsTotal.value);
    }
    if (mountRa.present) {
      map['mount_ra'] = Variable<double>(mountRa.value);
    }
    if (mountDec.present) {
      map['mount_dec'] = Variable<double>(mountDec.value);
    }
    if (mountAltitude.present) {
      map['mount_altitude'] = Variable<double>(mountAltitude.value);
    }
    if (mountAzimuth.present) {
      map['mount_azimuth'] = Variable<double>(mountAzimuth.value);
    }
    if (pierSide.present) {
      map['pier_side'] = Variable<String>(pierSide.value);
    }
    if (focuserPosition.present) {
      map['focuser_position'] = Variable<int>(focuserPosition.value);
    }
    if (focuserTemp.present) {
      map['focuser_temp'] = Variable<double>(focuserTemp.value);
    }
    if (rotatorAngle.present) {
      map['rotator_angle'] = Variable<double>(rotatorAngle.value);
    }
    if (isPlateSolved.present) {
      map['is_plate_solved'] = Variable<bool>(isPlateSolved.value);
    }
    if (solvedRa.present) {
      map['solved_ra'] = Variable<double>(solvedRa.value);
    }
    if (solvedDec.present) {
      map['solved_dec'] = Variable<double>(solvedDec.value);
    }
    if (solvedRotation.present) {
      map['solved_rotation'] = Variable<double>(solvedRotation.value);
    }
    if (solvedPixelScale.present) {
      map['solved_pixel_scale'] = Variable<double>(solvedPixelScale.value);
    }
    if (capturedAt.present) {
      map['captured_at'] = Variable<DateTime>(capturedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isAccepted.present) {
      map['is_accepted'] = Variable<bool>(isAccepted.value);
    }
    if (rejectionReason.present) {
      map['rejection_reason'] = Variable<String>(rejectionReason.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CapturedImagesCompanion(')
          ..write('id: $id, ')
          ..write('filePath: $filePath, ')
          ..write('fileName: $fileName, ')
          ..write('fileFormat: $fileFormat, ')
          ..write('fileSize: $fileSize, ')
          ..write('sessionId: $sessionId, ')
          ..write('targetId: $targetId, ')
          ..write('frameType: $frameType, ')
          ..write('exposureDuration: $exposureDuration, ')
          ..write('gain: $gain, ')
          ..write('offset: $offset, ')
          ..write('binX: $binX, ')
          ..write('binY: $binY, ')
          ..write('filter: $filter, ')
          ..write('sensorTemp: $sensorTemp, ')
          ..write('coolerPower: $coolerPower, ')
          ..write('hfr: $hfr, ')
          ..write('starCount: $starCount, ')
          ..write('background: $background, ')
          ..write('noise: $noise, ')
          ..write('qualityScore: $qualityScore, ')
          ..write('guidingRmsRa: $guidingRmsRa, ')
          ..write('guidingRmsDec: $guidingRmsDec, ')
          ..write('guidingRmsTotal: $guidingRmsTotal, ')
          ..write('mountRa: $mountRa, ')
          ..write('mountDec: $mountDec, ')
          ..write('mountAltitude: $mountAltitude, ')
          ..write('mountAzimuth: $mountAzimuth, ')
          ..write('pierSide: $pierSide, ')
          ..write('focuserPosition: $focuserPosition, ')
          ..write('focuserTemp: $focuserTemp, ')
          ..write('rotatorAngle: $rotatorAngle, ')
          ..write('isPlateSolved: $isPlateSolved, ')
          ..write('solvedRa: $solvedRa, ')
          ..write('solvedDec: $solvedDec, ')
          ..write('solvedRotation: $solvedRotation, ')
          ..write('solvedPixelScale: $solvedPixelScale, ')
          ..write('capturedAt: $capturedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('isAccepted: $isAccepted, ')
          ..write('rejectionReason: $rejectionReason')
          ..write(')'))
        .toString();
  }
}

class $ImageMetadataTable extends ImageMetadata
    with TableInfo<$ImageMetadataTable, ImageMetadatum> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImageMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _imageIdMeta =
      const VerificationMeta('imageId');
  @override
  late final GeneratedColumn<int> imageId = GeneratedColumn<int>(
      'image_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES captured_images (id) ON DELETE CASCADE'));
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _commentMeta =
      const VerificationMeta('comment');
  @override
  late final GeneratedColumn<String> comment = GeneratedColumn<String>(
      'comment', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, imageId, key, value, comment];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'image_metadata';
  @override
  VerificationContext validateIntegrity(Insertable<ImageMetadatum> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('image_id')) {
      context.handle(_imageIdMeta,
          imageId.isAcceptableOrUnknown(data['image_id']!, _imageIdMeta));
    } else if (isInserting) {
      context.missing(_imageIdMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('comment')) {
      context.handle(_commentMeta,
          comment.isAcceptableOrUnknown(data['comment']!, _commentMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ImageMetadatum map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ImageMetadatum(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      imageId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}image_id'])!,
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      comment: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}comment']),
    );
  }

  @override
  $ImageMetadataTable createAlias(String alias) {
    return $ImageMetadataTable(attachedDatabase, alias);
  }
}

class ImageMetadatum extends DataClass implements Insertable<ImageMetadatum> {
  final int id;
  final int imageId;
  final String key;
  final String value;
  final String? comment;
  const ImageMetadatum(
      {required this.id,
      required this.imageId,
      required this.key,
      required this.value,
      this.comment});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['image_id'] = Variable<int>(imageId);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    if (!nullToAbsent || comment != null) {
      map['comment'] = Variable<String>(comment);
    }
    return map;
  }

  ImageMetadataCompanion toCompanion(bool nullToAbsent) {
    return ImageMetadataCompanion(
      id: Value(id),
      imageId: Value(imageId),
      key: Value(key),
      value: Value(value),
      comment: comment == null && nullToAbsent
          ? const Value.absent()
          : Value(comment),
    );
  }

  factory ImageMetadatum.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ImageMetadatum(
      id: serializer.fromJson<int>(json['id']),
      imageId: serializer.fromJson<int>(json['imageId']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      comment: serializer.fromJson<String?>(json['comment']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'imageId': serializer.toJson<int>(imageId),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'comment': serializer.toJson<String?>(comment),
    };
  }

  ImageMetadatum copyWith(
          {int? id,
          int? imageId,
          String? key,
          String? value,
          Value<String?> comment = const Value.absent()}) =>
      ImageMetadatum(
        id: id ?? this.id,
        imageId: imageId ?? this.imageId,
        key: key ?? this.key,
        value: value ?? this.value,
        comment: comment.present ? comment.value : this.comment,
      );
  ImageMetadatum copyWithCompanion(ImageMetadataCompanion data) {
    return ImageMetadatum(
      id: data.id.present ? data.id.value : this.id,
      imageId: data.imageId.present ? data.imageId.value : this.imageId,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      comment: data.comment.present ? data.comment.value : this.comment,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ImageMetadatum(')
          ..write('id: $id, ')
          ..write('imageId: $imageId, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('comment: $comment')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, imageId, key, value, comment);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImageMetadatum &&
          other.id == this.id &&
          other.imageId == this.imageId &&
          other.key == this.key &&
          other.value == this.value &&
          other.comment == this.comment);
}

class ImageMetadataCompanion extends UpdateCompanion<ImageMetadatum> {
  final Value<int> id;
  final Value<int> imageId;
  final Value<String> key;
  final Value<String> value;
  final Value<String?> comment;
  const ImageMetadataCompanion({
    this.id = const Value.absent(),
    this.imageId = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.comment = const Value.absent(),
  });
  ImageMetadataCompanion.insert({
    this.id = const Value.absent(),
    required int imageId,
    required String key,
    required String value,
    this.comment = const Value.absent(),
  })  : imageId = Value(imageId),
        key = Value(key),
        value = Value(value);
  static Insertable<ImageMetadatum> custom({
    Expression<int>? id,
    Expression<int>? imageId,
    Expression<String>? key,
    Expression<String>? value,
    Expression<String>? comment,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (imageId != null) 'image_id': imageId,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (comment != null) 'comment': comment,
    });
  }

  ImageMetadataCompanion copyWith(
      {Value<int>? id,
      Value<int>? imageId,
      Value<String>? key,
      Value<String>? value,
      Value<String?>? comment}) {
    return ImageMetadataCompanion(
      id: id ?? this.id,
      imageId: imageId ?? this.imageId,
      key: key ?? this.key,
      value: value ?? this.value,
      comment: comment ?? this.comment,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (imageId.present) {
      map['image_id'] = Variable<int>(imageId.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (comment.present) {
      map['comment'] = Variable<String>(comment.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImageMetadataCompanion(')
          ..write('id: $id, ')
          ..write('imageId: $imageId, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('comment: $comment')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [id, key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(Insertable<AppSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final int id;
  final String key;
  final String value;
  final DateTime updatedAt;
  const AppSetting(
      {required this.id,
      required this.key,
      required this.value,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(
      id: Value(id),
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      id: serializer.fromJson<int>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppSetting copyWith(
          {int? id, String? key, String? value, DateTime? updatedAt}) =>
      AppSetting(
        id: id ?? this.id,
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.id == this.id &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<int> id;
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  const AppSettingsCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    this.id = const Value.absent(),
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<int>? id,
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  AppSettingsCompanion copyWith(
      {Value<int>? id,
      Value<String>? key,
      Value<String>? value,
      Value<DateTime>? updatedAt}) {
    return AppSettingsCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $WeatherSettingsTable extends WeatherSettings
    with TableInfo<$WeatherSettingsTable, WeatherSettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WeatherSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _triggerDistanceKmMeta =
      const VerificationMeta('triggerDistanceKm');
  @override
  late final GeneratedColumn<double> triggerDistanceKm =
      GeneratedColumn<double>('trigger_distance_km', aliasedName, false,
          type: DriftSqlType.double,
          requiredDuringInsert: false,
          defaultValue: const Constant(30.0));
  static const VerificationMeta _cloudDensityThresholdMeta =
      const VerificationMeta('cloudDensityThreshold');
  @override
  late final GeneratedColumn<double> cloudDensityThreshold =
      GeneratedColumn<double>('cloud_density_threshold', aliasedName, false,
          type: DriftSqlType.double,
          requiredDuringInsert: false,
          defaultValue: const Constant(60.0));
  static const VerificationMeta _leadTimeMinutesMeta =
      const VerificationMeta('leadTimeMinutes');
  @override
  late final GeneratedColumn<int> leadTimeMinutes = GeneratedColumn<int>(
      'lead_time_minutes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(15));
  static const VerificationMeta _weatherSafetyEnabledMeta =
      const VerificationMeta('weatherSafetyEnabled');
  @override
  late final GeneratedColumn<bool> weatherSafetyEnabled = GeneratedColumn<bool>(
      'weather_safety_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("weather_safety_enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _autoParkEnabledMeta =
      const VerificationMeta('autoParkEnabled');
  @override
  late final GeneratedColumn<bool> autoParkEnabled = GeneratedColumn<bool>(
      'auto_park_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("auto_park_enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _autoResumeEnabledMeta =
      const VerificationMeta('autoResumeEnabled');
  @override
  late final GeneratedColumn<bool> autoResumeEnabled = GeneratedColumn<bool>(
      'auto_resume_enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("auto_resume_enabled" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _preferredProviderMeta =
      const VerificationMeta('preferredProvider');
  @override
  late final GeneratedColumn<String> preferredProvider =
      GeneratedColumn<String>('preferred_provider', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('auto'));
  static const VerificationMeta _refreshIntervalSecondsMeta =
      const VerificationMeta('refreshIntervalSeconds');
  @override
  late final GeneratedColumn<int> refreshIntervalSeconds = GeneratedColumn<int>(
      'refresh_interval_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(300));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        triggerDistanceKm,
        cloudDensityThreshold,
        leadTimeMinutes,
        weatherSafetyEnabled,
        autoParkEnabled,
        autoResumeEnabled,
        preferredProvider,
        refreshIntervalSeconds,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'weather_settings';
  @override
  VerificationContext validateIntegrity(Insertable<WeatherSettingRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('trigger_distance_km')) {
      context.handle(
          _triggerDistanceKmMeta,
          triggerDistanceKm.isAcceptableOrUnknown(
              data['trigger_distance_km']!, _triggerDistanceKmMeta));
    }
    if (data.containsKey('cloud_density_threshold')) {
      context.handle(
          _cloudDensityThresholdMeta,
          cloudDensityThreshold.isAcceptableOrUnknown(
              data['cloud_density_threshold']!, _cloudDensityThresholdMeta));
    }
    if (data.containsKey('lead_time_minutes')) {
      context.handle(
          _leadTimeMinutesMeta,
          leadTimeMinutes.isAcceptableOrUnknown(
              data['lead_time_minutes']!, _leadTimeMinutesMeta));
    }
    if (data.containsKey('weather_safety_enabled')) {
      context.handle(
          _weatherSafetyEnabledMeta,
          weatherSafetyEnabled.isAcceptableOrUnknown(
              data['weather_safety_enabled']!, _weatherSafetyEnabledMeta));
    }
    if (data.containsKey('auto_park_enabled')) {
      context.handle(
          _autoParkEnabledMeta,
          autoParkEnabled.isAcceptableOrUnknown(
              data['auto_park_enabled']!, _autoParkEnabledMeta));
    }
    if (data.containsKey('auto_resume_enabled')) {
      context.handle(
          _autoResumeEnabledMeta,
          autoResumeEnabled.isAcceptableOrUnknown(
              data['auto_resume_enabled']!, _autoResumeEnabledMeta));
    }
    if (data.containsKey('preferred_provider')) {
      context.handle(
          _preferredProviderMeta,
          preferredProvider.isAcceptableOrUnknown(
              data['preferred_provider']!, _preferredProviderMeta));
    }
    if (data.containsKey('refresh_interval_seconds')) {
      context.handle(
          _refreshIntervalSecondsMeta,
          refreshIntervalSeconds.isAcceptableOrUnknown(
              data['refresh_interval_seconds']!, _refreshIntervalSecondsMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WeatherSettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WeatherSettingRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      triggerDistanceKm: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}trigger_distance_km'])!,
      cloudDensityThreshold: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}cloud_density_threshold'])!,
      leadTimeMinutes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}lead_time_minutes'])!,
      weatherSafetyEnabled: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}weather_safety_enabled'])!,
      autoParkEnabled: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}auto_park_enabled'])!,
      autoResumeEnabled: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}auto_resume_enabled'])!,
      preferredProvider: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}preferred_provider'])!,
      refreshIntervalSeconds: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}refresh_interval_seconds'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $WeatherSettingsTable createAlias(String alias) {
    return $WeatherSettingsTable(attachedDatabase, alias);
  }
}

class WeatherSettingRow extends DataClass
    implements Insertable<WeatherSettingRow> {
  final int id;
  final double triggerDistanceKm;
  final double cloudDensityThreshold;
  final int leadTimeMinutes;
  final bool weatherSafetyEnabled;
  final bool autoParkEnabled;
  final bool autoResumeEnabled;
  final String preferredProvider;
  final int refreshIntervalSeconds;
  final DateTime updatedAt;
  const WeatherSettingRow(
      {required this.id,
      required this.triggerDistanceKm,
      required this.cloudDensityThreshold,
      required this.leadTimeMinutes,
      required this.weatherSafetyEnabled,
      required this.autoParkEnabled,
      required this.autoResumeEnabled,
      required this.preferredProvider,
      required this.refreshIntervalSeconds,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['trigger_distance_km'] = Variable<double>(triggerDistanceKm);
    map['cloud_density_threshold'] = Variable<double>(cloudDensityThreshold);
    map['lead_time_minutes'] = Variable<int>(leadTimeMinutes);
    map['weather_safety_enabled'] = Variable<bool>(weatherSafetyEnabled);
    map['auto_park_enabled'] = Variable<bool>(autoParkEnabled);
    map['auto_resume_enabled'] = Variable<bool>(autoResumeEnabled);
    map['preferred_provider'] = Variable<String>(preferredProvider);
    map['refresh_interval_seconds'] = Variable<int>(refreshIntervalSeconds);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WeatherSettingsCompanion toCompanion(bool nullToAbsent) {
    return WeatherSettingsCompanion(
      id: Value(id),
      triggerDistanceKm: Value(triggerDistanceKm),
      cloudDensityThreshold: Value(cloudDensityThreshold),
      leadTimeMinutes: Value(leadTimeMinutes),
      weatherSafetyEnabled: Value(weatherSafetyEnabled),
      autoParkEnabled: Value(autoParkEnabled),
      autoResumeEnabled: Value(autoResumeEnabled),
      preferredProvider: Value(preferredProvider),
      refreshIntervalSeconds: Value(refreshIntervalSeconds),
      updatedAt: Value(updatedAt),
    );
  }

  factory WeatherSettingRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WeatherSettingRow(
      id: serializer.fromJson<int>(json['id']),
      triggerDistanceKm: serializer.fromJson<double>(json['triggerDistanceKm']),
      cloudDensityThreshold:
          serializer.fromJson<double>(json['cloudDensityThreshold']),
      leadTimeMinutes: serializer.fromJson<int>(json['leadTimeMinutes']),
      weatherSafetyEnabled:
          serializer.fromJson<bool>(json['weatherSafetyEnabled']),
      autoParkEnabled: serializer.fromJson<bool>(json['autoParkEnabled']),
      autoResumeEnabled: serializer.fromJson<bool>(json['autoResumeEnabled']),
      preferredProvider: serializer.fromJson<String>(json['preferredProvider']),
      refreshIntervalSeconds:
          serializer.fromJson<int>(json['refreshIntervalSeconds']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'triggerDistanceKm': serializer.toJson<double>(triggerDistanceKm),
      'cloudDensityThreshold': serializer.toJson<double>(cloudDensityThreshold),
      'leadTimeMinutes': serializer.toJson<int>(leadTimeMinutes),
      'weatherSafetyEnabled': serializer.toJson<bool>(weatherSafetyEnabled),
      'autoParkEnabled': serializer.toJson<bool>(autoParkEnabled),
      'autoResumeEnabled': serializer.toJson<bool>(autoResumeEnabled),
      'preferredProvider': serializer.toJson<String>(preferredProvider),
      'refreshIntervalSeconds': serializer.toJson<int>(refreshIntervalSeconds),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WeatherSettingRow copyWith(
          {int? id,
          double? triggerDistanceKm,
          double? cloudDensityThreshold,
          int? leadTimeMinutes,
          bool? weatherSafetyEnabled,
          bool? autoParkEnabled,
          bool? autoResumeEnabled,
          String? preferredProvider,
          int? refreshIntervalSeconds,
          DateTime? updatedAt}) =>
      WeatherSettingRow(
        id: id ?? this.id,
        triggerDistanceKm: triggerDistanceKm ?? this.triggerDistanceKm,
        cloudDensityThreshold:
            cloudDensityThreshold ?? this.cloudDensityThreshold,
        leadTimeMinutes: leadTimeMinutes ?? this.leadTimeMinutes,
        weatherSafetyEnabled: weatherSafetyEnabled ?? this.weatherSafetyEnabled,
        autoParkEnabled: autoParkEnabled ?? this.autoParkEnabled,
        autoResumeEnabled: autoResumeEnabled ?? this.autoResumeEnabled,
        preferredProvider: preferredProvider ?? this.preferredProvider,
        refreshIntervalSeconds:
            refreshIntervalSeconds ?? this.refreshIntervalSeconds,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  WeatherSettingRow copyWithCompanion(WeatherSettingsCompanion data) {
    return WeatherSettingRow(
      id: data.id.present ? data.id.value : this.id,
      triggerDistanceKm: data.triggerDistanceKm.present
          ? data.triggerDistanceKm.value
          : this.triggerDistanceKm,
      cloudDensityThreshold: data.cloudDensityThreshold.present
          ? data.cloudDensityThreshold.value
          : this.cloudDensityThreshold,
      leadTimeMinutes: data.leadTimeMinutes.present
          ? data.leadTimeMinutes.value
          : this.leadTimeMinutes,
      weatherSafetyEnabled: data.weatherSafetyEnabled.present
          ? data.weatherSafetyEnabled.value
          : this.weatherSafetyEnabled,
      autoParkEnabled: data.autoParkEnabled.present
          ? data.autoParkEnabled.value
          : this.autoParkEnabled,
      autoResumeEnabled: data.autoResumeEnabled.present
          ? data.autoResumeEnabled.value
          : this.autoResumeEnabled,
      preferredProvider: data.preferredProvider.present
          ? data.preferredProvider.value
          : this.preferredProvider,
      refreshIntervalSeconds: data.refreshIntervalSeconds.present
          ? data.refreshIntervalSeconds.value
          : this.refreshIntervalSeconds,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WeatherSettingRow(')
          ..write('id: $id, ')
          ..write('triggerDistanceKm: $triggerDistanceKm, ')
          ..write('cloudDensityThreshold: $cloudDensityThreshold, ')
          ..write('leadTimeMinutes: $leadTimeMinutes, ')
          ..write('weatherSafetyEnabled: $weatherSafetyEnabled, ')
          ..write('autoParkEnabled: $autoParkEnabled, ')
          ..write('autoResumeEnabled: $autoResumeEnabled, ')
          ..write('preferredProvider: $preferredProvider, ')
          ..write('refreshIntervalSeconds: $refreshIntervalSeconds, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      triggerDistanceKm,
      cloudDensityThreshold,
      leadTimeMinutes,
      weatherSafetyEnabled,
      autoParkEnabled,
      autoResumeEnabled,
      preferredProvider,
      refreshIntervalSeconds,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WeatherSettingRow &&
          other.id == this.id &&
          other.triggerDistanceKm == this.triggerDistanceKm &&
          other.cloudDensityThreshold == this.cloudDensityThreshold &&
          other.leadTimeMinutes == this.leadTimeMinutes &&
          other.weatherSafetyEnabled == this.weatherSafetyEnabled &&
          other.autoParkEnabled == this.autoParkEnabled &&
          other.autoResumeEnabled == this.autoResumeEnabled &&
          other.preferredProvider == this.preferredProvider &&
          other.refreshIntervalSeconds == this.refreshIntervalSeconds &&
          other.updatedAt == this.updatedAt);
}

class WeatherSettingsCompanion extends UpdateCompanion<WeatherSettingRow> {
  final Value<int> id;
  final Value<double> triggerDistanceKm;
  final Value<double> cloudDensityThreshold;
  final Value<int> leadTimeMinutes;
  final Value<bool> weatherSafetyEnabled;
  final Value<bool> autoParkEnabled;
  final Value<bool> autoResumeEnabled;
  final Value<String> preferredProvider;
  final Value<int> refreshIntervalSeconds;
  final Value<DateTime> updatedAt;
  const WeatherSettingsCompanion({
    this.id = const Value.absent(),
    this.triggerDistanceKm = const Value.absent(),
    this.cloudDensityThreshold = const Value.absent(),
    this.leadTimeMinutes = const Value.absent(),
    this.weatherSafetyEnabled = const Value.absent(),
    this.autoParkEnabled = const Value.absent(),
    this.autoResumeEnabled = const Value.absent(),
    this.preferredProvider = const Value.absent(),
    this.refreshIntervalSeconds = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WeatherSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.triggerDistanceKm = const Value.absent(),
    this.cloudDensityThreshold = const Value.absent(),
    this.leadTimeMinutes = const Value.absent(),
    this.weatherSafetyEnabled = const Value.absent(),
    this.autoParkEnabled = const Value.absent(),
    this.autoResumeEnabled = const Value.absent(),
    this.preferredProvider = const Value.absent(),
    this.refreshIntervalSeconds = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  static Insertable<WeatherSettingRow> custom({
    Expression<int>? id,
    Expression<double>? triggerDistanceKm,
    Expression<double>? cloudDensityThreshold,
    Expression<int>? leadTimeMinutes,
    Expression<bool>? weatherSafetyEnabled,
    Expression<bool>? autoParkEnabled,
    Expression<bool>? autoResumeEnabled,
    Expression<String>? preferredProvider,
    Expression<int>? refreshIntervalSeconds,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (triggerDistanceKm != null) 'trigger_distance_km': triggerDistanceKm,
      if (cloudDensityThreshold != null)
        'cloud_density_threshold': cloudDensityThreshold,
      if (leadTimeMinutes != null) 'lead_time_minutes': leadTimeMinutes,
      if (weatherSafetyEnabled != null)
        'weather_safety_enabled': weatherSafetyEnabled,
      if (autoParkEnabled != null) 'auto_park_enabled': autoParkEnabled,
      if (autoResumeEnabled != null) 'auto_resume_enabled': autoResumeEnabled,
      if (preferredProvider != null) 'preferred_provider': preferredProvider,
      if (refreshIntervalSeconds != null)
        'refresh_interval_seconds': refreshIntervalSeconds,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WeatherSettingsCompanion copyWith(
      {Value<int>? id,
      Value<double>? triggerDistanceKm,
      Value<double>? cloudDensityThreshold,
      Value<int>? leadTimeMinutes,
      Value<bool>? weatherSafetyEnabled,
      Value<bool>? autoParkEnabled,
      Value<bool>? autoResumeEnabled,
      Value<String>? preferredProvider,
      Value<int>? refreshIntervalSeconds,
      Value<DateTime>? updatedAt}) {
    return WeatherSettingsCompanion(
      id: id ?? this.id,
      triggerDistanceKm: triggerDistanceKm ?? this.triggerDistanceKm,
      cloudDensityThreshold:
          cloudDensityThreshold ?? this.cloudDensityThreshold,
      leadTimeMinutes: leadTimeMinutes ?? this.leadTimeMinutes,
      weatherSafetyEnabled: weatherSafetyEnabled ?? this.weatherSafetyEnabled,
      autoParkEnabled: autoParkEnabled ?? this.autoParkEnabled,
      autoResumeEnabled: autoResumeEnabled ?? this.autoResumeEnabled,
      preferredProvider: preferredProvider ?? this.preferredProvider,
      refreshIntervalSeconds:
          refreshIntervalSeconds ?? this.refreshIntervalSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (triggerDistanceKm.present) {
      map['trigger_distance_km'] = Variable<double>(triggerDistanceKm.value);
    }
    if (cloudDensityThreshold.present) {
      map['cloud_density_threshold'] =
          Variable<double>(cloudDensityThreshold.value);
    }
    if (leadTimeMinutes.present) {
      map['lead_time_minutes'] = Variable<int>(leadTimeMinutes.value);
    }
    if (weatherSafetyEnabled.present) {
      map['weather_safety_enabled'] =
          Variable<bool>(weatherSafetyEnabled.value);
    }
    if (autoParkEnabled.present) {
      map['auto_park_enabled'] = Variable<bool>(autoParkEnabled.value);
    }
    if (autoResumeEnabled.present) {
      map['auto_resume_enabled'] = Variable<bool>(autoResumeEnabled.value);
    }
    if (preferredProvider.present) {
      map['preferred_provider'] = Variable<String>(preferredProvider.value);
    }
    if (refreshIntervalSeconds.present) {
      map['refresh_interval_seconds'] =
          Variable<int>(refreshIntervalSeconds.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WeatherSettingsCompanion(')
          ..write('id: $id, ')
          ..write('triggerDistanceKm: $triggerDistanceKm, ')
          ..write('cloudDensityThreshold: $cloudDensityThreshold, ')
          ..write('leadTimeMinutes: $leadTimeMinutes, ')
          ..write('weatherSafetyEnabled: $weatherSafetyEnabled, ')
          ..write('autoParkEnabled: $autoParkEnabled, ')
          ..write('autoResumeEnabled: $autoResumeEnabled, ')
          ..write('preferredProvider: $preferredProvider, ')
          ..write('refreshIntervalSeconds: $refreshIntervalSeconds, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $FlatHistoryTable extends FlatHistory
    with TableInfo<$FlatHistoryTable, FlatHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FlatHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _equipmentProfileIdMeta =
      const VerificationMeta('equipmentProfileId');
  @override
  late final GeneratedColumn<int> equipmentProfileId = GeneratedColumn<int>(
      'equipment_profile_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _filterNameMeta =
      const VerificationMeta('filterName');
  @override
  late final GeneratedColumn<String> filterName = GeneratedColumn<String>(
      'filter_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _exposureTimeMeta =
      const VerificationMeta('exposureTime');
  @override
  late final GeneratedColumn<double> exposureTime = GeneratedColumn<double>(
      'exposure_time', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _histogramTargetMeta =
      const VerificationMeta('histogramTarget');
  @override
  late final GeneratedColumn<double> histogramTarget = GeneratedColumn<double>(
      'histogram_target', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _actualAduMeta =
      const VerificationMeta('actualAdu');
  @override
  late final GeneratedColumn<int> actualAdu = GeneratedColumn<int>(
      'actual_adu', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _panelBrightnessMeta =
      const VerificationMeta('panelBrightness');
  @override
  late final GeneratedColumn<int> panelBrightness = GeneratedColumn<int>(
      'panel_brightness', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _skyAduRateMeta =
      const VerificationMeta('skyAduRate');
  @override
  late final GeneratedColumn<double> skyAduRate = GeneratedColumn<double>(
      'sky_adu_rate', aliasedName, true,
      type: DriftSqlType.double, requiredDuringInsert: false);
  static const VerificationMeta _twilightPhaseMeta =
      const VerificationMeta('twilightPhase');
  @override
  late final GeneratedColumn<String> twilightPhase = GeneratedColumn<String>(
      'twilight_phase', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _gainMeta = const VerificationMeta('gain');
  @override
  late final GeneratedColumn<int> gain = GeneratedColumn<int>(
      'gain', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _binningMeta =
      const VerificationMeta('binning');
  @override
  late final GeneratedColumn<int> binning = GeneratedColumn<int>(
      'binning', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        equipmentProfileId,
        filterName,
        exposureTime,
        histogramTarget,
        actualAdu,
        panelBrightness,
        skyAduRate,
        twilightPhase,
        gain,
        binning,
        timestamp
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'flat_history';
  @override
  VerificationContext validateIntegrity(Insertable<FlatHistoryEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('equipment_profile_id')) {
      context.handle(
          _equipmentProfileIdMeta,
          equipmentProfileId.isAcceptableOrUnknown(
              data['equipment_profile_id']!, _equipmentProfileIdMeta));
    }
    if (data.containsKey('filter_name')) {
      context.handle(
          _filterNameMeta,
          filterName.isAcceptableOrUnknown(
              data['filter_name']!, _filterNameMeta));
    } else if (isInserting) {
      context.missing(_filterNameMeta);
    }
    if (data.containsKey('exposure_time')) {
      context.handle(
          _exposureTimeMeta,
          exposureTime.isAcceptableOrUnknown(
              data['exposure_time']!, _exposureTimeMeta));
    } else if (isInserting) {
      context.missing(_exposureTimeMeta);
    }
    if (data.containsKey('histogram_target')) {
      context.handle(
          _histogramTargetMeta,
          histogramTarget.isAcceptableOrUnknown(
              data['histogram_target']!, _histogramTargetMeta));
    } else if (isInserting) {
      context.missing(_histogramTargetMeta);
    }
    if (data.containsKey('actual_adu')) {
      context.handle(_actualAduMeta,
          actualAdu.isAcceptableOrUnknown(data['actual_adu']!, _actualAduMeta));
    } else if (isInserting) {
      context.missing(_actualAduMeta);
    }
    if (data.containsKey('panel_brightness')) {
      context.handle(
          _panelBrightnessMeta,
          panelBrightness.isAcceptableOrUnknown(
              data['panel_brightness']!, _panelBrightnessMeta));
    }
    if (data.containsKey('sky_adu_rate')) {
      context.handle(
          _skyAduRateMeta,
          skyAduRate.isAcceptableOrUnknown(
              data['sky_adu_rate']!, _skyAduRateMeta));
    }
    if (data.containsKey('twilight_phase')) {
      context.handle(
          _twilightPhaseMeta,
          twilightPhase.isAcceptableOrUnknown(
              data['twilight_phase']!, _twilightPhaseMeta));
    }
    if (data.containsKey('gain')) {
      context.handle(
          _gainMeta, gain.isAcceptableOrUnknown(data['gain']!, _gainMeta));
    }
    if (data.containsKey('binning')) {
      context.handle(_binningMeta,
          binning.isAcceptableOrUnknown(data['binning']!, _binningMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FlatHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FlatHistoryEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      equipmentProfileId: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}equipment_profile_id']),
      filterName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filter_name'])!,
      exposureTime: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}exposure_time'])!,
      histogramTarget: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}histogram_target'])!,
      actualAdu: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}actual_adu'])!,
      panelBrightness: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}panel_brightness']),
      skyAduRate: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}sky_adu_rate']),
      twilightPhase: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}twilight_phase']),
      gain: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}gain'])!,
      binning: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}binning'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
    );
  }

  @override
  $FlatHistoryTable createAlias(String alias) {
    return $FlatHistoryTable(attachedDatabase, alias);
  }
}

class FlatHistoryEntry extends DataClass
    implements Insertable<FlatHistoryEntry> {
  final int id;

  /// Reference to equipment profile used
  final int? equipmentProfileId;

  /// Filter name (e.g., "L", "R", "Ha")
  final String filterName;

  /// Optimal exposure time found (seconds)
  final double exposureTime;

  /// Target histogram percentage (0-100)
  final double histogramTarget;

  /// Actual ADU value achieved
  final int actualAdu;

  /// Panel brightness used (0-255, null for sky flats)
  final int? panelBrightness;

  /// For sky flats: ADU change rate (ADU/second)
  final double? skyAduRate;

  /// Twilight phase: 'dawn', 'dusk', or null for panel
  final String? twilightPhase;

  /// Gain setting used
  final int gain;

  /// Binning used
  final int binning;

  /// When this calibration was performed
  final DateTime timestamp;
  const FlatHistoryEntry(
      {required this.id,
      this.equipmentProfileId,
      required this.filterName,
      required this.exposureTime,
      required this.histogramTarget,
      required this.actualAdu,
      this.panelBrightness,
      this.skyAduRate,
      this.twilightPhase,
      required this.gain,
      required this.binning,
      required this.timestamp});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || equipmentProfileId != null) {
      map['equipment_profile_id'] = Variable<int>(equipmentProfileId);
    }
    map['filter_name'] = Variable<String>(filterName);
    map['exposure_time'] = Variable<double>(exposureTime);
    map['histogram_target'] = Variable<double>(histogramTarget);
    map['actual_adu'] = Variable<int>(actualAdu);
    if (!nullToAbsent || panelBrightness != null) {
      map['panel_brightness'] = Variable<int>(panelBrightness);
    }
    if (!nullToAbsent || skyAduRate != null) {
      map['sky_adu_rate'] = Variable<double>(skyAduRate);
    }
    if (!nullToAbsent || twilightPhase != null) {
      map['twilight_phase'] = Variable<String>(twilightPhase);
    }
    map['gain'] = Variable<int>(gain);
    map['binning'] = Variable<int>(binning);
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  FlatHistoryCompanion toCompanion(bool nullToAbsent) {
    return FlatHistoryCompanion(
      id: Value(id),
      equipmentProfileId: equipmentProfileId == null && nullToAbsent
          ? const Value.absent()
          : Value(equipmentProfileId),
      filterName: Value(filterName),
      exposureTime: Value(exposureTime),
      histogramTarget: Value(histogramTarget),
      actualAdu: Value(actualAdu),
      panelBrightness: panelBrightness == null && nullToAbsent
          ? const Value.absent()
          : Value(panelBrightness),
      skyAduRate: skyAduRate == null && nullToAbsent
          ? const Value.absent()
          : Value(skyAduRate),
      twilightPhase: twilightPhase == null && nullToAbsent
          ? const Value.absent()
          : Value(twilightPhase),
      gain: Value(gain),
      binning: Value(binning),
      timestamp: Value(timestamp),
    );
  }

  factory FlatHistoryEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FlatHistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      equipmentProfileId: serializer.fromJson<int?>(json['equipmentProfileId']),
      filterName: serializer.fromJson<String>(json['filterName']),
      exposureTime: serializer.fromJson<double>(json['exposureTime']),
      histogramTarget: serializer.fromJson<double>(json['histogramTarget']),
      actualAdu: serializer.fromJson<int>(json['actualAdu']),
      panelBrightness: serializer.fromJson<int?>(json['panelBrightness']),
      skyAduRate: serializer.fromJson<double?>(json['skyAduRate']),
      twilightPhase: serializer.fromJson<String?>(json['twilightPhase']),
      gain: serializer.fromJson<int>(json['gain']),
      binning: serializer.fromJson<int>(json['binning']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'equipmentProfileId': serializer.toJson<int?>(equipmentProfileId),
      'filterName': serializer.toJson<String>(filterName),
      'exposureTime': serializer.toJson<double>(exposureTime),
      'histogramTarget': serializer.toJson<double>(histogramTarget),
      'actualAdu': serializer.toJson<int>(actualAdu),
      'panelBrightness': serializer.toJson<int?>(panelBrightness),
      'skyAduRate': serializer.toJson<double?>(skyAduRate),
      'twilightPhase': serializer.toJson<String?>(twilightPhase),
      'gain': serializer.toJson<int>(gain),
      'binning': serializer.toJson<int>(binning),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  FlatHistoryEntry copyWith(
          {int? id,
          Value<int?> equipmentProfileId = const Value.absent(),
          String? filterName,
          double? exposureTime,
          double? histogramTarget,
          int? actualAdu,
          Value<int?> panelBrightness = const Value.absent(),
          Value<double?> skyAduRate = const Value.absent(),
          Value<String?> twilightPhase = const Value.absent(),
          int? gain,
          int? binning,
          DateTime? timestamp}) =>
      FlatHistoryEntry(
        id: id ?? this.id,
        equipmentProfileId: equipmentProfileId.present
            ? equipmentProfileId.value
            : this.equipmentProfileId,
        filterName: filterName ?? this.filterName,
        exposureTime: exposureTime ?? this.exposureTime,
        histogramTarget: histogramTarget ?? this.histogramTarget,
        actualAdu: actualAdu ?? this.actualAdu,
        panelBrightness: panelBrightness.present
            ? panelBrightness.value
            : this.panelBrightness,
        skyAduRate: skyAduRate.present ? skyAduRate.value : this.skyAduRate,
        twilightPhase:
            twilightPhase.present ? twilightPhase.value : this.twilightPhase,
        gain: gain ?? this.gain,
        binning: binning ?? this.binning,
        timestamp: timestamp ?? this.timestamp,
      );
  FlatHistoryEntry copyWithCompanion(FlatHistoryCompanion data) {
    return FlatHistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      equipmentProfileId: data.equipmentProfileId.present
          ? data.equipmentProfileId.value
          : this.equipmentProfileId,
      filterName:
          data.filterName.present ? data.filterName.value : this.filterName,
      exposureTime: data.exposureTime.present
          ? data.exposureTime.value
          : this.exposureTime,
      histogramTarget: data.histogramTarget.present
          ? data.histogramTarget.value
          : this.histogramTarget,
      actualAdu: data.actualAdu.present ? data.actualAdu.value : this.actualAdu,
      panelBrightness: data.panelBrightness.present
          ? data.panelBrightness.value
          : this.panelBrightness,
      skyAduRate:
          data.skyAduRate.present ? data.skyAduRate.value : this.skyAduRate,
      twilightPhase: data.twilightPhase.present
          ? data.twilightPhase.value
          : this.twilightPhase,
      gain: data.gain.present ? data.gain.value : this.gain,
      binning: data.binning.present ? data.binning.value : this.binning,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FlatHistoryEntry(')
          ..write('id: $id, ')
          ..write('equipmentProfileId: $equipmentProfileId, ')
          ..write('filterName: $filterName, ')
          ..write('exposureTime: $exposureTime, ')
          ..write('histogramTarget: $histogramTarget, ')
          ..write('actualAdu: $actualAdu, ')
          ..write('panelBrightness: $panelBrightness, ')
          ..write('skyAduRate: $skyAduRate, ')
          ..write('twilightPhase: $twilightPhase, ')
          ..write('gain: $gain, ')
          ..write('binning: $binning, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      equipmentProfileId,
      filterName,
      exposureTime,
      histogramTarget,
      actualAdu,
      panelBrightness,
      skyAduRate,
      twilightPhase,
      gain,
      binning,
      timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FlatHistoryEntry &&
          other.id == this.id &&
          other.equipmentProfileId == this.equipmentProfileId &&
          other.filterName == this.filterName &&
          other.exposureTime == this.exposureTime &&
          other.histogramTarget == this.histogramTarget &&
          other.actualAdu == this.actualAdu &&
          other.panelBrightness == this.panelBrightness &&
          other.skyAduRate == this.skyAduRate &&
          other.twilightPhase == this.twilightPhase &&
          other.gain == this.gain &&
          other.binning == this.binning &&
          other.timestamp == this.timestamp);
}

class FlatHistoryCompanion extends UpdateCompanion<FlatHistoryEntry> {
  final Value<int> id;
  final Value<int?> equipmentProfileId;
  final Value<String> filterName;
  final Value<double> exposureTime;
  final Value<double> histogramTarget;
  final Value<int> actualAdu;
  final Value<int?> panelBrightness;
  final Value<double?> skyAduRate;
  final Value<String?> twilightPhase;
  final Value<int> gain;
  final Value<int> binning;
  final Value<DateTime> timestamp;
  const FlatHistoryCompanion({
    this.id = const Value.absent(),
    this.equipmentProfileId = const Value.absent(),
    this.filterName = const Value.absent(),
    this.exposureTime = const Value.absent(),
    this.histogramTarget = const Value.absent(),
    this.actualAdu = const Value.absent(),
    this.panelBrightness = const Value.absent(),
    this.skyAduRate = const Value.absent(),
    this.twilightPhase = const Value.absent(),
    this.gain = const Value.absent(),
    this.binning = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  FlatHistoryCompanion.insert({
    this.id = const Value.absent(),
    this.equipmentProfileId = const Value.absent(),
    required String filterName,
    required double exposureTime,
    required double histogramTarget,
    required int actualAdu,
    this.panelBrightness = const Value.absent(),
    this.skyAduRate = const Value.absent(),
    this.twilightPhase = const Value.absent(),
    this.gain = const Value.absent(),
    this.binning = const Value.absent(),
    this.timestamp = const Value.absent(),
  })  : filterName = Value(filterName),
        exposureTime = Value(exposureTime),
        histogramTarget = Value(histogramTarget),
        actualAdu = Value(actualAdu);
  static Insertable<FlatHistoryEntry> custom({
    Expression<int>? id,
    Expression<int>? equipmentProfileId,
    Expression<String>? filterName,
    Expression<double>? exposureTime,
    Expression<double>? histogramTarget,
    Expression<int>? actualAdu,
    Expression<int>? panelBrightness,
    Expression<double>? skyAduRate,
    Expression<String>? twilightPhase,
    Expression<int>? gain,
    Expression<int>? binning,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (equipmentProfileId != null)
        'equipment_profile_id': equipmentProfileId,
      if (filterName != null) 'filter_name': filterName,
      if (exposureTime != null) 'exposure_time': exposureTime,
      if (histogramTarget != null) 'histogram_target': histogramTarget,
      if (actualAdu != null) 'actual_adu': actualAdu,
      if (panelBrightness != null) 'panel_brightness': panelBrightness,
      if (skyAduRate != null) 'sky_adu_rate': skyAduRate,
      if (twilightPhase != null) 'twilight_phase': twilightPhase,
      if (gain != null) 'gain': gain,
      if (binning != null) 'binning': binning,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  FlatHistoryCompanion copyWith(
      {Value<int>? id,
      Value<int?>? equipmentProfileId,
      Value<String>? filterName,
      Value<double>? exposureTime,
      Value<double>? histogramTarget,
      Value<int>? actualAdu,
      Value<int?>? panelBrightness,
      Value<double?>? skyAduRate,
      Value<String?>? twilightPhase,
      Value<int>? gain,
      Value<int>? binning,
      Value<DateTime>? timestamp}) {
    return FlatHistoryCompanion(
      id: id ?? this.id,
      equipmentProfileId: equipmentProfileId ?? this.equipmentProfileId,
      filterName: filterName ?? this.filterName,
      exposureTime: exposureTime ?? this.exposureTime,
      histogramTarget: histogramTarget ?? this.histogramTarget,
      actualAdu: actualAdu ?? this.actualAdu,
      panelBrightness: panelBrightness ?? this.panelBrightness,
      skyAduRate: skyAduRate ?? this.skyAduRate,
      twilightPhase: twilightPhase ?? this.twilightPhase,
      gain: gain ?? this.gain,
      binning: binning ?? this.binning,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (equipmentProfileId.present) {
      map['equipment_profile_id'] = Variable<int>(equipmentProfileId.value);
    }
    if (filterName.present) {
      map['filter_name'] = Variable<String>(filterName.value);
    }
    if (exposureTime.present) {
      map['exposure_time'] = Variable<double>(exposureTime.value);
    }
    if (histogramTarget.present) {
      map['histogram_target'] = Variable<double>(histogramTarget.value);
    }
    if (actualAdu.present) {
      map['actual_adu'] = Variable<int>(actualAdu.value);
    }
    if (panelBrightness.present) {
      map['panel_brightness'] = Variable<int>(panelBrightness.value);
    }
    if (skyAduRate.present) {
      map['sky_adu_rate'] = Variable<double>(skyAduRate.value);
    }
    if (twilightPhase.present) {
      map['twilight_phase'] = Variable<String>(twilightPhase.value);
    }
    if (gain.present) {
      map['gain'] = Variable<int>(gain.value);
    }
    if (binning.present) {
      map['binning'] = Variable<int>(binning.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FlatHistoryCompanion(')
          ..write('id: $id, ')
          ..write('equipmentProfileId: $equipmentProfileId, ')
          ..write('filterName: $filterName, ')
          ..write('exposureTime: $exposureTime, ')
          ..write('histogramTarget: $histogramTarget, ')
          ..write('actualAdu: $actualAdu, ')
          ..write('panelBrightness: $panelBrightness, ')
          ..write('skyAduRate: $skyAduRate, ')
          ..write('twilightPhase: $twilightPhase, ')
          ..write('gain: $gain, ')
          ..write('binning: $binning, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

class $TutorialProgressTable extends TutorialProgress
    with TableInfo<$TutorialProgressTable, TutorialProgressEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TutorialProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _lastStepIndexMeta =
      const VerificationMeta('lastStepIndex');
  @override
  late final GeneratedColumn<int> lastStepIndex = GeneratedColumn<int>(
      'last_step_index', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _completedMeta =
      const VerificationMeta('completed');
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
      'completed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("completed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _dismissedMeta =
      const VerificationMeta('dismissed');
  @override
  late final GeneratedColumn<bool> dismissed = GeneratedColumn<bool>(
      'dismissed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("dismissed" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        category,
        lastStepIndex,
        completed,
        startedAt,
        completedAt,
        dismissed
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'tutorial_progress';
  @override
  VerificationContext validateIntegrity(
      Insertable<TutorialProgressEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('last_step_index')) {
      context.handle(
          _lastStepIndexMeta,
          lastStepIndex.isAcceptableOrUnknown(
              data['last_step_index']!, _lastStepIndexMeta));
    }
    if (data.containsKey('completed')) {
      context.handle(_completedMeta,
          completed.isAcceptableOrUnknown(data['completed']!, _completedMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    if (data.containsKey('dismissed')) {
      context.handle(_dismissedMeta,
          dismissed.isAcceptableOrUnknown(data['dismissed']!, _dismissedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TutorialProgressEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TutorialProgressEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      lastStepIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_step_index'])!,
      completed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}completed'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at']),
      dismissed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}dismissed'])!,
    );
  }

  @override
  $TutorialProgressTable createAlias(String alias) {
    return $TutorialProgressTable(attachedDatabase, alias);
  }
}

class TutorialProgressEntry extends DataClass
    implements Insertable<TutorialProgressEntry> {
  /// Auto-incrementing primary key
  final int id;

  /// Tutorial category name (TutorialCategory.name, e.g., 'firstLight')
  /// Unique constraint ensures only one progress entry per category
  final String category;

  /// Last step index the user was on (0-indexed)
  final int lastStepIndex;

  /// Whether this tutorial has been fully completed
  final bool completed;

  /// When the user first started this tutorial
  final DateTime startedAt;

  /// When the tutorial was completed (null if not completed)
  final DateTime? completedAt;

  /// Whether the user explicitly dismissed this tutorial without completing
  final bool dismissed;
  const TutorialProgressEntry(
      {required this.id,
      required this.category,
      required this.lastStepIndex,
      required this.completed,
      required this.startedAt,
      this.completedAt,
      required this.dismissed});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['category'] = Variable<String>(category);
    map['last_step_index'] = Variable<int>(lastStepIndex);
    map['completed'] = Variable<bool>(completed);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    map['dismissed'] = Variable<bool>(dismissed);
    return map;
  }

  TutorialProgressCompanion toCompanion(bool nullToAbsent) {
    return TutorialProgressCompanion(
      id: Value(id),
      category: Value(category),
      lastStepIndex: Value(lastStepIndex),
      completed: Value(completed),
      startedAt: Value(startedAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      dismissed: Value(dismissed),
    );
  }

  factory TutorialProgressEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TutorialProgressEntry(
      id: serializer.fromJson<int>(json['id']),
      category: serializer.fromJson<String>(json['category']),
      lastStepIndex: serializer.fromJson<int>(json['lastStepIndex']),
      completed: serializer.fromJson<bool>(json['completed']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      dismissed: serializer.fromJson<bool>(json['dismissed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'category': serializer.toJson<String>(category),
      'lastStepIndex': serializer.toJson<int>(lastStepIndex),
      'completed': serializer.toJson<bool>(completed),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'dismissed': serializer.toJson<bool>(dismissed),
    };
  }

  TutorialProgressEntry copyWith(
          {int? id,
          String? category,
          int? lastStepIndex,
          bool? completed,
          DateTime? startedAt,
          Value<DateTime?> completedAt = const Value.absent(),
          bool? dismissed}) =>
      TutorialProgressEntry(
        id: id ?? this.id,
        category: category ?? this.category,
        lastStepIndex: lastStepIndex ?? this.lastStepIndex,
        completed: completed ?? this.completed,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
        dismissed: dismissed ?? this.dismissed,
      );
  TutorialProgressEntry copyWithCompanion(TutorialProgressCompanion data) {
    return TutorialProgressEntry(
      id: data.id.present ? data.id.value : this.id,
      category: data.category.present ? data.category.value : this.category,
      lastStepIndex: data.lastStepIndex.present
          ? data.lastStepIndex.value
          : this.lastStepIndex,
      completed: data.completed.present ? data.completed.value : this.completed,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      dismissed: data.dismissed.present ? data.dismissed.value : this.dismissed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TutorialProgressEntry(')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('lastStepIndex: $lastStepIndex, ')
          ..write('completed: $completed, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('dismissed: $dismissed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, category, lastStepIndex, completed,
      startedAt, completedAt, dismissed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TutorialProgressEntry &&
          other.id == this.id &&
          other.category == this.category &&
          other.lastStepIndex == this.lastStepIndex &&
          other.completed == this.completed &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.dismissed == this.dismissed);
}

class TutorialProgressCompanion extends UpdateCompanion<TutorialProgressEntry> {
  final Value<int> id;
  final Value<String> category;
  final Value<int> lastStepIndex;
  final Value<bool> completed;
  final Value<DateTime> startedAt;
  final Value<DateTime?> completedAt;
  final Value<bool> dismissed;
  const TutorialProgressCompanion({
    this.id = const Value.absent(),
    this.category = const Value.absent(),
    this.lastStepIndex = const Value.absent(),
    this.completed = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.dismissed = const Value.absent(),
  });
  TutorialProgressCompanion.insert({
    this.id = const Value.absent(),
    required String category,
    this.lastStepIndex = const Value.absent(),
    this.completed = const Value.absent(),
    required DateTime startedAt,
    this.completedAt = const Value.absent(),
    this.dismissed = const Value.absent(),
  })  : category = Value(category),
        startedAt = Value(startedAt);
  static Insertable<TutorialProgressEntry> custom({
    Expression<int>? id,
    Expression<String>? category,
    Expression<int>? lastStepIndex,
    Expression<bool>? completed,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<bool>? dismissed,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (category != null) 'category': category,
      if (lastStepIndex != null) 'last_step_index': lastStepIndex,
      if (completed != null) 'completed': completed,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (dismissed != null) 'dismissed': dismissed,
    });
  }

  TutorialProgressCompanion copyWith(
      {Value<int>? id,
      Value<String>? category,
      Value<int>? lastStepIndex,
      Value<bool>? completed,
      Value<DateTime>? startedAt,
      Value<DateTime?>? completedAt,
      Value<bool>? dismissed}) {
    return TutorialProgressCompanion(
      id: id ?? this.id,
      category: category ?? this.category,
      lastStepIndex: lastStepIndex ?? this.lastStepIndex,
      completed: completed ?? this.completed,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      dismissed: dismissed ?? this.dismissed,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (lastStepIndex.present) {
      map['last_step_index'] = Variable<int>(lastStepIndex.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (dismissed.present) {
      map['dismissed'] = Variable<bool>(dismissed.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TutorialProgressCompanion(')
          ..write('id: $id, ')
          ..write('category: $category, ')
          ..write('lastStepIndex: $lastStepIndex, ')
          ..write('completed: $completed, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('dismissed: $dismissed')
          ..write(')'))
        .toString();
  }
}

class $PolarAlignmentHistoryTable extends PolarAlignmentHistory
    with TableInfo<$PolarAlignmentHistoryTable, PolarAlignmentHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PolarAlignmentHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _equipmentProfileIdMeta =
      const VerificationMeta('equipmentProfileId');
  @override
  late final GeneratedColumn<String> equipmentProfileId =
      GeneratedColumn<String>('equipment_profile_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _initialAzimuthErrorMeta =
      const VerificationMeta('initialAzimuthError');
  @override
  late final GeneratedColumn<double> initialAzimuthError =
      GeneratedColumn<double>('initial_azimuth_error', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _initialAltitudeErrorMeta =
      const VerificationMeta('initialAltitudeError');
  @override
  late final GeneratedColumn<double> initialAltitudeError =
      GeneratedColumn<double>('initial_altitude_error', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _initialTotalErrorMeta =
      const VerificationMeta('initialTotalError');
  @override
  late final GeneratedColumn<double> initialTotalError =
      GeneratedColumn<double>('initial_total_error', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _finalAzimuthErrorMeta =
      const VerificationMeta('finalAzimuthError');
  @override
  late final GeneratedColumn<double> finalAzimuthError =
      GeneratedColumn<double>('final_azimuth_error', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _finalAltitudeErrorMeta =
      const VerificationMeta('finalAltitudeError');
  @override
  late final GeneratedColumn<double> finalAltitudeError =
      GeneratedColumn<double>('final_altitude_error', aliasedName, false,
          type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _finalTotalErrorMeta =
      const VerificationMeta('finalTotalError');
  @override
  late final GeneratedColumn<double> finalTotalError = GeneratedColumn<double>(
      'final_total_error', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _autoCompletedMeta =
      const VerificationMeta('autoCompleted');
  @override
  late final GeneratedColumn<bool> autoCompleted = GeneratedColumn<bool>(
      'auto_completed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("auto_completed" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isNorthMeta =
      const VerificationMeta('isNorth');
  @override
  late final GeneratedColumn<bool> isNorth = GeneratedColumn<bool>(
      'is_north', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_north" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _configJsonMeta =
      const VerificationMeta('configJson');
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
      'config_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        equipmentProfileId,
        initialAzimuthError,
        initialAltitudeError,
        initialTotalError,
        finalAzimuthError,
        finalAltitudeError,
        finalTotalError,
        startedAt,
        completedAt,
        autoCompleted,
        isNorth,
        configJson
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'polar_alignment_history';
  @override
  VerificationContext validateIntegrity(
      Insertable<PolarAlignmentHistoryEntry> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('equipment_profile_id')) {
      context.handle(
          _equipmentProfileIdMeta,
          equipmentProfileId.isAcceptableOrUnknown(
              data['equipment_profile_id']!, _equipmentProfileIdMeta));
    }
    if (data.containsKey('initial_azimuth_error')) {
      context.handle(
          _initialAzimuthErrorMeta,
          initialAzimuthError.isAcceptableOrUnknown(
              data['initial_azimuth_error']!, _initialAzimuthErrorMeta));
    } else if (isInserting) {
      context.missing(_initialAzimuthErrorMeta);
    }
    if (data.containsKey('initial_altitude_error')) {
      context.handle(
          _initialAltitudeErrorMeta,
          initialAltitudeError.isAcceptableOrUnknown(
              data['initial_altitude_error']!, _initialAltitudeErrorMeta));
    } else if (isInserting) {
      context.missing(_initialAltitudeErrorMeta);
    }
    if (data.containsKey('initial_total_error')) {
      context.handle(
          _initialTotalErrorMeta,
          initialTotalError.isAcceptableOrUnknown(
              data['initial_total_error']!, _initialTotalErrorMeta));
    } else if (isInserting) {
      context.missing(_initialTotalErrorMeta);
    }
    if (data.containsKey('final_azimuth_error')) {
      context.handle(
          _finalAzimuthErrorMeta,
          finalAzimuthError.isAcceptableOrUnknown(
              data['final_azimuth_error']!, _finalAzimuthErrorMeta));
    } else if (isInserting) {
      context.missing(_finalAzimuthErrorMeta);
    }
    if (data.containsKey('final_altitude_error')) {
      context.handle(
          _finalAltitudeErrorMeta,
          finalAltitudeError.isAcceptableOrUnknown(
              data['final_altitude_error']!, _finalAltitudeErrorMeta));
    } else if (isInserting) {
      context.missing(_finalAltitudeErrorMeta);
    }
    if (data.containsKey('final_total_error')) {
      context.handle(
          _finalTotalErrorMeta,
          finalTotalError.isAcceptableOrUnknown(
              data['final_total_error']!, _finalTotalErrorMeta));
    } else if (isInserting) {
      context.missing(_finalTotalErrorMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    } else if (isInserting) {
      context.missing(_completedAtMeta);
    }
    if (data.containsKey('auto_completed')) {
      context.handle(
          _autoCompletedMeta,
          autoCompleted.isAcceptableOrUnknown(
              data['auto_completed']!, _autoCompletedMeta));
    }
    if (data.containsKey('is_north')) {
      context.handle(_isNorthMeta,
          isNorth.isAcceptableOrUnknown(data['is_north']!, _isNorthMeta));
    }
    if (data.containsKey('config_json')) {
      context.handle(
          _configJsonMeta,
          configJson.isAcceptableOrUnknown(
              data['config_json']!, _configJsonMeta));
    } else if (isInserting) {
      context.missing(_configJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PolarAlignmentHistoryEntry map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PolarAlignmentHistoryEntry(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      equipmentProfileId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}equipment_profile_id']),
      initialAzimuthError: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}initial_azimuth_error'])!,
      initialAltitudeError: attachedDatabase.typeMapping.read(
          DriftSqlType.double,
          data['${effectivePrefix}initial_altitude_error'])!,
      initialTotalError: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}initial_total_error'])!,
      finalAzimuthError: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}final_azimuth_error'])!,
      finalAltitudeError: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}final_altitude_error'])!,
      finalTotalError: attachedDatabase.typeMapping.read(
          DriftSqlType.double, data['${effectivePrefix}final_total_error'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at'])!,
      autoCompleted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}auto_completed'])!,
      isNorth: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_north'])!,
      configJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}config_json'])!,
    );
  }

  @override
  $PolarAlignmentHistoryTable createAlias(String alias) {
    return $PolarAlignmentHistoryTable(attachedDatabase, alias);
  }
}

class PolarAlignmentHistoryEntry extends DataClass
    implements Insertable<PolarAlignmentHistoryEntry> {
  /// Primary key
  final int id;

  /// Reference to equipment profile used (nullable for unassociated sessions)
  final String? equipmentProfileId;

  /// Initial azimuth error in arcseconds
  final double initialAzimuthError;

  /// Initial altitude error in arcseconds
  final double initialAltitudeError;

  /// Initial total error in arcseconds
  final double initialTotalError;

  /// Final azimuth error in arcseconds
  final double finalAzimuthError;

  /// Final altitude error in arcseconds
  final double finalAltitudeError;

  /// Final total error in arcseconds
  final double finalTotalError;

  /// When alignment started
  final DateTime startedAt;

  /// When alignment completed
  final DateTime completedAt;

  /// Whether alignment was auto-completed (reached threshold)
  final bool autoCompleted;

  /// Whether observing from northern hemisphere
  final bool isNorth;

  /// Full configuration JSON for reference
  final String configJson;
  const PolarAlignmentHistoryEntry(
      {required this.id,
      this.equipmentProfileId,
      required this.initialAzimuthError,
      required this.initialAltitudeError,
      required this.initialTotalError,
      required this.finalAzimuthError,
      required this.finalAltitudeError,
      required this.finalTotalError,
      required this.startedAt,
      required this.completedAt,
      required this.autoCompleted,
      required this.isNorth,
      required this.configJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || equipmentProfileId != null) {
      map['equipment_profile_id'] = Variable<String>(equipmentProfileId);
    }
    map['initial_azimuth_error'] = Variable<double>(initialAzimuthError);
    map['initial_altitude_error'] = Variable<double>(initialAltitudeError);
    map['initial_total_error'] = Variable<double>(initialTotalError);
    map['final_azimuth_error'] = Variable<double>(finalAzimuthError);
    map['final_altitude_error'] = Variable<double>(finalAltitudeError);
    map['final_total_error'] = Variable<double>(finalTotalError);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['completed_at'] = Variable<DateTime>(completedAt);
    map['auto_completed'] = Variable<bool>(autoCompleted);
    map['is_north'] = Variable<bool>(isNorth);
    map['config_json'] = Variable<String>(configJson);
    return map;
  }

  PolarAlignmentHistoryCompanion toCompanion(bool nullToAbsent) {
    return PolarAlignmentHistoryCompanion(
      id: Value(id),
      equipmentProfileId: equipmentProfileId == null && nullToAbsent
          ? const Value.absent()
          : Value(equipmentProfileId),
      initialAzimuthError: Value(initialAzimuthError),
      initialAltitudeError: Value(initialAltitudeError),
      initialTotalError: Value(initialTotalError),
      finalAzimuthError: Value(finalAzimuthError),
      finalAltitudeError: Value(finalAltitudeError),
      finalTotalError: Value(finalTotalError),
      startedAt: Value(startedAt),
      completedAt: Value(completedAt),
      autoCompleted: Value(autoCompleted),
      isNorth: Value(isNorth),
      configJson: Value(configJson),
    );
  }

  factory PolarAlignmentHistoryEntry.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PolarAlignmentHistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      equipmentProfileId:
          serializer.fromJson<String?>(json['equipmentProfileId']),
      initialAzimuthError:
          serializer.fromJson<double>(json['initialAzimuthError']),
      initialAltitudeError:
          serializer.fromJson<double>(json['initialAltitudeError']),
      initialTotalError: serializer.fromJson<double>(json['initialTotalError']),
      finalAzimuthError: serializer.fromJson<double>(json['finalAzimuthError']),
      finalAltitudeError:
          serializer.fromJson<double>(json['finalAltitudeError']),
      finalTotalError: serializer.fromJson<double>(json['finalTotalError']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
      autoCompleted: serializer.fromJson<bool>(json['autoCompleted']),
      isNorth: serializer.fromJson<bool>(json['isNorth']),
      configJson: serializer.fromJson<String>(json['configJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'equipmentProfileId': serializer.toJson<String?>(equipmentProfileId),
      'initialAzimuthError': serializer.toJson<double>(initialAzimuthError),
      'initialAltitudeError': serializer.toJson<double>(initialAltitudeError),
      'initialTotalError': serializer.toJson<double>(initialTotalError),
      'finalAzimuthError': serializer.toJson<double>(finalAzimuthError),
      'finalAltitudeError': serializer.toJson<double>(finalAltitudeError),
      'finalTotalError': serializer.toJson<double>(finalTotalError),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'completedAt': serializer.toJson<DateTime>(completedAt),
      'autoCompleted': serializer.toJson<bool>(autoCompleted),
      'isNorth': serializer.toJson<bool>(isNorth),
      'configJson': serializer.toJson<String>(configJson),
    };
  }

  PolarAlignmentHistoryEntry copyWith(
          {int? id,
          Value<String?> equipmentProfileId = const Value.absent(),
          double? initialAzimuthError,
          double? initialAltitudeError,
          double? initialTotalError,
          double? finalAzimuthError,
          double? finalAltitudeError,
          double? finalTotalError,
          DateTime? startedAt,
          DateTime? completedAt,
          bool? autoCompleted,
          bool? isNorth,
          String? configJson}) =>
      PolarAlignmentHistoryEntry(
        id: id ?? this.id,
        equipmentProfileId: equipmentProfileId.present
            ? equipmentProfileId.value
            : this.equipmentProfileId,
        initialAzimuthError: initialAzimuthError ?? this.initialAzimuthError,
        initialAltitudeError: initialAltitudeError ?? this.initialAltitudeError,
        initialTotalError: initialTotalError ?? this.initialTotalError,
        finalAzimuthError: finalAzimuthError ?? this.finalAzimuthError,
        finalAltitudeError: finalAltitudeError ?? this.finalAltitudeError,
        finalTotalError: finalTotalError ?? this.finalTotalError,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        autoCompleted: autoCompleted ?? this.autoCompleted,
        isNorth: isNorth ?? this.isNorth,
        configJson: configJson ?? this.configJson,
      );
  PolarAlignmentHistoryEntry copyWithCompanion(
      PolarAlignmentHistoryCompanion data) {
    return PolarAlignmentHistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      equipmentProfileId: data.equipmentProfileId.present
          ? data.equipmentProfileId.value
          : this.equipmentProfileId,
      initialAzimuthError: data.initialAzimuthError.present
          ? data.initialAzimuthError.value
          : this.initialAzimuthError,
      initialAltitudeError: data.initialAltitudeError.present
          ? data.initialAltitudeError.value
          : this.initialAltitudeError,
      initialTotalError: data.initialTotalError.present
          ? data.initialTotalError.value
          : this.initialTotalError,
      finalAzimuthError: data.finalAzimuthError.present
          ? data.finalAzimuthError.value
          : this.finalAzimuthError,
      finalAltitudeError: data.finalAltitudeError.present
          ? data.finalAltitudeError.value
          : this.finalAltitudeError,
      finalTotalError: data.finalTotalError.present
          ? data.finalTotalError.value
          : this.finalTotalError,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      completedAt:
          data.completedAt.present ? data.completedAt.value : this.completedAt,
      autoCompleted: data.autoCompleted.present
          ? data.autoCompleted.value
          : this.autoCompleted,
      isNorth: data.isNorth.present ? data.isNorth.value : this.isNorth,
      configJson:
          data.configJson.present ? data.configJson.value : this.configJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PolarAlignmentHistoryEntry(')
          ..write('id: $id, ')
          ..write('equipmentProfileId: $equipmentProfileId, ')
          ..write('initialAzimuthError: $initialAzimuthError, ')
          ..write('initialAltitudeError: $initialAltitudeError, ')
          ..write('initialTotalError: $initialTotalError, ')
          ..write('finalAzimuthError: $finalAzimuthError, ')
          ..write('finalAltitudeError: $finalAltitudeError, ')
          ..write('finalTotalError: $finalTotalError, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('autoCompleted: $autoCompleted, ')
          ..write('isNorth: $isNorth, ')
          ..write('configJson: $configJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      equipmentProfileId,
      initialAzimuthError,
      initialAltitudeError,
      initialTotalError,
      finalAzimuthError,
      finalAltitudeError,
      finalTotalError,
      startedAt,
      completedAt,
      autoCompleted,
      isNorth,
      configJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PolarAlignmentHistoryEntry &&
          other.id == this.id &&
          other.equipmentProfileId == this.equipmentProfileId &&
          other.initialAzimuthError == this.initialAzimuthError &&
          other.initialAltitudeError == this.initialAltitudeError &&
          other.initialTotalError == this.initialTotalError &&
          other.finalAzimuthError == this.finalAzimuthError &&
          other.finalAltitudeError == this.finalAltitudeError &&
          other.finalTotalError == this.finalTotalError &&
          other.startedAt == this.startedAt &&
          other.completedAt == this.completedAt &&
          other.autoCompleted == this.autoCompleted &&
          other.isNorth == this.isNorth &&
          other.configJson == this.configJson);
}

class PolarAlignmentHistoryCompanion
    extends UpdateCompanion<PolarAlignmentHistoryEntry> {
  final Value<int> id;
  final Value<String?> equipmentProfileId;
  final Value<double> initialAzimuthError;
  final Value<double> initialAltitudeError;
  final Value<double> initialTotalError;
  final Value<double> finalAzimuthError;
  final Value<double> finalAltitudeError;
  final Value<double> finalTotalError;
  final Value<DateTime> startedAt;
  final Value<DateTime> completedAt;
  final Value<bool> autoCompleted;
  final Value<bool> isNorth;
  final Value<String> configJson;
  const PolarAlignmentHistoryCompanion({
    this.id = const Value.absent(),
    this.equipmentProfileId = const Value.absent(),
    this.initialAzimuthError = const Value.absent(),
    this.initialAltitudeError = const Value.absent(),
    this.initialTotalError = const Value.absent(),
    this.finalAzimuthError = const Value.absent(),
    this.finalAltitudeError = const Value.absent(),
    this.finalTotalError = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.autoCompleted = const Value.absent(),
    this.isNorth = const Value.absent(),
    this.configJson = const Value.absent(),
  });
  PolarAlignmentHistoryCompanion.insert({
    this.id = const Value.absent(),
    this.equipmentProfileId = const Value.absent(),
    required double initialAzimuthError,
    required double initialAltitudeError,
    required double initialTotalError,
    required double finalAzimuthError,
    required double finalAltitudeError,
    required double finalTotalError,
    required DateTime startedAt,
    required DateTime completedAt,
    this.autoCompleted = const Value.absent(),
    this.isNorth = const Value.absent(),
    required String configJson,
  })  : initialAzimuthError = Value(initialAzimuthError),
        initialAltitudeError = Value(initialAltitudeError),
        initialTotalError = Value(initialTotalError),
        finalAzimuthError = Value(finalAzimuthError),
        finalAltitudeError = Value(finalAltitudeError),
        finalTotalError = Value(finalTotalError),
        startedAt = Value(startedAt),
        completedAt = Value(completedAt),
        configJson = Value(configJson);
  static Insertable<PolarAlignmentHistoryEntry> custom({
    Expression<int>? id,
    Expression<String>? equipmentProfileId,
    Expression<double>? initialAzimuthError,
    Expression<double>? initialAltitudeError,
    Expression<double>? initialTotalError,
    Expression<double>? finalAzimuthError,
    Expression<double>? finalAltitudeError,
    Expression<double>? finalTotalError,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? completedAt,
    Expression<bool>? autoCompleted,
    Expression<bool>? isNorth,
    Expression<String>? configJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (equipmentProfileId != null)
        'equipment_profile_id': equipmentProfileId,
      if (initialAzimuthError != null)
        'initial_azimuth_error': initialAzimuthError,
      if (initialAltitudeError != null)
        'initial_altitude_error': initialAltitudeError,
      if (initialTotalError != null) 'initial_total_error': initialTotalError,
      if (finalAzimuthError != null) 'final_azimuth_error': finalAzimuthError,
      if (finalAltitudeError != null)
        'final_altitude_error': finalAltitudeError,
      if (finalTotalError != null) 'final_total_error': finalTotalError,
      if (startedAt != null) 'started_at': startedAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (autoCompleted != null) 'auto_completed': autoCompleted,
      if (isNorth != null) 'is_north': isNorth,
      if (configJson != null) 'config_json': configJson,
    });
  }

  PolarAlignmentHistoryCompanion copyWith(
      {Value<int>? id,
      Value<String?>? equipmentProfileId,
      Value<double>? initialAzimuthError,
      Value<double>? initialAltitudeError,
      Value<double>? initialTotalError,
      Value<double>? finalAzimuthError,
      Value<double>? finalAltitudeError,
      Value<double>? finalTotalError,
      Value<DateTime>? startedAt,
      Value<DateTime>? completedAt,
      Value<bool>? autoCompleted,
      Value<bool>? isNorth,
      Value<String>? configJson}) {
    return PolarAlignmentHistoryCompanion(
      id: id ?? this.id,
      equipmentProfileId: equipmentProfileId ?? this.equipmentProfileId,
      initialAzimuthError: initialAzimuthError ?? this.initialAzimuthError,
      initialAltitudeError: initialAltitudeError ?? this.initialAltitudeError,
      initialTotalError: initialTotalError ?? this.initialTotalError,
      finalAzimuthError: finalAzimuthError ?? this.finalAzimuthError,
      finalAltitudeError: finalAltitudeError ?? this.finalAltitudeError,
      finalTotalError: finalTotalError ?? this.finalTotalError,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      autoCompleted: autoCompleted ?? this.autoCompleted,
      isNorth: isNorth ?? this.isNorth,
      configJson: configJson ?? this.configJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (equipmentProfileId.present) {
      map['equipment_profile_id'] = Variable<String>(equipmentProfileId.value);
    }
    if (initialAzimuthError.present) {
      map['initial_azimuth_error'] =
          Variable<double>(initialAzimuthError.value);
    }
    if (initialAltitudeError.present) {
      map['initial_altitude_error'] =
          Variable<double>(initialAltitudeError.value);
    }
    if (initialTotalError.present) {
      map['initial_total_error'] = Variable<double>(initialTotalError.value);
    }
    if (finalAzimuthError.present) {
      map['final_azimuth_error'] = Variable<double>(finalAzimuthError.value);
    }
    if (finalAltitudeError.present) {
      map['final_altitude_error'] = Variable<double>(finalAltitudeError.value);
    }
    if (finalTotalError.present) {
      map['final_total_error'] = Variable<double>(finalTotalError.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (autoCompleted.present) {
      map['auto_completed'] = Variable<bool>(autoCompleted.value);
    }
    if (isNorth.present) {
      map['is_north'] = Variable<bool>(isNorth.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PolarAlignmentHistoryCompanion(')
          ..write('id: $id, ')
          ..write('equipmentProfileId: $equipmentProfileId, ')
          ..write('initialAzimuthError: $initialAzimuthError, ')
          ..write('initialAltitudeError: $initialAltitudeError, ')
          ..write('initialTotalError: $initialTotalError, ')
          ..write('finalAzimuthError: $finalAzimuthError, ')
          ..write('finalAltitudeError: $finalAltitudeError, ')
          ..write('finalTotalError: $finalTotalError, ')
          ..write('startedAt: $startedAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('autoCompleted: $autoCompleted, ')
          ..write('isNorth: $isNorth, ')
          ..write('configJson: $configJson')
          ..write(')'))
        .toString();
  }
}

abstract class _$NightshadeDatabase extends GeneratedDatabase {
  _$NightshadeDatabase(QueryExecutor e) : super(e);
  $NightshadeDatabaseManager get managers => $NightshadeDatabaseManager(this);
  late final $EquipmentProfilesTable equipmentProfiles =
      $EquipmentProfilesTable(this);
  late final $TargetsTable targets = $TargetsTable(this);
  late final $SequencesTable sequences = $SequencesTable(this);
  late final $ImagingSessionsTable imagingSessions =
      $ImagingSessionsTable(this);
  late final $SequenceNodesTable sequenceNodes = $SequenceNodesTable(this);
  late final $SequenceCheckpointsTable sequenceCheckpoints =
      $SequenceCheckpointsTable(this);
  late final $CapturedImagesTable capturedImages = $CapturedImagesTable(this);
  late final $ImageMetadataTable imageMetadata = $ImageMetadataTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $WeatherSettingsTable weatherSettings =
      $WeatherSettingsTable(this);
  late final $FlatHistoryTable flatHistory = $FlatHistoryTable(this);
  late final $TutorialProgressTable tutorialProgress =
      $TutorialProgressTable(this);
  late final $PolarAlignmentHistoryTable polarAlignmentHistory =
      $PolarAlignmentHistoryTable(this);
  late final Index idxProfilesName = Index('idx_profiles_name',
      'CREATE INDEX idx_profiles_name ON equipment_profiles (name)');
  late final Index idxProfilesActive = Index('idx_profiles_active',
      'CREATE INDEX idx_profiles_active ON equipment_profiles (is_active)');
  late final Index idxSessionsTarget = Index('idx_sessions_target',
      'CREATE INDEX idx_sessions_target ON imaging_sessions (target_id)');
  late final Index idxSessionsProfile = Index('idx_sessions_profile',
      'CREATE INDEX idx_sessions_profile ON imaging_sessions (profile_id)');
  late final Index idxSessionsStart = Index('idx_sessions_start',
      'CREATE INDEX idx_sessions_start ON imaging_sessions (start_time)');
  late final Index idxSessionsStatus = Index('idx_sessions_status',
      'CREATE INDEX idx_sessions_status ON imaging_sessions (status)');
  late final Index idxTargetsName = Index(
      'idx_targets_name', 'CREATE INDEX idx_targets_name ON targets (name)');
  late final Index idxTargetsCatalog = Index('idx_targets_catalog',
      'CREATE INDEX idx_targets_catalog ON targets (catalog_id)');
  late final Index idxTargetsPriority = Index('idx_targets_priority',
      'CREATE INDEX idx_targets_priority ON targets (priority)');
  late final Index idxTargetsFavorite = Index('idx_targets_favorite',
      'CREATE INDEX idx_targets_favorite ON targets (is_favorite)');
  late final Index idxTargetsObjectType = Index('idx_targets_object_type',
      'CREATE INDEX idx_targets_object_type ON targets (object_type)');
  late final Index idxSequencesName = Index('idx_sequences_name',
      'CREATE INDEX idx_sequences_name ON sequences (name)');
  late final Index idxSequencesTemplate = Index('idx_sequences_template',
      'CREATE INDEX idx_sequences_template ON sequences (is_template)');
  late final Index idxSequencesUpdated = Index('idx_sequences_updated',
      'CREATE INDEX idx_sequences_updated ON sequences (updated_at)');
  late final Index idxNodesSequence = Index('idx_nodes_sequence',
      'CREATE INDEX idx_nodes_sequence ON sequence_nodes (sequence_id)');
  late final Index idxNodesParent = Index('idx_nodes_parent',
      'CREATE INDEX idx_nodes_parent ON sequence_nodes (parent_node_id)');
  late final Index idxNodesTarget = Index('idx_nodes_target',
      'CREATE INDEX idx_nodes_target ON sequence_nodes (target_id)');
  late final Index idxNodesType = Index('idx_nodes_type',
      'CREATE INDEX idx_nodes_type ON sequence_nodes (node_type)');
  late final Index idxNodesNodeId = Index('idx_nodes_node_id',
      'CREATE INDEX idx_nodes_node_id ON sequence_nodes (node_id)');
  late final Index idxCheckpointsCheckpointedAt = Index(
      'idx_checkpoints_checkpointed_at',
      'CREATE INDEX idx_checkpoints_checkpointed_at ON sequence_checkpoints (checkpointed_at)');
  late final Index idxImagesSession = Index('idx_images_session',
      'CREATE INDEX idx_images_session ON captured_images (session_id)');
  late final Index idxImagesTarget = Index('idx_images_target',
      'CREATE INDEX idx_images_target ON captured_images (target_id)');
  late final Index idxImagesFrameType = Index('idx_images_frame_type',
      'CREATE INDEX idx_images_frame_type ON captured_images (frame_type)');
  late final Index idxImagesCapturedAt = Index('idx_images_captured_at',
      'CREATE INDEX idx_images_captured_at ON captured_images (captured_at)');
  late final Index idxImagesFilter = Index('idx_images_filter',
      'CREATE INDEX idx_images_filter ON captured_images ("filter")');
  late final Index idxImagesAccepted = Index('idx_images_accepted',
      'CREATE INDEX idx_images_accepted ON captured_images (is_accepted)');
  late final Index idxImagesSessionFrame = Index('idx_images_session_frame',
      'CREATE INDEX idx_images_session_frame ON captured_images (session_id, frame_type)');
  late final Index idxMetadataImage = Index('idx_metadata_image',
      'CREATE INDEX idx_metadata_image ON image_metadata (image_id)');
  late final Index idxMetadataKey = Index('idx_metadata_key',
      'CREATE INDEX idx_metadata_key ON image_metadata ("key")');
  late final Index idxFlatHistoryProfile = Index('idx_flat_history_profile',
      'CREATE INDEX idx_flat_history_profile ON flat_history (equipment_profile_id)');
  late final Index idxFlatHistoryFilter = Index('idx_flat_history_filter',
      'CREATE INDEX idx_flat_history_filter ON flat_history (filter_name)');
  late final Index idxFlatHistoryTimestamp = Index('idx_flat_history_timestamp',
      'CREATE INDEX idx_flat_history_timestamp ON flat_history (timestamp)');
  late final Index idxTutorialProgressCategory = Index(
      'idx_tutorial_progress_category',
      'CREATE INDEX idx_tutorial_progress_category ON tutorial_progress (category)');
  late final Index idxPolarHistoryProfile = Index('idx_polar_history_profile',
      'CREATE INDEX idx_polar_history_profile ON polar_alignment_history (equipment_profile_id)');
  late final Index idxPolarHistoryStarted = Index('idx_polar_history_started',
      'CREATE INDEX idx_polar_history_started ON polar_alignment_history (started_at)');
  late final Index idxPolarHistoryCompleted = Index(
      'idx_polar_history_completed',
      'CREATE INDEX idx_polar_history_completed ON polar_alignment_history (completed_at)');
  late final ImagesDao imagesDao = ImagesDao(this as NightshadeDatabase);
  late final EquipmentProfilesDao equipmentProfilesDao =
      EquipmentProfilesDao(this as NightshadeDatabase);
  late final SessionsDao sessionsDao = SessionsDao(this as NightshadeDatabase);
  late final SequencesDao sequencesDao =
      SequencesDao(this as NightshadeDatabase);
  late final SequenceCheckpointsDao sequenceCheckpointsDao =
      SequenceCheckpointsDao(this as NightshadeDatabase);
  late final TargetsDao targetsDao = TargetsDao(this as NightshadeDatabase);
  late final SettingsDao settingsDao = SettingsDao(this as NightshadeDatabase);
  late final WeatherSettingsDao weatherSettingsDao =
      WeatherSettingsDao(this as NightshadeDatabase);
  late final FlatHistoryDao flatHistoryDao =
      FlatHistoryDao(this as NightshadeDatabase);
  late final TutorialProgressDao tutorialProgressDao =
      TutorialProgressDao(this as NightshadeDatabase);
  late final PolarAlignmentHistoryDao polarAlignmentHistoryDao =
      PolarAlignmentHistoryDao(this as NightshadeDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        equipmentProfiles,
        targets,
        sequences,
        imagingSessions,
        sequenceNodes,
        sequenceCheckpoints,
        capturedImages,
        imageMetadata,
        appSettings,
        weatherSettings,
        flatHistory,
        tutorialProgress,
        polarAlignmentHistory,
        idxProfilesName,
        idxProfilesActive,
        idxSessionsTarget,
        idxSessionsProfile,
        idxSessionsStart,
        idxSessionsStatus,
        idxTargetsName,
        idxTargetsCatalog,
        idxTargetsPriority,
        idxTargetsFavorite,
        idxTargetsObjectType,
        idxSequencesName,
        idxSequencesTemplate,
        idxSequencesUpdated,
        idxNodesSequence,
        idxNodesParent,
        idxNodesTarget,
        idxNodesType,
        idxNodesNodeId,
        idxCheckpointsCheckpointedAt,
        idxImagesSession,
        idxImagesTarget,
        idxImagesFrameType,
        idxImagesCapturedAt,
        idxImagesFilter,
        idxImagesAccepted,
        idxImagesSessionFrame,
        idxMetadataImage,
        idxMetadataKey,
        idxFlatHistoryProfile,
        idxFlatHistoryFilter,
        idxFlatHistoryTimestamp,
        idxTutorialProgressCategory,
        idxPolarHistoryProfile,
        idxPolarHistoryStarted,
        idxPolarHistoryCompleted
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('sequences',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('sequence_nodes', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('targets',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('sequence_nodes', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('sequences',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('sequence_checkpoints', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('imaging_sessions',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('captured_images', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('targets',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('captured_images', kind: UpdateKind.update),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('captured_images',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('image_metadata', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$EquipmentProfilesTableCreateCompanionBuilder
    = EquipmentProfilesCompanion Function({
  Value<int> id,
  required String name,
  Value<String?> description,
  Value<String?> cameraId,
  Value<String?> mountId,
  Value<String?> focuserId,
  Value<String?> filterWheelId,
  Value<String?> guiderId,
  Value<String?> rotatorId,
  Value<String?> domeId,
  Value<String?> weatherId,
  Value<String?> coverCalibratorId,
  Value<double> focalLength,
  Value<double> aperture,
  Value<double?> focalRatio,
  Value<int?> defaultGain,
  Value<int?> defaultOffset,
  Value<int> defaultBinX,
  Value<int> defaultBinY,
  Value<double?> defaultCoolingTemp,
  Value<String?> filterNames,
  Value<String?> filterFocusOffsets,
  Value<String?> meridianFlipOverrides,
  Value<String?> cameraName,
  Value<String?> mountName,
  Value<String?> focuserName,
  Value<String?> filterWheelName,
  Value<String?> guiderName,
  Value<String?> rotatorName,
  Value<String?> telescopeName,
  Value<double?> telescopeFocalLength,
  Value<double?> telescopeAperture,
  Value<String?> profileIcon,
  Value<int?> profileColor,
  Value<int> sortOrder,
  Value<bool> isDefault,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> isActive,
});
typedef $$EquipmentProfilesTableUpdateCompanionBuilder
    = EquipmentProfilesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String?> description,
  Value<String?> cameraId,
  Value<String?> mountId,
  Value<String?> focuserId,
  Value<String?> filterWheelId,
  Value<String?> guiderId,
  Value<String?> rotatorId,
  Value<String?> domeId,
  Value<String?> weatherId,
  Value<String?> coverCalibratorId,
  Value<double> focalLength,
  Value<double> aperture,
  Value<double?> focalRatio,
  Value<int?> defaultGain,
  Value<int?> defaultOffset,
  Value<int> defaultBinX,
  Value<int> defaultBinY,
  Value<double?> defaultCoolingTemp,
  Value<String?> filterNames,
  Value<String?> filterFocusOffsets,
  Value<String?> meridianFlipOverrides,
  Value<String?> cameraName,
  Value<String?> mountName,
  Value<String?> focuserName,
  Value<String?> filterWheelName,
  Value<String?> guiderName,
  Value<String?> rotatorName,
  Value<String?> telescopeName,
  Value<double?> telescopeFocalLength,
  Value<double?> telescopeAperture,
  Value<String?> profileIcon,
  Value<int?> profileColor,
  Value<int> sortOrder,
  Value<bool> isDefault,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> isActive,
});

final class $$EquipmentProfilesTableReferences extends BaseReferences<
    _$NightshadeDatabase, $EquipmentProfilesTable, EquipmentProfile> {
  $$EquipmentProfilesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ImagingSessionsTable, List<ImagingSession>>
      _imagingSessionsRefsTable(_$NightshadeDatabase db) =>
          MultiTypedResultKey.fromTable(db.imagingSessions,
              aliasName: $_aliasNameGenerator(
                  db.equipmentProfiles.id, db.imagingSessions.profileId));

  $$ImagingSessionsTableProcessedTableManager get imagingSessionsRefs {
    final manager =
        $$ImagingSessionsTableTableManager($_db, $_db.imagingSessions)
            .filter((f) => f.profileId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_imagingSessionsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$EquipmentProfilesTableFilterComposer
    extends Composer<_$NightshadeDatabase, $EquipmentProfilesTable> {
  $$EquipmentProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cameraId => $composableBuilder(
      column: $table.cameraId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mountId => $composableBuilder(
      column: $table.mountId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get focuserId => $composableBuilder(
      column: $table.focuserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filterWheelId => $composableBuilder(
      column: $table.filterWheelId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get guiderId => $composableBuilder(
      column: $table.guiderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rotatorId => $composableBuilder(
      column: $table.rotatorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get domeId => $composableBuilder(
      column: $table.domeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get weatherId => $composableBuilder(
      column: $table.weatherId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get coverCalibratorId => $composableBuilder(
      column: $table.coverCalibratorId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get focalLength => $composableBuilder(
      column: $table.focalLength, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get aperture => $composableBuilder(
      column: $table.aperture, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get focalRatio => $composableBuilder(
      column: $table.focalRatio, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get defaultGain => $composableBuilder(
      column: $table.defaultGain, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get defaultOffset => $composableBuilder(
      column: $table.defaultOffset, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get defaultBinX => $composableBuilder(
      column: $table.defaultBinX, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get defaultBinY => $composableBuilder(
      column: $table.defaultBinY, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get defaultCoolingTemp => $composableBuilder(
      column: $table.defaultCoolingTemp,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filterNames => $composableBuilder(
      column: $table.filterNames, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filterFocusOffsets => $composableBuilder(
      column: $table.filterFocusOffsets,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get meridianFlipOverrides => $composableBuilder(
      column: $table.meridianFlipOverrides,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cameraName => $composableBuilder(
      column: $table.cameraName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mountName => $composableBuilder(
      column: $table.mountName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get focuserName => $composableBuilder(
      column: $table.focuserName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filterWheelName => $composableBuilder(
      column: $table.filterWheelName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get guiderName => $composableBuilder(
      column: $table.guiderName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rotatorName => $composableBuilder(
      column: $table.rotatorName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get telescopeName => $composableBuilder(
      column: $table.telescopeName, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get telescopeFocalLength => $composableBuilder(
      column: $table.telescopeFocalLength,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get telescopeAperture => $composableBuilder(
      column: $table.telescopeAperture,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get profileIcon => $composableBuilder(
      column: $table.profileIcon, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get profileColor => $composableBuilder(
      column: $table.profileColor, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDefault => $composableBuilder(
      column: $table.isDefault, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  Expression<bool> imagingSessionsRefs(
      Expression<bool> Function($$ImagingSessionsTableFilterComposer f) f) {
    final $$ImagingSessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableFilterComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$EquipmentProfilesTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $EquipmentProfilesTable> {
  $$EquipmentProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cameraId => $composableBuilder(
      column: $table.cameraId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mountId => $composableBuilder(
      column: $table.mountId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get focuserId => $composableBuilder(
      column: $table.focuserId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filterWheelId => $composableBuilder(
      column: $table.filterWheelId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get guiderId => $composableBuilder(
      column: $table.guiderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rotatorId => $composableBuilder(
      column: $table.rotatorId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get domeId => $composableBuilder(
      column: $table.domeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get weatherId => $composableBuilder(
      column: $table.weatherId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get coverCalibratorId => $composableBuilder(
      column: $table.coverCalibratorId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get focalLength => $composableBuilder(
      column: $table.focalLength, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get aperture => $composableBuilder(
      column: $table.aperture, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get focalRatio => $composableBuilder(
      column: $table.focalRatio, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get defaultGain => $composableBuilder(
      column: $table.defaultGain, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get defaultOffset => $composableBuilder(
      column: $table.defaultOffset,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get defaultBinX => $composableBuilder(
      column: $table.defaultBinX, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get defaultBinY => $composableBuilder(
      column: $table.defaultBinY, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get defaultCoolingTemp => $composableBuilder(
      column: $table.defaultCoolingTemp,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filterNames => $composableBuilder(
      column: $table.filterNames, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filterFocusOffsets => $composableBuilder(
      column: $table.filterFocusOffsets,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get meridianFlipOverrides => $composableBuilder(
      column: $table.meridianFlipOverrides,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cameraName => $composableBuilder(
      column: $table.cameraName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mountName => $composableBuilder(
      column: $table.mountName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get focuserName => $composableBuilder(
      column: $table.focuserName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filterWheelName => $composableBuilder(
      column: $table.filterWheelName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get guiderName => $composableBuilder(
      column: $table.guiderName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rotatorName => $composableBuilder(
      column: $table.rotatorName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get telescopeName => $composableBuilder(
      column: $table.telescopeName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get telescopeFocalLength => $composableBuilder(
      column: $table.telescopeFocalLength,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get telescopeAperture => $composableBuilder(
      column: $table.telescopeAperture,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get profileIcon => $composableBuilder(
      column: $table.profileIcon, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get profileColor => $composableBuilder(
      column: $table.profileColor,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortOrder => $composableBuilder(
      column: $table.sortOrder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDefault => $composableBuilder(
      column: $table.isDefault, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));
}

class $$EquipmentProfilesTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $EquipmentProfilesTable> {
  $$EquipmentProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get cameraId =>
      $composableBuilder(column: $table.cameraId, builder: (column) => column);

  GeneratedColumn<String> get mountId =>
      $composableBuilder(column: $table.mountId, builder: (column) => column);

  GeneratedColumn<String> get focuserId =>
      $composableBuilder(column: $table.focuserId, builder: (column) => column);

  GeneratedColumn<String> get filterWheelId => $composableBuilder(
      column: $table.filterWheelId, builder: (column) => column);

  GeneratedColumn<String> get guiderId =>
      $composableBuilder(column: $table.guiderId, builder: (column) => column);

  GeneratedColumn<String> get rotatorId =>
      $composableBuilder(column: $table.rotatorId, builder: (column) => column);

  GeneratedColumn<String> get domeId =>
      $composableBuilder(column: $table.domeId, builder: (column) => column);

  GeneratedColumn<String> get weatherId =>
      $composableBuilder(column: $table.weatherId, builder: (column) => column);

  GeneratedColumn<String> get coverCalibratorId => $composableBuilder(
      column: $table.coverCalibratorId, builder: (column) => column);

  GeneratedColumn<double> get focalLength => $composableBuilder(
      column: $table.focalLength, builder: (column) => column);

  GeneratedColumn<double> get aperture =>
      $composableBuilder(column: $table.aperture, builder: (column) => column);

  GeneratedColumn<double> get focalRatio => $composableBuilder(
      column: $table.focalRatio, builder: (column) => column);

  GeneratedColumn<int> get defaultGain => $composableBuilder(
      column: $table.defaultGain, builder: (column) => column);

  GeneratedColumn<int> get defaultOffset => $composableBuilder(
      column: $table.defaultOffset, builder: (column) => column);

  GeneratedColumn<int> get defaultBinX => $composableBuilder(
      column: $table.defaultBinX, builder: (column) => column);

  GeneratedColumn<int> get defaultBinY => $composableBuilder(
      column: $table.defaultBinY, builder: (column) => column);

  GeneratedColumn<double> get defaultCoolingTemp => $composableBuilder(
      column: $table.defaultCoolingTemp, builder: (column) => column);

  GeneratedColumn<String> get filterNames => $composableBuilder(
      column: $table.filterNames, builder: (column) => column);

  GeneratedColumn<String> get filterFocusOffsets => $composableBuilder(
      column: $table.filterFocusOffsets, builder: (column) => column);

  GeneratedColumn<String> get meridianFlipOverrides => $composableBuilder(
      column: $table.meridianFlipOverrides, builder: (column) => column);

  GeneratedColumn<String> get cameraName => $composableBuilder(
      column: $table.cameraName, builder: (column) => column);

  GeneratedColumn<String> get mountName =>
      $composableBuilder(column: $table.mountName, builder: (column) => column);

  GeneratedColumn<String> get focuserName => $composableBuilder(
      column: $table.focuserName, builder: (column) => column);

  GeneratedColumn<String> get filterWheelName => $composableBuilder(
      column: $table.filterWheelName, builder: (column) => column);

  GeneratedColumn<String> get guiderName => $composableBuilder(
      column: $table.guiderName, builder: (column) => column);

  GeneratedColumn<String> get rotatorName => $composableBuilder(
      column: $table.rotatorName, builder: (column) => column);

  GeneratedColumn<String> get telescopeName => $composableBuilder(
      column: $table.telescopeName, builder: (column) => column);

  GeneratedColumn<double> get telescopeFocalLength => $composableBuilder(
      column: $table.telescopeFocalLength, builder: (column) => column);

  GeneratedColumn<double> get telescopeAperture => $composableBuilder(
      column: $table.telescopeAperture, builder: (column) => column);

  GeneratedColumn<String> get profileIcon => $composableBuilder(
      column: $table.profileIcon, builder: (column) => column);

  GeneratedColumn<int> get profileColor => $composableBuilder(
      column: $table.profileColor, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  Expression<T> imagingSessionsRefs<T extends Object>(
      Expression<T> Function($$ImagingSessionsTableAnnotationComposer a) f) {
    final $$ImagingSessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.profileId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$EquipmentProfilesTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $EquipmentProfilesTable,
    EquipmentProfile,
    $$EquipmentProfilesTableFilterComposer,
    $$EquipmentProfilesTableOrderingComposer,
    $$EquipmentProfilesTableAnnotationComposer,
    $$EquipmentProfilesTableCreateCompanionBuilder,
    $$EquipmentProfilesTableUpdateCompanionBuilder,
    (EquipmentProfile, $$EquipmentProfilesTableReferences),
    EquipmentProfile,
    PrefetchHooks Function({bool imagingSessionsRefs})> {
  $$EquipmentProfilesTableTableManager(
      _$NightshadeDatabase db, $EquipmentProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EquipmentProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EquipmentProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EquipmentProfilesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> cameraId = const Value.absent(),
            Value<String?> mountId = const Value.absent(),
            Value<String?> focuserId = const Value.absent(),
            Value<String?> filterWheelId = const Value.absent(),
            Value<String?> guiderId = const Value.absent(),
            Value<String?> rotatorId = const Value.absent(),
            Value<String?> domeId = const Value.absent(),
            Value<String?> weatherId = const Value.absent(),
            Value<String?> coverCalibratorId = const Value.absent(),
            Value<double> focalLength = const Value.absent(),
            Value<double> aperture = const Value.absent(),
            Value<double?> focalRatio = const Value.absent(),
            Value<int?> defaultGain = const Value.absent(),
            Value<int?> defaultOffset = const Value.absent(),
            Value<int> defaultBinX = const Value.absent(),
            Value<int> defaultBinY = const Value.absent(),
            Value<double?> defaultCoolingTemp = const Value.absent(),
            Value<String?> filterNames = const Value.absent(),
            Value<String?> filterFocusOffsets = const Value.absent(),
            Value<String?> meridianFlipOverrides = const Value.absent(),
            Value<String?> cameraName = const Value.absent(),
            Value<String?> mountName = const Value.absent(),
            Value<String?> focuserName = const Value.absent(),
            Value<String?> filterWheelName = const Value.absent(),
            Value<String?> guiderName = const Value.absent(),
            Value<String?> rotatorName = const Value.absent(),
            Value<String?> telescopeName = const Value.absent(),
            Value<double?> telescopeFocalLength = const Value.absent(),
            Value<double?> telescopeAperture = const Value.absent(),
            Value<String?> profileIcon = const Value.absent(),
            Value<int?> profileColor = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<bool> isDefault = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
          }) =>
              EquipmentProfilesCompanion(
            id: id,
            name: name,
            description: description,
            cameraId: cameraId,
            mountId: mountId,
            focuserId: focuserId,
            filterWheelId: filterWheelId,
            guiderId: guiderId,
            rotatorId: rotatorId,
            domeId: domeId,
            weatherId: weatherId,
            coverCalibratorId: coverCalibratorId,
            focalLength: focalLength,
            aperture: aperture,
            focalRatio: focalRatio,
            defaultGain: defaultGain,
            defaultOffset: defaultOffset,
            defaultBinX: defaultBinX,
            defaultBinY: defaultBinY,
            defaultCoolingTemp: defaultCoolingTemp,
            filterNames: filterNames,
            filterFocusOffsets: filterFocusOffsets,
            meridianFlipOverrides: meridianFlipOverrides,
            cameraName: cameraName,
            mountName: mountName,
            focuserName: focuserName,
            filterWheelName: filterWheelName,
            guiderName: guiderName,
            rotatorName: rotatorName,
            telescopeName: telescopeName,
            telescopeFocalLength: telescopeFocalLength,
            telescopeAperture: telescopeAperture,
            profileIcon: profileIcon,
            profileColor: profileColor,
            sortOrder: sortOrder,
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isActive: isActive,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String?> description = const Value.absent(),
            Value<String?> cameraId = const Value.absent(),
            Value<String?> mountId = const Value.absent(),
            Value<String?> focuserId = const Value.absent(),
            Value<String?> filterWheelId = const Value.absent(),
            Value<String?> guiderId = const Value.absent(),
            Value<String?> rotatorId = const Value.absent(),
            Value<String?> domeId = const Value.absent(),
            Value<String?> weatherId = const Value.absent(),
            Value<String?> coverCalibratorId = const Value.absent(),
            Value<double> focalLength = const Value.absent(),
            Value<double> aperture = const Value.absent(),
            Value<double?> focalRatio = const Value.absent(),
            Value<int?> defaultGain = const Value.absent(),
            Value<int?> defaultOffset = const Value.absent(),
            Value<int> defaultBinX = const Value.absent(),
            Value<int> defaultBinY = const Value.absent(),
            Value<double?> defaultCoolingTemp = const Value.absent(),
            Value<String?> filterNames = const Value.absent(),
            Value<String?> filterFocusOffsets = const Value.absent(),
            Value<String?> meridianFlipOverrides = const Value.absent(),
            Value<String?> cameraName = const Value.absent(),
            Value<String?> mountName = const Value.absent(),
            Value<String?> focuserName = const Value.absent(),
            Value<String?> filterWheelName = const Value.absent(),
            Value<String?> guiderName = const Value.absent(),
            Value<String?> rotatorName = const Value.absent(),
            Value<String?> telescopeName = const Value.absent(),
            Value<double?> telescopeFocalLength = const Value.absent(),
            Value<double?> telescopeAperture = const Value.absent(),
            Value<String?> profileIcon = const Value.absent(),
            Value<int?> profileColor = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
            Value<bool> isDefault = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
          }) =>
              EquipmentProfilesCompanion.insert(
            id: id,
            name: name,
            description: description,
            cameraId: cameraId,
            mountId: mountId,
            focuserId: focuserId,
            filterWheelId: filterWheelId,
            guiderId: guiderId,
            rotatorId: rotatorId,
            domeId: domeId,
            weatherId: weatherId,
            coverCalibratorId: coverCalibratorId,
            focalLength: focalLength,
            aperture: aperture,
            focalRatio: focalRatio,
            defaultGain: defaultGain,
            defaultOffset: defaultOffset,
            defaultBinX: defaultBinX,
            defaultBinY: defaultBinY,
            defaultCoolingTemp: defaultCoolingTemp,
            filterNames: filterNames,
            filterFocusOffsets: filterFocusOffsets,
            meridianFlipOverrides: meridianFlipOverrides,
            cameraName: cameraName,
            mountName: mountName,
            focuserName: focuserName,
            filterWheelName: filterWheelName,
            guiderName: guiderName,
            rotatorName: rotatorName,
            telescopeName: telescopeName,
            telescopeFocalLength: telescopeFocalLength,
            telescopeAperture: telescopeAperture,
            profileIcon: profileIcon,
            profileColor: profileColor,
            sortOrder: sortOrder,
            isDefault: isDefault,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isActive: isActive,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$EquipmentProfilesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({imagingSessionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (imagingSessionsRefs) db.imagingSessions
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (imagingSessionsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$EquipmentProfilesTableReferences
                            ._imagingSessionsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$EquipmentProfilesTableReferences(db, table, p0)
                                .imagingSessionsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.profileId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$EquipmentProfilesTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $EquipmentProfilesTable,
    EquipmentProfile,
    $$EquipmentProfilesTableFilterComposer,
    $$EquipmentProfilesTableOrderingComposer,
    $$EquipmentProfilesTableAnnotationComposer,
    $$EquipmentProfilesTableCreateCompanionBuilder,
    $$EquipmentProfilesTableUpdateCompanionBuilder,
    (EquipmentProfile, $$EquipmentProfilesTableReferences),
    EquipmentProfile,
    PrefetchHooks Function({bool imagingSessionsRefs})>;
typedef $$TargetsTableCreateCompanionBuilder = TargetsCompanion Function({
  Value<int> id,
  required String name,
  Value<String?> catalogId,
  Value<String?> objectType,
  required double ra,
  required double dec,
  Value<double?> positionAngle,
  Value<double?> magnitude,
  Value<String?> constellation,
  Value<double?> sizeArcmin,
  Value<double> minAltitude,
  Value<int> priority,
  Value<int> totalPlannedSubs,
  Value<int> capturedSubs,
  Value<double> totalIntegrationSecs,
  Value<String?> filterProgress,
  Value<String?> notes,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> isFavorite,
});
typedef $$TargetsTableUpdateCompanionBuilder = TargetsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String?> catalogId,
  Value<String?> objectType,
  Value<double> ra,
  Value<double> dec,
  Value<double?> positionAngle,
  Value<double?> magnitude,
  Value<String?> constellation,
  Value<double?> sizeArcmin,
  Value<double> minAltitude,
  Value<int> priority,
  Value<int> totalPlannedSubs,
  Value<int> capturedSubs,
  Value<double> totalIntegrationSecs,
  Value<String?> filterProgress,
  Value<String?> notes,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> isFavorite,
});

final class $$TargetsTableReferences
    extends BaseReferences<_$NightshadeDatabase, $TargetsTable, Target> {
  $$TargetsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ImagingSessionsTable, List<ImagingSession>>
      _imagingSessionsRefsTable(_$NightshadeDatabase db) =>
          MultiTypedResultKey.fromTable(db.imagingSessions,
              aliasName: $_aliasNameGenerator(
                  db.targets.id, db.imagingSessions.targetId));

  $$ImagingSessionsTableProcessedTableManager get imagingSessionsRefs {
    final manager =
        $$ImagingSessionsTableTableManager($_db, $_db.imagingSessions)
            .filter((f) => f.targetId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_imagingSessionsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$SequenceNodesTable, List<SequenceNode>>
      _sequenceNodesRefsTable(_$NightshadeDatabase db) =>
          MultiTypedResultKey.fromTable(db.sequenceNodes,
              aliasName: $_aliasNameGenerator(
                  db.targets.id, db.sequenceNodes.targetId));

  $$SequenceNodesTableProcessedTableManager get sequenceNodesRefs {
    final manager = $$SequenceNodesTableTableManager($_db, $_db.sequenceNodes)
        .filter((f) => f.targetId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_sequenceNodesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$CapturedImagesTable, List<CapturedImage>>
      _capturedImagesRefsTable(_$NightshadeDatabase db) =>
          MultiTypedResultKey.fromTable(db.capturedImages,
              aliasName: $_aliasNameGenerator(
                  db.targets.id, db.capturedImages.targetId));

  $$CapturedImagesTableProcessedTableManager get capturedImagesRefs {
    final manager = $$CapturedImagesTableTableManager($_db, $_db.capturedImages)
        .filter((f) => f.targetId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_capturedImagesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$TargetsTableFilterComposer
    extends Composer<_$NightshadeDatabase, $TargetsTable> {
  $$TargetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get catalogId => $composableBuilder(
      column: $table.catalogId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get ra => $composableBuilder(
      column: $table.ra, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get dec => $composableBuilder(
      column: $table.dec, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get positionAngle => $composableBuilder(
      column: $table.positionAngle, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get magnitude => $composableBuilder(
      column: $table.magnitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get constellation => $composableBuilder(
      column: $table.constellation, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get sizeArcmin => $composableBuilder(
      column: $table.sizeArcmin, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get minAltitude => $composableBuilder(
      column: $table.minAltitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalPlannedSubs => $composableBuilder(
      column: $table.totalPlannedSubs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get capturedSubs => $composableBuilder(
      column: $table.capturedSubs, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get totalIntegrationSecs => $composableBuilder(
      column: $table.totalIntegrationSecs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filterProgress => $composableBuilder(
      column: $table.filterProgress,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnFilters(column));

  Expression<bool> imagingSessionsRefs(
      Expression<bool> Function($$ImagingSessionsTableFilterComposer f) f) {
    final $$ImagingSessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.targetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableFilterComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> sequenceNodesRefs(
      Expression<bool> Function($$SequenceNodesTableFilterComposer f) f) {
    final $$SequenceNodesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sequenceNodes,
        getReferencedColumn: (t) => t.targetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequenceNodesTableFilterComposer(
              $db: $db,
              $table: $db.sequenceNodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> capturedImagesRefs(
      Expression<bool> Function($$CapturedImagesTableFilterComposer f) f) {
    final $$CapturedImagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.capturedImages,
        getReferencedColumn: (t) => t.targetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CapturedImagesTableFilterComposer(
              $db: $db,
              $table: $db.capturedImages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TargetsTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $TargetsTable> {
  $$TargetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get catalogId => $composableBuilder(
      column: $table.catalogId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get ra => $composableBuilder(
      column: $table.ra, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get dec => $composableBuilder(
      column: $table.dec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get positionAngle => $composableBuilder(
      column: $table.positionAngle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get magnitude => $composableBuilder(
      column: $table.magnitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get constellation => $composableBuilder(
      column: $table.constellation,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get sizeArcmin => $composableBuilder(
      column: $table.sizeArcmin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get minAltitude => $composableBuilder(
      column: $table.minAltitude, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalPlannedSubs => $composableBuilder(
      column: $table.totalPlannedSubs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get capturedSubs => $composableBuilder(
      column: $table.capturedSubs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get totalIntegrationSecs => $composableBuilder(
      column: $table.totalIntegrationSecs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filterProgress => $composableBuilder(
      column: $table.filterProgress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => ColumnOrderings(column));
}

class $$TargetsTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $TargetsTable> {
  $$TargetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get catalogId =>
      $composableBuilder(column: $table.catalogId, builder: (column) => column);

  GeneratedColumn<String> get objectType => $composableBuilder(
      column: $table.objectType, builder: (column) => column);

  GeneratedColumn<double> get ra =>
      $composableBuilder(column: $table.ra, builder: (column) => column);

  GeneratedColumn<double> get dec =>
      $composableBuilder(column: $table.dec, builder: (column) => column);

  GeneratedColumn<double> get positionAngle => $composableBuilder(
      column: $table.positionAngle, builder: (column) => column);

  GeneratedColumn<double> get magnitude =>
      $composableBuilder(column: $table.magnitude, builder: (column) => column);

  GeneratedColumn<String> get constellation => $composableBuilder(
      column: $table.constellation, builder: (column) => column);

  GeneratedColumn<double> get sizeArcmin => $composableBuilder(
      column: $table.sizeArcmin, builder: (column) => column);

  GeneratedColumn<double> get minAltitude => $composableBuilder(
      column: $table.minAltitude, builder: (column) => column);

  GeneratedColumn<int> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<int> get totalPlannedSubs => $composableBuilder(
      column: $table.totalPlannedSubs, builder: (column) => column);

  GeneratedColumn<int> get capturedSubs => $composableBuilder(
      column: $table.capturedSubs, builder: (column) => column);

  GeneratedColumn<double> get totalIntegrationSecs => $composableBuilder(
      column: $table.totalIntegrationSecs, builder: (column) => column);

  GeneratedColumn<String> get filterProgress => $composableBuilder(
      column: $table.filterProgress, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
      column: $table.isFavorite, builder: (column) => column);

  Expression<T> imagingSessionsRefs<T extends Object>(
      Expression<T> Function($$ImagingSessionsTableAnnotationComposer a) f) {
    final $$ImagingSessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.targetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> sequenceNodesRefs<T extends Object>(
      Expression<T> Function($$SequenceNodesTableAnnotationComposer a) f) {
    final $$SequenceNodesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sequenceNodes,
        getReferencedColumn: (t) => t.targetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequenceNodesTableAnnotationComposer(
              $db: $db,
              $table: $db.sequenceNodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> capturedImagesRefs<T extends Object>(
      Expression<T> Function($$CapturedImagesTableAnnotationComposer a) f) {
    final $$CapturedImagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.capturedImages,
        getReferencedColumn: (t) => t.targetId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CapturedImagesTableAnnotationComposer(
              $db: $db,
              $table: $db.capturedImages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$TargetsTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $TargetsTable,
    Target,
    $$TargetsTableFilterComposer,
    $$TargetsTableOrderingComposer,
    $$TargetsTableAnnotationComposer,
    $$TargetsTableCreateCompanionBuilder,
    $$TargetsTableUpdateCompanionBuilder,
    (Target, $$TargetsTableReferences),
    Target,
    PrefetchHooks Function(
        {bool imagingSessionsRefs,
        bool sequenceNodesRefs,
        bool capturedImagesRefs})> {
  $$TargetsTableTableManager(_$NightshadeDatabase db, $TargetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TargetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TargetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TargetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> catalogId = const Value.absent(),
            Value<String?> objectType = const Value.absent(),
            Value<double> ra = const Value.absent(),
            Value<double> dec = const Value.absent(),
            Value<double?> positionAngle = const Value.absent(),
            Value<double?> magnitude = const Value.absent(),
            Value<String?> constellation = const Value.absent(),
            Value<double?> sizeArcmin = const Value.absent(),
            Value<double> minAltitude = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int> totalPlannedSubs = const Value.absent(),
            Value<int> capturedSubs = const Value.absent(),
            Value<double> totalIntegrationSecs = const Value.absent(),
            Value<String?> filterProgress = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
          }) =>
              TargetsCompanion(
            id: id,
            name: name,
            catalogId: catalogId,
            objectType: objectType,
            ra: ra,
            dec: dec,
            positionAngle: positionAngle,
            magnitude: magnitude,
            constellation: constellation,
            sizeArcmin: sizeArcmin,
            minAltitude: minAltitude,
            priority: priority,
            totalPlannedSubs: totalPlannedSubs,
            capturedSubs: capturedSubs,
            totalIntegrationSecs: totalIntegrationSecs,
            filterProgress: filterProgress,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isFavorite: isFavorite,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String?> catalogId = const Value.absent(),
            Value<String?> objectType = const Value.absent(),
            required double ra,
            required double dec,
            Value<double?> positionAngle = const Value.absent(),
            Value<double?> magnitude = const Value.absent(),
            Value<String?> constellation = const Value.absent(),
            Value<double?> sizeArcmin = const Value.absent(),
            Value<double> minAltitude = const Value.absent(),
            Value<int> priority = const Value.absent(),
            Value<int> totalPlannedSubs = const Value.absent(),
            Value<int> capturedSubs = const Value.absent(),
            Value<double> totalIntegrationSecs = const Value.absent(),
            Value<String?> filterProgress = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> isFavorite = const Value.absent(),
          }) =>
              TargetsCompanion.insert(
            id: id,
            name: name,
            catalogId: catalogId,
            objectType: objectType,
            ra: ra,
            dec: dec,
            positionAngle: positionAngle,
            magnitude: magnitude,
            constellation: constellation,
            sizeArcmin: sizeArcmin,
            minAltitude: minAltitude,
            priority: priority,
            totalPlannedSubs: totalPlannedSubs,
            capturedSubs: capturedSubs,
            totalIntegrationSecs: totalIntegrationSecs,
            filterProgress: filterProgress,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isFavorite: isFavorite,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$TargetsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {imagingSessionsRefs = false,
              sequenceNodesRefs = false,
              capturedImagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (imagingSessionsRefs) db.imagingSessions,
                if (sequenceNodesRefs) db.sequenceNodes,
                if (capturedImagesRefs) db.capturedImages
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (imagingSessionsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$TargetsTableReferences
                            ._imagingSessionsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TargetsTableReferences(db, table, p0)
                                .imagingSessionsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.targetId == item.id),
                        typedResults: items),
                  if (sequenceNodesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$TargetsTableReferences
                            ._sequenceNodesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TargetsTableReferences(db, table, p0)
                                .sequenceNodesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.targetId == item.id),
                        typedResults: items),
                  if (capturedImagesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$TargetsTableReferences
                            ._capturedImagesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$TargetsTableReferences(db, table, p0)
                                .capturedImagesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.targetId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$TargetsTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $TargetsTable,
    Target,
    $$TargetsTableFilterComposer,
    $$TargetsTableOrderingComposer,
    $$TargetsTableAnnotationComposer,
    $$TargetsTableCreateCompanionBuilder,
    $$TargetsTableUpdateCompanionBuilder,
    (Target, $$TargetsTableReferences),
    Target,
    PrefetchHooks Function(
        {bool imagingSessionsRefs,
        bool sequenceNodesRefs,
        bool capturedImagesRefs})>;
typedef $$SequencesTableCreateCompanionBuilder = SequencesCompanion Function({
  Value<int> id,
  required String name,
  Value<String?> description,
  Value<String?> rootNodeId,
  Value<int> estimatedDurationMins,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> isTemplate,
});
typedef $$SequencesTableUpdateCompanionBuilder = SequencesCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<String?> description,
  Value<String?> rootNodeId,
  Value<int> estimatedDurationMins,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<bool> isTemplate,
});

final class $$SequencesTableReferences
    extends BaseReferences<_$NightshadeDatabase, $SequencesTable, Sequence> {
  $$SequencesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ImagingSessionsTable, List<ImagingSession>>
      _imagingSessionsRefsTable(_$NightshadeDatabase db) =>
          MultiTypedResultKey.fromTable(db.imagingSessions,
              aliasName: $_aliasNameGenerator(
                  db.sequences.id, db.imagingSessions.sequenceId));

  $$ImagingSessionsTableProcessedTableManager get imagingSessionsRefs {
    final manager =
        $$ImagingSessionsTableTableManager($_db, $_db.imagingSessions)
            .filter((f) => f.sequenceId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_imagingSessionsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$SequenceNodesTable, List<SequenceNode>>
      _sequenceNodesRefsTable(_$NightshadeDatabase db) =>
          MultiTypedResultKey.fromTable(db.sequenceNodes,
              aliasName: $_aliasNameGenerator(
                  db.sequences.id, db.sequenceNodes.sequenceId));

  $$SequenceNodesTableProcessedTableManager get sequenceNodesRefs {
    final manager = $$SequenceNodesTableTableManager($_db, $_db.sequenceNodes)
        .filter((f) => f.sequenceId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_sequenceNodesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$SequenceCheckpointsTable,
      List<SequenceCheckpoint>> _sequenceCheckpointsRefsTable(
          _$NightshadeDatabase db) =>
      MultiTypedResultKey.fromTable(db.sequenceCheckpoints,
          aliasName: $_aliasNameGenerator(
              db.sequences.id, db.sequenceCheckpoints.sequenceId));

  $$SequenceCheckpointsTableProcessedTableManager get sequenceCheckpointsRefs {
    final manager =
        $$SequenceCheckpointsTableTableManager($_db, $_db.sequenceCheckpoints)
            .filter((f) => f.sequenceId.id($_item.id));

    final cache =
        $_typedResult.readTableOrNull(_sequenceCheckpointsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SequencesTableFilterComposer
    extends Composer<_$NightshadeDatabase, $SequencesTable> {
  $$SequencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rootNodeId => $composableBuilder(
      column: $table.rootNodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get estimatedDurationMins => $composableBuilder(
      column: $table.estimatedDurationMins,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isTemplate => $composableBuilder(
      column: $table.isTemplate, builder: (column) => ColumnFilters(column));

  Expression<bool> imagingSessionsRefs(
      Expression<bool> Function($$ImagingSessionsTableFilterComposer f) f) {
    final $$ImagingSessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.sequenceId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableFilterComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> sequenceNodesRefs(
      Expression<bool> Function($$SequenceNodesTableFilterComposer f) f) {
    final $$SequenceNodesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sequenceNodes,
        getReferencedColumn: (t) => t.sequenceId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequenceNodesTableFilterComposer(
              $db: $db,
              $table: $db.sequenceNodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> sequenceCheckpointsRefs(
      Expression<bool> Function($$SequenceCheckpointsTableFilterComposer f) f) {
    final $$SequenceCheckpointsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sequenceCheckpoints,
        getReferencedColumn: (t) => t.sequenceId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequenceCheckpointsTableFilterComposer(
              $db: $db,
              $table: $db.sequenceCheckpoints,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SequencesTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $SequencesTable> {
  $$SequencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rootNodeId => $composableBuilder(
      column: $table.rootNodeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get estimatedDurationMins => $composableBuilder(
      column: $table.estimatedDurationMins,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isTemplate => $composableBuilder(
      column: $table.isTemplate, builder: (column) => ColumnOrderings(column));
}

class $$SequencesTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $SequencesTable> {
  $$SequencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get rootNodeId => $composableBuilder(
      column: $table.rootNodeId, builder: (column) => column);

  GeneratedColumn<int> get estimatedDurationMins => $composableBuilder(
      column: $table.estimatedDurationMins, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isTemplate => $composableBuilder(
      column: $table.isTemplate, builder: (column) => column);

  Expression<T> imagingSessionsRefs<T extends Object>(
      Expression<T> Function($$ImagingSessionsTableAnnotationComposer a) f) {
    final $$ImagingSessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.sequenceId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> sequenceNodesRefs<T extends Object>(
      Expression<T> Function($$SequenceNodesTableAnnotationComposer a) f) {
    final $$SequenceNodesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.sequenceNodes,
        getReferencedColumn: (t) => t.sequenceId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequenceNodesTableAnnotationComposer(
              $db: $db,
              $table: $db.sequenceNodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> sequenceCheckpointsRefs<T extends Object>(
      Expression<T> Function($$SequenceCheckpointsTableAnnotationComposer a)
          f) {
    final $$SequenceCheckpointsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.sequenceCheckpoints,
            getReferencedColumn: (t) => t.sequenceId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$SequenceCheckpointsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.sequenceCheckpoints,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$SequencesTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $SequencesTable,
    Sequence,
    $$SequencesTableFilterComposer,
    $$SequencesTableOrderingComposer,
    $$SequencesTableAnnotationComposer,
    $$SequencesTableCreateCompanionBuilder,
    $$SequencesTableUpdateCompanionBuilder,
    (Sequence, $$SequencesTableReferences),
    Sequence,
    PrefetchHooks Function(
        {bool imagingSessionsRefs,
        bool sequenceNodesRefs,
        bool sequenceCheckpointsRefs})> {
  $$SequencesTableTableManager(_$NightshadeDatabase db, $SequencesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SequencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SequencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SequencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String?> rootNodeId = const Value.absent(),
            Value<int> estimatedDurationMins = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> isTemplate = const Value.absent(),
          }) =>
              SequencesCompanion(
            id: id,
            name: name,
            description: description,
            rootNodeId: rootNodeId,
            estimatedDurationMins: estimatedDurationMins,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isTemplate: isTemplate,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<String?> description = const Value.absent(),
            Value<String?> rootNodeId = const Value.absent(),
            Value<int> estimatedDurationMins = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<bool> isTemplate = const Value.absent(),
          }) =>
              SequencesCompanion.insert(
            id: id,
            name: name,
            description: description,
            rootNodeId: rootNodeId,
            estimatedDurationMins: estimatedDurationMins,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isTemplate: isTemplate,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SequencesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {imagingSessionsRefs = false,
              sequenceNodesRefs = false,
              sequenceCheckpointsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (imagingSessionsRefs) db.imagingSessions,
                if (sequenceNodesRefs) db.sequenceNodes,
                if (sequenceCheckpointsRefs) db.sequenceCheckpoints
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (imagingSessionsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$SequencesTableReferences
                            ._imagingSessionsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SequencesTableReferences(db, table, p0)
                                .imagingSessionsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sequenceId == item.id),
                        typedResults: items),
                  if (sequenceNodesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$SequencesTableReferences
                            ._sequenceNodesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SequencesTableReferences(db, table, p0)
                                .sequenceNodesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sequenceId == item.id),
                        typedResults: items),
                  if (sequenceCheckpointsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$SequencesTableReferences
                            ._sequenceCheckpointsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SequencesTableReferences(db, table, p0)
                                .sequenceCheckpointsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sequenceId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SequencesTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $SequencesTable,
    Sequence,
    $$SequencesTableFilterComposer,
    $$SequencesTableOrderingComposer,
    $$SequencesTableAnnotationComposer,
    $$SequencesTableCreateCompanionBuilder,
    $$SequencesTableUpdateCompanionBuilder,
    (Sequence, $$SequencesTableReferences),
    Sequence,
    PrefetchHooks Function(
        {bool imagingSessionsRefs,
        bool sequenceNodesRefs,
        bool sequenceCheckpointsRefs})>;
typedef $$ImagingSessionsTableCreateCompanionBuilder = ImagingSessionsCompanion
    Function({
  Value<int> id,
  Value<String?> name,
  Value<int?> profileId,
  Value<int?> targetId,
  required DateTime startTime,
  Value<DateTime?> endTime,
  Value<int> totalExposures,
  Value<int> successfulExposures,
  Value<int> failedExposures,
  Value<double> totalIntegrationSecs,
  Value<double?> avgTemperature,
  Value<double?> avgHumidity,
  Value<double?> avgSeeing,
  Value<double?> avgHfr,
  Value<double?> avgGuidingRms,
  Value<int> autofocusCount,
  Value<String?> notes,
  Value<String> status,
  Value<int?> sequenceId,
  Value<String?> equipmentSnapshot,
});
typedef $$ImagingSessionsTableUpdateCompanionBuilder = ImagingSessionsCompanion
    Function({
  Value<int> id,
  Value<String?> name,
  Value<int?> profileId,
  Value<int?> targetId,
  Value<DateTime> startTime,
  Value<DateTime?> endTime,
  Value<int> totalExposures,
  Value<int> successfulExposures,
  Value<int> failedExposures,
  Value<double> totalIntegrationSecs,
  Value<double?> avgTemperature,
  Value<double?> avgHumidity,
  Value<double?> avgSeeing,
  Value<double?> avgHfr,
  Value<double?> avgGuidingRms,
  Value<int> autofocusCount,
  Value<String?> notes,
  Value<String> status,
  Value<int?> sequenceId,
  Value<String?> equipmentSnapshot,
});

final class $$ImagingSessionsTableReferences extends BaseReferences<
    _$NightshadeDatabase, $ImagingSessionsTable, ImagingSession> {
  $$ImagingSessionsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $EquipmentProfilesTable _profileIdTable(_$NightshadeDatabase db) =>
      db.equipmentProfiles.createAlias($_aliasNameGenerator(
          db.imagingSessions.profileId, db.equipmentProfiles.id));

  $$EquipmentProfilesTableProcessedTableManager? get profileId {
    if ($_item.profileId == null) return null;
    final manager =
        $$EquipmentProfilesTableTableManager($_db, $_db.equipmentProfiles)
            .filter((f) => f.id($_item.profileId!));
    final item = $_typedResult.readTableOrNull(_profileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $TargetsTable _targetIdTable(_$NightshadeDatabase db) =>
      db.targets.createAlias(
          $_aliasNameGenerator(db.imagingSessions.targetId, db.targets.id));

  $$TargetsTableProcessedTableManager? get targetId {
    if ($_item.targetId == null) return null;
    final manager = $$TargetsTableTableManager($_db, $_db.targets)
        .filter((f) => f.id($_item.targetId!));
    final item = $_typedResult.readTableOrNull(_targetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $SequencesTable _sequenceIdTable(_$NightshadeDatabase db) =>
      db.sequences.createAlias(
          $_aliasNameGenerator(db.imagingSessions.sequenceId, db.sequences.id));

  $$SequencesTableProcessedTableManager? get sequenceId {
    if ($_item.sequenceId == null) return null;
    final manager = $$SequencesTableTableManager($_db, $_db.sequences)
        .filter((f) => f.id($_item.sequenceId!));
    final item = $_typedResult.readTableOrNull(_sequenceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$CapturedImagesTable, List<CapturedImage>>
      _capturedImagesRefsTable(_$NightshadeDatabase db) =>
          MultiTypedResultKey.fromTable(db.capturedImages,
              aliasName: $_aliasNameGenerator(
                  db.imagingSessions.id, db.capturedImages.sessionId));

  $$CapturedImagesTableProcessedTableManager get capturedImagesRefs {
    final manager = $$CapturedImagesTableTableManager($_db, $_db.capturedImages)
        .filter((f) => f.sessionId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_capturedImagesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ImagingSessionsTableFilterComposer
    extends Composer<_$NightshadeDatabase, $ImagingSessionsTable> {
  $$ImagingSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalExposures => $composableBuilder(
      column: $table.totalExposures,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get successfulExposures => $composableBuilder(
      column: $table.successfulExposures,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get failedExposures => $composableBuilder(
      column: $table.failedExposures,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get totalIntegrationSecs => $composableBuilder(
      column: $table.totalIntegrationSecs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get avgTemperature => $composableBuilder(
      column: $table.avgTemperature,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get avgHumidity => $composableBuilder(
      column: $table.avgHumidity, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get avgSeeing => $composableBuilder(
      column: $table.avgSeeing, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get avgHfr => $composableBuilder(
      column: $table.avgHfr, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get avgGuidingRms => $composableBuilder(
      column: $table.avgGuidingRms, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get autofocusCount => $composableBuilder(
      column: $table.autofocusCount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get equipmentSnapshot => $composableBuilder(
      column: $table.equipmentSnapshot,
      builder: (column) => ColumnFilters(column));

  $$EquipmentProfilesTableFilterComposer get profileId {
    final $$EquipmentProfilesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.equipmentProfiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$EquipmentProfilesTableFilterComposer(
              $db: $db,
              $table: $db.equipmentProfiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TargetsTableFilterComposer get targetId {
    final $$TargetsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableFilterComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SequencesTableFilterComposer get sequenceId {
    final $$SequencesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableFilterComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> capturedImagesRefs(
      Expression<bool> Function($$CapturedImagesTableFilterComposer f) f) {
    final $$CapturedImagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.capturedImages,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CapturedImagesTableFilterComposer(
              $db: $db,
              $table: $db.capturedImages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ImagingSessionsTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $ImagingSessionsTable> {
  $$ImagingSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startTime => $composableBuilder(
      column: $table.startTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
      column: $table.endTime, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalExposures => $composableBuilder(
      column: $table.totalExposures,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get successfulExposures => $composableBuilder(
      column: $table.successfulExposures,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get failedExposures => $composableBuilder(
      column: $table.failedExposures,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get totalIntegrationSecs => $composableBuilder(
      column: $table.totalIntegrationSecs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get avgTemperature => $composableBuilder(
      column: $table.avgTemperature,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get avgHumidity => $composableBuilder(
      column: $table.avgHumidity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get avgSeeing => $composableBuilder(
      column: $table.avgSeeing, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get avgHfr => $composableBuilder(
      column: $table.avgHfr, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get avgGuidingRms => $composableBuilder(
      column: $table.avgGuidingRms,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get autofocusCount => $composableBuilder(
      column: $table.autofocusCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get equipmentSnapshot => $composableBuilder(
      column: $table.equipmentSnapshot,
      builder: (column) => ColumnOrderings(column));

  $$EquipmentProfilesTableOrderingComposer get profileId {
    final $$EquipmentProfilesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.profileId,
        referencedTable: $db.equipmentProfiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$EquipmentProfilesTableOrderingComposer(
              $db: $db,
              $table: $db.equipmentProfiles,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TargetsTableOrderingComposer get targetId {
    final $$TargetsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableOrderingComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SequencesTableOrderingComposer get sequenceId {
    final $$SequencesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableOrderingComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ImagingSessionsTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $ImagingSessionsTable> {
  $$ImagingSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get startTime =>
      $composableBuilder(column: $table.startTime, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<int> get totalExposures => $composableBuilder(
      column: $table.totalExposures, builder: (column) => column);

  GeneratedColumn<int> get successfulExposures => $composableBuilder(
      column: $table.successfulExposures, builder: (column) => column);

  GeneratedColumn<int> get failedExposures => $composableBuilder(
      column: $table.failedExposures, builder: (column) => column);

  GeneratedColumn<double> get totalIntegrationSecs => $composableBuilder(
      column: $table.totalIntegrationSecs, builder: (column) => column);

  GeneratedColumn<double> get avgTemperature => $composableBuilder(
      column: $table.avgTemperature, builder: (column) => column);

  GeneratedColumn<double> get avgHumidity => $composableBuilder(
      column: $table.avgHumidity, builder: (column) => column);

  GeneratedColumn<double> get avgSeeing =>
      $composableBuilder(column: $table.avgSeeing, builder: (column) => column);

  GeneratedColumn<double> get avgHfr =>
      $composableBuilder(column: $table.avgHfr, builder: (column) => column);

  GeneratedColumn<double> get avgGuidingRms => $composableBuilder(
      column: $table.avgGuidingRms, builder: (column) => column);

  GeneratedColumn<int> get autofocusCount => $composableBuilder(
      column: $table.autofocusCount, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get equipmentSnapshot => $composableBuilder(
      column: $table.equipmentSnapshot, builder: (column) => column);

  $$EquipmentProfilesTableAnnotationComposer get profileId {
    final $$EquipmentProfilesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.profileId,
            referencedTable: $db.equipmentProfiles,
            getReferencedColumn: (t) => t.id,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$EquipmentProfilesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.equipmentProfiles,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return composer;
  }

  $$TargetsTableAnnotationComposer get targetId {
    final $$TargetsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableAnnotationComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$SequencesTableAnnotationComposer get sequenceId {
    final $$SequencesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableAnnotationComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> capturedImagesRefs<T extends Object>(
      Expression<T> Function($$CapturedImagesTableAnnotationComposer a) f) {
    final $$CapturedImagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.capturedImages,
        getReferencedColumn: (t) => t.sessionId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CapturedImagesTableAnnotationComposer(
              $db: $db,
              $table: $db.capturedImages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ImagingSessionsTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $ImagingSessionsTable,
    ImagingSession,
    $$ImagingSessionsTableFilterComposer,
    $$ImagingSessionsTableOrderingComposer,
    $$ImagingSessionsTableAnnotationComposer,
    $$ImagingSessionsTableCreateCompanionBuilder,
    $$ImagingSessionsTableUpdateCompanionBuilder,
    (ImagingSession, $$ImagingSessionsTableReferences),
    ImagingSession,
    PrefetchHooks Function(
        {bool profileId,
        bool targetId,
        bool sequenceId,
        bool capturedImagesRefs})> {
  $$ImagingSessionsTableTableManager(
      _$NightshadeDatabase db, $ImagingSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImagingSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImagingSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImagingSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> name = const Value.absent(),
            Value<int?> profileId = const Value.absent(),
            Value<int?> targetId = const Value.absent(),
            Value<DateTime> startTime = const Value.absent(),
            Value<DateTime?> endTime = const Value.absent(),
            Value<int> totalExposures = const Value.absent(),
            Value<int> successfulExposures = const Value.absent(),
            Value<int> failedExposures = const Value.absent(),
            Value<double> totalIntegrationSecs = const Value.absent(),
            Value<double?> avgTemperature = const Value.absent(),
            Value<double?> avgHumidity = const Value.absent(),
            Value<double?> avgSeeing = const Value.absent(),
            Value<double?> avgHfr = const Value.absent(),
            Value<double?> avgGuidingRms = const Value.absent(),
            Value<int> autofocusCount = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int?> sequenceId = const Value.absent(),
            Value<String?> equipmentSnapshot = const Value.absent(),
          }) =>
              ImagingSessionsCompanion(
            id: id,
            name: name,
            profileId: profileId,
            targetId: targetId,
            startTime: startTime,
            endTime: endTime,
            totalExposures: totalExposures,
            successfulExposures: successfulExposures,
            failedExposures: failedExposures,
            totalIntegrationSecs: totalIntegrationSecs,
            avgTemperature: avgTemperature,
            avgHumidity: avgHumidity,
            avgSeeing: avgSeeing,
            avgHfr: avgHfr,
            avgGuidingRms: avgGuidingRms,
            autofocusCount: autofocusCount,
            notes: notes,
            status: status,
            sequenceId: sequenceId,
            equipmentSnapshot: equipmentSnapshot,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> name = const Value.absent(),
            Value<int?> profileId = const Value.absent(),
            Value<int?> targetId = const Value.absent(),
            required DateTime startTime,
            Value<DateTime?> endTime = const Value.absent(),
            Value<int> totalExposures = const Value.absent(),
            Value<int> successfulExposures = const Value.absent(),
            Value<int> failedExposures = const Value.absent(),
            Value<double> totalIntegrationSecs = const Value.absent(),
            Value<double?> avgTemperature = const Value.absent(),
            Value<double?> avgHumidity = const Value.absent(),
            Value<double?> avgSeeing = const Value.absent(),
            Value<double?> avgHfr = const Value.absent(),
            Value<double?> avgGuidingRms = const Value.absent(),
            Value<int> autofocusCount = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int?> sequenceId = const Value.absent(),
            Value<String?> equipmentSnapshot = const Value.absent(),
          }) =>
              ImagingSessionsCompanion.insert(
            id: id,
            name: name,
            profileId: profileId,
            targetId: targetId,
            startTime: startTime,
            endTime: endTime,
            totalExposures: totalExposures,
            successfulExposures: successfulExposures,
            failedExposures: failedExposures,
            totalIntegrationSecs: totalIntegrationSecs,
            avgTemperature: avgTemperature,
            avgHumidity: avgHumidity,
            avgSeeing: avgSeeing,
            avgHfr: avgHfr,
            avgGuidingRms: avgGuidingRms,
            autofocusCount: autofocusCount,
            notes: notes,
            status: status,
            sequenceId: sequenceId,
            equipmentSnapshot: equipmentSnapshot,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ImagingSessionsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {profileId = false,
              targetId = false,
              sequenceId = false,
              capturedImagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (capturedImagesRefs) db.capturedImages
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (profileId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.profileId,
                    referencedTable:
                        $$ImagingSessionsTableReferences._profileIdTable(db),
                    referencedColumn:
                        $$ImagingSessionsTableReferences._profileIdTable(db).id,
                  ) as T;
                }
                if (targetId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.targetId,
                    referencedTable:
                        $$ImagingSessionsTableReferences._targetIdTable(db),
                    referencedColumn:
                        $$ImagingSessionsTableReferences._targetIdTable(db).id,
                  ) as T;
                }
                if (sequenceId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sequenceId,
                    referencedTable:
                        $$ImagingSessionsTableReferences._sequenceIdTable(db),
                    referencedColumn: $$ImagingSessionsTableReferences
                        ._sequenceIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (capturedImagesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$ImagingSessionsTableReferences
                            ._capturedImagesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ImagingSessionsTableReferences(db, table, p0)
                                .capturedImagesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.sessionId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ImagingSessionsTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $ImagingSessionsTable,
    ImagingSession,
    $$ImagingSessionsTableFilterComposer,
    $$ImagingSessionsTableOrderingComposer,
    $$ImagingSessionsTableAnnotationComposer,
    $$ImagingSessionsTableCreateCompanionBuilder,
    $$ImagingSessionsTableUpdateCompanionBuilder,
    (ImagingSession, $$ImagingSessionsTableReferences),
    ImagingSession,
    PrefetchHooks Function(
        {bool profileId,
        bool targetId,
        bool sequenceId,
        bool capturedImagesRefs})>;
typedef $$SequenceNodesTableCreateCompanionBuilder = SequenceNodesCompanion
    Function({
  Value<int> id,
  required String nodeId,
  required int sequenceId,
  Value<int?> targetId,
  required String nodeType,
  required String specificType,
  required String name,
  Value<String> properties,
  Value<String?> recoveryConfig,
  Value<String?> parentNodeId,
  Value<int> orderIndex,
  Value<bool> isEnabled,
});
typedef $$SequenceNodesTableUpdateCompanionBuilder = SequenceNodesCompanion
    Function({
  Value<int> id,
  Value<String> nodeId,
  Value<int> sequenceId,
  Value<int?> targetId,
  Value<String> nodeType,
  Value<String> specificType,
  Value<String> name,
  Value<String> properties,
  Value<String?> recoveryConfig,
  Value<String?> parentNodeId,
  Value<int> orderIndex,
  Value<bool> isEnabled,
});

final class $$SequenceNodesTableReferences extends BaseReferences<
    _$NightshadeDatabase, $SequenceNodesTable, SequenceNode> {
  $$SequenceNodesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $SequencesTable _sequenceIdTable(_$NightshadeDatabase db) =>
      db.sequences.createAlias(
          $_aliasNameGenerator(db.sequenceNodes.sequenceId, db.sequences.id));

  $$SequencesTableProcessedTableManager? get sequenceId {
    if ($_item.sequenceId == null) return null;
    final manager = $$SequencesTableTableManager($_db, $_db.sequences)
        .filter((f) => f.id($_item.sequenceId!));
    final item = $_typedResult.readTableOrNull(_sequenceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $TargetsTable _targetIdTable(_$NightshadeDatabase db) =>
      db.targets.createAlias(
          $_aliasNameGenerator(db.sequenceNodes.targetId, db.targets.id));

  $$TargetsTableProcessedTableManager? get targetId {
    if ($_item.targetId == null) return null;
    final manager = $$TargetsTableTableManager($_db, $_db.targets)
        .filter((f) => f.id($_item.targetId!));
    final item = $_typedResult.readTableOrNull(_targetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$SequenceNodesTableFilterComposer
    extends Composer<_$NightshadeDatabase, $SequenceNodesTable> {
  $$SequenceNodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nodeId => $composableBuilder(
      column: $table.nodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get nodeType => $composableBuilder(
      column: $table.nodeType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get specificType => $composableBuilder(
      column: $table.specificType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get properties => $composableBuilder(
      column: $table.properties, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recoveryConfig => $composableBuilder(
      column: $table.recoveryConfig,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get parentNodeId => $composableBuilder(
      column: $table.parentNodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnFilters(column));

  $$SequencesTableFilterComposer get sequenceId {
    final $$SequencesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableFilterComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TargetsTableFilterComposer get targetId {
    final $$TargetsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableFilterComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SequenceNodesTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $SequenceNodesTable> {
  $$SequenceNodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nodeId => $composableBuilder(
      column: $table.nodeId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get nodeType => $composableBuilder(
      column: $table.nodeType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get specificType => $composableBuilder(
      column: $table.specificType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get properties => $composableBuilder(
      column: $table.properties, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recoveryConfig => $composableBuilder(
      column: $table.recoveryConfig,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get parentNodeId => $composableBuilder(
      column: $table.parentNodeId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEnabled => $composableBuilder(
      column: $table.isEnabled, builder: (column) => ColumnOrderings(column));

  $$SequencesTableOrderingComposer get sequenceId {
    final $$SequencesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableOrderingComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TargetsTableOrderingComposer get targetId {
    final $$TargetsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableOrderingComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SequenceNodesTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $SequenceNodesTable> {
  $$SequenceNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get nodeId =>
      $composableBuilder(column: $table.nodeId, builder: (column) => column);

  GeneratedColumn<String> get nodeType =>
      $composableBuilder(column: $table.nodeType, builder: (column) => column);

  GeneratedColumn<String> get specificType => $composableBuilder(
      column: $table.specificType, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get properties => $composableBuilder(
      column: $table.properties, builder: (column) => column);

  GeneratedColumn<String> get recoveryConfig => $composableBuilder(
      column: $table.recoveryConfig, builder: (column) => column);

  GeneratedColumn<String> get parentNodeId => $composableBuilder(
      column: $table.parentNodeId, builder: (column) => column);

  GeneratedColumn<int> get orderIndex => $composableBuilder(
      column: $table.orderIndex, builder: (column) => column);

  GeneratedColumn<bool> get isEnabled =>
      $composableBuilder(column: $table.isEnabled, builder: (column) => column);

  $$SequencesTableAnnotationComposer get sequenceId {
    final $$SequencesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableAnnotationComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TargetsTableAnnotationComposer get targetId {
    final $$TargetsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableAnnotationComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SequenceNodesTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $SequenceNodesTable,
    SequenceNode,
    $$SequenceNodesTableFilterComposer,
    $$SequenceNodesTableOrderingComposer,
    $$SequenceNodesTableAnnotationComposer,
    $$SequenceNodesTableCreateCompanionBuilder,
    $$SequenceNodesTableUpdateCompanionBuilder,
    (SequenceNode, $$SequenceNodesTableReferences),
    SequenceNode,
    PrefetchHooks Function({bool sequenceId, bool targetId})> {
  $$SequenceNodesTableTableManager(
      _$NightshadeDatabase db, $SequenceNodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SequenceNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SequenceNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SequenceNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> nodeId = const Value.absent(),
            Value<int> sequenceId = const Value.absent(),
            Value<int?> targetId = const Value.absent(),
            Value<String> nodeType = const Value.absent(),
            Value<String> specificType = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> properties = const Value.absent(),
            Value<String?> recoveryConfig = const Value.absent(),
            Value<String?> parentNodeId = const Value.absent(),
            Value<int> orderIndex = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
          }) =>
              SequenceNodesCompanion(
            id: id,
            nodeId: nodeId,
            sequenceId: sequenceId,
            targetId: targetId,
            nodeType: nodeType,
            specificType: specificType,
            name: name,
            properties: properties,
            recoveryConfig: recoveryConfig,
            parentNodeId: parentNodeId,
            orderIndex: orderIndex,
            isEnabled: isEnabled,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String nodeId,
            required int sequenceId,
            Value<int?> targetId = const Value.absent(),
            required String nodeType,
            required String specificType,
            required String name,
            Value<String> properties = const Value.absent(),
            Value<String?> recoveryConfig = const Value.absent(),
            Value<String?> parentNodeId = const Value.absent(),
            Value<int> orderIndex = const Value.absent(),
            Value<bool> isEnabled = const Value.absent(),
          }) =>
              SequenceNodesCompanion.insert(
            id: id,
            nodeId: nodeId,
            sequenceId: sequenceId,
            targetId: targetId,
            nodeType: nodeType,
            specificType: specificType,
            name: name,
            properties: properties,
            recoveryConfig: recoveryConfig,
            parentNodeId: parentNodeId,
            orderIndex: orderIndex,
            isEnabled: isEnabled,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SequenceNodesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({sequenceId = false, targetId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sequenceId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sequenceId,
                    referencedTable:
                        $$SequenceNodesTableReferences._sequenceIdTable(db),
                    referencedColumn:
                        $$SequenceNodesTableReferences._sequenceIdTable(db).id,
                  ) as T;
                }
                if (targetId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.targetId,
                    referencedTable:
                        $$SequenceNodesTableReferences._targetIdTable(db),
                    referencedColumn:
                        $$SequenceNodesTableReferences._targetIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$SequenceNodesTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $SequenceNodesTable,
    SequenceNode,
    $$SequenceNodesTableFilterComposer,
    $$SequenceNodesTableOrderingComposer,
    $$SequenceNodesTableAnnotationComposer,
    $$SequenceNodesTableCreateCompanionBuilder,
    $$SequenceNodesTableUpdateCompanionBuilder,
    (SequenceNode, $$SequenceNodesTableReferences),
    SequenceNode,
    PrefetchHooks Function({bool sequenceId, bool targetId})>;
typedef $$SequenceCheckpointsTableCreateCompanionBuilder
    = SequenceCheckpointsCompanion Function({
  Value<int> sequenceId,
  required String currentNodeId,
  required String stateJson,
  required int completedFrames,
  required int totalFrames,
  required int currentTargetIndex,
  Value<DateTime> checkpointedAt,
});
typedef $$SequenceCheckpointsTableUpdateCompanionBuilder
    = SequenceCheckpointsCompanion Function({
  Value<int> sequenceId,
  Value<String> currentNodeId,
  Value<String> stateJson,
  Value<int> completedFrames,
  Value<int> totalFrames,
  Value<int> currentTargetIndex,
  Value<DateTime> checkpointedAt,
});

final class $$SequenceCheckpointsTableReferences extends BaseReferences<
    _$NightshadeDatabase, $SequenceCheckpointsTable, SequenceCheckpoint> {
  $$SequenceCheckpointsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $SequencesTable _sequenceIdTable(_$NightshadeDatabase db) =>
      db.sequences.createAlias($_aliasNameGenerator(
          db.sequenceCheckpoints.sequenceId, db.sequences.id));

  $$SequencesTableProcessedTableManager? get sequenceId {
    if ($_item.sequenceId == null) return null;
    final manager = $$SequencesTableTableManager($_db, $_db.sequences)
        .filter((f) => f.id($_item.sequenceId!));
    final item = $_typedResult.readTableOrNull(_sequenceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$SequenceCheckpointsTableFilterComposer
    extends Composer<_$NightshadeDatabase, $SequenceCheckpointsTable> {
  $$SequenceCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get currentNodeId => $composableBuilder(
      column: $table.currentNodeId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stateJson => $composableBuilder(
      column: $table.stateJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get completedFrames => $composableBuilder(
      column: $table.completedFrames,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalFrames => $composableBuilder(
      column: $table.totalFrames, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get currentTargetIndex => $composableBuilder(
      column: $table.currentTargetIndex,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get checkpointedAt => $composableBuilder(
      column: $table.checkpointedAt,
      builder: (column) => ColumnFilters(column));

  $$SequencesTableFilterComposer get sequenceId {
    final $$SequencesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableFilterComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SequenceCheckpointsTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $SequenceCheckpointsTable> {
  $$SequenceCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get currentNodeId => $composableBuilder(
      column: $table.currentNodeId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stateJson => $composableBuilder(
      column: $table.stateJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get completedFrames => $composableBuilder(
      column: $table.completedFrames,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalFrames => $composableBuilder(
      column: $table.totalFrames, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get currentTargetIndex => $composableBuilder(
      column: $table.currentTargetIndex,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get checkpointedAt => $composableBuilder(
      column: $table.checkpointedAt,
      builder: (column) => ColumnOrderings(column));

  $$SequencesTableOrderingComposer get sequenceId {
    final $$SequencesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableOrderingComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SequenceCheckpointsTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $SequenceCheckpointsTable> {
  $$SequenceCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get currentNodeId => $composableBuilder(
      column: $table.currentNodeId, builder: (column) => column);

  GeneratedColumn<String> get stateJson =>
      $composableBuilder(column: $table.stateJson, builder: (column) => column);

  GeneratedColumn<int> get completedFrames => $composableBuilder(
      column: $table.completedFrames, builder: (column) => column);

  GeneratedColumn<int> get totalFrames => $composableBuilder(
      column: $table.totalFrames, builder: (column) => column);

  GeneratedColumn<int> get currentTargetIndex => $composableBuilder(
      column: $table.currentTargetIndex, builder: (column) => column);

  GeneratedColumn<DateTime> get checkpointedAt => $composableBuilder(
      column: $table.checkpointedAt, builder: (column) => column);

  $$SequencesTableAnnotationComposer get sequenceId {
    final $$SequencesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sequenceId,
        referencedTable: $db.sequences,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SequencesTableAnnotationComposer(
              $db: $db,
              $table: $db.sequences,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SequenceCheckpointsTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $SequenceCheckpointsTable,
    SequenceCheckpoint,
    $$SequenceCheckpointsTableFilterComposer,
    $$SequenceCheckpointsTableOrderingComposer,
    $$SequenceCheckpointsTableAnnotationComposer,
    $$SequenceCheckpointsTableCreateCompanionBuilder,
    $$SequenceCheckpointsTableUpdateCompanionBuilder,
    (SequenceCheckpoint, $$SequenceCheckpointsTableReferences),
    SequenceCheckpoint,
    PrefetchHooks Function({bool sequenceId})> {
  $$SequenceCheckpointsTableTableManager(
      _$NightshadeDatabase db, $SequenceCheckpointsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SequenceCheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SequenceCheckpointsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SequenceCheckpointsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> sequenceId = const Value.absent(),
            Value<String> currentNodeId = const Value.absent(),
            Value<String> stateJson = const Value.absent(),
            Value<int> completedFrames = const Value.absent(),
            Value<int> totalFrames = const Value.absent(),
            Value<int> currentTargetIndex = const Value.absent(),
            Value<DateTime> checkpointedAt = const Value.absent(),
          }) =>
              SequenceCheckpointsCompanion(
            sequenceId: sequenceId,
            currentNodeId: currentNodeId,
            stateJson: stateJson,
            completedFrames: completedFrames,
            totalFrames: totalFrames,
            currentTargetIndex: currentTargetIndex,
            checkpointedAt: checkpointedAt,
          ),
          createCompanionCallback: ({
            Value<int> sequenceId = const Value.absent(),
            required String currentNodeId,
            required String stateJson,
            required int completedFrames,
            required int totalFrames,
            required int currentTargetIndex,
            Value<DateTime> checkpointedAt = const Value.absent(),
          }) =>
              SequenceCheckpointsCompanion.insert(
            sequenceId: sequenceId,
            currentNodeId: currentNodeId,
            stateJson: stateJson,
            completedFrames: completedFrames,
            totalFrames: totalFrames,
            currentTargetIndex: currentTargetIndex,
            checkpointedAt: checkpointedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SequenceCheckpointsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({sequenceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sequenceId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sequenceId,
                    referencedTable: $$SequenceCheckpointsTableReferences
                        ._sequenceIdTable(db),
                    referencedColumn: $$SequenceCheckpointsTableReferences
                        ._sequenceIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$SequenceCheckpointsTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $SequenceCheckpointsTable,
    SequenceCheckpoint,
    $$SequenceCheckpointsTableFilterComposer,
    $$SequenceCheckpointsTableOrderingComposer,
    $$SequenceCheckpointsTableAnnotationComposer,
    $$SequenceCheckpointsTableCreateCompanionBuilder,
    $$SequenceCheckpointsTableUpdateCompanionBuilder,
    (SequenceCheckpoint, $$SequenceCheckpointsTableReferences),
    SequenceCheckpoint,
    PrefetchHooks Function({bool sequenceId})>;
typedef $$CapturedImagesTableCreateCompanionBuilder = CapturedImagesCompanion
    Function({
  Value<int> id,
  required String filePath,
  required String fileName,
  Value<String> fileFormat,
  Value<int?> fileSize,
  Value<int?> sessionId,
  Value<int?> targetId,
  Value<String> frameType,
  required double exposureDuration,
  Value<int?> gain,
  Value<int?> offset,
  Value<int> binX,
  Value<int> binY,
  Value<String?> filter,
  Value<double?> sensorTemp,
  Value<double?> coolerPower,
  Value<double?> hfr,
  Value<int?> starCount,
  Value<double?> background,
  Value<double?> noise,
  Value<double?> qualityScore,
  Value<double?> guidingRmsRa,
  Value<double?> guidingRmsDec,
  Value<double?> guidingRmsTotal,
  Value<double?> mountRa,
  Value<double?> mountDec,
  Value<double?> mountAltitude,
  Value<double?> mountAzimuth,
  Value<String?> pierSide,
  Value<int?> focuserPosition,
  Value<double?> focuserTemp,
  Value<double?> rotatorAngle,
  Value<bool> isPlateSolved,
  Value<double?> solvedRa,
  Value<double?> solvedDec,
  Value<double?> solvedRotation,
  Value<double?> solvedPixelScale,
  required DateTime capturedAt,
  Value<DateTime> createdAt,
  Value<bool> isAccepted,
  Value<String?> rejectionReason,
});
typedef $$CapturedImagesTableUpdateCompanionBuilder = CapturedImagesCompanion
    Function({
  Value<int> id,
  Value<String> filePath,
  Value<String> fileName,
  Value<String> fileFormat,
  Value<int?> fileSize,
  Value<int?> sessionId,
  Value<int?> targetId,
  Value<String> frameType,
  Value<double> exposureDuration,
  Value<int?> gain,
  Value<int?> offset,
  Value<int> binX,
  Value<int> binY,
  Value<String?> filter,
  Value<double?> sensorTemp,
  Value<double?> coolerPower,
  Value<double?> hfr,
  Value<int?> starCount,
  Value<double?> background,
  Value<double?> noise,
  Value<double?> qualityScore,
  Value<double?> guidingRmsRa,
  Value<double?> guidingRmsDec,
  Value<double?> guidingRmsTotal,
  Value<double?> mountRa,
  Value<double?> mountDec,
  Value<double?> mountAltitude,
  Value<double?> mountAzimuth,
  Value<String?> pierSide,
  Value<int?> focuserPosition,
  Value<double?> focuserTemp,
  Value<double?> rotatorAngle,
  Value<bool> isPlateSolved,
  Value<double?> solvedRa,
  Value<double?> solvedDec,
  Value<double?> solvedRotation,
  Value<double?> solvedPixelScale,
  Value<DateTime> capturedAt,
  Value<DateTime> createdAt,
  Value<bool> isAccepted,
  Value<String?> rejectionReason,
});

final class $$CapturedImagesTableReferences extends BaseReferences<
    _$NightshadeDatabase, $CapturedImagesTable, CapturedImage> {
  $$CapturedImagesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ImagingSessionsTable _sessionIdTable(_$NightshadeDatabase db) =>
      db.imagingSessions.createAlias($_aliasNameGenerator(
          db.capturedImages.sessionId, db.imagingSessions.id));

  $$ImagingSessionsTableProcessedTableManager? get sessionId {
    if ($_item.sessionId == null) return null;
    final manager =
        $$ImagingSessionsTableTableManager($_db, $_db.imagingSessions)
            .filter((f) => f.id($_item.sessionId!));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $TargetsTable _targetIdTable(_$NightshadeDatabase db) =>
      db.targets.createAlias(
          $_aliasNameGenerator(db.capturedImages.targetId, db.targets.id));

  $$TargetsTableProcessedTableManager? get targetId {
    if ($_item.targetId == null) return null;
    final manager = $$TargetsTableTableManager($_db, $_db.targets)
        .filter((f) => f.id($_item.targetId!));
    final item = $_typedResult.readTableOrNull(_targetIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$ImageMetadataTable, List<ImageMetadatum>>
      _imageMetadataRefsTable(_$NightshadeDatabase db) =>
          MultiTypedResultKey.fromTable(db.imageMetadata,
              aliasName: $_aliasNameGenerator(
                  db.capturedImages.id, db.imageMetadata.imageId));

  $$ImageMetadataTableProcessedTableManager get imageMetadataRefs {
    final manager = $$ImageMetadataTableTableManager($_db, $_db.imageMetadata)
        .filter((f) => f.imageId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_imageMetadataRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$CapturedImagesTableFilterComposer
    extends Composer<_$NightshadeDatabase, $CapturedImagesTable> {
  $$CapturedImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileFormat => $composableBuilder(
      column: $table.fileFormat, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get fileSize => $composableBuilder(
      column: $table.fileSize, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get frameType => $composableBuilder(
      column: $table.frameType, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get exposureDuration => $composableBuilder(
      column: $table.exposureDuration,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get gain => $composableBuilder(
      column: $table.gain, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get offset => $composableBuilder(
      column: $table.offset, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get binX => $composableBuilder(
      column: $table.binX, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get binY => $composableBuilder(
      column: $table.binY, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filter => $composableBuilder(
      column: $table.filter, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get sensorTemp => $composableBuilder(
      column: $table.sensorTemp, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get coolerPower => $composableBuilder(
      column: $table.coolerPower, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get hfr => $composableBuilder(
      column: $table.hfr, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get starCount => $composableBuilder(
      column: $table.starCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get background => $composableBuilder(
      column: $table.background, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get noise => $composableBuilder(
      column: $table.noise, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get qualityScore => $composableBuilder(
      column: $table.qualityScore, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get guidingRmsRa => $composableBuilder(
      column: $table.guidingRmsRa, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get guidingRmsDec => $composableBuilder(
      column: $table.guidingRmsDec, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get guidingRmsTotal => $composableBuilder(
      column: $table.guidingRmsTotal,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mountRa => $composableBuilder(
      column: $table.mountRa, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mountDec => $composableBuilder(
      column: $table.mountDec, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mountAltitude => $composableBuilder(
      column: $table.mountAltitude, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get mountAzimuth => $composableBuilder(
      column: $table.mountAzimuth, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pierSide => $composableBuilder(
      column: $table.pierSide, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get focuserPosition => $composableBuilder(
      column: $table.focuserPosition,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get focuserTemp => $composableBuilder(
      column: $table.focuserTemp, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get rotatorAngle => $composableBuilder(
      column: $table.rotatorAngle, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPlateSolved => $composableBuilder(
      column: $table.isPlateSolved, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get solvedRa => $composableBuilder(
      column: $table.solvedRa, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get solvedDec => $composableBuilder(
      column: $table.solvedDec, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get solvedRotation => $composableBuilder(
      column: $table.solvedRotation,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get solvedPixelScale => $composableBuilder(
      column: $table.solvedPixelScale,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isAccepted => $composableBuilder(
      column: $table.isAccepted, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get rejectionReason => $composableBuilder(
      column: $table.rejectionReason,
      builder: (column) => ColumnFilters(column));

  $$ImagingSessionsTableFilterComposer get sessionId {
    final $$ImagingSessionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableFilterComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TargetsTableFilterComposer get targetId {
    final $$TargetsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableFilterComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> imageMetadataRefs(
      Expression<bool> Function($$ImageMetadataTableFilterComposer f) f) {
    final $$ImageMetadataTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.imageMetadata,
        getReferencedColumn: (t) => t.imageId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImageMetadataTableFilterComposer(
              $db: $db,
              $table: $db.imageMetadata,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$CapturedImagesTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $CapturedImagesTable> {
  $$CapturedImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filePath => $composableBuilder(
      column: $table.filePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileFormat => $composableBuilder(
      column: $table.fileFormat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get fileSize => $composableBuilder(
      column: $table.fileSize, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get frameType => $composableBuilder(
      column: $table.frameType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get exposureDuration => $composableBuilder(
      column: $table.exposureDuration,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get gain => $composableBuilder(
      column: $table.gain, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get offset => $composableBuilder(
      column: $table.offset, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get binX => $composableBuilder(
      column: $table.binX, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get binY => $composableBuilder(
      column: $table.binY, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filter => $composableBuilder(
      column: $table.filter, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get sensorTemp => $composableBuilder(
      column: $table.sensorTemp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get coolerPower => $composableBuilder(
      column: $table.coolerPower, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get hfr => $composableBuilder(
      column: $table.hfr, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get starCount => $composableBuilder(
      column: $table.starCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get background => $composableBuilder(
      column: $table.background, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get noise => $composableBuilder(
      column: $table.noise, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get qualityScore => $composableBuilder(
      column: $table.qualityScore,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get guidingRmsRa => $composableBuilder(
      column: $table.guidingRmsRa,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get guidingRmsDec => $composableBuilder(
      column: $table.guidingRmsDec,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get guidingRmsTotal => $composableBuilder(
      column: $table.guidingRmsTotal,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mountRa => $composableBuilder(
      column: $table.mountRa, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mountDec => $composableBuilder(
      column: $table.mountDec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mountAltitude => $composableBuilder(
      column: $table.mountAltitude,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get mountAzimuth => $composableBuilder(
      column: $table.mountAzimuth,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pierSide => $composableBuilder(
      column: $table.pierSide, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get focuserPosition => $composableBuilder(
      column: $table.focuserPosition,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get focuserTemp => $composableBuilder(
      column: $table.focuserTemp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get rotatorAngle => $composableBuilder(
      column: $table.rotatorAngle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPlateSolved => $composableBuilder(
      column: $table.isPlateSolved,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get solvedRa => $composableBuilder(
      column: $table.solvedRa, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get solvedDec => $composableBuilder(
      column: $table.solvedDec, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get solvedRotation => $composableBuilder(
      column: $table.solvedRotation,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get solvedPixelScale => $composableBuilder(
      column: $table.solvedPixelScale,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isAccepted => $composableBuilder(
      column: $table.isAccepted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get rejectionReason => $composableBuilder(
      column: $table.rejectionReason,
      builder: (column) => ColumnOrderings(column));

  $$ImagingSessionsTableOrderingComposer get sessionId {
    final $$ImagingSessionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableOrderingComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TargetsTableOrderingComposer get targetId {
    final $$TargetsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableOrderingComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$CapturedImagesTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $CapturedImagesTable> {
  $$CapturedImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get fileFormat => $composableBuilder(
      column: $table.fileFormat, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get frameType =>
      $composableBuilder(column: $table.frameType, builder: (column) => column);

  GeneratedColumn<double> get exposureDuration => $composableBuilder(
      column: $table.exposureDuration, builder: (column) => column);

  GeneratedColumn<int> get gain =>
      $composableBuilder(column: $table.gain, builder: (column) => column);

  GeneratedColumn<int> get offset =>
      $composableBuilder(column: $table.offset, builder: (column) => column);

  GeneratedColumn<int> get binX =>
      $composableBuilder(column: $table.binX, builder: (column) => column);

  GeneratedColumn<int> get binY =>
      $composableBuilder(column: $table.binY, builder: (column) => column);

  GeneratedColumn<String> get filter =>
      $composableBuilder(column: $table.filter, builder: (column) => column);

  GeneratedColumn<double> get sensorTemp => $composableBuilder(
      column: $table.sensorTemp, builder: (column) => column);

  GeneratedColumn<double> get coolerPower => $composableBuilder(
      column: $table.coolerPower, builder: (column) => column);

  GeneratedColumn<double> get hfr =>
      $composableBuilder(column: $table.hfr, builder: (column) => column);

  GeneratedColumn<int> get starCount =>
      $composableBuilder(column: $table.starCount, builder: (column) => column);

  GeneratedColumn<double> get background => $composableBuilder(
      column: $table.background, builder: (column) => column);

  GeneratedColumn<double> get noise =>
      $composableBuilder(column: $table.noise, builder: (column) => column);

  GeneratedColumn<double> get qualityScore => $composableBuilder(
      column: $table.qualityScore, builder: (column) => column);

  GeneratedColumn<double> get guidingRmsRa => $composableBuilder(
      column: $table.guidingRmsRa, builder: (column) => column);

  GeneratedColumn<double> get guidingRmsDec => $composableBuilder(
      column: $table.guidingRmsDec, builder: (column) => column);

  GeneratedColumn<double> get guidingRmsTotal => $composableBuilder(
      column: $table.guidingRmsTotal, builder: (column) => column);

  GeneratedColumn<double> get mountRa =>
      $composableBuilder(column: $table.mountRa, builder: (column) => column);

  GeneratedColumn<double> get mountDec =>
      $composableBuilder(column: $table.mountDec, builder: (column) => column);

  GeneratedColumn<double> get mountAltitude => $composableBuilder(
      column: $table.mountAltitude, builder: (column) => column);

  GeneratedColumn<double> get mountAzimuth => $composableBuilder(
      column: $table.mountAzimuth, builder: (column) => column);

  GeneratedColumn<String> get pierSide =>
      $composableBuilder(column: $table.pierSide, builder: (column) => column);

  GeneratedColumn<int> get focuserPosition => $composableBuilder(
      column: $table.focuserPosition, builder: (column) => column);

  GeneratedColumn<double> get focuserTemp => $composableBuilder(
      column: $table.focuserTemp, builder: (column) => column);

  GeneratedColumn<double> get rotatorAngle => $composableBuilder(
      column: $table.rotatorAngle, builder: (column) => column);

  GeneratedColumn<bool> get isPlateSolved => $composableBuilder(
      column: $table.isPlateSolved, builder: (column) => column);

  GeneratedColumn<double> get solvedRa =>
      $composableBuilder(column: $table.solvedRa, builder: (column) => column);

  GeneratedColumn<double> get solvedDec =>
      $composableBuilder(column: $table.solvedDec, builder: (column) => column);

  GeneratedColumn<double> get solvedRotation => $composableBuilder(
      column: $table.solvedRotation, builder: (column) => column);

  GeneratedColumn<double> get solvedPixelScale => $composableBuilder(
      column: $table.solvedPixelScale, builder: (column) => column);

  GeneratedColumn<DateTime> get capturedAt => $composableBuilder(
      column: $table.capturedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isAccepted => $composableBuilder(
      column: $table.isAccepted, builder: (column) => column);

  GeneratedColumn<String> get rejectionReason => $composableBuilder(
      column: $table.rejectionReason, builder: (column) => column);

  $$ImagingSessionsTableAnnotationComposer get sessionId {
    final $$ImagingSessionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.sessionId,
        referencedTable: $db.imagingSessions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImagingSessionsTableAnnotationComposer(
              $db: $db,
              $table: $db.imagingSessions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$TargetsTableAnnotationComposer get targetId {
    final $$TargetsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.targetId,
        referencedTable: $db.targets,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$TargetsTableAnnotationComposer(
              $db: $db,
              $table: $db.targets,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> imageMetadataRefs<T extends Object>(
      Expression<T> Function($$ImageMetadataTableAnnotationComposer a) f) {
    final $$ImageMetadataTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.imageMetadata,
        getReferencedColumn: (t) => t.imageId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ImageMetadataTableAnnotationComposer(
              $db: $db,
              $table: $db.imageMetadata,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$CapturedImagesTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $CapturedImagesTable,
    CapturedImage,
    $$CapturedImagesTableFilterComposer,
    $$CapturedImagesTableOrderingComposer,
    $$CapturedImagesTableAnnotationComposer,
    $$CapturedImagesTableCreateCompanionBuilder,
    $$CapturedImagesTableUpdateCompanionBuilder,
    (CapturedImage, $$CapturedImagesTableReferences),
    CapturedImage,
    PrefetchHooks Function(
        {bool sessionId, bool targetId, bool imageMetadataRefs})> {
  $$CapturedImagesTableTableManager(
      _$NightshadeDatabase db, $CapturedImagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CapturedImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CapturedImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CapturedImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<String> fileName = const Value.absent(),
            Value<String> fileFormat = const Value.absent(),
            Value<int?> fileSize = const Value.absent(),
            Value<int?> sessionId = const Value.absent(),
            Value<int?> targetId = const Value.absent(),
            Value<String> frameType = const Value.absent(),
            Value<double> exposureDuration = const Value.absent(),
            Value<int?> gain = const Value.absent(),
            Value<int?> offset = const Value.absent(),
            Value<int> binX = const Value.absent(),
            Value<int> binY = const Value.absent(),
            Value<String?> filter = const Value.absent(),
            Value<double?> sensorTemp = const Value.absent(),
            Value<double?> coolerPower = const Value.absent(),
            Value<double?> hfr = const Value.absent(),
            Value<int?> starCount = const Value.absent(),
            Value<double?> background = const Value.absent(),
            Value<double?> noise = const Value.absent(),
            Value<double?> qualityScore = const Value.absent(),
            Value<double?> guidingRmsRa = const Value.absent(),
            Value<double?> guidingRmsDec = const Value.absent(),
            Value<double?> guidingRmsTotal = const Value.absent(),
            Value<double?> mountRa = const Value.absent(),
            Value<double?> mountDec = const Value.absent(),
            Value<double?> mountAltitude = const Value.absent(),
            Value<double?> mountAzimuth = const Value.absent(),
            Value<String?> pierSide = const Value.absent(),
            Value<int?> focuserPosition = const Value.absent(),
            Value<double?> focuserTemp = const Value.absent(),
            Value<double?> rotatorAngle = const Value.absent(),
            Value<bool> isPlateSolved = const Value.absent(),
            Value<double?> solvedRa = const Value.absent(),
            Value<double?> solvedDec = const Value.absent(),
            Value<double?> solvedRotation = const Value.absent(),
            Value<double?> solvedPixelScale = const Value.absent(),
            Value<DateTime> capturedAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isAccepted = const Value.absent(),
            Value<String?> rejectionReason = const Value.absent(),
          }) =>
              CapturedImagesCompanion(
            id: id,
            filePath: filePath,
            fileName: fileName,
            fileFormat: fileFormat,
            fileSize: fileSize,
            sessionId: sessionId,
            targetId: targetId,
            frameType: frameType,
            exposureDuration: exposureDuration,
            gain: gain,
            offset: offset,
            binX: binX,
            binY: binY,
            filter: filter,
            sensorTemp: sensorTemp,
            coolerPower: coolerPower,
            hfr: hfr,
            starCount: starCount,
            background: background,
            noise: noise,
            qualityScore: qualityScore,
            guidingRmsRa: guidingRmsRa,
            guidingRmsDec: guidingRmsDec,
            guidingRmsTotal: guidingRmsTotal,
            mountRa: mountRa,
            mountDec: mountDec,
            mountAltitude: mountAltitude,
            mountAzimuth: mountAzimuth,
            pierSide: pierSide,
            focuserPosition: focuserPosition,
            focuserTemp: focuserTemp,
            rotatorAngle: rotatorAngle,
            isPlateSolved: isPlateSolved,
            solvedRa: solvedRa,
            solvedDec: solvedDec,
            solvedRotation: solvedRotation,
            solvedPixelScale: solvedPixelScale,
            capturedAt: capturedAt,
            createdAt: createdAt,
            isAccepted: isAccepted,
            rejectionReason: rejectionReason,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String filePath,
            required String fileName,
            Value<String> fileFormat = const Value.absent(),
            Value<int?> fileSize = const Value.absent(),
            Value<int?> sessionId = const Value.absent(),
            Value<int?> targetId = const Value.absent(),
            Value<String> frameType = const Value.absent(),
            required double exposureDuration,
            Value<int?> gain = const Value.absent(),
            Value<int?> offset = const Value.absent(),
            Value<int> binX = const Value.absent(),
            Value<int> binY = const Value.absent(),
            Value<String?> filter = const Value.absent(),
            Value<double?> sensorTemp = const Value.absent(),
            Value<double?> coolerPower = const Value.absent(),
            Value<double?> hfr = const Value.absent(),
            Value<int?> starCount = const Value.absent(),
            Value<double?> background = const Value.absent(),
            Value<double?> noise = const Value.absent(),
            Value<double?> qualityScore = const Value.absent(),
            Value<double?> guidingRmsRa = const Value.absent(),
            Value<double?> guidingRmsDec = const Value.absent(),
            Value<double?> guidingRmsTotal = const Value.absent(),
            Value<double?> mountRa = const Value.absent(),
            Value<double?> mountDec = const Value.absent(),
            Value<double?> mountAltitude = const Value.absent(),
            Value<double?> mountAzimuth = const Value.absent(),
            Value<String?> pierSide = const Value.absent(),
            Value<int?> focuserPosition = const Value.absent(),
            Value<double?> focuserTemp = const Value.absent(),
            Value<double?> rotatorAngle = const Value.absent(),
            Value<bool> isPlateSolved = const Value.absent(),
            Value<double?> solvedRa = const Value.absent(),
            Value<double?> solvedDec = const Value.absent(),
            Value<double?> solvedRotation = const Value.absent(),
            Value<double?> solvedPixelScale = const Value.absent(),
            required DateTime capturedAt,
            Value<DateTime> createdAt = const Value.absent(),
            Value<bool> isAccepted = const Value.absent(),
            Value<String?> rejectionReason = const Value.absent(),
          }) =>
              CapturedImagesCompanion.insert(
            id: id,
            filePath: filePath,
            fileName: fileName,
            fileFormat: fileFormat,
            fileSize: fileSize,
            sessionId: sessionId,
            targetId: targetId,
            frameType: frameType,
            exposureDuration: exposureDuration,
            gain: gain,
            offset: offset,
            binX: binX,
            binY: binY,
            filter: filter,
            sensorTemp: sensorTemp,
            coolerPower: coolerPower,
            hfr: hfr,
            starCount: starCount,
            background: background,
            noise: noise,
            qualityScore: qualityScore,
            guidingRmsRa: guidingRmsRa,
            guidingRmsDec: guidingRmsDec,
            guidingRmsTotal: guidingRmsTotal,
            mountRa: mountRa,
            mountDec: mountDec,
            mountAltitude: mountAltitude,
            mountAzimuth: mountAzimuth,
            pierSide: pierSide,
            focuserPosition: focuserPosition,
            focuserTemp: focuserTemp,
            rotatorAngle: rotatorAngle,
            isPlateSolved: isPlateSolved,
            solvedRa: solvedRa,
            solvedDec: solvedDec,
            solvedRotation: solvedRotation,
            solvedPixelScale: solvedPixelScale,
            capturedAt: capturedAt,
            createdAt: createdAt,
            isAccepted: isAccepted,
            rejectionReason: rejectionReason,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$CapturedImagesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {sessionId = false,
              targetId = false,
              imageMetadataRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (imageMetadataRefs) db.imageMetadata
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (sessionId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.sessionId,
                    referencedTable:
                        $$CapturedImagesTableReferences._sessionIdTable(db),
                    referencedColumn:
                        $$CapturedImagesTableReferences._sessionIdTable(db).id,
                  ) as T;
                }
                if (targetId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.targetId,
                    referencedTable:
                        $$CapturedImagesTableReferences._targetIdTable(db),
                    referencedColumn:
                        $$CapturedImagesTableReferences._targetIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (imageMetadataRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$CapturedImagesTableReferences
                            ._imageMetadataRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$CapturedImagesTableReferences(db, table, p0)
                                .imageMetadataRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.imageId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$CapturedImagesTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $CapturedImagesTable,
    CapturedImage,
    $$CapturedImagesTableFilterComposer,
    $$CapturedImagesTableOrderingComposer,
    $$CapturedImagesTableAnnotationComposer,
    $$CapturedImagesTableCreateCompanionBuilder,
    $$CapturedImagesTableUpdateCompanionBuilder,
    (CapturedImage, $$CapturedImagesTableReferences),
    CapturedImage,
    PrefetchHooks Function(
        {bool sessionId, bool targetId, bool imageMetadataRefs})>;
typedef $$ImageMetadataTableCreateCompanionBuilder = ImageMetadataCompanion
    Function({
  Value<int> id,
  required int imageId,
  required String key,
  required String value,
  Value<String?> comment,
});
typedef $$ImageMetadataTableUpdateCompanionBuilder = ImageMetadataCompanion
    Function({
  Value<int> id,
  Value<int> imageId,
  Value<String> key,
  Value<String> value,
  Value<String?> comment,
});

final class $$ImageMetadataTableReferences extends BaseReferences<
    _$NightshadeDatabase, $ImageMetadataTable, ImageMetadatum> {
  $$ImageMetadataTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $CapturedImagesTable _imageIdTable(_$NightshadeDatabase db) =>
      db.capturedImages.createAlias(
          $_aliasNameGenerator(db.imageMetadata.imageId, db.capturedImages.id));

  $$CapturedImagesTableProcessedTableManager? get imageId {
    if ($_item.imageId == null) return null;
    final manager = $$CapturedImagesTableTableManager($_db, $_db.capturedImages)
        .filter((f) => f.id($_item.imageId!));
    final item = $_typedResult.readTableOrNull(_imageIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ImageMetadataTableFilterComposer
    extends Composer<_$NightshadeDatabase, $ImageMetadataTable> {
  $$ImageMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get comment => $composableBuilder(
      column: $table.comment, builder: (column) => ColumnFilters(column));

  $$CapturedImagesTableFilterComposer get imageId {
    final $$CapturedImagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.imageId,
        referencedTable: $db.capturedImages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CapturedImagesTableFilterComposer(
              $db: $db,
              $table: $db.capturedImages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ImageMetadataTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $ImageMetadataTable> {
  $$ImageMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get comment => $composableBuilder(
      column: $table.comment, builder: (column) => ColumnOrderings(column));

  $$CapturedImagesTableOrderingComposer get imageId {
    final $$CapturedImagesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.imageId,
        referencedTable: $db.capturedImages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CapturedImagesTableOrderingComposer(
              $db: $db,
              $table: $db.capturedImages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ImageMetadataTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $ImageMetadataTable> {
  $$ImageMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get comment =>
      $composableBuilder(column: $table.comment, builder: (column) => column);

  $$CapturedImagesTableAnnotationComposer get imageId {
    final $$CapturedImagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.imageId,
        referencedTable: $db.capturedImages,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CapturedImagesTableAnnotationComposer(
              $db: $db,
              $table: $db.capturedImages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ImageMetadataTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $ImageMetadataTable,
    ImageMetadatum,
    $$ImageMetadataTableFilterComposer,
    $$ImageMetadataTableOrderingComposer,
    $$ImageMetadataTableAnnotationComposer,
    $$ImageMetadataTableCreateCompanionBuilder,
    $$ImageMetadataTableUpdateCompanionBuilder,
    (ImageMetadatum, $$ImageMetadataTableReferences),
    ImageMetadatum,
    PrefetchHooks Function({bool imageId})> {
  $$ImageMetadataTableTableManager(
      _$NightshadeDatabase db, $ImageMetadataTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImageMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImageMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImageMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> imageId = const Value.absent(),
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<String?> comment = const Value.absent(),
          }) =>
              ImageMetadataCompanion(
            id: id,
            imageId: imageId,
            key: key,
            value: value,
            comment: comment,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int imageId,
            required String key,
            required String value,
            Value<String?> comment = const Value.absent(),
          }) =>
              ImageMetadataCompanion.insert(
            id: id,
            imageId: imageId,
            key: key,
            value: value,
            comment: comment,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ImageMetadataTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({imageId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (imageId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.imageId,
                    referencedTable:
                        $$ImageMetadataTableReferences._imageIdTable(db),
                    referencedColumn:
                        $$ImageMetadataTableReferences._imageIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ImageMetadataTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $ImageMetadataTable,
    ImageMetadatum,
    $$ImageMetadataTableFilterComposer,
    $$ImageMetadataTableOrderingComposer,
    $$ImageMetadataTableAnnotationComposer,
    $$ImageMetadataTableCreateCompanionBuilder,
    $$ImageMetadataTableUpdateCompanionBuilder,
    (ImageMetadatum, $$ImageMetadataTableReferences),
    ImageMetadatum,
    PrefetchHooks Function({bool imageId})>;
typedef $$AppSettingsTableCreateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<int> id,
  required String key,
  required String value,
  Value<DateTime> updatedAt,
});
typedef $$AppSettingsTableUpdateCompanionBuilder = AppSettingsCompanion
    Function({
  Value<int> id,
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
});

class $$AppSettingsTableFilterComposer
    extends Composer<_$NightshadeDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppSettingsTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      AppSetting,
      BaseReferences<_$NightshadeDatabase, $AppSettingsTable, AppSetting>
    ),
    AppSetting,
    PrefetchHooks Function()> {
  $$AppSettingsTableTableManager(
      _$NightshadeDatabase db, $AppSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              AppSettingsCompanion(
            id: id,
            key: key,
            value: value,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String key,
            required String value,
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              AppSettingsCompanion.insert(
            id: id,
            key: key,
            value: value,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppSettingsTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $AppSettingsTable,
    AppSetting,
    $$AppSettingsTableFilterComposer,
    $$AppSettingsTableOrderingComposer,
    $$AppSettingsTableAnnotationComposer,
    $$AppSettingsTableCreateCompanionBuilder,
    $$AppSettingsTableUpdateCompanionBuilder,
    (
      AppSetting,
      BaseReferences<_$NightshadeDatabase, $AppSettingsTable, AppSetting>
    ),
    AppSetting,
    PrefetchHooks Function()>;
typedef $$WeatherSettingsTableCreateCompanionBuilder = WeatherSettingsCompanion
    Function({
  Value<int> id,
  Value<double> triggerDistanceKm,
  Value<double> cloudDensityThreshold,
  Value<int> leadTimeMinutes,
  Value<bool> weatherSafetyEnabled,
  Value<bool> autoParkEnabled,
  Value<bool> autoResumeEnabled,
  Value<String> preferredProvider,
  Value<int> refreshIntervalSeconds,
  Value<DateTime> updatedAt,
});
typedef $$WeatherSettingsTableUpdateCompanionBuilder = WeatherSettingsCompanion
    Function({
  Value<int> id,
  Value<double> triggerDistanceKm,
  Value<double> cloudDensityThreshold,
  Value<int> leadTimeMinutes,
  Value<bool> weatherSafetyEnabled,
  Value<bool> autoParkEnabled,
  Value<bool> autoResumeEnabled,
  Value<String> preferredProvider,
  Value<int> refreshIntervalSeconds,
  Value<DateTime> updatedAt,
});

class $$WeatherSettingsTableFilterComposer
    extends Composer<_$NightshadeDatabase, $WeatherSettingsTable> {
  $$WeatherSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get triggerDistanceKm => $composableBuilder(
      column: $table.triggerDistanceKm,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get cloudDensityThreshold => $composableBuilder(
      column: $table.cloudDensityThreshold,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get leadTimeMinutes => $composableBuilder(
      column: $table.leadTimeMinutes,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get weatherSafetyEnabled => $composableBuilder(
      column: $table.weatherSafetyEnabled,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get autoParkEnabled => $composableBuilder(
      column: $table.autoParkEnabled,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get autoResumeEnabled => $composableBuilder(
      column: $table.autoResumeEnabled,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get preferredProvider => $composableBuilder(
      column: $table.preferredProvider,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get refreshIntervalSeconds => $composableBuilder(
      column: $table.refreshIntervalSeconds,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$WeatherSettingsTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $WeatherSettingsTable> {
  $$WeatherSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get triggerDistanceKm => $composableBuilder(
      column: $table.triggerDistanceKm,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get cloudDensityThreshold => $composableBuilder(
      column: $table.cloudDensityThreshold,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get leadTimeMinutes => $composableBuilder(
      column: $table.leadTimeMinutes,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get weatherSafetyEnabled => $composableBuilder(
      column: $table.weatherSafetyEnabled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get autoParkEnabled => $composableBuilder(
      column: $table.autoParkEnabled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get autoResumeEnabled => $composableBuilder(
      column: $table.autoResumeEnabled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get preferredProvider => $composableBuilder(
      column: $table.preferredProvider,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get refreshIntervalSeconds => $composableBuilder(
      column: $table.refreshIntervalSeconds,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$WeatherSettingsTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $WeatherSettingsTable> {
  $$WeatherSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get triggerDistanceKm => $composableBuilder(
      column: $table.triggerDistanceKm, builder: (column) => column);

  GeneratedColumn<double> get cloudDensityThreshold => $composableBuilder(
      column: $table.cloudDensityThreshold, builder: (column) => column);

  GeneratedColumn<int> get leadTimeMinutes => $composableBuilder(
      column: $table.leadTimeMinutes, builder: (column) => column);

  GeneratedColumn<bool> get weatherSafetyEnabled => $composableBuilder(
      column: $table.weatherSafetyEnabled, builder: (column) => column);

  GeneratedColumn<bool> get autoParkEnabled => $composableBuilder(
      column: $table.autoParkEnabled, builder: (column) => column);

  GeneratedColumn<bool> get autoResumeEnabled => $composableBuilder(
      column: $table.autoResumeEnabled, builder: (column) => column);

  GeneratedColumn<String> get preferredProvider => $composableBuilder(
      column: $table.preferredProvider, builder: (column) => column);

  GeneratedColumn<int> get refreshIntervalSeconds => $composableBuilder(
      column: $table.refreshIntervalSeconds, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WeatherSettingsTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $WeatherSettingsTable,
    WeatherSettingRow,
    $$WeatherSettingsTableFilterComposer,
    $$WeatherSettingsTableOrderingComposer,
    $$WeatherSettingsTableAnnotationComposer,
    $$WeatherSettingsTableCreateCompanionBuilder,
    $$WeatherSettingsTableUpdateCompanionBuilder,
    (
      WeatherSettingRow,
      BaseReferences<_$NightshadeDatabase, $WeatherSettingsTable,
          WeatherSettingRow>
    ),
    WeatherSettingRow,
    PrefetchHooks Function()> {
  $$WeatherSettingsTableTableManager(
      _$NightshadeDatabase db, $WeatherSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WeatherSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WeatherSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WeatherSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<double> triggerDistanceKm = const Value.absent(),
            Value<double> cloudDensityThreshold = const Value.absent(),
            Value<int> leadTimeMinutes = const Value.absent(),
            Value<bool> weatherSafetyEnabled = const Value.absent(),
            Value<bool> autoParkEnabled = const Value.absent(),
            Value<bool> autoResumeEnabled = const Value.absent(),
            Value<String> preferredProvider = const Value.absent(),
            Value<int> refreshIntervalSeconds = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              WeatherSettingsCompanion(
            id: id,
            triggerDistanceKm: triggerDistanceKm,
            cloudDensityThreshold: cloudDensityThreshold,
            leadTimeMinutes: leadTimeMinutes,
            weatherSafetyEnabled: weatherSafetyEnabled,
            autoParkEnabled: autoParkEnabled,
            autoResumeEnabled: autoResumeEnabled,
            preferredProvider: preferredProvider,
            refreshIntervalSeconds: refreshIntervalSeconds,
            updatedAt: updatedAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<double> triggerDistanceKm = const Value.absent(),
            Value<double> cloudDensityThreshold = const Value.absent(),
            Value<int> leadTimeMinutes = const Value.absent(),
            Value<bool> weatherSafetyEnabled = const Value.absent(),
            Value<bool> autoParkEnabled = const Value.absent(),
            Value<bool> autoResumeEnabled = const Value.absent(),
            Value<String> preferredProvider = const Value.absent(),
            Value<int> refreshIntervalSeconds = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
          }) =>
              WeatherSettingsCompanion.insert(
            id: id,
            triggerDistanceKm: triggerDistanceKm,
            cloudDensityThreshold: cloudDensityThreshold,
            leadTimeMinutes: leadTimeMinutes,
            weatherSafetyEnabled: weatherSafetyEnabled,
            autoParkEnabled: autoParkEnabled,
            autoResumeEnabled: autoResumeEnabled,
            preferredProvider: preferredProvider,
            refreshIntervalSeconds: refreshIntervalSeconds,
            updatedAt: updatedAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WeatherSettingsTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $WeatherSettingsTable,
    WeatherSettingRow,
    $$WeatherSettingsTableFilterComposer,
    $$WeatherSettingsTableOrderingComposer,
    $$WeatherSettingsTableAnnotationComposer,
    $$WeatherSettingsTableCreateCompanionBuilder,
    $$WeatherSettingsTableUpdateCompanionBuilder,
    (
      WeatherSettingRow,
      BaseReferences<_$NightshadeDatabase, $WeatherSettingsTable,
          WeatherSettingRow>
    ),
    WeatherSettingRow,
    PrefetchHooks Function()>;
typedef $$FlatHistoryTableCreateCompanionBuilder = FlatHistoryCompanion
    Function({
  Value<int> id,
  Value<int?> equipmentProfileId,
  required String filterName,
  required double exposureTime,
  required double histogramTarget,
  required int actualAdu,
  Value<int?> panelBrightness,
  Value<double?> skyAduRate,
  Value<String?> twilightPhase,
  Value<int> gain,
  Value<int> binning,
  Value<DateTime> timestamp,
});
typedef $$FlatHistoryTableUpdateCompanionBuilder = FlatHistoryCompanion
    Function({
  Value<int> id,
  Value<int?> equipmentProfileId,
  Value<String> filterName,
  Value<double> exposureTime,
  Value<double> histogramTarget,
  Value<int> actualAdu,
  Value<int?> panelBrightness,
  Value<double?> skyAduRate,
  Value<String?> twilightPhase,
  Value<int> gain,
  Value<int> binning,
  Value<DateTime> timestamp,
});

class $$FlatHistoryTableFilterComposer
    extends Composer<_$NightshadeDatabase, $FlatHistoryTable> {
  $$FlatHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get equipmentProfileId => $composableBuilder(
      column: $table.equipmentProfileId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get filterName => $composableBuilder(
      column: $table.filterName, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get exposureTime => $composableBuilder(
      column: $table.exposureTime, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get histogramTarget => $composableBuilder(
      column: $table.histogramTarget,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get actualAdu => $composableBuilder(
      column: $table.actualAdu, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get panelBrightness => $composableBuilder(
      column: $table.panelBrightness,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get skyAduRate => $composableBuilder(
      column: $table.skyAduRate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get twilightPhase => $composableBuilder(
      column: $table.twilightPhase, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get gain => $composableBuilder(
      column: $table.gain, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get binning => $composableBuilder(
      column: $table.binning, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));
}

class $$FlatHistoryTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $FlatHistoryTable> {
  $$FlatHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get equipmentProfileId => $composableBuilder(
      column: $table.equipmentProfileId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get filterName => $composableBuilder(
      column: $table.filterName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get exposureTime => $composableBuilder(
      column: $table.exposureTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get histogramTarget => $composableBuilder(
      column: $table.histogramTarget,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get actualAdu => $composableBuilder(
      column: $table.actualAdu, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get panelBrightness => $composableBuilder(
      column: $table.panelBrightness,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get skyAduRate => $composableBuilder(
      column: $table.skyAduRate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get twilightPhase => $composableBuilder(
      column: $table.twilightPhase,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get gain => $composableBuilder(
      column: $table.gain, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get binning => $composableBuilder(
      column: $table.binning, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));
}

class $$FlatHistoryTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $FlatHistoryTable> {
  $$FlatHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get equipmentProfileId => $composableBuilder(
      column: $table.equipmentProfileId, builder: (column) => column);

  GeneratedColumn<String> get filterName => $composableBuilder(
      column: $table.filterName, builder: (column) => column);

  GeneratedColumn<double> get exposureTime => $composableBuilder(
      column: $table.exposureTime, builder: (column) => column);

  GeneratedColumn<double> get histogramTarget => $composableBuilder(
      column: $table.histogramTarget, builder: (column) => column);

  GeneratedColumn<int> get actualAdu =>
      $composableBuilder(column: $table.actualAdu, builder: (column) => column);

  GeneratedColumn<int> get panelBrightness => $composableBuilder(
      column: $table.panelBrightness, builder: (column) => column);

  GeneratedColumn<double> get skyAduRate => $composableBuilder(
      column: $table.skyAduRate, builder: (column) => column);

  GeneratedColumn<String> get twilightPhase => $composableBuilder(
      column: $table.twilightPhase, builder: (column) => column);

  GeneratedColumn<int> get gain =>
      $composableBuilder(column: $table.gain, builder: (column) => column);

  GeneratedColumn<int> get binning =>
      $composableBuilder(column: $table.binning, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);
}

class $$FlatHistoryTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $FlatHistoryTable,
    FlatHistoryEntry,
    $$FlatHistoryTableFilterComposer,
    $$FlatHistoryTableOrderingComposer,
    $$FlatHistoryTableAnnotationComposer,
    $$FlatHistoryTableCreateCompanionBuilder,
    $$FlatHistoryTableUpdateCompanionBuilder,
    (
      FlatHistoryEntry,
      BaseReferences<_$NightshadeDatabase, $FlatHistoryTable, FlatHistoryEntry>
    ),
    FlatHistoryEntry,
    PrefetchHooks Function()> {
  $$FlatHistoryTableTableManager(
      _$NightshadeDatabase db, $FlatHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FlatHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FlatHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FlatHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> equipmentProfileId = const Value.absent(),
            Value<String> filterName = const Value.absent(),
            Value<double> exposureTime = const Value.absent(),
            Value<double> histogramTarget = const Value.absent(),
            Value<int> actualAdu = const Value.absent(),
            Value<int?> panelBrightness = const Value.absent(),
            Value<double?> skyAduRate = const Value.absent(),
            Value<String?> twilightPhase = const Value.absent(),
            Value<int> gain = const Value.absent(),
            Value<int> binning = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
          }) =>
              FlatHistoryCompanion(
            id: id,
            equipmentProfileId: equipmentProfileId,
            filterName: filterName,
            exposureTime: exposureTime,
            histogramTarget: histogramTarget,
            actualAdu: actualAdu,
            panelBrightness: panelBrightness,
            skyAduRate: skyAduRate,
            twilightPhase: twilightPhase,
            gain: gain,
            binning: binning,
            timestamp: timestamp,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int?> equipmentProfileId = const Value.absent(),
            required String filterName,
            required double exposureTime,
            required double histogramTarget,
            required int actualAdu,
            Value<int?> panelBrightness = const Value.absent(),
            Value<double?> skyAduRate = const Value.absent(),
            Value<String?> twilightPhase = const Value.absent(),
            Value<int> gain = const Value.absent(),
            Value<int> binning = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
          }) =>
              FlatHistoryCompanion.insert(
            id: id,
            equipmentProfileId: equipmentProfileId,
            filterName: filterName,
            exposureTime: exposureTime,
            histogramTarget: histogramTarget,
            actualAdu: actualAdu,
            panelBrightness: panelBrightness,
            skyAduRate: skyAduRate,
            twilightPhase: twilightPhase,
            gain: gain,
            binning: binning,
            timestamp: timestamp,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$FlatHistoryTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $FlatHistoryTable,
    FlatHistoryEntry,
    $$FlatHistoryTableFilterComposer,
    $$FlatHistoryTableOrderingComposer,
    $$FlatHistoryTableAnnotationComposer,
    $$FlatHistoryTableCreateCompanionBuilder,
    $$FlatHistoryTableUpdateCompanionBuilder,
    (
      FlatHistoryEntry,
      BaseReferences<_$NightshadeDatabase, $FlatHistoryTable, FlatHistoryEntry>
    ),
    FlatHistoryEntry,
    PrefetchHooks Function()>;
typedef $$TutorialProgressTableCreateCompanionBuilder
    = TutorialProgressCompanion Function({
  Value<int> id,
  required String category,
  Value<int> lastStepIndex,
  Value<bool> completed,
  required DateTime startedAt,
  Value<DateTime?> completedAt,
  Value<bool> dismissed,
});
typedef $$TutorialProgressTableUpdateCompanionBuilder
    = TutorialProgressCompanion Function({
  Value<int> id,
  Value<String> category,
  Value<int> lastStepIndex,
  Value<bool> completed,
  Value<DateTime> startedAt,
  Value<DateTime?> completedAt,
  Value<bool> dismissed,
});

class $$TutorialProgressTableFilterComposer
    extends Composer<_$NightshadeDatabase, $TutorialProgressTable> {
  $$TutorialProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastStepIndex => $composableBuilder(
      column: $table.lastStepIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get dismissed => $composableBuilder(
      column: $table.dismissed, builder: (column) => ColumnFilters(column));
}

class $$TutorialProgressTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $TutorialProgressTable> {
  $$TutorialProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastStepIndex => $composableBuilder(
      column: $table.lastStepIndex,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get dismissed => $composableBuilder(
      column: $table.dismissed, builder: (column) => ColumnOrderings(column));
}

class $$TutorialProgressTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $TutorialProgressTable> {
  $$TutorialProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get lastStepIndex => $composableBuilder(
      column: $table.lastStepIndex, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<bool> get dismissed =>
      $composableBuilder(column: $table.dismissed, builder: (column) => column);
}

class $$TutorialProgressTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $TutorialProgressTable,
    TutorialProgressEntry,
    $$TutorialProgressTableFilterComposer,
    $$TutorialProgressTableOrderingComposer,
    $$TutorialProgressTableAnnotationComposer,
    $$TutorialProgressTableCreateCompanionBuilder,
    $$TutorialProgressTableUpdateCompanionBuilder,
    (
      TutorialProgressEntry,
      BaseReferences<_$NightshadeDatabase, $TutorialProgressTable,
          TutorialProgressEntry>
    ),
    TutorialProgressEntry,
    PrefetchHooks Function()> {
  $$TutorialProgressTableTableManager(
      _$NightshadeDatabase db, $TutorialProgressTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TutorialProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TutorialProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TutorialProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<int> lastStepIndex = const Value.absent(),
            Value<bool> completed = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime?> completedAt = const Value.absent(),
            Value<bool> dismissed = const Value.absent(),
          }) =>
              TutorialProgressCompanion(
            id: id,
            category: category,
            lastStepIndex: lastStepIndex,
            completed: completed,
            startedAt: startedAt,
            completedAt: completedAt,
            dismissed: dismissed,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String category,
            Value<int> lastStepIndex = const Value.absent(),
            Value<bool> completed = const Value.absent(),
            required DateTime startedAt,
            Value<DateTime?> completedAt = const Value.absent(),
            Value<bool> dismissed = const Value.absent(),
          }) =>
              TutorialProgressCompanion.insert(
            id: id,
            category: category,
            lastStepIndex: lastStepIndex,
            completed: completed,
            startedAt: startedAt,
            completedAt: completedAt,
            dismissed: dismissed,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$TutorialProgressTableProcessedTableManager = ProcessedTableManager<
    _$NightshadeDatabase,
    $TutorialProgressTable,
    TutorialProgressEntry,
    $$TutorialProgressTableFilterComposer,
    $$TutorialProgressTableOrderingComposer,
    $$TutorialProgressTableAnnotationComposer,
    $$TutorialProgressTableCreateCompanionBuilder,
    $$TutorialProgressTableUpdateCompanionBuilder,
    (
      TutorialProgressEntry,
      BaseReferences<_$NightshadeDatabase, $TutorialProgressTable,
          TutorialProgressEntry>
    ),
    TutorialProgressEntry,
    PrefetchHooks Function()>;
typedef $$PolarAlignmentHistoryTableCreateCompanionBuilder
    = PolarAlignmentHistoryCompanion Function({
  Value<int> id,
  Value<String?> equipmentProfileId,
  required double initialAzimuthError,
  required double initialAltitudeError,
  required double initialTotalError,
  required double finalAzimuthError,
  required double finalAltitudeError,
  required double finalTotalError,
  required DateTime startedAt,
  required DateTime completedAt,
  Value<bool> autoCompleted,
  Value<bool> isNorth,
  required String configJson,
});
typedef $$PolarAlignmentHistoryTableUpdateCompanionBuilder
    = PolarAlignmentHistoryCompanion Function({
  Value<int> id,
  Value<String?> equipmentProfileId,
  Value<double> initialAzimuthError,
  Value<double> initialAltitudeError,
  Value<double> initialTotalError,
  Value<double> finalAzimuthError,
  Value<double> finalAltitudeError,
  Value<double> finalTotalError,
  Value<DateTime> startedAt,
  Value<DateTime> completedAt,
  Value<bool> autoCompleted,
  Value<bool> isNorth,
  Value<String> configJson,
});

class $$PolarAlignmentHistoryTableFilterComposer
    extends Composer<_$NightshadeDatabase, $PolarAlignmentHistoryTable> {
  $$PolarAlignmentHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get equipmentProfileId => $composableBuilder(
      column: $table.equipmentProfileId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get initialAzimuthError => $composableBuilder(
      column: $table.initialAzimuthError,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get initialAltitudeError => $composableBuilder(
      column: $table.initialAltitudeError,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get initialTotalError => $composableBuilder(
      column: $table.initialTotalError,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get finalAzimuthError => $composableBuilder(
      column: $table.finalAzimuthError,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get finalAltitudeError => $composableBuilder(
      column: $table.finalAltitudeError,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get finalTotalError => $composableBuilder(
      column: $table.finalTotalError,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get autoCompleted => $composableBuilder(
      column: $table.autoCompleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isNorth => $composableBuilder(
      column: $table.isNorth, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get configJson => $composableBuilder(
      column: $table.configJson, builder: (column) => ColumnFilters(column));
}

class $$PolarAlignmentHistoryTableOrderingComposer
    extends Composer<_$NightshadeDatabase, $PolarAlignmentHistoryTable> {
  $$PolarAlignmentHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get equipmentProfileId => $composableBuilder(
      column: $table.equipmentProfileId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get initialAzimuthError => $composableBuilder(
      column: $table.initialAzimuthError,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get initialAltitudeError => $composableBuilder(
      column: $table.initialAltitudeError,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get initialTotalError => $composableBuilder(
      column: $table.initialTotalError,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get finalAzimuthError => $composableBuilder(
      column: $table.finalAzimuthError,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get finalAltitudeError => $composableBuilder(
      column: $table.finalAltitudeError,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get finalTotalError => $composableBuilder(
      column: $table.finalTotalError,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get autoCompleted => $composableBuilder(
      column: $table.autoCompleted,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isNorth => $composableBuilder(
      column: $table.isNorth, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get configJson => $composableBuilder(
      column: $table.configJson, builder: (column) => ColumnOrderings(column));
}

class $$PolarAlignmentHistoryTableAnnotationComposer
    extends Composer<_$NightshadeDatabase, $PolarAlignmentHistoryTable> {
  $$PolarAlignmentHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get equipmentProfileId => $composableBuilder(
      column: $table.equipmentProfileId, builder: (column) => column);

  GeneratedColumn<double> get initialAzimuthError => $composableBuilder(
      column: $table.initialAzimuthError, builder: (column) => column);

  GeneratedColumn<double> get initialAltitudeError => $composableBuilder(
      column: $table.initialAltitudeError, builder: (column) => column);

  GeneratedColumn<double> get initialTotalError => $composableBuilder(
      column: $table.initialTotalError, builder: (column) => column);

  GeneratedColumn<double> get finalAzimuthError => $composableBuilder(
      column: $table.finalAzimuthError, builder: (column) => column);

  GeneratedColumn<double> get finalAltitudeError => $composableBuilder(
      column: $table.finalAltitudeError, builder: (column) => column);

  GeneratedColumn<double> get finalTotalError => $composableBuilder(
      column: $table.finalTotalError, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
      column: $table.completedAt, builder: (column) => column);

  GeneratedColumn<bool> get autoCompleted => $composableBuilder(
      column: $table.autoCompleted, builder: (column) => column);

  GeneratedColumn<bool> get isNorth =>
      $composableBuilder(column: $table.isNorth, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
      column: $table.configJson, builder: (column) => column);
}

class $$PolarAlignmentHistoryTableTableManager extends RootTableManager<
    _$NightshadeDatabase,
    $PolarAlignmentHistoryTable,
    PolarAlignmentHistoryEntry,
    $$PolarAlignmentHistoryTableFilterComposer,
    $$PolarAlignmentHistoryTableOrderingComposer,
    $$PolarAlignmentHistoryTableAnnotationComposer,
    $$PolarAlignmentHistoryTableCreateCompanionBuilder,
    $$PolarAlignmentHistoryTableUpdateCompanionBuilder,
    (
      PolarAlignmentHistoryEntry,
      BaseReferences<_$NightshadeDatabase, $PolarAlignmentHistoryTable,
          PolarAlignmentHistoryEntry>
    ),
    PolarAlignmentHistoryEntry,
    PrefetchHooks Function()> {
  $$PolarAlignmentHistoryTableTableManager(
      _$NightshadeDatabase db, $PolarAlignmentHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PolarAlignmentHistoryTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$PolarAlignmentHistoryTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PolarAlignmentHistoryTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> equipmentProfileId = const Value.absent(),
            Value<double> initialAzimuthError = const Value.absent(),
            Value<double> initialAltitudeError = const Value.absent(),
            Value<double> initialTotalError = const Value.absent(),
            Value<double> finalAzimuthError = const Value.absent(),
            Value<double> finalAltitudeError = const Value.absent(),
            Value<double> finalTotalError = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<DateTime> completedAt = const Value.absent(),
            Value<bool> autoCompleted = const Value.absent(),
            Value<bool> isNorth = const Value.absent(),
            Value<String> configJson = const Value.absent(),
          }) =>
              PolarAlignmentHistoryCompanion(
            id: id,
            equipmentProfileId: equipmentProfileId,
            initialAzimuthError: initialAzimuthError,
            initialAltitudeError: initialAltitudeError,
            initialTotalError: initialTotalError,
            finalAzimuthError: finalAzimuthError,
            finalAltitudeError: finalAltitudeError,
            finalTotalError: finalTotalError,
            startedAt: startedAt,
            completedAt: completedAt,
            autoCompleted: autoCompleted,
            isNorth: isNorth,
            configJson: configJson,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String?> equipmentProfileId = const Value.absent(),
            required double initialAzimuthError,
            required double initialAltitudeError,
            required double initialTotalError,
            required double finalAzimuthError,
            required double finalAltitudeError,
            required double finalTotalError,
            required DateTime startedAt,
            required DateTime completedAt,
            Value<bool> autoCompleted = const Value.absent(),
            Value<bool> isNorth = const Value.absent(),
            required String configJson,
          }) =>
              PolarAlignmentHistoryCompanion.insert(
            id: id,
            equipmentProfileId: equipmentProfileId,
            initialAzimuthError: initialAzimuthError,
            initialAltitudeError: initialAltitudeError,
            initialTotalError: initialTotalError,
            finalAzimuthError: finalAzimuthError,
            finalAltitudeError: finalAltitudeError,
            finalTotalError: finalTotalError,
            startedAt: startedAt,
            completedAt: completedAt,
            autoCompleted: autoCompleted,
            isNorth: isNorth,
            configJson: configJson,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PolarAlignmentHistoryTableProcessedTableManager
    = ProcessedTableManager<
        _$NightshadeDatabase,
        $PolarAlignmentHistoryTable,
        PolarAlignmentHistoryEntry,
        $$PolarAlignmentHistoryTableFilterComposer,
        $$PolarAlignmentHistoryTableOrderingComposer,
        $$PolarAlignmentHistoryTableAnnotationComposer,
        $$PolarAlignmentHistoryTableCreateCompanionBuilder,
        $$PolarAlignmentHistoryTableUpdateCompanionBuilder,
        (
          PolarAlignmentHistoryEntry,
          BaseReferences<_$NightshadeDatabase, $PolarAlignmentHistoryTable,
              PolarAlignmentHistoryEntry>
        ),
        PolarAlignmentHistoryEntry,
        PrefetchHooks Function()>;

class $NightshadeDatabaseManager {
  final _$NightshadeDatabase _db;
  $NightshadeDatabaseManager(this._db);
  $$EquipmentProfilesTableTableManager get equipmentProfiles =>
      $$EquipmentProfilesTableTableManager(_db, _db.equipmentProfiles);
  $$TargetsTableTableManager get targets =>
      $$TargetsTableTableManager(_db, _db.targets);
  $$SequencesTableTableManager get sequences =>
      $$SequencesTableTableManager(_db, _db.sequences);
  $$ImagingSessionsTableTableManager get imagingSessions =>
      $$ImagingSessionsTableTableManager(_db, _db.imagingSessions);
  $$SequenceNodesTableTableManager get sequenceNodes =>
      $$SequenceNodesTableTableManager(_db, _db.sequenceNodes);
  $$SequenceCheckpointsTableTableManager get sequenceCheckpoints =>
      $$SequenceCheckpointsTableTableManager(_db, _db.sequenceCheckpoints);
  $$CapturedImagesTableTableManager get capturedImages =>
      $$CapturedImagesTableTableManager(_db, _db.capturedImages);
  $$ImageMetadataTableTableManager get imageMetadata =>
      $$ImageMetadataTableTableManager(_db, _db.imageMetadata);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$WeatherSettingsTableTableManager get weatherSettings =>
      $$WeatherSettingsTableTableManager(_db, _db.weatherSettings);
  $$FlatHistoryTableTableManager get flatHistory =>
      $$FlatHistoryTableTableManager(_db, _db.flatHistory);
  $$TutorialProgressTableTableManager get tutorialProgress =>
      $$TutorialProgressTableTableManager(_db, _db.tutorialProgress);
  $$PolarAlignmentHistoryTableTableManager get polarAlignmentHistory =>
      $$PolarAlignmentHistoryTableTableManager(_db, _db.polarAlignmentHistory);
}
