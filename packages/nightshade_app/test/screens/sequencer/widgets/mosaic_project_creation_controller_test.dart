// Mosaic M3 — planner-wiring: the persist contract.
//
// The "Create mosaic project" action snapshots the wizard's on-screen design
// (centre RA/Dec + rows × cols + overlap + position angle + per-panel FOV) and
// forwards it to the committed `MosaicProjectService.createProject`. This test
// pins exactly that forwarding — every design value reaches the service with
// the right name and unit — without pumping the dialog, so a regression in the
// glue (wrong field mapped, dropped argument, swapped rows/cols) fails loudly.
//
// We read the forwarded values straight from the recorded `Invocation`'s
// `namedArguments` map (keyed by Symbol), which is order-independent and
// self-documenting — no reliance on mocktail's `captureAny` ordering.

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/sequencer/widgets/mosaic_wizard_dialog/mosaic_project_creation_controller.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _MockService extends Mock implements MosaicProjectService {}

/// Stub `createProject` (all args matched by `any`) to echo [returns] AND record
/// each call's named arguments as a `String → value` map.
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
      )).thenAnswer((invocation) async {
    calls.add({
      for (final entry in invocation.namedArguments.entries)
        _symbolName(entry.key): entry.value,
    });
    return returns;
  });
  return calls;
}

/// `Symbol("centerRa")` -> `"centerRa"`.
String _symbolName(Symbol symbol) {
  final s = symbol.toString(); // Symbol("centerRa")
  return s.substring('Symbol("'.length, s.length - 2);
}

void main() {
  late _MockService service;
  late MosaicProjectCreationController controller;

  setUp(() {
    service = _MockService();
    controller = MosaicProjectCreationController(service);
  });

  const design = MosaicProjectDesign(
    name: 'Mosaic 12.50h 30.0°',
    centerRaHours: 12.5,
    centerDecDegrees: 30.0,
    rows: 2,
    cols: 3,
    overlapPercent: 12.0,
    positionAngleDeg: 45.0,
    panelWidthArcmin: 60.0,
    panelHeightArcmin: 40.0,
    targetId: 7,
  );

  test('createProject forwards the design values to the service', () async {
    final calls = _recordCreateCalls(service, returns: 99);

    final id = await controller.createProject(design);

    expect(id, 99,
        reason: 'returns the new mosaic_projects.id from the service');
    expect(calls, hasLength(1), reason: 'exactly one create call');

    final args = calls.single;
    expect(args['name'], 'Mosaic 12.50h 30.0°');
    expect(args['rows'], 2); // vertical panel count
    expect(args['cols'], 3); // horizontal panel count
    expect(args['centerRa'], 12.5); // hours
    expect(args['centerDec'], 30.0); // degrees
    expect(args['targetId'], 7);
    expect(args['overlapPct'], 12.0);
    expect(args['positionAngleDeg'], 45.0);
    expect(args['panelWidthArcmin'], 60.0);
    expect(args['panelHeightArcmin'], 40.0);
  });

  test('a null design targetId is forwarded as null (ad-hoc centre)', () async {
    final calls = _recordCreateCalls(service, returns: 1);

    const adHoc = MosaicProjectDesign(
      name: 'Mosaic 0.00h 0.0°',
      centerRaHours: 0,
      centerDecDegrees: 0,
      rows: 1,
      cols: 2,
      overlapPercent: 10,
      positionAngleDeg: 0,
      panelWidthArcmin: 30,
      panelHeightArcmin: 20,
    );

    await controller.createProject(adHoc);

    expect(calls.single['targetId'], isNull);
  });
}
