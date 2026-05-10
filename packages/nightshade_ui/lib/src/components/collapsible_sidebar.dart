import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../widgets/resizable_panel.dart';

/// A sidebar that animates between a collapsed icon strip and an expanded
/// resizable panel.
///
/// Consolidates the duplicated logic that lived in
/// `equipment_screen.dart` (`_CollapsibleSidebar`) and
/// `sequencer_screen.dart` (`_CollapsiblePanel`). Both versions had the
/// same animation controller setup, the same width tween, the same
/// "isEffectivelyCollapsed" sentinel, and the same `ResizablePanel` swap.
///
/// The sidebar:
///   * animates width via an `AnimationController` driving an inner
///     `Tween<double>`.
///   * snaps the visual to a fixed `collapsedWidth` once the tween falls
///     below `collapsedWidth + 20`, so the icon strip doesn't flicker.
///   * remembers user resize on the expanded side via the `ResizablePanel`
///     drag handle and notifies via [onExpandedWidthChanged].
class CollapsibleSidebar extends StatefulWidget {
  /// True when the sidebar is collapsed to the icon strip.
  final bool isCollapsed;

  /// Width of the collapsed icon strip.
  final double collapsedWidth;

  /// Initial expanded width. User can drag-resize within
  /// [minExpandedWidth, maxExpandedWidth].
  final double expandedWidth;

  final double minExpandedWidth;
  final double maxExpandedWidth;

  /// Which side of the sidebar hosts the drag handle / border.
  final ResizeSide side;

  /// Animation duration for the collapse/expand transition.
  final Duration animationDuration;

  /// Curve for the collapse/expand transition.
  final Curve animationCurve;

  /// Widget shown when collapsed (typically an icon button column).
  final Widget collapsedChild;

  /// Widget shown when expanded.
  final Widget expandedChild;

  /// Optional callback invoked when the user drags the resize handle.
  final ValueChanged<double>? onExpandedWidthChanged;

  /// Optional callback fired when the sidebar's effective collapsed state
  /// flips (e.g. user dragged the handle to the minimum). Mirrors the
  /// implicit `onCollapsedChange` pattern callers were emulating with
  /// `setState` chains.
  final ValueChanged<bool>? onCollapsedChange;

  const CollapsibleSidebar({
    super.key,
    required this.isCollapsed,
    required this.collapsedChild,
    required this.expandedChild,
    this.collapsedWidth = 56.0,
    this.expandedWidth = 280.0,
    this.minExpandedWidth = 220.0,
    this.maxExpandedWidth = 480.0,
    this.side = ResizeSide.right,
    this.animationDuration = const Duration(milliseconds: 200),
    this.animationCurve = Curves.easeInOut,
    this.onExpandedWidthChanged,
    this.onCollapsedChange,
  });

  @override
  State<CollapsibleSidebar> createState() => _CollapsibleSidebarState();
}

class _CollapsibleSidebarState extends State<CollapsibleSidebar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _widthAnimation;
  late double _currentExpandedWidth;
  bool _lastReportedCollapsed = false;

  @override
  void initState() {
    super.initState();
    _currentExpandedWidth = widget.expandedWidth;
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _rebuildTween();
    if (!widget.isCollapsed) {
      _controller.value = 1.0;
    }
    _lastReportedCollapsed = widget.isCollapsed;
  }

  void _rebuildTween() {
    _widthAnimation = Tween<double>(
      begin: widget.collapsedWidth,
      end: _currentExpandedWidth,
    ).animate(
      CurvedAnimation(parent: _controller, curve: widget.animationCurve),
    );
  }

  @override
  void didUpdateWidget(CollapsibleSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationDuration != widget.animationDuration) {
      _controller.duration = widget.animationDuration;
    }
    if (oldWidget.isCollapsed != widget.isCollapsed) {
      if (widget.isCollapsed) {
        _controller.reverse();
      } else {
        _currentExpandedWidth = widget.expandedWidth;
        _rebuildTween();
        _controller.forward();
      }
    }
    // External expanded-width change (e.g. parent restored a saved value)
    // resets the tween so the drag handle starts from the right place.
    if (oldWidget.expandedWidth != widget.expandedWidth &&
        !widget.isCollapsed) {
      _currentExpandedWidth = widget.expandedWidth;
      _rebuildTween();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _maybeReportCollapsed(bool isEffectivelyCollapsed) {
    if (_lastReportedCollapsed == isEffectivelyCollapsed) return;
    _lastReportedCollapsed = isEffectivelyCollapsed;
    widget.onCollapsedChange?.call(isEffectivelyCollapsed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return AnimatedBuilder(
      animation: _widthAnimation,
      builder: (context, _) {
        final width = _widthAnimation.value;
        // 20px hysteresis keeps the icon strip from flickering during the
        // tween; matches the heuristic the duplicated screens used.
        final isEffectivelyCollapsed =
            width < widget.collapsedWidth + 20.0;

        // Defer the callback to a post-frame microtask: AnimatedBuilder
        // rebuilds inside the animation tick, so calling setState on a
        // listener synchronously would violate the build contract.
        if (isEffectivelyCollapsed != _lastReportedCollapsed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _maybeReportCollapsed(isEffectivelyCollapsed);
          });
        }

        if (isEffectivelyCollapsed) {
          return Container(
            width: widget.collapsedWidth,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(
                left: widget.side == ResizeSide.left
                    ? BorderSide(color: colors.border)
                    : BorderSide.none,
                right: widget.side == ResizeSide.right
                    ? BorderSide(color: colors.border)
                    : BorderSide.none,
              ),
            ),
            child: widget.collapsedChild,
          );
        }

        return SizedBox(
          width: width,
          child: ResizablePanel(
            initialWidth: width,
            minWidth: widget.minExpandedWidth,
            maxWidth: widget.maxExpandedWidth,
            side: widget.side,
            onWidthChanged: (newWidth) {
              setState(() {
                _currentExpandedWidth = newWidth;
                _rebuildTween();
              });
              widget.onExpandedWidthChanged?.call(newWidth);
            },
            child: widget.expandedChild,
          ),
        );
      },
    );
  }
}
