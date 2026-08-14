// An operator's Stop is not a failure. The classifier used to map the
// `Stopped` and `Error` sequencer events to the same `sequenceFailed`
// category, so pressing Stop raised "Sequence failed" banners and a
// critical-priority phone push — the cry-wolf shape at its purest: the app
// alarming about an action the operator just took on purpose.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/backend/event_types.dart';
import 'package:nightshade_core/src/models/notification/notification_categories.dart';
import 'package:nightshade_core/src/services/notification/event_classifier.dart';

NightshadeEvent _sequencer(String eventType) => NightshadeEvent(
  timestamp: DateTime.now().millisecondsSinceEpoch,
  severity: EventSeverity.info,
  category: EventCategory.sequencer,
  eventType: eventType,
  data: const {},
);

void main() {
  test('an operator Stop classifies as stopped, not failed', () {
    final classified = NotificationEventClassifier.classify(
      _sequencer('Stopped'),
    );
    expect(classified?.category, NotificationCategory.sequenceStopped);
  });

  test('a stopped sequence is neither critical nor an error', () {
    expect(NotificationCategory.sequenceStopped.isCritical, isFalse);
    expect(
      NotificationCategory.sequenceStopped.defaultSeverity,
      EventSeverity.info,
    );
  });

  test('a real Error still classifies as failed and critical', () {
    final classified = NotificationEventClassifier.classify(
      _sequencer('Error'),
    );
    expect(classified?.category, NotificationCategory.sequenceFailed);
    expect(NotificationCategory.sequenceFailed.isCritical, isTrue);
  });

  // Wave E: the Stop the operator presses does NOT reach this classifier as
  // `Stopped`. The native executor emits `Error { message: "Sequence cancelled" }`
  // first, and that is what produced the red "Sequence failed / Sequence
  // aborted at …" toast at the same second as a Session Report titled
  // "Stopped (resumable)".
  test(
    'the cancellation notice arriving as an Error classifies as stopped',
    () {
      final classified = NotificationEventClassifier.classify(
        _sequencerWithData('Error', const {'message': 'Sequence cancelled'}),
      );
      expect(classified?.category, NotificationCategory.sequenceStopped);
    },
  );

  test('a fault whose text contains "cancelled" is still a failure', () {
    final classified = NotificationEventClassifier.classify(
      _sequencerWithData('Error', const {
        'message': 'Temperature compensation cancelled',
      }),
    );
    expect(classified?.category, NotificationCategory.sequenceFailed);
  });
}

NightshadeEvent _sequencerWithData(
  String eventType,
  Map<String, dynamic> data,
) => NightshadeEvent(
  timestamp: DateTime.now().millisecondsSinceEpoch,
  severity: EventSeverity.error,
  category: EventCategory.sequencer,
  eventType: eventType,
  data: data,
);
