import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Per-target integration-goals editor.
///
/// One row per existing goal (filter, exposure seconds, frame count,
/// priority, captured-count read-only) plus an "Add filter" footer that
/// inserts a new goal. Persists immediately through
/// [IntegrationGoalService] (no Save button); the engine's
/// candidatesUpdated trigger is fired by the calling screen so the
/// scheduler re-evaluates with fresh integration targets.
class IntegrationGoalsEditor extends ConsumerStatefulWidget {
  final int targetId;
  final String targetName;
  final List<String> availableFilters;

  const IntegrationGoalsEditor({
    super.key,
    required this.targetId,
    required this.targetName,
    required this.availableFilters,
  });

  @override
  ConsumerState<IntegrationGoalsEditor> createState() =>
      _IntegrationGoalsEditorState();
}

class _IntegrationGoalsEditorState
    extends ConsumerState<IntegrationGoalsEditor> {
  bool _busy = false;

  Future<void> _addGoal({
    required String filter,
    required double exposureSeconds,
    required int frameCount,
    required int priority,
  }) async {
    setState(() => _busy = true);
    try {
      final svc = ref.read(integrationGoalServiceProvider);
      await svc.upsert(IntegrationGoal(
        targetId: widget.targetId,
        filter: filter,
        exposureSeconds: exposureSeconds,
        frameCount: frameCount,
        priority: priority,
        createdAt: DateTime.now().toUtc(),
      ));
      ref.invalidate(integrationGoalProgressProvider(widget.targetId));
      ref.invalidate(allIntegrationGoalsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateGoal(IntegrationGoal goal,
      {required int frameCount, required int priority}) async {
    if (goal.id == null) {
      throw StateError('Cannot update an unsaved integration goal');
    }
    setState(() => _busy = true);
    try {
      final svc = ref.read(integrationGoalServiceProvider);
      await svc.upsert(goal.copyWith(
        frameCount: frameCount,
        priority: priority,
      ));
      ref.invalidate(integrationGoalProgressProvider(widget.targetId));
      ref.invalidate(allIntegrationGoalsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteGoal(IntegrationGoal goal) async {
    if (goal.id == null) return;
    setState(() => _busy = true);
    try {
      final svc = ref.read(integrationGoalServiceProvider);
      await svc.delete(goal.id!);
      ref.invalidate(integrationGoalProgressProvider(widget.targetId));
      ref.invalidate(allIntegrationGoalsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final progressAsync =
        ref.watch(integrationGoalProgressProvider(widget.targetId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.target,
                size: NightshadeTokens.iconSm, color: colors.primary),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'Integration goals',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            if (_busy) ...[
              const SizedBox(width: NightshadeTokens.spaceMd),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Text(
          'How many frames in each filter does ${widget.targetName} still need?',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        progressAsync.when(
          loading: () => Padding(
            padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
          ),
          error: (e, _) => Text(
            'Failed to load goals: $e',
            style: TextStyle(fontSize: 12, color: colors.error),
          ),
          data: (progress) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (progress.isEmpty)
                Container(
                  padding: NightshadeTokens.paddingMd,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    'No integration goals yet. Add filters below to tell the scheduler what to image.',
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ),
              for (final p in progress)
                _GoalRow(
                  progress: p,
                  onUpdate: (count, priority) => _updateGoal(p.goal,
                      frameCount: count, priority: priority),
                  onDelete: () => _deleteGoal(p.goal),
                  busy: _busy,
                ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              _AddGoalRow(
                availableFilters: widget.availableFilters,
                existingFilters: progress.map((p) => p.goal.filter).toSet(),
                onAdd: _addGoal,
                busy: _busy,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoalRow extends StatefulWidget {
  final IntegrationGoalProgress progress;
  final Future<void> Function(int frameCount, int priority) onUpdate;
  final Future<void> Function() onDelete;
  final bool busy;

  const _GoalRow({
    required this.progress,
    required this.onUpdate,
    required this.onDelete,
    required this.busy,
  });

  @override
  State<_GoalRow> createState() => _GoalRowState();
}

class _GoalRowState extends State<_GoalRow> {
  late final TextEditingController _countCtl;
  late final TextEditingController _priorityCtl;

  @override
  void initState() {
    super.initState();
    _countCtl =
        TextEditingController(text: widget.progress.goal.frameCount.toString());
    _priorityCtl =
        TextEditingController(text: widget.progress.goal.priority.toString());
  }

  @override
  void didUpdateWidget(_GoalRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh fields when the underlying goal mutates externally.
    if (oldWidget.progress.goal != widget.progress.goal) {
      _countCtl.text = widget.progress.goal.frameCount.toString();
      _priorityCtl.text = widget.progress.goal.priority.toString();
    }
  }

  @override
  void dispose() {
    _countCtl.dispose();
    _priorityCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final p = widget.progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: p.isComplete
              ? colors.success.withValues(alpha: 0.08)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: p.isComplete
                ? colors.success.withValues(alpha: 0.4)
                : colors.border,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                p.goal.filter,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                '${p.goal.exposureSeconds.toStringAsFixed(0)}s',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _countCtl,
                enabled: !widget.busy,
                keyboardType: TextInputType.number,
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Frames',
                  border: const OutlineInputBorder(),
                  labelStyle:
                      TextStyle(fontSize: 11, color: colors.textMuted),
                ),
                onSubmitted: (v) {
                  final parsed = int.tryParse(v.trim());
                  if (parsed == null || parsed < 1) {
                    throw FormatException(
                        'Frame count must be a positive integer; got "$v"');
                  }
                  widget.onUpdate(parsed, p.goal.priority);
                },
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            SizedBox(
              width: 84,
              child: TextField(
                controller: _priorityCtl,
                enabled: !widget.busy,
                keyboardType: TextInputType.number,
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Prio',
                  border: const OutlineInputBorder(),
                  labelStyle:
                      TextStyle(fontSize: 11, color: colors.textMuted),
                ),
                onSubmitted: (v) {
                  final parsed = int.tryParse(v.trim());
                  if (parsed == null) {
                    throw FormatException(
                        'Priority must be an integer; got "$v"');
                  }
                  widget.onUpdate(p.goal.frameCount, parsed);
                },
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${p.capturedCount} / ${p.goal.frameCount} captured',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          p.isComplete ? colors.success : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  LinearProgressIndicator(
                    value: p.goal.frameCount > 0
                        ? (p.capturedCount / p.goal.frameCount).clamp(0.0, 1.0)
                        : 0.0,
                    minHeight: 4,
                    backgroundColor: colors.surfaceHover,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      p.isComplete ? colors.success : colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            IconButton(
              tooltip: 'Delete goal',
              onPressed: widget.busy ? null : () => widget.onDelete(),
              icon: Icon(LucideIcons.trash2,
                  size: NightshadeTokens.iconSm, color: colors.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddGoalRow extends StatefulWidget {
  final List<String> availableFilters;
  final Set<String> existingFilters;
  final Future<void> Function({
    required String filter,
    required double exposureSeconds,
    required int frameCount,
    required int priority,
  }) onAdd;
  final bool busy;

  const _AddGoalRow({
    required this.availableFilters,
    required this.existingFilters,
    required this.onAdd,
    required this.busy,
  });

  @override
  State<_AddGoalRow> createState() => _AddGoalRowState();
}

class _AddGoalRowState extends State<_AddGoalRow> {
  String? _selectedFilter;
  final _exposureCtl = TextEditingController(text: '180');
  final _frameCtl = TextEditingController(text: '20');
  final _priorityCtl = TextEditingController(text: '5');

  @override
  void dispose() {
    _exposureCtl.dispose();
    _frameCtl.dispose();
    _priorityCtl.dispose();
    super.dispose();
  }

  bool get _canAdd =>
      _selectedFilter != null &&
      !widget.existingFilters
          .any((f) => f.toLowerCase() == _selectedFilter!.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final remaining = widget.availableFilters
        .where((f) => !widget.existingFilters
            .any((existing) => existing.toLowerCase() == f.toLowerCase()))
        .toList();

    if (widget.availableFilters.isEmpty) {
      return Text(
        'Equipment profile has no filters configured; configure a filter wheel first.',
        style: TextStyle(fontSize: 12, color: colors.warning),
      );
    }
    if (remaining.isEmpty) {
      return Text(
        'All filters from the active equipment profile already have goals.',
        style: TextStyle(fontSize: 12, color: colors.textMuted),
      );
    }

    return Container(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedFilter,
              hint: const Text('Filter'),
              items: [
                for (final f in remaining)
                  DropdownMenuItem(value: f, child: Text(f)),
              ],
              onChanged: widget.busy
                  ? null
                  : (v) => setState(() => _selectedFilter = v),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _exposureCtl,
              enabled: !widget.busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Exposure (s)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _frameCtl,
              enabled: !widget.busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Frames',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _priorityCtl,
              enabled: !widget.busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Prio',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const Spacer(),
          NightshadeButton(
            label: 'Add',
            icon: LucideIcons.plus,
            size: ButtonSize.small,
            onPressed: widget.busy || !_canAdd
                ? null
                : () {
                    final exposure = double.parse(_exposureCtl.text.trim());
                    final frames = int.parse(_frameCtl.text.trim());
                    final priority = int.parse(_priorityCtl.text.trim());
                    if (exposure <= 0) {
                      throw FormatException(
                          'Exposure seconds must be positive; got $exposure');
                    }
                    if (frames < 1) {
                      throw FormatException(
                          'Frame count must be at least 1; got $frames');
                    }
                    widget.onAdd(
                      filter: _selectedFilter!,
                      exposureSeconds: exposure,
                      frameCount: frames,
                      priority: priority,
                    );
                    setState(() => _selectedFilter = null);
                  },
          ),
        ],
      ),
    );
  }
}
