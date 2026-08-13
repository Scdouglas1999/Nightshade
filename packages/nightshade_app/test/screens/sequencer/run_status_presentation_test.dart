/// SEQ-6 / STATE-VOCAB: a run the operator stopped WHILE IT WAS RUNNING was
/// reported as "paused-stopped" — a raw state-machine token, and a false claim
/// about what happened (the log shows Resumed, then Stopping). The token means
/// "stopped, checkpoint kept", which is about resumability.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/run_status_presentation.dart';

void main() {
  test('the resumable stop reads as a stop, not as a pause', () {
    expect(runStatusLabel('paused-stopped'), 'Stopped (resumable)');
    expect(runStatusLabel('paused-stopped'), isNot(contains('paused')));
  });

  test('every status the executor durably writes has product English', () {
    const durable = {
      'completed': 'Completed',
      'failed': 'Failed',
      'aborted': 'Aborted',
      'stopped': 'Stopped',
      'paused-stopped': 'Stopped (resumable)',
      'interrupted': 'Interrupted',
      'running': 'Running',
      'paused': 'Paused',
    };
    durable.forEach((status, label) {
      expect(runStatusLabel(status), label);
    });
  });

  test('an unmapped status degrades to something readable', () {
    expect(runStatusLabel('half_way-there'), 'Half way there');
    expect(runStatusLabel(''), 'Unknown');
  });
}
