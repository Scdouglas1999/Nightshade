import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart' hide Sequence;
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/providers/sequence/sequence_executor.dart';
import 'package:nightshade_core/src/providers/sequence/sequencer_defaults.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';

/// Forces appSettingsProvider into a known state without spinning up
/// the real AsyncNotifier (which reads from SQLite).
class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);
  final AppSettingsState _initial;

  @override
  Future<AppSettingsState> build() async => _initial;
}

ProviderContainer _container({
  required bool autoFocusOnFilterChange,
  required int autoFocusEveryMinutes,
  required bool ditherEnabled,
  required int ditherEveryFrames,
}) {
  final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      appSettingsProvider.overrideWith(
        () => _FakeAppSettingsNotifier(
          AppSettingsState(
            autoFocusOnFilterChange: autoFocusOnFilterChange,
            autoFocusEveryMinutes: autoFocusEveryMinutes,
            ditherEnabled: ditherEnabled,
            ditherEveryFrames: ditherEveryFrames,
          ),
        ),
      ),
    ],
  );
  // Why: dispose the container first so any provider that holds a
  // reference to the database can drop it before we close the database
  // itself. Reversing the order triggers "Can't re-open a database
  // after closing it" when async listeners run during dispose.
  addTearDown(() async {
    container.dispose();
    // Let microtasks drain so any pending async listener work finishes
    // before we close the database.
    await Future<void>.delayed(Duration.zero);
    await db.close();
  });
  return container;
}

