// Properties editor for the SciencePhotometryNode. One vertical
// scroll of form fields mapped onto the
// SciencePhotometryConfig the Rust runtime consumes. The reference-star
// list is rendered as removable chips with a quick-add text field so an
// operator with an AAVSO comp-star chart can type IDs in sequence.
//
// canEdit gating is honoured at the dispatching
// `_NodeEditor` boundary; this widget therefore receives interaction
// events only when the sequence is editable.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  final _targetFocus = FocusNode();
  final _exposureFocus = FocusNode();
  final _countFocus = FocusNode();
  final _maxCadenceFocus = FocusNode();
  final _minSnrFocus = FocusNode();
  final _maxFwhmFocus = FocusNode();
  final _maxAirmassFocus = FocusNode();
  final _gainFocus = FocusNode();
  final _offsetFocus = FocusNode();

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
    _gainCtl = TextEditingController(text: widget.node.gain?.toString() ?? '');
    _offsetCtl =
        TextEditingController(text: widget.node.offset?.toString() ?? '');
  }

  @override
  void didUpdateWidget(SciencePhotometryProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The dispatching _NodeEditor is unkeyed, so this State is reused when
    // widget.node changes — an undo/redo on the same node or a switch to a
    // different SciencePhotometryNode. Resync each controller from the model
    // so the text fields never lag the dropdowns/switches. A field that is
    // being typed into (focused) is left alone to avoid clobbering the caret;
    // a node id change forces a resync regardless.
    final node = widget.node;
    final idChanged = oldWidget.node.id != node.id;
    _syncField(_targetCtl, _targetFocus, node.targetDesignation,
        force: idChanged);
    _syncField(_exposureCtl, _exposureFocus, node.exposureSecs.toString(),
        force: idChanged);
    _syncField(_countCtl, _countFocus, node.count.toString(), force: idChanged);
    _syncField(
        _maxCadenceCtl, _maxCadenceFocus, node.maxCadenceGapSecs.toString(),
        force: idChanged);
    _syncField(_minSnrCtl, _minSnrFocus, node.quality.minSnr.toString(),
        force: idChanged);
    _syncField(
        _maxFwhmCtl, _maxFwhmFocus, node.quality.maxFwhmArcsec.toString(),
        force: idChanged);
    _syncField(
        _maxAirmassCtl, _maxAirmassFocus, node.quality.maxAirmass.toString(),
        force: idChanged);
    _syncField(_gainCtl, _gainFocus, node.gain?.toString() ?? '',
        force: idChanged);
    _syncField(_offsetCtl, _offsetFocus, node.offset?.toString() ?? '',
        force: idChanged);
    if (idChanged) _addRefCtl.clear();
  }

  void _syncField(
    TextEditingController ctl,
    FocusNode focus,
    String value, {
    required bool force,
  }) {
    if (!force && focus.hasFocus) return;
    if (ctl.text != value) ctl.text = value;
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
    _targetFocus.dispose();
    _exposureFocus.dispose();
    _countFocus.dispose();
    _maxCadenceFocus.dispose();
    _minSnrFocus.dispose();
    _maxFwhmFocus.dispose();
    _maxAirmassFocus.dispose();
    _gainFocus.dispose();
    _offsetFocus.dispose();
    super.dispose();
  }

  void _update(SciencePhotometryNode Function(SciencePhotometryNode) mutate) {
    final notifier = ref.read(currentSequenceProvider.notifier);
    notifier.updateNode(mutate(widget.node));
  }

  /// `SciencePhotometryNode.copyWith` uses plain `?? this.gain` /
  /// `?? this.offset` semantics, so a null arg does not clear. Clearing back to
  /// "use device default" requires rebuilding a fresh node.
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
    final filtered = widget.node.referenceStars
        .where((e) => e != id)
        .toList(growable: false);
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
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceSm + 2,
          ),
          decoration: NightshadeDecorations.emphasisSurface(
            colors.accent,
            borderRadius: NightshadeTokens.borderRadiusLg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(NightshadeTokens.spaceXs + 2),
                decoration: NightshadeDecorations.iconChip(colors.accent),
                child: Icon(LucideIcons.lineChart,
                    size: NightshadeTokens.iconXs, color: colors.accent),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This node produces a calibrated light curve you can '
                      'export straight to AAVSO.',
                      style: NightshadeTypography.labelStrongSm
                          .copyWith(color: colors.textPrimary),
                    ),
                    if (node.reduceLive) ...[
                      const SizedBox(height: NightshadeTokens.spaceSm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: NightshadeButton(
                          label: 'Open Light Curve',
                          icon: LucideIcons.lineChart,
                          variant: ButtonVariant.ghost,
                          size: ButtonSize.small,
                          onPressed: () => context.go('/science'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),

        _sectionLabel(theme, colors, 'Target'),
        NightshadeTextField(
          controller: _targetCtl,
          focusNode: _targetFocus,
          label: 'Target designation',
          hint:
              'AAVSO / catalogue identifier (e.g. "V0376 Per", "TIC 38846515")',
          onChanged: (v) =>
              _update((n) => n.copyWith(targetDesignation: v.trim())),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),

        _sectionLabel(theme, colors, 'Reference stars'),
        Text(
          'Comparison stars for differential photometry. Order does not '
          'matter; the runtime extracts each independently.',
          style: NightshadeTypography.captionSm
              .copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        if (node.referenceStars.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: NightshadeTokens.spaceSm,
            ),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: NightshadeTokens.borderRadiusMd,
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertCircle,
                    size: NightshadeTokens.iconXs, color: colors.textMuted),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Expanded(
                  child: Text(
                    'No reference stars configured. Differential '
                    'photometry will fall back to instrumental magnitude only.',
                    style: NightshadeTypography.captionSm
                        .copyWith(color: colors.textMuted),
                  ),
                ),
              ],
            ),
          )
        else
          Wrap(
            spacing: NightshadeTokens.spaceXs + 2,
            runSpacing: NightshadeTokens.spaceXs + 2,
            children: [
              for (final id in node.referenceStars)
                NightshadeChip(
                  label: id,
                  icon: LucideIcons.x,
                  onTap: () => _removeReferenceStar(id),
                ),
            ],
          ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Row(
          children: [
            Expanded(
              child: NightshadeTextField(
                controller: _addRefCtl,
                hint: 'Catalogue id, e.g. AAVSO 000-BMP-364',
                textInputAction: TextInputAction.done,
                onSubmitted: _addReferenceStar,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            NightshadeButton(
              label: 'Add',
              icon: LucideIcons.plus,
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
              onPressed: () => _addReferenceStar(_addRefCtl.text),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),

        _sectionLabel(theme, colors, 'Capture'),
        _fieldLabel(colors, 'Photometric filter'),
        NightshadeDropdown(
          value: kPhotometricFilterBands.contains(node.filter)
              ? node.filter
              : null,
          hint: 'Photometric filter',
          isExpanded: true,
          items: kPhotometricFilterBands.toList(),
          onChanged: (v) {
            if (v == null) return;
            _update((n) => n.copyWith(filter: v));
          },
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          isPhotometricFilter
              ? 'Standard photometric band'
              : 'WARNING: not a standard photometric band',
          style: NightshadeTypography.captionSm.copyWith(
            color: isPhotometricFilter ? colors.textMuted : colors.warning,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Row(
          children: [
            Expanded(
              child: NightshadeTextField(
                controller: _exposureCtl,
                focusNode: _exposureFocus,
                label: 'Exposure (s)',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) {
                  final parsed = double.tryParse(v);
                  if (parsed == null || parsed <= 0) return;
                  _update((n) => n.copyWith(exposureSecs: parsed));
                },
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: NightshadeTextField(
                controller: _countCtl,
                focusNode: _countFocus,
                label: 'Frame count',
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final parsed = int.tryParse(v);
                  if (parsed == null || parsed < 1) return;
                  _update((n) => n.copyWith(count: parsed));
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        NightshadeTextField(
          controller: _maxCadenceCtl,
          focusNode: _maxCadenceFocus,
          label: 'Max cadence gap (s)',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            final parsed = double.tryParse(v);
            if (parsed == null || parsed < 0) return;
            _update((n) => n.copyWith(maxCadenceGapSecs: parsed));
          },
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          'Extra start-to-start gap permitted on top of the exposure. '
          'Larger values tolerate slower download / longer dithers. '
          'A gap larger than this fires a cadence-broken warning '
          'on the dashboard but does NOT abort the burst.',
          style:
              NightshadeTypography.captionSm.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),

        _sectionLabel(theme, colors, 'Reduction'),
        NightshadeSwitchRow(
          label: 'Reduce live',
          subtitle: 'Extract instrumental magnitude per frame and write a row '
              'to photometry_measurements as the sequence runs.',
          value: node.reduceLive,
          onChanged: (v) => _update((n) => n.copyWith(reduceLive: v)),
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        NightshadeSwitchRow(
          label: 'Apply differential',
          subtitle: 'Compute differential magnitude against reference stars. '
              'Requires "Reduce live" and at least one reference star.',
          value: node.applyDifferential,
          enabled: node.reduceLive,
          onChanged: node.reduceLive
              ? (v) => _update((n) => n.copyWith(applyDifferential: v))
              : null,
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),

        _sectionLabel(theme, colors, 'Camera overrides (optional)'),
        Row(
          children: [
            Expanded(
              child: NightshadeTextField(
                controller: _gainCtl,
                focusNode: _gainFocus,
                label: 'Gain',
                hint: 'leave blank for default',
                keyboardType: TextInputType.number,
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
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: NightshadeTextField(
                controller: _offsetCtl,
                focusNode: _offsetFocus,
                label: 'Offset',
                hint: 'leave blank for default',
                keyboardType: TextInputType.number,
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
        const SizedBox(height: NightshadeTokens.spaceMd),
        _fieldLabel(colors, 'Binning'),
        NightshadeDropdown(
          value: node.binning.name,
          isExpanded: true,
          items: BinningMode.values.map((b) => b.name).toList(),
          itemLabels:
              BinningMode.values.map((b) => b.name.toUpperCase()).toList(),
          onChanged: (v) {
            if (v == null) return;
            final mode = BinningMode.values.firstWhere((b) => b.name == v);
            _update((n) => n.copyWith(binning: mode));
          },
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),

        // Quality gates — collapsible because they're rarely tuned and
        // can crowd the editor.
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            onTap: () => setState(() => _qualityExpanded = !_qualityExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _qualityExpanded
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronRight,
                    size: NightshadeTokens.iconXs,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: NightshadeTokens.spaceXs + 2),
                  Text(
                    'Quality gates',
                    style: NightshadeTypography.h6
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Text(
                    '(SNR ≥ ${node.quality.minSnr.toStringAsFixed(0)}, '
                    'FWHM ≤ ${node.quality.maxFwhmArcsec.toStringAsFixed(1)}", '
                    'airmass ≤ ${node.quality.maxAirmass.toStringAsFixed(2)})',
                    style: NightshadeTypography.captionSm
                        .copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_qualityExpanded) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: NightshadeTextField(
                  controller: _minSnrCtl,
                  focusNode: _minSnrFocus,
                  label: 'Min SNR',
                  hint: 'AAVSO research-grade ≥ 50',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
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
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: NightshadeTextField(
                  controller: _maxFwhmCtl,
                  focusNode: _maxFwhmFocus,
                  label: 'Max FWHM (")',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed == null || parsed <= 0) return;
                    _update((n) => n.copyWith(
                          quality: n.quality.copyWith(maxFwhmArcsec: parsed),
                        ));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          NightshadeTextField(
            controller: _maxAirmassCtl,
            focusNode: _maxAirmassFocus,
            label: 'Max airmass',
            hint: 'AAVSO BSM cutoff ≈ 2.5',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              final parsed = double.tryParse(v);
              if (parsed == null || parsed <= 1.0) return;
              _update((n) => n.copyWith(
                    quality: n.quality.copyWith(maxAirmass: parsed),
                  ));
            },
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          NightshadeSwitchRow(
            label: 'Require all reference stars',
            subtitle:
                'When on, frames where any reference star failed extraction '
                'are routed to the reject folder. Off accepts the frame and '
                'falls back to instrumental magnitude.',
            value: node.quality.requireAllRefsVisible,
            onChanged: (v) => _update(
              (n) => n.copyWith(
                quality: n.quality.copyWith(requireAllRefsVisible: v),
              ),
            ),
          ),
        ],
        const SizedBox(height: NightshadeTokens.spaceSm),

        if (node.hasImpossibleCadence)
          Container(
            margin: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
            padding: const EdgeInsets.symmetric(
              horizontal: NightshadeTokens.spaceMd,
              vertical: NightshadeTokens.spaceSm + 2,
            ),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.warning,
              borderRadius: NightshadeTokens.borderRadiusLg,
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: NightshadeTokens.iconXs, color: colors.warning),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Expanded(
                  child: Text(
                    'Negative cadence gap is impossible — the executor '
                    'will reject this node at validation.',
                    style: NightshadeTypography.labelStrongSm
                        .copyWith(color: colors.warning),
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
      padding: const EdgeInsets.only(
        bottom: NightshadeTokens.spaceXs + 2,
        top: NightshadeTokens.spaceXs,
      ),
      child: Text(
        label.toUpperCase(),
        style: NightshadeTypography.overline.copyWith(color: colors.textMuted),
      ),
    );
  }

  Widget _fieldLabel(NightshadeColors colors, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
      child: Text(
        label,
        style:
            NightshadeTypography.labelSm.copyWith(color: colors.textSecondary),
      ),
    );
  }
}
