import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../framing/altitude_chart.dart';
import 'notes_panel.dart';

/// A rich card widget for displaying target header nodes in the sequencer.
/// Shows coordinates, altitude chart, progress tracking, and mosaic panel info.
class TargetHeaderCard extends ConsumerStatefulWidget {
  final TargetHeaderNode node;
  final NightshadeColors colors;
  final bool isSelected;
  final NodeStatus? nodeStatus;
  final VoidCallback? onSelect;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onDelete;
  final VoidCallback? onExpand;
  final bool isExpanded;
  final bool isMobile;

  const TargetHeaderCard({
    super.key,
    required this.node,
    required this.colors,
    this.isSelected = false,
    this.nodeStatus,
    this.onSelect,
    this.onToggleEnabled,
    this.onDelete,
    this.onExpand,
    this.isExpanded = true,
    this.isMobile = false,
  });

  @override
  ConsumerState<TargetHeaderCard> createState() => _TargetHeaderCardState();
}

class _TargetHeaderCardState extends ConsumerState<TargetHeaderCard> {
  late bool _showAltitudeChart;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    // Hide altitude chart by default on mobile to save space
    _showAltitudeChart = !widget.isMobile;
  }

  Color _getStatusColor() {
    switch (widget.nodeStatus) {
      case NodeStatus.running:
        return widget.colors.info;
      case NodeStatus.success:
        return widget.colors.success;
      case NodeStatus.failure:
        return widget.colors.error;
      case NodeStatus.skipped:
        return widget.colors.textMuted;
      case NodeStatus.cancelled:
        return widget.colors.warning;
      default:
        return Colors.transparent;
    }
  }

  String _formatRA(double raHours) {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    final seconds = (((raHours - hours) * 60 - minutes) * 60).round();
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final absVal = decDegrees.abs();
    final degrees = absVal.floor();
    final minutes = ((absVal - degrees) * 60).floor();
    final seconds = (((absVal - degrees) * 60 - minutes) * 60).round();
    return '$sign${degrees.toString().padLeft(2, '0')}° ${minutes.toString().padLeft(2, '0')}\' ${seconds.toString().padLeft(2, '0')}"';
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final statusColor = _getStatusColor();
    final isDisabled = !node.isEnabled;
    final isRunning = widget.nodeStatus == NodeStatus.running;
    final categoryColor = widget.colors.warning; // Target category color

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: widget.isSelected
              ? NightshadeDecorations.cardSelected(
                  categoryColor,
                  background: widget.colors.surface,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                  borderWidth: 2,
                )
              : BoxDecoration(
                  color: _isHovered
                      ? categoryColor.withValues(alpha: 0.06)
                      : widget.colors.surface,
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline8),
                  border: Border.all(
                    color: isRunning
                        ? widget.colors.info
                        : categoryColor.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
          child: Opacity(
            opacity: isDisabled ? 0.5 : 1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header row
                _buildHeader(node, statusColor, categoryColor, isRunning),

                // Coordinates row
                _buildCoordinatesRow(node),

                // Altitude chart (collapsible)
                if (_showAltitudeChart) _buildAltitudeChart(node),

                // Constraints row (if any)
                if (node.hasTimeConstraints || node.hasAltitudeConstraints)
                  _buildConstraintsRow(node),

                // Unified progress row. Single source of truth for the
                // per-target progress display — adapts to either idle
                // ("24 planned exposures") or running ("12/24 done · 32m
                // / 96m") states so we never stack two indicators.
                _buildProgressRow(),

                // Wave 6 Agent 5 — per-target notes journal. Renders
                // the latest 2 notes for this target with a "View all"
                // affordance opening the full list. Notes are keyed by
                // [TargetHeaderNode.targetName] (display name; catalog
                // id when available — same string the journal indexes
                // on) so the entries survive renaming a sequence-side
                // target object.
                TargetNotesSection(
                  targetId: widget.node.targetName,
                  colors: widget.colors,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    TargetHeaderNode node,
    Color statusColor,
    Color categoryColor,
    bool isRunning,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: NightshadeDecorations.tintedBadge(
        categoryColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
      ),
      child: Row(
        children: [
          // Status indicator
          if (widget.nodeStatus != null &&
              widget.nodeStatus != NodeStatus.pending)
            Container(
              width: 4,
              height: 28,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline2),
              ),
            ),

          // Target icon
          Container(
            width: 36,
            height: 36,
            decoration: NightshadeDecorations.statusChip(
              categoryColor,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
              bordered: false,
            ),
            child: isRunning
                ? _SpinningIcon(
                    icon: LucideIcons.target,
                    color: categoryColor,
                  )
                : Icon(
                    LucideIcons.target,
                    size: 18,
                    color: categoryColor,
                  ),
          ),
          const SizedBox(width: 12),

          // Target name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.displayName,
                  style: NightshadeTypography.h5
                      .copyWith(color: widget.colors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (node.mosaicPanel != null)
                  Text(
                    node.mosaicPanel!.mosaicName,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: widget.colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Mosaic panel badge
          if (node.mosaicPanel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: NightshadeDecorations.statusChip(
                widget.colors.accent,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                bordered: false,
              ),
              child: Text(
                node.mosaicPanel!.displayLabel,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.accent,
                ),
              ),
            ),

          const SizedBox(width: 8),

          // Altitude chart toggle
          IconButton(
            icon: Icon(
              _showAltitudeChart
                  ? LucideIcons.chevronUp
                  : LucideIcons.chevronDown,
              size: 16,
              color: widget.colors.textMuted,
            ),
            onPressed: () =>
                setState(() => _showAltitudeChart = !_showAltitudeChart),
            tooltip: _showAltitudeChart
                ? 'Hide altitude chart'
                : 'Show altitude chart',
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),

          // Menu button
          PopupMenuButton<String>(
            icon: Icon(
              LucideIcons.moreVertical,
              size: 16,
              color: widget.colors.textMuted,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onSelected: (value) {
              switch (value) {
                case 'toggle':
                  widget.onToggleEnabled?.call();
                  break;
                case 'delete':
                  widget.onDelete?.call();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle',
                child: Row(
                  children: [
                    Icon(
                      node.isEnabled ? LucideIcons.eyeOff : LucideIcons.eye,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(node.isEnabled ? 'Disable' : 'Enable'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash2,
                        size: 16, color: widget.colors.error),
                    const SizedBox(width: 8),
                    Text('Delete',
                        style: TextStyle(color: widget.colors.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinatesRow(TargetHeaderNode node) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: widget.colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // RA
          _CoordinateChip(
            label: 'RA',
            value: _formatRA(node.raHours),
            colors: widget.colors,
          ),
          const SizedBox(width: 16),

          // Dec
          _CoordinateChip(
            label: 'Dec',
            value: _formatDec(node.decDegrees),
            colors: widget.colors,
          ),

          // Rotation (if set)
          if (node.rotation != null) ...[
            const SizedBox(width: 16),
            _CoordinateChip(
              label: '↻',
              value: '${node.rotation!.toStringAsFixed(1)}°',
              colors: widget.colors,
            ),
          ],

          const Spacer(),

          // Priority badge
          if (node.priority > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: widget.colors.surfaceAlt,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline4),
              ),
              child: Text(
                'P${node.priority}',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize10,
                  fontWeight: FontWeight.w500,
                  color: widget.colors.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAltitudeChart(TargetHeaderNode node) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: widget.colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: AltitudeChart(
        raHours: node.raHours,
        decDegrees: node.decDegrees,
        targetName: node.targetName,
      ),
    );
  }

  Widget _buildConstraintsRow(TargetHeaderNode node) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: widget.colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          // Time constraints
          if (node.startAfter != null)
            _ConstraintChip(
              icon: LucideIcons.clock,
              label: 'Start: ${_formatTime(node.startAfter!)}',
              colors: widget.colors,
            ),
          if (node.startAfter != null && node.endBefore != null)
            const SizedBox(width: 12),
          if (node.endBefore != null)
            _ConstraintChip(
              icon: LucideIcons.timer,
              label: 'End: ${_formatTime(node.endBefore!)}',
              colors: widget.colors,
            ),

          // Altitude constraints
          if (node.hasTimeConstraints && node.hasAltitudeConstraints)
            const SizedBox(width: 12),
          if (node.minAltitude != null)
            _ConstraintChip(
              icon: LucideIcons.arrowUp,
              label: 'Min: ${node.minAltitude!.toStringAsFixed(0)}°',
              colors: widget.colors,
            ),
          if (node.minAltitude != null && node.maxAltitude != null)
            const SizedBox(width: 8),
          if (node.maxAltitude != null)
            _ConstraintChip(
              icon: LucideIcons.arrowDown,
              label: 'Max: ${node.maxAltitude!.toStringAsFixed(0)}°',
              colors: widget.colors,
            ),
        ],
      ),
    );
  }

  /// Unified progress row: shows the plan summary when idle, and the
  /// live progress bar + completed/planned counters when running.
  ///
  /// Why merged: the earlier implementation rendered a separate
  /// `_buildExecutionProgressBar()` block above this row during a run,
  /// so the card showed two indicators stacked (a frame counter on top
  /// of a status line below). The audit flagged that as confusing — a
  /// user can only act on one "current state" at a time. This row now
  /// adapts: idle shows the static plan summary, running shows the
  /// progress bar with the same per-target stats from
  /// [targetExecutionProgressProvider].
  Widget _buildProgressRow() {
    final sequence = ref.watch(currentSequenceProvider);
    final progress = ref.watch(sequenceProgressProvider);
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final stats = ref.watch(targetExecutionProgressProvider(widget.node.id));
    final plan = _calculateTargetPlan(sequence);

    final isActive = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused ||
        executionState == SequenceExecutionState.stopping;
    final showLiveBar = isActive && stats.hasPlannedFrames;

    final currentNodeId = progress.currentNodeId;
    final currentNodeDetail = currentNodeId != null
        ? progress.nodeProgressDetail[currentNodeId]
        : null;

    final statusLabel = switch (widget.nodeStatus) {
      NodeStatus.running => currentNodeDetail ?? progress.message ?? 'Running',
      NodeStatus.success => 'Completed',
      NodeStatus.failure => 'Failed',
      NodeStatus.skipped => 'Skipped',
      NodeStatus.cancelled => 'Cancelled',
      _ => 'Ready',
    };

    // Build the plan summary. A loop-until-stopped SmartExposure is
    // open-ended, so we describe it as "looping" (with the budget if set)
    // rather than inventing a fixed exposure count — and we never fall back to
    // "No exposure nodes" just because the only imager is an open-ended loop.
    final String planLabel;
    if (plan.hasOpenEndedLoop) {
      final loopPart = plan.loopBudgetSecs > 0
          ? 'Looping • up to ${_formatDuration(plan.loopBudgetSecs)} (until window end)'
          : 'Looping until window end';
      planLabel = plan.totalExposures > 0
          ? '${plan.totalExposures} planned exposures + $loopPart'
          : loopPart;
    } else if (plan.totalExposures > 0) {
      planLabel =
          '${plan.totalExposures} planned exposures • ${_formatDuration(plan.totalIntegrationSecs)}';
    } else {
      planLabel = 'No exposure nodes under this target';
    }

    if (!showLiveBar) {
      // Idle / completed / skipped — single line with status + plan
      // summary. No progress bar.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              widget.nodeStatus == NodeStatus.running
                  ? LucideIcons.activity
                  : LucideIcons.camera,
              size: 14,
              color: widget.nodeStatus == NodeStatus.running
                  ? widget.colors.info
                  : widget.colors.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusLabel,
                    style: NightshadeTypography.labelStrongSm.copyWith(
                        color: widget.nodeStatus == NodeStatus.running
                            ? widget.colors.info
                            : widget.colors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    planLabel,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      color: widget.colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.chevronDown,
              size: 14,
              color: widget.colors.textMuted,
            ),
          ],
        ),
      );
    }

    // Live run: progress bar with counters above.
    final completedMins = (stats.completedIntegrationSecs / 60).round();
    final totalMins = (stats.totalIntegrationSecs / 60).round();
    final progressState = executionState == SequenceExecutionState.paused
        ? NightshadeProgressState.paused
        : NightshadeProgressState.normal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.activity, size: 14, color: widget.colors.info),
              const SizedBox(width: 8),
              Text(
                '${stats.completedFrames}/${stats.totalFrames} done',
                style: NightshadeTypography.labelStrongSm
                    .copyWith(color: widget.colors.textSecondary),
              ),
              const SizedBox(width: 6),
              Text('•',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: widget.colors.textMuted)),
              const SizedBox(width: 6),
              Text(
                '${completedMins}m / ${totalMins}m',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: widget.colors.textMuted),
              ),
              const Spacer(),
              Text(
                '${(stats.fraction * 100).round()}%',
                style: NightshadeTypography.labelStrongSm
                    .copyWith(color: widget.colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 4),
          NightshadeProgressBar(
            value: stats.fraction,
            style: NightshadeProgressStyle.thin,
            state: progressState,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  ({
    int totalExposures,
    double totalIntegrationSecs,
    bool hasOpenEndedLoop,
    double loopBudgetSecs,
  }) _calculateTargetPlan(Sequence? sequence) {
    if (sequence == null || !sequence.nodes.containsKey(widget.node.id)) {
      return (
        totalExposures: 0,
        totalIntegrationSecs: 0.0,
        hasOpenEndedLoop: false,
        loopBudgetSecs: 0.0,
      );
    }

    var totalExposures = 0;
    var totalIntegrationSecs = 0.0;
    // Loop-until-stopped SmartExposure nodes capture an unbounded number of
    // subs (bounded by time/window, not by counts), so a fixed "N planned
    // exposures" figure is meaningless for them. Track that separately so the
    // label can say "looping" / "up to <budget>" instead of a misleading count.
    var hasOpenEndedLoop = false;
    var loopBudgetSecs = 0.0;
    final visited = <String>{};

    void visit(String nodeId) {
      if (!visited.add(nodeId)) return;
      final node = sequence.nodes[nodeId];
      if (node == null) return;

      if (node is ExposureNode) {
        totalExposures += node.count;
        totalIntegrationSecs += node.durationSecs * node.count;
      } else if (node is SmartExposureNode) {
        if (node.loopUntilStopped) {
          // Open-ended: counts are ignored. Record the budget (if any) so the
          // label can show "up to Xh"; don't fold a fake exposure count in.
          hasOpenEndedLoop = true;
          loopBudgetSecs += node.integrationBudgetSecs;
        } else {
          // Smart Exposure carries its captures in per-filter plans, not as
          // standalone ExposureNodes — count them so an auto-built (Plan
          // Tonight) sequence, whose imaging is a single SmartExposure node,
          // no longer reports "No exposure nodes under this target".
          for (final plan in node.plans) {
            totalExposures += plan.count;
          }
          totalIntegrationSecs += node.totalIntegrationSecs;
        }
      }

      for (final childId in node.childIds) {
        visit(childId);
      }
    }

    visit(widget.node.id);
    return (
      totalExposures: totalExposures,
      totalIntegrationSecs: totalIntegrationSecs,
      hasOpenEndedLoop: hasOpenEndedLoop,
      loopBudgetSecs: loopBudgetSecs,
    );
  }

  String _formatDuration(double totalSeconds) {
    final seconds = totalSeconds.round();
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}

class _CoordinateChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _CoordinateChip({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style:
              NightshadeTypography.labelQuiet.copyWith(color: colors.textMuted),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

class _ConstraintChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _ConstraintChip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Spinning icon for running state
class _SpinningIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _SpinningIcon({
    required this.icon,
    required this.color,
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
            size: 18,
            color: widget.color,
          ),
        );
      },
    );
  }
}
