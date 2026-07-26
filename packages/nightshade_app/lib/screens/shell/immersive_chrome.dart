import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Drives the phone "immersive" shell chrome — the bottom navigation + status
/// bar, which can be hidden to give content the whole (very short, on a
/// foldable cover) height.
///
/// Interaction model:
///  * **Manual is primary and sticky.** [toggle]/[show]/[hide] (the always-on
///    grabber handle / a swipe) put the chrome exactly where the operator wants
///    it and it STAYS there — incidental taps never bring it back. This is the
///    control the operator reaches for.
///  * **Idle auto-hide is a per-screen convenience.** On arriving at a screen
///    ([onRouteChanged]) the chrome is shown and, if untouched, tucks away once
///    after [idleTimeout]. The moment the operator uses the handle, auto-hide
///    yields for that screen.
///
/// Phone-only: desktop/tablet set [enabled] false (chrome pinned visible, no
/// timer).
class ImmersiveChromeController extends StateNotifier<bool> {
  ImmersiveChromeController() : super(true);

  Timer? _idleTimer;
  bool _enabled = false;
  bool _manual = false;

  /// Idle delay before the chrome tucks itself away on a freshly-entered
  /// screen (only while the operator hasn't taken manual control).
  ///
  /// 30s, not the original 5s: at five seconds the nav vanished before a
  /// first-time operator finished reading the screen, and the only way back
  /// was the slim grabber — live-device testing showed people (and one
  /// auditor) simply got stranded. Thirty seconds keeps the tuck-away for
  /// long monitoring stretches without amputating navigation mid-orientation.
  static const Duration idleTimeout = Duration(seconds: 30);

  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _idleTimer?.cancel();
      if (!state) state = true; // pin visible on desktop/tablet
    } else {
      _arm();
    }
  }

  /// Fresh screen: reveal and allow the one-shot idle auto-hide again.
  void onRouteChanged() {
    if (!_enabled) return;
    _manual = false;
    if (!state) state = true;
    _arm();
  }

  /// Explicitly reveal (grabber tap / swipe up) and pin — no auto-hide until
  /// the next screen or an explicit hide.
  void show() {
    if (!_enabled) return;
    _manual = true;
    _idleTimer?.cancel();
    if (!state) state = true;
  }

  /// Explicitly hide (grabber tap / swipe down) and keep it hidden.
  void hide() {
    if (!_enabled) return;
    _manual = true;
    _idleTimer?.cancel();
    if (state) state = false;
  }

  /// Manual toggle from the always-visible grabber handle.
  void toggle() => state ? hide() : show();

  void _arm() {
    _idleTimer?.cancel();
    if (!_enabled || _manual) return;
    _idleTimer = Timer(idleTimeout, () {
      if (mounted && state) state = false;
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}

/// `true` when the phone shell chrome (bottom nav + status bar) is visible.
final immersiveChromeProvider =
    StateNotifierProvider<ImmersiveChromeController, bool>(
  (ref) => ImmersiveChromeController(),
);
