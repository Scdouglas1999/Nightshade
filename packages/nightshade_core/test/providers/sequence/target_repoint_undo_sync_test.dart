// Wave E refutation of SEQ-13: the builder→catalog re-point sync was hung off
// `updateNode` ONLY, and undo()/redo() restore a whole Sequence snapshot
// without going through it.
//
// So Ctrl+Z reached the identical two-copies divergence SEQ-13 was raised for —
// and worse, the STALE copy became the one the operator never confirmed: the
// builder card reads the restored coordinates while the scheduler keeps scoring
// the ones that were just undone.
//
// The refuter's exact counter-input is pinned below: re-point M42-TEST
// 5.5885 h / −5.39° → 21.42 h / −35.0° (catalog follows), then undo().
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/targets_dao.dart';
import 'package:nightshade_core/src/database/database.dart'
    show NightshadeDatabase, Target;
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/providers/sequence/sequence_editor.dart';

final _refProvider = Provider<Ref>((ref) => ref);

Sequence _sequenceWithTarget(TargetHeaderNode target) {
  const rootId = 'root';
  return Sequence.create(
    name: 'Plan',
    nodes: {
      rootId: InstructionSetNode(
        id: rootId,
        name: 'Sequence',
        childIds: [target.id],
      ),
      target.id: target,
    },
    rootNodeId: rootId,
  );
}

void main() {
  late NightshadeDatabase db;
  late ProviderContainer container;
  late CurrentSequenceNotifier editor;
  late TargetsDao dao;
  late int rowId;

  final original = TargetHeaderNode(
    id: 't1',
    name: 'M42-TEST',
    targetName: 'M42-TEST',
    raHours: 5.5885,
    decDegrees: -5.39,
  );

  setUp(() async {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    dao = container.read(targetsDaoProvider);
    rowId = await dao.findOrCreateByName(
      name: 'M42-TEST',
      raHours: 5.5885,
      decDegrees: -5.39,
    );
    editor = CurrentSequenceNotifier(ref: container.read(_refProvider));
    editor.loadSequence(_sequenceWithTarget(original));
  });

  tearDown(() async {
    editor.dispose();
    container.dispose();
    await db.close();
  });

  Future<Target> row() async => (await dao.getTargetById(rowId))!;

  test('undo puts the catalog row back where the builder points', () async {
    editor.updateNode(original.copyWith(raHours: 21.42, decDegrees: -35.0));
    await pumpEventQueue();
    expect(
      (await row()).ra,
      closeTo(21.42, 1e-9),
      reason: 'the edit itself still syncs (SEQ-13 proper)',
    );

    editor.undo();
    await pumpEventQueue();

    final node = editor.state!.nodes['t1']! as TargetHeaderNode;
    expect(node.raHours, closeTo(5.5885, 1e-9));
    expect(
      (await row()).ra,
      closeTo(5.5885, 1e-9),
      reason:
          'Ctrl+Z is a re-point too: the scheduler scores the catalog row, so '
          'leaving it at the undone coordinates recreates the exact divergence '
          'SEQ-13 was raised for — with the stale copy now the one the '
          'operator never confirmed',
    );
    expect((await row()).dec, closeTo(-5.39, 1e-9));
  });

  test('redo re-applies the re-point to the catalog too', () async {
    editor.updateNode(original.copyWith(raHours: 21.42, decDegrees: -35.0));
    await pumpEventQueue();
    editor.undo();
    await pumpEventQueue();

    editor.redo();
    await pumpEventQueue();

    final node = editor.state!.nodes['t1']! as TargetHeaderNode;
    expect(node.raHours, closeTo(21.42, 1e-9));
    expect((await row()).ra, closeTo(21.42, 1e-9));
    expect((await row()).dec, closeTo(-35.0, 1e-9));
  });

  test('an undo that does not move a target writes nothing', () async {
    final before = (await row()).updatedAt;
    editor.updateNode(original.copyWith(priority: 9));
    await pumpEventQueue();

    editor.undo();
    await pumpEventQueue();

    final after = await row();
    expect(after.ra, closeTo(5.5885, 1e-9));
    expect(
      after.updatedAt,
      before,
      reason: 'undoing a priority edit is not a re-point',
    );
  });
}
