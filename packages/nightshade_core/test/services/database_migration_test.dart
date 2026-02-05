import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';

void main() {
  test('migrates captured_images to include quality_score', () async {
    final tempDir = await Directory.systemTemp.createTemp('nightshade_migration_test_');
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
      final columns = await db.customSelect("PRAGMA table_info('captured_images')").get();
      final hasQualityScore = columns.any((row) => row.data['name'] == 'quality_score');

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
}
