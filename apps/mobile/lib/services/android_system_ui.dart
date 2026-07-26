import 'package:flutter/services.dart';

/// Applies the mobile companion's Android fullscreen preference.
///
/// Edge-to-edge keeps the status and navigation bars visible. Flutter's
/// [SystemUiMode.leanBack] is a fullscreen mode even when every overlay is
/// passed, so it cannot represent the preference's disabled state.
Future<void> applyAndroidSystemUiPreference(bool immersiveSticky) {
  return SystemChrome.setEnabledSystemUIMode(
    immersiveSticky ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
  );
}
