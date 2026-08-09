import 'dart:io';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/images_dao.dart';
import 'package:nightshade_core/src/database/daos/sessions_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/services/session_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SessionExportService', () {
    late NightshadeDatabase database;
    late SessionsDao sessionsDao;
    late ImagesDao imagesDao;

    setUp(() async {
      database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      sessionsDao = SessionsDao(database);
      imagesDao = ImagesDao(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('exportToHtml writes an HTML report file', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nightshade_session_export_test_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sessionId = await sessionsDao.createSession(
        ImagingSessionsCompanion.insert(
          name: const Value('Rosette'),
          startTime: DateTime.utc(2026, 2, 1, 2),
          status: const Value('completed'),
        ),
      );

      await sessionsDao.updateSessionStats(
        sessionId,
        totalExposures: 10,
        successfulExposures: 8,
        failedExposures: 2,
        totalIntegrationSecs: 3600.0,
        avgHfr: 2.3,
        avgGuidingRms: 0.9,
      );
      await sessionsDao.endSession(sessionId);

      final service = SessionExportService(
        sessionsDao: sessionsDao,
        imagesDao: imagesDao,
        documentsDirectoryProvider: () async => tempDir,
      );

      final reportPath = await service.exportToHtml(sessionId);
      addTearDown(() async {
        final file = File(reportPath);
        if (await file.exists()) {
          await file.delete();
        }
      });

      final report = await File(reportPath).readAsString();
      expect(reportPath, endsWith('.html'));
      expect(report, contains('Nightshade Session Report'));
      expect(report, contains('Rosette'));
      expect(report, contains('Integration'));
    });

    // Observed defect: a report whose summary read "Average HFR -   Guiding RMS
    // -   Humidity -%   Temperature - C" sat directly above a frame table that
    // listed an HFR for every one of the eight frames. The session-level
    // avg_hfr column was simply never written for that run.
    test('exportToHtml derives the HFR/RMS summary from the frames when the '
        'session columns are null, and never prints a bare unit', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nightshade_session_export_summary_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final sessionId = await sessionsDao.createSession(
        ImagingSessionsCompanion.insert(
          name: const Value('MF PROBE B'),
          startTime: DateTime.utc(2026, 7, 25, 17, 4),
          status: const Value('completed'),
        ),
      );
      // No updateSessionStats call: avg_hfr / avg_guiding_rms / humidity /
      // temperature all stay NULL, exactly like the observed session.
      for (var i = 0; i < 4; i++) {
        await imagesDao.createImage(
          CapturedImagesCompanion.insert(
            filePath: '/lights/l$i.fits',
            fileName: 'l$i.fits',
            sessionId: Value(sessionId),
            exposureDuration: 3.0,
            frameType: const Value('light'),
            capturedAt: DateTime.utc(
              2026,
              7,
              25,
              17,
              4,
            ).add(Duration(minutes: i)),
            hfr: Value(2.0 + i * 0.2), // 2.0, 2.2, 2.4, 2.6 -> mean 2.30
            guidingRmsTotal: const Value(0.50),
            isAccepted: const Value(true),
          ),
        );
      }

      final service = SessionExportService(
        sessionsDao: sessionsDao,
        imagesDao: imagesDao,
        documentsDirectoryProvider: () async => tempDir,
      );
      final reportPath = await service.exportToHtml(sessionId);
      addTearDown(() async {
        final file = File(reportPath);
        if (await file.exists()) await file.delete();
      });
      final report = await File(reportPath).readAsString();

      // The summary now states the mean of the frames it is built from…
      expect(report, contains('2.30 px'));
      expect(report, contains('mean of 4 accepted frames'));
      expect(report, contains('0.50"'));
      // …and the missing ambient readings show an em dash with NO stray unit.
      expect(report, isNot(contains('-%')));
      expect(report, isNot(contains('- C')));
      expect(report, contains('not recorded'));
      // The frame table still lists the per-frame HFRs it always did.
      expect(report, contains('2.60'));
    });

    // Observed defect: the CSV's "FWHM (px)" column was always hfr * 2.3548 —
    // the sigma->FWHM factor applied to a half-flux RADIUS, an 18% inflation —
    // and the measured `fwhm` column the pipeline writes was never read.
    test('exportToCsv prefers the measured FWHM and derives 2x HFR '
        'only when there is none', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nightshade_session_export_fwhm_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      final sessionId = await sessionsDao.createSession(
        ImagingSessionsCompanion.insert(
          name: const Value('FWHM PROBE'),
          startTime: DateTime.utc(2026, 8, 1, 2),
        ),
      );
      // Frame 1: pipeline measured a real FWHM that disagrees with any
      // multiple of HFR, so a derived column cannot accidentally match it.
      final measuredId = await imagesDao.createImage(
        CapturedImagesCompanion.insert(
          filePath: '/lights/m.fits',
          fileName: 'm.fits',
          sessionId: Value(sessionId),
          exposureDuration: 300.0,
          frameType: const Value('light'),
          capturedAt: DateTime.utc(2026, 8, 1, 2, 1),
          hfr: const Value(2.00),
          isAccepted: const Value(true),
        ),
      );
      await imagesDao.stampProducingNode(imageId: measuredId, fwhm: 3.11);
      // Frame 2: no measured FWHM, so the exporter must derive it.
      await imagesDao.createImage(
        CapturedImagesCompanion.insert(
          filePath: '/lights/d.fits',
          fileName: 'd.fits',
          sessionId: Value(sessionId),
          exposureDuration: 300.0,
          frameType: const Value('light'),
          capturedAt: DateTime.utc(2026, 8, 1, 2, 2),
          hfr: const Value(2.00),
          isAccepted: const Value(true),
        ),
      );

      final csvPath = await SessionExportService(
        sessionsDao: sessionsDao,
        imagesDao: imagesDao,
        documentsDirectoryProvider: () async => tempDir,
      ).exportToCsv(sessionId);
      addTearDown(() async {
        final file = File(csvPath);
        if (await file.exists()) await file.delete();
      });

      final table = const CsvToListConverter(
        shouldParseNumbers: false,
      ).convert(await File(csvPath).readAsString());
      final header = table.first.cast<String>();
      final hfrCol = header.indexWhere((c) => c.contains('HFR (px)'));
      final fwhmCol = header.indexWhere((c) => c.startsWith('FWHM'));
      expect(hfrCol, isNonNegative);
      expect(fwhmCol, isNonNegative);

      final measuredRow = table.firstWhere((r) => r[0] == 'm.fits');
      final derivedRow = table.firstWhere((r) => r[0] == 'd.fits');
      // The measured column wins outright.
      expect(measuredRow[fwhmCol], '3.11');
      // With no measurement, FWHM = 2.0 * HFR — NOT 2.3548 * HFR (4.71).
      expect(derivedRow[hfrCol], '2.00');
      expect(derivedRow[fwhmCol], '4.00');
      // And the header says the number can be derived.
      expect(header[fwhmCol], contains('HFR'));
    });

    test('exportSummary derives Average HFR from frames when null', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'nightshade_session_export_summary_text_',
      );
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final sessionId = await sessionsDao.createSession(
        ImagingSessionsCompanion.insert(
          name: const Value('MF PROBE B'),
          startTime: DateTime.utc(2026, 7, 25, 17, 4),
        ),
      );
      await imagesDao.createImage(
        CapturedImagesCompanion.insert(
          filePath: '/lights/only.fits',
          fileName: 'only.fits',
          sessionId: Value(sessionId),
          exposureDuration: 3.0,
          frameType: const Value('light'),
          capturedAt: DateTime.utc(2026, 7, 25, 17, 5),
          hfr: const Value(2.38),
          isAccepted: const Value(true),
        ),
      );

      final summary = await SessionExportService(
        sessionsDao: sessionsDao,
        imagesDao: imagesDao,
        documentsDirectoryProvider: () async => tempDir,
      ).exportSummary(sessionId);

      expect(summary, contains('Average HFR: 2.38 px'));
    });
  });
}
