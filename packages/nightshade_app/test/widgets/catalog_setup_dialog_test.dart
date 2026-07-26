import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/widgets/catalog_setup_dialog.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../harness/harness.dart';

class _MockCatalogManager extends Mock implements CatalogManager {}

void main() {
  setUpAll(() {
    registerFallbackValue(CatalogPackage.standard);
  });

  testWidgets('disposed catalog setup does not launch the next download',
      (tester) async {
    final manager = _MockCatalogManager();
    final starDownload = Completer<bool>();
    when(
      () => manager.downloadStarCatalog(
        package: any(named: 'package'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) => starDownload.future);

    await pumpAppScreen(
      tester,
      const CatalogSetupDialog(),
      size: const Size(390, 650),
      extraOverrides: [
        catalogSetupManagerProvider.overrideWithValue(manager),
      ],
    );

    final downloadButton =
        find.widgetWithText(NightshadeButton, 'Download Now');
    await tester.ensureVisible(downloadButton);
    await tester.tap(downloadButton);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    starDownload.complete(true);
    await tester.pump();

    verifyNever(
      () => manager.downloadDsoCatalog(
        package: any(named: 'package'),
        onProgress: any(named: 'onProgress'),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed catalog download remains visible and retryable',
      (tester) async {
    final manager = _MockCatalogManager();
    var dsoAttempts = 0;
    var completed = 0;
    when(
      () => manager.downloadStarCatalog(
        package: any(named: 'package'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => true);
    when(
      () => manager.downloadDsoCatalog(
        package: any(named: 'package'),
        onProgress: any(named: 'onProgress'),
      ),
    ).thenAnswer((_) async => ++dsoAttempts > 1);

    await pumpAppScreen(
      tester,
      CatalogSetupDialog(onComplete: () => completed++),
      extraOverrides: [
        catalogSetupManagerProvider.overrideWithValue(manager),
      ],
    );

    var downloadButton = find.widgetWithText(NightshadeButton, 'Download Now');
    await tester.ensureVisible(downloadButton);
    await tester.tap(downloadButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('DSO catalog download failed'), findsOneWidget);
    expect(completed, 0);

    downloadButton = find.widgetWithText(NightshadeButton, 'Download Now');
    await tester.ensureVisible(downloadButton);
    await tester.tap(downloadButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(dsoAttempts, 2);
    expect(completed, 1);
    verify(
      () => manager.downloadStarCatalog(
        package: CatalogPackage.standard,
        onProgress: any(named: 'onProgress'),
      ),
    ).called(1);
  });
}
