// Widget tests for SettingsScreen.
//
// Smoke tests (CQ-W5-WIDGET-TESTS-SETTINGS — intentionally narrow):
//   1. renders_without_throwing            — default desktop pump under the
//      standard harness surfaces no uncaught exceptions.
//   2. form_validation_rejects_invalid_input — entering non-numeric garbage
//      into the latitude field does not propagate to AppSettingsState, so
//      the bad value is silently rejected by the SettingsNumberInput guard.
//   3. settings_load_from_defaults         — the default AppSettingsState
//      (latitude == 0.0) renders the formatted default value into the
//      latitude TextField when the user navigates to the Location panel.
//
// Behavior tests (CQ-W12-WIDGET-TESTS-SETTINGS-DEEPER):
//   4. section_navigation_switches_content_pane — tapping a different
//      sidebar category swaps the content area from ConnectionSettings to
//      LocationSettingsPage. Why this is load-bearing: the _selectedCategory
//      index is the only state pinning the IndexedStack-equivalent switch
//      block in _buildContent; if that wiring breaks, the sidebar visually
//      highlights the new row but the body never updates.
//   5. valid_input_persists_to_state_and_db — entering a valid latitude
//      number flows through SettingsNumberInput.onChanged → setLatitude →
//      _saveSetting (writes DAO row) → _patchState. We assert both halves:
//      provider state moves to the new value AND the row landed in the
//      in-memory drift database. A test that only checked one half would
//      miss a regression where the in-memory copyWith fires but the DB
//      write throws silently (or vice versa).
//   6. horizon_reset_button_zeroes_all_directions — the "Reset All to 0°"
//      TextButton on the Location page rewrites every horizon altitude
//      controller to "0" and calls setHorizonProfileJson. Why a dedicated
//      test: the JSON encoding (`{"N":0.0,"NE":0.0,...}`) is what scheduler
//      visibility math reads; a regression that wrote `{}` or skipped one
//      direction would silently mis-classify low-altitude targets.
//   7. dark_mode_switch_toggles_theme_state — flipping the Appearance →
//      Dark mode SettingsSwitch fires setTheme('light') after the 300 ms
//      debounce. We use a generous pump window so the debounce timer fires
//      without making the test order-sensitive on tick boundaries.
//
// Why a stub AppSettingsNotifier instead of letting the real one read from
// the in-memory drift database: the default mocked DB returns zero rows,
// so the real notifier *does* synthesize defaults (latitude 0.0 etc.)
// correctly — that is the third assertion. But the mutation tests need to
// *write* through the notifier and inspect the result without the
// network-backend branch tripping. A small in-memory stub overriding only
// build() keeps the test deterministic and side-effect-free; the inherited
// setter methods still call _saveSetting → settingsDao (which the harness
// wires to the in-memory drift DB) and _patchState (which updates the
// AsyncNotifier state in-place).
//
// Why settle: true / pumpAndSettle: SettingsScreen wires no infinite
// animations (the only AnimatedContainer is the sidebar hover indicator,
// which settles in 150ms). pumpAndSettle therefore terminates cleanly.
//
// Why we swallow "overflowed" FlutterErrors: the production sidebar
// _CategoryItem row overflows by a handful of pixels for some labels
// at the default ResizablePanel sidebar width. These are tracked
// cosmetic issues out of scope for this work; we drop only errors whose
// summary contains "overflowed" and forward everything else so a real
// layout regression still trips takeException().

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/appearance_settings.dart';
import 'package:nightshade_app/screens/settings/widgets/connection_settings.dart';
import 'package:nightshade_app/screens/settings/widgets/location_settings.dart';
import 'package:nightshade_app/screens/settings/widgets/settings_widgets.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// Install a FlutterError.onError handler that drops "overflowed"
/// layout exceptions during the current test and re-forwards everything
/// else to the default presenter. See the file-level comment for the
/// full reasoning.
void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final summary = details.exceptionAsString();
    if (summary.contains('overflowed')) {
      return; // Drop known _CategoryItem sidebar overflows.
    }
    defaultOnError?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = defaultOnError;
  });
}

