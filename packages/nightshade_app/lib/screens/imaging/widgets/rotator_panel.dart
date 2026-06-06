import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import '../../../utils/snackbar_helper.dart';
import 'panel_widgets.dart';

class RotatorPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const RotatorPanel({super.key, required this.colors});

  @override
  ConsumerState<RotatorPanel> createState() => _RotatorPanelState();
}

class _RotatorPanelState extends ConsumerState<RotatorPanel> {
  final _angleController = TextEditingController();
  final _angleFocusNode = FocusNode();
  bool _isGoingTo = false;

  @override
  void dispose() {
    _angleController.dispose();
    _angleFocusNode.dispose();
    super.dispose();
  }

  RotatorState get _rotatorState => ref.watch(rotatorStateProvider);
  bool get _isConnected =>
      _rotatorState.connectionState == DeviceConnectionState.connected;
  bool get _isMoving => _rotatorState.isMoving;

  /// Resolves the rotator's valid absolute-angle range from its reported
  /// capabilities, falling back to a full 0..360 turn when the driver does
  /// not advertise bounds. An inverted or degenerate range (min >= max) is
  /// treated as missing data and also falls back to 0..360.
  ({double min, double max}) _angleRange() {
    final caps = ref
        .read(equipmentRotatorCapabilitiesProvider(
          _rotatorState.deviceId ?? '',
        ))
        .valueOrNull;
    final min = caps?.minAngleDeg ?? 0.0;
    final max = caps?.maxAngleDeg ?? 360.0;
    if (min >= max) return (min: 0.0, max: 360.0);
    return (min: min, max: max);
  }

  Future<void> _moveRelative(double delta) async {
    if (_isMoving) return;
    try {
      await ref.read(deviceServiceProvider).moveRotatorRelative(delta);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Failed to move rotator: $e');
    }
  }

  Future<void> _goToAngle() async {
    final range = _angleRange();
    final text = _angleController.text.trim();
    final angle = double.tryParse(text);
    if (angle == null) {
      context.showErrorSnackBar(
        'Enter a valid angle '
        '(${range.min.toStringAsFixed(0)}-${range.max.toStringAsFixed(0)})',
      );
      return;
    }
    if (angle < range.min || angle > range.max) {
      context.showErrorSnackBar(
        'Angle must be between '
        '${range.min.toStringAsFixed(0)} and ${range.max.toStringAsFixed(0)}',
      );
      return;
    }

    setState(() => _isGoingTo = true);
    try {
      await ref.read(deviceServiceProvider).moveRotatorTo(angle);
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Failed to move rotator: $e');
    } finally {
      if (mounted) setState(() => _isGoingTo = false);
    }
  }

  Future<void> _halt() async {
    try {
      await ref.read(deviceServiceProvider).haltRotator();
    } catch (e) {
      if (mounted) context.showErrorSnackBar('Failed to halt rotator: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;

    // DEV-P3-1: gate absolute-angle move and halt on the rotator's
    // reported capabilities. Hide Go-To entirely when canMoveAbsolute is
    // false — the workflow has no analog form. Halt is shown only while
    // moving anyway, but we drop it when the driver can't halt.
    final rotatorCapsAsync = ref.watch(equipmentRotatorCapabilitiesProvider(
        _rotatorState.deviceId ?? ''));
    final canMoveAbsolute = gateCapability<RotatorCapabilities>(
      rotatorCapsAsync,
      (c) => c.canMoveAbsolute,
      loadingDefault: true,
    );
    final canHalt = gateCapability<RotatorCapabilities>(
      rotatorCapsAsync,
      (c) => c.canHalt,
      loadingDefault: true,
    );

    // Valid absolute-angle range for the Go-To input hint. Mirrors the
    // validation in _goToAngle: use the driver's reported bounds, falling
    // back to a full turn (0..360) when they are absent or degenerate.
    final caps = rotatorCapsAsync.valueOrNull;
    final rawMin = caps?.minAngleDeg ?? 0.0;
    final rawMax = caps?.maxAngleDeg ?? 360.0;
    final hasValidRange = rawMin < rawMax;
    final minAngle = hasValidRange ? rawMin : 0.0;
    final maxAngle = hasValidRange ? rawMax : 360.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Current angle display
        _buildAngleDisplay(colors),
        const SizedBox(height: 16),

        // Go To section — visible only when the driver supports absolute
        // moves. Relative move falls back to a sequence of small steps so
        // it stays available on any rotator.
        if (canMoveAbsolute) ...[
          PanelSection(
            title: 'Go To Angle',
            colors: colors,
            child: _buildGoToSection(colors, minAngle, maxAngle),
          ),
          const SizedBox(height: 16),
        ],

        // Relative movement section
        PanelSection(
          title: 'Relative Move',
          colors: colors,
          child: _buildRelativeMoveSection(colors),
        ),
        const SizedBox(height: 16),

        // Halt button — only meaningful when the driver supports halt
        // and the rotator is currently moving.
        if (_isMoving && canHalt)
          SizedBox(
            width: double.infinity,
            child: SmallButton(
              label: 'HALT',
              icon: LucideIcons.octagon,
              colors: colors,
              isEnabled: _isConnected,
              onTap: _halt,
            ),
          ),
      ],
    );
  }

