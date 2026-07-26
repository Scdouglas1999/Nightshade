import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/settings/widgets/rig_catalog_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }

  void switchTo(NightshadeBackend backend) => state = backend;
}

const _installedStars = RemoteCatalogStatus(
  name: 'stars',
  status: 'installed',
  version: '4.2',
);

const _missingStars = RemoteCatalogStatus(
  name: 'stars',
  status: 'missing',
);

const _availableStars = RemoteAvailableCatalog(
  name: 'stars',
  displayName: 'HYG Stars',
  version: '4.2',
  description: 'Plate-solving star catalog',
  sizeBytes: 1024,
  requiredForPlateSolve: true,
);

void _stubCatalogs(
  _MockNetworkBackend backend, {
  List<RemoteCatalogStatus> status = const [],
  List<RemoteAvailableCatalog> available = const [],
}) {
  when(() => backend.getCatalogStatus()).thenAnswer(
    (_) async => RemoteCatalogStatusResponse(
      catalogs: status,
      totalBytes: 0,
      dataDir: '/catalogs',
    ),
  );
  when(() => backend.listAvailableCatalogs())
      .thenAnswer((_) async => available);
}

Future<_SwappableBackendNotifier> _pump(
  WidgetTester tester,
  _MockNetworkBackend backend,
) async {
  late _SwappableBackendNotifier notifier;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWith((ref) {
          notifier = _SwappableBackendNotifier(ref, backend);
          return notifier;
        }),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(body: RigCatalogSettings(isMobile: true)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('missing status row remains downloadable on a fresh rig',
      (tester) async {
    final backend = _MockNetworkBackend();
    _stubCatalogs(
      backend,
      status: const [_missingStars],
      available: const [_availableStars],
    );
    await _pump(tester, backend);

    expect(find.textContaining('No catalogs installed'), findsOneWidget);
    final download = tester.widget<NightshadeButton>(
      find.widgetWithText(NightshadeButton, 'Download'),
    );
    expect(download.onPressed, isNotNull);
    expect(
      tester
          .widget<NightshadeButton>(
            find.widgetWithText(NightshadeButton, 'Reload'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('failed hash result is reported as verification failure',
      (tester) async {
    final backend = _MockNetworkBackend();
    _stubCatalogs(backend, status: const [_installedStars]);
    when(() => backend.verifyCatalog(name: 'stars')).thenAnswer(
      (_) async => const {
        'stars': RemoteCatalogVerifyResult(
          ok: false,
          errors: ['checksum mismatch'],
        ),
      },
    );
    await _pump(tester, backend);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Verify'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Verify failed'), findsOneWidget);
    expect(find.textContaining('checksum mismatch'), findsOneWidget);
    expect(find.textContaining('catalog verified'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('download waits for terminal job and reports job failure',
      (tester) async {
    final backend = _MockNetworkBackend();
    _stubCatalogs(
      backend,
      status: const [_missingStars],
      available: const [_availableStars],
    );
    when(() => backend.downloadCatalog('stars')).thenAnswer(
      (_) async => const RemoteJob(
        jobId: 'catalog-job',
        operation: 'catalog.download',
        state: 'queued',
      ),
    );
    when(
      () => backend.awaitJobCompletion(
        'catalog-job',
        timeout: const Duration(minutes: 30),
      ),
    ).thenAnswer(
      (_) async => const RemoteJob(
        jobId: 'catalog-job',
        operation: 'catalog.download',
        state: 'failed',
        error: {'message': 'upstream unavailable'},
      ),
    );
    await _pump(tester, backend);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Download'));
    await tester.pump();
    await tester.pump();

    verify(
      () => backend.awaitJobCompletion(
        'catalog-job',
        timeout: const Duration(minutes: 30),
      ),
    ).called(1);
    expect(find.textContaining('Download failed'), findsOneWidget);
    expect(find.textContaining('upstream unavailable'), findsOneWidget);
    expect(find.text('HYG Stars installed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removal requires confirmation', (tester) async {
    final backend = _MockNetworkBackend();
    _stubCatalogs(backend, status: const [_installedStars]);
    when(() => backend.uninstallCatalog('stars')).thenAnswer((_) async {});
    await _pump(tester, backend);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Remove'));
    await tester.pump();
    verifyNever(() => backend.uninstallCatalog('stars'));

    await tester.tap(find.widgetWithText(NightshadeButton, 'Remove').last);
    await tester.pump();
    await tester.pump();

    verify(() => backend.uninstallCatalog('stars')).called(1);
    expect(find.text('stars catalog removed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late action result from old rig cannot report on new rig',
      (tester) async {
    final hostA = _MockNetworkBackend();
    final hostB = _MockNetworkBackend();
    _stubCatalogs(hostA, status: const [_installedStars]);
    _stubCatalogs(
      hostB,
      status: const [_missingStars],
      available: const [_availableStars],
    );
    final verification = Completer<Map<String, RemoteCatalogVerifyResult>>();
    when(() => hostA.verifyCatalog(name: 'stars'))
        .thenAnswer((_) => verification.future);
    final notifier = await _pump(tester, hostA);

    await tester.tap(find.widgetWithText(NightshadeButton, 'Verify'));
    await tester.pump();
    notifier.switchTo(hostB);
    await tester.pump();
    await tester.pump();

    verification.complete(
      const {'stars': RemoteCatalogVerifyResult(ok: true)},
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('catalog verified'), findsNothing);
    final download = tester.widget<NightshadeButton>(
      find.widgetWithText(NightshadeButton, 'Download'),
    );
    expect(download.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
