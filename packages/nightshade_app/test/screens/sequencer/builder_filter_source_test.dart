// SEQ-19: the builder said "No Filter" / "No filters in profile" while every
// frame of the run was captured, named `M42-TEST_R_0001.fits` and reported
// under filter "R". The authoring surface read the equipment PROFILE and
// nothing else; the capture path uses the connected wheel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/filter_source.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _StubFilterWheel extends FilterWheelStateNotifier {
  _StubFilterWheel(super.ref, FilterWheelState initial) {
    state = initial;
  }
}

Future<BuilderFilterSource> _resolve(
  WidgetTester tester, {
  required FilterWheelState wheel,
}) async {
  late BuilderFilterSource resolved;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        filterWheelStateProvider.overrideWith(
          (ref) => _StubFilterWheel(ref, wheel),
        ),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          resolved = builderFilterSource(ref);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return resolved;
}

void main() {
  testWidgets(
      'a connected wheel supplies the filters when the profile has '
      'none', (tester) async {
    final source = await _resolve(
      tester,
      wheel: const FilterWheelState(
        connectionState: DeviceConnectionState.connected,
        filterNames: ['R', 'G', 'B'],
      ),
    );

    expect(source.names, ['R', 'G', 'B']);
    expect(source.fromWheel, isTrue);
    expect(source.isEmpty, isFalse);
  });

  testWidgets('a disconnected wheel offers nothing, and says so',
      (tester) async {
    final source = await _resolve(
      tester,
      wheel: const FilterWheelState(filterNames: ['R']),
    );

    expect(source.isEmpty, isTrue);
    expect(BuilderFilterSource.emptyHint, isNot(contains('in profile')));
  });
}
