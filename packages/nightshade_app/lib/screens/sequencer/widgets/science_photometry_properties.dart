// Wave 7.5 — Properties editor for the SciencePhotometryNode (Wave 7
// Science). One vertical scroll of form fields mapped onto the
// SciencePhotometryConfig the Rust runtime consumes. The reference-star
// list is rendered as removable chips with a quick-add text field so an
// operator with an AAVSO comp-star chart can type IDs in sequence.
//
// canEdit gating from Wave 1.5 Pack B is honoured at the dispatching
// `_NodeEditor` boundary; this widget therefore receives interaction
// events only when the sequence is editable.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class SciencePhotometryProperties extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final SciencePhotometryNode node;

  const SciencePhotometryProperties({
    super.key,
    required this.colors,
    required this.node,
  });

  @override
  ConsumerState<SciencePhotometryProperties> createState() =>
      _SciencePhotometryPropertiesState();
}

class _SciencePhotometryPropertiesState
    extends ConsumerState<SciencePhotometryProperties> {
  late TextEditingController _targetCtl;
  late TextEditingController _addRefCtl;
  late TextEditingController _exposureCtl;
  late TextEditingController _countCtl;
  late TextEditingController _maxCadenceCtl;
  late TextEditingController _minSnrCtl;
  late TextEditingController _maxFwhmCtl;
  late TextEditingController _maxAirmassCtl;
  late TextEditingController _gainCtl;
  late TextEditingController _offsetCtl;

  bool _qualityExpanded = false;

  @override
  void initState() {
    super.initState();
    _targetCtl = TextEditingController(text: widget.node.targetDesignation);
    _addRefCtl = TextEditingController();
    _exposureCtl = TextEditingController(
      text: widget.node.exposureSecs.toString(),
    );
    _countCtl = TextEditingController(text: widget.node.count.toString());
    _maxCadenceCtl = TextEditingController(
      text: widget.node.maxCadenceGapSecs.toString(),
    );
    _minSnrCtl = TextEditingController(
      text: widget.node.quality.minSnr.toString(),
    );
    _maxFwhmCtl = TextEditingController(
      text: widget.node.quality.maxFwhmArcsec.toString(),
    );
    _maxAirmassCtl = TextEditingController(
      text: widget.node.quality.maxAirmass.toString(),
    );
    _gainCtl =
        TextEditingController(text: widget.node.gain?.toString() ?? '');
    _offsetCtl =
        TextEditingController(text: widget.node.offset?.toString() ?? '');
  }

  @override
  void dispose() {
    _targetCtl.dispose();
    _addRefCtl.dispose();
    _exposureCtl.dispose();
    _countCtl.dispose();
    _maxCadenceCtl.dispose();
    _minSnrCtl.dispose();
    _maxFwhmCtl.dispose();
    _maxAirmassCtl.dispose();
    _gainCtl.dispose();
    _offsetCtl.dispose();
    super.dispose();
  }

  void _update(SciencePhotometryNode Function(SciencePhotometryNode) mutate) {
    final notifier = ref.read(currentSequenceProvider.notifier);
    notifier.updateNode(mutate(widget.node));
  }

  /// PHASE-5: SciencePhotometryNode.copyWith now uses plain
  /// `?? this.gain` / `?? this.offset` semantics, so a null arg no
  /// longer clears. Clearing back to "use device default" requires
  /// rebuilding a fresh node.
  void _clearGainOrOffset({bool clearGain = false, bool clearOffset = false}) {
    final n = widget.node;
    ref.read(currentSequenceProvider.notifier).updateNode(
          SciencePhotometryNode(
            id: n.id,
            name: n.name,
            isEnabled: n.isEnabled,
            childIds: n.childIds,
            parentId: n.parentId,
            orderIndex: n.orderIndex,
            comment: n.comment,
            targetDesignation: n.targetDesignation,
            referenceStars: n.referenceStars,
            maxCadenceGapSecs: n.maxCadenceGapSecs,
            filter: n.filter,
            exposureSecs: n.exposureSecs,
            count: n.count,
            reduceLive: n.reduceLive,
            applyDifferential: n.applyDifferential,
            quality: n.quality,
            gain: clearGain ? null : n.gain,
            offset: clearOffset ? null : n.offset,
            binning: n.binning,
          ),
        );
  }

  void _addReferenceStar(String raw) {
    final id = raw.trim();
    if (id.isEmpty) return;
    final existing = widget.node.referenceStars;
    // Deduplicate by case-insensitive match; preserve insertion order.
    if (existing.any((e) => e.toLowerCase() == id.toLowerCase())) {
      return;
    }
    _update((n) => n.copyWith(
          referenceStars: [...existing, id],
        ));
    _addRefCtl.clear();
  }

  void _removeReferenceStar(String id) {
    final filtered =
        widget.node.referenceStars.where((e) => e != id).toList(growable: false);
    _update((n) => n.copyWith(referenceStars: filtered));
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final node = widget.node;
    final theme = Theme.of(context);
    final isPhotometricFilter = node.isPhotometricFilter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(theme, colors, 'Target'),
        TextField(
          controller: _targetCtl,
          decoration: const InputDecoration(
            labelText: 'Target designation',
            helperText:
                'AAVSO / catalogue identifier (e.g. "V0376 Per", "TIC 38846515")',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) =>
              _update((n) => n.copyWith(targetDesignation: v.trim())),
        ),
        const SizedBox(height: 16),

        _sectionLabel(theme, colors, 'Reference stars'),
        Text(
          'Comparison stars for differential photometry. Order does not '
          'matter; the runtime extracts each independently.',
          style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textSecondary),
        ),
        const SizedBox(height: 8),
        if (node.referenceStars.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertCircle,
                    size: 14, color: colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No reference stars configured. Differential '
                    'photometry will fall back to instrumental magnitude only.',
                    style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in node.referenceStars)
                InputChip(
                  label: Text(id),
                  onDeleted: () => _removeReferenceStar(id),
                  deleteIcon: const Icon(LucideIcons.x, size: 14),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _addRefCtl,
                decoration: const InputDecoration(
                  hintText: 'Catalogue id, e.g. AAVSO 000-BMP-364',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: _addReferenceStar,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Add reference star',
              onPressed: () => _addReferenceStar(_addRefCtl.text),
              icon: const Icon(LucideIcons.plus, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _sectionLabel(theme, colors, 'Capture'),
        DropdownButtonFormField<String>(
          initialValue: kPhotometricFilterBands.contains(node.filter)
              ? node.filter
              : null,
          items: [
            for (final band in kPhotometricFilterBands)
              DropdownMenuItem(value: band, child: Text(band)),
          ],
          onChanged: (v) {
            if (v == null) return;
            _update((n) => n.copyWith(filter: v));
          },
          decoration: InputDecoration(
            labelText: 'Photometric filter',
            helperText: isPhotometricFilter
                ? 'Standard photometric band'
                : 'WARNING: not a standard photometric band',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _exposureCtl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Exposure (s)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed == null || parsed <= 0) return;
                  _update((n) => n.copyWith(exposureSecs: parsed));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _countCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Frame count',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed == null || parsed < 1) return;
                  _update((n) => n.copyWith(count: parsed));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _maxCadenceCtl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Max cadence gap (s)',
            helperText:
                'Extra start-to-start gap permitted on top of the exposure. '
                'Larger values tolerate slower download / longer dithers. '
                'A gap larger than this fires a cadence-broken warning '
                'on the dashboard but does NOT abort the burst.',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) {
            final parsed = double.tryParse(v);
            if (parsed == null || parsed < 0) return;
            _update((n) => n.copyWith(maxCadenceGapSecs: parsed));
          },
        ),
        const SizedBox(height: 16),

        _sectionLabel(theme, colors, 'Reduction'),
        SwitchListTile(
          value: node.reduceLive,
          onChanged: (v) => _update((n) => n.copyWith(reduceLive: v)),
          title: const Text('Reduce live'),
          subtitle: const Text(
            'Extract instrumental magnitude per frame and write a row '
            'to photometry_measurements as the sequence runs.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: node.applyDifferential,
          onChanged: node.reduceLive
              ? (v) => _update((n) => n.copyWith(applyDifferential: v))
              : null,
          title: const Text('Apply differential'),
          subtitle: const Text(
            'Compute differential magnitude against reference stars. '
            'Requires "Reduce live" and at least one reference star.',
          ),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),

        _sectionLabel(theme, colors, 'Camera overrides (optional)'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _gainCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Gain',
                  hintText: 'leave blank for default',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  if (v.isEmpty) {
                    _clearGainOrOffset(clearGain: true);
                    return;
                  }
                  final parsed = int.tryParse(v);
                  if (parsed == null) return;
                  _update((n) => n.copyWith(gain: parsed));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _offsetCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Offset',
                  hintText: 'leave blank for default',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  if (v.isEmpty) {
                    _clearGainOrOffset(clearOffset: true);
                    return;
                  }
                  final parsed = int.tryParse(v);
                  if (parsed == null) return;
                  _update((n) => n.copyWith(offset: parsed));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<BinningMode>(
          initialValue: node.binning,
          items: BinningMode.values
              .map((b) => DropdownMenuItem(
                    value: b,
                    child: Text(b.name.toUpperCase()),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            _update((n) => n.copyWith(binning: v));
          },
          decoration: const InputDecoration(
            labelText: 'Binning',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Quality gates — collapsible because they're rarely tuned and
        // can crowd the editor.
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            onTap: () =>
                setState(() => _qualityExpanded = !_qualityExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _qualityExpanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Quality gates',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(SNR ≥ ${node.quality.minSnr.toStringAsFixed(0)}, '
                    'FWHM ≤ ${node.quality.maxFwhmArcsec.toStringAsFixed(1)}", '
                    'airmass ≤ ${node.quality.maxAirmass.toStringAsFixed(2)})',
                    style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_qualityExpanded) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minSnrCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Min SNR',
                    helperText: 'AAVSO research-grade ≥ 50',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed == null || parsed < 0) return;
                    _update((n) => n.copyWith(
                          quality: n.quality.copyWith(minSnr: parsed),
                        ));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _maxFwhmCtl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Max FWHM (")',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed == null || parsed <= 0) return;
                    _update((n) => n.copyWith(
                          quality:
                              n.quality.copyWith(maxFwhmArcsec: parsed),
                        ));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxAirmassCtl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Max airmass',
              helperText: 'AAVSO BSM cutoff ≈ 2.5',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              if (parsed == null || parsed <= 1.0) return;
              _update((n) => n.copyWith(
                    quality: n.quality.copyWith(maxAirmass: parsed),
                  ));
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: node.quality.requireAllRefsVisible,
            onChanged: (v) => _update(
              (n) => n.copyWith(
                quality: n.quality.copyWith(requireAllRefsVisible: v),
              ),
            ),
            title: const Text('Require all reference stars'),
            subtitle: const Text(
              'When on, frames where any reference star failed extraction '
              'are routed to the reject folder. Off accepts the frame and '
              'falls back to instrumental magnitude.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ],
        const SizedBox(height: 8),

        if (node.hasImpossibleCadence)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.warning,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 14, color: colors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Negative cadence gap is impossible — the executor '
                    'will reject this node at validation.',
                    style: NightshadeTypography.labelStrongSm.copyWith(color: colors.warning),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionLabel(
    ThemeData theme,
    NightshadeColors colors,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: colors.textMuted,
        ),
      ),
    );
  }
}
