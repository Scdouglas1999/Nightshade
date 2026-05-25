import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

void main() {
  testWidgets('ConstellationArtLayer paints when placements are provided',
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
          constellationArtPlacementsProvider.overrideWithValue([
            const ConstellationArtPlacementDto(
              abbreviation: 'Ori',
              screenX: 320,
              screenY: 240,
            ),
          ]),
          renderConfigProvider.overrideWith(
            (ref) => _ShowConstellationArtConfig(),
          ),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 640,
            height: 480,
            child: ConstellationArtLayer(),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('constellation_art_layer_paint')), findsOneWidget);
  });

  testWidgets('ConstellationArtLayer hidden when art toggle is off',
      (tester) async {
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
          constellationArtPlacementsProvider.overrideWithValue([
            const ConstellationArtPlacementDto(
              abbreviation: 'Ori',
              screenX: 200,
              screenY: 200,
            ),
          ]),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: ConstellationArtLayer(),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('constellation_art_layer_paint')), findsNothing);
  });

  testWidgets('ConstellationArtLayer empty when placements list is empty',
      (tester) async {
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
          renderConfigProvider.overrideWith(
            (ref) => _ShowConstellationArtConfig(),
          ),
        ],
        child: const MaterialApp(
          home: SizedBox(
            width: 640,
            height: 480,
            child: ConstellationArtLayer(),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('constellation_art_layer_paint')), findsNothing);
  });
}

class _FixedSceneSnapshot extends SceneSnapshotNotifier {
  _FixedSceneSnapshot(this._snapshot);

  final SceneSnapshotDto _snapshot;

  @override
  SceneSnapshotDto build() => _snapshot;
}

class _ShowConstellationArtConfig extends RenderConfigNotifier {
  _ShowConstellationArtConfig() : super() {
    state = state.copyWith(showConstellationArt: true);
  }
}