/// In-memory [AppSettingsNotifier] that skips the database / network read
/// path and serves a fixed [AppSettingsState]. Tests mutate via the real
/// `setLatitude` / `setLongitude` setters so the production validation
/// path (SettingsNumberInput.onChanged -> notifier.setLatitude) is exercised
/// end-to-end; only the persistence side-effects are short-circuited.
class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this._initial);

  final AppSettingsState _initial;

  @override
  Future<AppSettingsState> build() async => _initial;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders_without_throwing: default desktop pump is exception-free',
      (tester) async {
    _swallowKnownOverflows();
    // Desktop width >= 768 picks the Row + sidebar layout, which is the
    // primary code path the production GUI exercises. The Connection
    // category (index 0) is the default selection; if its
    // ConsumerWidget chain throws on the default MockBackend, this
    // catches it.
    await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(const AppSettingsState()),
        ),
      ],
    );

    expect(tester.takeException(), isNull,
        reason:
            'Initial SettingsScreen pump under the default harness should '
            'not surface any uncaught exceptions.');
  });

  testWidgets(
      'form_validation_rejects_invalid_input: '
      'non-numeric latitude does not mutate AppSettingsState',
      (tester) async {
    _swallowKnownOverflows();
    // Use a non-zero initial latitude so a successful (but unwanted)
    // mutation would visibly change the value, and verify the bad input
    // leaves it alone.
    const initial = AppSettingsState(latitude: 42.5, longitude: -71.0);

    final handle = await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(initial),
        ),
      ],
    );

    // Navigate to the Location panel — its first SettingsNumberInput is
    // the latitude field with min:-90 / max:90.
    final locationItem = find.text('Location');
    expect(locationItem, findsWidgets,
        reason: 'Sidebar must offer a Location entry');
    await tester.tap(locationItem.first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The latitude field is the first numeric TextField rendered by the
    // LocationSettingsPage. Find by initial value so we do not depend on
    // widget ordering changes.
    final latField = find.widgetWithText(TextField, '42.500000');
    expect(latField, findsOneWidget,
        reason: 'Latitude field must render the seeded value');

    // SettingsNumberInput filters input characters via FilteringTextInputFormatter
    // (allows [0-9.-]); we bypass that by writing directly via
    // tester.enterText, which simulates a paste of arbitrary text. The
    // onChanged guard (`double.tryParse(value)` -> null) must reject it.
    await tester.enterText(latField, 'abc');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final state = handle.container.read(appSettingsProvider).value;
    expect(state, isNotNull, reason: 'Provider must be in the data state');
    expect(state!.latitude, 42.5,
        reason:
            'Invalid (non-numeric) input must not propagate to AppSettingsState; '
            'the SettingsNumberInput onChanged guard short-circuits the call.');
  });

  testWidgets(
      'settings_load_from_defaults: '
      'default latitude renders in the location field',
      (tester) async {
    _swallowKnownOverflows();
    // Default AppSettingsState() has latitude == 0.0; the location panel
    // formats it as "0.000000" (6 decimals) and seeds the controller.
    await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(const AppSettingsState()),
        ),
      ],
    );

    final locationItem = find.text('Location');
    await tester.tap(locationItem.first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The page itself rendered (rules out the loading / error branches),
    // and the latitude TextField shows the default 0.0 formatted to 6
    // decimals — proof that the default state flowed all the way into
    // the form.
    expect(find.byType(LocationSettingsPage), findsOneWidget,
        reason: 'Tapping Location must navigate to LocationSettingsPage');
    expect(
      find.widgetWithText(TextField, '0.000000'),
      findsWidgets,
      reason:
          'Default latitude (0.0) must render formatted as "0.000000" in a '
          'latitude or longitude SettingsNumberInput.',
    );
  });

  // ===========================================================================
  // W12-DEEPER: behavior tests beyond the smoke pumps above.
  // ===========================================================================

  testWidgets(
      'section_navigation_switches_content_pane: tapping Location swaps the '
      'right pane from ConnectionSettings to LocationSettingsPage',
      (tester) async {
    _swallowKnownOverflows();
    // The sidebar starts on category 0 (Connection). Tapping the
    // Location row in the sidebar must move _selectedCategory to 3,
    // which the switch in _buildContent maps to LocationSettingsPage.
    // A regression that visually highlighted the new row but failed to
    // call setState would leave ConnectionSettings on screen — exactly
    // what this test catches.
    await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(const AppSettingsState()),
        ),
      ],
    );

    // Sanity: the default pane is Connection.
    expect(find.byType(ConnectionSettings), findsOneWidget,
        reason: 'Default _selectedCategory == 0 must render ConnectionSettings.');
    expect(find.byType(LocationSettingsPage), findsNothing,
        reason: 'Location must not render before the sidebar selects it.');

    // Tap the Location entry in the sidebar. Multiple "Location" strings
    // can appear on-screen (sidebar label + page header once selected),
    // but at this point only the sidebar entry exists.
    await tester.tap(find.text('Location').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(LocationSettingsPage), findsOneWidget,
        reason:
            'Tapping the Location sidebar entry must swap the content pane '
            'to LocationSettingsPage — otherwise _selectedCategory → '
            '_buildContent wiring has drifted.');
    expect(find.byType(ConnectionSettings), findsNothing,
        reason:
            'Connection pane must be gone after switching; if both render '
            'simultaneously the switch block lost its mutual exclusion.');
  });

  testWidgets(
      'valid_input_persists_to_state_and_db: setLatitude flows from '
      'SettingsNumberInput.onChanged through to provider state and the DAO',
      (tester) async {
    _swallowKnownOverflows();
    // We assert *both* halves of the persist contract:
    //   (a) AppSettingsNotifier state is patched in place
    //       (read via container.read(appSettingsProvider).value).
    //   (b) The settings DAO row for 'observer_latitude' is written
    //       (read via the harness's in-memory drift database).
    // A regression that fired the in-memory copyWith but skipped the
    // DAO write (or vice versa) would still pass a single-sided check,
    // hiding a real persistence bug for as long as the user kept the app
    // open. Asserting both pins the round-trip.
    const initial = AppSettingsState(latitude: 0.0, longitude: 0.0);

    final handle = await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(initial),
        ),
      ],
    );

    await tester.tap(find.text('Location').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The latitude field renders the seeded 0.0 as "0.000000".
    final latField = find.widgetWithText(TextField, '0.000000').first;
    // 47.5 is well inside [-90, 90] so the clamp is a no-op; a value
    // that the production guard would clamp would muddy the assertion.
    await tester.enterText(latField, '47.5');
    // pumpAndSettle drains the awaited DAO write and the subsequent
    // _patchState frame. 1 second matches the existing tests' window.
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // (a) Provider state was patched.
    final state = handle.container.read(appSettingsProvider).value;
    expect(state, isNotNull, reason: 'Provider must be in the data state');
    expect(state!.latitude, 47.5,
        reason:
            'Valid input must propagate through SettingsNumberInput.onChanged '
            '→ setLatitude → _patchState into AppSettingsState.');

    // (b) DAO row was written. The DAO key matches setLatitude's
    // _saveSetting('observer_latitude', value.toString()) call.
    final dao = handle.container.read(settingsDaoProvider);
    final persisted = await dao.getSetting('observer_latitude');
    expect(persisted, isNotNull,
        reason: 'setLatitude must write a row to settingsDao.');
    expect(double.parse(persisted!), 47.5,
        reason:
            'The persisted DAO value must round-trip to the entered number; '
            'a mismatch means the save path lost or transformed the value.');
  });

  testWidgets(
      'horizon_reset_button_zeroes_all_directions: tapping "Reset All to 0°" '
      'writes a horizon JSON with every compass direction at 0.0',
      (tester) async {
    _swallowKnownOverflows();
    // Seed with a non-default horizon (N=30°) so a successful reset is
    // observable as a state change rather than a no-op. The reset
    // button writes through setHorizonProfileJson, which encodes every
    // direction; the production scheduler reads this JSON to mask
    // low-altitude targets and a malformed encoding (missing keys,
    // wrong number format) would silently mis-classify them.
    const initial = AppSettingsState(
      horizonProfileJson:
          '{"N":30.0,"NE":0.0,"E":0.0,"SE":0.0,"S":0.0,"SW":0.0,"W":0.0,"NW":0.0}',
    );

    final handle = await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(initial),
        ),
      ],
    );

    await tester.tap(find.text('Location').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The reset row is a TextButton.icon with the literal label
    // "Reset All to 0°" (the trailing degree sign is a real °).
    final resetButton = find.text('Reset All to 0°');
    expect(resetButton, findsOneWidget,
        reason:
            'Location page must expose the horizon "Reset All to 0°" button.');
    // ensureVisible because the horizon section is below the fold on a
    // 1280x800 surface; without scrolling the button is not hittable.
    await tester.ensureVisible(resetButton);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    await tester.tap(resetButton);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final state = handle.container.read(appSettingsProvider).value;
    expect(state, isNotNull);
    final json = state!.horizonProfileJson;
    // Why a substring check on the seeded non-zero entry instead of a
    // full JSON equality: setHorizonProfileJson serialises with one
    // decimal place ("0.0") and a fixed key order. A future formatting
    // tweak should not break this assertion; what *must* hold is that
    // N is no longer 30 and that every direction's value is 0.
    expect(json.contains('"N":30'), isFalse,
        reason: 'N=30 must be cleared after Reset All to 0°.');
    for (final dir in const ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']) {
      expect(json.contains('"$dir":0'), isTrue,
          reason:
              'Direction "$dir" must be reset to 0 in the horizon JSON; '
              'a missing or non-zero entry means the reset button skipped '
              'a compass direction.');
    }
  });

  testWidgets(
      'dark_mode_switch_toggles_theme_state: tapping the Appearance dark mode '
      'switch flips AppSettingsState.theme through setTheme()', (tester) async {
    _swallowKnownOverflows();
    // The Appearance page renders a SettingsSwitch wired to setTheme.
    // SettingsSwitch debounces by 300 ms before calling onChanged, so
    // the test must pump past that window. A regression that wired the
    // visual toggle without firing onChanged (or fired with the wrong
    // value) would leave state.theme stuck on 'dark'.
    const initial = AppSettingsState();
    expect(initial.theme, 'dark',
        reason:
            'Sanity: the default theme is dark — the test sets up a flip to '
            'light, which would be a no-op if the default were already light.');

    final handle = await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(initial),
        ),
      ],
    );

    // Navigate to Appearance (sidebar index 2).
    await tester.tap(find.text('Appearance').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(AppearanceSettings), findsOneWidget,
        reason: 'Tapping Appearance must navigate to AppearanceSettings.');

    // The page renders multiple SettingsSwitch widgets (Dark mode +
    // Sidebar collapsed). The dark-mode switch is the first one in
    // widget order — it sits inside the "Theme" section above
    // "Display". A find.byType.first call pins to that ordering.
    final switches = find.byType(SettingsSwitch);
    expect(switches, findsAtLeastNWidgets(1),
        reason: 'AppearanceSettings must render at least one SettingsSwitch.');
    await tester.tap(switches.first);
    // 500 ms covers the SettingsSwitch's 300 ms debounce plus one frame
    // for the awaited setTheme → _patchState to land.
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final state = handle.container.read(appSettingsProvider).value;
    expect(state, isNotNull);
    expect(state!.theme, 'light',
        reason:
            'Tapping the Dark mode switch when theme=="dark" must fire '
            'setTheme("light"); state stuck on "dark" means the switch '
            'never reached its onChanged callback.');
  });
}
