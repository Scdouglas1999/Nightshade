import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/dialogs/indi_server_dialog.dart';
import 'package:nightshade_app/screens/equipment/dialogs/profile_editor_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../golden/surface_golden_harness.dart';
import '../../harness/mock_database.dart';

const double profileEditorLabelWidthForTest = 116;

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final db = mockDatabase();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        activeProfileProvider.overrideWith((ref) => Stream.value(null)),
        allProfilesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final size in const [
    Size(700, 900),
    Size(760, 700),
    Size(1280, 900),
    Size(420, 900),
  ]) {
    testWidgets('profile editor lays out without overflow at $size',
        (tester) async {
      await _pumpAt(tester, size, const ProfileEditorDialog());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('optical train page lays out without overflow at 700', (
    tester,
  ) async {
    await _pumpAt(
      tester,
      const Size(700, 900),
      const ProfileEditorDialog(mode: ProfileEditorMode.opticalTrainPage),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('no form label wraps to a second line', (tester) async {
    await SurfaceGoldenHarness.ensureFonts();
    for (final label in const [
      'Profile name',
      'Icon',
      'Accent colour',
      'Telescope / OTA',
      'Focal length',
      'Aperture',
      'Reducer / barlow',
      'Camera',
      'Mount',
      'Focuser',
      'Filter wheel',
      'Guider',
      'Rotator',
      'Dome',
      'Weather',
      'Safety monitor',
      'Switch',
      'Cover / calibrator',
      'Gain',
      'Offset',
      'Binning',
      'Cooling target',
      'Centering exposure',
      'Host',
      'Port',
    ]) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: NightshadeTypography.bodySm),
        textDirection: TextDirection.ltr,
      )..layout();
      // ignore: avoid_print
      print('LABELWIDTH $label = ${painter.width.toStringAsFixed(1)}');
      expect(painter.width, lessThan(profileEditorLabelWidthForTest));
    }
  });

  testWidgets('indi dialog lays out without overflow at 700', (tester) async {
    await _pumpAt(tester, const Size(700, 900), const IndiServerDialog());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fully-populated profile lays out without overflow at 700',
      (tester) async {
    await _pumpAt(
      tester,
      const Size(700, 900),
      const ProfileEditorDialog(
        profile: EquipmentProfileModel(
          id: 7,
          name: 'Backyard rig',
          telescopeName: 'Sky-Watcher Esprit 100ED',
          telescopeFocalLength: 550,
          telescopeAperture: 100,
          focalLength: 440,
          aperture: 100,
          cameraId: 'ascom:ZWO.ASI2600MM.Pro.Camera.Device.1',
          cameraName: 'ASI2600MM Pro',
          mountId: 'ascom:ASCOM.SoftwareBisque.Telescope',
          mountName: 'Paramount MyT',
          filterWheelId: 'ascom:ZWO.EFW.FilterWheel.1',
          filterWheelName: 'EFW 7x36',
          coverCalibratorId: 'ascom:Alnitak.CoverCalibrator.1',
          filterNames: ['Luminance', 'Red', 'Green', 'Blue', 'Ha'],
          defaultGain: 100,
          defaultOffset: 50,
          defaultCoolingTemp: -10,
          defaultCenteringExposure: 5,
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    // Collapse every section, then expand them again: both states must lay out.
    for (final title in const [
      'Profile identity',
      'Optical train',
      'Devices',
      'Camera defaults',
    ]) {
      await tester.ensureVisible(find.byTooltip('Collapse $title'));
      await tester.pump();
      await tester.tap(find.byTooltip('Collapse $title'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('Expand $title'));
      await tester.pump();
      await tester.tap(find.byTooltip('Expand $title'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the validation banner lays out without overflow at 700',
      (tester) async {
    await _pumpAt(tester, const Size(700, 900), const ProfileEditorDialog());
    // Blank name plus junk optics: several problems at once.
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'e.g., 550',
      ),
      '-4',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'e.g., 10',
      ),
      'nonsense',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Fix 3 problems'), findsOneWidget);
  });
}
