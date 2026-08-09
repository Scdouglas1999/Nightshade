import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/sequencer_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

class _MockSequencerBackend extends Mock implements SequencerBackend {}

class _MockSequenceExecutor extends Mock implements SequenceExecutor {}

/// The native `SequenceDefinition` wire shape produced by
/// `SequenceExecutor._sequenceToJson` and consumed by `sequencerLoadJson`.
String wireSequence({
  required double raHours,
  required double decDegrees,
  bool exposureEnabled = true,
  bool targetEnabled = true,
}) => jsonEncode({
  'id': 'seq-1',
  'name': 'Remote run',
  'description': '',
  'root_node_id': 'root',
  'metadata': const <String, String>{},
  'nodes': [
    {
      'id': 'root',
      'name': 'Sequence',
      'node_type': {'type': 'Loop', 'iterations': 1, 'condition': 'Count'},
      'enabled': true,
      'children': ['target'],
    },
    {
      'id': 'target',
      'name': 'M31',
      'node_type': {
        'type': 'TargetHeader',
        'target_name': 'M31',
        'ra_hours': raHours,
        'dec_degrees': decDegrees,
      },
      'enabled': targetEnabled,
      'children': ['expose'],
    },
    {
      'id': 'expose',
      'name': 'Take Exposure',
      'node_type': {'type': 'TakeExposure', 'duration': 60.0},
      'enabled': exposureEnabled,
      'children': const <String>[],
    },
  ],
});

Future<Response> postLoad(SequencerHandlers handlers, String wireJson) =>
    translateHandlerErrors(
      handlers.handleSequencerLoad(
        Request(
          'POST',
          Uri.parse('http://localhost/api/sequencer/load'),
          body: jsonEncode({'json': wireJson}),
        ),
      ),
    );

Sequence placeholderTargetSequence() {
  final target = TargetHeaderNode(
    id: 'target',
    name: 'M31',
    targetName: 'M31',
    raHours: 0,
    decDegrees: 0,
    parentId: 'root',
    childIds: const ['expose'],
  );
  final expose = ExposureNode(
    id: 'expose',
    name: 'Take Exposure',
    parentId: 'target',
    durationSecs: 60,
  );
  final root = InstructionSetNode(
    id: 'root',
    name: 'Sequence',
    childIds: const ['target'],
  );
  return Sequence.create(
    name: 'Interrupted run',
    nodes: {'root': root, 'target': target, 'expose': expose},
    rootNodeId: 'root',
  );
}

