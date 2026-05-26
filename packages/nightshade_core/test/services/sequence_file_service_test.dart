import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as path;

class TestFileSelectorPlatform extends FileSelectorPlatform {
  TestFileSelectorPlatform({
    required this.openPath,
    required this.savePath,
  });

  final String openPath;
  final String savePath;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    return XFile(openPath);
  }

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    return FileSaveLocation(savePath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sequence file export/import preserves nodes', () async {
    final tempDir =
        await Directory.systemTemp.createTemp('sequence_file_service_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath = path.join(tempDir.path, 'sequence.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;

    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    final sequence = Sequence.create(
      id: 'seq-1',
      name: 'Test Sequence',
      rootNodeId: 'target-1',
      nodes: {
        'target-1': TargetHeaderNode(
          id: 'target-1',
          targetName: 'M31',
          raHours: 0.712,
          decDegrees: 41.269,
          childIds: const ['exposure-1'],
        ),
        'exposure-1': ExposureNode(
          id: 'exposure-1',
          parentId: 'target-1',
          durationSecs: 60,
          count: 1,
          frameType: FrameType.light,
        ),
      },
    );

    final service = SequenceFileService();
    await service.exportSequence(sequence);
    final imported = await service.importSequence();

    expect(imported, isNotNull);
    expect(imported!.rootNodeId, 'target-1');
    expect(imported.nodes.length, 2);
    expect(imported.nodes['target-1'], isA<TargetHeaderNode>());
    expect(imported.nodes['exposure-1'], isA<ExposureNode>());
  });

  test('dither pattern + grid size survive export/import round trip',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('sequence_file_service_dither_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath = path.join(tempDir.path, 'dither.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    final sequence = Sequence.create(
      id: 'seq-dither',
      name: 'Dither pattern roundtrip',
      rootNodeId: 'target-1',
      nodes: {
        'target-1': TargetHeaderNode(
          id: 'target-1',
          targetName: 'M81',
          raHours: 9.926,
          decDegrees: 69.065,
          childIds: const ['dither-1'],
        ),
        'dither-1': DitherNode(
          id: 'dither-1',
          parentId: 'target-1',
          pixels: 7.0,
          pattern: DitherPattern.grid,
          gridSize: 4,
        ),
      },
    );

    final service = SequenceFileService();
    await service.exportSequence(sequence);
    final imported = await service.importSequence();

    expect(imported, isNotNull);
    final ditherNode = imported!.nodes['dither-1'];
    expect(ditherNode, isA<DitherNode>());
    final dither = ditherNode as DitherNode;
    expect(dither.pattern, DitherPattern.grid);
    expect(dither.gridSize, 4);
    expect(dither.pixels, 7.0);
  });

  test('sequence import fails fast when active profile is missing filters',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('sequence_file_service_validation_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath =
        path.join(tempDir.path, 'sequence_invalid_filter.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;

    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    const sequenceJson = '''
{
  "name": "Filter Test",
  "rootNodeId": "target-1",
  "nodes": {
    "target-1": {
      "id": "target-1",
      "nodeType": "targetHeader",
      "targetName": "M31",
      "raHours": 0.712,
      "decDegrees": 41.269,
      "childIds": ["filter-1"],
      "isEnabled": true
    },
    "filter-1": {
      "id": "filter-1",
      "nodeType": "filterChange",
      "filterName": "Ha",
      "parentId": "target-1",
      "childIds": [],
      "isEnabled": true
    }
  }
}
''';
    await File(filePath).writeAsString(sequenceJson);

    final container = ProviderContainer(
      overrides: [
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 1,
            name: 'Widefield',
            filterNames: ['L', 'R', 'G', 'B'],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final service = container.read(sequenceFileServiceProvider);

    await expectLater(
      service.importSequence(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('filters not present'),
        ),
      ),
    );
  });

  test('exportSequence refuses to write a sequence with validation errors',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('sequence_file_service_export_validation_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath = path.join(tempDir.path, 'invalid.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    // An empty sequence is the simplest pre-built validation failure
    // (EmptySequenceRule fires).
    final bad = Sequence.create(id: 'bad', name: 'Empty');

    final service = SequenceFileService();

    await expectLater(
      service.exportSequence(bad),
      throwsA(isA<SequenceValidationFailedException>()),
    );

    // No file should have been written.
    expect(await File(filePath).exists(), isFalse,
        reason: 'export must not write when validation errors block it');
  });

  test('sequence round-trip preserves Wave-1 RecoveryNode focus-drift fields',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('sequence_file_service_recovery_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath = path.join(tempDir.path, 'recovery.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    // Build a sequence using every new RecoveryNode / trigger field
    // introduced in Wave 1 (focus-drift window + humidity / focus-drift
    // trigger types). The exported JSON must round-trip back through
    // _jsonToNode without silently resetting to default values.
    final exposure = ExposureNode(
      id: 'exp-1',
      durationSecs: 60,
      count: 5,
    );
    final recovery = RecoveryNode(
      id: 'recov-1',
      name: 'AF on drift',
      triggerType: TriggerType.focusDrift,
      recoveryAction: RecoveryActionType.autofocus,
      maxRetries: 4,
      triggerThreshold: 1.25,
      hfrThresholdPercent: 18.5,
      hfrConsecutiveFrames: 4,
      focusDriftWindowSize: 12,
      focusDriftMinIncreasingCount: 6,
      focusDriftMinTotalIncrease: 0.75,
      childIds: const ['exp-1'],
    );
    final root = InstructionSetNode(
      id: 'root',
      childIds: const ['recov-1'],
    );

    final sequence = Sequence.create(
      id: 'seq-recov',
      name: 'Round trip recovery',
      rootNodeId: 'root',
      nodes: {
        'root': root,
        'recov-1': recovery.copyWith(parentId: 'root'),
        'exp-1': exposure.copyWith(parentId: 'recov-1'),
      },
    );

    final service = SequenceFileService();
    await service.exportSequence(sequence);
    final imported = await service.importSequence();
    expect(imported, isNotNull);

    final reloaded = imported!.nodes['recov-1'] as RecoveryNode;
    expect(reloaded.triggerType, TriggerType.focusDrift,
        reason: 'focusDrift trigger type must round-trip');
    expect(reloaded.recoveryAction, RecoveryActionType.autofocus);
    expect(reloaded.maxRetries, 4);
    expect(reloaded.triggerThreshold, 1.25);
    expect(reloaded.hfrThresholdPercent, 18.5);
    expect(reloaded.hfrConsecutiveFrames, 4);
    // Pack A's new focus-drift window fields — these were the round-trip
    // gap the audit caught.
    expect(reloaded.focusDriftWindowSize, 12);
    expect(reloaded.focusDriftMinIncreasingCount, 6);
    expect(reloaded.focusDriftMinTotalIncrease, 0.75);
  });

  test('sequence round-trip preserves humidityThreshold trigger type',
      () async {
    // Confirms TriggerType.humidityThreshold (added in Wave 1) survives
    // export → import via the same _parseTriggerType path used for
    // pre-existing trigger types.
    final tempDir = await Directory.systemTemp
        .createTemp('sequence_file_service_humidity_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath = path.join(tempDir.path, 'humidity.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    final exposure = ExposureNode(
      id: 'exp-1',
      durationSecs: 60,
      count: 3,
    );
    final recovery = RecoveryNode(
      id: 'recov-h',
      triggerType: TriggerType.humidityThreshold,
      triggerThreshold: 85,
      recoveryAction: RecoveryActionType.pause,
      childIds: const ['exp-1'],
    );
    final root = InstructionSetNode(
      id: 'root',
      childIds: const ['recov-h'],
    );
    final sequence = Sequence.create(
      id: 'seq-humid',
      name: 'Humidity trigger round trip',
      rootNodeId: 'root',
      nodes: {
        'root': root,
        'recov-h': recovery.copyWith(parentId: 'root'),
        'exp-1': exposure.copyWith(parentId: 'recov-h'),
      },
    );

    final service = SequenceFileService();
    await service.exportSequence(sequence);
    final imported = await service.importSequence();
    final reloaded = imported!.nodes['recov-h'] as RecoveryNode;
    expect(reloaded.triggerType, TriggerType.humidityThreshold);
    expect(reloaded.triggerThreshold, 85);
    expect(reloaded.recoveryAction, RecoveryActionType.pause);
  });

  test('sequence round-trip preserves TargetScheduler adaptive swap fields',
      () async {
    final tempDir =
        await Directory.systemTemp.createTemp('sequence_file_service_sched_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath = path.join(tempDir.path, 'scheduler.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    final root = InstructionSetNode(
      id: 'root',
      childIds: const ['scheduler'],
    );
    final scheduler = TargetSchedulerNode(
      id: 'scheduler',
      parentId: 'root',
      childIds: const ['target'],
      swapOnConditionsBelow: 46,
      swapHysteresisSecs: 225,
      brightnessTierPreferences: const BrightnessTierPreferences(
        faintMinScore: 76,
        mediumMinScore: 54,
        brightMinScore: 31,
      ),
      maxConditionsScoreAgeSecs: 480,
    );
    final target = TargetHeaderNode(
      id: 'target',
      parentId: 'scheduler',
      targetName: 'M51',
      raHours: 13.5,
      decDegrees: 47.2,
      childIds: const ['smart'],
    );
    final smart = SmartExposureNode(
      id: 'smart',
      parentId: 'target',
      plans: const [
        FilterPlan(
          filterName: 'L',
          count: 2,
          durationSecs: 120,
        ),
      ],
    );
    final sequence = Sequence.create(
      id: 'seq-scheduler',
      name: 'Scheduler',
      rootNodeId: root.id,
      nodes: {
        root.id: root,
        scheduler.id: scheduler,
        target.id: target,
        smart.id: smart,
      },
    );

    final service = SequenceFileService();
    await service.exportSequence(sequence, forceExport: true);
    final imported = await service.importSequence();

    final restored = imported!.nodes['scheduler'] as TargetSchedulerNode;
    expect(restored.swapOnConditionsBelow, 46);
    expect(restored.swapHysteresisSecs, 225);
    expect(restored.maxConditionsScoreAgeSecs, 480);
    expect(restored.brightnessTierPreferences.faintMinScore, 76);
    expect(restored.brightnessTierPreferences.mediumMinScore, 54);
    expect(restored.brightnessTierPreferences.brightMinScore, 31);
  });

  test('exportSequence honours forceExport flag and writes even with errors',
      () async {
    final tempDir = await Directory.systemTemp
        .createTemp('sequence_file_service_export_force_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath = path.join(tempDir.path, 'forced.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    final bad = Sequence.create(id: 'bad', name: 'Empty');
    final service = SequenceFileService();

    await service.exportSequence(bad, forceExport: true);
    expect(await File(filePath).exists(), isTrue,
        reason: 'forceExport=true should bypass the validation gate');
  });
}
