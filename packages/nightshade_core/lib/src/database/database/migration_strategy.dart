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
        await _ensureIntegratedMastersOverlayColumns();
        await _createNightReportsTable();
        await _ensureIntegratedMastersV42Columns();
        await _createCampaignsTable();
        await _ensureIntegratedMastersV44Columns();
        await _createNarrowbandCompositesTable();
        await _createMosaicTables();
        await _createCalibrationTagsTable();
        await _createCustomIndexes();
        await _ensureDefaultSettings();
      },
      beforeOpen: (details) async {
        // Enable foreign key enforcement
        await customStatement('PRAGMA foreign_keys = ON');

        // Close out runs a previous process left mid-flight.
        //
        // A `sequence_runs` row is only 'running' while THIS process's
        // executor is driving it — that executor state lives in memory, so
        // nothing can still be running at the moment the database opens. Any
        // row still marked 'running' here is residue from a process that died
        // mid-run: a crash, a force quit, or the power cut at 3am that this
        // kind of software has to expect.
        //
        // Nothing ever cleared them, so they were permanent. Observed live:
        // the run list reported 13 runs "running", the oldest 17 hours old,
        // while /api/status simultaneously reported the sequencer `idle` —
        // the app contradicting itself about whether it was imaging. A stale
        // row is also what previously blocked the next run from starting.
        //
        // `ended_at` is deliberately left NULL. We do not know when the run
        // actually stopped, and stamping "now" would invent a duration
        // spanning the entire downtime. An unknown end time is the truth.
        final interrupted = await customUpdate(
          "UPDATE sequence_runs SET status = 'interrupted' "
          "WHERE status = 'running'",
          updates: {sequenceRuns},
          updateKind: UpdateKind.update,
        );
        if (interrupted > 0) {
          // ignore: avoid_print
          print(
            '[nightshade_db] Marked $interrupted sequence run(s) left '
            "'running' by a previous process as 'interrupted'.",
          );
        }

        // Rebuild session statistics that a dead process never got to write.
        //
        // `imaging_sessions.total_exposures` / `total_integration_secs` are
        // denormalised counters accumulated IN MEMORY by SessionService and
        // flushed when the session ends. A session that never ends cleanly
        // therefore keeps zeros forever — even though every frame it captured
        // is safely in `captured_images` with the right `session_id`.
        //
        // Analytics sums those counters, so the loss is user-visible and
        // permanent. Observed live: 63 of 65 sessions sat at 0, and the
        // summary reported 16 exposures / 48s of integration when the frames
        // on record were 116 exposures / 374s — under-reporting total
        // integration time, the headline number of the whole hobby, by 87%.
        //
        // `successful_exposures` is rebuilt alongside the total because it is
        // what the Analytics HISTORY view counts: fixing only the total left
        // every historical night still reading "0 frames / 0.0h" there.
        //
        // Only sessions that under-report AND demonstrably have frames are
        // touched, so this can never overwrite a correctly-written richer
        // count (a clean session's total legitimately also counts FAILED
        // exposures, which leave no image row and must not be clobbered).
        // `failed_exposures` is deliberately left alone — a failure writes no
        // frame, so the rows on disk cannot tell us how many there were, and
        // inventing a number would be its own falsehood.
        final rebuilt = await customUpdate(
          'UPDATE imaging_sessions SET '
          'total_exposures = (SELECT COUNT(*) FROM captured_images c '
          'WHERE c.session_id = imaging_sessions.id), '
          'successful_exposures = (SELECT COUNT(*) FROM captured_images c '
          'WHERE c.session_id = imaging_sessions.id), '
          'total_integration_secs = (SELECT IFNULL(SUM(c.exposure_duration), 0) '
          'FROM captured_images c WHERE c.session_id = imaging_sessions.id) '
          'WHERE (total_exposures = 0 OR successful_exposures = 0) '
          'AND EXISTS ('
          'SELECT 1 FROM captured_images c WHERE c.session_id = '
          'imaging_sessions.id)',
          updates: {imagingSessions},
          updateKind: UpdateKind.update,
        );
        if (rebuilt > 0) {
          // ignore: avoid_print
          print(
            '[nightshade_db] Rebuilt statistics for $rebuilt imaging '
            'session(s) from the frames actually on record.',
          );
        }

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
        final integrityRow = await customSelect(
          'PRAGMA integrity_check;',
        ).get();
        final ok =
            integrityRow.length == 1 &&
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
        await _upgradeSchemaV44(m, from);
        await _upgradeSchemaV45(m, from);
        await _upgradeSchemaV46(m, from);
        await _upgradeSchemaV47(m, from);
        await _upgradeSchemaV48(m, from);
        await _upgradeSchemaV49(m, from);
        await _upgradeSchemaV50(m, from);
        await _upgradeSchemaV51(m, from);
        await _upgradeSchemaV52(m, from);
        await _upgradeSchemaV53(m, from);
        await _upgradeSchemaV54(m, from);
        await _upgradeSchemaV55(m, from);
        await _upgradeSchemaV56(m, from);
        await _upgradeSchemaV57(m, from);

        await _ensureDefaultSettings();
        await _createCustomIndexes();
      },
    );
  }
}
