import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/analytics/widgets/science_export_hub.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('science-export-test');
    testerView.physicalSize = const Size(1200, 900);
    testerView.devicePixelRatio = 1;
  });

  tearDown(() {
    testerView.resetPhysicalSize();
    testerView.resetDevicePixelRatio();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  testWidgets('session failure is visible, retryable, and blocks exports',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allSessionsProvider.overrideWith((ref) {
            attempts++;
            return Stream<List<ImagingSession>>.error(
              StateError('session index unavailable'),
            );
          }),
          allTransientDetectionsProvider.overrideWith(
            (ref) => Stream.value(const <TransientDetectionRow>[]),
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: ScienceExportHub()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not load sessions: Bad state: '),
      findsOneWidget,
    );
    final csvButtons = find.widgetWithText(NightshadeButton, 'CSV');
    expect(csvButtons, findsNWidgets(7));
    for (final element in csvButtons.evaluate()) {
      expect((element.widget as NightshadeButton).onPressed, isNull);
    }
    final reportButton = tester.widget<NightshadeButton>(
      find.widgetWithText(
        NightshadeButton,
        'Generate Observation Report (PDF)',
      ),
    );
    expect(reportButton.onPressed, isNull);
    expect(attempts, 1);

    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('all-data CSV includes standalone captures without a session',
      (tester) async {
    var standaloneProviderBuilds = 0;
    var directoryProviderBuilds = 0;
    String? writtenCsv;
    final measurement = PhotometryMeasurementRow(
      id: 1,
      objectId: 'standalone-target',
      role: 'target',
      x: 10,
      y: 20,
      flux: 1234,
      differentialMagnitude: 12.3,
      snr: 42,
      uncertainty: 0.02,
      isOutlier: false,
      timestamp: DateTime.utc(2026, 7, 13, 2),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allSessionsProvider.overrideWith(
            (ref) => Stream.value(const <ImagingSession>[]),
          ),
          // The export reads the COMPLETE-dataset provider, not the capped UI
          // preview stream (the preview cap silently truncated every CSV).
          sessionlessPhotometryExportProvider.overrideWith(
            (ref) {
              standaloneProviderBuilds++;
              return Future.value([measurement]);
            },
          ),
          allTransientDetectionsProvider.overrideWith(
            (ref) => Stream.value(const <TransientDetectionRow>[]),
          ),
          scienceExportDirectoryProvider.overrideWith((ref) {
            directoryProviderBuilds++;
            final directory = Directory('${tempDir.path}/Nightshade/exports');
            directory.createSync(recursive: true);
            return directory;
          }),
          scienceExportFileWriterProvider.overrideWithValue((file, contents) {
            writtenCsv = contents;
            file.writeAsStringSync(contents);
            return Future<void>.value();
          }),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: ScienceExportHub()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All Sessions & Standalone'), findsOneWidget);
    final photometryButton = find.widgetWithText(NightshadeButton, 'CSV').first;
    expect(
        tester.widget<NightshadeButton>(photometryButton).onPressed, isNotNull);
    await tester.ensureVisible(photometryButton);
    await tester.tap(photometryButton);
    await tester.pump();
    final exportDir = Directory('${tempDir.path}/Nightshade/exports');
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (exportDir.existsSync() && exportDir.listSync().isNotEmpty) break;
    }
    await tester.pumpAndSettle();

    final renderedText = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .join(' | ');
    expect(
      find.textContaining('Exported 1 rows to '),
      findsOneWidget,
      reason: 'Standalone builds: $standaloneProviderBuilds; '
          'directory builds: $directoryProviderBuilds; '
          'rendered text: $renderedText',
    );
    final files = exportDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(writtenCsv, contains('standalone-target'));
    expect(files.single.readAsStringSync(), contains('standalone-target'));
  });

  testWidgets('filter controls reflow without overflow at phone width',
      (tester) async {
    testerView.physicalSize = const Size(430, 932);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allSessionsProvider.overrideWith(
            (ref) => Stream.value(const <ImagingSession>[]),
          ),
          allTransientDetectionsProvider.overrideWith(
            (ref) => Stream.value(const <TransientDetectionRow>[]),
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: ScienceExportHub()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All Sessions & Standalone'), findsOneWidget);
    expect(find.text('Start Date'), findsOneWidget);
    expect(find.text('End Date'), findsOneWidget);
  });
}

TestFlutterView get testerView =>
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
