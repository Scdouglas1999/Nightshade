import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/src/backend/bridge_event_mapper.dart';
import 'package:nightshade_core/src/models/backend/event_types.dart' as core;

void main() {
  group('bridgeEventFromCoreEvent', () {
    test('reconstructs RecoveryStarted typed sequencer payload', () {
      final now = DateTime.utc(2026, 5, 23, 12);
      final coreEvent = core.NightshadeEvent(
        timestamp: now.millisecondsSinceEpoch,
        severity: core.EventSeverity.critical,
        category: core.EventCategory.sequencer,
        eventType: 'RecoveryStarted',
        data: recoveryFieldsFromTyped(
          startedAtIso: now.toIso8601String(),
          causeKind: 'GuideStarLost',
          causeCustomLabel: null,
          lastAttemptAtIso: now.toIso8601String(),
          attemptCount: 1,
          maxAttempts: 9,
          retryIntervalSecs: 600.0,
          maxDurationSecs: 5400.0,
          phase: 'Waiting',
          lastError: 'star lost',
        ),
      );

      final bridgeEvent = bridgeEventFromCoreEvent(coreEvent);
      expect(bridgeEvent.category, bridge.EventCategory.sequencer);
      expect(bridgeEvent.payload, isA<bridge.EventPayload_Sequencer>());

      final inner =
          (bridgeEvent.payload as bridge.EventPayload_Sequencer).field0;
      expect(inner, isA<bridge.SequencerEvent_RecoveryStarted>());
      final recovery = inner as bridge.SequencerEvent_RecoveryStarted;
      expect(recovery.causeKind, 'GuideStarLost');
      expect(recovery.attemptCount, 1);
      expect(recovery.maxAttempts, 9);
      expect(recovery.phase, 'Waiting');
      expect(recovery.lastError, 'star lost');
    });

    test('reconstructs RecoveryGaveUp with aborted_by_user flag', () {
      final now = DateTime.utc(2026, 5, 23, 12, 30);
      final coreEvent = core.NightshadeEvent(
        timestamp: now.millisecondsSinceEpoch,
        severity: core.EventSeverity.critical,
        category: core.EventCategory.sequencer,
        eventType: 'RecoveryGaveUp',
        data: recoveryFieldsFromTyped(
          startedAtIso: now.toIso8601String(),
          causeKind: 'SlewFailed',
          causeCustomLabel: null,
          lastAttemptAtIso: now.toIso8601String(),
          attemptCount: 3,
          maxAttempts: 3,
          retryIntervalSecs: 120.0,
          maxDurationSecs: 3600.0,
          phase: 'GaveUp',
          lastError: 'timeout',
          abortedByUser: true,
        ),
      );

      final bridgeEvent = bridgeEventFromCoreEvent(coreEvent);
      final inner =
          (bridgeEvent.payload as bridge.EventPayload_Sequencer).field0;
      expect(inner, isA<bridge.SequencerEvent_RecoveryGaveUp>());
      final gaveUp = inner as bridge.SequencerEvent_RecoveryGaveUp;
      expect(gaveUp.abortedByUser, isTrue);
      expect(gaveUp.causeKind, 'SlewFailed');
    });

    test('reconstructs guiding lost-star for scheduler triggers', () {
      const coreEvent = core.NightshadeEvent(
        timestamp: 1,
        severity: core.EventSeverity.warning,
        category: core.EventCategory.guiding,
        eventType: 'StarLost',
        data: {},
      );

      final bridgeEvent = bridgeEventFromCoreEvent(coreEvent);
      final inner = (bridgeEvent.payload as bridge.EventPayload_Guiding).field0;
      expect(inner, isA<bridge.GuidingEvent_LostStar>());
    });

    test('reconstructs mount park completed for scheduler triggers', () {
      const coreEvent = core.NightshadeEvent(
        timestamp: 1,
        severity: core.EventSeverity.info,
        category: core.EventCategory.equipment,
        eventType: 'MountParkCompleted',
        data: {},
      );

      final bridgeEvent = bridgeEventFromCoreEvent(coreEvent);
      final inner =
          (bridgeEvent.payload as bridge.EventPayload_Equipment).field0;
      expect(inner, isA<bridge.EquipmentEvent_MountParkCompleted>());
    });
  });
}
