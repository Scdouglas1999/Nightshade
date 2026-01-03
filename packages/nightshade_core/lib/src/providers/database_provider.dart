import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart' as db;
import '../database/daos/equipment_profiles_dao.dart';
import '../database/daos/targets_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/daos/images_dao.dart';
import '../database/daos/sequences_dao.dart';
import '../database/daos/settings_dao.dart';

/// Global database instance provider
final databaseProvider = Provider<db.NightshadeDatabase>((ref) {
  final database = db.NightshadeDatabase();
  ref.onDispose(() => database.close());
  return database;
});

/// Equipment profiles DAO provider
final equipmentProfilesDaoProvider = Provider<EquipmentProfilesDao>((ref) {
  return EquipmentProfilesDao(ref.watch(databaseProvider));
});

/// Targets DAO provider
final targetsDaoProvider = Provider<TargetsDao>((ref) {
  return TargetsDao(ref.watch(databaseProvider));
});

/// Sessions DAO provider
final sessionsDaoProvider = Provider<SessionsDao>((ref) {
  return SessionsDao(ref.watch(databaseProvider));
});

/// Images DAO provider
final imagesDaoProvider = Provider<ImagesDao>((ref) {
  return ImagesDao(ref.watch(databaseProvider));
});

/// Sequences DAO provider
final sequencesDaoProvider = Provider<SequencesDao>((ref) {
  return SequencesDao(ref.watch(databaseProvider));
});

/// Settings DAO provider
final settingsDaoProvider = Provider<SettingsDao>((ref) {
  return SettingsDao(ref.watch(databaseProvider));
});

// ============================================================================
// Convenience providers for watching data
// Note: These use the database entity types (prefixed with db.)
// ============================================================================

/// Watch all equipment profiles
final allProfilesProvider = StreamProvider<List<db.EquipmentProfile>>((ref) {
  return ref.watch(equipmentProfilesDaoProvider).watchAllProfiles();
});

/// Watch the active equipment profile
final activeProfileProvider = StreamProvider<db.EquipmentProfile?>((ref) {
  return ref.watch(equipmentProfilesDaoProvider).watchActiveProfile();
});

/// Watch all targets (database entities)
final allDbTargetsProvider = StreamProvider<List<db.Target>>((ref) {
  return ref.watch(targetsDaoProvider).watchAllTargets();
});

/// Watch favorite targets (database entities)
final favoriteDbTargetsProvider = StreamProvider<List<db.Target>>((ref) {
  return ref.watch(targetsDaoProvider).watchFavoriteTargets();
});

/// Watch all sequences (database entities)
final allDbSequencesProvider = StreamProvider<List<db.Sequence>>((ref) {
  return ref.watch(sequencesDaoProvider).watchAllSequences();
});

/// Watch all sequence templates (database entities)
final allDbTemplatesProvider = StreamProvider<List<db.Sequence>>((ref) {
  return ref.watch(sequencesDaoProvider).watchAllTemplates();
});

/// Watch all imaging sessions
final allSessionsProvider = StreamProvider<List<db.ImagingSession>>((ref) {
  return ref.watch(sessionsDaoProvider).watchAllSessions();
});

/// Watch all captured images (database entities)
final allDbImagesProvider = StreamProvider<List<db.CapturedImage>>((ref) {
  return ref.watch(imagesDaoProvider).watchAllImages();
});

/// Watch all settings as a map
final allSettingsProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(settingsDaoProvider).watchAllSettings();
});
