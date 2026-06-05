part of '../mosaic_wizard_dialog.dart';

class _GridSizer extends StatelessWidget {
  final NightshadeColors colors;
  final int rows;
  final int cols;
  final double overlapPercent;
  final double rotation;
  final void Function({
    int? rows,
    int? cols,
    double? overlap,
    double? rotation,
  }) onChange;

  const _GridSizer({
    required this.colors,
    required this.rows,
    required this.cols,
    required this.overlapPercent,
    required this.rotation,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grid', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _IntStepper(
                  colors: colors,
                  label: 'Columns',
                  value: cols,
                  min: 1,
                  max: 10,
                  onChanged: (v) => onChange(cols: v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _IntStepper(
                  colors: colors,
                  label: 'Rows',
                  value: rows,
                  min: 1,
                  max: 10,
                  onChanged: (v) => onChange(rows: v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SliderRow(
            colors: colors,
            label: 'Overlap',
            value: overlapPercent,
            min: 0,
            max: 50,
            suffix: '%',
            onChanged: (v) => onChange(overlap: v),
          ),
          const SizedBox(height: 8),
          _SliderRow(
            colors: colors,
            label: 'Rotation',
            value: rotation,
            min: -180,
            max: 180,
            suffix: '°',
            onChanged: (v) => onChange(rotation: v),
          ),
        ],
      ),
    );
  }
}

class _IntStepper extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _IntStepper({
    required this.colors,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textSecondary)),
        const SizedBox(height: 4),
        Row(
          children: [
            _StepperButton(
              colors: colors,
              icon: LucideIcons.minus,
              enabled: value > min,
              onTap: () => onChanged(value - 1),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            _StepperButton(
              colors: colors,
              icon: LucideIcons.plus,
              enabled: value < max,
              onTap: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepperButton({
    required this.colors,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            color: enabled ? colors.surfaceAlt : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 14,
            color: enabled ? colors.textPrimary : colors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final double value;
  final double min;
  final double max;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.colors,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textSecondary)),
            const Spacer(),
            Text(
              '${value.toStringAsFixed(0)}$suffix',
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.primary,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            activeColor: colors.primary,
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final NightshadeColors colors;
  final int activePanels;
  final String gridLabel;
  final String panelArcminLabel;
  final String overlapLabel;
  final double exposureSeconds;
  final int exposuresPerPanel;
  final double estTimeHours;
  final int totalExposures;

  const _StatsCard({
    required this.colors,
    required this.activePanels,
    required this.gridLabel,
    required this.panelArcminLabel,
    required this.overlapLabel,
    required this.exposureSeconds,
    required this.exposuresPerPanel,
    required this.estTimeHours,
    required this.totalExposures,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Plan summary', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _row('Active panels:', '$activePanels'),
          _row('Grid:', gridLabel),
          _row('Panel size:', panelArcminLabel),
          _row('Overlap:', overlapLabel),
          const Divider(height: 16),
          _row(
              'Est. time (${exposureSeconds.toStringAsFixed(0)}s x $exposuresPerPanel):',
              '${estTimeHours.toStringAsFixed(1)} h',
              highlight: true),
          _row('Total exposures:', '$totalExposures'),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize12,
                color: colors.textSecondary,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              )),
          Text(
            value,
            style: TextStyle(
              fontSize: highlight ? NightshadeTypography.fontSize14 : NightshadeTypography.fontSize12,
              color: highlight ? colors.accent : colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdvancedPanel extends StatelessWidget {
  final NightshadeColors colors;
  final bool expanded;
  final double centerRa;
  final double centerDec;
  final double panelWidthArcmin;
  final double panelHeightArcmin;
  final VoidCallback onToggle;
  final void Function({
    double? centerRa,
    double? centerDec,
    double? panelWidthArcmin,
    double? panelHeightArcmin,
  }) onChanged;

  const _AdvancedPanel({
    required this.colors,
    required this.expanded,
    required this.centerRa,
    required this.centerDec,
    required this.panelWidthArcmin,
    required this.panelHeightArcmin,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(LucideIcons.sliders, size: 14, color: colors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Advanced (numerical)',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        )),
                  ),
                  Icon(
                    expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 14,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  _NumberField(
                    colors: colors,
                    label: 'Center RA (hours)',
                    value: centerRa,
                    min: 0,
                    max: 24,
                    decimals: 4,
                    onChanged: (v) => onChanged(centerRa: v),
                  ),
                  const SizedBox(height: 10),
                  _NumberField(
                    colors: colors,
                    label: 'Center Dec (degrees)',
                    value: centerDec,
                    min: -90,
                    max: 90,
                    decimals: 4,
                    onChanged: (v) => onChanged(centerDec: v),
                  ),
                  const SizedBox(height: 10),
                  _NumberField(
                    colors: colors,
                    label: 'Panel width (arcmin)',
                    value: panelWidthArcmin,
                    min: 1,
                    max: 360,
                    decimals: 1,
                    onChanged: (v) => onChanged(panelWidthArcmin: v),
                  ),
                  const SizedBox(height: 10),
                  _NumberField(
                    colors: colors,
                    label: 'Panel height (arcmin)',
                    value: panelHeightArcmin,
                    min: 1,
                    max: 360,
                    decimals: 1,
                    onChanged: (v) => onChanged(panelHeightArcmin: v),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  final NightshadeColors colors;
  final String label;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final ValueChanged<double> onChanged;

  const _NumberField({
    required this.colors,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    required this.onChanged,
  });

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = TextEditingController(
        text: widget.value.toStringAsFixed(widget.decimals));
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    final external = widget.value.toStringAsFixed(widget.decimals);
    final current = double.tryParse(_ctl.text);
    if (current == null || (current - widget.value).abs() > 1e-3) {
      _ctl.text = external;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctl,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: OutlineInputBorder(
            borderSide: BorderSide(color: widget.colors.border)),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: (text) {
        final parsed = double.tryParse(text);
        if (parsed != null && parsed >= widget.min && parsed <= widget.max) {
          widget.onChanged(parsed);
        }
      },
    );
  }
}

// ============================================================================
// Visual planner — interactive sky view with FOV panels
// ============================================================================
