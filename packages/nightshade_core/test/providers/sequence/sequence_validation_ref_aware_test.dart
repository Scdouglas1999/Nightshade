import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/equipment/equipment_models.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/equipment/camera_state_provider.dart';
import 'package:nightshade_core/src/providers/equipment/filter_wheel_state_provider.dart';
import 'package:nightshade_core/src/providers/equipment/focuser_state_provider.dart';
import 'package:nightshade_core/src/providers/equipment/guider_state_provider.dart';
import 'package:nightshade_core/src/providers/equipment/mount_state_provider.dart';
import 'package:nightshade_core/src/providers/equipment/rotator_state_provider.dart';
import 'package:nightshade_core/src/providers/sequence/rules/equipment_rules.dart';
import 'package:nightshade_core/src/providers/sequence/rules/filter_rules.dart';
import 'package:nightshade_core/src/providers/sequence/rules/settings_rules.dart';
import 'package:nightshade_core/src/providers/sequence/sequence_validation.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';

// Minimal fakes so we can drive the equipment / settings providers from
// tests without touching real device drivers or the on-disk SQLite store.
//
// Each fake StateNotifier is intentionally tiny — just enough surface to
// satisfy the rule under test.

// Tests extend the real notifier classes so they can be returned from
// `overrideWith`, but bypass their constructors (which would touch real
// Riverpod dependencies via the production `Ref`) by passing a fresh
// ProviderContainer-built ref. We don't need any of the notifier's
// production behaviour — only the initial state value.
class _StubCameraNotifier extends CameraStateNotifier {
  _StubCameraNotifier(Ref ref, CameraStateSnapshot initial) : super(ref) {
    state = initial;
  }
}

class _StubMountNotifier extends MountStateNotifier {
  _StubMountNotifier(Ref ref, MountState initial) : super(ref) {
    state = initial;
  }
}

class _StubFocuserNotifier extends FocuserStateNotifier {
  _StubFocuserNotifier(Ref ref, FocuserState initial) : super(ref) {
    state = initial;
  }
}

class _StubFilterWheelNotifier extends FilterWheelStateNotifier {
  _StubFilterWheelNotifier(Ref ref, FilterWheelState initial) : super(ref) {
    state = initial;
  }
}

class _StubGuiderNotifier extends GuiderStateNotifier {
  _StubGuiderNotifier(Ref ref, GuiderState initial) : super(ref) {
    state = initial;
  }
}

class _StubRotatorNotifier extends RotatorStateNotifier {
  _StubRotatorNotifier(Ref ref, RotatorState initial) : super(ref) {
    state = initial;
  }
}

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);
  final AppSettingsState _initial;
  @override
  Future<AppSettingsState> build() async => _initial;
}

/// Drives a closure with a real Riverpod [Ref] so tests can construct a
/// [ValidationContext]. We do not have a `Ref` from `ProviderContainer`
/// directly — they're constructed by provider builds — so wrap the call in
/// an ad-hoc test provider.
T _withRef<T>(ProviderContainer container, T Function(Ref ref) body) {
  final probe = Provider<T>((ref) => body(ref));
  return container.read(probe);
}

