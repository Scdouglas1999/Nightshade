import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout_provider.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_screen.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _TestDashboardLayoutNotifier extends DashboardLayoutNotifier {
  @override
  Future<DashboardLayout> build() async {
    final disabledTiles = DashboardLayout.defaultLayout()
        .tiles
        .map((tile) => tile.copyWith(enabled: false))
        .toList();

    return DashboardLayout(
      version: DashboardLayout.currentVersion,
      tiles: disabledTiles,
      secondaryZoneWidth: 0.4,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Widget picker dialog opens without exceptions', (tester) async {
    tester.binding.window.devicePixelRatioTestValue = 1.0;
    tester.binding.window.physicalSizeTestValue = const Size(780, 600);
    addTearDown(() {
      tester.binding.window.clearPhysicalSizeTestValue();
      tester.binding.window.clearDevicePixelRatioTestValue();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardLayoutProvider.overrideWith(() => _TestDashboardLayoutNotifier()),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: DashboardScreen(),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));

    final editButton = find.byWidgetPredicate(
      (widget) => widget is NightshadeButton && widget.label == 'Edit',
    );
    expect(editButton, findsOneWidget);

    await tester.tap(editButton);
    await tester.pump(const Duration(milliseconds: 200));

    final widgetsButton = find.byWidgetPredicate(
      (widget) => widget is NightshadeButton && widget.icon == LucideIcons.layoutGrid,
    );
    expect(widgetsButton, findsOneWidget);

    await tester.tap(widgetsButton);
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Dashboard Widgets'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
