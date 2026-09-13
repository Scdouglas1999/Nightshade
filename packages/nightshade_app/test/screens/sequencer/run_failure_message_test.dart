import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/run_status_presentation.dart';

void main() {
  test('bridge errors show the reason and preserve normal messages', () {
    expect(
        runFailureMessage(
            'Failed to start: NightshadeError.operationFailed(field0: No plate solver (ASTAP) configured)'),
        'Failed to start: No plate solver (ASTAP) configured');
    expect(runFailureMessage('Camera disconnected'), 'Camera disconnected');
    expect(
        runFailureMessage(
            'NightshadeError.operationFailed(field0: Line one\nLine two)'),
        'Line one\nLine two');
  });
}
