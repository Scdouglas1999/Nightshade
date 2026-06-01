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
}
