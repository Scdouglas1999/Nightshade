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
  int _operationGeneration = 0;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (previous != null && !identical(previous, next)) {
          _retireOperation();
        }
      },
    );
  }

  @override
  void didUpdateWidget(IntegrationGoalsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetId != widget.targetId) _retireOperation();
  }

  @override
  void dispose() {
    _operationGeneration++;
    _backendSubscription?.close();
    super.dispose();
  }

  void _retireOperation() {
    _operationGeneration++;
    if (mounted && _busy) setState(() => _busy = false);
  }

  Future<bool> _addGoal({
    required String filter,
    required double exposureSeconds,
    required int frameCount,
    required int priority,
    required NightshadeBackend authority,
    required IntegrationGoalService service,
  }) async {
    if (_busy) return false;
    if (!_isCurrentAuthority(authority)) {
      _showAuthorityChanged();
      return false;
    }
    final targetId = widget.targetId;
    final operationGeneration = ++_operationGeneration;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = NightshadeColors.of(context).error;
    setState(() => _busy = true);
    try {
      await service.upsert(IntegrationGoal(
        targetId: targetId,
        filter: filter,
        exposureSeconds: exposureSeconds,
        frameCount: frameCount,
        priority: priority,
        createdAt: DateTime.now().toUtc(),
      ));
      if (!_isCurrentOperation(
        authority,
        targetId,
        operationGeneration,
      )) {
        return false;
      }
      ref.invalidate(integrationGoalProgressProvider(targetId));
      ref.invalidate(allIntegrationGoalsProvider);
      return true;
    } catch (e) {
      if (_isCurrentOperation(authority, targetId, operationGeneration)) {
        _showGoalErrorOn(messenger, errorColor, 'Failed to add goal: $e');
      }
      return false;
    } finally {
      if (_isCurrentOperation(authority, targetId, operationGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _updateGoal(IntegrationGoal goal,
      {required int frameCount,
      required int priority,
      required NightshadeBackend authority,
      required IntegrationGoalService service}) async {
    if (_busy) return;
    if (goal.id == null) {
      throw StateError('Cannot update an unsaved integration goal');
    }
    if (!_isCurrentAuthority(authority)) {
      _showAuthorityChanged();
      return;
    }
    final targetId = widget.targetId;
    final operationGeneration = ++_operationGeneration;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = NightshadeColors.of(context).error;
    setState(() => _busy = true);
    try {
      await service.upsert(goal.copyWith(
        frameCount: frameCount,
        priority: priority,
      ));
      if (!_isCurrentOperation(
        authority,
        targetId,
        operationGeneration,
      )) {
        return;
      }
      ref.invalidate(integrationGoalProgressProvider(targetId));
      ref.invalidate(allIntegrationGoalsProvider);
    } catch (e) {
      if (_isCurrentOperation(authority, targetId, operationGeneration)) {
        _showGoalErrorOn(messenger, errorColor, 'Failed to update goal: $e');
      }
    } finally {
      if (_isCurrentOperation(authority, targetId, operationGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteGoal(
    IntegrationGoal goal,
    NightshadeBackend authority,
    IntegrationGoalService service,
  ) async {
    if (_busy) return;
    if (goal.id == null) return;
    if (!_isCurrentAuthority(authority)) {
      _showAuthorityChanged();
      return;
    }
    final targetId = widget.targetId;
    final operationGeneration = ++_operationGeneration;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = NightshadeColors.of(context).error;
    setState(() => _busy = true);
    try {
      await service.delete(goal.id!);
      if (!_isCurrentOperation(
        authority,
        targetId,
        operationGeneration,
      )) {
        return;
      }
      ref.invalidate(integrationGoalProgressProvider(targetId));
      ref.invalidate(allIntegrationGoalsProvider);
    } catch (e) {
      if (_isCurrentOperation(authority, targetId, operationGeneration)) {
        _showGoalErrorOn(messenger, errorColor, 'Failed to delete goal: $e');
      }
    } finally {
      if (_isCurrentOperation(authority, targetId, operationGeneration)) {
        setState(() => _busy = false);
      }
    }
  }

  bool _isCurrentAuthority(NightshadeBackend authority) =>
      mounted && identical(ref.read(backendProvider), authority);

  bool _isCurrentOperation(
    NightshadeBackend authority,
    int targetId,
    int operationGeneration,
  ) =>
      operationGeneration == _operationGeneration &&
      widget.targetId == targetId &&
      _isCurrentAuthority(authority);

  void _showAuthorityChanged() {
    if (!mounted) return;
    _showGoalError(
      context,
      'The imaging host changed. Reopen the integration-goal editor.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final progressAsync =
        ref.watch(integrationGoalProgressProvider(widget.targetId));
    final exposureContext =
        ref.watch(smartNightExposureContextProvider).valueOrNull;
    final authority = ref.watch(backendProvider);
    final service = ref.watch(integrationGoalServiceProvider);

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
              style: NightshadeTypography.h5.copyWith(
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
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary),
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
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize12, color: colors.error),
          ),
          data: (progress) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (progress.isEmpty)
                NightshadeCard(
                  padding: NightshadeTokens.paddingMd,
                  child: Text(
                    'No integration goals yet. Add filters below to tell the scheduler what to image.',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        color: colors.textMuted),
                  ),
                ),
              for (final p in progress)
                _GoalRow(
                  progress: p,
                  onUpdate: (count, priority) => _updateGoal(p.goal,
                      frameCount: count,
                      priority: priority,
                      authority: authority,
                      service: service),
                  onDelete: () => _deleteGoal(p.goal, authority, service),
                  busy: _busy,
                ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              _AddGoalRow(
                availableFilters: widget.availableFilters,
                existingFilters: progress.map((p) => p.goal.filter).toSet(),
                exposureContext: exposureContext,
                onAdd: ({
                  required filter,
                  required exposureSeconds,
                  required frameCount,
                  required priority,
                }) =>
                    _addGoal(
                  filter: filter,
                  exposureSeconds: exposureSeconds,
                  frameCount: frameCount,
                  priority: priority,
                  authority: authority,
                  service: service,
                ),
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
    final colors = NightshadeColors.of(context);
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
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
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
                  fontSize: NightshadeTypography.fontSize14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                '${p.goal.exposureSeconds.toStringAsFixed(0)}s',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            SizedBox(
              width: 96,
              child: TextField(
                controller: _countCtl,
                enabled: !widget.busy,
                keyboardType: TextInputType.number,
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize13,
                    color: colors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Frames',
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted),
                ),
                onSubmitted: (v) {
                  final parsed = int.tryParse(v.trim());
                  if (parsed == null || parsed < 1) {
                    _countCtl.text = p.goal.frameCount.toString();
                    _showGoalError(
                        context, 'Frame count must be a positive integer.');
                    return;
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
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize13,
                    color: colors.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Prio',
                  border: const OutlineInputBorder(),
                  labelStyle: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted),
                ),
                onSubmitted: (v) {
                  final parsed = int.tryParse(v.trim());
                  if (parsed == null) {
                    _priorityCtl.text = p.goal.priority.toString();
                    _showGoalError(context, 'Priority must be an integer.');
                    return;
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
                    style: NightshadeTypography.h6.copyWith(
                      color: p.isComplete ? colors.success : colors.textPrimary,
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
  final SmartNightExposureContext? exposureContext;
  final Future<bool> Function({
    required String filter,
    required double exposureSeconds,
    required int frameCount,
    required int priority,
  }) onAdd;
  final bool busy;

  const _AddGoalRow({
    required this.availableFilters,
    required this.existingFilters,
    required this.exposureContext,
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

  void _selectFilter(String? filter) {
    setState(() {
      _selectedFilter = filter;
      final seconds =
          widget.exposureContext?.recommendForFilter(filter).seconds;
      if (seconds != null && seconds.isFinite && seconds > 0) {
        _exposureCtl.text = _formatExposureSeconds(seconds);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final remaining = widget.availableFilters
        .where((f) => !widget.existingFilters
            .any((existing) => existing.toLowerCase() == f.toLowerCase()))
        .toList();

    if (widget.availableFilters.isEmpty) {
      return Text(
        'Equipment profile has no filters configured; configure a filter wheel first.',
        style: TextStyle(
            fontSize: NightshadeTypography.fontSize12, color: colors.warning),
      );
    }
    if (remaining.isEmpty) {
      return Text(
        'All filters from the active equipment profile already have goals.',
        style: TextStyle(
            fontSize: NightshadeTypography.fontSize12, color: colors.textMuted),
      );
    }

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
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
              onChanged: widget.busy ? null : _selectFilter,
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
            onPressed: widget.busy || !_canAdd ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final exposure = double.tryParse(_exposureCtl.text.trim());
    final frames = int.tryParse(_frameCtl.text.trim());
    final priority = int.tryParse(_priorityCtl.text.trim());
    if (exposure == null || exposure <= 0) {
      _showGoalError(context, 'Exposure seconds must be a positive number.');
      return;
    }
    if (frames == null || frames < 1) {
      _showGoalError(context, 'Frame count must be at least 1.');
      return;
    }
    if (priority == null) {
      _showGoalError(context, 'Priority must be an integer.');
      return;
    }
    final selectedFilter = _selectedFilter;
    if (selectedFilter == null) return;
    final added = await widget.onAdd(
      filter: selectedFilter,
      exposureSeconds: exposure,
      frameCount: frames,
      priority: priority,
    );
    if (mounted && added) _selectFilter(null);
  }
}

void _showGoalError(BuildContext context, String message) {
  _showGoalErrorOn(
    ScaffoldMessenger.of(context),
    NightshadeColors.of(context).error,
    message,
  );
}

void _showGoalErrorOn(
  ScaffoldMessengerState messenger,
  Color errorColor,
  String message,
) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: errorColor,
      duration: const Duration(seconds: 4),
    ),
  );
}

String _formatExposureSeconds(double seconds) {
  final rounded = seconds.roundToDouble();
  if ((seconds - rounded).abs() < 0.05) {
    return rounded.toInt().toString();
  }
  return seconds.toStringAsFixed(1);
}
