import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Lists the persisted [IntegratedMaster]s for the current target and surfaces
/// the multi-night accumulation actions: open, finalize, add tonight's data,
/// start a new accumulating master, and delete.
///
/// Pure presentation — every mutation is delegated to the supplied callbacks so
/// the owning controller remains the single source of truth.
class MasterLibraryPanel extends StatelessWidget {
  final List<IntegratedMaster> masters;

  /// Accepted-light count in scope, so "add tonight" can be disabled when empty.
  final int acceptedSubCount;

  /// True while any integration / accumulation run is in flight.
  final bool busy;

  final void Function(IntegratedMaster) onOpen;
  final void Function(IntegratedMaster) onAddTonight;
  final void Function(IntegratedMaster) onFinalize;
  final void Function(IntegratedMaster) onDelete;
  final VoidCallback onCreateAccumulating;

  const MasterLibraryPanel({
    super.key,
    required this.masters,
    required this.acceptedSubCount,
    required this.busy,
    required this.onOpen,
    required this.onAddTonight,
    required this.onFinalize,
    required this.onDelete,
    required this.onCreateAccumulating,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Masters',
          subtitle: 'Finished + accumulating masters for this target.',
          trailing: NightshadeButton(
            label: 'New accumulating',
            icon: NightshadeIcons.add,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed:
                (busy || acceptedSubCount == 0) ? null : onCreateAccumulating,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        if (masters.isEmpty)
          NightshadeCard(
            variant: CardVariant.subtle,
            padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
            child: Row(
              children: [
                Icon(NightshadeIcons.layers, size: 18, color: colors.textMuted),
                const SizedBox(width: NightshadeTokens.spaceMd),
                Expanded(
                  child: Text(
                    'No masters yet. Integrate the night, or start an '
                    'accumulating master to grow across multiple nights.',
                    style: NightshadeTypography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ...masters.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
              child: _MasterCard(
                master: m,
                acceptedSubCount: acceptedSubCount,
                busy: busy,
                onOpen: () => onOpen(m),
                onAddTonight: () => onAddTonight(m),
                onFinalize: () => onFinalize(m),
                onDelete: () => onDelete(m),
              ),
            ),
          ),
      ],
    );
  }
}

class _MasterCard extends StatelessWidget {
  final IntegratedMaster master;
  final int acceptedSubCount;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAddTonight;
  final VoidCallback onFinalize;
  final VoidCallback onDelete;

  const _MasterCard({
    required this.master,
    required this.acceptedSubCount,
    required this.busy,
    required this.onOpen,
    required this.onAddTonight,
    required this.onFinalize,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final accumulating =
        master.accumulationMode == AccumulationMode.runningWeightedMean;
    final canOpen =
        master.previewPngPath != null || master.masterFitsPath != null;

    return NightshadeCard(
      onTap: canOpen && !busy ? onOpen : null,
      enableHover: canOpen,
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumb(previewPath: master.previewPngPath, colors: colors),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        master.name,
                        style: NightshadeTypography.h6.copyWith(
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _StatusBadge(
                      label: accumulating
                          ? (master.status == IntegratedMasterStatus.finalized
                              ? 'Accumulating · finalized'
                              : 'Accumulating')
                          : 'Batch',
                      color: accumulating ? colors.info : colors.success,
                    ),
                  ],
                ),
                const SizedBox(height: NightshadeTokens.spaceXs),
                Text(
                  '${master.frameCount} frame'
                  '${master.frameCount == 1 ? '' : 's'} · '
                  '${formatHms(master.totalIntegrationSeconds)} integration'
                  '${master.filter != null ? ' · ${master.filter}' : ''}',
                  style: NightshadeTypography.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                Text(
                  '${master.width}×${master.height} · '
                  '${master.isColor ? 'colour' : 'mono'} · '
                  'updated ${_relativeDate(master.updatedAt)}',
                  style: NightshadeTypography.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                Wrap(
                  spacing: NightshadeTokens.spaceSm,
                  runSpacing: NightshadeTokens.spaceSm,
                  children: [
                    if (canOpen)
                      _MiniButton(
                        label: 'Open',
                        icon: NightshadeIcons.image,
                        onPressed: busy ? null : onOpen,
                      ),
                    if (accumulating)
                      _MiniButton(
                        label: 'Add tonight',
                        icon: NightshadeIcons.add,
                        onPressed: (busy || acceptedSubCount == 0)
                            ? null
                            : onAddTonight,
                      ),
                    if (accumulating)
                      _MiniButton(
                        label: master.status == IntegratedMasterStatus.finalized
                            ? 'Re-finalize'
                            : 'Finalize',
                        icon: NightshadeIcons.download,
                        onPressed: busy ? null : onFinalize,
                      ),
                    _MiniButton(
                      label: 'Delete',
                      icon: NightshadeIcons.error,
                      destructive: true,
                      onPressed: busy ? null : onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _relativeDate(DateTime when) {
    final d = when.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}

class _Thumb extends StatelessWidget {
  final String? previewPath;
  final NightshadeColors colors;

  const _Thumb({required this.previewPath, required this.colors});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        border: Border.all(color: colors.border),
      ),
      child: Icon(NightshadeIcons.layers, size: 24, color: colors.textMuted),
    );
    final path = previewPath;
    if (path == null) return placeholder;
    final file = File(path);
    bool exists;
    try {
      exists = file.existsSync();
    } catch (_) {
      exists = false;
    }
    if (!exists) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
      child: Image.file(
        file,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: NightshadeDecorations.tintedBadge(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Text(
        label,
        style: NightshadeTypography.labelStrongSm.copyWith(color: color),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  const _MiniButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final fg = onPressed == null
        ? colors.textMuted
        : destructive
            ? colors.error
            : colors.textSecondary;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceSm,
          vertical: NightshadeTokens.spaceXs,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: NightshadeTokens.spaceXs),
            Text(
              label,
              style: NightshadeTypography.labelSm.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
