// Part of ../node_properties_panel.dart -- migrated from the former
// instruction_node_properties library (Wave 4 consolidation).
// Sky-brightness adaptive-exposure config block + per-filter override row.
part of '../node_properties_panel.dart';

class _AdaptiveExposureSection extends ConsumerStatefulWidget {
  const _AdaptiveExposureSection({
    required this.colors,
    required this.node,
    required this.profile,
  });

  final NightshadeColors colors;
  final ExposureNode node;
  final EquipmentProfileModel? profile;

  @override
  ConsumerState<_AdaptiveExposureSection> createState() =>
      _AdaptiveExposureSectionState();
}

class _AdaptiveExposureSectionState
    extends ConsumerState<_AdaptiveExposureSection> {
  AdaptiveExposureConfig get _effective =>
      widget.node.adaptiveExposure ?? const AdaptiveExposureConfig();

  /// Whether this node carries its own per-node override (vs. inheriting
  /// the global default from settings).
  bool get _hasOverride => widget.node.adaptiveExposure != null;

  void _update(AdaptiveExposureConfig next) {
    ref.read(currentSequenceProvider.notifier).updateNode(
          widget.node.copyWith(adaptiveExposure: next),
        );
  }

  void _clearOverride() {
    // Rebuild explicitly: ExposureNode.copyWith now uses plain
    // `?? this.adaptiveExposure` semantics, so a null arg means "keep
    // current". The only way to set adaptiveExposure back to null
    // ("inherit global default") is to construct a fresh node.
    final n = widget.node;
    ref.read(currentSequenceProvider.notifier).updateNode(
          ExposureNode(
            id: n.id,
            name: n.name,
            isEnabled: n.isEnabled,
            childIds: n.childIds,
            parentId: n.parentId,
            orderIndex: n.orderIndex,
            comment: n.comment,
            durationSecs: n.durationSecs,
            count: n.count,
            frameType: n.frameType,
            filter: n.filter,
            filterIndex: n.filterIndex,
            gain: n.gain,
            offset: n.offset,
            binning: n.binning,
            ditherEvery: n.ditherEvery,
            triggers: n.triggers,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.4),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.barChart3, size: 14, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Adaptive Exposure (sky-brightness)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _hasOverride ? 'Per-node' : 'Inherit',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize10,
                    color: colors.textMuted),
              ),
              const SizedBox(width: 6),
              NightshadeSwitch(
                value: _hasOverride,
                onChanged: (v) {
                  if (v) {
                    _update(const AdaptiveExposureConfig());
                  } else {
                    _clearOverride();
                  }
                  setState(() {});
                },
              ),
            ],
          ),
          if (!_hasOverride)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 22),
              child: Text(
                'Inheriting global default from Settings → Adaptive Exposure.',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textMuted),
              ),
            ),
          if (_hasOverride) ...[
            const SizedBox(height: 12),
            _buildKnobs(),
            const SizedBox(height: 12),
            _buildPerFilterTable(),
            const SizedBox(height: 12),
            _buildPreview(),
          ],
        ],
      ),
    );
  }

  Widget _buildKnobs() {
    final cfg = _effective;
    final colors = widget.colors;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Target SNR',
                child: NodeNumberInput(
                  colors: colors,
                  value: cfg.targetSnr,
                  min: 1,
                  max: 1000,
                  decimals: 0,
                  onChanged: (v) => _update(cfg.copyWith(targetSnr: v)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Reference (mag/arcsec²)',
                child: NodeNumberInput(
                  colors: colors,
                  value: cfg.referenceSkyBrightnessMag,
                  min: 14,
                  max: 24,
                  decimals: 2,
                  onChanged: (v) =>
                      _update(cfg.copyWith(referenceSkyBrightnessMag: v)),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Min (s)',
                child: NodeNumberInput(
                  colors: colors,
                  value: cfg.minExposureSecs,
                  min: 0.001,
                  max: 7200,
                  decimals: 1,
                  onChanged: (v) => _update(cfg.copyWith(minExposureSecs: v)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Max (s)',
                child: NodeNumberInput(
                  colors: colors,
                  value: cfg.maxExposureSecs,
                  min: 0.001,
                  max: 7200,
                  decimals: 1,
                  onChanged: (v) => _update(cfg.copyWith(maxExposureSecs: v)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPerFilterTable() {
    final cfg = _effective;
    final colors = widget.colors;
    final filterNames = widget.profile?.filterNames ?? const <String>[];
    if (filterNames.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'No filter wheel on active profile — adaptive applies to every '
          'capture (mono camera assumption).',
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Per-filter overrides',
          style: NightshadeTypography.labelStrongSm
              .copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        for (final filter in filterNames)
          _PerFilterRow(
            colors: colors,
            filter: filter,
            cfg: cfg,
            onChanged: _update,
          ),
      ],
    );
  }

  Widget _buildPreview() {
    final cfg = _effective;
    final colors = widget.colors;
    final tracker = ref.read(skyBrightnessTrackerProvider);
    final liveMag = tracker.currentMagPerArcsec2();
    final filter = widget.node.filter;

    final enabled = cfg.isEnabledForFilter(filter);
    final min = cfg.minForFilter(filter);
    final max = cfg.maxForFilter(filter);
    String preview;
    Color color = colors.textPrimary;
    if (!cfg.enabled) {
      preview = 'Adaptive exposure is off (global enable switch).';
      color = colors.textMuted;
    } else if (!enabled) {
      preview = 'Adaptive disabled for filter "${filter ?? "(none)"}". '
          'Exposure stays at ${widget.node.durationSecs.toStringAsFixed(1)}s.';
      color = colors.textMuted;
    } else if (liveMag == null) {
      preview = 'Sky brightness not yet available — exposure stays at '
          '${widget.node.durationSecs.toStringAsFixed(1)}s until the tracker converges.';
      color = colors.textMuted;
    } else {
      final ratio = math
          .pow(10, (cfg.referenceSkyBrightnessMag - liveMag) / 2.5)
          .toDouble();
      final raw = widget.node.durationSecs * ratio;
      final clamped = raw < min
          ? min
          : raw > max
              ? max
              : raw;
      preview = 'At current sky ${liveMag.toStringAsFixed(2)} mag/arcsec², '
          'this exposure would be ${clamped.toStringAsFixed(0)}s '
          '(nominal ${widget.node.durationSecs.toStringAsFixed(0)}s).';
      if (clamped == min || clamped == max) {
        color = colors.warning;
      } else {
        color = colors.primary;
      }
    }

    final outOfBounds =
        widget.node.durationSecs < min || widget.node.durationSecs > max;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.background.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.lineChart, size: 12, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(preview,
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: color)),
              ),
            ],
          ),
          if (outOfBounds && cfg.enabled) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 12, color: colors.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Nominal duration (${widget.node.durationSecs.toStringAsFixed(0)}s) '
                    'is outside the adaptive [${min.toStringAsFixed(0)}, ${max.toStringAsFixed(0)}]s '
                    'bounds — every frame will be clamped.',
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
                        color: colors.warning),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PerFilterRow extends StatelessWidget {
  const _PerFilterRow({
    required this.colors,
    required this.filter,
    required this.cfg,
    required this.onChanged,
  });

  final NightshadeColors colors;
  final String filter;
  final AdaptiveExposureConfig cfg;
  final ValueChanged<AdaptiveExposureConfig> onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled =
        cfg.perFilterEnabled[filter] ?? cfg.perFilterEnabled.isEmpty;
    final min = cfg.perFilterMinSecs[filter];
    final max = cfg.perFilterMaxSecs[filter];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              filter,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textPrimary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          NightshadeCheckbox(
            value: enabled,
            onChanged: (v) {
              final next = Map<String, bool>.from(cfg.perFilterEnabled);
              next[filter] = v ?? false;
              onChanged(cfg.copyWith(perFilterEnabled: next));
            },
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: NodeNumberInput(
              colors: colors,
              value: min ?? cfg.minExposureSecs,
              min: 0.001,
              max: 7200,
              decimals: 1,
              suffix: 's min',
              onChanged: (v) {
                final next = Map<String, double>.from(cfg.perFilterMinSecs);
                next[filter] = v;
                onChanged(cfg.copyWith(perFilterMinSecs: next));
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: NodeNumberInput(
              colors: colors,
              value: max ?? cfg.maxExposureSecs,
              min: 0.001,
              max: 7200,
              decimals: 1,
              suffix: 's max',
              onChanged: (v) {
                final next = Map<String, double>.from(cfg.perFilterMaxSecs);
                next[filter] = v;
                onChanged(cfg.copyWith(perFilterMaxSecs: next));
              },
            ),
          ),
        ],
      ),
    );
  }
}
