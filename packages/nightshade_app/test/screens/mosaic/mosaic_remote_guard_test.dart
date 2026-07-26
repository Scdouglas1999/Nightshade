import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_project_controller.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_project_screen.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_projects_list_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Override> remoteOverrides() => [
        backendProvider.overrideWith(
          (ref) => _FixedBackendNotifier(ref, _MockNetworkBackend()),
        ),
        mosaicProjectsListProvider.overrideWith(
          (ref) => throw StateError(
            'The client-local mosaic project list must not load remotely',
          ),
        ),
        mosaicProjectsDaoProvider.overrideWith(
          (ref) => throw StateError(
            'The client-local mosaic project DAO must not load remotely',
          ),
        ),
      ];

  testWidgets('remote project list is guarded before the local list provider',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: remoteOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const MosaicProjectsListScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Open Mosaic Projects on the imaging host'),
      findsOneWidget,
    );
    expect(find.text('Could not load mosaic projects'), findsNothing);
  });

  testWidgets('remote project is guarded before its local DAO controller',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: remoteOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: MosaicProjectScreen(
            projectId: 42,
            panelOutputPathBuilder: (panel) => '/client/panel.fits',
            stitchOutputDirectory: (project) => '/client/stitch',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Open this mosaic project on the imaging host'),
      findsOneWidget,
    );
    expect(find.text('Mosaic project not found'), findsNothing);
  });
}
