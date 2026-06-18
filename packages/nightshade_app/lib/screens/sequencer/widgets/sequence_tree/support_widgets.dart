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
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
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
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: !disabled && _isHovered
                  ? NightshadeDecorations.tintedBadge(
                      color,
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusInline4),
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

/// Collapsible legend showing node category colors.
/// Shown as a "?" icon that opens a popup overlay.
class _NodeColorLegend extends StatelessWidget {
  final NightshadeColors colors;

  const _NodeColorLegend({required this.colors});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: 'Node color legend',
      offset: const Offset(0, 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        side: BorderSide(color: colors.border),
      ),
      color: colors.surface,
      icon: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
          border: Border.all(color: colors.border),
        ),
        child: Icon(
          LucideIcons.helpCircle,
          size: 12,
          color: colors.textMuted,
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Node Colors',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              // Swatches mirror the shared palette map (palette_icon_map.dart)
              // so the legend can't drift from the actual node colors. Mount
              // is `info`, Camera is `success` (de-collided from Imaging).
              _legendRow(nodePaletteCategoryColor('Target', colors),
                  'Target / Trigger'),
              const SizedBox(height: 6),
              _legendRow(nodePaletteCategoryColor('Imaging', colors),
                  'Imaging (Expose, Filter, Dither)'),
              const SizedBox(height: 6),
              _legendRow(nodePaletteCategoryColor('Mount', colors),
                  'Mount (Slew, Center, Park)'),
              const SizedBox(height: 6),
              _legendRow(nodePaletteCategoryColor('Camera', colors),
                  'Camera (Cool, Warm)'),
              const SizedBox(height: 6),
              _legendRow(nodePaletteCategoryColor('Logic', colors),
                  'Logic (Loop, Parallel, Conditional)'),
              const SizedBox(height: 6),
              _legendRow(nodePaletteCategoryColor('Focus', colors),
                  'Focus / Recovery'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Wraps a node widget with a validation badge overlay.
/// Shows a small warning/error indicator in the top-right corner when the node
/// has validation issues.
class _NodeValidationWrapper extends StatelessWidget {
  final NightshadeColors colors;
  final ValidationSeverity? validationSeverity;
  final List<ValidationIssue>? validationIssues;
  final Widget child;

  const _NodeValidationWrapper({
    required this.colors,
    required this.validationSeverity,
    required this.validationIssues,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (validationSeverity == null ||
        validationIssues == null ||
        validationIssues!.isEmpty) {
      return child;
    }

    final Color badgeColor;
    final IconData badgeIcon;
    switch (validationSeverity!) {
      case ValidationSeverity.error:
        badgeColor = colors.error;
        badgeIcon = LucideIcons.xCircle;
        break;
      case ValidationSeverity.warning:
        badgeColor = colors.warning;
        badgeIcon = LucideIcons.alertTriangle;
        break;
      case ValidationSeverity.info:
        badgeColor = colors.info;
        badgeIcon = LucideIcons.info;
        break;
    }

    final badgeForeground =
        ThemeData.estimateBrightnessForColor(badgeColor) == Brightness.dark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: 0,
          right: 0,
          child: Tooltip(
            richMessage: TextSpan(
              children: [
                for (int i = 0; i < validationIssues!.length; i++) ...[
                  if (i > 0) const TextSpan(text: '\n'),
                  TextSpan(
                    text: validationIssues![i].title,
                    style: NightshadeTypography.h6,
                  ),
                  TextSpan(
                    text: ': ${validationIssues![i].description}',
                    style: const TextStyle(
                        fontSize: NightshadeTypography.fontSize11),
                  ),
                ],
              ],
            ),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: badgeColor.withValues(alpha: 0.3),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Center(
                child: validationIssues!.length > 1
                    ? Text(
                        '${validationIssues!.length}',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize9,
                          fontWeight: FontWeight.w700,
                          color: badgeForeground,
                        ),
                      )
                    : Icon(
                        badgeIcon,
                        size: 10,
                        color: badgeForeground,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact validation summary badges for the sequence header toolbar.
class _ValidationBadges extends StatelessWidget {
  final NightshadeColors colors;
  final int errorCount;
  final int warningCount;
  final int infoCount;

  const _ValidationBadges({
    required this.colors,
    required this.errorCount,
    required this.warningCount,
    required this.infoCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorCount > 0)
          _MiniCountBadge(
            count: errorCount,
            color: colors.error,
            icon: LucideIcons.xCircle,
          ),
        if (warningCount > 0) ...[
          if (errorCount > 0) const SizedBox(width: 4),
          _MiniCountBadge(
            count: warningCount,
            color: colors.warning,
            icon: LucideIcons.alertTriangle,
          ),
        ],
        if (infoCount > 0) ...[
          if (errorCount > 0 || warningCount > 0) const SizedBox(width: 4),
          _MiniCountBadge(
            count: infoCount,
            color: colors.info,
            icon: LucideIcons.info,
          ),
        ],
      ],
    );
  }
}

class _MiniCountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final IconData icon;

  const _MiniCountBadge({
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: NightshadeDecorations.statusChip(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        bordered: false,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// In-tree search/jump field for the sequence header. Filters nodes by name
/// using the same collapsed-aware [visibleNodeOrderProvider] the tree renders,
/// and on selection sets [selectedNodeIdProvider] and scrolls the row into
/// view via [treeNodeKeyRegistryProvider] + `Scrollable.ensureVisible` — the
/// same path auto-follow uses.
class _TreeSearchField extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _TreeSearchField({required this.colors, required this.sequence});

  @override
  ConsumerState<_TreeSearchField> createState() => _TreeSearchFieldState();
}

class _TreeSearchFieldState extends ConsumerState<_TreeSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _portalController = OverlayPortalController();
  final _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      if (!_portalController.isShowing) _portalController.show();
    }
  }

  void _jumpTo(String nodeId) {
    ref.read(multiSelectedNodeIdsProvider.notifier).clear();
    ref.read(selectedNodeIdProvider.notifier).state = nodeId;

    final registry = ref.read(treeNodeKeyRegistryProvider);
    final key = registry?[nodeId];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.3,
      );
    }

    _controller.clear();
    ref.read(treeSearchQueryProvider.notifier).state = '';
    _portalController.hide();
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: (context) => _buildResultsOverlay(colors),
        child: SizedBox(
          width: 160,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline4),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.search, size: 12, color: colors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    onChanged: (value) {
                      ref.read(treeSearchQueryProvider.notifier).state = value;
                      if (!_portalController.isShowing) {
                        _portalController.show();
                      }
                    },
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Find node...',
                      hintStyle: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.textMuted,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      ref.read(treeSearchQueryProvider.notifier).state = '';
                      _portalController.hide();
                      _focusNode.unfocus();
                    },
                    child:
                        Icon(LucideIcons.x, size: 12, color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsOverlay(NightshadeColors colors) {
    final query = ref.watch(treeSearchQueryProvider).toLowerCase();
    if (query.isEmpty) return const SizedBox.shrink();

    final visible = ref.watch(visibleNodeOrderProvider);
    final matches = <SequenceNode>[
      for (final v in visible)
        if (widget.sequence.nodes[v.id] case final node?)
          if (node.name.toLowerCase().contains(query)) node,
    ];

    return Positioned(
      width: 280,
      child: CompositedTransformFollower(
        link: _layerLink,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 4),
        child: TapRegion(
          onTapOutside: (_) {
            _portalController.hide();
            _focusNode.unfocus();
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
                border: Border.all(color: colors.border),
                boxShadow: NightshadeTokens.shadowLg,
              ),
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No matching nodes',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: colors.textMuted,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        for (final node in matches)
                          InkWell(
                            onTap: () => _jumpTo(node.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              child: Text(
                                node.name,
                                style: TextStyle(
                                  fontSize: NightshadeTypography.fontSize13,
                                  color: colors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header action that collapses every container in one shot, or expands all
/// when something is already collapsed. The container id set is derived from
/// the sequence: any node that can hold children.
class _CollapseAllToggle extends ConsumerWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _CollapseAllToggle({required this.colors, required this.sequence});

  bool _isContainer(SequenceNode node) =>
      node is TargetHeaderNode ||
      node is LoopNode ||
      node is InstructionSetNode ||
      node is ParallelNode ||
      node is ConditionalNode ||
      node is RecoveryNode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anyCollapsed = ref.watch(
      collapsedNodeIdsProvider.select((s) => s.isNotEmpty),
    );

    return Tooltip(
      message: anyCollapsed ? 'Expand all' : 'Collapse all',
      child: GestureDetector(
        onTap: () {
          final notifier = ref.read(collapsedNodeIdsProvider.notifier);
          if (anyCollapsed) {
            notifier.expandAll();
          } else {
            final containerIds = <String>[
              for (final entry in sequence.nodes.entries)
                if (entry.key != sequence.rootNodeId &&
                    _isContainer(entry.value) &&
                    entry.value.childIds.isNotEmpty)
                  entry.key,
            ];
            notifier.collapseAll(containerIds);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                anyCollapsed
                    ? LucideIcons.chevronsDownUp
                    : LucideIcons.chevronsUpDown,
                size: 12,
                color: colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                anyCollapsed ? 'Expand' : 'Collapse',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MinimapToggle extends ConsumerWidget {
  final NightshadeColors colors;

  const _MinimapToggle({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible = ref.watch(minimapVisibleProvider);

    return Tooltip(
      message: isVisible ? 'Hide mini-map' : 'Show mini-map',
      child: GestureDetector(
        onTap: () {
          ref.read(minimapVisibleProvider.notifier).state = !isVisible;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isVisible
                ? NightshadeDecorations.statusChip(
                    colors.primary,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    bordered: false,
                  ).color
                : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
            border: Border.all(
              color: isVisible
                  ? colors.primary.withValues(alpha: 0.4)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.map,
                size: 12,
                color: isVisible ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Map',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w600,
                  color: isVisible ? colors.primary : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineToggle extends ConsumerWidget {
  final NightshadeColors colors;

  const _TimelineToggle({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVisible = ref.watch(timelineVisibleProvider);

    return Tooltip(
      message: isVisible ? 'Hide timeline' : 'Show timeline',
      child: GestureDetector(
        onTap: () {
          ref.read(timelineVisibleProvider.notifier).state = !isVisible;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isVisible
                ? NightshadeDecorations.statusChip(
                    colors.primary,
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    bordered: false,
                  ).color
                : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
            border: Border.all(
              color: isVisible
                  ? colors.primary.withValues(alpha: 0.4)
                  : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.ganttChart,
                size: 12,
                color: isVisible ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Timeline',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w600,
                  color: isVisible ? colors.primary : colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
