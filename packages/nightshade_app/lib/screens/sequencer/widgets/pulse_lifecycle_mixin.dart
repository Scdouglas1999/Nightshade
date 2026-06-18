import 'package:flutter/material.dart';

/// Shared lifecycle plumbing for the dashboard's small "live" pulse
/// animations (the running-dot, the status-icon pulse, the broadcast LED).
///
/// Each of these used to call `_controller.repeat()` unconditionally in
/// `initState`, so the animation kept ticking — and waking the engine — even
/// when the app was backgrounded or the surface was hidden. This mixin uses
/// an [AppLifecycleListener] to stop the controller while the app is paused /
/// inactive / hidden and resume it on `resumed`, mirroring the lifecycle
/// handling already used by `_FullTimelineState`.
///
/// Implementers expose their [AnimationController] via [pulseController] and
/// optionally set [pulseReverses]. The mixin owns the start / stop calls;
/// implementers must NOT call `repeat()` themselves — they call [startPulse]
/// from `initState` and [stopPulseLifecycle] from `dispose`.
mixin PulseLifecycleMixin<T extends StatefulWidget> on State<T> {
  /// The controller that drives the pulse. Created by the implementing state
  /// before [startPulse] is called.
  AnimationController get pulseController;

  /// Whether the repeat should reverse (ping-pong) rather than restart.
  bool get pulseReverses => false;

  AppLifecycleListener? _lifecycleListener;

  /// Register the lifecycle listener and start the pulse. Call from the
  /// implementer's `initState` after the controller has been created.
  void startPulse() {
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onLifecycleState,
    );
    pulseController.repeat(reverse: pulseReverses);
  }

  /// Tear down the lifecycle listener. Call from the implementer's `dispose`
  /// before disposing the controller.
  void stopPulseLifecycle() {
    _lifecycleListener?.dispose();
    _lifecycleListener = null;
  }

  void _onLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!pulseController.isAnimating) {
        pulseController.repeat(reverse: pulseReverses);
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (pulseController.isAnimating) pulseController.stop();
    }
  }
}
