// COL2-16 / COL2-17 — the Mosaic Wizard must refuse visibly and tell one story.
//
// Driven live, "Create mosaic project" did nothing at all: no snackbar, no
// inline error, no dialog. It is in fact disabled (no panel size), but the only
// explanation was a hover tooltip, so the primary action of the whole feature is
// indistinguishable from a broken button — and one screen below, "Advanced
// (numerical)" pre-filled a concrete 60.0 x 40.0 panel field under a banner
// saying the panel field was unknown.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/sequencer/widgets/mosaic_wizard_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/mock_backend.dart';
import '../../../harness/pump_app_screen.dart';

Future<void> _pumpWizard(
  WidgetTester tester, {
  OpticalConfig? optics,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final backend = mockBackend();
  when(() => backend.hasCheckpoint()).thenAnswer((_) async => false);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider
            .overrideWith((ref) => TestBackendNotifier(ref, backend)),
        smartNightExposureContextProvider.overrideWith((ref) async => null),
        opticalConfigProvider.overrideWithValue(optics),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: MosaicWizardDialog(initialRa: 12.5, initialDec: 30),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _rig = OpticalConfig(
  telescopeName: 'Test scope',
  focalLength: 500,
  aperture: 100,
  cameraName: 'Test cam',
  sensorWidth: 4144,
  sensorHeight: 2822,
  pixelSize: 4.63,
);

void main() {
  testWidgets('the footer says why the primary action cannot run',
      (tester) async {
    await _pumpWizard(tester);

    final reason = find.byKey(const ValueKey('mosaic_action_blocked_reason'));
    expect(reason, findsOneWidget);
    expect(
      tester
          .widget<Text>(
              find.descendant(of: reason, matching: find.byType(Text)))
          .data,
      allOf(contains('Panel size unknown'), contains('Advanced')),
    );
    expect(
      tester
          .widget<NightshadeButton>(
            find.byKey(const ValueKey('mosaic_create_project_btn')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('no reason is shown once the rig supplies a panel size',
      (tester) async {
    await _pumpWizard(tester, optics: _rig);

    expect(
      find.byKey(const ValueKey('mosaic_action_blocked_reason')),
      findsNothing,
    );
    expect(
      tester
          .widget<NightshadeButton>(
            find.byKey(const ValueKey('mosaic_create_project_btn')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Advanced does not pre-fill a panel size the wizard disclaims',
      (tester) async {
    await _pumpWizard(tester);

    await tester.ensureVisible(find.text('Advanced (numerical)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced (numerical)'));
    await tester.pumpAndSettle();

    final width = find.ancestor(
      of: find.text('Panel width (arcmin)'),
      matching: find.byType(TextField),
    );
    final height = find.ancestor(
      of: find.text('Panel height (arcmin)'),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(width).controller!.text, isEmpty);
    expect(tester.widget<TextField>(height).controller!.text, isEmpty);
  });

  testWidgets('typing a panel size in Advanced unblocks the primary action',
      (tester) async {
    await _pumpWizard(tester);

    await tester.ensureVisible(find.text('Advanced (numerical)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced (numerical)'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.ancestor(
        of: find.text('Panel width (arcmin)'),
        matching: find.byType(TextField),
      ),
      '60',
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mosaic_unknown_panel_size_banner')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mosaic_action_blocked_reason')),
      findsNothing,
    );
    expect(
      tester
          .widget<NightshadeButton>(
            find.byKey(const ValueKey('mosaic_create_project_btn')),
          )
          .onPressed,
      isNotNull,
    );
  });
}