Sequence _filterThenExposureSequence() {
  // FilterChange -> Exposure -> Exposure (no AF between filter change and
  // exposure). The wire-up should inject an AF synthetic node after the
  // filter change when autoFocusOnFilterChange is true.
  final root = TargetHeaderNode(
    id: 'root',
    name: 'Test target',
    targetName: 'M31',
    raHours: 0,
    decDegrees: 0,
    childIds: ['filter', 'exp1', 'exp2'],
  );
  final filter = FilterChangeNode(
    id: 'filter',
    name: 'Switch to L',
    filterName: 'L',
    parentId: 'root',
  );
  final exp1 = ExposureNode(
    id: 'exp1',
    parentId: 'root',
    durationSecs: 60,
    count: 5,
  );
  final exp2 = ExposureNode(
    id: 'exp2',
    parentId: 'root',
    durationSecs: 60,
    count: 5,
  );
  return Sequence(
    id: 'seq',
    name: 'unit-test',
    rootNodeId: 'root',
    nodes: {
      'root': root,
      'filter': filter,
      'exp1': exp1,
      'exp2': exp2,
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SequenceExecutor._sequenceToJson (§2.1 WIRE-UP #4 / #5)', () {
    test('injects AF node after filter change when toggle is on', () async {
      final container = _container(
        autoFocusOnFilterChange: true,
        autoFocusEveryMinutes: 60,
        ditherEnabled: true,
        ditherEveryFrames: 3,
      );
      await container.read(appSettingsProvider.future);
      // Warm sequencerDefaultsProvider so its async load completes
      // before we serialise. Without this the notifier hasn't finished
      // reading the (empty) settings DAO before the executor reads it.
      container.read(sequencerDefaultsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final executor = container.read(sequenceExecutorProvider);

      final json = executor.sequenceToJsonForTest(_filterThenExposureSequence());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final nodes = (decoded['nodes'] as List).cast<Map<String, dynamic>>();
      final rootNode = nodes.firstWhere((n) => n['id'] == 'root');
      final children = (rootNode['children'] as List).cast<String>();

      // children should now be: filter, af-auto-filter, exp1, exp2.
      expect(children.length, 4);
      expect(children[0], 'filter');
      expect(children[1], 'af-auto-filter');
      expect(children[2], 'exp1');
      expect(children[3], 'exp2');

      // The synthetic AF node must be present at the top level.
      final synthetic = nodes.firstWhere((n) => n['id'] == 'af-auto-filter');
      expect(
        (synthetic['node_type'] as Map<String, dynamic>)['type'],
        'Autofocus',
      );
    });

    test('does not inject AF node when toggle is off', () async {
      final container = _container(
        autoFocusOnFilterChange: false,
        autoFocusEveryMinutes: 60,
        ditherEnabled: true,
        ditherEveryFrames: 3,
      );
      await container.read(appSettingsProvider.future);
      // Warm sequencerDefaultsProvider so its async load completes
      // before we serialise. Without this the notifier hasn't finished
      // reading the (empty) settings DAO before the executor reads it.
      container.read(sequencerDefaultsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final executor = container.read(sequenceExecutorProvider);

      final json = executor.sequenceToJsonForTest(_filterThenExposureSequence());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final nodes = (decoded['nodes'] as List).cast<Map<String, dynamic>>();
      final rootNode = nodes.firstWhere((n) => n['id'] == 'root');
      final children = (rootNode['children'] as List).cast<String>();
      expect(children.length, 3);
      expect(
        nodes.where((n) => (n['id'] as String).startsWith('af-auto-')),
        isEmpty,
      );
    });

    test('metadata carries AF interval and on-filter-change flags', () async {
      final container = _container(
        autoFocusOnFilterChange: true,
        autoFocusEveryMinutes: 45,
        ditherEnabled: true,
        ditherEveryFrames: 3,
      );
      await container.read(appSettingsProvider.future);
      // Warm sequencerDefaultsProvider so its async load completes
      // before we serialise. Without this the notifier hasn't finished
      // reading the (empty) settings DAO before the executor reads it.
      container.read(sequencerDefaultsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final executor = container.read(sequenceExecutorProvider);
      final json = executor.sequenceToJsonForTest(_filterThenExposureSequence());
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final metadata =
          (decoded['metadata'] as Map<String, dynamic>).cast<String, String>();
      expect(metadata['autofocus_every_minutes'], '45');
      expect(metadata['autofocus_on_filter_change'], 'true');
    });

    test(
        'per-node dither_every wins over app-setting fallback',
        () async {
      // The user explicitly set ditherEvery=7 on this exposure; the
      // app-setting default of 3 must NOT override it.
      final root = TargetHeaderNode(
        id: 'root',
        name: 'Test',
        targetName: 'M81',
        raHours: 0,
        decDegrees: 0,
        childIds: ['exp1'],
      );
      final exp1 = ExposureNode(
        id: 'exp1',
        parentId: 'root',
        durationSecs: 60,
        count: 5,
        ditherEvery: 7,
      );
      final sequence = Sequence(
        id: 's',
        name: 't',
        rootNodeId: 'root',
        nodes: {'root': root, 'exp1': exp1},
      );

      final container = _container(
        autoFocusOnFilterChange: false,
        autoFocusEveryMinutes: 0,
        ditherEnabled: true,
        ditherEveryFrames: 3,
      );
      await container.read(appSettingsProvider.future);
      // Warm sequencerDefaultsProvider so its async load completes
      // before we serialise. Without this the notifier hasn't finished
      // reading the (empty) settings DAO before the executor reads it.
      container.read(sequencerDefaultsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final executor = container.read(sequenceExecutorProvider);
      final json = executor.sequenceToJsonForTest(sequence);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final nodes = (decoded['nodes'] as List).cast<Map<String, dynamic>>();
      final exposureNode = nodes.firstWhere((n) => n['id'] == 'exp1');
      final cfg = exposureNode['node_type'] as Map<String, dynamic>;
      expect(cfg['dither_every'], 7);
    });

    test('exposure with no ditherEvery falls back to app-setting default',
        () async {
      final root = TargetHeaderNode(
        id: 'root',
        name: 'Test',
        targetName: 'M81',
        raHours: 0,
        decDegrees: 0,
        childIds: ['exp1'],
      );
      final exp1 = ExposureNode(
        id: 'exp1',
        parentId: 'root',
        durationSecs: 60,
        count: 5,
        ditherEvery: null,
      );
      final sequence = Sequence(
        id: 's',
        name: 't',
        rootNodeId: 'root',
        nodes: {'root': root, 'exp1': exp1},
      );

      final container = _container(
        autoFocusOnFilterChange: false,
        autoFocusEveryMinutes: 0,
        ditherEnabled: true,
        ditherEveryFrames: 4,
      );
      await container.read(appSettingsProvider.future);
      // Warm sequencerDefaultsProvider so its async load completes
      // before we serialise. Without this the notifier hasn't finished
      // reading the (empty) settings DAO before the executor reads it.
      container.read(sequencerDefaultsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final executor = container.read(sequenceExecutorProvider);
      final json = executor.sequenceToJsonForTest(sequence);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final nodes = (decoded['nodes'] as List).cast<Map<String, dynamic>>();
      final exposureNode = nodes.firstWhere((n) => n['id'] == 'exp1');
      final cfg = exposureNode['node_type'] as Map<String, dynamic>;
      expect(cfg['dither_every'], 4);
    });
  });
}
