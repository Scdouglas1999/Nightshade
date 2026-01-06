import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/equipment_profiles.dart';

part 'equipment_profiles_dao.g.dart';

@DriftAccessor(tables: [EquipmentProfiles])
class EquipmentProfilesDao extends DatabaseAccessor<NightshadeDatabase>
    with _$EquipmentProfilesDaoMixin {
  EquipmentProfilesDao(NightshadeDatabase db) : super(db);

  /// Get all equipment profiles
  Future<List<EquipmentProfile>> getAllProfiles() => select(equipmentProfiles).get();

  /// Watch all equipment profiles
  Stream<List<EquipmentProfile>> watchAllProfiles() => select(equipmentProfiles).watch();

  /// Get the active profile
  Future<EquipmentProfile?> getActiveProfile() {
    return (select(equipmentProfiles)..where((p) => p.isActive.equals(true)))
        .getSingleOrNull();
  }

  /// Watch the active profile
  Stream<EquipmentProfile?> watchActiveProfile() {
    return (select(equipmentProfiles)..where((p) => p.isActive.equals(true)))
        .watchSingleOrNull();
  }

  /// Get a profile by ID
  Future<EquipmentProfile?> getProfileById(int id) {
    return (select(equipmentProfiles)..where((p) => p.id.equals(id)))
        .getSingleOrNull();
  }

  /// Create a new profile
  Future<int> createProfile(EquipmentProfilesCompanion profile) {
    return into(equipmentProfiles).insert(profile);
  }

  /// Update a profile
  Future<bool> updateProfile(EquipmentProfile profile) {
    return update(equipmentProfiles).replace(profile);
  }

  /// Delete a profile
  Future<int> deleteProfile(int id) {
    return (delete(equipmentProfiles)..where((p) => p.id.equals(id))).go();
  }

  /// Set a profile as active (and deactivate others)
  Future<void> setActiveProfile(int profileId) async {
    await transaction(() async {
      // Deactivate all profiles
      await update(equipmentProfiles).write(
        const EquipmentProfilesCompanion(isActive: Value(false)),
      );
      // Activate the selected profile
      await (update(equipmentProfiles)..where((p) => p.id.equals(profileId)))
          .write(const EquipmentProfilesCompanion(isActive: Value(true)));
    });
  }

  /// Duplicate a profile
  Future<int> duplicateProfile(int sourceId, String newName) async {
    final source = await getProfileById(sourceId);
    if (source == null) {
      throw Exception('Profile not found');
    }

    return into(equipmentProfiles).insert(
      EquipmentProfilesCompanion.insert(
        name: newName,
        description: Value(source.description),
        cameraId: Value(source.cameraId),
        mountId: Value(source.mountId),
        focuserId: Value(source.focuserId),
        filterWheelId: Value(source.filterWheelId),
        guiderId: Value(source.guiderId),
        rotatorId: Value(source.rotatorId),
        domeId: Value(source.domeId),
        weatherId: Value(source.weatherId),
        coverCalibratorId: Value(source.coverCalibratorId),
        focalLength: Value(source.focalLength),
        aperture: Value(source.aperture),
        focalRatio: Value(source.focalRatio),
        defaultGain: Value(source.defaultGain),
        defaultOffset: Value(source.defaultOffset),
        defaultBinX: Value(source.defaultBinX),
        defaultBinY: Value(source.defaultBinY),
        defaultCoolingTemp: Value(source.defaultCoolingTemp),
        filterNames: Value(source.filterNames),
        filterFocusOffsets: Value(source.filterFocusOffsets),
        meridianFlipOverrides: Value(source.meridianFlipOverrides),
      ),
    );
  }
}





