// Part of ../guiding_screen.dart -- extracted for maintainability.
//
// Shared mutable screen state used by the responsive section mixins.
part of '../guiding_screen.dart';

mixin _GuidingStateFields on ConsumerState<GuidingScreen> {
  GraphTimeScale _timeScale = GraphTimeScale.fiveMinutes;
  GraphYScale _yScale = GraphYScale.two;
  bool _showBrainPanel = false;

  // Tab controller for mobile layout
  late TabController _tabController;

  /// True when the viewport is a phone in EITHER orientation.
  ///
  /// [Responsive.isPhone] is width-only (`< 600`), which misclassifies a phone
  /// held in landscape (a large phone is ~932 px wide). Branching on the
  /// shortest side keeps both portrait and landscape phones on the reflowed
  /// mobile layout, while genuine tablets (>= 600 in their shorter dimension)
  /// keep the desktop split.
  bool _isPhoneViewport(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide <
      BreakpointTokens.breakpointPhone;
}
