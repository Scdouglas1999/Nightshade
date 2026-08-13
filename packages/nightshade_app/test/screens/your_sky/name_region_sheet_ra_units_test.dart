// Regression: SKY-3 — Your Sky asked for RA in degrees while the rest of the
// app speaks hours.
//
// Found live. The field was labelled `RA (degrees)` with the hint `0-360` and
// accepted digits only. Two tabs away Framing prints the same quantity as
// `05h 35m 16s`, the planetarium readout as `Center RA: 0h 42m 44s`, and
// Framing's own RA box takes sexagesimal. A user who copies the RA in front of
// them into this box lands a region 79 degrees from where they meant, and
// nothing validated or echoed it.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/your_sky/widgets/name_region_sheet.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

/// Records the centre the sheet actually committed.
class _CapturingBackend extends Mock implements NetworkBackend {
  double? raDeg;
  double? decDeg;

  @override
  Future<int> createAtlasRegion({
    required String name,
    required double centerRaDeg,
    required double centerDecDeg,
    required double radiusDeg,
    String kind = 'custom',
    int? targetId,
  }) async {
    raDeg = centerRaDeg;
    decDeg = centerDecDeg;
    return 1;
  }
}

Widget _surface(NetworkBackend backend) {
  return ProviderScope(
    overrides: [
      backendProvider.overrideWith(
        (ref) => _FixedBackendNotifier(ref, backend),
      ),
      skyAtlasRegionWriterProvider.overrideWithValue(
        SkyAtlasRegionWriter.remote(backend),
      ),
      allDbTargetsProvider.overrideWith((ref) => Stream.value(const [])),
    ],
    child: const MaterialApp(home: Scaffold(body: NameRegionSheet())),
  );
}

Future<void> _enterCentre(WidgetTester tester, String ra, String dec) async {
  await tester.tap(find.text('Custom RA/Dec'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), ra);
  await tester.enterText(find.byType(TextField).at(1), dec);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sexagesimal RA lands where the user is looking', (tester) async {
    final backend = _CapturingBackend();
    await tester.pumpWidget(_surface(backend));
    await tester.pumpAndSettle();

    // M42, exactly as Framing prints it.
    await _enterCentre(tester, '05h 35m 16s', "-05 23' 24\"");
    await tester.tap(find.text('Create region'));
    await tester.pumpAndSettle();

    expect(backend.raDeg, closeTo(83.82, 0.01));
    expect(backend.decDeg, closeTo(-5.39, 0.01));
  });

  testWidgets('decimal degrees still mean degrees', (tester) async {
    final backend = _CapturingBackend();
    await tester.pumpWidget(_surface(backend));
    await tester.pumpAndSettle();

    await _enterCentre(tester, '83.82', '-5.39');
    await tester.tap(find.text('Create region'));
    await tester.pumpAndSettle();

    expect(backend.raDeg, closeTo(83.82, 0.01));
    expect(backend.decDeg, closeTo(-5.39, 0.01));
  });

  testWidgets('the sheet echoes the position it read', (tester) async {
    await tester.pumpWidget(_surface(_CapturingBackend()));
    await tester.pumpAndSettle();

    await _enterCentre(tester, '83.82', '-5.39');

    expect(find.textContaining('05:35:16'), findsOneWidget);
    expect(find.textContaining('83.820°'), findsOneWidget);
  });
}
