part of '../backup_service.dart';

extension _BackupSequenceCodec on BackupService {
  Map<String, dynamic> _sequenceToJson(Sequence sequence) {
    return SequenceFileService().sequenceToMap(sequence);
  }

  // =========================================================================
  // Private import methods
  // =========================================================================

  Future<int> _importSettings(
    Map<String, dynamic> settingsMap, {
    bool replace = false,
  }) async {
    final settingsDao = SettingsDao(database);
    int count = 0;

    for (final entry in settingsMap.entries) {
      await settingsDao.setSetting(entry.key, entry.value?.toString() ?? '');
      count++;
    }

    return count;
  }

  Future<int> _importProfiles(
    List<dynamic> profilesList, {
    bool replace = false,
  }) async {
    int count = 0;
    final hasExplicitDefault = profilesList.any(
      (raw) => raw is Map && raw['isDefault'] == true,
    );
    var legacyDefaultAssigned = false;

    for (final profileJson in profilesList) {
      final profile = profileJson as Map<String, dynamic>;
      final isActive = profile['isActive'] as bool? ?? false;
      final legacyDefault =
          !hasExplicitDefault && !legacyDefaultAssigned && isActive;
      if (legacyDefault) {
        legacyDefaultAssigned = true;
      }

      await database
          .into(database.equipmentProfiles)
          .insert(
            EquipmentProfilesCompanion.insert(
              id: profile['id'] == null
                  ? const Value.absent()
                  : Value(_intOrDefault(profile['id'], 0)),
              name: profile['name'] as String,
              description: Value(_stringOrNull(profile['description'])),
              isActive: Value(isActive),
              isDefault: Value(profile['isDefault'] as bool? ?? legacyDefault),
              cameraId: Value(_stringOrNull(profile['cameraId'])),
              mountId: Value(_stringOrNull(profile['mountId'])),
              focuserId: Value(_stringOrNull(profile['focuserId'])),
              filterWheelId: Value(_stringOrNull(profile['filterWheelId'])),
              guiderId: Value(_stringOrNull(profile['guiderId'])),
              rotatorId: Value(_stringOrNull(profile['rotatorId'])),
              domeId: Value(_stringOrNull(profile['domeId'])),
              weatherId: Value(_stringOrNull(profile['weatherId'])),
              safetyMonitorId: Value(_stringOrNull(profile['safetyMonitorId'])),
              switchId: Value(_stringOrNull(profile['switchId'])),
              coverCalibratorId: Value(
                _stringOrNull(profile['coverCalibratorId']),
              ),
              focalLength: Value(_doubleOrDefault(profile['focalLength'], 0.0)),
              aperture: Value(_doubleOrDefault(profile['aperture'], 0.0)),
              focalRatio: Value(_doubleOrNull(profile['focalRatio'])),
              defaultGain: Value(_intOrNull(profile['defaultGain'])),
              defaultOffset: Value(_intOrNull(profile['defaultOffset'])),
              defaultBinX: Value(_intOrDefault(profile['defaultBinX'], 1)),
              defaultBinY: Value(_intOrDefault(profile['defaultBinY'], 1)),
              defaultCoolingTemp: Value(
                _doubleOrNull(profile['defaultCoolingTemp']),
              ),
              coolOnConnect: Value(profile['coolOnConnect'] as bool? ?? false),
              defaultCenteringExposure: Value(
                _doubleOrNull(profile['defaultCenteringExposure']),
              ),
              filterNames: Value(_stringOrNull(profile['filterNames'])),
              filterFocusOffsets: Value(
                _stringOrNull(profile['filterFocusOffsets']),
              ),
              meridianFlipOverrides: Value(
                _stringOrNull(profile['meridianFlipOverrides']),
              ),
              cameraName: Value(_stringOrNull(profile['cameraName'])),
              mountName: Value(_stringOrNull(profile['mountName'])),
              focuserName: Value(_stringOrNull(profile['focuserName'])),
              filterWheelName: Value(_stringOrNull(profile['filterWheelName'])),
              guiderName: Value(_stringOrNull(profile['guiderName'])),
              rotatorName: Value(_stringOrNull(profile['rotatorName'])),
              safetyMonitorName: Value(
                _stringOrNull(profile['safetyMonitorName']),
              ),
              switchName: Value(_stringOrNull(profile['switchName'])),
              telescopeName: Value(_stringOrNull(profile['telescopeName'])),
              telescopeFocalLength: Value(
                _doubleOrNull(profile['telescopeFocalLength']),
              ),
              telescopeAperture: Value(
                _doubleOrNull(profile['telescopeAperture']),
              ),
              profileIcon: Value(_stringOrNull(profile['profileIcon'])),
              profileColor: Value(_intOrNull(profile['profileColor'])),
              sortOrder: Value(_intOrDefault(profile['sortOrder'], 0)),
              createdAt: _dateTimeValue(profile['createdAt']),
              updatedAt: _dateTimeValue(profile['updatedAt']),
            ),
            mode: replace ? InsertMode.replace : InsertMode.insertOrIgnore,
          );
      count++;
    }

    return count;
  }

  Future<int> _importTargets(
    List<dynamic> targetsList, {
    bool replace = false,
  }) async {
    int count = 0;

    for (final targetJson in targetsList) {
      final target = targetJson as Map<String, dynamic>;

      await database
          .into(database.targets)
          .insert(
            TargetsCompanion.insert(
              name: target['name'] as String,
              catalogId: Value(_stringOrNull(target['catalogId'])),
              ra: _doubleOrDefault(target['ra'], 0.0),
              dec: _doubleOrDefault(target['dec'], 0.0),
              constellation: Value(_stringOrNull(target['constellation'])),
              objectType: Value(_stringOrNull(target['objectType'])),
              magnitude: Value(_doubleOrNull(target['magnitude'])),
              sizeArcmin: Value(_doubleOrNull(target['sizeArcmin'])),
              notes: Value(_stringOrNull(target['notes'])),
              isFavorite: Value(target['isFavorite'] as bool? ?? false),
              priority: Value(_intOrDefault(target['priority'], 0)),
            ),
            mode: replace ? InsertMode.replace : InsertMode.insertOrIgnore,
          );
      count++;
    }

    return count;
  }

  Sequence? _jsonToSequence(Map<String, dynamic> json) {
    try {
      // parseFromMap mutates the supplied map while stamping its schema
      // version. Restore validation should remain side-effect free, so decode
      // a shallow copy of the backup entry.
      return SequenceFileService().parseFromMap(Map<String, dynamic>.of(json));
    } catch (e) {
      _logger.debug('Failed to parse sequence: $e');
      return null;
    }
  }
}
