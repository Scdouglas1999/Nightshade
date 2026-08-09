// Tests for the OSC / Color controls in the live-stacking panel (component
// C14) and the channel-aware stacked-preview pixel conversion.
//
// The panel is exercised with overridden providers so it never reaches the
// native dynamic library: `liveStackingProvider` uses a real notifier (its
// `updateConfig` is a pure state mutation), and the camera providers are
// overridden to control the auto-detection path.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/stacking_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../harness/mock_database.dart' show inMemoryDatabaseOverride;

CameraCapabilities _colorCaps({String? bayerPattern = 'RGGB'}) {
  return CameraCapabilities(
    maxWidth: 1000,
    maxHeight: 1000,
    bitDepth: 16,
    isColor: true,
    bayerPattern: bayerPattern,
  );
}

CameraCapabilities _monoCaps() {
  return const CameraCapabilities(
    maxWidth: 1000,
    maxHeight: 1000,
    bitDepth: 16,
    isColor: false,
  );
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  String? cameraId,
  CameraCapabilities? caps,
  bool isRemote = false,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(420, 1600);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final overrides = <Override>[
    isRemoteModeProvider.overrideWithValue(isRemote),
    connectedCameraIdProvider.overrideWithValue(cameraId),
  ];
  if (cameraId != null && caps != null) {
    overrides.add(
      equipmentCameraCapabilitiesProvider(cameraId)
          .overrideWith((ref) async => caps),
    );
  }

  const colors = NightshadeColors.dark;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(body: StackingPanel(colors: colors)),
      ),
    ),
  );
  // Resolve the caps FutureProvider + run the post-frame seeding callback.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 10));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StackingPanel OSC controls', () {
    testWidgets('remote mode identifies Stack & Share as host-only',
        (tester) async {
      await _pumpPanel(tester, isRemote: true);

      final action = find.widgetWithText(
        NightshadeButton,
        'Stack & Share on imaging host',
      );
      expect(action, findsOneWidget);
      expect(tester.widget<NightshadeButton>(action).onPressed, isNull);
    });

    testWidgets('Color section renders with the switch OFF by default',
        (tester) async {
      await _pumpPanel(tester);

      expect(find.text('Color (OSC)'), findsOneWidget);
      expect(find.text('OSC / Color'), findsOneWidget);

      // No camera connected → pristine mono config → switch OFF → dropdowns
      // hidden.
      expect(find.text('Bayer pattern'), findsNothing);
      expect(find.text('Demosaic quality'), findsNothing);
    });

    testWidgets(
        'toggling the switch ON flips sensorMode off mono and reveals '
        'the Bayer + demosaic dropdowns', (tester) async {
      late ProviderContainer container;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const colors = NightshadeColors.dark;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryDatabaseOverride(),
            isRemoteModeProvider.overrideWithValue(false),
            connectedCameraIdProvider.overrideWithValue(null),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: NightshadeTheme.dark,
                home: const Scaffold(body: StackingPanel(colors: colors)),
              );
            },
          ),
        ),
      );
      await tester.pump();

      // Default config is mono.
      expect(
        container.read(liveStackingProvider).config.sensorMode,
        'mono',
      );

      // Flip the OSC switch ON.
      final toggle = find.descendant(
        of: find.byType(NightshadeSwitchRow),
        matching: find.byType(NightshadeSwitch),
      );
      await tester.tap(toggle);
      await tester.pump();

      // Sensor mode left mono → resolves to auto.
      expect(
        container.read(liveStackingProvider).config.sensorMode,
        'auto',
      );
      expect(find.text('Bayer pattern'), findsOneWidget);
      expect(find.text('Demosaic quality'), findsOneWidget);
    });

    testWidgets(
        'a connected colour camera defaults the switch ON and '
        'preselects the detected pattern', (tester) async {
      await _pumpPanel(
        tester,
        cameraId: 'native:zwo:0',
        caps: _colorCaps(bayerPattern: 'RGGB'),
      );

      // Seeded ON → dropdowns visible, Auto entry names the detected pattern.
      expect(find.text('Bayer pattern'), findsOneWidget);
      expect(find.text('Demosaic quality'), findsOneWidget);
      expect(find.text('Auto (detected: RGGB)'), findsOneWidget);
    });

    testWidgets('a connected mono camera leaves the switch OFF',
        (tester) async {
      await _pumpPanel(
        tester,
        cameraId: 'native:zwo:0',
        caps: _monoCaps(),
      );

      expect(find.text('Bayer pattern'), findsNothing);
      expect(find.text('Demosaic quality'), findsNothing);
    });

    testWidgets('changing the Bayer dropdown updates bayerPattern',
        (tester) async {
      late ProviderContainer container;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(420, 1600);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const colors = NightshadeColors.dark;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inMemoryDatabaseOverride(),
            isRemoteModeProvider.overrideWithValue(false),
            connectedCameraIdProvider.overrideWithValue('native:zwo:0'),
            equipmentCameraCapabilitiesProvider('native:zwo:0')
                .overrideWith((ref) async => _colorCaps(bayerPattern: 'RGGB')),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: NightshadeTheme.dark,
                home: const Scaffold(body: StackingPanel(colors: colors)),
              );
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      // Seeded to auto with RGGB preselected (null override + auto sensor mode).
      expect(container.read(liveStackingProvider).config.sensorMode, 'auto');
      expect(container.read(liveStackingProvider).config.bayerPattern, isNull);

      // Open the Bayer dropdown and pick an explicit BGGR.
      await tester.tap(find.text('Auto (detected: RGGB)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BGGR').last);
      await tester.pumpAndSettle();

      expect(container.read(liveStackingProvider).config.bayerPattern, 'BGGR');

      // Switch back to automatic detection. This used to be a no-op because
      // LiveStackingConfig.copyWith(bayerPattern: null) meant "keep old".
      await tester.tap(find.text('BGGR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto (detected: RGGB)').last);
      await tester.pumpAndSettle();

      expect(container.read(liveStackingProvider).config.bayerPattern, isNull);
    });
  });

  group('stacked preview pixel conversion', () {
    test('mono buffer maps to grayscale RGBA (R==G==B per pixel)', () {
      // 2x1 luminance ramp.
      final mono = Uint16List.fromList([0, 65535]);
      final rgba = stackedPreviewGrayRgba(mono, 2);

      // Pixel 0 → black, pixel 1 → white, both gray (R==G==B).
      expect(rgba[0], 0);
      expect(rgba[1], 0);
      expect(rgba[2], 0);
      expect(rgba[3], 255);
      expect(rgba[4], 255);
      expect(rgba[5], 255);
      expect(rgba[6], 255);
      expect(rgba[7], 255);
    });

    test('interleaved RGB16 buffer maps to distinct per-channel RGBA', () {
      // Three pixels. Each channel has a *different* extent and the middle pixel
      // sits at a *different fraction* of each channel's span, so a correct
      // per-channel stretch must yield three distinct output bytes for the
      // middle pixel — proving it is genuine colour, not a grayscale collapse.
      //
      //   R channel: min 0,  max 100,  mid 25   → 25/100  = 0.25 → ~63
      //   G channel: min 0,  max 100,  mid 50   → 50/100  = 0.50 → ~127
      //   B channel: min 0,  max 100,  mid 75   → 75/100  = 0.75 → ~191
      final rgb = Uint16List.fromList([
        0, 0, 0, // pixel0: all channel minima
        25, 50, 75, // pixel1: distinct per-channel fractions
        100, 100, 100, // pixel2: all channel maxima
      ]);
      final rgba = stackedPreviewColorRgba(rgb, 3);

      // Pixel 0 → each channel min → 0.
      expect(rgba[0], 0);
      expect(rgba[1], 0);
      expect(rgba[2], 0);
      expect(rgba[3], 255);

      // Pixel 1 → distinct per-channel bytes (the colour signal).
      final r1 = rgba[4], g1 = rgba[5], b1 = rgba[6];
      expect(r1, inInclusiveRange(60, 66)); // ~0.25 * 255
      expect(g1, inInclusiveRange(124, 130)); // ~0.50 * 255
      expect(b1, inInclusiveRange(188, 194)); // ~0.75 * 255
      expect(r1 != g1 && g1 != b1, isTrue,
          reason: 'channels must differ — not a grayscale fallback');
      expect(rgba[7], 255);

      // Pixel 2 → each channel max → 255.
      expect(rgba[8], 255);
      expect(rgba[9], 255);
      expect(rgba[10], 255);
      expect(rgba[11], 255);
    });
  });
}
