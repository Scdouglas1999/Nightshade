// C4 — wire the settings-backed plugin-enablement store into C3's
// registration pipeline.
//
// C3 (`nightshade_plugins/src/plugin_registration.dart`) defines the abstract
// [PluginEnablementStore] contract and a settings-agnostic
// `AllEnabledPluginEnablementStore` default. C4
// (`nightshade_core/src/providers/plugin_enablement_provider.dart`) implements
// that contract against the settings database and exposes
// [settingsPluginEnablementStoreProvider].
//
// Neither provider is surfaced through its package barrel (both are internal
// wiring seams), so — exactly like `integrations_settings.dart` and the C4
// provider itself — we import them by path. `nightshade_app` is the only
// package that depends on BOTH `nightshade_core` and `nightshade_plugins`, so
// it is the correct home for the override that bridges them. The
// implementation_imports lint is suppressed deliberately: there is no
// barrel-only alternative for this app-layer composition.
//
// ignore_for_file: implementation_imports

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/src/providers/plugin_enablement_provider.dart'
    show settingsPluginEnablementStoreProvider;
import 'package:nightshade_plugins/src/plugin_registration.dart'
    show pluginEnablementStoreProvider;

/// Build the Riverpod override that makes the bundled-plugin registration
/// honour the user's persisted enable/disable choices.
///
/// Without this override C3's [pluginEnablementStoreProvider] resolves to the
/// default `AllEnabledPluginEnablementStore`, which reports every plugin
/// enabled — so a plugin the user disabled on the Integrations page would
/// silently come back ENABLED on the next launch (the registration pipeline
/// would call `onEnable` again). Installing the settings-backed store makes the
/// registration-time decision read the persisted `plugin_enablement` map, so a
/// disabled plugin is registered (loaded) but NOT enabled.
///
/// Use in every app entry point's `ProviderScope` / `ProviderContainer`
/// overrides (desktop GUI, desktop headless, mobile):
///
/// ```dart
/// final container = ProviderContainer(
///   overrides: [
///     backendProvider.overrideWith(...),
///     pluginNodeDispatcherOverride(),
///     pluginEnablementStoreOverride(),
///   ],
/// );
/// ```
Override pluginEnablementStoreOverride() {
  return pluginEnablementStoreProvider.overrideWith(
    (ref) => ref.watch(settingsPluginEnablementStoreProvider),
  );
}
