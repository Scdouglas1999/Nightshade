import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mobile-only preferences persisted via SharedPreferences.
///
/// These settings are UI-shell concerns that don't belong in the cross-
/// platform desktop AppSettings model (which is mirrored to the headless
/// server). Audit §3.13 added [androidImmersiveSticky] so users who want
/// status bar / battery / clock visible can opt out of fullscreen.
class MobilePreferences {
  MobilePreferences(this._prefs);

  static const _kAndroidImmersiveSticky = 'mobile.androidImmersiveSticky';

  // Per-category notification mute toggles. All default to true (enabled)
  // because v2.5 ships with notifications opt-out; the mobile companion is
  // useless during an unattended sequence if the operator can't be paged.
  static const _kNotifySequence = 'mobile.notify.sequence';
  static const _kNotifyMeridianFlip = 'mobile.notify.meridianFlip';
  static const _kNotifySafety = 'mobile.notify.safety';
  static const _kNotifyGuiding = 'mobile.notify.guiding';
  static const _kNotifyExposureFailed = 'mobile.notify.exposureFailed';
  static const _kNotifyAutofocusFailed = 'mobile.notify.autofocusFailed';
  static const _kNotifyEquipmentDisconnected =
      'mobile.notify.equipmentDisconnected';
  static const _kNotifyDiskLow = 'mobile.notify.diskLow';
  static const _kNotifyTargetCompleted = 'mobile.notify.targetCompleted';
  static const _kNotifyBattery = 'mobile.notify.battery';

  final SharedPreferences _prefs;

  /// When true, hide the status bar and use [SystemUiMode.immersiveSticky].
  /// When false, use [SystemUiMode.leanBack] so the clock and battery stay
  /// visible — astrophotographers monitor those during long sequences.
  /// Default: false.
  bool get androidImmersiveSticky =>
      _prefs.getBool(_kAndroidImmersiveSticky) ?? false;

  Future<void> setAndroidImmersiveSticky(bool value) async {
    await _prefs.setBool(_kAndroidImmersiveSticky, value);
  }

  // ---------------------------------------------------------------------------
  // Notification category toggles
  //
  // Each toggle gates a specific notification channel emitted by the mobile-
  // direct event subscriber (`MobileEventNotifier`) or by the foreground/
  // power services. Defaults are intentionally ON: an astrophotographer who
  // installs the companion app does so to be paged during failures, so the
  // burden of proof for muting is on the user, not the app.
  // ---------------------------------------------------------------------------

  bool get notifySequence => _prefs.getBool(_kNotifySequence) ?? true;
  Future<void> setNotifySequence(bool value) =>
      _prefs.setBool(_kNotifySequence, value);

  bool get notifyMeridianFlip => _prefs.getBool(_kNotifyMeridianFlip) ?? true;
  Future<void> setNotifyMeridianFlip(bool value) =>
      _prefs.setBool(_kNotifyMeridianFlip, value);

  bool get notifySafety => _prefs.getBool(_kNotifySafety) ?? true;
  Future<void> setNotifySafety(bool value) =>
      _prefs.setBool(_kNotifySafety, value);

  bool get notifyGuiding => _prefs.getBool(_kNotifyGuiding) ?? true;
  Future<void> setNotifyGuiding(bool value) =>
      _prefs.setBool(_kNotifyGuiding, value);

  bool get notifyExposureFailed =>
      _prefs.getBool(_kNotifyExposureFailed) ?? true;
  Future<void> setNotifyExposureFailed(bool value) =>
      _prefs.setBool(_kNotifyExposureFailed, value);

  bool get notifyAutofocusFailed =>
      _prefs.getBool(_kNotifyAutofocusFailed) ?? true;
  Future<void> setNotifyAutofocusFailed(bool value) =>
      _prefs.setBool(_kNotifyAutofocusFailed, value);

  bool get notifyEquipmentDisconnected =>
      _prefs.getBool(_kNotifyEquipmentDisconnected) ?? true;
  Future<void> setNotifyEquipmentDisconnected(bool value) =>
      _prefs.setBool(_kNotifyEquipmentDisconnected, value);

  bool get notifyDiskLow => _prefs.getBool(_kNotifyDiskLow) ?? true;
  Future<void> setNotifyDiskLow(bool value) =>
      _prefs.setBool(_kNotifyDiskLow, value);

  /// Per-target-completed pings are noisier than sequence-level events, so
  /// the operator may want them off independently of the sequence toggle.
  bool get notifyTargetCompleted =>
      _prefs.getBool(_kNotifyTargetCompleted) ?? true;
  Future<void> setNotifyTargetCompleted(bool value) =>
      _prefs.setBool(_kNotifyTargetCompleted, value);

  bool get notifyBattery => _prefs.getBool(_kNotifyBattery) ?? true;
  Future<void> setNotifyBattery(bool value) =>
      _prefs.setBool(_kNotifyBattery, value);
}

/// Async provider that resolves once SharedPreferences is loaded.
final mobilePreferencesProvider =
    FutureProvider<MobilePreferences>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return MobilePreferences(prefs);
});
