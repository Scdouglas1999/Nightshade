import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/collaborative_sky/collaborative_sky_providers.dart';
import 'package:nightshade_app/screens/collaborative_sky/collaborative_sky_screen.dart';
import 'package:nightshade_app/screens/constellation/constellation_ui_providers.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  CoImagingSession session() => const CoImagingSession(
        sessionId: 's1',
        ownerAccountId: 'owner',
        ownerDisplayName: 'Ada',
        targetName: 'NGC 7000',
        centerRaDeg: 314.7,
        centerDecDeg: 44.5,
        sharedTargetId: 42,
        status: 'active',
        combinedFrames: 240,
        combinedIntegrationSeconds: 7200,
        activeTileId: 99,
        batonHolder: 'owner',
        batonHolderDisplayName: 'Ada',
        participants: [],
      );

  Widget host({
    required bool configured,
    List<CoImagingSession> sessions = const [],
    Future<List<CoImagingSessionRow>> Function()? membershipLoader,
    List<CollabMosaic> mosaics = const [],
    SharedLibrarySummary library =
        const SharedLibrarySummary(publishedCount: 0, pulledCount: 0),
  }) {
    return ProviderScope(
      overrides: [
        constellationConfiguredProvider.overrideWith((ref) => configured),
        constellationHubInfoProvider.overrideWith((ref) async => null),
        constellationDisplayNameProvider.overrideWith((ref) async => ''),
        coImagingSessionsProvider.overrideWith((ref) async => sessions),
        coImagingMembershipsProvider.overrideWith(
          (ref) =>
              membershipLoader?.call() ??
              Future<List<CoImagingSessionRow>>.value(const []),
        ),
        collaborativeMosaicsProvider.overrideWith((ref) async => mosaics),
        sharedLibrarySummaryProvider.overrideWith((ref) async => library),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(body: CollaborativeSkyView()),
      ),
    );
  }

  CoImagingSessionRow joinedMembership() {
    final now = DateTime.utc(2026, 7, 14);
    return CoImagingSessionRow(
      id: 1,
      hubKey: 'https://hub.test',
      sessionId: 's1',
      targetName: 'NGC 7000',
      targetRaDeg: 314.7,
      targetDecDeg: 44.5,
      role: 'contribute',
      claimToken: 'claim',
      framingOffsetIndex: 0,
      framingOffsetRaArcsec: 0,
      framingOffsetDecArcsec: 0,
      contributedFrames: 0,
      contributedIntegrationSeconds: 0,
      active: true,
      joinedAt: now,
      updatedAt: now,
    );
  }

  testWidgets('signed-out body invites connecting to a hub', (tester) async {
    await tester.pumpWidget(host(configured: false));
    await tester.pumpAndSettle();

    expect(find.text('Image the sky together'), findsOneWidget);
    expect(find.text('Connect to a hub'), findsOneWidget);
    // None of the connected sections render before sign-in.
    expect(find.text('Live co-imaging'), findsNothing);
  });

  testWidgets('connected body shows all three collaborative sections (empty)',
      (tester) async {
    await tester.pumpWidget(host(configured: true));
    await tester.pumpAndSettle();

    expect(find.text('Collaborative Sky'), findsOneWidget);
    expect(find.text('Live co-imaging'), findsOneWidget);
    expect(find.text('Collaborative mosaics'), findsOneWidget);
    expect(find.text('Shared calibration'), findsOneWidget);
    // Empty hints, not crashes.
    expect(find.textContaining('No live sessions on this hub yet'),
        findsOneWidget);
    expect(find.textContaining('No collaborative mosaics on this hub yet'),
        findsOneWidget);
    // The shared library card renders its empty pitch.
    expect(
        find.textContaining('Never shoot the same dark twice'), findsOneWidget);
  });

  testWidgets('a live session renders its card with a Join affordance',
      (tester) async {
    await tester.pumpWidget(host(configured: true, sessions: [session()]));
    await tester.pumpAndSettle();

    expect(find.text('NGC 7000'), findsOneWidget);
    expect(find.text('Join session'), findsOneWidget);
    expect(
        find.textContaining('No live sessions on this hub yet'), findsNothing);
  });

  testWidgets('membership loading preserves the session but disables mutation',
      (tester) async {
    final membership = Completer<List<CoImagingSessionRow>>();
    await tester.pumpWidget(host(
      configured: true,
      sessions: [session()],
      membershipLoader: () => membership.future,
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('NGC 7000'), findsOneWidget);
    expect(find.text('Checking membership…'), findsOneWidget);
    expect(find.text('Join session'), findsNothing);
    expect(find.text('Leave'), findsNothing);
  });

  testWidgets('membership error disables mutation and Retry reloads it',
      (tester) async {
    var attempts = 0;
    await tester.pumpWidget(host(
      configured: true,
      sessions: [session()],
      membershipLoader: () {
        attempts++;
        if (attempts == 1) {
          return Future<List<CoImagingSessionRow>>.error(
            StateError('membership database unavailable'),
          );
        }
        return Future<List<CoImagingSessionRow>>.value(const []);
      },
    ));
    await tester.pumpAndSettle();

    expect(find.text('Could not verify membership'), findsOneWidget);
    expect(find.text('Join session'), findsNothing);
    expect(find.text('Leave'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Could not verify membership'), findsNothing);
    expect(find.text('Join session'), findsOneWidget);
  });

  testWidgets('successful matching membership enables Leave, never Join',
      (tester) async {
    await tester.pumpWidget(host(
      configured: true,
      sessions: [session()],
      membershipLoader: () => Future<List<CoImagingSessionRow>>.value(
        [joinedMembership()],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('You are pooling light here'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    expect(find.text('Join session'), findsNothing);
  });
}
