import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../framing/altitude_chart.dart';

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
          decoration: BoxDecoration(
            color: widget.isSelected
                ? categoryColor.withValues(alpha: 0.12)
                : _isHovered
                    ? categoryColor.withValues(alpha: 0.06)
                    : widget.colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected
                  ? categoryColor
                  : isRunning
                      ? widget.colors.info
                      : categoryColor.withValues(alpha: 0.4),
              width: widget.isSelected ? 2 : 1.5,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: categoryColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
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

                // Runtime progress row
                _buildProgressRow(),
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
      decoration: BoxDecoration(
        color: categoryColor.withValues(alpha: 0.08),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),

          // Target icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: widget.colors.textPrimary,
                  ),
                ),
                if (node.mosaicPanel != null)
                  Text(
                    node.mosaicPanel!.mosaicName,
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),

          // Mosaic panel badge
          if (node.mosaicPanel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: widget.colors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                node.mosaicPanel!.displayLabel,
                style: TextStyle(
                  fontSize: 10,
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
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'P${node.priority}',
                style: TextStyle(
                  fontSize: 10,
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

  Widget _buildProgressRow() {
    final sequence = ref.watch(currentSequenceProvider);
    final progress = ref.watch(sequenceProgressProvider);
    final plan = _calculateTargetPlan(sequence);

    final currentNodeId = progress.currentNodeId;
    final currentNodeProgress = currentNodeId != null
        ? progress.nodeProgressPercent[currentNodeId]
        : null;
    final currentNodeDetail = currentNodeId != null
        ? progress.nodeProgressDetail[currentNodeId]
        : null;

    final isCurrentTarget = progress.currentTarget != null &&
        (progress.currentTarget == widget.node.targetName ||
            progress.currentTarget == widget.node.displayName);

    final statusLabel = switch (widget.nodeStatus) {
      NodeStatus.running => currentNodeDetail ?? progress.message ?? 'Running',
      NodeStatus.success => 'Completed',
      NodeStatus.failure => 'Failed',
      NodeStatus.skipped => 'Skipped',
      NodeStatus.cancelled => 'Cancelled',
      _ => 'Ready',
    };

    final planLabel = plan.totalExposures > 0
        ? '${plan.totalExposures} planned exposures • ${_formatDuration(plan.totalIntegrationSecs)}'
        : 'No exposure nodes under this target';

    final detailLabel = isCurrentTarget && currentNodeProgress != null
        ? '${currentNodeProgress.toStringAsFixed(0)}% • $statusLabel'
        : statusLabel;

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
                  detailLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: widget.nodeStatus == NodeStatus.running
                        ? widget.colors.info
                        : widget.colors.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  planLabel,
                  style: TextStyle(
                    fontSize: 10,
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

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  ({int totalExposures, double totalIntegrationSecs}) _calculateTargetPlan(
      Sequence? sequence) {
    if (sequence == null || !sequence.nodes.containsKey(widget.node.id)) {
      return (totalExposures: 0, totalIntegrationSecs: 0.0);
    }

    var totalExposures = 0;
    var totalIntegrationSecs = 0.0;
    final visited = <String>{};

    void visit(String nodeId) {
      if (!visited.add(nodeId)) return;
      final node = sequence.nodes[nodeId];
      if (node == null) return;

      if (node is ExposureNode) {
        totalExposures += node.count;
        totalIntegrationSecs += node.durationSecs * node.count;
      }

      for (final childId in node.childIds) {
        visit(childId);
      }
    }

    visit(widget.node.id);
    return (
      totalExposures: totalExposures,
      totalIntegrationSecs: totalIntegrationSecs,
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
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
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
