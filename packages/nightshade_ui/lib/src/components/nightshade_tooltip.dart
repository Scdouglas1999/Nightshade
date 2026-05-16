import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// Position of the tooltip relative to the target widget
enum NightshadeTooltipPosition {
  top,
  bottom,
  left,
  right,
}

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

class _NightshadeTooltipState extends State<NightshadeTooltip>
    with SingleTickerProviderStateMixin {
  final _overlayController = OverlayPortalController();
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: NightshadeTokens.curveSnappy),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _showTooltip() async {
    if (_overlayController.isShowing) return;

    _isHovered = true;
    await Future.delayed(widget.waitDuration);

    if (_isHovered && mounted) {
      _overlayController.show();
      _animController.forward();
    }
  }

  void _hideTooltip() {
    _isHovered = false;
    _animController.reverse().then((_) {
      if (mounted && _overlayController.isShowing) {
        _overlayController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (context) {
        return _TooltipOverlay(
          targetContext: context,
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
        child: widget.child,
      ),
    );
  }
}

class _TooltipOverlay extends StatelessWidget {
  final BuildContext targetContext;
  final String message;
  final Widget? richMessage;
  final NightshadeTooltipPosition position;
  final bool showArrow;
  final double maxWidth;
  final Animation<double> fadeAnimation;
  final Animation<double> scaleAnimation;

  const _TooltipOverlay({
    required this.targetContext,
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Get target position
    final renderBox = targetContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return const SizedBox.shrink();

    final targetSize = renderBox.size;
    final targetPosition = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.sizeOf(context);

    // Safety check for valid values
    if (targetSize.width.isNaN || targetSize.height.isNaN ||
        targetPosition.dx.isNaN || targetPosition.dy.isNaN ||
        screenSize.width <= 0 || screenSize.height <= 0) {
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

    // Clamp to screen bounds (ensure positive range)
    final maxLeft = (screenSize.width - padding).clamp(padding, double.infinity);
    final maxTop = (screenSize.height - padding).clamp(padding, double.infinity);
    left = left.clamp(padding, maxLeft);
    top = top.clamp(padding, maxTop);

    // For horizontal tooltips, use FractionalTranslation to center vertically
    // For vertical tooltips, use FractionalTranslation to center horizontally
    Offset translationOffset;
    switch (position) {
      case NightshadeTooltipPosition.top:
        translationOffset = const Offset(-0.5, -1.0);
      case NightshadeTooltipPosition.bottom:
        translationOffset = const Offset(-0.5, 0.0);
      case NightshadeTooltipPosition.left:
        translationOffset = const Offset(-1.0, -0.5);
      case NightshadeTooltipPosition.right:
        translationOffset = const Offset(0.0, -0.5);
    }

    return Positioned(
      left: left,
      top: top,
      child: FractionalTranslation(
        translation: translationOffset,
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
          child: _buildTooltipContent(colors, position, targetPosition, targetSize),
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
        border: Border.all(
          color: colors.border.withValues(alpha: 0.3),
        ),
        boxShadow: [
          // Main shadow
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          // Accent-tinted glow
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.1),
            blurRadius: 12,
            spreadRadius: -2,
          ),
        ],
      ),
      child: richMessage ??
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: colors.textPrimary,
            ),
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

/// A simple wrapper that adds a tooltip to any widget.
///
/// This is a convenience widget for common tooltip use cases.
class WithTooltip extends StatelessWidget {
  final Widget child;
  final String tooltip;
  final NightshadeTooltipPosition position;

  const WithTooltip({
    super.key,
    required this.child,
    required this.tooltip,
    this.position = NightshadeTooltipPosition.top,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeTooltip(
      message: tooltip,
      position: position,
      child: child,
    );
  }
}
