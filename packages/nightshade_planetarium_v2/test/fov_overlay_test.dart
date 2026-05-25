import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

void main() {
  testWidgets('FovOverlay paints when equipment FOV is available',
      (tester) async {
    const canvasSize = Size(640, 480);
    final snapshot = SceneSnapshotDto(
      frameId: BigInt.from(1),
      viewPose: ViewPoseDto(
        raRad: 5.5 * math.pi / 12,
        decRad: 0,
        fovRad: 60 * math.pi / 180,
        rollRad: 0,
        projection: SkyProjectionDto.stereographic,
      ),
      labels: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sceneSnapshotProvider.overrideWith(() => _FixedSceneSnapshot(snapshot)),
          equipmentFovProvider.overrideWith(
            (ref) => _FixedEquipmentFov(
              ref,
              const EquipmentFovState(
                widthDegrees: 1.2,
                heightDegrees: 0.9,
                rotationDegrees: 15,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 640,
            height: 480,
            child: FovOverlay(),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('fov_overlay_paint')), findsOneWidget);
  });

  testWidgets('FovOverlay hidden when equipment FOV is unknown', (tester) async {
    final snapshot = SceneSnapshotDto(
      frameId: BigInt.from(1),
      viewPose: const ViewPoseDto(
        raRad: 0,
        decRad: 1.5707963267948966,
        fovRad: 1.5707963267948966,
        rollRad: 0,
        projection: SkyProjectionDto.stereographic,
      ),
      labels: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sceneSnapshotProvider.overrideWith(() => _FixedSceneSnapshot(snapshot)),
          equipmentFovProvider.overrideWith(
            (ref) => _FixedEquipmentFov(ref, const EquipmentFovState()),
          ),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: FovOverlay(),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('fov_overlay_paint')), findsNothing);
  });
}

class _FixedSceneSnapshot extends SceneSnapshotNotifier {
  _FixedSceneSnapshot(this._snapshot);

  final SceneSnapshotDto _snapshot;

  @override
  SceneSnapshotDto build() => _snapshot;
}

class _FixedEquipmentFov extends EquipmentFovNotifier {
  _FixedEquipmentFov(Ref ref, EquipmentFovState initial)
      : super(ref, bindSources: false) {
    state = initial;
  }
}
