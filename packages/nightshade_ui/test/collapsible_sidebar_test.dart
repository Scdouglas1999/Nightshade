import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _Host extends StatefulWidget {
  final bool initialCollapsed;
  final ValueChanged<bool>? onCollapsedChange;

  const _Host({super.key, this.initialCollapsed = false, this.onCollapsedChange});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool _collapsed = widget.initialCollapsed;

  void setCollapsed(bool v) => setState(() => _collapsed = v);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: Row(children: [
          CollapsibleSidebar(
            isCollapsed: _collapsed,
            collapsedWidth: 56,
            expandedWidth: 280,
            minExpandedWidth: 220,
            maxExpandedWidth: 400,
            onCollapsedChange: widget.onCollapsedChange,
            collapsedChild: const Center(
                child: Icon(Icons.menu, key: ValueKey('icon'))),
            expandedChild: const Center(
                child: Text('Sidebar Content', key: ValueKey('content'))),
          ),
          const Expanded(child: ColoredBox(color: Color(0xFF000000))),
        ]),
      ),
    );
  }
}

void main() {
  testWidgets('renders expanded content when not collapsed', (tester) async {
    await tester.pumpWidget(const _Host(initialCollapsed: false));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('content')), findsOneWidget);
  });

  testWidgets('renders collapsed icon child when collapsed', (tester) async {
    await tester.pumpWidget(const _Host(initialCollapsed: true));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('icon')), findsOneWidget);
    expect(find.byKey(const ValueKey('content')), findsNothing);
  });

  testWidgets('animates between collapsed and expanded', (tester) async {
    final key = GlobalKey<_HostState>();
    await tester
        .pumpWidget(_Host(key: key, initialCollapsed: true));
    await tester.pumpAndSettle();

    // Width starts at the collapsed width.
    final widgetFinder = find.byType(CollapsibleSidebar);
    var size = tester.getSize(widgetFinder);
    expect(size.width, closeTo(56, 0.5));

    // Trigger expand.
    key.currentState!.setCollapsed(false);
    await tester.pump();
    // Mid-animation: width should be growing past collapsed.
    await tester.pump(const Duration(milliseconds: 100));
    size = tester.getSize(widgetFinder);
    expect(size.width, greaterThan(56));

    await tester.pumpAndSettle();
    size = tester.getSize(widgetFinder);
    expect(size.width, closeTo(280, 0.5));
  });

  testWidgets('onCollapsedChange fires when transitioning to collapsed',
      (tester) async {
    final events = <bool>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(
      key: key,
      initialCollapsed: false,
      onCollapsedChange: events.add,
    ));
    await tester.pumpAndSettle();

    key.currentState!.setCollapsed(true);
    await tester.pumpAndSettle();

    expect(events, contains(true));
  });

  testWidgets('onCollapsedChange fires when transitioning to expanded',
      (tester) async {
    final events = <bool>[];
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(_Host(
      key: key,
      initialCollapsed: true,
      onCollapsedChange: events.add,
    ));
    await tester.pumpAndSettle();
    events.clear();

    key.currentState!.setCollapsed(false);
    await tester.pumpAndSettle();

    expect(events, contains(false));
  });
}