  Widget _buildAngleDisplay(NightshadeColors colors) {
    final angle = _rotatorState.position;
    final mechanicalAngle = _rotatorState.mechanicalPosition;

    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      borderRadius: NightshadeTokens.radiusLg,
      child: Column(
        children: [
          // Visual angle indicator
          SizedBox(
            width: 100,
            height: 100,
            child: CustomPaint(
              painter: _AngleIndicatorPainter(
                angle: angle ?? 0,
                primaryColor: colors.primary,
                trackColor: colors.border,
                isConnected: _isConnected,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      angle != null
                          ? '${angle.toStringAsFixed(1)}°'
                          : '---',
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize18,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: _isConnected
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                    ),
                    if (_isMoving)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Moving...',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize10,
                            color: colors.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Mechanical position (if different)
          if (mechanicalAngle != null && angle != null &&
              (mechanicalAngle - angle).abs() > 0.1)
            Text(
              'Mechanical: ${mechanicalAngle.toStringAsFixed(1)}°',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
          if (!_isConnected)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Rotator not connected',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  color: colors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGoToSection(
    NightshadeColors colors,
    double minAngle,
    double maxAngle,
  ) {
    final canGoTo = _isConnected && !_isMoving && !_isGoingTo;

    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              border: Border.all(color: colors.border),
            ),
            child: TextField(
              controller: _angleController,
              focusNode: _angleFocusNode,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize13,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
                isDense: true,
                hintText:
                    '${minAngle.toStringAsFixed(1)} - ${maxAngle.toStringAsFixed(1)}',
                hintStyle: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textMuted,
                ),
                suffixText: '°',
                suffixStyle: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  color: colors.textMuted,
                ),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              enabled: _isConnected,
              onSubmitted: (_) {
                if (canGoTo) _goToAngle();
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        SmallButton(
          label: _isGoingTo ? 'Moving...' : 'Go To',
          icon: _isGoingTo ? NightshadeIcons.loading : LucideIcons.navigation,
          colors: colors,
          isEnabled: canGoTo,
          onTap: _goToAngle,
        ),
      ],
    );
  }

  Widget _buildRelativeMoveSection(NightshadeColors colors) {
    final canMove = _isConnected && !_isMoving;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RelativeMoveButton(
              label: '-15°',
              colors: colors,
              onPressed: canMove ? () => _moveRelative(-15) : null,
            ),
            _RelativeMoveButton(
              label: '-5°',
              colors: colors,
              onPressed: canMove ? () => _moveRelative(-5) : null,
            ),
            _RelativeMoveButton(
              label: '-1°',
              colors: colors,
              onPressed: canMove ? () => _moveRelative(-1) : null,
            ),
            Container(
              width: 1,
              height: 24,
              color: colors.border,
            ),
            _RelativeMoveButton(
              label: '+1°',
              colors: colors,
              onPressed: canMove ? () => _moveRelative(1) : null,
            ),
            _RelativeMoveButton(
              label: '+5°',
              colors: colors,
              onPressed: canMove ? () => _moveRelative(5) : null,
            ),
            _RelativeMoveButton(
              label: '+15°',
              colors: colors,
              onPressed: canMove ? () => _moveRelative(15) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _RelativeMoveButton extends StatefulWidget {
  final String label;
  final NightshadeColors colors;
  final VoidCallback? onPressed;

  const _RelativeMoveButton({
    required this.label,
    required this.colors,
    this.onPressed,
  });

  @override
  State<_RelativeMoveButton> createState() => _RelativeMoveButtonState();
}

class _RelativeMoveButtonState extends State<_RelativeMoveButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final textColor = isEnabled ? widget.colors.textPrimary : widget.colors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: _isHovered && isEnabled
              ? NightshadeDecorations.selectedSurface(
                  widget.colors.primary,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                )
              : BoxDecoration(
                  color: widget.colors.background,
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                  border: Border.all(color: widget.colors.border),
                ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter that draws a circular angle indicator with a needle.
class _AngleIndicatorPainter extends CustomPainter {
  final double angle;
  final Color primaryColor;
  final Color trackColor;
  final bool isConnected;

  _AngleIndicatorPainter({
    required this.angle,
    required this.primaryColor,
    required this.trackColor,
    required this.isConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Draw track circle
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, trackPaint);

    if (!isConnected) return;

    // Draw filled arc from 0 to current angle
    final arcPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final arcRect = Rect.fromCircle(center: center, radius: radius);
    // Convert angle to radians, starting from top (north = -pi/2)
    final sweepRadians = angle * math.pi / 180.0;
    canvas.drawArc(arcRect, -math.pi / 2, sweepRadians, true, arcPaint);

    // Draw needle
    final needleRadians = (angle - 90) * math.pi / 180.0;
    final needleEnd = Offset(
      center.dx + radius * math.cos(needleRadians),
      center.dy + radius * math.sin(needleRadians),
    );

    final needlePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needlePaint);

    // Draw center dot
    final dotPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3, dotPaint);
  }

  @override
  bool shouldRepaint(_AngleIndicatorPainter oldDelegate) {
    return oldDelegate.angle != angle ||
        oldDelegate.isConnected != isConnected ||
        oldDelegate.primaryColor != primaryColor;
  }
}
