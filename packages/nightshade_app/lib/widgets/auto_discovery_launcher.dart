import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Widget that triggers device discovery in the background after app launch.
///
/// This uses several techniques to avoid freezing the UI:
/// 1. Uses addPostFrameCallback to wait until the first frame is rendered
/// 2. Adds an additional delay to ensure the UI is fully interactive
/// 3. Fire-and-forget pattern - doesn't await the discovery completion
/// 4. Discovery itself runs backends in parallel for speed
class AutoDiscoveryLauncher extends ConsumerStatefulWidget {
  final Widget child;

  const AutoDiscoveryLauncher({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<AutoDiscoveryLauncher> createState() =>
      _AutoDiscoveryLauncherState();
}

class _AutoDiscoveryLauncherState extends ConsumerState<AutoDiscoveryLauncher> {
  bool _hasLaunched = false;

  LoggingService get _logger => ref.read(loggingServiceProvider);

  @override
  void initState() {
    super.initState();
    // Schedule discovery after the first frame is fully rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _triggerAutoDiscovery();
    });
  }

  Future<void> _triggerAutoDiscovery() async {
    if (_hasLaunched || !mounted) return;
    _hasLaunched = true;

    try {
      // Wait for settings to load
      final settings = await ref.read(appSettingsProvider.future);

      // Check if auto-discovery is enabled
      if (!settings.autoDiscoverOnLaunch) {
        _logger.info('[AutoDiscovery] Auto-discovery disabled in settings',
            source: 'AutoDiscoveryLauncher');
        return;
      }

      // Additional delay to ensure UI is fully interactive
      // This prevents any perceived stutter during app startup
      await Future.delayed(const Duration(milliseconds: 800));

      if (!mounted) return;

      _logger.info('[AutoDiscovery] Starting background device discovery...',
          source: 'AutoDiscoveryLauncher');

      // Fire-and-forget: Start discovery without awaiting completion
      // This allows the UI to remain responsive while discovery runs
      _runDiscoveryInBackground();
    } catch (e) {
      _logger.error(
          '[AutoDiscovery] Error during auto-discovery setup: $e',
          source: 'AutoDiscoveryLauncher',
          fields: {'error': e.toString()});
      // Don't show error to user - this is a background operation
    }
  }

  void _runDiscoveryInBackground() {
    // Use Future.microtask to ensure this doesn't block the current frame
    Future.microtask(() async {
      try {
        if (!mounted) return;

        final discoveryNotifier = ref.read(unifiedDiscoveryProvider.notifier);

        // Run discovery - this already runs backends in parallel internally
        await discoveryNotifier.discoverAll();

        _logger.info('[AutoDiscovery] Background discovery completed',
            source: 'AutoDiscoveryLauncher');
      } catch (e) {
        _logger.warning('[AutoDiscovery] Discovery error (non-fatal): $e',
            source: 'AutoDiscoveryLauncher',
            fields: {'error': e.toString()});
        // Errors during discovery are non-fatal - user can manually refresh
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
