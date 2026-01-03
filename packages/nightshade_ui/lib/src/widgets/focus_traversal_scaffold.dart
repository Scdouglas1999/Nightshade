import 'package:flutter/material.dart';

/// A scaffold widget that implements proper focus traversal for a screen.
///
/// This widget provides:
/// - Ordered keyboard navigation
/// - Focus group management
/// - Screen reader support
///
/// Example:
/// ```dart
/// FocusTraversalScaffold(
///   child: Column(
///     children: [
///       TextField(), // Tab order: 1
///       ElevatedButton(), // Tab order: 2
///       Checkbox(), // Tab order: 3
///     ],
///   ),
/// )
/// ```
class FocusTraversalScaffold extends StatelessWidget {
  final Widget child;
  final FocusTraversalPolicy? policy;
  final bool requestFocus;

  const FocusTraversalScaffold({
    super.key,
    required this.child,
    this.policy,
    this.requestFocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: policy ?? OrderedTraversalPolicy(),
      child: child,
    );
  }
}

/// A widget that can be explicitly ordered in focus traversal.
///
/// Use this to control the exact tab order of widgets.
///
/// Example:
/// ```dart
/// Column(
///   children: [
///     FocusOrderedWidget(
///       order: 1,
///       child: TextField(controller: nameController),
///     ),
///     FocusOrderedWidget(
///       order: 3,
///       child: TextField(controller: emailController),
///     ),
///     FocusOrderedWidget(
///       order: 2,
///       child: ElevatedButton(onPressed: submit),
///     ),
///   ],
/// )
/// ```
class FocusOrderedWidget extends StatelessWidget {
  final double order;
  final Widget child;

  const FocusOrderedWidget({
    super.key,
    required this.order,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order),
      child: child,
    );
  }
}
