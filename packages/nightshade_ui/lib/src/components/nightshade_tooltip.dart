import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// Position of the tooltip relative to the target widget
enum NightshadeTooltipPosition { top, bottom, left, right }

/// A styled tooltip with animations and accent shadow.
///
/// Features:
/// - 300ms delay before showing
/// - Fade + scale animation on appear/disappear
/// - Dark background with subtle accent-tinted shadow
/// - Arrow pointer aligned to target
class NightshadeTooltip extends StatefulWidget {
  /// The widget that triggers the tooltip
  final Widget child;

  /// The message to display in the tooltip
  final String message;

  /// Rich content for the tooltip (overrides message)
  final Widget? richMessage;

  /// Position of the tooltip relative to the child
  final NightshadeTooltipPosition position;

  /// Delay before showing the tooltip
  final Duration waitDuration;

  /// Duration of the show/hide animation
  final Duration animationDuration;

  /// Whether to show the arrow pointer
  final bool showArrow;

  /// Maximum width of the tooltip
  final double maxWidth;

  const NightshadeTooltip({
    super.key,
    required this.child,
    required this.message,
    this.richMessage,
    this.position = NightshadeTooltipPosition.top,
    this.waitDuration = const Duration(milliseconds: 300),
    this.animationDuration = NightshadeTokens.durationNormal,
    this.showArrow = true,
    this.maxWidth = 240,
  });

  @override
  State<NightshadeTooltip> createState() => _NightshadeTooltipState();
}

/// The tooltip currently on screen, app-wide.
///
/// Every `NightshadeTooltip` owns an independent `OverlayPortalController`, so
/// nothing used to stop several from being visible at once: the touch trigger
/// shows on long-press and only retires on its own 3 s timer or a second
/// long-press, and a hover that never produces a matching `onExit` (pointer
/// leaves the window, the trigger is rebuilt away under the cursor) strands the
/// label indefinitely. On the planetarium's dark star field two stale floating
/// labels read as sky annotations. One tooltip at a time is the contract every
/// tooltip system has; this single-slot registry is what enforces it.
_NightshadeTooltipState? _visibleTooltip;

