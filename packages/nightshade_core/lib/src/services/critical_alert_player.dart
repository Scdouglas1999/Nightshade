import 'package:flutter/services.dart';

/// Plays an audible alert when a critical executor event fires.
///
/// Why a service (not a static call): the alert path needs to be mockable in
/// the integration test that proves [audibleAlertsOnCritical] actually
/// reaches a speaker. Tests inject a `_FakeCriticalAlertPlayer` via
/// `criticalAlertPlayerProvider` to capture invocations without touching
/// the real platform channel.
abstract class CriticalAlertPlayer {
  /// Play the configured alert sound. Implementations must be cheap to call
  /// repeatedly because the run-dashboard bridge may call us once per
  /// critical event. The bridge itself applies a 5-second cooldown so
  /// implementations don't need to throttle internally.
  ///
  /// [sound] is the persisted `criticalAlertSound` value
  /// (`systemBell` | `none`). Implementations must treat any other value as
  /// `systemBell` rather than silently doing nothing; an unknown value
  /// shouldn't suppress alerts the user wanted.
  Future<void> play({required String sound});
}

/// Production implementation that plays Flutter's `SystemSound.alert`.
///
/// `SystemSound.alert` is supported on every Flutter target platform
/// (Windows / macOS / Linux / iOS / Android). On platforms that don't have
/// a system "alert" sound (some Linux desktop environments), Flutter falls
/// back to a no-op rather than raising — the user will still see the
/// banner and toast, so a missing audio cue is not a critical failure.
class SystemSoundCriticalAlertPlayer implements CriticalAlertPlayer {
  const SystemSoundCriticalAlertPlayer();

  @override
  Future<void> play({required String sound}) async {
    if (sound == 'none') return;
    // `systemBell` (and unknown — see CriticalAlertPlayer.play docs).
    await SystemSound.play(SystemSoundType.alert);
  }
}
