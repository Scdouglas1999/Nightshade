import 'dart:io';

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
    final tempDir = await Directory.systemTemp.createTemp('sequence_file_service_');
    addTearDown(() async => tempDir.delete(recursive: true));

    final filePath = path.join(tempDir.path, 'sequence.nseq.json');
    final originalPlatform = FileSelectorPlatform.instance;

    FileSelectorPlatform.instance = TestFileSelectorPlatform(
      openPath: filePath,
      savePath: filePath,
    );
    addTearDown(() => FileSelectorPlatform.instance = originalPlatform);

    final sequence = Sequence(
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
}
