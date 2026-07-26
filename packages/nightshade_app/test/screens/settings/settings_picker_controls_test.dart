import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/widgets/settings_widgets.dart';

import '../../harness/harness.dart';

class _ColorHarness extends StatefulWidget {
  const _ColorHarness({required this.save});

  final Future<void> Function(String color) save;

  @override
  State<_ColorHarness> createState() => _ColorHarnessState();
}

class _ColorHarnessState extends State<_ColorHarness> {
  String color = '#5B9EC4';

  Future<void> _save(String next) async {
    await widget.save(next);
    if (mounted) setState(() => color = next);
  }

  @override
  Widget build(BuildContext context) {
    return SettingsColorPicker(
      selectedColor: color,
      onColorSelected: _save,
    );
  }
}

double _colorBorderWidth(WidgetTester tester, String color) {
  final circle = find.byKey(ValueKey('settings-color-$color'));
  final container = tester.widget<Container>(
    find.descendant(of: circle, matching: find.byType(Container)).first,
  );
  final decoration = container.decoration! as BoxDecoration;
  return (decoration.border! as Border).top.width;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('failed color save restores the confirmed selection',
      (tester) async {
    final completion = Completer<void>();
    await pumpAppScreen(
      tester,
      _ColorHarness(save: (_) => completion.future),
    );

    await tester.tap(find.byKey(const ValueKey('settings-color-#10B981')));
    await tester.pump();
    expect(_colorBorderWidth(tester, '#10B981'), 2);

    completion.completeError(StateError('write failed'));
    await tester.pump();
    await tester.pump();

    expect(_colorBorderWidth(tester, '#5B9EC4'), 2);
    expect(_colorBorderWidth(tester, '#10B981'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('path browse ignores repeat taps while the picker is active',
      (tester) async {
    var calls = 0;
    final completion = Completer<void>();
    await pumpAppScreen(
      tester,
      SettingsPathInput(
        path: '/images',
        onBrowse: () {
          calls++;
          return completion.future;
        },
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completion.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('path browse reports async picker failures', (tester) async {
    await pumpAppScreen(
      tester,
      SettingsPathInput(
        path: '',
        onBrowse: () async => throw StateError('picker unavailable'),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();

    expect(find.textContaining('picker unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'path browse unlocks and ignores stale errors after authority change',
      (tester) async {
    final authority = ValueNotifier<Object>(Object());
    final completion = Completer<void>();
    addTearDown(authority.dispose);

    await pumpAppScreen(
      tester,
      ValueListenableBuilder<Object>(
        valueListenable: authority,
        builder: (context, value, child) => SettingsPathInput(
          path: '/images',
          authorityKey: value,
          onBrowse: () => completion.future,
        ),
      ),
    );

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    authority.value = Object();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    completion.completeError(StateError('old host failed'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('old host failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
