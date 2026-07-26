import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/router/app_router.dart';
import 'package:nightshade_app/widgets/database_recovery_launcher.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  testWidgets('outer-wrapper topology shows consumed recovery marker',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    var consumed = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRouterProvider.overrideWithValue(router)],
        child: DatabaseRecoveryLauncher(
          markerConsumer: () async {
            consumed++;
            return DatabaseRecoveryMarker(
              markerPath: '/tmp/recovered.txt',
              backupPath: '/tmp/nightshade-corrupt.db',
              recoveredAtUtc: DateTime.utc(2026, 7, 14),
              reason: 'integrity check failed',
            );
          },
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(consumed, 1);
    expect(find.text('Database recovered'), findsOneWidget);
    expect(find.text('/tmp/nightshade-corrupt.db'), findsOneWidget);
  });

  testWidgets('acknowledges a recovery marker only after the warning closes',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: Text('Dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    var acknowledgements = 0;
    final marker = DatabaseRecoveryMarker(
      markerPath: '/tmp/recovered.txt',
      backupPath: '/tmp/nightshade-corrupt.db',
      recoveredAtUtc: DateTime.utc(2026, 7, 14),
      reason: 'integrity check failed',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appRouterProvider.overrideWithValue(router)],
        child: DatabaseRecoveryLauncher(
          markerConsumer: () async => marker,
          markerAcknowledger: (value) async {
            expect(identical(value, marker), isTrue);
            acknowledgements++;
          },
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('Database recovered'), findsOneWidget);
    expect(acknowledgements, 0);

    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();

    expect(acknowledgements, 1);
    expect(find.text('Database recovered'), findsNothing);
  });
}