class _NightshadeTooltipState extends State<NightshadeTooltip>
    with SingleTickerProviderStateMixin {
  final _overlayController = OverlayPortalController();
  final GlobalKey _childKey = GlobalKey();
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;
  Timer? _dismissTimer;
  Timer? _showTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: NightshadeTokens.curveSnappy,
      ),
    );
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _showTimer?.cancel();
    if (identical(_visibleTooltip, this)) _visibleTooltip = null;
    _animController.dispose();
    super.dispose();
  }

  /// Takes the single visible-tooltip slot, retiring whoever held it.
  void _claimVisibility() {
    final previous = _visibleTooltip;
    if (previous != null && !identical(previous, this)) {
      previous._hideTooltip();
    }
    _visibleTooltip = this;
  }

  // The hover delay is a Timer rather than a `Future.delayed` so dispose() can
  // cancel it; an uncancellable delay keeps this state object alive past
  // teardown and turns any throw into an unhandled zone error.
  void _showTooltip() {
    if (_overlayController.isShowing || _showTimer != null) return;

    _isHovered = true;
    _showTimer = Timer(widget.waitDuration, () {
      _showTimer = null;
      if (!_isHovered || !mounted) return;
      _claimVisibility();
      _overlayController.show();
      _animController.forward();
    });
  }

  void _hideTooltip() {
    _dismissTimer?.cancel();
    _showTimer?.cancel();
    _showTimer = null;
    _isHovered = false;
    if (identical(_visibleTooltip, this)) _visibleTooltip = null;
    _animController.reverse().then((_) {
      if (mounted && _overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }

  // Touch trigger: show immediately on long-press (no hover), toggle off on a
  // repeat long-press, and auto-dismiss after a few seconds.
  void _toggleTooltipForTouch() {
    if (_overlayController.isShowing) {
      _hideTooltip();
      return;
    }
    _dismissTimer?.cancel();
    _showTimer?.cancel();
    _showTimer = null;
    _isHovered = true;
    _claimVisibility();
    _overlayController.show();
    _animController.forward();
    _dismissTimer = Timer(const Duration(seconds: 3), _hideTooltip);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (context) {
        return _TooltipOverlay(
          targetKey: _childKey,
          message: widget.message,
          richMessage: widget.richMessage,
          position: widget.position,
          showArrow: widget.showArrow,
          maxWidth: widget.maxWidth,
          fadeAnimation: _fadeAnimation,
          scaleAnimation: _scaleAnimation,
        );
      },
      child: MouseRegion(
        onEnter: (_) => _showTooltip(),
        onExit: (_) => _hideTooltip(),
        child: GestureDetector(
          onLongPress: _toggleTooltipForTouch,
          child: KeyedSubtree(key: _childKey, child: widget.child),
        ),
      ),
    );
  }
}

class _TooltipOverlay extends StatelessWidget {
  final GlobalKey targetKey;
  final String message;
  final Widget? richMessage;
  final NightshadeTooltipPosition position;
  final bool showArrow;
  final double maxWidth;
  final Animation<double> fadeAnimation;
  final Animation<double> scaleAnimation;

  const _TooltipOverlay({
    required this.targetKey,
    required this.message,
    this.richMessage,
    required this.position,
    required this.showArrow,
    required this.maxWidth,
    required this.fadeAnimation,
    required this.scaleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    // Get target position from the trigger child's render box (not this
    // overlay's own context, which lives under the Overlay subtree).
    final renderBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return const SizedBox.shrink();

    // The overlay child is laid out in the HOST OVERLAY's coordinate space, not
    // the screen's, so the anchor has to be measured against that same overlay.
    // It used to be `localToGlobal(Offset.zero)` — screen coordinates — laid out
    // against an overlay origin assumed to be (0, 0). Wherever the overlay is
    // inset from the window the tooltip was displaced by exactly that inset and
    // drew next to a different control (observed on the planetarium toolbar,
    // where the `Layers` label landed 176 px right and 79 px below its button,
    // out over the star field). `MediaQuery.sizeOf` was wrong for the same
    // reason: the edge the tooltip must stay inside is the overlay's, not the
    // window's, and the two clamps disagreeing let a tooltip be constrained to
    // one box and positioned in another.
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final targetSize = renderBox.size;
    final targetPosition = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final screenSize = overlayBox != null && overlayBox.hasSize
        ? overlayBox.size
        : MediaQuery.sizeOf(context);

    // Safety check for valid values
    if (targetSize.width.isNaN ||
        targetSize.height.isNaN ||
        targetPosition.dx.isNaN ||
        targetPosition.dy.isNaN ||
        screenSize.width <= 0 ||
        screenSize.height <= 0) {
      return const SizedBox.shrink();
    }

    // Calculate tooltip position
    double left = 0;
    double top = 0;
    const arrowSize = 8.0;
    const padding = 8.0;

    switch (position) {
      case NightshadeTooltipPosition.top:
        left = targetPosition.dx + (targetSize.width / 2);
        top = targetPosition.dy - padding - arrowSize;
      case NightshadeTooltipPosition.bottom:
        left = targetPosition.dx + (targetSize.width / 2);
        top = targetPosition.dy + targetSize.height + padding + arrowSize;
      case NightshadeTooltipPosition.left:
        left = targetPosition.dx - padding - arrowSize;
        top = targetPosition.dy + (targetSize.height / 2);
      case NightshadeTooltipPosition.right:
        left = targetPosition.dx + targetSize.width + padding + arrowSize;
        top = targetPosition.dy + (targetSize.height / 2);
    }

    // Anchor point only. Turning it into a final on-screen rect needs the
    // tooltip's measured size, which is why that happens in the layout delegate
    // below rather than here.
    //
    // Clamping `left`/`top` at this point is NOT enough, and used to be all this
    // did: the tooltip was then offset by a FRACTION OF ITS OWN WIDTH
    // (FractionalTranslation), so a `right`-positioned tooltip anchored at
    // `screenWidth - 8` still drew its whole width past the edge, and a
    // `top`/`bottom` one still drew half its width outside. Observed on the
    // Imaging panel's "Stack & Share" button, whose tooltip appeared as a
    // one-character sliver at the window edge. It affected every tooltip near any
    // edge, since this is the shared design-system component.
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _TooltipLayoutDelegate(
          anchor: Offset(left, top),
          position: position,
          padding: padding,
          viewport: screenSize,
        ),
        child: AnimatedBuilder(
          animation: fadeAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: fadeAnimation.value,
              child: Transform.scale(
                scale: scaleAnimation.value,
                alignment: _getScaleAlignment(),
                child: child,
              ),
            );
          },
          child: _buildTooltipContent(
            colors,
            position,
            targetPosition,
            targetSize,
          ),
        ),
      ),
    );
  }

  Alignment _getScaleAlignment() {
    switch (position) {
      case NightshadeTooltipPosition.top:
        return Alignment.bottomCenter;
      case NightshadeTooltipPosition.bottom:
        return Alignment.topCenter;
      case NightshadeTooltipPosition.left:
        return Alignment.centerRight;
      case NightshadeTooltipPosition.right:
        return Alignment.centerLeft;
    }
  }

  Widget _buildTooltipContent(
    NightshadeColors colors,
    NightshadeTooltipPosition pos,
    Offset targetPos,
    Size targetSize,
  ) {
    Widget content = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border.withValues(alpha: 0.3)),
        boxShadow: NightshadeTokens.shadowMd,
      ),
      child:
          richMessage ??
          Text(
            message,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
          ),
    );

    // Wrap with arrow if enabled
    if (showArrow) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pos == NightshadeTooltipPosition.bottom)
            _buildArrow(colors, isPointingUp: true),
          content,
          if (pos == NightshadeTooltipPosition.top)
            _buildArrow(colors, isPointingUp: false),
        ],
      );
    }

    return content;
  }

  Widget _buildArrow(NightshadeColors colors, {required bool isPointingUp}) {
    return CustomPaint(
      size: const Size(16, 8),
      painter: _ArrowPainter(
        color: colors.surfaceOverlay,
        borderColor: colors.border.withValues(alpha: 0.3),
        isPointingUp: isPointingUp,
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  final Color color;
  final Color borderColor;
  final bool isPointingUp;

  _ArrowPainter({
    required this.color,
    required this.borderColor,
    required this.isPointingUp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path();
    if (isPointingUp) {
      path.moveTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    }
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    return color != oldDelegate.color ||
        borderColor != oldDelegate.borderColor ||
        isPointingUp != oldDelegate.isPointingUp;
  }
}

/// Places the tooltip relative to its anchor and keeps it fully on screen.
///
/// A layout delegate rather than arithmetic at build time because the decision
/// needs the tooltip's MEASURED size: the offset from the anchor is half (or all)
/// of the tooltip's own width/height depending on which side it sits, and only
/// the layout pass knows that. Clamping the anchor instead leaves the box itself
/// hanging off the edge — see the note at the call site.
class _TooltipLayoutDelegate extends SingleChildLayoutDelegate {
  const _TooltipLayoutDelegate({
    required this.anchor,
    required this.position,
    required this.padding,
    required this.viewport,
  });

  /// The point on the trigger the tooltip points at.
  final Offset anchor;
  final NightshadeTooltipPosition position;

  /// Minimum gap kept between the tooltip and each viewport edge.
  final double padding;
  final Size viewport;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // Never ask the tooltip to be wider or taller than the space it has to fit
    // in, so a long message wraps instead of being clipped.
    final maxWidth = (viewport.width - padding * 2).clamp(0.0, double.infinity);
    final maxHeight = (viewport.height - padding * 2).clamp(
      0.0,
      double.infinity,
    );
    return constraints.loosen().copyWith(
      maxWidth: maxWidth == 0 ? constraints.maxWidth : maxWidth,
      maxHeight: maxHeight == 0 ? constraints.maxHeight : maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // Offset the anchor by the tooltip's own extent for the chosen side, which
    // is what centres it on the trigger (or sits it fully to one side).
    double x;
    double y;
    switch (position) {
      case NightshadeTooltipPosition.top:
        x = anchor.dx - childSize.width / 2;
        y = anchor.dy - childSize.height;
      case NightshadeTooltipPosition.bottom:
        x = anchor.dx - childSize.width / 2;
        y = anchor.dy;
      case NightshadeTooltipPosition.left:
        x = anchor.dx - childSize.width;
        y = anchor.dy - childSize.height / 2;
      case NightshadeTooltipPosition.right:
        x = anchor.dx;
        y = anchor.dy - childSize.height / 2;
    }

    // Now clamp the REAL box. Upper bounds are lower-bounded by `padding` so a
    // tooltip larger than the viewport still starts on screen and is clipped at
    // the far edge, rather than being pushed off the near one.
    final maxX = (size.width - childSize.width - padding).clamp(
      padding,
      double.infinity,
    );
    final maxY = (size.height - childSize.height - padding).clamp(
      padding,
      double.infinity,
    );
    return Offset(x.clamp(padding, maxX), y.clamp(padding, maxY));
  }

  @override
  bool shouldRelayout(_TooltipLayoutDelegate oldDelegate) =>
      anchor != oldDelegate.anchor ||
      position != oldDelegate.position ||
      padding != oldDelegate.padding ||
      viewport != oldDelegate.viewport;
}
