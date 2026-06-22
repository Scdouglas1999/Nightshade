import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the fix for the "promises retraction the app can't deliver" gap: the
/// Constellation contribute/detail copy must not tell the user a contribution
/// "can be retracted" while no in-app retract path exists (the retract id is
/// never persisted, so `ConstellationService.retract` has no app caller yet).
///
/// If a real, reachable retract action lands (a persisted contribution log + a
/// button that calls `retract(...)`), relax this guard alongside it.
void main() {
  const detailScreen =
      'lib/screens/constellation/shared_target_detail_screen.dart';
  const contributeSheet =
      'lib/screens/constellation/constellation_contribute_sheet.dart';

  String read(String relative) {
    final file = File(relative);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'expected $relative relative to the package root (run from '
          'packages/nightshade_app)',
    );
    return file.readAsStringSync();
  }

  test('user-facing constellation copy does not promise an in-app retraction',
      () {
    for (final path in const [detailScreen, contributeSheet]) {
      final source = read(path).toLowerCase();
      expect(
        source.contains('retract'),
        isFalse,
        reason: '$path still tells the user a contribution can be retracted, '
            'but no reachable retract action exists. Either wire a real '
            'retract path or keep the copy describing the additive-sums '
            'property without promising the action.',
      );
    }
  });

  test('contribute consent copy still explains the additive-sums protection',
      () {
    // The reassurance the user consents on must remain honest and present: only
    // additive sums leave the device, so the depth is exactly reversible
    // hub-side. We keep the property, drop the unbacked "you can retract" claim.
    final source = read(contributeSheet);
    expect(source, contains('additive co-add sums'));
    expect(source, contains('subtracted exactly'));
  });
}
