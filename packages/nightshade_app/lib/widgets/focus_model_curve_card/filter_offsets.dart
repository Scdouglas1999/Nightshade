part of '../focus_model_curve_card.dart';

class _FilterOffsetsStrip extends ConsumerWidget {
  final String profileId;
  final NightshadeColors colors;

  const _FilterOffsetsStrip({
    required this.profileId,
    required this.colors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offsets = ref.watch(filterOffsetProvider);
    if (offsets.isLoading) {
      return SizedBox(
        height: 28,
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Text('Loading filter offsets…',
                style: TextStyle(fontSize: 11, color: colors.textMuted)),
          ],
        ),
      );
    }
    if (offsets.offsets.isEmpty) {
      return Text(
        'No filter offsets yet — collect autofocus data on multiple filters '
        'and pick a reference to populate.',
        style: TextStyle(fontSize: 11, color: colors.textMuted),
      );
    }
    final entries = offsets.offsets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final e = entries[i];
          final isReference = offsets.referenceFilter == e.key;
          return _FilterChip(
            label: e.key,
            offset: e.value,
            isReference: isReference,
            colors: colors,
            onTap: () => _editOffset(context, ref, e.key, e.value),
          );
        },
      ),
    );
  }

  Future<void> _editOffset(
    BuildContext context,
    WidgetRef ref,
    String filterName,
    int currentOffset,
  ) async {
    final controller = TextEditingController(text: currentOffset.toString());
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<NightshadeColors>()!;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Edit "$filterName" offset',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Offset (steps, relative to reference)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: NightshadeButton(
                      label: 'Cancel',
                      variant: ButtonVariant.outline,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NightshadeButton(
                      label: 'Set as reference',
                      variant: ButtonVariant.ghost,
                      onPressed: () => Navigator.of(ctx).pop(_kSetAsReference),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NightshadeButton(
                      label: 'Save',
                      onPressed: () {
                        final v = int.tryParse(controller.text.trim());
                        if (v == null) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Enter a whole-number offset'),
                            ),
                          );
                          return;
                        }
                        Navigator.of(ctx).pop(v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    if (result == _kSetAsReference) {
      await ref
          .read(filterOffsetProvider.notifier)
          .setReferenceFilter(filterName);
    } else {
      await ref
          .read(filterOffsetProvider.notifier)
          .setFilterOffset(filterName, result);
    }
  }
}

/// Sentinel value returned from the offset-editor sheet to indicate "make this
/// filter the reference"; chosen well outside the legal step range so a real
/// user offset can never collide with it. Using a sentinel keeps the sheet a
/// single bottom modal instead of an additional confirmation dialog.
const int _kSetAsReference = -0x7FFFFFFF;

class _FilterChip extends StatelessWidget {
  final String label;
  final int offset;
  final bool isReference;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.offset,
    required this.isReference,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colour = isReference ? colors.primary : colors.surfaceAlt;
    final textColour = isReference ? colors.background : colors.textPrimary;
    final sign = offset > 0 ? '+' : '';
    final valueText = isReference ? 'reference' : '$sign$offset steps';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colour,
          border: Border.all(
            color: isReference ? colors.primary : colors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColour,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 11,
                color: isReference
                    ? colors.background.withValues(alpha: 0.8)
                    : colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Module-level helper used by `FocusModelCurveCard.onRunAutofocus` to fire
/// the autofocus job in the background. We keep this as a top-level so the
/// import surface in the widget is small (no `dart:async` leak).
void unawaited(Future<void> future) {
  // ignore: unawaited_futures
  future;
}
