import 'package:flutter/material.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

/// Builds normalized [`GestureEventDto`] values for the Rust gesture machine.
class PlanetariumGestureEvents {
  PlanetariumGestureEvents._();

  static double normX(Offset local, Size size) {
    if (size.width <= 0) {
      return 0;
    }
    return (local.dx / size.width).clamp(0.0, 1.0);
  }

  static double normY(Offset local, Size size) {
    if (size.height <= 0) {
      return 0;
    }
    return (local.dy / size.height).clamp(0.0, 1.0);
  }

  static GestureEventDto panStart(Offset local, Size size) => GestureEventDto(
        kind: GestureKindDto.panStart,
        x: normX(local, size),
        y: normY(local, size),
        dx: 0,
        dy: 0,
        vx: 0,
        vy: 0,
        factor: 1,
        radians: 0,
      );

  static GestureEventDto panUpdate({
    required double dx,
    required double dy,
    double vx = 0,
    double vy = 0,
  }) =>
      GestureEventDto(
        kind: GestureKindDto.panUpdate,
        x: 0,
        y: 0,
        dx: dx,
        dy: dy,
        vx: vx,
        vy: vy,
        factor: 1,
        radians: 0,
      );

  static GestureEventDto panEnd({double vx = 0, double vy = 0}) =>
      GestureEventDto(
        kind: GestureKindDto.panEnd,
        x: 0,
        y: 0,
        dx: 0,
        dy: 0,
        vx: vx,
        vy: vy,
        factor: 1,
        radians: 0,
      );

  static GestureEventDto zoomStart(Offset local, Size size) => GestureEventDto(
        kind: GestureKindDto.zoomStart,
        x: normX(local, size),
        y: normY(local, size),
        dx: 0,
        dy: 0,
        vx: 0,
        vy: 0,
        factor: 1,
        radians: 0,
      );

  static GestureEventDto zoomUpdate({
    required Offset focal,
    required Size size,
    required double factor,
  }) =>
      GestureEventDto(
        kind: GestureKindDto.zoomUpdate,
        x: normX(focal, size),
        y: normY(focal, size),
        dx: 0,
        dy: 0,
        vx: 0,
        vy: 0,
        factor: factor,
        radians: 0,
      );

  static const GestureEventDto zoomEnd = GestureEventDto(
    kind: GestureKindDto.zoomEnd,
    x: 0,
    y: 0,
    dx: 0,
    dy: 0,
    vx: 0,
    vy: 0,
    factor: 1,
    radians: 0,
  );

  static GestureEventDto rotateUpdate(double radians) => GestureEventDto(
        kind: GestureKindDto.rotateUpdate,
        x: 0,
        y: 0,
        dx: 0,
        dy: 0,
        vx: 0,
        vy: 0,
        factor: 1,
        radians: radians,
      );

  static GestureEventDto tap(Offset local, Size size) => GestureEventDto(
        kind: GestureKindDto.tap,
        x: normX(local, size),
        y: normY(local, size),
        dx: 0,
        dy: 0,
        vx: 0,
        vy: 0,
        factor: 1,
        radians: 0,
      );

  static GestureEventDto doubleTap(Offset local, Size size) => GestureEventDto(
        kind: GestureKindDto.doubleTap,
        x: normX(local, size),
        y: normY(local, size),
        dx: 0,
        dy: 0,
        vx: 0,
        vy: 0,
        factor: 1,
        radians: 0,
      );

  static const GestureEventDto cancel = GestureEventDto(
    kind: GestureKindDto.cancel,
    x: 0,
    y: 0,
    dx: 0,
    dy: 0,
    vx: 0,
    vy: 0,
    factor: 1,
    radians: 0,
  );
}
