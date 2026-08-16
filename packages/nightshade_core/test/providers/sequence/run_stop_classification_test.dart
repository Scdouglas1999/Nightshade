// The operator's Stop arrives on the wire as a sequencer ERROR carrying the
// verbatim notice "Sequence cancelled" (native executor, NodeStatus::Cancelled
// arm). Every surface that reads the raw event stream has to recognise that one
// string — and NOTHING else — or it either cries wolf over a deliberate stop or
// swallows a genuine fault whose text merely contains the word "cancelled".
//
// The counter-inputs below are strings the stack really emits.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/providers/sequence/run_stop_classification.dart';

void main() {
  group('isSequenceCancelledNotice', () {
    test('recognises the notice the executor emits, in either spelling', () {
      expect(isSequenceCancelledNotice(kSequenceCancelledNotice), isTrue);
      expect(isSequenceCancelledNotice('Sequence cancelled'), isTrue);
      expect(isSequenceCancelledNotice('Sequence canceled'), isTrue);
      expect(isSequenceCancelledNotice('  sequence CANCELLED  '), isTrue);
    });

    // A substring test on "cancelled" swallows every one of these, so a night
    // with a real fault reports no errors at all.
    test('a real fault whose text contains "cancelled" is NOT a stop', () {
      const realFaults = <String>[
        // native/.../instructions/temperature_compensation.rs
        'Temperature compensation cancelled',
        // native/.../executor/preflight.rs documents this mid-run failure
        'Cancelled: Target',
        'focuser move was canceled by the driver',
        'slew canceled by the mount (limit switch)',
        'Autofocus cancelled: star lost',
        'Sequence cancelled by the dome roof interlock',
      ];
      for (final fault in realFaults) {
        expect(
          isSequenceCancelledNotice(fault),
          isFalse,
          reason: 'a fault must survive: $fault',
        );
      }
    });

    test('an unrelated failure is not a stop', () {
      expect(isSequenceCancelledNotice('Camera disconnected'), isFalse);
      expect(isSequenceCancelledNotice(''), isFalse);
    });
  });
}
