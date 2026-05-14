import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart' show NightshadeBackend;
import 'package:nightshade_core/src/database/daos/dark_library_dao.dart';
import 'package:nightshade_core/src/database/daos/equipment_profiles_dao.dart';
import 'package:nightshade_core/src/database/daos/images_dao.dart';
import 'package:nightshade_core/src/database/daos/sequence_checkpoints_dao.dart';
import 'package:nightshade_core/src/database/daos/sequences_dao.dart';
import 'package:nightshade_core/src/database/daos/sessions_dao.dart';
import 'package:nightshade_core/src/database/daos/settings_dao.dart';
import 'package:nightshade_core/src/database/daos/targets_dao.dart';
import 'package:nightshade_core/src/database/daos/weather_settings_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart'
    as seq_models;
import 'package:nightshade_core/src/models/science/science_models.dart'
    as science;
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';
import 'package:nightshade_core/src/services/backup_service.dart';
import 'package:nightshade_core/src/services/catalog_service.dart';
import 'package:nightshade_core/src/services/dark_library_service.dart';
import 'package:nightshade_core/src/services/flat_wizard_service.dart';
import 'package:nightshade_core/src/services/logging_service.dart';
import 'package:nightshade_core/src/services/notification_service.dart';
import 'package:nightshade_core/src/services/paginated_image_loader.dart';
import 'package:nightshade_core/src/services/plate_solve_service.dart'
    as plate_solve;
import 'package:nightshade_core/src/services/profile_service.dart';
import 'package:nightshade_core/src/services/quick_start_service.dart';
import 'package:nightshade_core/src/services/sequence_repository.dart';
import 'package:nightshade_core/src/services/sky_brightness_tracker.dart';

import '../mocks/mock_backend.dart';
import '../mocks/mock_database.dart';

class _MockSessionsDao extends Mock implements SessionsDao {}

class _MockEquipmentProfilesDao extends Mock implements EquipmentProfilesDao {}

class _MockTargetsDao extends Mock implements TargetsDao {}

class _MockSequencesDao extends Mock implements SequencesDao {}

class _MockSequenceCheckpointsDao extends Mock
    implements SequenceCheckpointsDao {}

class _MockSequenceRepository extends Mock implements SequenceRepository {}

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(Ref ref, NightshadeBackend backend) : super(ref) {
    state = backend;
  }
}

class _TestFlatWizardService extends FlatWizardService {
  final List<double?> _samples;
  int _index = 0;

  _TestFlatWizardService(this._samples) : super(MockBackend());

  @override
  Future<double?> captureTestFrame({
    required String deviceId,
    required double exposureTime,
    String? filterName,
    int? filterPosition,
    String? filterWheelDeviceId,
    int binX = 1,
    int binY = 1,
  }) async {
    final sample = _samples[_index];
    _index = (_index + 1).clamp(0, _samples.length - 1);
    return sample;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Residual service fixes', () {
    test('searchCatalog applies offset exactly once across streamed pages',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('catalog_service_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final catalogFile =
          File('${tempDir.path}${Platform.pathSeparator}catalog.csv');
      final rows = <String>[
        'id,name,ra,dec',
        for (int i = 1; i <= 10; i++)
          'M$i,Object $i,${i.toDouble()},${i.toDouble()}',
      ];
      await catalogFile.writeAsString(rows.join('\n'));

      final service = CatalogService(catalogFile.path);
      final results =
          await service.searchCatalog(query: '', offset: 5, limit: 3);

      expect(results.map((entry) => entry.id).toList(), ['M6', 'M7', 'M8']);
    });

    test('loadDarkPixels rejects truncated FITS pixel payloads', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final service = DarkLibraryService(DarkLibraryDao(database));
      final tempDir = await Directory.systemTemp.createTemp('dark_library_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final truncatedFits =
          File('${tempDir.path}${Platform.pathSeparator}truncated.fit');
      await truncatedFits.writeAsBytes(
          _buildFitsFileBytes(width: 2, height: 1, dataBytes: [0, 1, 2]));

      expect(
        service.loadDarkPixels(truncatedFits.path),
        throwsA(isA<FormatException>()),
      );
    });

    test('notification requests time out instead of hanging indefinitely',
        () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      });

      final service = NotificationService.testing(
        settingsReader: () => AppSettingsState(
          notificationsEnabled: true,
          discordWebhook: 'https://example.com/webhook',
        ),
        httpClient: client,
        requestTimeout: const Duration(milliseconds: 10),
      );

      final sent = await service.notify(
        event: NotificationEvent.custom,
        title: 'Test',
        message: 'Timeout test',
      );

