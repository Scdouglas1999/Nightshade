// The desktop app has to be able to tell you a new version exists.
//
// Without a check here, searching Settings for "update" returns About (no update
// control at all) and "Appliance Updates", which is about a REMOTE rig and
// off-network renders one sentence claiming "The local desktop app updates
// itself through its own installer" — untrue of every shipped build: nothing
// calls UpdateNotifier.configure on desktop, so the bundled updater never issues
// a version request, and the Linux build is a tarball with no installer.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/widgets/about_settings.dart';
import 'package:nightshade_app/screens/settings/widgets/update_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

Future<void> _pumpAbout(
  WidgetTester tester, {
  required LatestReleaseChecker checker,
  AppVersionInfo version = const AppVersionInfo(
    version: '6.1.0',
    buildNumber: 21,
  ),
  List<Uri>? launched,
}) async {
  await pumpAppScreen(
    tester,
    const AboutSettings(),
    size: const Size(1200, 1400),
    appVersion: version,
    extraOverrides: [
      latestReleaseCheckerProvider.overrideWithValue(checker),
      if (launched != null)
        aboutLinkLauncherProvider.overrideWithValue((uri) async {
          launched.add(uri);
          return true;
        }),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('About offers a working update check and names the new release',
      (tester) async {
    final launched = <Uri>[];
    await _pumpAbout(
      tester,
      launched: launched,
      checker: () async => const LatestRelease(
        version: '6.2.0',
        url: 'https://github.com/Scdouglas1999/Nightshade/releases/tag/v6.2.0',
      ),
    );

    expect(find.text('Software Update'), findsOneWidget);
    expect(find.text('Version 6.1.0 (build 21)'), findsOneWidget);

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.text('Nightshade 6.2.0 is available.'), findsOneWidget);

    await tester.tap(find.text('View release notes'));
    await tester.pumpAndSettle();
    expect(
      launched.single.toString(),
      'https://github.com/Scdouglas1999/Nightshade/releases/tag/v6.2.0',
    );
  });

  testWidgets('an up-to-date install is told so, not left guessing',
      (tester) async {
    await _pumpAbout(
      tester,
      checker: () async => const LatestRelease(
        version: '6.1.0',
        url: 'https://github.com/Scdouglas1999/Nightshade/releases/latest',
      ),
    );

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(
      find.text('You are running the latest release (6.1.0).'),
      findsOneWidget,
    );
  });

  testWidgets('a failed check says so instead of implying you are current',
      (tester) async {
    await _pumpAbout(
      tester,
      checker: () async => throw const HttpFailure(),
    );

    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not check for updates'), findsOneWidget);
  });

  testWidgets('the appliance page no longer claims the desktop self-updates',
      (tester) async {
    await pumpAppScreen(
      tester,
      const UpdateSettings(),
      size: const Size(1200, 1000),
      settle: false,
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('updates itself through its own installer'),
      findsNothing,
    );
    expect(
      find.textContaining('Settings > About > Check for updates'),
      findsOneWidget,
    );
  });

  group('version comparison', () {
    test('orders releases numerically, not lexically', () {
      expect(compareReleaseVersions('6.10.0', '6.9.0'), greaterThan(0));
      expect(compareReleaseVersions('6.1.0', '6.1.0'), 0);
      expect(compareReleaseVersions('6.0.1', '6.1.0'), lessThan(0));
      expect(compareReleaseVersions('6.1', '6.1.0'), 0);
    });

    test('refuses to guess about an unparseable tag', () {
      expect(compareReleaseVersions('nightly', '6.1.0'), isNull);
    });

    test('strips the tag prefix', () {
      expect(normalizeReleaseVersion('v6.1.0'), '6.1.0');
      expect(normalizeReleaseVersion(' 6.1.0 '), '6.1.0');
    });
  });
}

class HttpFailure implements Exception {
  const HttpFailure();

  @override
  String toString() => 'the release server answered 503';
}
