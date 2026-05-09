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
    return (select(weatherSettings)
          ..orderBy([(s) => OrderingTerm.asc(s.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Get existing settings or create with defaults
  Future<WeatherSettingRow> getOrCreateSettings() async {
    return transaction(() async {
      final rows = await (select(weatherSettings)
            ..orderBy([(s) => OrderingTerm.asc(s.id)]))
          .get();

      if (rows.isEmpty) {
        await into(weatherSettings).insert(
          WeatherSettingsCompanion.insert(id: const Value(1)),
        );
        return (await (select(weatherSettings)..where((s) => s.id.equals(1)))
            .getSingle());
      }

      final primary = rows.first;
      if (rows.length > 1) {
        final duplicateIds = rows.skip(1).map((row) => row.id).toList();
        await (delete(weatherSettings)..where((s) => s.id.isIn(duplicateIds)))
            .go();
      }

      return primary;
    });
  }

  /// Update specific fields
  Future<void> updateSettings({
    double? triggerDistanceKm,
    double? cloudDensityThreshold,
    int? leadTimeMinutes,
    bool? weatherSafetyEnabled,
    double? maxHumidityPercent,
    double? maxWindSpeedKph,
    double? maxCloudCoverPercent,
    bool? autoParkEnabled,
    bool? autoResumeEnabled,
    String? preferredProvider,
    int? refreshIntervalSeconds,
  }) async {
    // Ensure at least one row exists
    final existing = await getOrCreateSettings();

    // Update the row by ID
    await (update(weatherSettings)..where((s) => s.id.equals(existing.id)))
        .write(
      WeatherSettingsCompanion(
        triggerDistanceKm: triggerDistanceKm != null
            ? Value(triggerDistanceKm)
            : const Value.absent(),
        cloudDensityThreshold: cloudDensityThreshold != null
            ? Value(cloudDensityThreshold)
            : const Value.absent(),
        leadTimeMinutes: leadTimeMinutes != null
            ? Value(leadTimeMinutes)
            : const Value.absent(),
        weatherSafetyEnabled: weatherSafetyEnabled != null
            ? Value(weatherSafetyEnabled)
            : const Value.absent(),
        maxHumidityPercent: maxHumidityPercent != null
            ? Value(maxHumidityPercent)
            : const Value.absent(),
        maxWindSpeedKph: maxWindSpeedKph != null
            ? Value(maxWindSpeedKph)
            : const Value.absent(),
        maxCloudCoverPercent: maxCloudCoverPercent != null
            ? Value(maxCloudCoverPercent)
            : const Value.absent(),
        autoParkEnabled: autoParkEnabled != null
            ? Value(autoParkEnabled)
            : const Value.absent(),
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
    await transaction(() async {
      await delete(weatherSettings).go();
      await into(weatherSettings).insert(
        WeatherSettingsCompanion.insert(id: const Value(1)),
      );
    });
  }

  /// Stream for Riverpod to watch
  Stream<WeatherSettingRow?> watchSettings() {
    return (select(weatherSettings)..limit(1)).watchSingleOrNull();
  }
}
