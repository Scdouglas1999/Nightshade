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

  testWidgets('the advertised catalog contents follow the selected package',
      (tester) async {
    // The dialog printed the Complete figures ("~120,000 stars",
    // "~13,000 DSOs") above a selector that defaults to Standard, so the
    // default choice was advertised as delivering three times what it
    // installs. Both summary lines must track the selection.
    await pumpAppScreen(
      tester,
      const CatalogSetupDialog(),
      size: const Size(900, 1200),
      extraOverrides: [
        catalogSetupManagerProvider.overrideWithValue(_MockCatalogManager()),
      ],
    );

    Future<void> select(CatalogPackage package) async {
      final option = find.text(package.displayName);
      await tester.ensureVisible(option);
      await tester.tap(option);
      await tester.pump();
    }

    // Standard is the default selection.
    expect(find.text('~40,000 stars'), findsOneWidget);
    expect(find.text('~8,000 DSOs (NGC/IC)'), findsOneWidget);
    expect(find.text('~120,000 stars'), findsNothing);

    await select(CatalogPackage.essential);
    expect(find.text('~9,000 stars'), findsOneWidget);
    expect(find.text('~2,000 DSOs (NGC/IC)'), findsOneWidget);
    expect(find.text('~40,000 stars'), findsNothing);

    await select(CatalogPackage.complete);
    expect(find.text('~120,000 stars'), findsOneWidget);
    expect(find.text('~13,000 DSOs (NGC/IC)'), findsOneWidget);

    // Every option states what it installs, not just how many megabytes.
    for (final package in CatalogPackage.values) {
      expect(
        find.text(
          '~${formatCatalogCount(package.approximateStarCount)} stars · '
          '~${formatCatalogCount(package.approximateDsoCount)} DSOs',
        ),
        findsOneWidget,
        reason: '${package.displayName} must show its contents',
      );
    }
  });
}
