import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// A per-filter narrowband master available for palette compositing.
///
/// Lightweight UI reference to a finished single-filter master (Ha / OIII / SII /
/// …). The controller surfaces one of these per per-filter master so the mixer
/// can present a row of R/G/B weight sliders per channel.
///
/// Shared contract type (the controller author owns the canonical definition and
/// exports it); kept minimal so the two definitions are structurally identical.
class NarrowbandChannelRef {
  /// Stable id of the backing master (used by the controller to resolve the
  /// FITS when combining).
  final int masterId;

  /// Filter token (e.g. `Ha`, `OIII`, `SII`) — drives the channel label.
  final String filter;

  /// Display label for the channel row; falls back to [filter] when empty.
  final String label;

  const NarrowbandChannelRef({
    required this.masterId,
    required this.filter,
    this.label = '',
  });

  /// The label to render for this channel.
  String get displayLabel => label.trim().isNotEmpty ? label.trim() : filter;
}

/// A named narrowband mapping preset (SHO, HOO, …) describing, per output RGB
/// channel, the contribution of each input filter.
class _NarrowbandPreset {
  final String name;

  /// Maps a filter token to its [r, g, b] contribution (0..1).
  final Map<String, List<double>> filterToRgb;

  const _NarrowbandPreset(this.name, this.filterToRgb);
}

/// The classic Hubble (SHO) and bicolor (HOO) palettes.
///
/// SHO → R=SII, G=Ha, B=OIII. HOO → R=Ha, G=OIII, B=OIII.
const List<_NarrowbandPreset> _kPresets = [
  _NarrowbandPreset('SHO', {
    'SII': [1, 0, 0],
    'Ha': [0, 1, 0],
    'OIII': [0, 0, 1],
  }),
  _NarrowbandPreset('HOO', {
    'Ha': [1, 0, 0],
    'OIII': [0, 1, 1],
  }),
];

/// Live narrowband palette mixer: pick a preset (SHO / HOO) or hand-tune the
/// per-channel R/G/B weights, see the resulting combine matrix, and Apply to run
/// the native channel combine through the controller.
///
/// The panel is a pure design-system surface: a [NightshadeCard] with preset
/// chips, one slider row per [NarrowbandChannelRef], a rendered weight matrix,
/// and an Apply [NightshadeButton]. It holds the editable weights locally and
/// hands them back via [onApply] as `(paletteOrCustom, weights)` where `weights`
/// is row-major `[channel][r, g, b]` aligned to [channels].
class NarrowbandMixerPanel extends StatefulWidget {
  /// The per-filter masters available to mix, in display order.
  final List<NarrowbandChannelRef> channels;

  /// Invoked on Apply with the active palette name (or `'custom'`) and the
  /// row-major `[channel][r, g, b]` weight matrix.
  final void Function(String paletteOrCustom, List<List<double>> weights)
      onApply;

  const NarrowbandMixerPanel({
    super.key,
    required this.channels,
    required this.onApply,
  });

  @override
  State<NarrowbandMixerPanel> createState() => _NarrowbandMixerPanelState();
}

class _NarrowbandMixerPanelState extends State<NarrowbandMixerPanel> {
  /// Editable per-channel weights, row-major `[channel][r, g, b]`.
  late List<List<double>> _weights;

  /// The active preset name, or `'custom'` once a slider is touched.
  String _palette = 'custom';

  @override
  void initState() {
    super.initState();
    _weights = _seedWeights();
    // Adopt the first preset that maps cleanly onto the available channels.
    for (final preset in _kPresets) {
      if (_presetApplies(preset)) {
        _applyPreset(preset, notify: false);
        break;
      }
    }
  }

  @override
  void didUpdateWidget(covariant NarrowbandMixerPanel old) {
    super.didUpdateWidget(old);
    if (old.channels.length != widget.channels.length) {
      setState(() {
        _weights = _seedWeights();
        _palette = 'custom';
      });
    }
  }

  List<List<double>> _seedWeights() =>
      List.generate(widget.channels.length, (_) => <double>[0, 0, 0]);

  /// Canonicalise a raw filter label to the preset key it maps to, mirroring the
  /// controller's fuzzy narrowband hints so real names ('Ha 7nm', 'O3', 'Sii')
  /// resolve to 'Ha' / 'OIII' / 'SII'. Returns null for non-narrowband labels.
  static String? _canon(String f) {
    final n = f.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (n.startsWith('halpha') || n.startsWith('ha')) return 'Ha';
    if (n.startsWith('oiii') || n.startsWith('o3')) return 'OIII';
    if (n.startsWith('sii') || n.startsWith('s2')) return 'SII';
    return null;
  }

  bool _presetApplies(_NarrowbandPreset preset) => widget.channels.any((c) {
        final key = _canon(c.filter);
        return key != null && preset.filterToRgb.containsKey(key);
      });

