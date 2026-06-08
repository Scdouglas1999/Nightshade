part of '../database.dart';

extension _NightshadeDatabaseMigration on NightshadeDatabase {
  MigrationStrategy _buildMigrationStrategy() {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await _createFrameForensicsTable();
        await _ensureCapturedImagesProducingNodeColumns();
        await _createStackedResultsTable();
        await _createProjectsTables();
        await _createPostSessionTables();
        await _createNightReportsTable();
        await _ensureIntegratedMastersV42Columns();
        await _createCampaignsTable();
        await _createCustomIndexes();
        await _ensureDefaultSettings();
      },
      beforeOpen: (details) async {
        // Enable foreign key enforcement
        await customStatement('PRAGMA foreign_keys = ON');

        // WHY a second integrity check here in addition to the pre-flight in
        // `_openConnection()`: the pre-flight catches corruption present
        // when the app starts, but cannot catch in-session corruption from a
        // crash, an SSD bit-flip, or a forced unmount. Running
        // `PRAGMA integrity_check` once per open is cheap (microseconds on a
        // small DB) and gives ops a structured warning in logs the moment
        // corruption first manifests rather than the next time the app
        // happens to read a damaged page. We do NOT auto-recover from here —
        // the connection is already live in a background isolate and we
        // cannot rotate the file out from under it safely.
        final integrityRow =
            await customSelect('PRAGMA integrity_check;').get();
        final ok = integrityRow.length == 1 &&
            integrityRow.first.data['integrity_check'] == 'ok';
        if (!ok) {
          // Emit through dart:developer-style logging would be nice, but
          // logging_service is not on the database layer's dependency
          // graph. A plain `print` matches the convention used elsewhere in
          // this file for migration-time diagnostics and is captured by the
          // app's stdout/stderr log sinks.
          // ignore: avoid_print
          print(
            '[nightshade_db] WARNING: PRAGMA integrity_check failed at '
            'beforeOpen: ${integrityRow.map((r) => r.data['integrity_check']).join('; ')}. '
            'Database remains live; restart the app to trigger the '
            'corruption-recovery rotation.',
          );
        }
      },
      onUpgrade: (Migrator m, int from, int to) async {
        await _upgradeSchemaV2ToV17(m, from);
        await _upgradeSchemaV18ToV22(m, from);
        await _upgradeSchemaV23ToV31(m, from);
        await _upgradeSchemaV32ToV40(m, from);
        await _upgradeSchemaV41(m, from);
        await _upgradeSchemaV42(m, from);
        await _upgradeSchemaV43(m, from);

        await _ensureDefaultSettings();
        await _createCustomIndexes();
      },
    );
  }
}
