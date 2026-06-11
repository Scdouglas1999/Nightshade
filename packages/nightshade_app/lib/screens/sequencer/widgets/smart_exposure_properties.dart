// SmartExposure properties editor.
//
// Tabular per-filter editor for the SmartExposureNode. Each row holds one
// FilterPlan (filter, count, duration, gain, offset, binning, dither cadence)
// and rows are drag-and-drop reorderable to change the rotation order.
//
// The editor wraps its inputs in IgnorePointer-on-canEdit-off the same way
// ExposureProperties does so a running sequence can't be
// mutated through this surface.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'node_property_widgets.dart';

class SmartExposureProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SmartExposureNode node;

  const SmartExposureProperties({
    super.key,
    required this.colors,
    required this.node,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeEquipmentProfileProvider);
    final filterNames = profile?.filterNames ?? <String>[];
    final canEdit = ref.watch(canEditSequenceProvider);
    final exposureContext =
        ref.watch(smartNightExposureContextProvider).valueOrNull;

    return IgnorePointer(
      ignoring: !canEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Smart Exposure',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 13),
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'One row per filter. Drag rows to reorder rotation.',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 11),
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 12),

          // === Filter plan list ===
          _PlanList(
            colors: colors,
            node: node,
            filterNames: filterNames,
            exposureContext: exposureContext,
            loopMode: node.loopUntilStopped,
            onPlansChanged: (newPlans) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(plans: newPlans),
                  );
            },
          ),

          // === Add row button ===
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              final defaultFilter =
                  filterNames.isNotEmpty ? filterNames.first : '';
              final defaultIndex = filterNames.isNotEmpty ? 0 : null;
              final durationSecs = _recommendedExposureSeconds(
                exposureContext,
                defaultFilter,
                fallbackSecs: 60.0,
              );
              final newPlans = List<FilterPlan>.from(node.plans)
                ..add(FilterPlan(
                  filterName: defaultFilter,
                  filterIndex: defaultIndex,
                  count: 10,
                  durationSecs: durationSecs,
                ));
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(plans: newPlans),
                  );
            },
            icon: Icon(LucideIcons.plus, size: 14, color: colors.primary),
            label: Text(
              'Add Filter Plan',
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 12),
                color: colors.primary,
              ),
            ),
          ),

          // === Global toggles ===
          const SizedBox(height: 16),
          NodePropertyField(
            colors: colors,
            label: 'Rotate Filters',
            child: NodeToggleSwitch(
              colors: colors,
              value: node.rotateFilters,
              onChanged: (v) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(rotateFilters: v),
                    );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              node.rotateFilters
                  ? 'Round-robin: RGRGRG…'
                  : 'Drain each filter before moving on: RRRGGGBBB…',
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 11),
                color: colors.textMuted,
              ),
            ),
          ),

          NodePropertyField(
            colors: colors,
            label: 'Dither on Filter Change',
            child: NodeToggleSwitch(
              colors: colors,
              value: node.ditherOnFilterChange,
              onChanged: (v) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(ditherOnFilterChange: v),
                    );
              },
            ),
          ),

          if (node.rotateFilters) ...[
            NodePropertyField(
              colors: colors,
              label: 'Switch Filter Every Frame',
              child: NodeToggleSwitch(
                colors: colors,
                // Drives "loop until stopped" mode: 1 sub per filter,
                // round-robin, looping until the target's window ends (or the
                // integration budget). In this mode the per-filter Counts and
                // Batch Size are irrelevant — the loop is bounded by time, not
                // by drained counts. Off → today's count-draining behaviour.
                value: node.loopUntilStopped,
                onChanged: (v) {
                  ref.read(currentSequenceProvider.notifier).updateNode(
                        // Force a clean 1-sub rotation when enabling. We leave
                        // batchSize at its stored value when turning OFF so the
                        // numeric Batch Size control reappears as the user left
                        // it (the Rust executor only coerces it while loop mode
                        // is on).
                        node.copyWith(
                          loopUntilStopped: v,
                          batchSize: v ? 1 : node.batchSize,
                        ),
                      );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                node.loopUntilStopped
                    ? '1 sub per filter, looping until the target’s window '
                        'ends (or the integration budget). Per-filter Counts are '
                        'ignored in this mode.'
                    : 'Takes Batch Size subs per filter before rotating to the next.',
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 11),
                  color: colors.textMuted,
                ),
              ),
            ),
            // The unbounded-loop hint: in loop mode, if there's neither an
            // integration budget nor a bounding target window, the executor
            // will fail closed (errors-are-a-feature). Surface that here so the
            // user fixes it at edit time rather than at runtime.
            if (node.loopUntilStopped &&
                node.integrationBudgetSecs <= 0 &&
                !_hasBoundingTargetWindow(ref))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline8),
                    border: Border.all(
                        color: colors.warning.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(LucideIcons.alertTriangle,
                          size: 14, color: colors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Nothing bounds this loop. Set an integration budget '
                          'below, or place this node under a target with an end '
                          'condition (ends-when / ends-before) — otherwise the '
                          'run will refuse to start.',
                          style: TextStyle(
                            fontSize: Responsive.fontSize(context, 11),
                            color: colors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // The numeric Batch Size only matters in the (non-loop) multi-sub
            // case. It's hidden in loop mode (batch is forced to 1).
            if (!node.loopUntilStopped && node.batchSize > 1)
              NodePropertyField(
                colors: colors,
                label: 'Batch Size (per visit)',
                child: NodeNumberInput(
                  colors: colors,
                  value: node.batchSize.toDouble(),
                  min: 2,
                  max: 999,
                  onChanged: (v) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(batchSize: v.toInt().clamp(2, 999)),
                        );
                  },
                ),
              ),
          ],

          // === Integration budget ===
          const SizedBox(height: 12),
          _BudgetInput(
            colors: colors,
            node: node,
            onChanged: (secs) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(integrationBudgetSecs: secs),
                  );
            },
          ),

          // === Estimate summary ===
          const SizedBox(height: 12),
          _EstimateSummary(colors: colors, node: node),
        ],
      ),
    );
  }

  /// True when this node sits (directly or transitively) under a
  /// [TargetHeaderNode] that has an end condition — `endWhen` (an
  /// altitude/time crossing trigger) or the legacy `endBefore` wall-clock
  /// cutoff. In loop-until-stopped mode that target window is what bounds the
  /// otherwise-unbounded rotation, so the editor only warns when no such
  /// window (and no integration budget) exists.
  ///
  /// Walks parents via [SequenceNode.parentId]; cheap (depth is small) and
  /// runs only while the warning predicate is being evaluated.
  bool _hasBoundingTargetWindow(WidgetRef ref) {
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) return false;
    final nodes = sequence.nodes;
    var currentId = node.parentId;
    final seen = <String>{};
    while (currentId != null && seen.add(currentId)) {
      final parent = nodes[currentId];
      if (parent == null) break;
      if (parent is TargetHeaderNode &&
          (parent.endWhen != null || parent.endBefore != null)) {
        return true;
      }
      currentId = parent.parentId;
    }
    return false;
  }
}