void main() {
  group('POST /api/sequencer/load pre-flight', () {
    late ProviderContainer container;
    late _MockSequencerBackend backend;
    late SequencerHandlers handlers;

    setUp(() {
      backend = _MockSequencerBackend();
      when(() => backend.sequencerLoadJson(any())).thenAnswer((_) async {});
      container = createHeadlessTestContainer(
        overrides: [sequencerBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(container.dispose);
      handlers = SequencerHandlers(container);
    });

    test('accepts a target with real coordinates', () async {
      final response = await postLoad(
        handlers,
        wireSequence(raHours: 0.712, decDegrees: 41.27),
      );

      expect(response.statusCode, HttpStatus.ok);
      verify(() => backend.sequencerLoadJson(any())).called(1);
    });

    test(
      'refuses a live target still on the RA 0h / Dec +0 placeholder and never '
      'loads it',
      () async {
        final response = await postLoad(
          handlers,
          wireSequence(raHours: 0, decDegrees: 0),
        );

        expect(response.statusCode, HttpStatus.badRequest);
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], 'sequence_validation_failed');
        expect(body['errorCount'], 1);
        final issues = body['issues'] as List;
        expect(issues.single, containsPair('code', 'target_coordinates_unset'));
        expect(issues.single, containsPair('affectedNodeId', 'target'));
        // The whole point: the bad tree never reaches the native executor, so
        // the bare start path has nothing wrong to run.
        verifyNever(() => backend.sequencerLoadJson(any()));
      },
    );

    test(
      'a placeholder target nothing enabled consumes warns but still loads',
      () async {
        final response = await postLoad(
          handlers,
          wireSequence(raHours: 0, decDegrees: 0, exposureEnabled: false),
        );

        expect(response.statusCode, HttpStatus.ok);
        verify(() => backend.sequencerLoadJson(any())).called(1);
      },
    );

    test('refuses out-of-range and non-numeric coordinates', () async {
      for (final target in [
        {'ra_hours': 25.0, 'dec_degrees': 41.0},
        {'ra_hours': -1.0, 'dec_degrees': 41.0},
        {'ra_hours': 3.0, 'dec_degrees': 91.0},
        {'ra_hours': 3.0},
      ]) {
        final response = await postLoad(
          handlers,
          jsonEncode({
            'root_node_id': 'root',
            'nodes': [
              {
                'id': 'root',
                'name': 'Sequence',
                'node_type': {'type': 'Loop'},
                'enabled': true,
                'children': ['target'],
              },
              {
                'id': 'target',
                'name': 'T',
                'node_type': {
                  'type': 'TargetHeader',
                  'target_name': 'T',
                  ...target,
                },
                'enabled': true,
                'children': const <String>[],
              },
            ],
          }),
        );
        expect(response.statusCode, HttpStatus.badRequest, reason: '$target');
      }
      verifyNever(() => backend.sequencerLoadJson(any()));
    });

    test('refuses a tree whose child ids or root do not resolve', () async {
      final dangling = jsonEncode({
        'root_node_id': 'root',
        'nodes': [
          {
            'id': 'root',
            'name': 'Sequence',
            'node_type': {'type': 'Loop'},
            'enabled': true,
            'children': ['ghost'],
          },
        ],
      });
      final rootless = jsonEncode({
        'root_node_id': 'nowhere',
        'nodes': const <Object>[],
      });

      for (final payload in [dangling, rootless]) {
        final response = await postLoad(handlers, payload);
        expect(response.statusCode, HttpStatus.badRequest);
      }
      verifyNever(() => backend.sequencerLoadJson(any()));
    });
  });

  group('POST /api/sequencer/checkpoint/resume pre-flight', () {
    late _MockSequencerBackend backend;
    late _MockSequenceExecutor executor;

    setUp(() {
      backend = _MockSequencerBackend();
      executor = _MockSequenceExecutor();
      when(() => executor.resumeFromCheckpoint()).thenAnswer((_) async {});
      when(() => backend.getCheckpointInfo()).thenAnswer(
        (_) async => CheckpointInfo(
          sequenceName: 'Interrupted run',
          timestamp: DateTime.now(),
          completedExposures: 3,
          completedIntegrationSecs: 180,
          canResume: true,
          ageSeconds: 60,
        ),
      );
    });

    ProviderContainer containerFor() {
      final container = createHeadlessTestContainer(
        overrides: [
          sequencerBackendProvider.overrideWithValue(backend),
          sequenceExecutorProvider.overrideWithValue(executor),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    Future<Response> postResume(SequencerHandlers handlers) =>
        translateHandlerErrors(
          handlers.handleSequencerResumeFromCheckpoint(
            Request(
              'POST',
              Uri.parse('http://localhost/api/sequencer/checkpoint/resume'),
            ),
          ),
        );

    test(
      'refuses to resume a stored checkpoint whose target has no coordinates',
      () async {
        final container = containerFor();
        final snapshot = jsonEncode(
          container
              .read(sequenceFileServiceProvider)
              .sequenceToMap(placeholderTargetSequence()),
        );
        await container
            .read(sequenceRunsDaoProvider)
            .startRun(
              sequenceId: null,
              sequenceName: 'Interrupted run',
              sequenceSnapshotJson: snapshot,
            );

        final response = await postResume(SequencerHandlers(container));

        expect(response.statusCode, HttpStatus.badRequest);
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error'], 'sequence_validation_failed');
        expect(
          (body['issues'] as List).single,
          containsPair('code', 'target_coordinates_unset'),
        );
        verifyNever(() => executor.resumeFromCheckpoint());
      },
    );

    test('resumes a checkpoint whose target is pointed somewhere', () async {
      final container = containerFor();
      final good = placeholderTargetSequence().copyWith(
        nodes: {
          ...placeholderTargetSequence().nodes,
          'target':
              (placeholderTargetSequence().nodes['target'] as TargetHeaderNode)
                  .copyWith(raHours: 0.712, decDegrees: 41.27),
        },
      );
      final snapshot = jsonEncode(
        container.read(sequenceFileServiceProvider).sequenceToMap(good),
      );
      await container
          .read(sequenceRunsDaoProvider)
          .startRun(
            sequenceId: null,
            sequenceName: 'Interrupted run',
            sequenceSnapshotJson: snapshot,
          );

      final response = await postResume(SequencerHandlers(container));

      expect(response.statusCode, HttpStatus.ok);
      verify(() => executor.resumeFromCheckpoint()).called(1);
    });

    test(
      'resumes when no snapshot survives — never blocks on bookkeeping',
      () async {
        final container = containerFor();

        final response = await postResume(SequencerHandlers(container));

        expect(response.statusCode, HttpStatus.ok);
        verify(() => executor.resumeFromCheckpoint()).called(1);
      },
    );
  });
}
