import 'dart:io' show Platform;

/// Ops-only companion dashboard (tabbed mobile UI).
///
/// Enabled via compile-time `--dart-define=NIGHTSHADE_COMPANION_UI=1` or
/// runtime `NIGHTSHADE_COMPANION_UI=1`. Default is full NightshadeApp parity.
bool get isCompanionUiEnabled {
  const fromDefine = bool.fromEnvironment(
    'NIGHTSHADE_COMPANION_UI',
    defaultValue: false,
  );
  if (fromDefine) return true;
  return Platform.environment['NIGHTSHADE_COMPANION_UI'] == '1';
}