  void _applyPreset(_NarrowbandPreset preset, {bool notify = true}) {
    final next = List.generate(widget.channels.length, (i) {
      final key = _canon(widget.channels[i].filter);
      final mapped = key == null ? null : preset.filterToRgb[key];
      return mapped != null ? List<double>.from(mapped) : <double>[0, 0, 0];
    });
    void apply() {
      _weights = next;
      _palette = preset.name;
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _setWeight(int channel, int rgb, double value) {
    setState(() {
      _weights[channel][rgb] = value;
      _palette = 'custom';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    if (widget.channels.isEmpty) {
      return const NightshadeCard(
        child: EmptyState(
          icon: NightshadeIcons.palette,
          title: 'No narrowband masters',
          body: 'Integrate per-filter masters (Ha / OIII / SII) to mix a '
              'narrowband palette.',
        ),
      );
    }

    return NightshadeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(colors),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _presetChips(colors),
          const SizedBox(height: NightshadeTokens.spaceLg),
          for (var i = 0; i < widget.channels.length; i++) ...[
            _channelRow(colors, i),
            if (i < widget.channels.length - 1)
              const SizedBox(height: NightshadeTokens.spaceMd),
          ],
          const SizedBox(height: NightshadeTokens.spaceLg),
          _matrixPreview(colors),
          const SizedBox(height: NightshadeTokens.spaceLg),
          Align(
            alignment: Alignment.centerRight,
            child: NightshadeButton(
              label: 'Apply palette',
              icon: NightshadeIcons.check,
              onPressed: () => widget.onApply(
                _palette,
                _weights.map((row) => List<double>.from(row)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(NightshadeColors colors) {
    return Row(
      children: [
        Icon(NightshadeIcons.palette,
            size: NightshadeTokens.iconSm, color: colors.primary),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          'Narrowband palette',
          style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
        ),
        const Spacer(),
        Text(
          _palette == 'custom' ? 'Custom mix' : '$_palette preset',
          style: NightshadeTypography.bodySm.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }

  Widget _presetChips(NightshadeColors colors) {
    return Wrap(
      spacing: NightshadeTokens.spaceSm,
      runSpacing: NightshadeTokens.spaceSm,
      children: [
        for (final preset in _kPresets)
          _PresetChip(
            label: preset.name,
            selected: _palette == preset.name,
            enabled: _presetApplies(preset),
            onTap: () => _applyPreset(preset),
          ),
      ],
    );
  }

  Widget _channelRow(NightshadeColors colors, int index) {
    final channel = widget.channels[index];
    const rgbLabels = ['R', 'G', 'B'];
    final rgbColors = [colors.error, colors.success, colors.info];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(NightshadeIcons.filter,
                size: NightshadeTokens.iconXs, color: colors.textSecondary),
            const SizedBox(width: NightshadeTokens.spaceXs),
            Text(
              channel.displayLabel,
              style: NightshadeTypography.labelStrong
                  .copyWith(color: colors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceXs),
        for (var rgb = 0; rgb < 3; rgb++)
          _WeightSlider(
            channelLabel: rgbLabels[rgb],
            channelColor: rgbColors[rgb],
            value: _weights[index][rgb],
            onChanged: (v) => _setWeight(index, rgb, v),
          ),
      ],
    );
  }

  Widget _matrixPreview(NightshadeColors colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
        border: Border.all(color: colors.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Combine matrix',
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          for (var i = 0; i < widget.channels.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
              child: Text(
                '${widget.channels[i].displayLabel}  -> '
                'R ${_fmt(_weights[i][0])}  '
                'G ${_fmt(_weights[i][1])}  '
                'B ${_fmt(_weights[i][2])}',
                style: NightshadeTypography.monoSm
                    .copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  static String _fmt(double v) => v.toStringAsFixed(2);
}

/// A selectable preset chip (SHO / HOO). Disabled when no available channel
/// matches the preset's filter map.
class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final accent = colors.primary;
    final fg = !enabled
        ? colors.textMuted.withValues(alpha: NightshadeTokens.opacityDisabled)
        : selected
            ? colors.onPrimary
            : colors.textSecondary;
    final bg = selected ? accent : colors.surfaceAlt;
    return Opacity(
      opacity: enabled ? 1 : NightshadeTokens.opacityMuted,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceSm,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
            border: Border.all(
              color: selected ? accent : colors.border.withValues(alpha: 0.75),
            ),
          ),
          child: Text(
            label,
            style: NightshadeTypography.buttonSm.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}

/// A single labelled 0..1 weight slider for one R/G/B contribution.
class _WeightSlider extends StatelessWidget {
  final String channelLabel;
  final Color channelColor;
  final double value;
  final ValueChanged<double> onChanged;

  const _WeightSlider({
    required this.channelLabel,
    required this.channelColor,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      children: [
        SizedBox(
          width: NightshadeTokens.space2xl,
          child: Text(
            channelLabel,
            style:
                NightshadeTypography.labelStrong.copyWith(color: channelColor),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: channelColor,
              inactiveTrackColor: colors.border.withValues(alpha: 0.5),
              thumbColor: channelColor,
              overlayColor: channelColor.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(0.0, 1.0),
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: NightshadeTokens.space4xl,
          child: Text(
            value.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: NightshadeTypography.monoSm
                .copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
  }
}