class _PlanList extends StatelessWidget {
  final NightshadeColors colors;
  final SmartExposureNode node;
  final List<String> filterNames;
  final SmartNightExposureContext? exposureContext;

  /// When true (loop-until-stopped), per-filter Count inputs are replaced by a
  /// read-only "looping" note because the counts are ignored.
  final bool loopMode;
  final ValueChanged<List<FilterPlan>> onPlansChanged;

  const _PlanList({
    required this.colors,
    required this.node,
    required this.filterNames,
    required this.exposureContext,
    required this.loopMode,
    required this.onPlansChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (node.plans.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.alertCircle, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No filter plans yet — add one below.',
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 12),
                  color: colors.textMuted,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: node.plans.length,
      onReorder: (oldIndex, newIndex) {
        var adjusted = newIndex;
        if (oldIndex < adjusted) adjusted -= 1;
        final newPlans = List<FilterPlan>.from(node.plans);
        final moved = newPlans.removeAt(oldIndex);
        newPlans.insert(adjusted, moved);
        onPlansChanged(newPlans);
      },
      itemBuilder: (context, index) {
        final plan = node.plans[index];
        return _PlanRow(
          key: ValueKey('smart-exposure-plan-$index-${plan.filterName}'),
          colors: colors,
          plan: plan,
          index: index,
          filterNames: filterNames,
          exposureContext: exposureContext,
          loopMode: loopMode,
          onChanged: (updated) {
            final newPlans = List<FilterPlan>.from(node.plans);
            newPlans[index] = updated;
            onPlansChanged(newPlans);
          },
          onDelete: () {
            final newPlans = List<FilterPlan>.from(node.plans)..removeAt(index);
            onPlansChanged(newPlans);
          },
        );
      },
    );
  }
}

class _PlanRow extends StatelessWidget {
  final NightshadeColors colors;
  final FilterPlan plan;
  final int index;
  final List<String> filterNames;
  final SmartNightExposureContext? exposureContext;
  final bool loopMode;
  final ValueChanged<FilterPlan> onChanged;
  final VoidCallback onDelete;

