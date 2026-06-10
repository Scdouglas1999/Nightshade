import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../../widgets/planetarium/adaptive_interactive_sky_view.dart';

/// Sky backdrop for the mosaic wizard visual planner.
class MosaicPlannerSkyView extends ConsumerStatefulWidget {
  const MosaicPlannerSkyView({
    super.key,
    required this.centerRaHours,
    required this.centerDecDegrees,
    this.onObjectTapped,
    this.showFOV = true,
    this.bortleClass = 5,
  });

  final double centerRaHours;
  final double centerDecDegrees;
  final void Function(
    CelestialObject? object,
    CelestialCoordinate coordinates,
    Offset screenPosition,
  )? onObjectTapped;
  final bool showFOV;
  final int bortleClass;

  @override
  ConsumerState<MosaicPlannerSkyView> createState() =>
      _MosaicPlannerSkyViewState();
}

class _MosaicPlannerSkyViewState extends ConsumerState<MosaicPlannerSkyView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(skyViewStateProvider.notifier).setCenter(
            widget.centerRaHours,
            widget.centerDecDegrees,
          );
    });
  }

  @override
  void didUpdateWidget(covariant MosaicPlannerSkyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centerRaHours != widget.centerRaHours ||
        oldWidget.centerDecDegrees != widget.centerDecDegrees) {
      ref.read(skyViewStateProvider.notifier).setCenter(
            widget.centerRaHours,
            widget.centerDecDegrees,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveInteractiveSkyView(
      key: widget.key,
      onObjectTapped: widget.onObjectTapped,
      showFOV: widget.showFOV,
      bortleClass: widget.bortleClass,
      syncViewPoseFromV1: true,
    );
  }
}
