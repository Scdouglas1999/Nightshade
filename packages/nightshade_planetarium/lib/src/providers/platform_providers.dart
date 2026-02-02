import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether we're on a touch-primary device
final isTouchDeviceProvider = Provider<bool>((ref) {
  if (kIsWeb) return false;
  return Platform.isIOS || Platform.isAndroid;
});

/// Whether hover interactions are available
final hasHoverProvider = Provider<bool>((ref) {
  if (kIsWeb) return true;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
});

/// Whether right-click context menus are expected
final hasContextMenuProvider = Provider<bool>((ref) {
  return ref.watch(hasHoverProvider);
});

/// Display refresh rate in Hz.
///
/// Uses the platform display when available, with an optional override
/// via NIGHTSHADE_REFRESH_RATE for headless environments.
final displayRefreshRateProvider = Provider<double>((ref) {
  const defaultHz = 60.0;

  if (!kIsWeb) {
    final override = Platform.environment['NIGHTSHADE_REFRESH_RATE'];
    if (override != null) {
      final parsed = double.tryParse(override);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
      if (kDebugMode) {
        debugPrint('Invalid NIGHTSHADE_REFRESH_RATE="$override", using $defaultHz Hz.');
      }
    }
  }

  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) {
    if (kDebugMode) {
      debugPrint('No Flutter views available, using $defaultHz Hz.');
    }
    return defaultHz;
  }

  final refreshRate = views.first.display.refreshRate;
  return refreshRate > 0 ? refreshRate : defaultHz;
});
