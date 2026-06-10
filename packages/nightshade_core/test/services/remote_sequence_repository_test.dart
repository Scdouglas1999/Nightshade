import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

void main() {
  group('SequenceRepository.remote', () {
    late _MockNetworkBackend backend;
    late ProviderContainer container;

    setUp(() {
      backend = _MockNetworkBackend();
      container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('loadAllSequences reads host list-full documents', () async {
      when(() => backend.listFullSequences()).thenAnswer(
        (_) async => [
          {
            'schemaVersion': SequenceFileService.currentSchemaVersion,
            'version': '2.0',
            'name': 'Host Sequence',
            'description': '',
            'rootNodeId': 'root-1',
            'isTemplate': false,
            'databaseId': 42,
            'createdAt': DateTime(2026, 1, 1).toIso8601String(),
            'modifiedAt': DateTime(2026, 1, 2).toIso8601String(),
            'nodes': {
              'root-1': {
                'id': 'root-1',
                'nodeType': 'instructionSet',
                'name': 'Sequence',
                'parentId': null,
                'childIds': <String>[],
                'orderIndex': 0,
                'isEnabled': true,
              },
            },
          },
        ],
      );

      final repo = container.read(sequenceRepositoryProvider);
      final sequences = await repo.loadAllSequences();

      expect(sequences, hasLength(1));
      expect(sequences.first.name, 'Host Sequence');
      expect(sequences.first.databaseId, 42);
      verify(() => backend.listFullSequences()).called(1);
    });

    test('saveSequence posts full document to host', () async {
      when(
        () => backend.saveFullSequence(
          any(),
          isTemplate: any(named: 'isTemplate'),
          databaseId: any(named: 'databaseId'),
        ),
      ).thenAnswer((_) async => 7);

      final repo = container.read(sequenceRepositoryProvider);
      const rootId = 'root-save-test';
      final sequence = Sequence.create(
        name: 'Tablet Draft',
        databaseId: null,
        nodes: {rootId: InstructionSetNode(id: rootId, name: 'Sequence')},
        rootNodeId: rootId,
      );

      final id = await repo.saveSequence(sequence);

      expect(id, 7);
      verify(
        () => backend.saveFullSequence(
          any(
            that: predicate<Map<String, dynamic>>(
              (map) => map['name'] == 'Tablet Draft',
            ),
          ),
          isTemplate: false,
          databaseId: null,
        ),
      ).called(1);
    });
  });
}
