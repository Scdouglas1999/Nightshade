import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Widget that displays the current operation progress in a compact status bar format.
///
/// Shows:
/// - Operation type icon
/// - Description / current step
/// - Progress bar (determinate or indeterminate)
/// - Elapsed time
/// - Cancel button (if operation is cancellable)
class OperationStatusBar extends ConsumerStatefulWidget {
  const OperationStatusBar({super.key});

  @override
  ConsumerState<OperationStatusBar> createState() => _OperationStatusBarState();
}

class _OperationStatusBarState extends ConsumerState<OperationStatusBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  IconData _getOperationIcon(OperationType type) {
    switch (type) {
      case OperationType.slewToTarget:
        return LucideIcons.move3d;
      case OperationType.autofocus:
        return LucideIcons.focus;
      case OperationType.filterChange:
        return LucideIcons.circleDot;
      case OperationType.plateSolve:
        return LucideIcons.compass;
      case OperationType.cooling:
        return LucideIcons.thermometerSnowflake;
      case OperationType.warming:
        return LucideIcons.thermometerSun;
      case OperationType.centeringLoop:
        return LucideIcons.crosshair;
      case OperationType.domeSlew:
        return LucideIcons.home;
      case OperationType.parkMount:
        return LucideIcons.parkingCircle;
      case OperationType.unparkMount:
        return LucideIcons.play;
      case OperationType.dither:
        return LucideIcons.shuffle;
      case OperationType.guideSettle:
        return LucideIcons.target;
      case OperationType.focuserMove:
        return LucideIcons.focus;
      case OperationType.rotatorMove:
        return LucideIcons.rotateCw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final hasOperation = ref.watch(hasActiveOperationProvider);
    final operation = ref.watch(primaryOperationProvider);

    // Handle animation and timer based on operation presence
    if (hasOperation && operation != null) {
      if (!_slideController.isCompleted) {
        _slideController.forward();
        _startElapsedTimer();
      }
    } else {
      if (_slideController.isCompleted || _slideController.isAnimating) {
        _slideController.reverse();
        _stopElapsedTimer();
      }
    }

    return SizeTransition(
      sizeFactor: _slideAnimation,
      axisAlignment: -1.0,
      child: operation != null ? _buildOperationBar(operation, colors) : const SizedBox.shrink(),
    );
  }

  Widget _buildOperationBar(OperationProgress operation, NightshadeColors colors) {
    return Container(
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          // Operation icon
          Icon(
            _getOperationIcon(operation.type),
            size: 14,
            color: colors.primary,
          ),
          const SizedBox(width: 8),
          // Description / current step
          Flexible(
            child: Text(
              operation.currentStep ?? operation.description,
              style: TextStyle(
                fontSize: 11,
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // Progress indicator
          SizedBox(
            width: 80,
            child: operation.progress != null
                ? LinearProgressIndicator(
                    value: operation.progress,
                    backgroundColor: colors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    minHeight: 4,
                  )
                : LinearProgressIndicator(
                    backgroundColor: colors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                    minHeight: 4,
                  ),
          ),
          const SizedBox(width: 12),
          // Elapsed time
          Text(
            operation.elapsedFormatted,
            style: TextStyle(
              fontSize: 10,
              color: colors.textMuted,
              fontFamily: 'monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          // Cancel button (if cancellable)
          if (operation.canCancel) ...[
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  ref.read(activeOperationsProvider.notifier).cancelOperation(operation.type);
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: colors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    LucideIcons.x,
                    size: 12,
                    color: colors.error,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Inline operation indicator for use within other widgets.
/// Shows a compact spinning indicator with operation name.
class OperationIndicator extends ConsumerWidget {
  final OperationType type;

  const OperationIndicator({super.key, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final operation = ref.watch(activeOperationsProvider)[type];

    if (operation == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
              value: operation.progress,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            operation.currentStep ?? type.activeLabel,
            style: TextStyle(
              fontSize: 11,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
