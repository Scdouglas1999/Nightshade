import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

Widget _host(void Function(WidgetRef) capture) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            capture(ref);
            return const SizedBox(
              width: 400,
              height: 400,
              child: MultiFovOverlay(
                centerRaHours: 6.0,
                centerDecDeg: 0.0,
                fieldOfViewDeg: 10.0,
                viewRotationDeg: 0.0,
              ),
            );
          },
        ),
      ),
    ),
  );
}

const _wideRig = FovPreset(
  id: 'a',
  name: 'Wide',
  focalLengthMm: 480,
  sensorWidthMm: 23.5,
  sensorHeightMm: 15.6,
  pixelSizeMicrons: 3.9,
);

void main() {
  testWidgets('renders nothing interactive when no presets exist', (
    tester,
  ) async {
    await tester.pumpWidget(_host((_) {}));
    expect(find.byType(MultiFovOverlay), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the active preset body pins it to a sky coordinate', (
    tester,
  ) async {
    late WidgetRef captured;
    await tester.pumpWidget(_host((ref) => captured = ref));
    captured.read(fovPresetsProvider.notifier).add(_wideRig);
    await tester.pump();

    // Drag from the center of the overlay rightward.
    final center = tester.getCenter(find.byType(MultiFovOverlay));
    await tester.dragFrom(center, const Offset(40, 0));
    await tester.pump();

    final active = captured.read(fovPresetsProvider).active!;
    // Drag pins the preset, and a rightward drag (toward increasing RA on a
    // standard sky view) shifts the stored center away from the view center.
    expect(active.center, isNotNull);
    expect(active.center!.ra, isNot(closeTo(6.0, 1e-6)));
  });

  testWidgets('dragging empty sky away from the rig does not pin it '
      '(no gesture hijack)', (tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(_host((ref) => captured = ref));
    captured.read(fovPresetsProvider.notifier).add(_wideRig);
    await tester.pump();

    // A narrow-field rig at view center occupies only the middle of the 400px
    // overlay; the top-left corner is well outside its hit region.
    await tester.dragFrom(const Offset(8, 8), const Offset(30, 30));
    await tester.pump();

    // The preset must stay unpinned: the drag fell through to the sky layer.
    expect(captured.read(fovPresetsProvider).active!.center, isNull);
  });

  testWidgets('dragging the rotation handle changes position angle', (
    tester,
  ) async {
    late WidgetRef captured;
    await tester.pumpWidget(_host((ref) => captured = ref));
    captured.read(fovPresetsProvider.notifier).add(_wideRig);
    await tester.pump();

    final initialPa = captured
        .read(fovPresetsProvider)
        .active!
        .positionAngleDeg;
    expect(initialPa, 0);

    // The handle sits above the preset center along the short axis.
    final overlayCenter = tester.getCenter(find.byType(MultiFovOverlay));
    final fov = _wideRig.fovDegrees!;
    const scale = 400 / 2 / (10.0 / 2); // min(w,h)/2 / (fov/2)
    final handle = overlayCenter + Offset(0, -(fov.$2 * scale / 2 + 18));

    // Drag the handle sideways to induce a rotation.
    await tester.dragFrom(handle, const Offset(60, 30));
    await tester.pump();

    final pa = captured.read(fovPresetsProvider).active!.positionAngleDeg;
    expect(pa, isNot(0));
  });

  testWidgets('hidden presets are not drawn (overlay collapses)', (
    tester,
  ) async {
    late WidgetRef captured;
    await tester.pumpWidget(_host((ref) => captured = ref));
    final notifier = captured.read(fovPresetsProvider.notifier);
    notifier.add(_wideRig);
    notifier.toggleVisible('a'); // now hidden
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(captured.read(fovPresetsProvider).active!.visible, isFalse);
  });
}
