import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart' as planetarium_v1;
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart' as planetarium_v2;

import 'planetarium_v2_host_wiring.dart';

/// Renders v1 or v2 planetarium sky based on [usePlanetariumV2Provider].
///
/// When v2 is active, stacks [planetarium_v2.InteractiveSkyView] with
/// [planetarium_v2.LabelLayer] and [planetarium_v2.ConstellationArtLayer].
/// v1 [planetarium_v1.InteractiveSkyView] is unchanged when the toggle is off.
class AdaptiveInteractiveSkyView extends ConsumerWidget {
  const AdaptiveInteractiveSkyView({
    super.key,
    this.onObjectSelected,
    this.onCoordinateTapped,
    this.onObjectTapped,
    this.showFOV = false,
    this.customFOV,
    this.fovCenter,
    this.observedObjectIds = const {},
    this.listedObjectIds = const {},
    this.bortleClass = 5,
    this.horizonAltitudes,
    this.syncViewPoseFromV1 = true,
  });

  final ValueChanged<planetarium_v1.CelestialObject?>? onObjectSelected;
  final ValueChanged<planetarium_v1.CelestialCoordinate>? onCoordinateTapped;
  final void Function(
    planetarium_v1.CelestialObject? object,
    planetarium_v1.CelestialCoordinate coordinates,
    Offset screenPosition,
  )? onObjectTapped;

  final bool showFOV;
  final (double width, double height)? customFOV;
  final planetarium_v1.CelestialCoordinate? fovCenter;
  final Set<String> observedObjectIds;
  final Set<String> listedObjectIds;
  final int bortleClass;
  final List<double>? horizonAltitudes;

  /// Mirrors v1 [planetarium_v1.skyViewStateProvider] into v2 pose when true.
  final bool syncViewPoseFromV1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useV2 = ref.watch(usePlanetariumV2Provider);
    if (!useV2) {
      return planetarium_v1.InteractiveSkyView(
        key: key,
        onObjectSelected: onObjectSelected,
        onCoordinateTapped: onCoordinateTapped,
        onObjectTapped: onObjectTapped,
        showFOV: showFOV,
        customFOV: customFOV,
        fovCenter: fovCenter,
        observedObjectIds: observedObjectIds,
        listedObjectIds: listedObjectIds,
        bortleClass: bortleClass,
        horizonAltitudes: horizonAltitudes,
      );
    }

    return PlanetariumV2HostWiring(
      syncViewPoseFromV1: syncViewPoseFromV1,
      child: _V2SkyStack(
        stackKey: key,
        onObjectTapped: onObjectTapped,
        onObjectSelected: onObjectSelected,
      ),
    );
  }
}

class _V2SkyStack extends ConsumerWidget {
  const _V2SkyStack({
    required this.stackKey,
    this.onObjectTapped,
    this.onObjectSelected,
  });

  final Key? stackKey;
  final void Function(
    planetarium_v1.CelestialObject? object,
    planetarium_v1.CelestialCoordinate coordinates,
    Offset screenPosition,
  )? onObjectTapped;
  final ValueChanged<planetarium_v1.CelestialObject?>? onObjectSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<SelectedObjectDto?>(
      planetarium_v2.selectionProvider,
      (previous, next) {
        final object = celestialObjectFromV2Selection(next);
        onObjectSelected?.call(object);
        if (onObjectTapped == null) {
          return;
        }
        if (next == null) {
          onObjectTapped!(
            null,
            const planetarium_v1.CelestialCoordinate(ra: 0, dec: 0),
            Offset.zero,
          );
          return;
        }
        final coordinates = planetarium_v1.CelestialCoordinate(
          ra: next.raRad * 12 / 3.141592653589793,
          dec: next.decRad * 180 / 3.141592653589793,
        );
        final box = context.findRenderObject() as RenderBox?;
        final screenPosition = box == null
            ? Offset.zero
            : box.localToGlobal(
                Offset(
                  next.screenX * box.size.width,
                  next.screenY * box.size.height,
                ),
              );
        onObjectTapped!(object, coordinates, screenPosition);
      },
    );

    return Stack(
      key: stackKey,
      fit: StackFit.expand,
      children: const [
        Positioned.fill(child: planetarium_v2.InteractiveSkyView()),
        Positioned.fill(child: planetarium_v2.LabelLayer()),
        Positioned.fill(child: planetarium_v2.ConstellationArtLayer()),
      ],
    );
  }
}
