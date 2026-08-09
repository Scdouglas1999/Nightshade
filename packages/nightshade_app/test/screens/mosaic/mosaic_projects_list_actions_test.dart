// The mosaic projects list used to be a dead end: a full-page list of rows with
// no "New mosaic" action and no back control, so an operator who opened it from
// Analytics could only go deeper into a project or restart the app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_project_controller.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_projects_list_screen.dart';
import 'package:nightshade_app/screens/sequencer/widgets/mosaic_wizard_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

MosaicProject _project() => MosaicProject(
      id: 1,
      name: 'Veil',
      rows: 2,
      cols: 3,
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );

Widget _app({required bool remote}) => ProviderScope(
      overrides: [
        if (remote)
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, _MockNetworkBackend()),
          ),
        mosaicProjectsListProvider.overrideWith((ref) async => [_project()]),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const MosaicProjectsListScreen(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a populated list still offers a way out and a way to add one',
      (tester) async {
    await tester.pumpWidget(_app(remote: false));
    await tester.pumpAndSettle();

    expect(find.text('Veil'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(
      find.widgetWithText(NightshadeButton, 'New mosaic'),
      findsOneWidget,
      reason: 'the list is the natural place to start a mosaic',
    );
  });

  testWidgets('New mosaic opens the planner, not a crash', (tester) async {
    await tester.pumpWidget(_app(remote: false));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NightshadeButton, 'New mosaic'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(tester.takeException(), isNull);
    expect(
      find.byType(MosaicWizardDialog),
      findsOneWidget,
      reason: 'the planner must open, so the list is no longer a dead end',
    );
    // Its create action is present (its label follows the backend: a
    // disconnected client is told to connect first).
    expect(find.byKey(const ValueKey('mosaic_create_project_btn')),
        findsOneWidget);
  });

  testWidgets('the remote host-only state keeps its back control',
      (tester) async {
    await tester.pumpWidget(_app(remote: true));
    await tester.pumpAndSettle();

    expect(
        find.text('Open Mosaic Projects on the imaging host'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });
}
