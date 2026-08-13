// Regression: a validation message must not outlive the state that produced it.
//
// Found live. In Your Sky > Name a region the "From a target" mode says
// "No targets in your library yet — switch to Custom to enter a sky position by
// hand", yet Create region was enabled; pressing it produced the red
// "Pick a target first.". Switching to Custom RA/Dec — doing exactly what the
// sheet asked — left that error on screen, and it stayed there while RA, Dec and
// a name were filled in, right up to a successful create. So the dialog told the
// user to do something the current mode does not even offer.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/your_sky/widgets/name_region_sheet.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

Widget _surface({List<DbTarget> targets = const []}) {
  return ProviderScope(
    overrides: [
      backendProvider.overrideWith(
        (ref) => _FixedBackendNotifier(ref, _MockNetworkBackend()),
      ),
      allDbTargetsProvider.overrideWith((ref) => Stream.value(targets)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: NameRegionSheet()),
    ),
  );
}

/// The error the custom-coordinate branch raises; reachable by hand, unlike the
/// target branch which is now blocked before it can fail.
const _rangeError =
    'Enter RA as 05h 35m 16s or 83.82°, Dec from -90° to +90°, and a radius '
    'greater than 0° and no more than 180°.';

Future<void> _raiseRangeError(WidgetTester tester) async {
  await tester.tap(find.text('Custom RA/Dec'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '999');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create region'));
  await tester.pumpAndSettle();
  expect(find.textContaining('Enter RA as'), findsOneWidget);
}

void main() {
  testWidgets('Create region is not offered when there is no target to pick',
      (tester) async {
    await tester.pumpWidget(_surface());
    await tester.pumpAndSettle();

    // "From a target" is the default mode and the library is empty.
    expect(
        find.textContaining('No targets in your library yet'), findsOneWidget);

    final button = tester.widget<NightshadeButton>(
      find
          .ancestor(
            of: find.text('Create region'),
            matching: find.byType(NightshadeButton),
          )
          .first,
    );
    expect(
      button.onPressed,
      isNull,
      reason: 'enabling it only to explain afterwards is the original bug',
    );
    expect(find.text('Pick a target first.'), findsNothing);
  });

  testWidgets('switching mode clears the error the other mode raised',
      (tester) async {
    await tester.pumpWidget(_surface());
    await tester.pumpAndSettle();

    await _raiseRangeError(tester);

    await tester.tap(find.text('From a target'));
    await tester.pumpAndSettle();

    expect(find.text(_rangeError), findsNothing);
    expect(find.textContaining('Enter RA as'), findsNothing);
  });

  testWidgets('editing a field clears the error', (tester) async {
    await tester.pumpWidget(_surface());
    await tester.pumpAndSettle();

    await _raiseRangeError(tester);

    await tester.enterText(find.byType(TextField).at(0), '283.4');
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter RA as'), findsNothing);
  });
}