      expect(sent, isFalse);
    });

    test(
        'calibrateFilterWithRateTracking reports maxIterations on non-convergence',
        () async {
      final service = _TestFlatWizardService([5000, 5000]);
      final tracker = SkyBrightnessTracker();

      final result = await service.calibrateFilterWithRateTracking(
        deviceId: 'camera-1',
        filter: 'L',
        targetAdu: 20000,
        tolerance: 5,
        minExposure: 1,
        maxExposure: 100,
        brightnessTracker: tracker,
        maxIterations: 2,
      );

      expect(result.success, isFalse);
      expect(result.iterations, 2);
    });

    test(
        'quick start propagates storage failures instead of returning empty state',
        () async {
      final sessionsDao = _MockSessionsDao();
      when(() => sessionsDao.getActiveSessions())
          .thenThrow(StateError('db corrupt'));

      final service = QuickStartService(
        sessionsDao: sessionsDao,
        profilesDao: _MockEquipmentProfilesDao(),
        targetsDao: _MockTargetsDao(),
        sequencesDao: _MockSequencesDao(),
        checkpointsDao: _MockSequenceCheckpointsDao(),
      );

      expect(
        service.getQuickStartContext(),
        throwsA(isA<StateError>()),
      );
    });

    test('paginated image loader updates paging state for explicit page loads',
        () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final imagesDao = ImagesDao(database);
      for (int i = 0; i < 3; i++) {
        await imagesDao.createImage(
          DatabaseTestFixtures.sampleImageCompanion(
            filePath: '/tmp/image_$i.fit',
            fileName: 'image_$i.fit',
            capturedAt: DateTime.utc(2026, 1, 1, 0, i),
          ),
        );
      }

      final loader = PaginatedImageLoader(imagesDao: imagesDao, pageSize: 2);
      final page = await loader.loadPage(2);

      expect(page, hasLength(1));
      expect(loader.currentPage, 2);
      expect(loader.hasMore, isFalse);
      expect(loader.loadedCount, 1);
    });

    test(
        'backup restore coerces legacy non-string setting values instead of crashing',
        () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final tempDir = await Directory.systemTemp.createTemp('backup_restore_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final backupFile =
          File('${tempDir.path}${Platform.pathSeparator}legacy.nsbackup');
      await backupFile.writeAsString(jsonEncode({
        'version': '2.0',
        'createdAt': DateTime.now().toIso8601String(),
        'appVersion': '2.5.0',
        'platform': 'windows',
        'settings': {
          'notifications_enabled': true,
          'plate_solve_timeout': 45,
        },
        'equipmentProfiles': const [],
        'targets': const [],
      }));

      final service = BackupService(
        database: database,
        sequenceRepository: _MockSequenceRepository(),
        logger: LoggingService(),
      );

      final result = await service.restoreBackup(filePath: backupFile.path);
      final settings = await SettingsDao(database).getAllSettings();

      expect(result.success, isTrue);
      expect(settings['notifications_enabled'], 'true');
      expect(settings['plate_solve_timeout'], '45');
    });

    test('backup metadata reads nested category counts from v2 backups',
        () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final tempDir = await Directory.systemTemp.createTemp('backup_metadata_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final backupFile =
          File('${tempDir.path}${Platform.pathSeparator}metadata.nsbackup');
      await backupFile.writeAsString(jsonEncode({
        'version': '2.0',
        'createdAt': DateTime.utc(2026, 5, 5).toIso8601String(),
        'appVersion': '2.5.0',
        'platform': 'windows',
        'metadata': {
          'settingsCount': 2,
          'profilesCount': 3,
          'sequencesCount': 4,
          'targetsCount': 5,
        },
        'settings': const {},
        'equipmentProfiles': const [],
        'sequences': const [],
        'targets': const [],
      }));

      final service = BackupService(
        database: database,
        sequenceRepository: _MockSequenceRepository(),
        logger: LoggingService(),
      );

      final metadata = await service.readBackupMetadata(backupFile.path);

      expect(metadata?.settingsCount, 2);
      expect(metadata?.profilesCount, 3);
      expect(metadata?.sequencesCount, 4);
      expect(metadata?.targetsCount, 5);
    });

    test('backup restore accepts current TargetHeader sequence nodes',
        () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final tempDir =
          await Directory.systemTemp.createTemp('backup_sequence_restore_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final backupFile =
          File('${tempDir.path}${Platform.pathSeparator}sequence.nsbackup');
      await backupFile.writeAsString(jsonEncode({
        'version': '2.0',
        'createdAt': DateTime.utc(2026, 5, 5).toIso8601String(),
        'appVersion': '2.5.0',
        'platform': 'windows',
        'settings': const {},
        'equipmentProfiles': const [],
        'sequences': [
          {
            'name': 'Restored Sequence',
            'description': 'TargetHeader restore coverage',
            'rootNodeId': 'target-1',
            'isTemplate': false,
            'createdAt': DateTime.utc(2026, 5, 5).toIso8601String(),
            'modifiedAt': DateTime.utc(2026, 5, 5).toIso8601String(),
            'nodes': {
              'target-1': {
                'id': 'target-1',
                'nodeType': 'TargetHeader',
                'name': 'M31',
                'parentId': null,
                'childIds': const [],
                'orderIndex': 0,
                'isEnabled': true,
                'targetName': 'M31',
                'raHours': 0.712,
                'decDegrees': 41.269,
                'rotation': 15.0,
                'minAltitude': 30.0,
                'maxAltitude': 80.0,
                'priority': 2,
              },
            },
          },
        ],
        'targets': const [],
      }));

      final repository = SequenceRepository(SequencesDao(database));
      final service = BackupService(
        database: database,
        sequenceRepository: repository,
        logger: LoggingService(),
      );

      final result = await service.restoreBackup(filePath: backupFile.path);
      final restoredSequences = await repository.loadAllSequences();
      final targetNode = restoredSequences.single.nodes['target-1'];

      expect(result.success, isTrue);
      expect(result.categoryCounts['sequences'], 1);
      expect(targetNode, isA<seq_models.TargetHeaderNode>());
      expect(
        (targetNode! as seq_models.TargetHeaderNode).targetName,
        'M31',
      );
    });

    test('profile import tolerates numeric legacy values and float offsets',
        () {
      final data = ProfileExportData.fromJson({
        'name': 'Test Profile',
        'defaultGain': 100.9,
        'defaultOffset': 50.1,
        'defaultBinX': 2.0,
        'defaultBinY': 3.0,
        'filterFocusOffsets': {
          'L': 1.9,
          'R': -2.2,
        },
      });

      expect(data.defaultGain, 100);
      expect(data.defaultOffset, 50);
      expect(data.defaultBinX, 2);
      expect(data.defaultBinY, 3);
      expect(data.filterFocusOffsets, {'L': 1, 'R': -2});
    });

    test('equipment snapshot rejects malformed JSON schema', () {
      expect(
        () => EquipmentSnapshot.fromJsonString('["not-an-object"]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('loadSequence fails loudly on unsupported node types', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final dao = SequencesDao(database);
      final repository = SequenceRepository(dao);
      final sequenceId = await dao.createSequence(
        SequencesCompanion.insert(name: 'Broken Sequence'),
      );

      await dao.createNode(
        SequenceNodesCompanion.insert(
          sequenceId: sequenceId,
          nodeId: 'node-1',
          nodeType: 'instruction',
          specificType: 'unknown-node-type',
          name: 'Broken Node',
        ),
      );

      expect(
        repository.loadSequence(sequenceId),
        throwsA(isA<StateError>()),
      );
    });

    test('saving sequence clears legacy recovery config references', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final dao = SequencesDao(database);
      final repository = SequenceRepository(dao);
      final sequenceId = await dao.createSequence(
        SequencesCompanion.insert(
          name: 'Legacy Recovery Sequence',
          rootNodeId: const Value('root'),
        ),
      );

      await dao.createNode(
        SequenceNodesCompanion.insert(
          sequenceId: sequenceId,
          nodeId: 'root',
          nodeType: 'logic',
          specificType: 'recovery',
          name: 'Recovery',
          properties: Value('{"recoveryAction":"retry"}'),
          recoveryConfig: const Value('{"targetNodeId":"child"}'),
        ),
      );
      await dao.createNode(
        SequenceNodesCompanion.insert(
          sequenceId: sequenceId,
          nodeId: 'child',
          nodeType: 'instruction',
          specificType: 'exposure',
          name: 'Exposure',
          properties: Value('{"count":1,"durationSecs":60.0}'),
          parentNodeId: const Value('root'),
          orderIndex: const Value(0),
        ),
      );

      await repository.saveSequence(
        seq_models.Sequence(
          databaseId: sequenceId,
          name: 'Legacy Recovery Sequence',
          rootNodeId: 'root',
          nodes: {
            'root': seq_models.RecoveryNode(
              id: 'root',
              childIds: const [],
            ),
          },
        ),
      );

      final nodes = await dao.getNodesForSequence(sequenceId);
      expect(nodes, hasLength(1));
      expect(nodes.single.nodeId, 'root');
      expect(nodes.single.recoveryConfig, equals(null));
    });

    test('plate solve fallback preserves backend error details', () async {
      final backend = MockBackend();
      when(() => backend.eventStream).thenAnswer((_) => const Stream.empty());
      when(() => backend.polarAlignmentEvents)
          .thenAnswer((_) => const Stream.empty());
      when(
        () => backend.plateSolve(
          imagePath: any(named: 'imagePath'),
          ra: any(named: 'ra'),
          dec: any(named: 'dec'),
          fovDegrees: any(named: 'fovDegrees'),
        ),
      ).thenThrow(StateError('backend failed'));

      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _TestBackendNotifier(ref, backend),
          ),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(plate_solve.plateSolveServiceProvider);
      final result = await service.solve(
        'missing.fit',
        const plate_solve.PlateSolverConfig(
          type: plate_solve.PlateSolverType.astap,
          executablePath: 'C:/missing/astap.exe',
        ),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('backend failed'));
      expect(result.errorMessage, contains('Local fallback failed'));
    });

    test('dark library deduplicates entries by file path', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final dao = DarkLibraryDao(database);
      final firstId = await dao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/dark.fit',
          exposureTime: 60,
          gain: const Value(100),
          offset: const Value(10),
        ),
      );
      final secondId = await dao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/dark.fit',
          exposureTime: 120,
          gain: const Value(100),
          offset: const Value(10),
        ),
      );

      final entries = await dao.getAllEntries();
      expect(secondId, firstId);
      expect(entries, hasLength(1));
      expect(entries.single.exposureTime, 120);
    });

    test('dark matching includes camera offset', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final dao = DarkLibraryDao(database);
      await dao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/dark_offset_10.fit',
          exposureTime: 60,
          gain: const Value(100),
          offset: const Value(10),
        ),
      );
      await dao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/dark_offset_20.fit',
          exposureTime: 60,
          gain: const Value(100),
          offset: const Value(20),
        ),
      );

      final match = await dao.findBestMatch(
        exposureTime: 60,
        gain: 100,
        offset: 20,
        binX: 1,
        binY: 1,
      );

      expect(match?.filePath, '/tmp/dark_offset_20.fit');
    });

    test('science session config upsert updates in place', () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final sessionId = await database.sessionsDao.createSession(
        ImagingSessionsCompanion.insert(
          startTime: DateTime.utc(2026, 1, 1),
        ),
      );

      await database.scienceDao.upsertSessionConfig(
        science.ScienceSessionConfig(
          sessionId: sessionId,
          photometryEnabled: true,
        ),
      );
      await database.scienceDao.upsertSessionConfig(
        science.ScienceSessionConfig(
          sessionId: sessionId,
          photometryEnabled: false,
        ),
      );

      final rows = await (database.select(database.scienceSessionConfig)
            ..where((tbl) => tbl.sessionId.equals(sessionId)))
          .get();

      expect(rows, hasLength(1));
      expect(rows.single.photometryEnabled, isFalse);
    });

    test('weather settings DAO collapses duplicate rows into a singleton',
        () async {
      final database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);

      final dao = WeatherSettingsDao(database);
      await database.into(database.weatherSettings).insert(
            WeatherSettingsCompanion.insert(id: const Value(1)),
          );
      await database.into(database.weatherSettings).insert(
            WeatherSettingsCompanion.insert(id: const Value(2)),
          );

      final settings = await dao.getOrCreateSettings();
      final rows = await database.select(database.weatherSettings).get();

      expect(settings.id, 1);
      expect(rows, hasLength(1));
    });
  });
}

Uint8List _buildFitsFileBytes({
  required int width,
  required int height,
  required List<int> dataBytes,
}) {
  final headerCards = <String>[
    _fitsCard('SIMPLE', 'T'),
    _fitsCard('BITPIX', '16'),
    _fitsCard('NAXIS', '2'),
    _fitsCard('NAXIS1', width.toString()),
    _fitsCard('NAXIS2', height.toString()),
    'END'.padRight(80, ' '),
  ];

  final header = headerCards.join().padRight(2880, ' ');
  final bytes = <int>[...ascii.encode(header), ...dataBytes];
  return Uint8List.fromList(bytes);
}

String _fitsCard(String keyword, String value) {
  return '${keyword.padRight(8)}= ${value.toString().padLeft(20)}'
      .padRight(80, ' ');
}
