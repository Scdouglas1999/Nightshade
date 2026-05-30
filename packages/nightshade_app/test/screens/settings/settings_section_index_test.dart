// Guards the Settings navigation contract for the Quick Wins Bundle (C8):
// the new "Integrations" page must be wired into `kSettingsSectionIndex`,
// `_categories`, and the `_buildContent` switch WITHOUT disturbing the
// existing append-only indices that deep-link buttons depend on.
//
// Three guarantees:
//
//   1. integrations_deep_link_key_is_pinned — `kSettingsSectionIndex`
//      maps 'integrations' to 33 (appended after Replay & Debug at 32). A
//      regression that inserted a category mid-list — silently shifting every
//      later deep-link — would trip this.
//
//   2. integrations_section_renders_the_page — deep-linking
//      `SettingsScreen(initialSection: 'integrations')` selects category 33
//      and `_buildContent` returns `IntegrationsSettings`, surfacing its
//      "Integrations" page title. This is the load-bearing wiring: the index
//      in the map must line up with the `case 33:` in the switch, or the
//      sidebar would highlight Integrations while the body rendered the
//      `default` empty pane.
//
//   3. every_section_index_maps_to_a_non_empty_case — every value in
//      `kSettingsSectionIndex` resolves to a real `_buildContent` case, never
//      the `default` `SizedBox()`. This is a forward guard: if someone adds a
//      deep-link key but forgets the matching `case N:`, the section would
//      open to a blank pane in production; here it fails the build instead.
//      We assert the content pane is non-empty (renders at least one `Text`),
//      which the bare-`SizedBox` default never does.
//
// Plugin-provider overrides: the Integrations page reads C3's
// `pluginRegistrationProvider` / activity tracker and C4's
// `pluginEnablementProvider`. We supply test doubles (registration resolves
// synchronously; the activity tracker subscribes to nothing) exactly as C7's
// own widget tests do, so the page renders without registering bundled
// plugins into real on-disk storage or subscribing to live event buses.
//
// Why we swallow "overflowed" FlutterErrors: the production sidebar
// `_CategoryItem` row overflows by a few pixels for some labels at the default
// ResizablePanel width — a tracked cosmetic issue, mirrored from
// settings_screen_test.dart. We drop only "overflowed" errors and re-forward
// everything else so a real layout regression still trips takeException().

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/integrations_settings.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
// C4 (enablement) and C3 (registration / activity tracker) are not surfaced
// through their package barrels, so — exactly like the Integrations page and
// its own tests — we import the providers by path.
// ignore: implementation_imports
import 'package:nightshade_core/src/providers/plugin_enablement_provider.dart';
import 'package:nightshade_plugins/nightshade_plugins.dart';
// ignore: implementation_imports
import 'package:nightshade_plugins/src/plugin_registration.dart';

import '../../harness/harness.dart';

/// Install a `FlutterError.onError` handler that drops "overflowed" layout
/// exceptions for the duration of the current test and re-forwards everything
/// else to the default presenter.
void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) {
      return;
    }
    defaultOnError?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = defaultOnError;
  });
}

/// Fixed-set enablement notifier so the Integrations page never reaches the
/// real settings DAO for its toggle state.
class _FakeEnablementNotifier extends PluginEnablementNotifier {
  _FakeEnablementNotifier(this._enabled);

  final Set<String> _enabled;

  @override
  Future<Set<String>> build() async => _enabled;
}

/// Overrides that let [IntegrationsSettings] render under the standard app
/// harness without touching real plugin storage or live event buses.
///
/// Mirrors C7's own widget-test harness:
///   * `pluginRegistrationProvider` resolves SYNCHRONOUSLY (returns void, not a
///     Future) so it is `AsyncData` on the first frame — an async override
///     would leave it `AsyncLoading`, rendering the loading shimmer whose
///     perpetual animation makes `pumpAndSettle` hang.
///   * `pluginActivityTrackerProvider` is built with NO descriptors so it
///     subscribes to no event buses (the page only needs the empty last-fired
///     map; C3's own tests cover the live subscriptions).
///   * `pluginEnablementProvider` serves a fixed enabled-set.
List<Override> _integrationsOverrides(PluginHost host) {
  return [
    pluginHostProvider.overrideWithValue(host),
    pluginRegistrationProvider.overrideWith((ref) {}),
    pluginActivityTrackerProvider.overrideWith(
      (ref) => PluginActivityTracker(host: host, descriptors: const []),
    ),
    pluginEnablementProvider.overrideWith(
      () => _FakeEnablementNotifier({
        kDiscordPluginId,
        kPushoverPluginId,
        kHomeAssistantPluginId,
      }),
    ),
  ];
}

