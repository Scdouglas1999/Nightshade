import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import '../bridge/gesture_events.dart';
import '../bridge/planetarium_driver.dart';
import '../providers/planetarium_handle_provider.dart';
import '../providers/planetarium_quiesced_provider.dart';
import '../providers/selection_provider.dart';

/// Minimal v2 sky viewport hosting the Rust-rendered [Texture].
///
/// Forwards pan/zoom gestures, resizes the native target on layout changes,
/// quiesces snapshot polling when backgrounded, and hit-tests taps for selection.
class InteractiveSkyView extends ConsumerStatefulWidget {
  const InteractiveSkyView({super.key});

  @override
  ConsumerState<InteractiveSkyView> createState() => _InteractiveSkyViewState();
}

class _InteractiveSkyViewState extends ConsumerState<InteractiveSkyView>
    with WidgetsBindingObserver {
  Size? _lastLayoutSize;
  double? _lastDevicePixelRatio;
  int _textureId = 0;

  Offset? _lastFocalPoint;
  double _lastScale = 1;
  bool _pinchActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final driver = ref.read(planetariumHandleProvider).valueOrNull;
    if (driver == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        ref.read(planetariumQuiescedProvider.notifier).state = false;
        driver.restore();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        ref.read(planetariumQuiescedProvider.notifier).state = true;
        driver.quiesce();
    }
  }

  @override
  void didChangeMetrics() {
    // System metrics (display added/removed, DPR changed, etc.) — invalidate
    // the resize cache so the next LayoutBuilder build pushes the new size
    // and DPR to Rust. The cache is widget-local, so we MUST trigger a
    // rebuild ourselves; the LayoutBuilder won't fire on its own when only
    // MediaQuery changes.
    if (!mounted) {
      return;
    }
    if (_lastLayoutSize != null || _lastDevicePixelRatio != null) {
      setState(() {
        _lastDevicePixelRatio = null;
        _lastLayoutSize = null;
      });
    }
  }

  void _scheduleResize(
    PlanetariumDriver driver,
    Size layoutSize,
    double devicePixelRatio,
  ) {
    if (layoutSize.width <= 0 ||
        layoutSize.height <= 0 ||
        !layoutSize.isFinite) {
      return;
    }
    if (_lastLayoutSize == layoutSize &&
        _lastDevicePixelRatio == devicePixelRatio) {
      return;
    }
    _lastLayoutSize = layoutSize;
    _lastDevicePixelRatio = devicePixelRatio;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final tex = driver.resize(
        width: layoutSize.width.round(),
        height: layoutSize.height.round(),
        devicePixelRatio: devicePixelRatio,
      );
      if (tex != _textureId) {
        setState(() => _textureId = tex);
      }
    });
  }

  void _pushGesture(PlanetariumDriver driver, GestureEventDto event) {
    driver.pushGesture(event);
  }

  void _handleTap(
    PlanetariumDriver driver,
    Offset localPosition,
    Size layoutSize,
  ) {
    final nx = PlanetariumGestureEvents.normX(localPosition, layoutSize);
    final ny = PlanetariumGestureEvents.normY(localPosition, layoutSize);
    _pushGesture(driver, PlanetariumGestureEvents.tap(localPosition, layoutSize));

    final hit = driver.hitTest(x: nx, y: ny);
    final selection = ref.read(selectionProvider.notifier);
    if (hit != null) {
      selection.select(hit);
    } else {
      selection.clear();
    }
  }

  Widget _buildSkyContent(
    PlanetariumDriver driver,
    Size layoutSize,
    int textureId,
  ) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) {
          return;
        }
        final factor = event.scrollDelta.dy > 0 ? 1.15 : 1 / 1.15;
        _pushGesture(
          driver,
          PlanetariumGestureEvents.zoomUpdate(
            focal: event.localPosition,
            size: layoutSize,
            factor: factor,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _lastFocalPoint = details.focalPoint;
          _lastScale = 1;
          _pinchActive = details.pointerCount >= 2;
          if (_pinchActive) {
            _pushGesture(
              driver,
              PlanetariumGestureEvents.zoomStart(details.focalPoint, layoutSize),
            );
          } else {
            _pushGesture(
              driver,
              PlanetariumGestureEvents.panStart(details.focalPoint, layoutSize),
            );
          }
        },
        onScaleUpdate: (details) {
          if (_pinchActive || details.pointerCount >= 2) {
            _pinchActive = true;
            final factor = details.scale / _lastScale;
            _lastScale = details.scale;
            if (factor != 1) {
              _pushGesture(
                driver,
                PlanetariumGestureEvents.zoomUpdate(
                  focal: details.focalPoint,
                  size: layoutSize,
                  factor: factor,
                ),
              );
            }
            if (details.rotation != 0) {
              _pushGesture(
                driver,
                PlanetariumGestureEvents.rotateUpdate(details.rotation),
              );
            }
          } else if (_lastFocalPoint != null) {
            final delta = details.focalPoint - _lastFocalPoint!;
            _lastFocalPoint = details.focalPoint;
            if (delta != Offset.zero) {
              _pushGesture(
                driver,
                PlanetariumGestureEvents.panUpdate(
                  dx: delta.dx / layoutSize.width,
                  dy: delta.dy / layoutSize.height,
                ),
              );
            }
          }
        },
        onScaleEnd: (_) {
          if (_pinchActive) {
            _pushGesture(driver, PlanetariumGestureEvents.zoomEnd);
          } else {
            _pushGesture(driver, PlanetariumGestureEvents.panEnd());
          }
          _lastFocalPoint = null;
          _lastScale = 1;
          _pinchActive = false;
        },
        onTapUp: (details) =>
            _handleTap(driver, details.localPosition, layoutSize),
        // NOTE: deliberately no `onDoubleTapDown`. Wiring both onTapUp and
        // onDoubleTapDown forces the gesture arena to wait for the double-tap
        // timeout (~300 ms) before firing tap — that produces a sluggish
        // selection feel and leaves a pending timer in widget tests. Rust
        // currently doesn't consume `DoubleTap` (see gesture/mod.rs line
        // 187 — it's a no-op in the gesture machine). If double-tap is
        // re-enabled later, place it in a sibling RawGestureDetector with
        // its own arena so tap stays low-latency.
        child: Texture(textureId: textureId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(planetariumSelectionSyncProvider);

    final asyncHandle = ref.watch(planetariumHandleProvider);

    return asyncHandle.when(
      loading: () => const ColoredBox(color: Colors.black),
      error: (error, _) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            '$error',
            style: const TextStyle(color: Colors.redAccent),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (driver) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final layoutSize = constraints.biggest;
            final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
            _scheduleResize(driver, layoutSize, devicePixelRatio);

            final textureId =
                _textureId != 0 ? _textureId : driver.textureId;
            if (textureId <= 0) {
              return const ColoredBox(color: Colors.black);
            }
            return _buildSkyContent(driver, layoutSize, textureId);
          },
        );
      },
    );
  }
}
