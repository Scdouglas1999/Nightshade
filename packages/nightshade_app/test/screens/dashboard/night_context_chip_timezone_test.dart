// The Dashboard command bar's night-context chip renders a clock FACE ("Sunset
// 20:14"), so it must honour Settings → Location → Timezone like every other
// clock face on the screen.
//
// A private `_formatClock(DateTime)` reading `t.hour` straight off the raw value
// puts a site at UTC+09:00 in the laptop's zone right beside a header clock in
// the site's: two zones on one screen, with nothing saying which is which.
//
// This drives the production widget through the real provider graph so the
// assertion covers the WIRING (NightContextChip reading `clockProvider`), not
// just the resolver's parameter.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/command_bar.dart';
import 'package:nightshade_app/services/observing_site.dart';
import 'package:nightshade_core/nightshade_core.dart' hide TwilightTimes;
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this.initial);

  final AppSettingsState initial;

  @override
  Future<AppSettingsState> build() async => initial;
}

/// Daytime "now" so `resolveNightContext` takes the sunset branch — the only
/// branch that renders a clock face rather than a duration.
final _now = DateTime(2026, 6, 10, 12, 0);

/// Sunset pinned at 20:14 UTC, with dusk and dawn already behind [_now].
final _twilight = TwilightTimes(
  sunset: DateTime.utc(2026, 6, 10, 20, 14),
  astronomicalDusk: _now.subtract(const Duration(hours: 10)),
  astronomicalDawn: _now.subtract(const Duration(hours: 5)),
);

const _moon = MoonTimes(illumination: 42, phaseName: 'Waning Gibbous');

Widget _wrap(String timezone) {
  return ProviderScope(
    overrides: [
      appSettingsProvider.overrideWith(
        () => _StubAppSettingsNotifier(
          AppSettingsState(timezone: timezone, useSystemTime: false),
        ),
      ),
      siteTwilightTimesProvider.overrideWithValue(_twilight),
      moonInfoProvider.overrideWithValue(_moon),
      observationTimeProvider.overrideWith(
        (ref) => ObservationTimeNotifier()..setTime(_now),
      ),
    ],
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: Builder(
          builder: (context) => Row(
            children: [
              NightContextChip(colors: NightshadeColors.of(context)),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the sunset face follows the chosen site timezone',
      (tester) async {
    await tester.pumpWidget(_wrap('UTC+09:00'));
    await tester.pump();

    expect(find.textContaining('05:14'), findsOneWidget);
    expect(find.textContaining('20:14'), findsNothing);
  });

  testWidgets('a site on UTC reads the UTC face', (tester) async {
    await tester.pumpWidget(_wrap('UTC'));
    await tester.pump();

    expect(find.textContaining('20:14'), findsOneWidget);
  });
}