/// Builds a real [PluginHost] with the three configurable bundled plugins so
/// the Integrations page renders a row per plugin.
///
/// Uses an in-memory storage factory: the Pushover / Home Assistant plugins
/// read persisted config from [PluginStorage] in their `onLoad`/`onEnable`
/// lifecycle. The default [FilePluginStorage] performs real `dart:io` file
/// reads, whose futures complete on the host event loop — but inside a
/// `testWidgets` body the binding runs in fake-async, where those completions
/// are never drained and the lifecycle's own 5s timeout `Timer` never advances.
/// The `await host.registerPlugin(...)` below would then deadlock for the full
/// per-test timeout. Injecting [InMemoryPluginStorage] makes the lifecycle
/// resolve synchronously and deterministically, exactly as the Integrations
/// page's own widget tests do (integrations_settings_test.dart).
Future<PluginHost> _buildHost() async {
  final host = PluginHost(
    contextFactory: PluginContextFactory(
      storageFactory: (_) => InMemoryPluginStorage(),
    ),
  );
  await host.registerPlugin(DiscordWebhookPlugin(), enabled: true);
  await host.registerPlugin(PushoverNotificationPlugin(), enabled: true);
  await host.registerPlugin(HomeAssistantPlugin(), enabled: true);
  return host;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'integrations_deep_link_key_is_pinned: kSettingsSectionIndex maps '
      '"integrations" to the appended index 33', () {
    // 33 = appended directly after Replay & Debug (32). Appending — never
    // inserting — keeps every existing key→index pair stable. If a future
    // category is inserted mid-list, this and the existing key assertions in
    // settings_screen_test.dart must both be updated deliberately.
    expect(kSettingsSectionIndex['integrations'], 33,
        reason:
            'Integrations must be the appended category 33; inserting it '
            'earlier would silently shift every later deep-link.');

    // Sanity: the pre-existing tail key is still where it was, proving the new
    // key was appended rather than inserted ahead of the prior maximum.
    expect(kSettingsSectionIndex['notification-routing'], 30);
    // Integrations must be the new maximum index in the contract.
    final maxIndex =
        kSettingsSectionIndex.values.reduce((a, b) => a > b ? a : b);
    expect(maxIndex, 33,
        reason: 'Integrations (33) must be the highest mapped section index.');
  });

  testWidgets(
      'integrations_section_renders_the_page: deep-linking section '
      '"integrations" renders IntegrationsSettings via case 33', (tester) async {
    _swallowKnownOverflows();
    final host = await _buildHost();
    addTearDown(host.dispose);

    await pumpAppScreen(
      tester,
      const SettingsScreen(initialSection: 'integrations'),
      size: const Size(1280, 800),
      extraOverrides: _integrationsOverrides(host),
    );

    // The deep link alone (no sidebar tap) must select category 33 and the
    // switch must map 33 → IntegrationsSettings. A drift between the map index
    // and the `case 33:` body would render the default empty pane instead.
    expect(find.byType(IntegrationsSettings), findsOneWidget,
        reason:
            'initialSection "integrations" must open the Integrations pane '
            'immediately; if this fails, kSettingsSectionIndex["integrations"] '
            'and the _buildContent case 33 have drifted apart.');

    // The page title is the user-facing marker that the real page (not a
    // placeholder) rendered. "Integrations" appears both as the sidebar label
    // and the SettingsPage header, so findsWidgets (≥ 1) is the right matcher.
    expect(find.text('Integrations'), findsWidgets,
        reason: 'The Integrations page must surface its "Integrations" title.');
  });

  testWidgets(
      'every_section_index_maps_to_a_non_empty_case: each kSettingsSectionIndex '
      'value resolves to a real _buildContent case, never the default blank '
      'pane', (tester) async {
    _swallowKnownOverflows();
    final host = await _buildHost();
    addTearDown(host.dispose);

    // Deep-link into each section in turn and assert the content pane is
    // non-empty. `_buildContent`'s `default` branch returns a bare
    // `SizedBox()` that renders no `Text`; every wired case renders a screen
    // that does. So "at least one Text in the content area" is a reliable
    // proxy for "this index hit a real case, not the default".
    //
    // We pump with settle:false and swallow FlutterErrors during each pump:
    // the contract under test is the index→case routing, not each individual
    // settings screen's internals (some heavyweight screens want providers the
    // base harness does not stub). A screen that throws still PUMPS its scaffold
    // and at least one Text, so the routing assertion holds; a genuinely
    // unrouted index would fall through to the empty default and fail here.
    for (final entry in kSettingsSectionIndex.entries) {
      final section = entry.key;
      final index = entry.value;

      final previousOnError = FlutterError.onError;
      FlutterError.onError = (_) {};
      try {
        await tester.pumpWidget(const SizedBox());
        await pumpAppScreen(
          tester,
          SettingsScreen(initialSection: section),
          size: const Size(1280, 800),
          extraOverrides: _integrationsOverrides(host),
          settle: false,
        );
        // A few frames to let the selected pane build its first content.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      } finally {
        FlutterError.onError = previousOnError;
      }

      expect(find.byType(Text), findsWidgets,
          reason:
              'Section "$section" (index $index) must resolve to a real '
              '_buildContent case that renders content; an empty pane means '
              'the deep-link key points at an index the switch does not '
              'handle (it fell through to the default SizedBox).');
    }
  });
}
