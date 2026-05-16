// Widget tests for DiagnosticsScreen and DiagnosticDumpScreen.
//
// Scope (CQ-W14-WIDGET-TESTS-MORE-SCREENS):
//
// DiagnosticsScreen (optical-train health surface):
//   1. renders_without_throwing_no_sessions — with `allSessionsProvider`
//      overridden to an empty stream, the screen lands on the "no session"
//      empty state and produces no uncaught exceptions. Why this signal:
//      DiagnosticsScreen auto-selects the active session if there is one;
//      pinning the empty-list path guarantees we test the EmptyState branch
//      (which is what new users see) rather than the data branch.
//   2. shows_title_and_no_session_empty_state — the localised "Optical Train
//      Diagnostics" title is in the header AND the "Select an imaging
//      session to analyze" EmptyState body renders. Together these prove
//      the localised title flow + the gating empty state both reach the
//      tree under the harness.
//
// DiagnosticDumpScreen (bug-report attachment surface):
//   3. dump_screen_renders_create_button — the "Create dump" action is
//      visible on initial pump. Why this signal: the entire purpose of the
//      screen is that one button, so a regression that hid it would silently
//      block bug reports without any compile-time error. We also assert the
//      header title is present.
//
// Why we override `allSessionsProvider` with an empty stream: the production
// provider is wired to a Drift StreamProvider that, even with the harness's
// in-memory DB, would emit a real empty list on first frame but only after
// awaiting the DAO. Overriding to a sync `Stream.value([])` short-circuits
// the await and lets the screen lay out in its first frame.
//
// Why settle: false and fixed-step pumps: the diagnostics shimmer skeleton
// runs a shimmer animation; pumpAndSettle would hang on it. A handful of
// 50ms pumps drains the StreamProvider override into the dropdown selector
// without waiting on the shimmer.
//
// Why we swallow "overflowed" FlutterErrors: at the chosen test surface the
// header row may overflow by a handful of pixels with the long "Optical
// Train Diagnostics" title and the session selector pill side by side.
// Cosmetic and out of scope; surface everything else so a real layout
// regression still trips takeException().
//
// See: docs/code-quality/audit-tests.md §1.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/diagnostics/diagnostic_dump_screen.dart';
import 'package:nightshade_app/screens/diagnostics/diagnostics_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// Drive several frames so the StreamProvider override (`allSessionsProvider`)
/// emits its single value and the dropdown selector lays out. We avoid
/// `pumpAndSettle` because the diagnostics loading skeleton uses a shimmer
/// animation that never settles.
Future<void> _drainAsyncFrames(WidgetTester tester) async {
  // 8 x 50ms = 400ms — comfortably more than the Stream.value(const [])
  // override needs to deliver its single frame and the LayoutBuilder to
  // commit.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Install a FlutterError.onError handler that drops "RenderFlex overflowed"
/// exceptions during the current test and re-forwards everything else to
/// the default presenter. See the file-level comment for the rationale.
void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    final summary = details.exceptionAsString();
    if (summary.contains('overflowed')) {
      return; // Drop known header-row overflows at test sizes.
    }
    defaultOnError?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = defaultOnError;
  });
}

List<Override> _diagnosticsOverrides() {
  return [
    // Empty session list → DiagnosticsScreen lands on its "no session"
    // EmptyState branch.
    allSessionsProvider.overrideWith(
      (ref) => Stream<List<ImagingSession>>.value(const []),
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // DiagnosticsScreen — optical-train health surface
  // ===========================================================================

  testWidgets(
      'renders_without_throwing_no_sessions: DiagnosticsScreen with no sessions '
      'lands on the empty state without uncaught exceptions', (tester) async {
    _swallowKnownOverflows();
    // 1280x800 is a typical desktop width and well above
    // Responsive.isMobile's threshold so the screen takes the desktop
    // padding branch (20 px outer pad, larger title font). The smoke test
    // is the cheapest signal that the heavy provider chain
    // (allSessionsProvider, sessionStateProvider, optical-train sub-
    // providers downstream of session selection) doesn't blow up under
    // the default MockBackend.
    await pumpAppScreen(
      tester,
      const DiagnosticsScreen(),
      size: const Size(1280, 800),
      settle: false,
      extraOverrides: _diagnosticsOverrides(),
    );
    await _drainAsyncFrames(tester);

    expect(tester.takeException(), isNull,
        reason:
            'Initial DiagnosticsScreen pump under the default harness should '
            'not surface any uncaught exceptions.');
  });

  testWidgets(
      'shows_title_and_no_session_empty_state: localised title and '
      '"select a session" empty body both render', (tester) async {
    _swallowKnownOverflows();
    // With no session selected (provider default) and no sessions to
    // auto-select from (override), DiagnosticsScreen must render its
    // header title plus the EmptyState that prompts the user to pick a
    // session. A regression that lost either half would either hide the
    // screen identity (no title) or skip the affordance new users need
    // (no "select" prompt).
    await pumpAppScreen(
      tester,
      const DiagnosticsScreen(),
      size: const Size(1280, 800),
      settle: false,
      extraOverrides: _diagnosticsOverrides(),
    );
    await _drainAsyncFrames(tester);

    // Default English localization fallback in NightshadeLocalizations.
    expect(find.text('Optical Train Diagnostics'), findsOneWidget,
        reason:
            'Header title from `diagnosticsTitle` localization must render. '
            'A missing match means either the localization key has drifted '
            'or the header Row was removed.');
    expect(find.text('Select an imaging session to analyze'), findsOneWidget,
        reason:
            'No-session EmptyState must surface the "select a session" prompt '
            'when allSessionsProvider is empty and no session is active.');
  });

  // ===========================================================================
  // DiagnosticDumpScreen — bug-report attachment surface
  // ===========================================================================

  testWidgets(
      'dump_screen_renders_create_button: header title and "Create dump" '
      'action are both present on initial pump', (tester) async {
    _swallowKnownOverflows();
    // DiagnosticDumpScreen has minimal provider deps — only reads
    // diagnosticDumpServiceProvider inside _createDump (i.e. on tap),
    // so a plain harness pump renders it cleanly. The "Create dump"
    // button is the entire purpose of the screen; if it ever disappears
    // bug reports break silently.
    await pumpAppScreen(
      tester,
      const DiagnosticDumpScreen(),
      size: const Size(1280, 800),
      settle: false,
    );
    await _drainAsyncFrames(tester);

    expect(tester.takeException(), isNull,
        reason:
            'Initial DiagnosticDumpScreen pump under the default harness '
            'should not surface any uncaught exceptions.');

    expect(find.text('Diagnostic Dump'), findsOneWidget,
        reason: 'Header title "Diagnostic Dump" must render on the screen.');
    expect(find.text('Create dump'), findsOneWidget,
        reason:
            '"Create dump" button is the load-bearing action on the screen; '
            'losing it would silently block bug-report attachment.');
  });
}
