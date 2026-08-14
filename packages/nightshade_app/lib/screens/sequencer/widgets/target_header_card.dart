import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../framing/altitude_chart.dart';
import 'notes_panel.dart';
import '../plan_math.dart';
import 'target_coordinates.dart';

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

  String _formatRA(double raHours) =>
      CoordinateFormat.ra(raHours, seconds: SecondsPrecision.integerRounded);

  String _formatDec(double decDegrees) => CoordinateFormat.dec(decDegrees,
      seconds: SecondsPrecision.integerRounded);

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

                // Per-target notes journal. Renders
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
            // `VisualDensity.compact` is what actually decided this button's
            // hit area: `IconButton` sizes its tap padding from
            // `kMinInteractiveDimension` PLUS `visualDensity
            // .baseSizeAdjustment`, so compact's -2 took 8dp off 48 and the
            // control measured 40x40 on a phone. `constraints` does not
            // override that — it bounds the visual button — so raising the
            // constraints alone left the measurement exactly where it was.
            visualDensity: NightshadeTouchTarget.visualDensity(context),
            padding: EdgeInsets.zero,
            constraints: NightshadeTouchTarget.constraints(
              context,
              desktopExtent: 28,
            ),
          ),

          // Menu button
          PopupMenuButton<String>(
            icon: Icon(
              LucideIcons.moreVertical,
              size: 16,
              color: widget.colors.textMuted,
            ),
            padding: EdgeInsets.zero,
            constraints: NightshadeTouchTarget.constraints(
              context,
              desktopExtent: 28,
            ),
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
    // Printing the 0h/+0° placeholder as `00h 00m 00s` reads as a real
    // pointing. Say "Not set" instead, in the same amber the card already
    // uses for the target category, so an unaimed target is obvious in the
    // tree without opening the properties panel.
    final unset = targetCoordinatesUnset(node);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: widget.colors.border.withValues(alpha: 0.5)),
        ),
      ),
      // The chips WRAP rather than sharing one rigid row. A fixed row of
      // monospace coordinates plus a Spacer overflowed the card by 41px at a
      // 900px window and 69px in the tighter builder pane (Wave D, WD-SEQ-N2),
      // which paints the striped overflow bar over the pointing the operator
      // came here to read.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                // RA
                _CoordinateChip(
                  label: 'RA',
                  value: unset ? 'Not set' : _formatRA(node.raHours),
                  colors: widget.colors,
                  isPlaceholder: unset,
                ),

                // Dec
                _CoordinateChip(
                  label: 'Dec',
                  value: unset ? 'Not set' : _formatDec(node.decDegrees),
                  colors: widget.colors,
                  isPlaceholder: unset,
                ),

                // Rotation (if set)
                if (node.rotation != null)
                  _CoordinateChip(
                    label: '↻',
                    value: '${node.rotation!.toStringAsFixed(1)}°',
                    colors: widget.colors,
                  ),
              ],
            ),
          ),

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
    // WE-SEQ-N2: the same card said "RA Not set · Dec Not set · Needs
    // coordinates" AND plotted a full curve with "Alt 44.7° / Airmass 1.42 /
    // Rise 15:03 / Transit 21:06" — the numbers for the 0h/+0° placeholder a
    // Target node is born with, presented as this target's night. An altitude
    // curve for a pointing nobody chose is a fabricated observation plan: it is
    // read as "this target transits at 21:06", and it is wrong for whatever
    // object the operator has in mind.
    //
    // Same predicate as the coordinate row and the "Needs coordinates" footer,
    // so the three cannot disagree.
    final unset = targetCoordinatesUnset(node);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: widget.colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: unset
          ? Row(
              children: [
                Icon(
                  LucideIcons.mapPin,
                  size: 14,
                  color: widget.colors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Set coordinates to see this target rise, transit and set.',
                    style: NightshadeTypography.caption.copyWith(
                      color: widget.colors.textMuted,
                    ),
                  ),
                ),
              ],
            )
          : AltitudeChart(
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
    // A looped target has no derivable completion (the loop resets its
    // children every pass), so fall back to the plan summary rather than
    // render a ratio that hits 100% after the first of N passes.
    final showLiveBar =
        isActive && stats.hasPlannedFrames && stats.hasKnownCompletion;

    final currentNodeId = progress.currentNodeId;
    final currentNodeDetail = currentNodeId != null
        ? progress.nodeProgressDetail[currentNodeId]
        : null;

    // The pre-run label is the node's *execution* status, so everything that
    // has not run yet lands on the default arm. Saying "Ready" there is a claim
    // the card has already contradicted two rows above: seen during the GUI
    // drive 2026-08-09, a target reading `RA Not set  Dec Not set`, carrying the
    // card's own red blocking-issue dot, and refused by pre-flight with "Target
    // Coordinates Not Set", still announced itself as **Ready**.
    //
    // "Ready" is the right word for a target that has not started and could;
    // it is the wrong word for one the app will refuse to run. The same
    // `targetCoordinatesUnset` predicate the coordinate row uses decides which
    // of the two this is.
    final statusLabel = switch (widget.nodeStatus) {
      NodeStatus.running => currentNodeDetail ?? progress.message ?? 'Running',
      NodeStatus.success => 'Completed',
      NodeStatus.failure => 'Failed',
      NodeStatus.skipped => 'Skipped',
      NodeStatus.cancelled => 'Cancelled',
      _ => targetCoordinatesUnset(widget.node) ? 'Needs coordinates' : 'Ready',
    };

    // Build the plan summary. A loop-until-stopped SmartExposure is
    // open-ended, so we describe it as "looping" (with the budget if set)
    // rather than inventing a fixed exposure count — and we never fall back to
    // "No exposure nodes" just because the only imager is an open-ended loop.
    final String planLabel;
    if (plan.hasOpenEndedLoop) {
      final loopPart = plan.openEndedBudgetSecs > 0
          ? 'Looping • up to ${_formatDuration(plan.openEndedBudgetSecs)} (until window end)'
          : 'Looping until window end';
      planLabel = plan.frames > 0
          ? '${plan.frames} planned exposures + $loopPart'
          : loopPart;
    } else if (plan.frames > 0) {
      final counted =
          '${plan.frames} planned exposures • ${_formatDuration(plan.integrationSecs)}';
      // Under a time/altitude/forever loop the counted figure is one pass, not
      // the night's total — say so rather than quoting a floor as the plan.
      planLabel = plan.hasUnboundedRepeat
          ? '$counted per pass • loop repeats until its stop condition'
          : counted;
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
    //
    // Whole minutes are the wrong unit for the first minute of a run and for
    // any short sequence: measured live, a 4x3s target read "0/4 done · 0m / 1m"
    // seven seconds in, and "2/4 done · 1m / 1m" at forty — while the panel
    // directly above it in the same card read "~34s". The estimate beside it
    // uses the shared compact duration format, so this uses it too and the two
    // halves of one card finally quote the same unit.
    final completedElapsed = _formatDuration(stats.completedIntegrationSecs);
    final totalElapsed = _formatDuration(stats.totalIntegrationSecs);
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
              Flexible(
                child: Text(
                  '${stats.completedFrames}/${stats.totalFrames} done',
                  style: NightshadeTypography.labelStrongSm
                      .copyWith(color: widget.colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text('•',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: widget.colors.textMuted)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$completedElapsed / $totalElapsed',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: widget.colors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 8),
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

  /// Count the frames and integration time planned under this target.
  ///
  /// Delegates to the shared [plannedCaptureUnder] walk so this card, the
  /// library preview and the model's own `Sequence.totalExposures` can never
  /// disagree again. It previously walked the subtree with NO loop
  /// multiplier: a Quick-Start-Wizard sequence (`Capture Loop x10` wrapping a
  /// single exposure node) read "1 planned exposures - 2m" here while the
  /// toolbar beside it read "10 frames".
  PlannedCapture _calculateTargetPlan(Sequence? sequence) {
    if (sequence == null) return PlannedCapture.empty;
    return plannedCaptureUnder(sequence, widget.node.id);
  }

  String _formatDuration(double totalSeconds) =>
      DurationFormat.seconds(totalSeconds, style: DurationStyle.compact);
}

class _CoordinateChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  /// True when [value] stands in for a coordinate the user has not set. Drawn
  /// in warning colour so "Not set" cannot be mistaken for a measurement.
  final bool isPlaceholder;

  const _CoordinateChip({
    required this.label,
    required this.value,
    required this.colors,
    this.isPlaceholder = false,
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
            color: isPlaceholder ? colors.warning : colors.textPrimary,
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
              size: 18,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}
