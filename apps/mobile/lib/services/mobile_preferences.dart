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
}

/// Async provider that resolves once SharedPreferences is loaded.
final mobilePreferencesProvider =
    FutureProvider<MobilePreferences>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return MobilePreferences(prefs);
});
