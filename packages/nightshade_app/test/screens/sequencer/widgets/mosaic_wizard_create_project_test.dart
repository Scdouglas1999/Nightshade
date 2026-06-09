// Mosaic M3 — planner-wiring: the "Create mosaic project" action end-to-end
// through the Mosaic Wizard dialog.
//
// Pins that the primary action (a) calls
// `mosaicProjectServiceProvider.createProject` with the wizard's CURRENT design
// (centre RA/Dec + rows × cols + overlap + position angle + per-panel FOV), and
// (b) routes to the new mosaic project screen at `/mosaic/:id` with the returned
// id. It also guards that the existing "Load into Sequencer" path is still
// present (the brief requires keeping that path working).
//
// The wizard is presented via `showDialog` (as production does) so its
// `Navigator.pop()` closes the dialog and the underlying GoRouter handles the
// `/mosaic/:id` push.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/sequencer/widgets/mosaic_wizard_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/mock_backend.dart';
import '../../../harness/pump_app_screen.dart';

class _MockService extends Mock implements MosaicProjectService {}

/// `Symbol("centerRa")` -> `"centerRa"`.
String _symbolName(Symbol symbol) {
  final s = symbol.toString();
  return s.substring('Symbol("'.length, s.length - 2);
}

/// Stub `createProject` to echo [returns] and record each call's named args.
List<Map<String, Object?>> _recordCreateCalls(
  _MockService service, {
  required int returns,
}) {
  final calls = <Map<String, Object?>>[];
  when(() => service.createProject(
        name: any(named: 'name'),
        rows: any(named: 'rows'),
        cols: any(named: 'cols'),
        centerRa: any(named: 'centerRa'),
        centerDec: any(named: 'centerDec'),
        targetId: any(named: 'targetId'),
        overlapPct: any(named: 'overlapPct'),
        positionAngleDeg: any(named: 'positionAngleDeg'),
        panelWidthArcmin: any(named: 'panelWidthArcmin'),
        panelHeightArcmin: any(named: 'panelHeightArcmin'),
        panelTargetId: any(named: 'panelTargetId'),
      )).thenAnswer((invocation) async {
    calls.add({
      for (final e in invocation.namedArguments.entries)
        _symbolName(e.key): e.value,
    });
    return returns;
  });
  return calls;
}

Future<void> _pumpWizard(
  WidgetTester tester, {
  required MosaicProjectService service,
  required void Function(String id) onMosaicRoute,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final backend = mockBackend();
  when(() => backend.hasCheckpoint()).thenAnswer((_) async => false);

  final router = GoRouter(
    initialLocation: '/wizard',
    routes: [
      GoRoute(
        path: '/wizard',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const MosaicWizardDialog(
                    initialRa: 12.5,
                    initialDec: 30.0,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/mosaic/:id',
        builder: (context, state) {
          onMosaicRoute(state.pathParameters['id']!);
          return const Scaffold(body: Text('mosaic-project-screen'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider
            .overrideWith((ref) => TestBackendNotifier(ref, backend)),
        smartNightExposureContextProvider.overrideWith((ref) async => null),
        mosaicProjectServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp.router(
        theme: NightshadeTheme.dark,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Open the dialog. The wizard's pre-existing narrow stats column can overflow
  // on the test surface; that overflow predates this action and is not under
  // test, so swallow only that specific message around the dialog open/render.
  final priorOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed by')) {
      return;
    }
    priorOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = priorOnError);

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Create mosaic project calls createProject with the design and routes to /mosaic/:id',
      (tester) async {
    final service = _MockService();
    final calls = _recordCreateCalls(service, returns: 314);

    String? routedId;
    await _pumpWizard(
      tester,
      service: service,
      onMosaicRoute: (id) => routedId = id,
    );

    expect(
      find.byKey(const ValueKey('mosaic_create_project_btn')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('mosaic_create_project_btn')));
    await tester.pumpAndSettle();

    expect(calls, hasLength(1), reason: 'exactly one create call');
    final args = calls.single;
    // The default wizard design: 3×3 grid, 10% overlap, 0° rotation, opened at
    // RA 12.5h / Dec 30.0°, default panel 60×40 arcmin.
    expect(args['name'], 'Mosaic 12.50h 30.0°');
    expect(args['rows'], 3);
    expect(args['cols'], 3);
    expect(args['centerRa'], 12.5);
    expect(args['centerDec'], 30.0);
    expect(args['overlapPct'], 10.0);
    expect(args['positionAngleDeg'], 0.0);
    expect(args['panelWidthArcmin'], 60.0);
    expect(args['panelHeightArcmin'], 40.0);
    // Capture-wiring (blocker b): the create-project path threads a
    // panelTargetId callback end-to-end (wizard design -> controller ->
    // service). For the wizard's ad-hoc centre it is null — the project-service
    // assigns the distinct per-panel capture targets inside createProject — but
    // the argument MUST be present in the call so the plumbing exists. Before
    // the fix the controller dropped it entirely and the service signature had
    // no such parameter.
    expect(args.containsKey('panelTargetId'), isTrue,
        reason: 'the per-panel target callback must be wired through createProject');
    expect(args['panelTargetId'], isNull,
        reason: 'ad-hoc wizard centre defers per-panel target assignment to the service');

    expect(routedId, '314',
        reason: 'routes to /mosaic/<new project id> after create');
    expect(find.text('mosaic-project-screen'), findsOneWidget);
  });

  testWidgets('the load-into-sequencer path is still present', (tester) async {
    final service = _MockService();
    final calls = _recordCreateCalls(service, returns: 1);
    await _pumpWizard(
      tester,
      service: service,
      onMosaicRoute: (_) {},
    );

    expect(
      find.byKey(const ValueKey('mosaic_generate_sequence_btn')),
      findsOneWidget,
      reason: 'the existing load-into-sequencer action must remain available',
    );
    expect(calls, isEmpty,
        reason: 'merely opening the wizard creates no project');
  });

  testWidgets(
      'W1: Load into Sequencer gives every panel a minAltitude altitude gate',
      (tester) async {
    // W1 no-daylight/altitude gate: the wizard's "Load into Sequencer" path
    // must default MosaicSequenceOptions.minAltitude to the Smart Night floor
    // so every panel TargetHeader carries a minAltitude (serialized as
    // `min_altitude` => a `start_when AltitudeAbove` wait in the executor).
    // Before the fix the wizard passed no minAltitude and every panel header's
    // minAltitude was null — a panel could begin imaging below the horizon
    // floor. This taps the real button and reads the generated sequence back.
    final service = _MockService();
    _recordCreateCalls(service, returns: 1);
    await _pumpWizard(
      tester,
      service: service,
      onMosaicRoute: (_) {},
    );

    await tester.tap(find.byKey(const ValueKey('mosaic_generate_sequence_btn')));
    await tester.pumpAndSettle();

    // Read the sequence the wizard loaded into the editor.
    final context = tester.element(find.byType(MaterialApp));
    final container = ProviderScope.containerOf(context);
    final sequence = container.read(currentSequenceProvider);
    expect(sequence, isNotNull,
        reason: 'Load into Sequencer creates/populates the editor sequence');

    final headers =
        sequence!.nodes.values.whereType<TargetHeaderNode>().toList();
    expect(headers, isNotEmpty, reason: '3x3 default => 9 panel headers');
    expect(
      headers.every((h) => h.minAltitude == const SmartNightSettings().minAltitudeDeg),
      isTrue,
      reason: 'every panel must gate on the Smart Night minimum altitude floor',
    );
    expect(headers.every((h) => h.hasAltitudeConstraints), isTrue);
  });
}