/// Build a ProviderContainer with all equipment + settings providers driven
/// from explicit state. Callers supply only the connection state they care
/// about; everything else defaults to disconnected.
ProviderContainer _container({
  DeviceConnectionState camera = DeviceConnectionState.disconnected,
  DeviceConnectionState mount = DeviceConnectionState.disconnected,
  DeviceConnectionState focuser = DeviceConnectionState.disconnected,
  DeviceConnectionState filterWheel = DeviceConnectionState.disconnected,
  DeviceConnectionState guider = DeviceConnectionState.disconnected,
  DeviceConnectionState rotator = DeviceConnectionState.disconnected,
  List<String> filterNames = const [],
  String imageOutputPath = '/tmp/out',
}) {
  final container = ProviderContainer(
    overrides: [
      cameraStateProvider.overrideWith(
        (ref) => _StubCameraNotifier(
            ref, CameraStateSnapshot(connectionState: camera)),
      ),
      mountStateProvider.overrideWith(
        (ref) =>
            _StubMountNotifier(ref, MountState(connectionState: mount)),
      ),
      focuserStateProvider.overrideWith(
        (ref) => _StubFocuserNotifier(
            ref, FocuserState(connectionState: focuser)),
      ),
      filterWheelStateProvider.overrideWith(
        (ref) => _StubFilterWheelNotifier(
          ref,
          FilterWheelState(
            connectionState: filterWheel,
            filterNames: filterNames,
          ),
        ),
      ),
      guiderStateProvider.overrideWith(
        (ref) =>
            _StubGuiderNotifier(ref, GuiderState(connectionState: guider)),
      ),
      rotatorStateProvider.overrideWith(
        (ref) => _StubRotatorNotifier(
            ref, RotatorState(connectionState: rotator)),
      ),
      appSettingsProvider.overrideWith(
        () => _FakeAppSettingsNotifier(
          AppSettingsState(imageOutputPath: imageOutputPath),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Make a sequence with the given children placed under a root container.
Sequence _sequenceWith(List<SequenceNode> children) {
  final root = InstructionSetNode(name: 'Root');
  final nodes = <String, SequenceNode>{root.id: root};
  final ids = <String>[];
  for (final child in children) {
    final placed = child.copyWith(parentId: root.id);
    nodes[placed.id] = placed;
    ids.add(placed.id);
  }
  nodes[root.id] = root.copyWith(childIds: ids);
  return Sequence(
    name: 'T',
    nodes: nodes,
    rootNodeId: root.id,
  );
}

void main() {
  group('EquipmentConnectionRule', () {
    test('fires error when camera is required but not connected', () {
      final container = _container();
      final rule = EquipmentConnectionRule();
      final s = _sequenceWith([ExposureNode()]);
      final issues =
          _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      final cam = issues.firstWhere((i) => i.title == 'No Camera Connected');
      expect(cam.severity, ValidationSeverity.error);
      expect(cam.category, ValidationCategory.equipment);
    });

    test('clean when required device is connected', () {
      final container =
          _container(camera: DeviceConnectionState.connected);
      final rule = EquipmentConnectionRule();
      final s = _sequenceWith([ExposureNode()]);
      final issues =
          _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      expect(issues.where((i) => i.title.contains('Camera')), isEmpty);
    });

    test('emits per-node + summary guider issues when missing', () {
      final container = _container(
        camera: DeviceConnectionState.connected,
        mount: DeviceConnectionState.connected,
      );
      final rule = EquipmentConnectionRule();
      final s = _sequenceWith([
        ExposureNode(),
        StartGuidingNode(),
      ]);
      final issues =
          _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      final guiderIssues =
          issues.where((i) => i.title.contains('Guider')).toList();
      // One summary + one per-node = 2 issues.
      expect(guiderIssues, hasLength(2));
      expect(guiderIssues.any((i) => i.affectedNodeId != null), isTrue);
    });
  });

  group('RotatorRotationConflictRule', () {
    test('fires when target has rotation but rotator is disconnected', () {
      final container = _container();
      final rule = RotatorRotationConflictRule();
      final t = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
        rotation: 90,
      );
      final s = _sequenceWith([t]);
      final issues = _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      expect(issues.single.title, 'Rotator Not Connected');
      expect(issues.single.affectedNodeId, t.id);
    });

    test('clean when rotator is connected', () {
      final container =
          _container(rotator: DeviceConnectionState.connected);
      final rule = RotatorRotationConflictRule();
      final t = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
        rotation: 90,
      );
      final s = _sequenceWith([t]);
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });
  });

  group('FilterInWheelRule', () {
    test('fires when exposure references a filter not in the wheel', () {
      final container = _container(
        filterWheel: DeviceConnectionState.connected,
        filterNames: ['L', 'R', 'G', 'B'],
      );
      final rule = FilterInWheelRule();
      final e = ExposureNode(filter: 'Ha');
      final s = _sequenceWith([e]);
      final issues = _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      expect(issues.single.title, 'Filter Not in Wheel');
      expect(issues.single.affectedNodeId, e.id);
    });

    test('clean when filter is in the wheel', () {
      final container = _container(
        filterWheel: DeviceConnectionState.connected,
        filterNames: ['L', 'R', 'G', 'B'],
      );
      final rule = FilterInWheelRule();
      final e = ExposureNode(filter: 'L');
      final s = _sequenceWith([e]);
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });

    test('emits info when filter wheel is connected but reports no filters',
        () {
      final container =
          _container(filterWheel: DeviceConnectionState.connected);
      final rule = FilterInWheelRule();
      final s = _sequenceWith([ExposureNode(filter: 'L')]);
      final issues = _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      expect(issues.single.title, 'Filter Wheel Reports No Filters');
      expect(issues.single.severity, ValidationSeverity.info);
    });

    test('skips check when filter wheel is disconnected', () {
      final container = _container();
      final rule = FilterInWheelRule();
      final s = _sequenceWith([ExposureNode(filter: 'L')]);
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });
  });

  group('ImageOutputPathRule', () {
    test('fires when no output path is configured and exposures exist',
        () async {
      final container = _container(imageOutputPath: '');
      // Force settings to load
      await container.read(appSettingsProvider.future);
      final rule = ImageOutputPathRule();
      final s = _sequenceWith([ExposureNode()]);
      final issues = _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      expect(issues.single.title, 'No Image Save Path');
      expect(issues.single.severity, ValidationSeverity.warning);
    });

    test('clean when output path is configured', () async {
      final container = _container(imageOutputPath: '/tmp/out');
      await container.read(appSettingsProvider.future);
      final rule = ImageOutputPathRule();
      final s = _sequenceWith([ExposureNode()]);
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });

    test('skips check when sequence has no enabled exposures', () async {
      final container = _container(imageOutputPath: '');
      await container.read(appSettingsProvider.future);
      final rule = ImageOutputPathRule();
      final s = _sequenceWith([SlewNode(useTargetCoords: true)]);
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });
  });

  group('DefaultSequenceNameRule', () {
    test('fires on "Untitled Sequence"', () async {
      final container = _container();
      await container.read(appSettingsProvider.future);
      final rule = DefaultSequenceNameRule();
      final s = Sequence(name: 'Untitled Sequence');
      final issues = _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      expect(issues.single.title, 'Default Sequence Name');
      expect(issues.single.severity, ValidationSeverity.info);
    });

    test('clean on a real name', () async {
      final container = _container();
      await container.read(appSettingsProvider.future);
      final rule = DefaultSequenceNameRule();
      final s = Sequence(name: 'My Run');
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });
  });

  group('LongEstimatedDurationRule', () {
    test('fires when estimatedDurationMins > 600', () async {
      final container = _container();
      await container.read(appSettingsProvider.future);
      final rule = LongEstimatedDurationRule();
      final s = Sequence(name: 'X', estimatedDurationMins: 700);
      final issues = _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      expect(issues.single.title, 'Long Sequence');
    });

    test('clean when no estimate is set', () async {
      final container = _container();
      await container.read(appSettingsProvider.future);
      final rule = LongEstimatedDurationRule();
      final s = Sequence(name: 'X');
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });
  });

  group('MeridianFlipTriggerRule', () {
    test('fires when long sequence has targets but no flip handling',
        () async {
      final container = _container();
      await container.read(appSettingsProvider.future);
      final rule = MeridianFlipTriggerRule();
      final target = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
      );
      // 4 hour run (240 minutes well over the 120 minute threshold)
      final exposure = ExposureNode(durationSecs: 600, count: 24);
      final s = Sequence(
        name: 'X',
        nodes: {
          target.id: target.copyWith(childIds: [exposure.id]),
          exposure.id: exposure.copyWith(parentId: target.id),
        },
        rootNodeId: target.id,
      );
      final issues = _withRef(container, (ref) => rule.validate(s, ValidationContext(ref)));
      expect(issues.single.title, 'No Meridian Flip Trigger');
    });

    test('clean when a MeridianFlipNode is present', () async {
      final container = _container();
      await container.read(appSettingsProvider.future);
      final rule = MeridianFlipTriggerRule();
      final flip = MeridianFlipNode();
      final target = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
      );
      final exposure = ExposureNode(durationSecs: 600, count: 24);
      final s = Sequence(
        name: 'X',
        nodes: {
          target.id: target.copyWith(childIds: [exposure.id]),
          exposure.id: exposure.copyWith(parentId: target.id),
          flip.id: flip,
        },
        rootNodeId: target.id,
      );
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });

    test('clean when run is short', () async {
      final container = _container();
      await container.read(appSettingsProvider.future);
      final rule = MeridianFlipTriggerRule();
      final target = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
      );
      // 30 minute run — below threshold
      final exposure = ExposureNode(durationSecs: 60, count: 30);
      final s = Sequence(
        name: 'X',
        nodes: {
          target.id: target.copyWith(childIds: [exposure.id]),
          exposure.id: exposure.copyWith(parentId: target.id),
        },
        rootNodeId: target.id,
      );
      expect(_withRef(container, (ref) => rule.validate(s, ValidationContext(ref))), isEmpty);
    });
  });
}
