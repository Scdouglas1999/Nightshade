import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/widgets/remote_connection_indicator.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }

  void switchTo(NightshadeBackend backend) => state = backend;
}

void _stubHost(
  _MockNetworkBackend backend,
  String host, {
  BackendConnectionState state = BackendConnectionState.disconnected,
}) {
  when(() => backend.serverHost).thenReturn(host);
  when(() => backend.serverPort).thenReturn(8080);
  when(() => backend.connectionState).thenReturn(state);
  when(() => backend.connectionStateStream)
      .thenAnswer((_) => const Stream<BackendConnectionState>.empty());
  when(() => backend.lastLatency).thenReturn(null);
  when(() => backend.latencyStream)
      .thenAnswer((_) => const Stream<Duration>.empty());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('details sheet reconnect follows the active host authority',
      (tester) async {
    final hostA = _MockNetworkBackend();
    final hostB = _MockNetworkBackend();
    _stubHost(hostA, 'host-a');
    _stubHost(hostB, 'host-b');
    final hostAResult = Completer<void>();
    final hostBResult = Completer<void>();
    when(() => hostA.reconnectNow()).thenAnswer((_) => hostAResult.future);
    when(() => hostB.reconnectNow()).thenAnswer((_) => hostBResult.future);
    late _SwappableBackendNotifier notifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith((ref) {
            notifier = _SwappableBackendNotifier(ref, hostA);
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: RemoteConnectionIndicator()),
        ),
      ),
    );

    await tester.tap(find.byType(RemoteConnectionIndicator));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect now'));
    await tester.pump();
    expect(find.text('Reconnecting...'), findsOneWidget);

    notifier.switchTo(hostB);
    await tester.pump();
    expect(find.text('Reconnect now'), findsOneWidget);
    expect(find.text('host-b'), findsOneWidget);

    await tester.tap(find.text('Reconnect now'));
    await tester.pump();
    verify(() => hostA.reconnectNow()).called(1);
    verify(() => hostB.reconnectNow()).called(1);

    hostAResult.completeError(StateError('old host failure'));
    await tester.pump();
    expect(find.textContaining('Reconnect failed'), findsNothing);
    expect(find.text('Reconnecting...'), findsOneWidget);

    hostBResult.complete();
    await tester.pump();
    expect(find.text('Reconnect now'), findsOneWidget);
  });

  testWidgets('blocked disconnect stays open and explains the active sequence',
      (tester) async {
    final backend = _MockNetworkBackend();
    _stubHost(
      backend,
      'imaging-host',
      state: BackendConnectionState.connected,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _SwappableBackendNotifier(ref, backend),
          ),
          sequenceExecutionStateProvider.overrideWith(
            (ref) => SequenceExecutionState.running,
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: RemoteConnectionIndicator()),
        ),
      ),
    );

    await tester.tap(find.byType(RemoteConnectionIndicator));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pump();

    expect(find.text('Connection Status'), findsOneWidget);
    expect(find.textContaining('Disconnect blocked:'), findsOneWidget);
    expect(
        find.textContaining('Stop the active sequence first'), findsOneWidget);
    verifyNever(backend.dispose);
  });
}
