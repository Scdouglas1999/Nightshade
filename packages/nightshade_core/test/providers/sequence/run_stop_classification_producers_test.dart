// WD-SEQ-N1, third strike on the two-implementations trap.
//
// An operator Stop reaches Dart as a sequencer `Error` carrying "Sequence
// cancelled". FIVE producers turned that into an error message, and each fix
// wave patched one of them:
//
//   1. NotificationEventClassifier          -> "Sequence failed" toast + push
//   2. SequenceExecutor._handleSequencerEvent -> rollup "Error: …", red node
//   2b. applySequencerEventToSequenceProviders -> the SAME rollup message,
//       from a second live subscriber on the same desktop host
//   3. runDashboardCriticalEventsBridge      -> "Critical · Sequencer" toast,
//       Dashboard banner, RECENT EVENTS row
//
// Producer 2 and 2b are the pair that made the last fix invisible: the
// executor's handler was corrected while the DeviceService-driven pump — which
// is subscribed from app start and handles the identical event — kept writing
// "Error: Sequence cancelled" into the same provider the target rollup reads.
//
// This file pins the behaviour of 2b directly and, for the handlers that need a
// whole executor to exercise, asserts structurally that every `case 'Error'` in
// the sequence providers consults the ONE shared predicate. If someone adds a
// third handler, or deletes the guard from one, this fails.

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

NightshadeEvent _sequencerError(String message) => NightshadeEvent(
  timestamp: DateTime.now().millisecondsSinceEpoch,
  severity: EventSeverity.error,
  category: EventCategory.sequencer,
  eventType: 'Error',
  data: {'message': message},
);

void main() {
  group('the DeviceService-driven pump (producer 2b)', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('an operator stop does not become "Error: Sequence cancelled"', () {
      applySequencerEventToSequenceProviders(
        container.read,
        _sequencerError(kSequenceCancelledNotice),
      );

      final message = container.read(sequenceProgressProvider).message;
      expect(message, kSequenceStoppedByRequestMessage);
      expect(message, isNot(contains('Error')));
    });

    test('a real fault is still reported as an error', () {
      applySequencerEventToSequenceProviders(
        container.read,
        _sequencerError('Temperature compensation cancelled'),
      );

      expect(
        container.read(sequenceProgressProvider).message,
        'Error: Temperature compensation cancelled',
      );
    });
  });

  // Structural guard for the implementations a unit test cannot reach cheaply.
  // Both files below own a `case 'Error':` for the SAME wire event.
  test('every sequencer-Error handler consults the shared predicate', () {
    const handlers = <String>[
      'lib/src/providers/sequence/sequence_progress.dart',
      'lib/src/providers/sequence/sequence_executor/event_operations.dart',
    ];
    for (final path in handlers) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains("case 'Error':"),
        reason:
            '$path no longer handles the sequencer Error event — if the '
            'handler moved, move this pin with it.',
      );
      expect(
        source,
        contains('isSequenceCancelledNotice('),
        reason:
            '$path handles a sequencer Error without asking whether it is '
            'the operator\'s Stop. That is the defect WD-SEQ-N1 keeps '
            'reopening: one producer fixed, the other still crying wolf.',
      );
    }
  });
}
