part of '../focus_model_curve_card.dart';

class _ActionRow extends ConsumerWidget {
  final String profileId;
  final FocuserState focuserState;
  final NightshadeColors colors;

  const _ActionRow({
    required this.profileId,
    required this.focuserState,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        NightshadeButton(
          label: 'Add point',
          icon: LucideIcons.plus,
          size: ButtonSize.small,
          variant: ButtonVariant.outline,
          onPressed: () => _showAddPointDialog(context, ref),
        ),
        const Spacer(),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: Icon(LucideIcons.moreHorizontal, color: colors.textSecondary),
          onSelected: (value) async {
            final focusService = ref.read(focusModelServiceProvider);
            switch (value) {
              case 'export':
                final json = focusService.exportData(profileId);
                if (context.mounted) {
                  await showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Export focus data'),
                      content: SingleChildScrollView(
                        child: SelectableText(json),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }
                break;
              case 'import':
                final controller = TextEditingController();
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Import focus data'),
                    content: TextField(
                      controller: controller,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        hintText: 'Paste JSON exported from another device',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(context).pop(controller.text),
                        child: const Text('Import'),
                      ),
                    ],
                  ),
                );
                if (result != null && result.trim().isNotEmpty) {
                  try {
                    await focusService.importData(profileId, result);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Focus data imported')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Import failed: $e')),
                      );
                    }
                  }
                }
                break;
              case 'clear':
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Clear focus model?'),
                    content: const Text(
                      'This deletes all collected focus data points and the '
                      'fitted model. This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await focusService.clearProfileData(profileId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Focus model cleared')),
                    );
                  }
                }
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'export', child: Text('Export JSON')),
            PopupMenuItem(value: 'import', child: Text('Import JSON')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'clear', child: Text('Clear model')),
          ],
        ),
      ],
    );
  }

  Future<void> _showAddPointDialog(BuildContext context, WidgetRef ref) async {
    final focuserState = ref.read(focuserStateProvider);
    final filterWheel = ref.read(filterWheelStateProvider);

    final positionCtrl = TextEditingController(
      text: focuserState.position?.toString() ?? '',
    );
    final hfrCtrl = TextEditingController();
    final tempCtrl = TextEditingController(
      text: focuserState.temperature?.toStringAsFixed(2) ?? '',
    );
    String? selectedFilter = filterWheel.currentFilterName;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add focus data point'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: positionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Focuser position (steps)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: hfrCtrl,
                  decoration: const InputDecoration(labelText: 'HFR'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: tempCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Temperature (°C)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                ),
                if (filterWheel.filterNames.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  StatefulBuilder(builder: (ctx, setState) {
                    return DropdownButtonFormField<String>(
                      initialValue: selectedFilter,
                      decoration: const InputDecoration(labelText: 'Filter'),
                      items: filterWheel.filterNames
                          .map(
                              (n) => DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: (v) => setState(() => selectedFilter = v),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (saved != true) return;
    final position = int.tryParse(positionCtrl.text.trim());
    final hfr = double.tryParse(hfrCtrl.text.trim());
    final temp = double.tryParse(tempCtrl.text.trim());
    if (position == null || hfr == null || temp == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Position, HFR and temperature are required'),
          ),
        );
      }
      return;
    }
    try {
      await ref.read(focusModelServiceProvider).addDataPoint(
            profileId: profileId,
            temperatureCelsius: temp,
            focusPosition: position,
            hfr: hfr,
            filterName: selectedFilter,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Focus point added')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add point: $e')),
        );
      }
    }
  }
}

/// Last predictive-AF consultation: decision band, predicted vs actual
/// position, and confidence. The model used to train and predict entirely
/// silently — this row is the operator's only window into whether the
/// per-filter focus model trusts itself yet.
class _PredictiveAfRow extends ConsumerWidget {
  const _PredictiveAfRow({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(lastPredictiveAfStatusProvider);
    if (status == null) return const SizedBox.shrink();

    final predicted = status.decision.targetPosition;
    final confidence = status.decision.confidence;
    final error = status.predictionErrorSteps;

    final parts = <String>[
      status.filterName,
      status.decisionLabel,
      if (predicted != null) 'predicted $predicted',
      if (confidence != null) 'R² ${confidence.toStringAsFixed(2)}',
      if (status.actualPosition != null) 'actual ${status.actualPosition}',
      if (error != null) 'Δ ${error >= 0 ? '+' : ''}$error steps',
    ];

    final tone = switch (status.decision) {
      ApplyDirect() => colors.success,
      ApplyDampened() => colors.primary,
      ForceAutofocus() => colors.warning,
      InsufficientData() => colors.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(LucideIcons.brainCircuit, size: 13, color: tone),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Predictive AF: ${parts.join(' · ')}',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
