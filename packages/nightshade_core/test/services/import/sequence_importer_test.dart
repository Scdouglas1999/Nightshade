import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/import/canonical_sequence_node.dart';
import 'package:nightshade_core/src/models/import/import_result.dart';
import 'package:nightshade_core/src/services/import/sequence_importer.dart';

void main() {
  group('SequenceImporter', () {
    test('detectFormat returns nina for NINA content', () async {
      final content =
          await File('test/services/import/fixtures/nina_basic.json')
              .readAsString();
      expect(SequenceImporter().detectFormat(content), SourceFormat.nina);
    });

    test('detectFormat returns sgp for SGP content', () async {
      final content =
          await File('test/services/import/fixtures/sgp_basic.sgf')
              .readAsString();
      expect(SequenceImporter().detectFormat(content), SourceFormat.sgp);
    });

    test('detectFormat throws UnknownFormatError for free-form text', () {
      expect(
        () => SequenceImporter().detectFormat('hello world'),
        throwsA(isA<UnknownFormatError>()),
      );
    });

    test('importFromString returns ImportResult for valid NINA file',
        () async {
      final content =
          await File('test/services/import/fixtures/nina_basic.json')
              .readAsString();
      final result = SequenceImporter().importFromString(
        content,
        forceUnsupported: false,
        sequenceName: 'M31 run',
      );
      expect(result.sourceFormat, SourceFormat.nina);
      expect(result.sequence.name, 'M31 run');
      expect(result.sequence.nodes, isNotEmpty);
      expect(result.unsupportedNodes, isEmpty);
      // Mapping table should include TakeExposure -> Exposure.
      final exposureRow = result.mappingTable
          .firstWhere((r) => r.sourceType == 'TakeExposure');
      expect(exposureRow.nightshadeType, 'Exposure');
    });

    test(
        'importFromString throws UnsupportedNodeError in strict mode for files with unsupported nodes',
        () async {
      final content =
          await File('test/services/import/fixtures/nina_unsupported.json')
              .readAsString();
      expect(
        () => SequenceImporter().importFromString(
          content,
          forceUnsupported: false,
          sequenceName: 'x',
        ),
        throwsA(isA<UnsupportedNodeError>()),
      );
    });

    test(
        'importFromString in force-import mode returns a result with forcedImport=true',
        () async {
      final content =
          await File('test/services/import/fixtures/nina_unsupported.json')
              .readAsString();
      final result = SequenceImporter().importFromString(
        content,
        forceUnsupported: true,
        sequenceName: 'forced',
      );
      expect(result.forcedImport, isTrue);
      expect(result.unsupportedNodes, isNotEmpty);
      expect(result.droppedNodes
          .any((d) => d.reason == DropReason.unsupported), isTrue);
      // Supported nodes still made it into the tree.
      expect(result.sequence.nodes.isNotEmpty, isTrue);
    });

    test('importFromString returns SGP result with mapping table', () async {
      final content =
          await File('test/services/import/fixtures/sgp_basic.sgf')
              .readAsString();
      final result = SequenceImporter().importFromString(
        content,
        forceUnsupported: false,
        sequenceName: 'sgp run',
      );
      expect(result.sourceFormat, SourceFormat.sgp);
      expect(result.unsupportedNodes, isEmpty);
      // Two targets in fixture; mapping table must report SgpTarget pairing.
      final targetRow = result.mappingTable
          .firstWhere((r) => r.sourceType == 'SgpTarget');
      expect(targetRow.nightshadeType, 'TargetHeader');
      expect(targetRow.count, 2);
    });

    test('importFromString surfaces MalformedSourceError for invalid JSON', () {
      expect(
        () => SequenceImporter().importFromString(
          '{"\$type": "NINA.Sequencer.X", broken',
          forceUnsupported: false,
          sequenceName: 'bad',
        ),
        throwsA(isA<MalformedSourceError>()),
      );
    });

    test('importFromPath reads file from disk and produces a result',
        () async {
      final result = await SequenceImporter().importFromPath(
        'test/services/import/fixtures/nina_basic.json',
        forceUnsupported: false,
      );
      expect(result.sourceFormat, SourceFormat.nina);
      // Default sequence name comes from the filename stem.
      expect(result.sequence.name, 'nina_basic');
    });

    test('importFromPath throws MalformedSourceError for nonexistent files',
        () async {
      await expectLater(
        SequenceImporter().importFromPath(
          'test/services/import/fixtures/__does_not_exist__.json',
          forceUnsupported: false,
        ),
        throwsA(isA<MalformedSourceError>()),
      );
    });
  });
}
