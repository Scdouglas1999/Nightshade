import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

void main() {
  testWidgets('LabelLayer renders snapshot label text', (tester) async {
    final snapshot = SceneSnapshotDto(
      frameId: BigInt.from(1),
      viewPose: ViewPoseDto(
        raRad: 0,
        decRad: 1.5707963267948966,
        fovRad: 1.5707963267948966,
        rollRad: 0,
        projection: SkyProjectionDto.stereographic,
      ),
      labels: [
        LabelHintDto(
          objectId: BigInt.from(246),
          screenX: 120,
          screenY: 180,
          apparentMag: 1.5,
          priority: 200,
          text: 'Sirius',
          category: LabelCategoryDto.star,
        ),
      ],
      constellationArt: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sceneSnapshotProvider.overrideWith(() => _FixedSceneSnapshot(snapshot)),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 640,
            height: 480,
            child: LabelLayer(),
          ),
        ),
      ),
    );

    expect(find.text('Sirius'), findsOneWidget);
  });

  testWidgets('LabelLayer drops overlapping lower-priority labels', (tester) async {
    final snapshot = SceneSnapshotDto(
      frameId: BigInt.from(1),
      viewPose: ViewPoseDto(
        raRad: 0,
        decRad: 1.5707963267948966,
        fovRad: 1.5707963267948966,
        rollRad: 0,
        projection: SkyProjectionDto.stereographic,
      ),
      labels: [
        LabelHintDto(
          objectId: BigInt.from(1),
          screenX: 100,
          screenY: 100,
          apparentMag: 0.5,
          priority: 10,
          text: 'Bright',
          category: LabelCategoryDto.star,
        ),
        LabelHintDto(
          objectId: BigInt.from(2),
          screenX: 102,
          screenY: 102,
          apparentMag: 4,
          priority: 1,
          text: 'Faint',
          category: LabelCategoryDto.star,
        ),
      ],
      constellationArt: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sceneSnapshotProvider.overrideWith(() => _FixedSceneSnapshot(snapshot)),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: LabelLayer(),
          ),
        ),
      ),
    );

    expect(find.text('Bright'), findsOneWidget);
    expect(find.text('Faint'), findsNothing);
  });

  testWidgets('LabelLayer uppercases constellation labels', (tester) async {
    final snapshot = SceneSnapshotDto(
      frameId: BigInt.from(1),
      viewPose: ViewPoseDto(
        raRad: 0,
        decRad: 1.5707963267948966,
        fovRad: 1.5707963267948966,
        rollRad: 0,
        projection: SkyProjectionDto.stereographic,
      ),
      labels: [
        LabelHintDto(
          objectId: BigInt.from(88),
          screenX: 200,
          screenY: 200,
          apparentMag: 0,
          priority: 50,
          text: 'orion',
          category: LabelCategoryDto.constellation,
        ),
      ],
      constellationArt: const [],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sceneSnapshotProvider.overrideWith(() => _FixedSceneSnapshot(snapshot)),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 640,
            height: 480,
            child: LabelLayer(),
          ),
        ),
      ),
    );

    expect(find.text('ORION'), findsOneWidget);
  });
}

class _FixedSceneSnapshot extends SceneSnapshotNotifier {
  _FixedSceneSnapshot(this._snapshot);

  final SceneSnapshotDto _snapshot;

  @override
  SceneSnapshotDto build() => _snapshot;
}
