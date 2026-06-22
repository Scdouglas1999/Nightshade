// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Search field, filter chips (object type, constellation, magnitude, size, altitude, moon separation), sort dropdown, reset chip, the _ControlChip primitive, and the shared _showAngleSlider helper used by the angle-based filter sheets.
part of '../planner_screen.dart';

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;

  /// On phone the field tightens (shorter, smaller hint) so search + the
  /// Filters button fit one row and the controls bar stays a single strip.
  final bool compact;

  const _SearchField({
    required this.controller,
    required this.colors,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // On a narrow phone row the long hint never fully shows anyway; a short
    // hint reads better and avoids an awkward mid-word clip.
    final hint = compact
        ? 'Search catalogs'
        : 'Search tonight candidates and installed catalogs';
    return SizedBox(
      height: 36,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(
            fontSize: NightshadeTypography.fontSize13,
            color: colors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(
              fontSize: NightshadeTypography.fontSize13,
              color: colors.textMuted),
          prefixIcon:
              Icon(LucideIcons.search, size: 16, color: colors.textMuted),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  iconSize: 14,
                  icon: Icon(LucideIcons.x, color: colors.textMuted),
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: colors.surfaceAlt,
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            borderSide: BorderSide(color: colors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            borderSide: BorderSide(color: colors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            borderSide: BorderSide(color: colors.primary),
          ),
        ),
      ),
    );
  }
}

class _ObjectTypeMultiSelect extends ConsumerWidget {
  final NightshadeColors colors;
  final Set<String> selected;

  const _ObjectTypeMultiSelect({required this.colors, required this.selected});

