import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/settings.dart';

part 'settings_dao.g.dart';

@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<NightshadeDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(NightshadeDatabase db) : super(db);

  /// Get a setting by key
  Future<String?> getSetting(String key) async {
    final result = await (select(appSettings)..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return result?.value;
  }

  /// Watch a setting by key
  Stream<String?> watchSetting(String key) {
    return (select(appSettings)..where((s) => s.key.equals(key)))
        .watchSingleOrNull()
        .map((s) => s?.value);
  }

  /// Get all settings
  Future<Map<String, String>> getAllSettings() async {
    final settings = await select(appSettings).get();
    return {for (var s in settings) s.key: s.value};
  }

  /// Watch all settings
  Stream<Map<String, String>> watchAllSettings() {
    return select(appSettings).watch().map((settings) {
      return {for (var s in settings) s.key: s.value};
    });
  }

  /// Set a setting
  Future<void> setSetting(String key, String value) async {
    await into(appSettings).insert(
      AppSettingsCompanion.insert(
        key: key,
        value: value,
      ),
      onConflict: DoUpdate(
        (old) => AppSettingsCompanion(
          value: Value(value),
          updatedAt: Value(DateTime.now()),
        ),
        target: <Column<Object>>[appSettings.key],
      ),
    );
  }

  /// Set multiple settings at once
  Future<void> setSettings(Map<String, String> settings) async {
    await batch((batch) {
      for (final entry in settings.entries) {
        batch.insert(
          appSettings,
          AppSettingsCompanion.insert(key: entry.key, value: entry.value),
          onConflict: DoUpdate(
            (old) => AppSettingsCompanion(
              value: Value(entry.value),
              updatedAt: Value(DateTime.now()),
            ),
            target: [appSettings.key],
          ),
        );
      }
    });
  }

  /// Delete a setting
  Future<int> deleteSetting(String key) {
    return (delete(appSettings)..where((s) => s.key.equals(key))).go();
  }

  // Typed getters for common settings

  Future<String> getTheme() async {
    return await getSetting('theme') ?? 'dark';
  }

  Future<void> setTheme(String theme) => setSetting('theme', theme);

  Future<String> getDefaultImageDirectory() async {
    return await getSetting('default_image_directory') ?? '';
  }

  Future<void> setDefaultImageDirectory(String path) =>
      setSetting('default_image_directory', path);

  Future<bool> getAutoConnectEquipment() async {
    final value = await getSetting('auto_connect_equipment');
    return value == 'true';
  }

  Future<void> setAutoConnectEquipment(bool enabled) =>
      setSetting('auto_connect_equipment', enabled.toString());

  Future<double> getObserverLatitude() async {
    final value = await getSetting('observer_latitude');
    return double.tryParse(value ?? '0') ?? 0.0;
  }

  Future<void> setObserverLatitude(double lat) =>
      setSetting('observer_latitude', lat.toString());

  Future<double> getObserverLongitude() async {
    final value = await getSetting('observer_longitude');
    return double.tryParse(value ?? '0') ?? 0.0;
  }

  Future<void> setObserverLongitude(double lon) =>
      setSetting('observer_longitude', lon.toString());

  Future<double> getObserverElevation() async {
    final value = await getSetting('observer_elevation');
    return double.tryParse(value ?? '0') ?? 0.0;
  }

  Future<void> setObserverElevation(double elevation) =>
      setSetting('observer_elevation', elevation.toString());

  // Auto-stretch settings
  static const String _autoStretchKey = 'auto_stretch_settings';

  /// Get auto-stretch settings as JSON string
  Future<String?> getAutoStretchSettings() async {
    return await getSetting(_autoStretchKey);
  }

  /// Watch auto-stretch settings
  Stream<String?> watchAutoStretchSettings() {
    return watchSetting(_autoStretchKey);
  }

  /// Save auto-stretch settings as JSON string
  Future<void> setAutoStretchSettings(String jsonSettings) =>
      setSetting(_autoStretchKey, jsonSettings);
}


