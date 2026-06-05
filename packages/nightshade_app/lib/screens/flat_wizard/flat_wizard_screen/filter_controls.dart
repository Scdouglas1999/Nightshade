part of '../flat_wizard_screen.dart';

// --- Shared Widgets ---

class _SectionHeader extends StatelessWidget {
  final String title;
  final NightshadeColors colors;

  const _SectionHeader({required this.title, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: NightshadeTypography.h6.copyWith(color: colors.textSecondary),
    );
  }
}

class _FilterSelector extends ConsumerWidget {
  const _FilterSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final fwState = ref.watch(filterWheelStateProvider);
    final state = ref.watch(flatWizardProvider);

    final currentFilter = state.filterSettings.isNotEmpty &&
            state.currentFilterIndex < state.filterSettings.length
        ? state.filterSettings[state.currentFilterIndex]
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.filter, size: 18, color: colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              currentFilter?.filterName ??
                  fwState.currentFilterName ??
                  'No filter',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize14,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChecklist extends ConsumerWidget {
  const _FilterChecklist({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);

    if (state.filterSettings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        ),
        child: Text(
          'No filters available. Connect a filter wheel.',
          style: TextStyle(color: colors.textMuted, fontSize: NightshadeTypography.fontSize13),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < state.filterSettings.length; i++)
            _FilterChecklistItem(
              filter: state.filterSettings[i],
              isLast: i == state.filterSettings.length - 1,
              onToggle: (enabled) => notifier.toggleFilter(i, enabled),
            ),
        ],
      ),
    );
  }
}

class _FilterChecklistItem extends StatelessWidget {
  final FlatFilterSettings filter;
  final bool isLast;
  final ValueChanged<bool> onToggle;

  const _FilterChecklistItem({
    required this.filter,
    required this.isLast,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border:
            isLast ? null : Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: filter.enabled,
            onChanged: (v) => onToggle(v ?? false),
            activeColor: colors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filter.filterName,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize13,
                color: filter.enabled ? colors.textPrimary : colors.textMuted,
              ),
            ),
          ),
          if (filter.suggestedExposure != null)
            Text(
              '~${filter.suggestedExposure!.toStringAsFixed(1)}s',
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}
