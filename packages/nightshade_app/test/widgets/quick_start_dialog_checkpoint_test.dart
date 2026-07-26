import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/quick_start_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

QuickStartContext _context({required bool canResume}) {
  return QuickStartContext(
    sessionId: 7,
    sessionName: 'Andromeda night',
    targetName: 'M31',
    sequenceName: 'M31 sequence',
    completedFrames: 12,
    totalFrames: 20,
    lastSessionDate: DateTime.now().subtract(const Duration(hours: 2)),
    totalIntegrationHours: 1.2,
    canResumeFromCheckpoint: canResume,
  );
}

Widget _host(QuickStartContext context) {
  return MaterialApp(
    theme: NightshadeTheme.dark,
    home: Scaffold(
      body: QuickStartDialog(
        quickStartContext: context,
        onStartFresh: () {},
        onResumeProgress: () {},
        onSkip: () {},
      ),
    ),
  );
}

void main() {
  testWidgets('historical progress offers setup loading, not fake resume',
      (tester) async {
    await tester.pumpWidget(_host(_context(canResume: false)));
    await tester.pumpAndSettle();

    expect(find.text('Load Previous Setup'), findsOneWidget);
    expect(find.text('Resume Progress'), findsNothing);
    expect(find.text('Start Fresh'), findsNothing);
  });

  testWidgets('real backend checkpoint offers fresh and resume actions',
      (tester) async {
    await tester.pumpWidget(_host(_context(canResume: true)));
    await tester.pumpAndSettle();

    expect(find.text('Start Fresh'), findsOneWidget);
    expect(find.text('Resume Progress'), findsOneWidget);
    expect(find.text('Load Previous Setup'), findsNothing);
  });
}
