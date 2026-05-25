import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/services/auto_save_service.dart';
import 'package:nightshade_core/src/services/backup_service.dart';
import 'package:nightshade_core/src/services/replay_debug_service.dart';
import 'package:nightshade_core/src/services/sequence_repository.dart';

class _MockSequenceRepository extends Mock implements SequenceRepository {}

class _MockBackupService extends Mock implements BackupService {}

class _MockReplayDebugService extends Mock implements ReplayDebugService {}

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime.utc(2026));
    registerFallbackValue(
      Sequence(
        id: 'seq',
        name: 'Test sequence',
        nodes: const {},
        createdAt: DateTime.utc(2026),
        modifiedAt: DateTime.utc(2026),
      ),
    );
  });

  group('AutoSaveService replay retention', () {
    test('prunes replay decisions once on startup using retention days',
        () async {
      final replayDebugService = _MockReplayDebugService();
      when(() => replayDebugService.pruneOlderThan(any()))
          .thenAnswer((_) async => 3);

      final service = AutoSaveService(
        sequenceRepository: _MockSequenceRepository(),
        backupService: _MockBackupService(),
        replayDebugService: replayDebugService,
        replayRetentionDays: () async => 90,
        clock: () => DateTime.utc(2026, 5, 21, 12),
      );

      service.start(
        const AutoSaveConfig(
          sequenceEnabled: false,
          backupEnabled: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      verify(
        () => replayDebugService.pruneOlderThan(
          DateTime.utc(2026, 2, 20, 12),
        ),
      ).called(1);

      await service.stop();
      service.dispose();
    });
  });
}
