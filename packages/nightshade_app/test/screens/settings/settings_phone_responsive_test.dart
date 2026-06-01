// Phone-tier responsive tests for SettingsScreen.
//
// The mobile-responsive standard (docs/plans/2026-06-01-mobile-responsive-
// standard.md) requires every screen to work, with no overflow, at three phone
// sizes in BOTH orientations. SettingsScreen is a grouped, searchable list ->
// full-screen detail flow on phones (width < 600).
//
// These tests pump the screen at each phone size in portrait and landscape and
// assert:
//   * no RenderFlex overflow,
//   * the grouped category list renders (group headers present),
//   * the search box is reachable,
//   * tapping a category pushes the full-screen detail pane (and the list is
//     gone), then Back returns to the list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/general_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// In-memory [AppSettingsNotifier] serving a fixed state (no DB/network).
class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this._initial);
  final AppSettingsState _initial;
  @override
  Future<AppSettingsState> build() async => _initial;
}

List<Override> _stubSettings([
  AppSettingsState state = const AppSettingsState(),
]) =>
    [appSettingsProvider.overrideWith(() => _StubAppSettingsNotifier(state))];

/// The three phone sizes from the standard, each in portrait and the rotated
/// landscape variant.
const _phonePortrait = <(String, Size)>[
  ('small 360x640', Size(360, 640)),
  ('modern 390x844', Size(390, 844)),
  ('large 430x932', Size(430, 932)),
];
const _phoneLandscape = <(String, Size)>[
  ('small 640x360', Size(640, 360)),
  ('modern 844x390', Size(844, 390)),
  ('large 932x430', Size(932, 430)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every test size/orientation: no overflow + a reachable, working search box.
  // (When a phone rotates to landscape its width crosses 600, so it correctly
  // adopts the tablet sidebar+detail split rather than the phone list flow —
  // the standard drives layout from width, not a fixed "is a phone" flag.)
  for (final (label, size) in [..._phonePortrait, ..._phoneLandscape]) {
    testWidgets('settings_$label: renders with no overflow and a reachable, '
        'working search box', (tester) async {
      await pumpAppScreen(
        tester,
        const SettingsScreen(),
        size: size,
        extraOverrides: _stubSettings(),
      );

      expect(tester.takeException(), isNull,
          reason: 'SettingsScreen must not overflow at $label.');

      // Grouped categories are present (group headers render in UPPER CASE).
      expect(find.text('GENERAL'), findsOneWidget,
          reason: 'The grouped category list must render at $label.');

      // The search box must be reachable and usable in either layout.
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'latitude');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Location'), findsOneWidget,
          reason: 'Searching must narrow to a matching section at $label.');
      expect(tester.takeException(), isNull,
          reason: 'Searching must not overflow at $label.');
    });
  }

  // Phone PORTRAIT (width < 600) uses list -> full-screen detail navigation.
  for (final (label, size) in _phonePortrait) {
    testWidgets('settings_phone_${label}_detail: tapping a category opens the '
        'full-screen detail pane (list gone), Back returns to the list',
        (tester) async {
      await pumpAppScreen(
        tester,
        const SettingsScreen(),
        size: size,
        extraOverrides: _stubSettings(),
      );

      // The phone list view shows the grouped list, not a detail pane.
      expect(find.byType(GeneralSettings), findsNothing,
          reason: 'The phone flow starts on the list, not a detail pane, '
              'at $label.');

      // The General group is expanded by default; tap its General entry.
      await tester.tap(find.text('General').first);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(tester.takeException(), isNull,
          reason: 'Opening the detail pane must not overflow at $label.');
      expect(find.byType(GeneralSettings), findsOneWidget,
          reason: 'Tapping a category must push its full-screen detail pane '
              'at $label.');
      // The grouped list is gone now that the detail pane is full-screen
      // (list -> detail navigation, not a split).
      expect(find.text('EQUIPMENT'), findsNothing,
          reason: 'The detail pane is full-screen on phone; the grouped list '
              'must not also be visible at $label.');

      // Back returns to the list. The detail header has a single IconButton
      // (the back arrow).
      await tester.tap(find.byType(IconButton).first);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('EQUIPMENT'), findsOneWidget,
          reason: 'Back from the detail pane must restore the grouped list '
              'at $label.');
    });
  }

  // Phone LANDSCAPE (width >= 600) adopts the sidebar + detail SPLIT: the
  // grouped sidebar and a detail pane are visible at once, no list->detail.
  for (final (label, size) in _phoneLandscape) {
    testWidgets('settings_landscape_${label}_split: shows the sidebar + detail '
        'split with the default pane already visible', (tester) async {
      await pumpAppScreen(
        tester,
        const SettingsScreen(),
        size: size,
        extraOverrides: _stubSettings(),
      );

      expect(tester.takeException(), isNull,
          reason: 'The split layout must not overflow at $label.');
      // Both the grouped sidebar (group headers) and the default detail pane
      // render together in the split.
      expect(find.text('GENERAL'), findsOneWidget,
          reason: 'The sidebar must remain visible in the split at $label.');
      expect(find.byType(GeneralSettings), findsOneWidget,
          reason: 'The default General pane renders beside the sidebar at '
              '$label.');
    });
  }
}
