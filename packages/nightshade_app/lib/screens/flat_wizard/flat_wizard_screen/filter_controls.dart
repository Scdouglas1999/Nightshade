part of '../flat_wizard_screen.dart';

// Shared widgets

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
    final state = ref.watch(flatWizardProvider);
    final notifier = ref.read(flatWizardProvider.notifier);
    final filters = state.filterSettings;

    // No filters loaded (no wheel / not yet seeded): keep the read-only card so
    // the section is not an empty control.
    if (filters.isEmpty) {
      return NightshadeCard(
        variant: CardVariant.standard,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(LucideIcons.filter, size: 18, color: colors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
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

    final selectedIndex = state.currentFilterIndex >= 0 &&
            state.currentFilterIndex < filters.length
        ? state.currentFilterIndex
        : 0;

    return Row(
      children: [
        Icon(LucideIcons.filter, size: 18, color: colors.textSecondary),
        const SizedBox(width: 12),
        // A REAL selection over the loaded filters. Indices are the item values
        // (labelled by filter name) so duplicate filter names never collide.
        // Disabled while a run holds the busy latch — the run captured its
        // target filter at start — mirroring _FilterChecklist's null-onChanged
        // disable.
        Expanded(
          child: NightshadeDropdown(
            isExpanded: true,
            isDense: true,
            value: selectedIndex.toString(),
            items: [for (var i = 0; i < filters.length; i++) i.toString()],
            itemLabels: [for (final f in filters) f.filterName],
            onChanged: state.isCapturing
                ? null
                : (v) {
                    if (v != null) notifier.selectQuickFilter(int.parse(v));
                  },
          ),
        ),
      ],
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
          style: TextStyle(
              color: colors.textMuted,
              fontSize: NightshadeTypography.fontSize13),
        ),
      );
    }

    // While a capture run is active the filter set must not change (the run
    // captured its filter list with stable indices at start), so the toggles
    // are visibly disabled — not just silently ignored by the notifier guard.
    final interactable = !state.isCapturing;

    return NightshadeCard(
      variant: CardVariant.standard,
      borderRadius: NightshadeTokens.radiusInline8,
      child: Column(
        children: [
          for (int i = 0; i < state.filterSettings.length; i++)
            _FilterChecklistItem(
              filter: state.filterSettings[i],
              isLast: i == state.filterSettings.length - 1,
              onToggle: interactable
                  ? (enabled) => notifier.toggleFilter(i, enabled)
                  : null,
            ),
        ],
      ),
    );
  }
}

class _FilterChecklistItem extends StatelessWidget {
  final FlatFilterSettings filter;
  final bool isLast;

  /// Null while a capture run is active — disables the checkbox so the filter
  /// set cannot change mid-run.
  final ValueChanged<bool>? onToggle;

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
            onChanged: onToggle == null ? null : (v) => onToggle!(v ?? false),
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
