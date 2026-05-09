import 'dart:io';

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
  });
}
