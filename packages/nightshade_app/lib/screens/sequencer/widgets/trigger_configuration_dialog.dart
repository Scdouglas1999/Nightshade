import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

enum TriggerConditionType { guidingRms, hfr, drift }
enum TriggerActionType { pauseAndRecalibrate, autofocus, abort }

class ExposureTriggerConfig {
  final TriggerConditionType condition;
  final double threshold;
  final TriggerActionType action;
  final double debounceSecs;

  ExposureTriggerConfig({
    required this.condition,
    required this.threshold,
    required this.action,
    this.debounceSecs = 10.0,
  });

  String get conditionLabel {
    switch (condition) {
      case TriggerConditionType.guidingRms:
        return 'Guiding RMS > $threshold"';
      case TriggerConditionType.hfr:
        return 'HFR > $threshold px';
      case TriggerConditionType.drift:
        return 'Drift > $threshold px';
    }
  }

  String get actionLabel {
    switch (action) {
      case TriggerActionType.pauseAndRecalibrate:
        return 'Pause & Recalibrate';
      case TriggerActionType.autofocus:
        return 'Run Autofocus';
      case TriggerActionType.abort:
        return 'Abort Sequence';
    }
  }

  IconData get conditionIcon {
    switch (condition) {
      case TriggerConditionType.guidingRms:
        return Icons.track_changes;
      case TriggerConditionType.hfr:
        return Icons.center_focus_weak;
      case TriggerConditionType.drift:
        return Icons.moving;
    }
  }

  Color conditionColor(NightshadeColors colors) {
    switch (condition) {
      case TriggerConditionType.guidingRms:
        return colors.warning;
      case TriggerConditionType.hfr:
        return colors.info;
      case TriggerConditionType.drift:
        return colors.error;
    }
  }
}

class TriggerConfigurationDialog extends ConsumerStatefulWidget {
  final List<ExposureTriggerConfig> initialTriggers;

  const TriggerConfigurationDialog({
    this.initialTriggers = const [],
    super.key,
  });

  @override
  ConsumerState<TriggerConfigurationDialog> createState() => 
      _TriggerConfigurationDialogState();
}

class _TriggerConfigurationDialogState 
    extends ConsumerState<TriggerConfigurationDialog> {
  late List<ExposureTriggerConfig> _triggers;

  @override
  void initState() {
    super.initState();
    _triggers = List.from(widget.initialTriggers);
  }

  void _addTrigger() {
    setState(() {
      _triggers.add(ExposureTriggerConfig(
        condition: TriggerConditionType.guidingRms,
        threshold: 2.0,
        action: TriggerActionType.pauseAndRecalibrate,
      ));
    });
  }

  void _removeTrigger(int index) {
    setState(() => _triggers.removeAt(index));
  }

  void _editTrigger(int index) {
    showDialog(
      context: context,
      builder: (context) => _TriggerEditDialog(
        trigger: _triggers[index],
        onSave: (trigger) {
          setState(() => _triggers[index] = trigger);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        height: 500,
        decoration: BoxDecoration(
          color: colors.background.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active, color: colors.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Exposure Triggers',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Triggers List
            Expanded(
              child: _triggers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_off,
                            size: 64,
                            color: colors.textSecondary.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No triggers configured',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a trigger to automatically respond to conditions',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: _triggers.length,
                      itemBuilder: (context, index) {
                        final trigger = _triggers[index];
                        return _buildTriggerCard(trigger, index, colors, theme);
                      },
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _addTrigger,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Trigger'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_triggers),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTriggerCard(
    ExposureTriggerConfig trigger,
    int index,
    NightshadeColors colors,
    ThemeData theme,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: trigger.conditionColor(colors).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            trigger.conditionIcon,
            color: trigger.conditionColor(colors),
          ),
        ),
        title: Text(trigger.conditionLabel),
        subtitle: Text(
          '→ ${trigger.actionLabel}',
          style: TextStyle(color: colors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editTrigger(index),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              color: colors.error,
              onPressed: () => _removeTrigger(index),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
}

class _TriggerEditDialog extends StatefulWidget {
  final ExposureTriggerConfig trigger;
  final ValueChanged<ExposureTriggerConfig> onSave;

  const _TriggerEditDialog({
    required this.trigger,
    required this.onSave,
  });

  @override
  State<_TriggerEditDialog> createState() => _TriggerEditDialogState();
}

class _TriggerEditDialogState extends State<_TriggerEditDialog> {
  late TriggerConditionType _condition;
  late double _threshold;
  late TriggerActionType _action;
  late double _debounce;

  @override
  void initState() {
    super.initState();
    _condition = widget.trigger.condition;
    _threshold = widget.trigger.threshold;
    _action = widget.trigger.action;
    _debounce = widget.trigger.debounceSecs;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>()!;

    return AlertDialog(
      title: const Text('Edit Trigger'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<TriggerConditionType>(
              initialValue: _condition,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: TriggerConditionType.values.map((c) {
                return DropdownMenuItem(
                  value: c,
                  child: Text(_conditionName(c)),
                );
              }).toList(),
              onChanged: (v) => setState(() => _condition = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _threshold.toString()),
              decoration: InputDecoration(
                labelText: 'Threshold',
                suffix: Text(_getThresholdUnit()),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                final parsed = double.tryParse(v);
                if (parsed != null) _threshold = parsed;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<TriggerActionType>(
              initialValue: _action,
              decoration: const InputDecoration(labelText: 'Action'),
              items: TriggerActionType.values.map((a) {
                return DropdownMenuItem(
                  value: a,
                  child: Text(_actionName(a)),
                );
              }).toList(),
              onChanged: (v) => setState(() => _action = v!),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(text: _debounce.toString()),
              decoration: const InputDecoration(
                labelText: 'Debounce Time',
                suffix: Text('seconds'),
                helperText: 'Wait time before triggering again',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (v) {
                final parsed = double.tryParse(v);
                if (parsed != null) _debounce = parsed;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onSave(ExposureTriggerConfig(
              condition: _condition,
              threshold: _threshold,
              action: _action,
              debounceSecs: _debounce,
            ));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _conditionName(TriggerConditionType c) {
    switch (c) {
      case TriggerConditionType.guidingRms:
        return 'Guiding RMS';
      case TriggerConditionType.hfr:
        return 'HFR';
      case TriggerConditionType.drift:
        return 'Drift';
    }
  }

  String _actionName(TriggerActionType a) {
    switch (a) {
      case TriggerActionType.pauseAndRecalibrate:
        return 'Pause & Recalibrate';
      case TriggerActionType.autofocus:
        return 'Run Autofocus';
      case TriggerActionType.abort:
        return 'Abort Sequence';
    }
  }

  String _getThresholdUnit() {
    switch (_condition) {
      case TriggerConditionType.guidingRms:
        return 'arcsec';
      case TriggerConditionType.hfr:
      case TriggerConditionType.drift:
        return 'pixels';
    }
  }
}