  static const _options = <String>[
    'galaxy',
    'nebula',
    'cluster',
    'planetary',
    'supernova remnant',
    'comet',
    'asteroid',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = selected.isEmpty
        ? 'Type: any'
        : 'Type: ${selected.map(_displayLabel).join(', ')}';

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.shapes,
      label: label,
      active: selected.isNotEmpty,
      onTap: () async {
        final result = await showModalBottomSheet<Set<String>>(
          context: context,
          backgroundColor: colors.surface,
          builder: (sheetCtx) {
            final draft = Set<String>.of(selected);
            return StatefulBuilder(
              builder: (sheetCtx, setSheetState) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Object types',
                          style: NightshadeTypography.h5.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: NightshadeTokens.spaceMd),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _options
                              .map((opt) => FilterChip(
                                    label: Text(_displayLabel(opt)),
                                    selected: draft.contains(opt),
                                    onSelected: (on) {
                                      setSheetState(() {
                                        if (on) {
                                          draft.add(opt);
                                        } else {
                                          draft.remove(opt);
                                        }
                                      });
                                    },
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: NightshadeTokens.spaceLg),
                        Row(
                          children: [
                            NightshadeButton(
                              label: 'Clear',
                              variant: ButtonVariant.ghost,
                              size: ButtonSize.small,
                              onPressed: () {
                                setSheetState(draft.clear);
                              },
                            ),
                            const Spacer(),
                            NightshadeButton(
                              label: 'Apply',
                              variant: ButtonVariant.primary,
                              size: ButtonSize.small,
                              onPressed: () =>
                                  Navigator.of(sheetCtx).pop(draft),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state = notifier.state.copyWith(selectedObjectTypes: result);
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }

  static String _displayLabel(String key) {
    return key
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _ConstellationDropdown extends ConsumerWidget {
  final NightshadeColors colors;
  final List<String> available;
  final String? selected;

  const _ConstellationDropdown({
    required this.colors,
    required this.available,
    required this.selected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Constellation: any'),
      ),
      for (final c in available)
        DropdownMenuItem<String?>(
          value: c,
          child: Text('Constellation: $c'),
        ),
    ];

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected == null
            ? colors.surfaceAlt
            : NightshadeDecorations.tintedBadge(colors.primary).color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
        border: Border.all(
          color: selected == null
              ? colors.border
              : colors.primary.withValues(alpha: 0.5),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected,
          items: items,
          isDense: true,
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textPrimary),
          dropdownColor: colors.surface,
          iconSize: 14,
          onChanged: (value) {
            final notifier = ref.read(suggestionFilterProvider.notifier);
            notifier.state = notifier.state.copyWith(
              selectedConstellations:
                  value == null ? <String>{} : <String>{value},
            );
            ref.read(_plannerVisibleCountProvider.notifier).state =
                _kPlannerPageSize;
          },
        ),
      ),
    );
  }
}

class _MagnitudeRangeControl extends ConsumerWidget {
  final NightshadeColors colors;
  final (double, double)? bounds;
  final double? min;
  final double? max;

  const _MagnitudeRangeControl({
    required this.colors,
    required this.bounds,
    required this.min,
    required this.max,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = min != null || max != null;
    String label;
    if (active) {
      final lo = min?.toStringAsFixed(1) ?? 'any';
      final hi = max?.toStringAsFixed(1) ?? 'any';
      label = 'Mag $lo–$hi';
    } else {
      label = 'Magnitude: any';
    }

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.sparkles,
      label: label,
      active: active,
      onTap: () async {
        final actualBounds = bounds ?? (-2.0, 18.0);
        final result = await showDialog<(double?, double?)>(
          context: context,
          builder: (dCtx) {
            double lo = min ?? actualBounds.$1;
            double hi = max ?? actualBounds.$2;
            return StatefulBuilder(
              builder: (dCtx, setDState) {
                return AlertDialog(
                  backgroundColor: colors.surface,
                  title: Text(
                    'Magnitude range',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Brighter ${lo.toStringAsFixed(1)} – Dimmer ${hi.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: colors.textSecondary,
                        ),
                      ),
                      RangeSlider(
                        values: RangeValues(lo, hi),
                        min: actualBounds.$1,
                        max: actualBounds.$2,
                        divisions: 40,
                        labels: RangeLabels(
                          lo.toStringAsFixed(1),
                          hi.toStringAsFixed(1),
                        ),
                        onChanged: (v) {
                          setDState(() {
                            lo = v.start;
                            hi = v.end;
                          });
                        },
                      ),
                    ],
                  ),
                  actions: [
                    NightshadeButton(
                      label: 'Clear',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(dCtx).pop((null, null)),
                    ),
                    NightshadeButton(
                      label: 'Apply',
                      variant: ButtonVariant.primary,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(dCtx).pop((lo, hi)),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state = notifier.state.copyWith(
            minMagnitude: () => result.$1,
            maxMagnitude: () => result.$2,
          );
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }
}

/// Sensible default bounds for the size slider when the data-derived range
/// is unavailable (e.g. before suggestions resolve). Covers planetary nebulae
/// (sub-arcminute) up to the largest M-class targets (~600').
const double _kSizeFilterMinArcmin = 0.1;
const double _kSizeFilterMaxArcmin = 600.0;

class _SizeRangeControl extends ConsumerWidget {
  final NightshadeColors colors;
  final (double, double)? bounds;
  final double? min;
  final double? max;

  const _SizeRangeControl({
    required this.colors,
    required this.bounds,
    required this.min,
    required this.max,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = min != null || max != null;
    final label = active
        ? 'Size ${_formatSizeLabel(min)}–${_formatSizeLabel(max)}'
        : 'Size: any';

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.ruler,
      label: label,
      active: active,
      onTap: () async {
        // Clamp the data-derived bounds into the slider's hard limits so the
        // RangeSlider doesn't assert when the catalog reports outliers.
        final dataLo = bounds?.$1 ?? _kSizeFilterMinArcmin;
        final dataHi = bounds?.$2 ?? _kSizeFilterMaxArcmin;
        final sliderLo =
            dataLo.clamp(_kSizeFilterMinArcmin, _kSizeFilterMaxArcmin);
        final sliderHi =
            dataHi.clamp(_kSizeFilterMinArcmin, _kSizeFilterMaxArcmin);
        final actualBounds = (
          sliderLo < _kSizeFilterMaxArcmin ? sliderLo : _kSizeFilterMinArcmin,
          sliderHi > sliderLo ? sliderHi : _kSizeFilterMaxArcmin,
        );

        final result = await showDialog<(double?, double?)>(
          context: context,
          builder: (dCtx) {
            double lo = (min ?? actualBounds.$1)
                .clamp(actualBounds.$1, actualBounds.$2);
            double hi = (max ?? actualBounds.$2)
                .clamp(actualBounds.$1, actualBounds.$2);
            return StatefulBuilder(
              builder: (dCtx, setDState) {
                return AlertDialog(
                  backgroundColor: colors.surface,
                  title: Text(
                    'Angular size range',
                    style: TextStyle(color: colors.textPrimary),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${_formatSizeLabel(lo)} – ${_formatSizeLabel(hi)}',
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize12,
                          color: colors.textSecondary,
                        ),
                      ),
                      RangeSlider(
                        values: RangeValues(lo, hi),
                        min: actualBounds.$1,
                        max: actualBounds.$2,
                        divisions: 60,
                        labels: RangeLabels(
                          _formatSizeLabel(lo),
                          _formatSizeLabel(hi),
                        ),
                        onChanged: (v) {
                          setDState(() {
                            lo = v.start;
                            hi = v.end;
                          });
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Targets without recorded size data are excluded '
                          'while this filter is active.',
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize11,
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    NightshadeButton(
                      label: 'Clear',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(dCtx).pop((null, null)),
                    ),
                    NightshadeButton(
                      label: 'Apply',
                      variant: ButtonVariant.primary,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(dCtx).pop((lo, hi)),
                    ),
                  ],
                );
              },
            );
          },
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state = notifier.state.copyWith(
            minSizeArcmin: () => result.$1,
            maxSizeArcmin: () => result.$2,
          );
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }
}

/// Format an arcminute value for compact display in size chips/labels.
/// Sub-arcminute → arcseconds (`45"`); >=1' → arcminutes with one decimal
/// (`12.4'`). Nulls and non-positive values render as "any".
String _formatSizeLabel(double? arcmin) {
  if (arcmin == null || arcmin <= 0) return 'any';
  if (arcmin < 1.0) {
    final arcsec = arcmin * 60.0;
    return '${arcsec.toStringAsFixed(0)}"';
  }
  return "${arcmin.toStringAsFixed(1)}'";
}

class _MinAltitudeControl extends ConsumerWidget {
  final NightshadeColors colors;
  final double? value;

  const _MinAltitudeControl({required this.colors, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value != null;
    final label =
        active ? 'Alt now ≥ ${value!.toStringAsFixed(0)}°' : 'Alt now: any';

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.mountain,
      label: label,
      active: active,
      onTap: () async {
        // Why: derive a sensible default from the user's horizon profile so
        // first-time users land on something that matches their site.
        final horizonProfile = ref.read(horizonProfileProvider);
        double seed = value ?? 0.0;
        if (!active && !horizonProfile.isFlat) {
          // Pick the maximum horizon obstruction as a starting guess.
          double maxAlt = 0.0;
          for (int az = 0; az < 360; az += 15) {
            final h = horizonProfile.altitudeAtAzimuth(az.toDouble());
            if (h > maxAlt) maxAlt = h;
          }
          seed = maxAlt;
        }
        final result = await _showAngleSlider(
          context: context,
          colors: colors,
          title: 'Minimum altitude right now',
          unit: '°',
          initial: seed,
          min: 0,
          max: 89,
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state =
              notifier.state.copyWith(minCurrentAltitude: () => result);
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }
}

class _MoonSeparationControl extends ConsumerWidget {
  final NightshadeColors colors;
  final double? value;

  const _MoonSeparationControl({required this.colors, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = value != null;
    final label = active ? 'Moon ≥ ${value!.toStringAsFixed(0)}°' : 'Moon: any';

    return _ControlChip(
      colors: colors,
      icon: LucideIcons.moon,
      label: label,
      active: active,
      onTap: () async {
        final result = await _showAngleSlider(
          context: context,
          colors: colors,
          title: 'Minimum moon separation',
          unit: '°',
          initial: value ?? 30.0,
          min: 0,
          max: 180,
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state =
              notifier.state.copyWith(minMoonDistance: () => result);
          ref.read(_plannerVisibleCountProvider.notifier).state =
              _kPlannerPageSize;
        }
      },
    );
  }
}

class _SortDropdown extends ConsumerWidget {
  final NightshadeColors colors;
  final PlannerSortMode value;

  const _SortDropdown({required this.colors, required this.value});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const labels = {
      PlannerSortMode.score: 'Sort: Score',
      PlannerSortMode.altitude: 'Sort: Altitude',
      PlannerSortMode.magnitude: 'Sort: Magnitude',
      PlannerSortMode.size: 'Sort: Size (largest)',
      PlannerSortMode.constellation: 'Sort: Constellation',
      PlannerSortMode.objectType: 'Sort: Object type',
      PlannerSortMode.catalogId: 'Sort: Catalog ID',
    };

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
        border: Border.all(color: colors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PlannerSortMode>(
          value: value,
          items: [
            for (final m in PlannerSortMode.values)
              DropdownMenuItem(value: m, child: Text(labels[m]!)),
          ],
          isDense: true,
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textPrimary),
          dropdownColor: colors.surface,
          iconSize: 14,
          onChanged: (v) {
            if (v == null) return;
            final notifier = ref.read(suggestionFilterProvider.notifier);
            notifier.state = notifier.state.copyWith(plannerSort: () => v);
          },
        ),
      ),
    );
  }
}

class _ResetChip extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onPressed;

  const _ResetChip({required this.colors, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return _ControlChip(
      colors: colors,
      icon: LucideIcons.rotateCcw,
      label: 'Reset filters',
      active: true,
      onTap: onPressed,
    );
  }
}

class _ControlChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ControlChip({
    required this.colors,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? NightshadeDecorations.tintedBadge(
            colors.primary,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          ).color
        : colors.surfaceAlt;
    final border =
        active ? colors.primary.withValues(alpha: 0.5) : colors.border;
    final fg = active ? colors.primary : colors.textSecondary;

    return InkWell(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: NightshadeTypography.labelSm.copyWith(
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<double?> _showAngleSlider({
  required BuildContext context,
  required NightshadeColors colors,
  required String title,
  required String unit,
  required double initial,
  required double min,
  required double max,
}) async {
  return showDialog<double>(
    context: context,
    builder: (dCtx) {
      double val = initial.clamp(min, max);
      return StatefulBuilder(
        builder: (dCtx, setDState) {
          return AlertDialog(
            backgroundColor: colors.surface,
            title: Text(title, style: TextStyle(color: colors.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${val.toStringAsFixed(0)}$unit',
                  style: NightshadeTypography.h4.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                Slider(
                  value: val,
                  min: min,
                  max: max,
                  divisions: (max - min).round(),
                  label: '${val.toStringAsFixed(0)}$unit',
                  onChanged: (v) => setDState(() => val = v),
                ),
              ],
            ),
            actions: [
              NightshadeButton(
                label: 'Clear',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: () => Navigator.of(dCtx).pop(-1.0),
              ),
              NightshadeButton(
                label: 'Apply',
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
                onPressed: () => Navigator.of(dCtx).pop(val),
              ),
            ],
          );
        },
      );
    },
  ).then((value) {
    if (value == null) return null;
    // -1 sentinel from the Clear button → tell caller to reset to null.
    if (value < 0) return double.nan;
    return value;
  }).then((v) {
    if (v == null) return null;
    if (v.isNaN) return null;
    return v;
  });
}
