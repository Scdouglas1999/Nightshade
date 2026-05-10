import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable view state for the imaging preview viewer.
///
/// Pulled out of `_ImagingScreenState` so navigation, hot-reload, and screen
/// rebuilds do not reset the user's pan / zoom / overlay choices, and so other
/// surfaces (e.g. fullscreen preview, secondary monitor mirror) can read the
/// same state without prop-drilling through widget constructors.
@immutable
class ImagingViewerState {
  /// 1.0 = fit-to-window. Clamped at the call site.
  final double zoomLevel;

  /// Pan offset accumulated while dragging the preview.
  final Offset panOffset;

  /// Crosshair overlay visibility.
  final bool showCrosshair;

  /// Reticle / grid overlay visibility.
  final bool showGrid;

  /// Star detection markers overlay visibility.
  final bool showStarOverlay;

  const ImagingViewerState({
    this.zoomLevel = 1.0,
    this.panOffset = Offset.zero,
    this.showCrosshair = true,
    this.showGrid = false,
    this.showStarOverlay = false,
  });

  ImagingViewerState copyWith({
    double? zoomLevel,
    Offset? panOffset,
    bool? showCrosshair,
    bool? showGrid,
    bool? showStarOverlay,
  }) {
    return ImagingViewerState(
      zoomLevel: zoomLevel ?? this.zoomLevel,
      panOffset: panOffset ?? this.panOffset,
      showCrosshair: showCrosshair ?? this.showCrosshair,
      showGrid: showGrid ?? this.showGrid,
      showStarOverlay: showStarOverlay ?? this.showStarOverlay,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImagingViewerState &&
          runtimeType == other.runtimeType &&
          zoomLevel == other.zoomLevel &&
          panOffset == other.panOffset &&
          showCrosshair == other.showCrosshair &&
          showGrid == other.showGrid &&
          showStarOverlay == other.showStarOverlay;

  @override
  int get hashCode => Object.hash(
        zoomLevel,
        panOffset,
        showCrosshair,
        showGrid,
        showStarOverlay,
      );
}

/// Notifier exposing intent-based mutators so callers don't have to hand-roll
/// clamping or copyWith chains, and so behavior (zoom step / clamp range) lives
/// in one place.
class ImagingViewerStateNotifier extends StateNotifier<ImagingViewerState> {
  ImagingViewerStateNotifier() : super(const ImagingViewerState());

  /// Min/max zoom mirror what the previous widget-state implementation
  /// used; keep them here so the bounds are not silently re-derived in the UI.
  static const double minZoom = 0.25;
  static const double maxZoom = 8.0;
  static const double zoomStep = 1.25;

  void zoomIn() {
    final next = (state.zoomLevel * zoomStep).clamp(minZoom, maxZoom);
    state = state.copyWith(zoomLevel: next);
  }

  void zoomOut() {
    final next = (state.zoomLevel / zoomStep).clamp(minZoom, maxZoom);
    state = state.copyWith(zoomLevel: next);
  }

  /// Reset to fit-to-window: zoom 1.0, pan zeroed.
  void fitToWindow() {
    state = state.copyWith(zoomLevel: 1.0, panOffset: Offset.zero);
  }

  /// Reset to 1:1 actual pixels: same effective state as fit on the current
  /// implementation, but expressed as a separate intent so behavior can diverge
  /// without touching call sites.
  void zoom1to1() {
    state = state.copyWith(zoomLevel: 1.0, panOffset: Offset.zero);
  }

  void pan(Offset delta) {
    state = state.copyWith(panOffset: state.panOffset + delta);
  }

  void toggleCrosshair() {
    state = state.copyWith(showCrosshair: !state.showCrosshair);
  }

  void toggleGrid() {
    state = state.copyWith(showGrid: !state.showGrid);
  }

  void toggleStarOverlay() {
    state = state.copyWith(showStarOverlay: !state.showStarOverlay);
  }
}

/// View state for the imaging preview area (zoom, pan, overlay flags).
final imagingViewerStateProvider =
    StateNotifierProvider<ImagingViewerStateNotifier, ImagingViewerState>(
  (ref) => ImagingViewerStateNotifier(),
);
