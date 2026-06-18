import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/backend/network_backend.dart';
import 'package:nightshade_core/src/database/daos/images_dao.dart';
import 'package:nightshade_core/src/database/daos/sessions_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/services/imaging_records_repository.dart';

import '../fakes/fake_network_client.dart';

void main() {
  group('ImagingRecordsRepository local', () {
    late NightshadeDatabase db;
    late SessionsDao sessionsDao;
    late ImagesDao imagesDao;
    late ImagingRecordsRepository repository;

    setUp(() {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      sessionsDao = SessionsDao(db);
      imagesDao = ImagesDao(db);
      repository = ImagingRecordsRepository.local(
        sessionsDao: sessionsDao,
        imagesDao: imagesDao,
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('startSession and getSessionById round-trip', () async {
      final id = await repository.startSession(name: 'Night 1');
      final session = await repository.getSessionById(id);
      expect(session, isNotNull);
      expect(session!.name, 'Night 1');
      expect(session.status, 'active');
    });

    test('createImage and rejectImage update row', () async {
      final sessionId = await repository.startSession();
      final imageId = await repository.createImage(
        CapturedImagesCompanion.insert(
          filePath: '/data/light.fits',
          fileName: 'light.fits',
          sessionId: Value(sessionId),
          frameType: const Value('light'),
          exposureDuration: 300,
          capturedAt: DateTime.utc(2025, 1, 1),
        ),
      );

      await repository.rejectImage(imageId, 'HFR too high');
      final row = await repository.getImageById(imageId);
      expect(row, isNotNull);
      expect(row!.isAccepted, isFalse);
      expect(row.rejectionReason, 'HFR too high');
    });
  });

  group('ImagingRecordsRepository remote', () {
    late FakeNetworkClient fake;
    late NetworkBackend backend;
    late ImagingRecordsRepository repository;

    setUp(() {
      fake = FakeNetworkClient();
      backend = NetworkBackend(
        serverHost: '127.0.0.1',
        serverPort: 8080,
        httpClient: fake,
        autoConnectWebSocket: false,
      );
      repository = ImagingRecordsRepository.remote(backend);
    });

    test('startSession posts to host API', () async {
      fake.setResponse('/api/sessions', method: 'POST', body: '{"id": 42}');

      final id = await repository.startSession(name: 'Remote night');
      expect(id, 42);
      expect(fake.requests.single.method, 'POST');
      expect(fake.requests.single.path, '/api/sessions');
    });

    test('createImage posts metadata to host API', () async {
      fake.setResponse('/api/images', method: 'POST', body: '{"id": 7}');

      final imageId = await repository.createImage(
        CapturedImagesCompanion.insert(
          filePath: '/host/light.fits',
          fileName: 'light.fits',
          frameType: const Value('light'),
          exposureDuration: 120,
          capturedAt: DateTime.utc(2025, 6, 1, 12),
        ),
      );

      expect(imageId, 7);
      expect(fake.requests.single.path, '/api/images');
      final body = fake.requests.single.body!;
      expect(body, contains('filePath'));
      expect(body, contains('/host/light.fits'));
    });

    test('rejectImage patches host row', () async {
      fake.setResponse(
        '/api/images/3',
        method: 'PUT',
        body: '{"status":"updated"}',
      );

      await repository.rejectImage(3, 'clouds');
      expect(fake.requests.single.method, 'PUT');
      expect(fake.requests.single.path, '/api/images/3');
      expect(fake.requests.single.body, contains('isAccepted'));
    });
  });
}