  const _PlanRow({
    super.key,
    required this.colors,
    required this.plan,
    required this.index,
    required this.filterNames,
    required this.exposureContext,
    required this.loopMode,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final recommendation = exposureContext?.recommendForFilter(plan.filterName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(
                    LucideIcons.gripVertical,
                    size: 16,
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _buildFilterDropdown(context)),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 14,
                    color: colors.error,
                  ),
                  tooltip: 'Remove plan',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: NodePropertyField(
                    colors: colors,
                    label: 'Count',
                    // Loop-until-stopped ignores per-filter counts — surface a
                    // read-only "looping" placeholder instead of an editable
                    // field so the user isn't misled into tuning a number that
                    // does nothing.
                    child: loopMode
                        ? Container(
                            height: 38,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(
                                  NightshadeTokens.radiusInline8),
                              border: Border.all(color: colors.border),
                            ),
                            child: Text(
                              '— looping',
                              style: TextStyle(
                                fontSize: Responsive.fontSize(context, 12),
                                color: colors.textMuted,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : NodeNumberInput(
                            colors: colors,
                            value: plan.count.toDouble(),
                            min: 0,
                            max: 9999,
                            onChanged: (v) =>
                                onChanged(plan.copyWith(count: v.toInt())),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NodePropertyField(
                    colors: colors,
                    label: 'Duration',
                    child: NodeNumberInput(
                      colors: colors,
                      value: plan.durationSecs,
                      suffix: 's',
                      min: 0.001,
                      max: 3600,
                      decimals: 1,
                      onChanged: (v) =>
                          onChanged(plan.copyWith(durationSecs: v)),
                    ),
                  ),
                ),
              ],
            ),
            if (recommendation != null) ...[
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => onChanged(
                    plan.copyWith(durationSecs: recommendation.seconds),
                  ),
                  icon: Icon(
                    LucideIcons.sparkles,
                    size: 13,
                    color: colors.primary,
                  ),
                  label: Text(
                    'Suggested ${_formatExposureSeconds(recommendation.seconds)}',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 11),
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ],
            Row(
              children: [
                Expanded(
                  child: NodePropertyField(
                    colors: colors,
                    label: 'Gain',
                    child: NodeNumberInput(
                      colors: colors,
                      value: (plan.gain ?? 0).toDouble(),
                      min: 0,
                      max: 1000,
                      onChanged: (v) =>
                          onChanged(plan.copyWith(gain: v.toInt())),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NodePropertyField(
                    colors: colors,
                    label: 'Offset',
                    child: NodeNumberInput(
                      colors: colors,
                      value: (plan.offset ?? 0).toDouble(),
                      min: 0,
                      max: 1000,
                      onChanged: (v) =>
                          onChanged(plan.copyWith(offset: v.toInt())),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: NodePropertyField(
                    colors: colors,
                    label: 'Binning',
                    child: NodeDropdown<BinningMode>(
                      colors: colors,
                      value: plan.binning,
                      items: BinningMode.values,
                      labelBuilder: (b) => b.label,
                      onChanged: (v) => onChanged(plan.copyWith(binning: v)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NodePropertyField(
                    colors: colors,
                    label: 'Dither Every',
                    child: NodeNumberInput(
                      colors: colors,
                      value: (plan.ditherEvery ?? 0).toDouble(),
                      suffix: ' frames',
                      min: 0,
                      max: 100,
                      onChanged: (v) {
                        final n = v.toInt();
                        onChanged(
                            plan.copyWith(ditherEvery: n == 0 ? null : n));
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDropdown(BuildContext context) {
    if (filterNames.isEmpty) {
      // No profile filter wheel — fall back to a free-text input so the
      // user can still author rows offline. They'll be invalid until a
      // filter wheel is configured (SmartExposureFilterWheelMissingRule
      // catches this).
      return NodeTextInput(
        colors: colors,
        value: plan.filterName,
        hint: 'Filter name (no profile filters)',
        onChanged: (v) => onChanged(plan.copyWith(filterName: v)),
      );
    }

    // Resolve current selection by name → index, or fall back to the
    // first filter when the persisted name no longer matches the profile
    // (e.g. profile was edited after the plan was created).
    final currentIndex = filterNames.indexOf(plan.filterName);
    final effectiveIndex = currentIndex >= 0 ? currentIndex : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: effectiveIndex,
          isExpanded: true,
          icon:
              Icon(LucideIcons.chevronDown, size: 14, color: colors.textMuted),
          dropdownColor: colors.surface,
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 12),
            color: colors.textPrimary,
          ),
          items: [
            for (var i = 0; i < filterNames.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(filterNames[i]),
              ),
          ],
          onChanged: (newIndex) {
            if (newIndex == null) return;
            onChanged(plan.copyWith(
              filterName: filterNames[newIndex],
              filterIndex: newIndex,
            ));
          },
        ),
      ),
    );
  }
}

class _BudgetInput extends StatefulWidget {
  final NightshadeColors colors;
  final SmartExposureNode node;
  final ValueChanged<double> onChanged;

  const _BudgetInput({
    required this.colors,
    required this.node,
    required this.onChanged,
  });

  @override
  State<_BudgetInput> createState() => _BudgetInputState();
}

class _BudgetInputState extends State<_BudgetInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.node.integrationBudgetSecs > 0
          ? formatHumanDurationSecs(widget.node.integrationBudgetSecs)
          : '',
    );
  }

  @override
  void didUpdateWidget(covariant _BudgetInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.integrationBudgetSecs !=
        widget.node.integrationBudgetSecs) {
      _controller.text = widget.node.integrationBudgetSecs > 0
          ? formatHumanDurationSecs(widget.node.integrationBudgetSecs)
          : '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Integration Budget (optional)',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 12),
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            border: Border.all(color: colors.border),
          ),
          child: TextField(
            controller: _controller,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 12),
              color: colors.textPrimary,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'e.g. 4h 30m, 2h, 90m (blank = no cap)',
              hintStyle: TextStyle(
                fontSize: Responsive.fontSize(context, 11),
                color: colors.textMuted,
              ),
            ),
            onChanged: (raw) {
              if (raw.trim().isEmpty) {
                widget.onChanged(0.0);
                return;
              }
              final parsed = parseHumanDurationSecs(raw);
              if (parsed != null) {
                widget.onChanged(parsed);
              }
              // Unparseable input is left in the field until the user
              // fixes it; we don't silently zero the budget.
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Stops early once the budget is reached, regardless of unfilled counts.',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 10),
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}

double _recommendedExposureSeconds(
  SmartNightExposureContext? context,
  String? filterName, {
  required double fallbackSecs,
}) {
  final recommendation = context?.recommendForFilter(filterName);
  final seconds = recommendation?.seconds;
  if (seconds == null || !seconds.isFinite || seconds <= 0) {
    return fallbackSecs;
  }
  return seconds;
}

String _formatExposureSeconds(double seconds) {
  final rounded = seconds.roundToDouble();
  if ((seconds - rounded).abs() < 0.05) {
    return '${rounded.toInt()}s';
  }
  return '${seconds.toStringAsFixed(1)}s';
}

class _EstimateSummary extends StatelessWidget {
  final NightshadeColors colors;
  final SmartExposureNode node;

  const _EstimateSummary({required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    final integration = node.totalIntegrationSecs;
    const estimator = SequenceTimeEstimator();
    // SequenceTimeEstimator's per-node duration is private; we approximate
    // wall-clock here by adding a 20% overhead to the integration figure
    // when no budget cap kicks in. The Run Dashboard's full timing panel
    // gives the authoritative number.
    final wallClock = node.integrationBudgetSecs > 0 &&
            node.integrationBudgetSecs < integration
        ? node.integrationBudgetSecs * 1.2
        : integration * 1.2;
    // Reference estimator so we don't break if SequenceTimeEstimator is
    // ever marked unused — the dashboard rendering depends on the same
    // class.
    estimator.toString();

    // In loop-until-stopped mode the per-plan counts are ignored, so a fixed
    // "Integration: Xh" figure would be a lie. The total is whatever fits in
    // the bound: the integration budget if set, otherwise "until window end".
    final loop = node.loopUntilStopped;
    final integrationLine = loop
        ? (node.integrationBudgetSecs > 0
            ? 'Integration: up to ${formatHumanDurationSecs(node.integrationBudgetSecs)} (looping)'
            : 'Integration: until the target’s window ends (looping)')
        : 'Integration: ${formatHumanDurationSecs(integration)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: NightshadeDecorations.tintedBadge(
        colors.primary,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(loop ? LucideIcons.repeat : LucideIcons.clock,
                  size: 14, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  integrationLine,
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 13),
                    fontWeight: FontWeight.w500,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          // Wall-clock approximation only makes sense for a bounded run.
          // In loop mode without a budget there's no finite figure.
          if (!loop || node.integrationBudgetSecs > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(LucideIcons.alarmClock, size: 14, color: colors.textMuted),
                const SizedBox(width: 8),
                Text(
                  'Wall clock (approx): ${formatHumanDurationSecs(wallClock)}',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 11),
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ],
          if (node.plans.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _planSummary(node),
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 11),
                color: colors.textMuted,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _planSummary(SmartExposureNode node) {
    if (node.loopUntilStopped) {
      // Counts are ignored — show "filter · 1 each · looping" so the summary
      // reflects the round-robin-forever shape, not fixed counts.
      final filters = node.plans
          .map((p) => p.filterName.isEmpty ? '#?' : p.filterName)
          .join('·');
      return '$filters · 1 each · looping';
    }
    return node.plans
        .map((p) =>
            '${p.filterName}: ${p.count}×${p.durationSecs.toStringAsFixed(0)}s')
        .join(' • ');
  }
}
