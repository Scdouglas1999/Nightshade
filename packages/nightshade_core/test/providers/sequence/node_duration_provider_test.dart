import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/sequence/node_duration_provider.dart';
import 'package:nightshade_core/src/providers/sequence_provider.dart';

/// Tests for the tree-row "~2h 14m" rollup provider.
///
/// The provider is meant to mirror [Sequence.estimateWithOverhead] but
/// produce per-node values. We assert against hand-computed sums so a
/// future change to the underlying math has to come look at this file.

ProviderContainer _containerWith(Sequence sequence) {
  // Seed the real notifier so we don't have to mock its public surface.
  // It takes a nullable Ref; passing null is fine for these read-only
  // tests (the notifier only consults Ref to guard mutations).
  final container = ProviderContainer(overrides: [
    currentSequenceProvider.overrideWith(
      (ref) {
        final notifier = CurrentSequenceNotifier();
        // ignore: invalid_use_of_protected_member
        notifier.state = sequence;
        return notifier;
      },
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

Sequence _seq(SequenceNode root, Map<String, SequenceNode> nodes) {
  return Sequence(
    name: 'test',
    nodes: nodes,
    rootNodeId: root.id,
  );
}

void main() {
  group('formatRollupDuration', () {
    test('zero shows <1s', () {
      expect(formatRollupDuration(Duration.zero), '<1s');
      expect(formatRollupDuration(const Duration(milliseconds: 1)), '<1s');
    });

    test('seconds-only', () {
      expect(formatRollupDuration(const Duration(seconds: 45)), '~45s');
    });

    test('minutes + seconds', () {
      expect(
        formatRollupDuration(const Duration(minutes: 14, seconds: 30)),
        '~14m 30s',
      );
    });

    test('hours + minutes', () {
      expect(
        formatRollupDuration(const Duration(hours: 2, minutes: 14)),
        '~2h 14m',
      );
    });
  });

  group('nodeRollupDurationProvider', () {
    test('returns zero when no sequence is loaded', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final d = container.read(nodeRollupDurationProvider('any-id'));
      expect(d, Duration.zero);
    });

    test('Target -> Loop(count:3) -> Exposure sums correctly', () {
      // 60s exposure × 4 frames = 240s integration + 4×3s download = 252s
      // per loop iteration. Loop count = 3 -> 756s. Target rollup wraps
      // the loop -> 756s. (No leaf overhead because Exposure overhead is
      // already baked into the per-exposure download.)
      final expo = ExposureNode(
        name: 'Lum',
        durationSecs: 60,
        count: 4,
      );
      final loop = LoopNode(
        name: 'Loop',
        repeatCount: 3,
        conditionType: LoopConditionType.count,
      );
      final target = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
      );
      final root = InstructionSetNode(name: 'Root');

      // Wire up the tree.
      final tree = <String, SequenceNode>{
        expo.id: expo.copyWith(parentId: loop.id),
        loop.id: loop.copyWith(parentId: target.id, childIds: [expo.id]),
        target.id: target.copyWith(parentId: root.id, childIds: [loop.id]),
        root.id: root.copyWith(childIds: [target.id]),
      };
      final container = _containerWith(_seq(root, tree));

      final expoSecs = 60 * 4 + 3.0 * 4; // 252
      expect(
        container
            .read(nodeRollupDurationProvider(expo.id))
            .inSeconds,
        expoSecs.round(),
      );
      expect(
        container
            .read(nodeRollupDurationProvider(loop.id))
            .inSeconds,
        (expoSecs * 3).round(),
      );
      expect(
        container
            .read(nodeRollupDurationProvider(target.id))
            .inSeconds,
        (expoSecs * 3).round(),
      );
    });

    test('Parallel returns max(children), not sum', () {
      // Two exposures, one 30s×1 (33s), one 60s×1 (63s). Parallel should
      // report 63s (the slower child), not 96s.
      final fast = ExposureNode(durationSecs: 30, count: 1, name: 'fast');
      final slow = ExposureNode(durationSecs: 60, count: 1, name: 'slow');
      final parallel = ParallelNode(name: 'p');
      final root = InstructionSetNode(name: 'Root');

      final tree = <String, SequenceNode>{
        fast.id: fast.copyWith(parentId: parallel.id),
        slow.id: slow.copyWith(parentId: parallel.id),
        parallel.id:
            parallel.copyWith(parentId: root.id, childIds: [fast.id, slow.id]),
        root.id: root.copyWith(childIds: [parallel.id]),
      };
      final container = _containerWith(_seq(root, tree));

      final parallelSecs =
          container.read(nodeRollupDurationProvider(parallel.id)).inSeconds;
      // Expected: max(33, 63) = 63
      expect(parallelSecs, 63);
    });

    test('disabled nodes contribute zero', () {
      final disabled =
          ExposureNode(durationSecs: 60, count: 4, name: 'off', isEnabled: false);
      final enabled = ExposureNode(durationSecs: 30, count: 2, name: 'on');
      final set = InstructionSetNode(name: 'set');
      final root = InstructionSetNode(name: 'Root');

      final tree = <String, SequenceNode>{
        disabled.id: disabled.copyWith(parentId: set.id),
        enabled.id: enabled.copyWith(parentId: set.id),
        set.id: set
            .copyWith(parentId: root.id, childIds: [disabled.id, enabled.id]),
        root.id: root.copyWith(childIds: [set.id]),
      };
      final container = _containerWith(_seq(root, tree));

      final setSecs =
          container.read(nodeRollupDurationProvider(set.id)).inSeconds;
      // Expected: enabled-only = 30×2 + 3×2 = 66s
      expect(setSecs, 66);
    });

    test('unbounded loop reports single-iteration duration', () {
      final expo = ExposureNode(durationSecs: 10, count: 1, name: 'expo');
      final loop = LoopNode(
        name: 'Forever',
        conditionType: LoopConditionType.forever,
      );
      final root = InstructionSetNode(name: 'Root');

      final tree = <String, SequenceNode>{
        expo.id: expo.copyWith(parentId: loop.id),
        loop.id: loop.copyWith(parentId: root.id, childIds: [expo.id]),
        root.id: root.copyWith(childIds: [loop.id]),
      };
      final container = _containerWith(_seq(root, tree));

      // Single iteration: 10 + 3 = 13s. No multiplier for unbounded.
      expect(
        container.read(nodeRollupDurationProvider(loop.id)).inSeconds,
        13,
      );
    });
  });
}
