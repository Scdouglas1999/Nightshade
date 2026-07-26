// Eager bootstrap for the bundled plugin runtime.
//
// Plugin registration used to be triggered only by opening Settings >
// Integrations. That made an unattended/headless sequence containing a plugin
// node fail after a clean restart until somebody visited that settings page.
// Hardware-owning entry points call this before accepting sequence work.

// ignore: implementation_imports
import 'package:nightshade_plugins/src/plugin_registration.dart'
    show pluginRegistrationProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Register every bundled plugin and apply persisted enablement choices.
///
/// Call only in a hardware-owning process. A NetworkBackend client must not
/// populate its palette from local plugin state because execution belongs to
/// the remote imaging host.
Future<void> initializeBundledPluginRuntime(ProviderContainer container) {
  return container.read(pluginRegistrationProvider.future);
}
