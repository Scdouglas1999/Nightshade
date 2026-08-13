part of '../sequence_tree.dart';

/// Inline badge that marks a node as a parallel safety watchdog.
///
/// Trigger-category nodes (currently [MeridianFlipNode], and any future
/// trigger node) do not execute in list order — they run in parallel and
/// fire when their condition is met (e.g. crossing the meridian) regardless
/// of where they sit in the sequence. The badge makes that non-obvious
/// behavior legible right in the tree so an operator reviewing a sequence
/// doesn't assume the flip "runs at this position".
class _WatchdogBadge extends StatelessWidget {
  final NightshadeColors colors;

  const _WatchdogBadge({required this.colors});

  @override
  Widget build(BuildContext context) {
    return NightshadeTooltip(
      message:
          'Runs in parallel as a safety watchdog — fires on meridian-crossing '
          'regardless of its position in the list',
      child: Container(
        padding: NightshadeTokens.paddingXs,
        decoration: NightshadeDecorations.statusChip(
          colors.warning,
          borderRadius: NightshadeTokens.borderRadiusSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.shieldAlert,
              size: NightshadeTokens.iconXs,
              color: colors.warning,
            ),
            const SizedBox(width: NightshadeTokens.spaceXs),
            Text(
              'Watchdog',
              style:
                  NightshadeTypography.overline.copyWith(color: colors.warning),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpinningIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const _SpinningIcon({
    required this.icon,
    required this.color,
    this.size = 16,
  });

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Started by the OnScreenAnimationGate in build(), not here: a repeat that
    // outlives visibility schedules a frame on every vsync and stops the whole
    // app from idling.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnScreenAnimationGate(
      controller: _controller,
      repeating: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _controller.value * 2 * 3.14159,
            child: Icon(
              widget.icon,
              size: widget.size,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _NodeActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final NightshadeColors colors;
  final Color? color;
  final VoidCallback? onPressed;

  const _NodeActionButton({
    required this.icon,
    required this.tooltip,
    required this.colors,
    this.color,
    this.onPressed,
  });

  @override
  State<_NodeActionButton> createState() => _NodeActionButtonState();
}

class _NodeActionButtonState extends State<_NodeActionButton> {
  /// Edge of the visible chip. Three of these sit in every tree row, so it
  /// stays dense on desktop and is padded up to the touch minimum on a phone.
  static const double _chipExtent = 24.0;

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? widget.colors.textSecondary;
    final disabled = widget.onPressed == null;
    final iconColor = disabled
        ? widget.colors.textMuted.withValues(alpha: 0.4)
        : (_isHovered ? color : widget.colors.textMuted);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: disabled ? null : (_) => setState(() => _isHovered = true),
        onExit: disabled ? null : (_) => setState(() => _isHovered = false),
        cursor:
            disabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPressed,
          // The 24x24 chip is right for a dense desktop tree row, but it is
          // also the whole hit area: a bare GestureDetector hit-tests its
          // child's box, so on a phone these measured 28x24 against Android's
          // 48. Padding the child (rather than wrapping the detector) grows the
          // real hit box, not just the semantics rect — and only on touch
          // platforms, so desktop density is untouched.
          child: Padding(
            padding: EdgeInsets.all(
              NightshadeTouchTarget.paddingToReach(context, _chipExtent),
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _chipExtent,
              height: _chipExtent,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: !disabled && _isHovered
                    ? NightshadeDecorations.tintedBadge(
                        color,
                        borderRadius: BorderRadius.circular(
                          NightshadeTokens.radiusInline4,
                        ),
                      ).color
                    : Colors.transparent,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
              ),
              child: Icon(
                widget.icon,
                size: 12,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DropZone extends ConsumerWidget {
  final NightshadeColors colors;
  final String parentId;
  final int index;

  /// Whether the *enclosing* container's DragTarget currently has a candidate
  /// hovering (plumbed down from `_NodeTreeView`). Drives the dashed-zone
  /// reveal per-container rather than off the global drag provider, so a drag
  /// over one container doesn't repaint every sibling subtree.
  final bool isActive;

  const _DropZone({
    required this.colors,
    required this.parentId,
    required this.index,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (data) =>
          data.data is String ||
          data.data is NodePaletteItem ||
          data.data is TemplateSnippet ||
          data.data is TargetQueueDragPayload,
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is String) {
          ref.read(currentSequenceProvider.notifier).moveNode(
                data,
                parentId,
                index,
              );
        } else if (data is NodePaletteItem) {
          final node = data.createNode();
          final notifier = ref.read(currentSequenceProvider.notifier);
          notifier.addNode(
            node,
            parentId: parentId,
            index: index,
          );
          final children = data.createChildren?.call();
          if (children != null) {
            for (final child in children) {
              notifier.addNode(child, parentId: node.id);
            }
          }
          ref.read(selectedNodeIdProvider.notifier).state = node.id;
        } else if (data is TemplateSnippet) {
          // Route through the guarded helper so a locked-state /
          // unknown-node-type insert surfaces a snackbar, matching the
          // tap path.
          insertSnippetGuarded(context, ref, data,
              parentId: parentId, index: index);
        } else if (data is TargetQueueDragPayload) {
          // Precise-position drop: insert the prebuilt
          // TargetHeaderNode at the exact index where the dashed
          // drop-zone lives. Mirrors the NodePaletteItem branch above
          // so the queue payload feels like any other dragged
          // toolbox item.
          final notifier = ref.read(currentSequenceProvider.notifier);
          notifier.addNode(data.node, parentId: parentId, index: index);
          ref.read(selectedNodeIdProvider.notifier).state = data.node.id;
        }
        // Reset drag state after drop
        ref.read(isDraggingNodeProvider.notifier).state = false;
      },
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        // RepaintBoundary isolates this zone's animation so the global
        // drag-state rebuild (read inside the Consumer below) doesn't
        // repaint sibling subtrees.
        return RepaintBoundary(
          child: Consumer(
            builder: (context, ref, _) {
              // Watch global drag state ONLY here so the rest of the row
              // doesn't rebuild when a drag starts elsewhere.
              final isDragging = ref.watch(isDraggingNodeProvider);
              final showDropZone = isDragging || isActive || isOver;
              return _buildZone(isOver: isOver, showDropZone: showDropZone);
            },
          ),
        );
      },
    );
  }

  Widget _buildZone({required bool isOver, required bool showDropZone}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: isOver ? 48 : (showDropZone ? 28 : 4),
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: isOver
          ? NightshadeDecorations.selectedSurface(
              colors.primary,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              fillAlpha: 0.2,
            ).copyWith(
              border: Border.all(color: colors.primary, width: 2),
            )
          : showDropZone
              ? _dashedDropDecoration(colors)
              : const BoxDecoration(),
      child: isOver
          ? Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.arrowDown,
                    size: 12,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Insert here',
                    style: NightshadeTypography.labelStrongSm
                        .copyWith(color: colors.primary),
                  ),
                ],
              ),
            )
          : showDropZone
              ? CustomPaint(
                  painter: _DashedLinePainter(
                      color: colors.primary.withValues(alpha: 0.5)),
                  child: Center(
                    child: Icon(
                      LucideIcons.plusCircle,
                      size: 12,
                      color: colors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                )
              : null,
    );
  }
}

/// Creates a dashed-border-style decoration for drop zone indicators.
BoxDecoration _dashedDropDecoration(NightshadeColors colors) {
  return NightshadeDecorations.tintedBadge(
    colors.primary,
    borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
  );
}

/// Paints a horizontal dashed line across the center of the widget,
/// acting as an insertion point indicator during drag operations.
class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final y = size.height / 2;

    // Draw left dashes (up to center minus icon space)
    final leftEnd = size.width / 2 - 12;
    var x = 4.0;
    while (x < leftEnd) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dashWidth).clamp(0, leftEnd), y),
        paint,
      );
      x += dashWidth + dashSpace;
    }

    // Draw right dashes (from center plus icon space)
    final rightStart = size.width / 2 + 12;
    x = rightStart;
    while (x < size.width - 4) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dashWidth).clamp(0, size.width - 4), y),
        paint,
      );
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
