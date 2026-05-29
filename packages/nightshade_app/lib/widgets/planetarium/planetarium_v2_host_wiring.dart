import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart' as planetarium_v1;
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart' as planetarium_v2;

/// Activates planetarium v2 engine sync providers and mirrors v1 sky state.
class PlanetariumV2HostWiring extends ConsumerStatefulWidget {
  const PlanetariumV2HostWiring({
    super.key,
    required this.child,
    this.syncViewPoseFromV1 = true,
  });

  final Widget child;

  /// When true, every change to [planetarium_v1.skyViewStateProvider] is
  /// pushed into [planetarium_v2.viewPoseProvider] and then on to the Rust
  /// renderer via [planetarium_v2.planetariumViewPoseSyncProvider].
  ///
  /// Default `false`: the v2 widget owns its own pose. The v1 widget runs
  /// in parallel and does not normally need to drive v2 — and bidirectional
  /// sync would currently produce a feedback loop: gestures in
  /// `InteractiveSkyView._pushGesture` go straight to Rust (they do not
  /// update the Dart `viewPoseProvider`), so any per-change v1 → v2 push
  /// would re-overwrite the gesture-driven Rust pose on the very next
  /// frame — appearing as "pan / zoom don't move the camera".
  ///
  /// The initial pose is still seeded from v1 in `initState`, so opening
  /// v2 lands at whatever sky region v1 was showing.
  final bool syncViewPoseFromV1;

  @override
  ConsumerState<PlanetariumV2HostWiring> createState() =>
      _PlanetariumV2HostWiringState();
}

class _PlanetariumV2HostWiringState extends ConsumerState<PlanetariumV2HostWiring> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // Time mirror is harmless and useful (so v2 "Now" matches v1's clock
      // when both are visible). Pose seed only when explicitly requested —
      // v1's default `centerDec=0, fieldOfView=60` would otherwise
      // override v2's own `decDegrees=90, fieldOfViewDegrees=90` default
      // and aim the camera at the celestial equator at RA=0 (often
      // partially below the horizon at mid-latitudes, often empty sky).
      _pushObservationTimeFromV1();
      if (widget.syncViewPoseFromV1) {
        _pushViewPoseFromV1();
      }
    });
  }

  void _pushObservationTimeFromV1() {
    final driver =
        ref.read(planetarium_v2.planetariumHandleProvider).valueOrNull;
    if (driver == null) {
      return;
    }
    final v1Time = ref.read(planetarium_v1.observationTimeProvider);
    driver.setTime(
      planetarium_v2.PlanetariumAstroTime.fromDateTime(v1Time.time).toDto(),
    );
  }

  void _pushViewPoseFromV1() {
    if (!mounted) {
      return;
    }
    final sky = ref.read(planetarium_v1.skyViewStateProvider);
    final poseNotifier = ref.read(planetarium_v2.viewPoseProvider.notifier);
    poseNotifier.setCenter(sky.centerRA, sky.centerDec);
    poseNotifier.setFieldOfView(sky.fieldOfView);
    poseNotifier.setRotation(sky.rotation);
    poseNotifier.setProjection(_mapProjection(sky.projection));
  }

  planetarium_v2.PlanetariumSkyProjection _mapProjection(
    planetarium_v1.SkyProjection projection,
  ) {
    return switch (projection) {
      planetarium_v1.SkyProjection.stereographic =>
        planetarium_v2.PlanetariumSkyProjection.stereographic,
      planetarium_v1.SkyProjection.orthographic =>
        planetarium_v2.PlanetariumSkyProjection.orthographic,
      planetarium_v1.SkyProjection.azimuthalEquidistant =>
        planetarium_v2.PlanetariumSkyProjection.azimuthalEquidistant,
    };
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(planetarium_v2.planetariumViewPoseSyncProvider);
    ref.watch(planetarium_v2.planetariumObserverSyncProvider);
    ref.watch(planetarium_v2.planetariumRenderConfigSyncProvider);
    ref.watch(planetarium_v2.sceneSnapshotProvider);
    ref.watch(planetarium_v2.planetariumSelectionSyncProvider);

    if (widget.syncViewPoseFromV1) {
      ref.listen(planetarium_v1.skyViewStateProvider, (_, __) {
        _pushViewPoseFromV1();
      });
    }

    ref.listen(planetarium_v1.observationTimeProvider, (_, __) {
      _pushObservationTimeFromV1();
    });

    return widget.child;
  }
}

/// Maps a v2 hit-test selection into a v1 [planetarium_v1.CelestialObject].
planetarium_v1.CelestialObject? celestialObjectFromV2Selection(
  SelectedObjectDto? selection,
) {
  if (selection == null) {
    return null;
  }

  final raHours = selection.raRad * 12 / math.pi;
  final decDegrees = selection.decRad * 180 / math.pi;
  final coordinates = planetarium_v1.CelestialCoordinate(
    ra: raHours,
    dec: decDegrees,
  );

  if (selection.category == LabelCategoryDto.star) {
    return planetarium_v1.Star(
      id: selection.objectId.toString(),
      name: selection.displayName,
      coordinates: coordinates,
    );
  }

  return planetarium_v1.DeepSkyObject(
    id: selection.objectId.toString(),
    name: selection.displayName,
    coordinates: coordinates,
    type: planetarium_v1.DsoType.other,
  );
}
