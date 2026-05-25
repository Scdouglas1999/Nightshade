import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/view_pose_state.dart';
import 'planetarium_sync.dart';

class ViewPoseNotifier extends StateNotifier<ViewPoseState> {
  ViewPoseNotifier() : super(const ViewPoseState());

  void setCenter(double raHours, double decDegrees) {
    state = state.copyWith(
      centerRaHours: raHours.clamp(0, 24),
      centerDecDegrees: decDegrees.clamp(-90, 90),
    );
  }

  void setFieldOfView(double fovDegrees) {
    state = state.copyWith(
      fieldOfViewDegrees: fovDegrees.clamp(1, 180),
    );
  }

  void setRotation(double rotationDegrees) {
    state = state.copyWith(
      rotationDegrees: rotationDegrees % 360,
    );
  }

  void setProjection(PlanetariumSkyProjection projection) {
    state = state.copyWith(projection: projection);
  }
}

/// Interactive sky view pose (RA/Dec/FOV/roll/projection).
final viewPoseProvider =
    StateNotifierProvider<ViewPoseNotifier, ViewPoseState>((ref) {
  return ViewPoseNotifier();
});

/// Mirrors [viewPoseProvider] into Rust via [planetariumSetPose].
final planetariumViewPoseSyncProvider = Provider<void>((ref) {
  bindPlanetariumSync(
    ref,
    listenSource: viewPoseProvider,
    push: (driver, pose) => driver.setPose(pose.toDto()),
  );
});
