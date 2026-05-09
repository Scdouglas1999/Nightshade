import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';

import '../fixtures/synthetic_old_profile_fixtures.dart';

void main() {
  test('migrates captured_images to include quality_score', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('nightshade_migration_test_');
    final dbFile = File('${tempDir.path}/nightshade.db');

    final setupDb = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
    try {
      await setupDb.customStatement('PRAGMA foreign_keys = OFF');
      await setupDb.customStatement('DROP TABLE IF EXISTS captured_images');
      await setupDb.customStatement('''
CREATE TABLE captured_images (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  file_path TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_format TEXT NOT NULL DEFAULT 'fits',
  file_size INTEGER,
  session_id INTEGER REFERENCES imaging_sessions(id) ON DELETE CASCADE,
  target_id INTEGER REFERENCES targets(id) ON DELETE SET NULL,
  frame_type TEXT NOT NULL DEFAULT 'light',
  exposure_duration REAL NOT NULL,
  gain INTEGER,
  offset INTEGER,
  bin_x INTEGER NOT NULL DEFAULT 1,
  bin_y INTEGER NOT NULL DEFAULT 1,
  filter TEXT,
  sensor_temp REAL,
  cooler_power REAL,
  hfr REAL,
  star_count INTEGER,
  background REAL,
  noise REAL,
  guiding_rms_ra REAL,
  guiding_rms_dec REAL,
  guiding_rms_total REAL,
  mount_ra REAL,
  mount_dec REAL,
  mount_altitude REAL,
  mount_azimuth REAL,
  pier_side TEXT,
  focuser_position INTEGER,
  focuser_temp REAL,
  rotator_angle REAL,
  is_plate_solved INTEGER NOT NULL DEFAULT 0,
  solved_ra REAL,
  solved_dec REAL,
  solved_rotation REAL,
  solved_pixel_scale REAL,
  captured_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
  is_accepted INTEGER NOT NULL DEFAULT 1,
  rejection_reason TEXT
)
''');
      await setupDb.customStatement('PRAGMA user_version = 9');
    } finally {
      await setupDb.close();
    }

    final db = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
    try {
      final columns =
          await db.customSelect("PRAGMA table_info('captured_images')").get();
      final hasQualityScore =
          columns.any((row) => row.data['name'] == 'quality_score');

      expect(
        hasQualityScore,
        isTrue,
        reason: 'captured_images should include quality_score after migration',
      );
    } finally {
      await db.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('creates science quality metric tables in latest schema', () async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    try {
      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      final tableNames =
          tables.map((row) => row.data['name']?.toString() ?? '').toSet();

      expect(tableNames.contains('science_frame_quality_metrics'), isTrue);
      expect(tableNames.contains('science_tile_metrics'), isTrue);

      final settings = await db.settingsDao.getAllSettings();
      expect(settings['science.feature.frame_quality_maps'], equals('true'));
      expect(settings['science.feature.surface3d'], equals('true'));
      expect(settings['science.overlay.live_grid_rows'], equals('12'));
      expect(settings['science.overlay.live_grid_cols'], equals('16'));
    } finally {
      await db.close();
    }
  });

  test('latest schema keeps imaging sessions when sequences are deleted',
      () async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    try {
      final sequenceId = await db.into(db.sequences).insert(
            SequencesCompanion.insert(name: 'Sequence A'),
          );
      final sessionId = await db.into(db.imagingSessions).insert(
            ImagingSessionsCompanion.insert(
              startTime: DateTime.now(),
              status: const Value('active'),
              sequenceId: Value(sequenceId),
            ),
          );

      await (db.delete(db.sequences)..where((t) => t.id.equals(sequenceId)))
          .go();

      final session = await (db.select(db.imagingSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingle();
      expect(session.sequenceId, equals(null));
    } finally {
      await db.close();
    }
  });

  test('latest schema cascades polar history on profile delete', () async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    try {
      final profileId = await db.into(db.equipmentProfiles).insert(
            EquipmentProfilesCompanion.insert(name: 'Profile A'),
          );

      await db.into(db.polarAlignmentHistory).insert(
            PolarAlignmentHistoryCompanion.insert(
              equipmentProfileId: Value(profileId),
              initialAzimuthError: 10,
              initialAltitudeError: 11,
              initialTotalError: 15,
              finalAzimuthError: 1,
              finalAltitudeError: 2,
              finalTotalError: 3,
              startedAt: DateTime.now(),
              completedAt: DateTime.now(),
              configJson: '{}',
            ),
          );

      await (db.delete(db.equipmentProfiles)
            ..where((t) => t.id.equals(profileId)))
          .go();

      final remaining = await db.select(db.polarAlignmentHistory).get();
      expect(remaining, isEmpty);
    } finally {
      await db.close();
    }
  });

  test('latest schema enforces single science config row per session',
      () async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    try {
      final sessionId = await db.into(db.imagingSessions).insert(
            ImagingSessionsCompanion.insert(
              startTime: DateTime.now(),
            ),
          );

      await db.into(db.scienceSessionConfig).insert(
            ScienceSessionConfigCompanion.insert(sessionId: Value(sessionId)),
          );

      await expectLater(
        db.into(db.scienceSessionConfig).insert(
              ScienceSessionConfigCompanion.insert(sessionId: Value(sessionId)),
            ),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      await db.close();
    }
  });

  test('latest schema enforces at most one active equipment profile', () async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    try {
      await db.into(db.equipmentProfiles).insert(
            EquipmentProfilesCompanion.insert(
              name: 'Profile A',
              isActive: Value(true),
            ),
          );

      await expectLater(
        db.into(db.equipmentProfiles).insert(
              EquipmentProfilesCompanion.insert(
                name: 'Profile B',
                isActive: Value(true),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      await db.close();
    }
  });

  test('fresh and upgraded databases converge on the same default settings',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('nightshade_settings_migration_');
    final dbFile = File('${tempDir.path}/nightshade.db');

    final setupDb = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
    try {
      await setupDb.customStatement('DELETE FROM app_settings');
      await setupDb.customStatement('PRAGMA user_version = 21');
    } finally {
      await setupDb.close();
    }

    final upgradedDb = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
    final freshDb = NightshadeDatabase.forTesting(NativeDatabase.memory());
    try {
      final upgradedSettings = await upgradedDb.settingsDao.getAllSettings();
      final freshSettings = await freshDb.settingsDao.getAllSettings();

      for (final key in const [
        'theme',
        'auto_connect_equipment',
        'notifications_enabled',
        'af_filter_settings',
        'science.overlay.live_grid_rows',
        'dark_library.temp_tolerance',
      ]) {
        expect(upgradedSettings[key], equals(freshSettings[key]));
      }

      final upgradedTables = await upgradedDb
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      final upgradedTableNames = upgradedTables
          .map((row) => row.data['name']?.toString() ?? '')
          .toSet();
      for (final tableName in const [
        'observation_logs',
        'observing_lists',
        'sequence_runs',
      ]) {
        expect(upgradedTableNames.contains(tableName), isTrue);
      }

      final targetsColumns =
          await upgradedDb.customSelect("PRAGMA table_info('targets')").get();
      final photometryColumns = await upgradedDb
          .customSelect("PRAGMA table_info('photometry_measurements')")
          .get();
      expect(
        targetsColumns
            .any((row) => row.data['name'] == 'goal_integration_secs'),
        isTrue,
      );
      expect(
        photometryColumns
            .any((row) => row.data['name'] == 'standard_magnitude'),
        isTrue,
      );
    } finally {
      await upgradedDb.close();
      await freshDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('schema 12 database upgrades to the complete current table set',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('nightshade_schema12_upgrade_');
    final dbFile = File('${tempDir.path}/nightshade.db');

    final setupDb = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
    try {
      for (final tableName in _tablesIntroducedAfterSchema12) {
        await setupDb.customStatement('DROP TABLE IF EXISTS $tableName');
      }
      await setupDb.customStatement(
        "DELETE FROM app_settings WHERE key LIKE 'science.%' OR key LIKE 'dark_library.%'",
      );
      await setupDb.customStatement('PRAGMA user_version = 12');
    } finally {
      await setupDb.close();
    }

    final upgradedDb = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
    final freshDb = NightshadeDatabase.forTesting(NativeDatabase.memory());
    try {
      final upgradedVersion =
          await upgradedDb.customSelect('PRAGMA user_version').getSingle();
      expect(
        upgradedVersion.data['user_version'],
        equals(upgradedDb.schemaVersion),
      );

      final upgradedTables = await _sqliteTableNames(upgradedDb);
      final freshDriftTables =
          freshDb.allTables.map((table) => table.actualTableName).toSet();

      expect(
        upgradedTables,
        containsAll(freshDriftTables),
        reason: 'Upgraded schema 12 databases must contain every current '
            'Drift-managed table.',
      );

      final upgradedSettings = await upgradedDb.settingsDao.getAllSettings();
      for (final key in const [
        'science.feature.photometry',
        'science.feature.frame_quality_maps',
        'science.overlay.live_grid_rows',
        'dark_library.auto_subtract',
        'dark_library.temp_tolerance',
      ]) {
        expect(
          upgradedSettings[key] != null,
          isTrue,
          reason: '$key should be restored during upgrade.',
        );
      }

      final photometryColumns = await upgradedDb
          .customSelect("PRAGMA table_info('photometry_measurements')")
          .get();
      expect(
        photometryColumns
            .any((row) => row.data['name'] == 'standard_magnitude'),
        isTrue,
      );
    } finally {
      await upgradedDb.close();
      await freshDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  });

  test('synthetic schema 20 profile fixture normalizes active and optics',
      () async {
    final fixture =
        await SyntheticOldProfileFixture.schema20WithDuplicateActiveProfiles();
    final db = NightshadeDatabase.forTesting(NativeDatabase(fixture.dbFile));
    try {
      final upgradedVersion =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(
        upgradedVersion.data['user_version'],
        equals(db.schemaVersion),
      );

      final profiles = await db.select(db.equipmentProfiles).get();
      expect(profiles, hasLength(2));

      final activeProfiles =
          profiles.where((profile) => profile.isActive).toList();
      expect(
        activeProfiles.map((profile) => profile.name),
        equals(['Legacy Observatory']),
        reason: 'Migration v21 should keep only the newest active profile.',
      );

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index'",
          )
          .get();
      expect(
        indexes.map((row) => row.data['name']).toSet(),
        contains('idx_profiles_single_active'),
        reason: 'The partial unique active-profile index should be restored.',
      );
      await expectLater(
        db.into(db.equipmentProfiles).insert(
              EquipmentProfilesCompanion.insert(
                name: 'Duplicate Active Profile',
                isActive: const Value(true),
              ),
            ),
        throwsA(isA<SqliteException>()),
        reason: 'Upgraded legacy databases should reject another active '
            'profile after migration.',
      );

      final widefield =
          profiles.singleWhere((profile) => profile.name == 'Legacy Widefield');
      expect(widefield.telescopeFocalLength, equals(250.0));
      expect(widefield.telescopeAperture, equals(60.0));

      final observatory = profiles
          .singleWhere((profile) => profile.name == 'Legacy Observatory');
      expect(observatory.focalLength, equals(900.0));
      expect(observatory.aperture, equals(120.0));
    } finally {
      await db.close();
      await fixture.dispose();
    }
  });

  test('synthetic schema 20 science fixture deduplicates session configs',
      () async {
    final fixture = await SyntheticOldProfileFixture
        .schema20WithDuplicateScienceSessionConfigs();
    final db = NightshadeDatabase.forTesting(NativeDatabase(fixture.dbFile));
    try {
      final upgradedVersion =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(
        upgradedVersion.data['user_version'],
        equals(db.schemaVersion),
      );

      final configs = await db
          .customSelect(
            'SELECT id, session_id, photometry_enabled, psf_grid_rows '
            'FROM science_session_config WHERE session_id = 1',
          )
          .get();
      expect(
        configs,
        hasLength(1),
        reason: 'Migration v21 should dedupe science session configs.',
      );
      expect(configs.single.data['id'], equals(2));
      expect(configs.single.data['photometry_enabled'], equals(0));
      expect(configs.single.data['psf_grid_rows'], equals(8));

      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index'",
          )
          .get();
      expect(
        indexes.map((row) => row.data['name']).toSet(),
        contains('idx_science_session_config_session_unique'),
        reason: 'The partial unique science-session config index should be '
            'restored after dedupe.',
      );

      await expectLater(
        db.into(db.scienceSessionConfig).insert(
              ScienceSessionConfigCompanion.insert(
                sessionId: const Value(1),
              ),
            ),
        throwsA(isA<SqliteException>()),
        reason: 'Upgraded legacy databases should reject another config for '
            'the same session after migration.',
      );
    } finally {
      await db.close();
      await fixture.dispose();
    }
  });

  test('synthetic schema 20 weather fixture deduplicates singleton settings',
      () async {
    final fixture =
        await SyntheticOldProfileFixture.schema20WithDuplicateWeatherSettings();
    final db = NightshadeDatabase.forTesting(NativeDatabase(fixture.dbFile));
    try {
      final upgradedVersion =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(
        upgradedVersion.data['user_version'],
        equals(db.schemaVersion),
      );

      final settings = await db.weatherSettingsDao.getOrCreateSettings();
      expect(settings.id, equals(1));
      expect(settings.preferredProvider, equals('legacy_primary'));
      expect(settings.triggerDistanceKm, equals(25.0));
      expect(settings.weatherSafetyEnabled, isTrue);

      final rows = await db.customSelect('SELECT id FROM weather_settings').get();
      expect(
        rows,
        hasLength(1),
        reason: 'Upgraded legacy weather settings should collapse to the '
            'primary singleton row on first settings access.',
      );

      await db.weatherSettingsDao.updateSettings(preferredProvider: 'updated');
      final updated = await db.weatherSettingsDao.getSettings();
      expect(updated?.id, equals(1));
      expect(updated?.preferredProvider, equals('updated'));
    } finally {
      await db.close();
      await fixture.dispose();
    }
  });

  test('synthetic schema 17 image fixture preserves metadata cascade',
      () async {
    final fixture =
        await SyntheticOldProfileFixture.schema17WithCapturedImageMetadata();
    final db = NightshadeDatabase.forTesting(NativeDatabase(fixture.dbFile));
    try {
      final upgradedVersion =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(
        upgradedVersion.data['user_version'],
        equals(db.schemaVersion),
      );

      final imageRows = await db
          .customSelect('SELECT id, file_name FROM captured_images')
          .get();
      expect(imageRows, hasLength(1));
      expect(imageRows.single.data['file_name'], equals('light-001.fits'));

      final metadataRows = await db
          .customSelect('SELECT "key", value FROM image_metadata')
          .get();
      expect(metadataRows, hasLength(1));
      expect(metadataRows.single.data['key'], equals('FILTER'));
      expect(metadataRows.single.data['value'], equals('L'));

      final foreignKeys = await db
          .customSelect("PRAGMA foreign_key_list('image_metadata')")
          .get();
      expect(
        foreignKeys.any((row) => row.data['on_delete'] == 'CASCADE'),
        isTrue,
        reason: 'Migration v18 should restore image metadata cascade delete.',
      );

      await db.customStatement('DELETE FROM captured_images WHERE id = 1');
      final remainingMetadata = await db
          .customSelect('SELECT COUNT(*) AS count FROM image_metadata')
          .getSingle();
      expect(
        remainingMetadata.data['count'],
        equals(0),
        reason:
            'Upgraded legacy image metadata should cascade on image delete.',
      );
    } finally {
      await db.close();
      await fixture.dispose();
    }
  });
}

const _tablesIntroducedAfterSchema12 = [
  'science_session_config',
  'photometry_measurements',
  'frame_photometric_calibration',
  'transparency_samples',
  'psf_field_tiles',
  'science_frame_quality_metrics',
  'science_tile_metrics',
  'astrometry_residual_vectors',
  'moving_object_candidates',
  'line_ratio_products',
  'photometric_transforms',
  'dark_library',
  'observation_logs',
  'observing_lists',
  'observing_list_items',
  'sequence_runs',
];

Future<Set<String>> _sqliteTableNames(NightshadeDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((row) => row.data['name']?.toString() ?? '').toSet();
}
