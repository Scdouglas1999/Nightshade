import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/settings/rendering_platform.dart';
import 'settings_provider.dart';

/// Selected planetarium rendering stack (v1 legacy or v2 Rust+wgpu).
///
/// Defaults to [RenderingPlatform.v1] until settings load or the user
/// opts into v2 via [AppSettingsNotifier.setRenderingPlatform].
final renderingPlatformProvider = Provider<RenderingPlatform>((ref) {
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  return settings?.renderingPlatform ?? RenderingPlatform.v1;
});

/// Convenience: whether planetarium screens should mount v2 widgets.
final usePlanetariumV2Provider = Provider<bool>((ref) {
  return ref.watch(renderingPlatformProvider).isV2;
});
