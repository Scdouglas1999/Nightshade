import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/weather_settings.dart';

part 'weather_settings_dao.g.dart';

@DriftAccessor(tables: [WeatherSettings])
class WeatherSettingsDao extends DatabaseAccessor<NightshadeDatabase>
    with _$WeatherSettingsDaoMixin {
  WeatherSettingsDao(NightshadeDatabase db) : super(db);

  /// Get the single settings row (first row or null)
  Future<WeatherSettingRow?> getSettings() async {
    return await (select(weatherSettings)..limit(1)).getSingleOrNull();
  }

  /// Get existing settings or create with defaults
  Future<WeatherSettingRow> getOrCreateSettings() async {
    final existing = await getSettings();
    if (existing != null) {
      return existing;
    }

    // Insert default settings
    final id = await into(weatherSettings).insert(
      WeatherSettingsCompanion.insert(),
    );

    // Return the newly created row
    return (await (select(weatherSettings)..where((s) => s.id.equals(id)))
        .getSingle());
  }

  /// Update specific fields
  Future<void> updateSettings({
    double? triggerDistanceKm,
    double? cloudDensityThreshold,
    int? leadTimeMinutes,
    bool? weatherSafetyEnabled,
    bool? autoParkEnabled,
    bool? autoResumeEnabled,
    String? preferredProvider,
    int? refreshIntervalSeconds,
  }) async {
    // Ensure at least one row exists
    final existing = await getOrCreateSettings();

    // Update the row by ID
    await (update(weatherSettings)..where((s) => s.id.equals(existing.id))).write(
      WeatherSettingsCompanion(
        triggerDistanceKm: triggerDistanceKm != null
            ? Value(triggerDistanceKm)
            : const Value.absent(),
        cloudDensityThreshold: cloudDensityThreshold != null
            ? Value(cloudDensityThreshold)
            : const Value.absent(),
        leadTimeMinutes:
            leadTimeMinutes != null ? Value(leadTimeMinutes) : const Value.absent(),
        weatherSafetyEnabled: weatherSafetyEnabled != null
            ? Value(weatherSafetyEnabled)
            : const Value.absent(),
        autoParkEnabled:
            autoParkEnabled != null ? Value(autoParkEnabled) : const Value.absent(),
        autoResumeEnabled: autoResumeEnabled != null
            ? Value(autoResumeEnabled)
            : const Value.absent(),
        preferredProvider: preferredProvider != null
            ? Value(preferredProvider)
            : const Value.absent(),
        refreshIntervalSeconds: refreshIntervalSeconds != null
            ? Value(refreshIntervalSeconds)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Reset to defaults - delete all rows and insert fresh default
  Future<void> resetToDefaults() async {
    await delete(weatherSettings).go();
    await into(weatherSettings).insert(
      WeatherSettingsCompanion.insert(),
    );
  }

  /// Stream for Riverpod to watch
  Stream<WeatherSettingRow?> watchSettings() {
    return (select(weatherSettings)..limit(1)).watchSingleOrNull();
  }
}
