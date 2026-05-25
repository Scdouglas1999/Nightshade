import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/screens/planetarium/widgets/sidebar_shared_widgets.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('TargetCard renders framing and sequencer actions',
      (tester) async {
    var framed = false;
    var sequenced = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: TargetCard(
            name: 'M51',
            catalog: 'Messier',
            type: 'Galaxy',
            altitude: '72 deg',
            transit: '01:22',
            colors: NightshadeColors.dark,
            onSendToFraming: () => framed = true,
            onAddToSequencer: () => sequenced = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(LucideIcons.frame), findsOneWidget);
    expect(find.byIcon(LucideIcons.listPlus), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.frame));
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.listPlus));
    await tester.pump();

    expect(framed, isTrue);
    expect(sequenced, isTrue);
  });

  testWidgets('TargetCard actions do not overflow narrow sidebars',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(size: Size(300, 600)),
          child: Scaffold(
            body: SizedBox(
              width: 300,
              child: TargetCard(
                name: 'A Very Long Primary Recommendation Name',
                catalog: 'OpenNGC',
                type: 'Emission Nebula',
                altitude: '72 deg',
                transit: '01:22',
                colors: NightshadeColors.dark,
                onSendToFraming: () {},
                onAddToSequencer: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
