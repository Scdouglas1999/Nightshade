import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_mobile/screens/dashboard/tabs/settings_tab.dart';
import 'package:nightshade_mobile/services/mobile_preferences.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a settings toggle is single-flight while persistence runs', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = _DelayedPreferences(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobilePreferencesProvider.overrideWith((ref) async => prefs),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: const [NightshadeColors.dark],
          ),
          home: const Scaffold(body: SettingsTab()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.ancestor(
      of: find.text('Meridian flips'),
      matching: find.byType(SwitchListTile),
    );
    await tester.tap(row);
    await tester.pump();
    expect(prefs.calls, 1);
    expect(tester.widget<SwitchListTile>(row).onChanged, isNull);

    await tester.tap(row);
    await tester.pump();
    expect(prefs.calls, 1);

    prefs.write.complete();
    await tester.pumpAndSettle();
    expect(prefs.notifyMeridianFlip, isFalse);
  });
}

class _DelayedPreferences extends MobilePreferences {
  final Completer<void> write = Completer<void>();
  bool _notifyMeridianFlip = true;
  int calls = 0;

  _DelayedPreferences(super.prefs);

  @override
  bool get notifyMeridianFlip => _notifyMeridianFlip;

  @override
  Future<void> setNotifyMeridianFlip(bool value) async {
    calls++;
    await write.future;
    _notifyMeridianFlip = value;
  }
}
