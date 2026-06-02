import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Drives the phone "immersive" shell chrome — the auto-hiding bottom
/// navigation + status bar.
///
/// The chrome is visible by default and **auto-hides after a short idle
/// period** so that when the operator is just watching a live frame / the sky /
/// a guiding graph, the navigation and status strip slide away and the content
/// gets the whole (very short, on a foldable cover screen) height. Any
/// interaction [poke]s it back and restarts the idle timer, so it only ever
/// disappears when genuinely unused. Tapping the reveal grabber or swiping up
/// from the bottom edge also brings it back.
///
/// Phone-only: the desktop/tablet shell never reads this (it uses a persistent
/// side rail), and [enabled] is set false there so the timer never runs.
class ImmersiveChromeController extends StateNotifier<bool> {
  ImmersiveChromeController() : super(true);

  Timer? _idleTimer;
  bool _enabled = false;
  int _holds = 0;

  /// How long the chrome stays after the last interaction before sliding away.
  static const Duration idleTimeout = Duration(seconds: 5);

  /// Whether immersive auto-hide is active (phone only). When false the chrome
  /// is pinned visible and no timer runs.
  bool get enabled => _enabled;

  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _idleTimer?.cancel();
      if (!state) state = true; // pin visible on desktop/tablet
    } else {
      _restartTimer();
    }
  }

  /// Register an interaction: reveal the chrome and restart the idle countdown.
  /// Call from a shell-level pointer listener and on route changes.
  void poke() {
    if (!_enabled) return;
    if (!state) state = true;
    _restartTimer();
  }

  /// Force the chrome visible (e.g. entering a list/setup screen) without the
  /// auto-hide fighting the user. Still restarts the idle timer.
  void reveal() => poke();

  /// Hide immediately (e.g. the user swiped down, or a canvas went fullscreen).
  void conceal() {
    if (!_enabled) return;
    _idleTimer?.cancel();
    if (state) state = false;
  }

  /// Toggle on an explicit gesture (grabber tap).
  void toggle() => state ? conceal() : poke();

  /// Pause auto-hide while a modal/sheet is open so the chrome can't vanish
  /// underneath it. Balance every [pushHold] with a [popHold].
  void pushHold() {
    _holds++;
    _idleTimer?.cancel();
    if (!state) state = true;
  }

  void popHold() {
    if (_holds > 0) _holds--;
    if (_holds == 0) _restartTimer();
  }

  void _restartTimer() {
    _idleTimer?.cancel();
    if (!_enabled || _holds > 0) return;
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
