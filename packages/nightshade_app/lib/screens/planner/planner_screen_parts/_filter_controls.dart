// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Search field, filter chips (object type, constellation, magnitude, size, altitude, moon separation), sort dropdown, reset chip, the _ControlChip primitive, and the shared _showAngleSlider helper used by the angle-based filter sheets.
part of '../planner_screen.dart';

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;
  final double height;

  /// On phone the field tightens (shorter, smaller hint) so search + the
  /// Filters button fit one row and the controls bar stays a single strip.
  final bool compact;

  const _SearchField({
    required this.controller,
    required this.colors,
    required this.onChanged,
    this.compact = false,
    this.height = 36,
  });

  @override
  Widget build(BuildContext context) {
    // On a narrow phone row the long hint never fully shows anyway; a short
    // hint reads better and avoids an awkward mid-word clip.
    final hint = compact
        ? 'Search catalogs'
        : 'Search tonight candidates and installed catalogs';
    return SizedBox(
      height: height,
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
        final result = await _showObjectTypeDialog(
          context: context,
          colors: colors,
          selected: selected,
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

/// Object-type multi-select sheet.
///
/// Returns `null` when dismissed, otherwise the chosen set.
Future<Set<String>?> _showObjectTypeDialog({
  required BuildContext context,
  required NightshadeColors colors,
  required Set<String> selected,
}) {
  return showDialog<Set<String>>(
    context: context,
    builder: (dialogCtx) {
      final draft = Set<String>.of(selected);
      return StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: colors.surface,
            title: Text(
              'Object types',
              style: NightshadeTypography.h5.copyWith(
                color: colors.textPrimary,
              ),
            ),
            content: SizedBox(
              width: dialogMaxWidth(context, 380),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _ObjectTypeMultiSelect._options
                    .map((opt) => FilterChip(
                          label: Text(
                            _ObjectTypeMultiSelect._displayLabel(opt),
                          ),
                          selected: draft.contains(opt),
                          showCheckmark: false,
                          onSelected: (on) {
                            setDialogState(() {
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
            ),
            actions: [
              NightshadeButton(
                label: 'Clear',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
                onPressed: () => setDialogState(draft.clear),
              ),
              NightshadeButton(
                label: 'Apply',
                variant: ButtonVariant.primary,
                size: ButtonSize.small,
                onPressed: () => Navigator.of(dialogCtx).pop(draft),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Test-only seam exposing the constellation picker.
///
/// Returns the dialog's result: null for a barrier dismiss, the empty string
/// for "Any constellation", otherwise the chosen abbreviation.
@visibleForTesting
Future<String?> showConstellationPickerForTest({
  required BuildContext context,
  required NightshadeColors colors,
  required List<String> available,
  String? selected,
}) {
  return showDialog<String?>(
    context: context,
    builder: (dCtx) => _ConstellationPickerDialog(
      colors: colors,
      available: available,
      selected: selected,
    ),
  );
}

/// Test-only seam exposing the object-types sheet.
///
/// Same rationale as [showAngleSliderForTest]: the sheet is a private helper
/// inside a `part` file, and pumping the whole PlannerScreen runs a 1 s sky
/// clock that never settles. Nothing in production calls this.
@visibleForTesting
Future<Set<String>?> showObjectTypeDialogForTest({
  required BuildContext context,
  required NightshadeColors colors,
  required Set<String> selected,
}) {
  return _showObjectTypeDialog(
    context: context,
    colors: colors,
    selected: selected,
  );
}

/// Constellation filter.
///
/// Catalog rows store the three-letter IAU abbreviation, and this control used
/// to be a bare [DropdownButton] of up to 88 of them ("And", "Aql", "CVn"…)
/// with the words "Constellation: " repeated on every row and no way to type.
/// Finding a constellation meant knowing its abbreviation and scrolling. It is
/// now a searchable dialog, like every other filter chip in this row, listing
/// the full name with the abbreviation in tow so both spellings are matchable.
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
    final active = selected != null;
    return _ControlChip(
      colors: colors,
      icon: LucideIcons.star,
      label: active ? constellationFullName(selected!) : 'Constellation: any',
      active: active,
      onTap: () async {
        final result = await showDialog<String?>(
          context: context,
          builder: (dCtx) => _ConstellationPickerDialog(
            colors: colors,
            available: available,
            selected: selected,
          ),
        );
        // A barrier dismiss returns null and must NOT clear the filter; the
        // dialog signals both "any" and a pick through a wrapper.
        if (result == null) return;
        final picked = result.isEmpty ? null : result;
        final notifier = ref.read(suggestionFilterProvider.notifier);
        notifier.state = notifier.state.copyWith(
          selectedConstellations:
              picked == null ? <String>{} : <String>{picked},
        );
        ref.read(_plannerVisibleCountProvider.notifier).state =
            _kPlannerPageSize;
      },
    );
  }
}

class _ConstellationPickerDialog extends StatefulWidget {
  final NightshadeColors colors;
  final List<String> available;
  final String? selected;

  const _ConstellationPickerDialog({
    required this.colors,
    required this.available,
    required this.selected,
  });

  @override
  State<_ConstellationPickerDialog> createState() =>
      _ConstellationPickerDialogState();
}

class _ConstellationPickerDialogState
    extends State<_ConstellationPickerDialog> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    // Sorted by the name the user reads, not by the abbreviation, so the list
    // is alphabetical on screen.
    final entries = [
      for (final abbr in widget.available) (abbr, constellationFullName(abbr)),
    ]..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? entries
        : entries
            .where((e) =>
                e.$2.toLowerCase().contains(q) ||
                e.$1.toLowerCase().contains(q))
            .toList();

    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Constellation',
        style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
      ),
      content: SizedBox(
        width: dialogMaxWidth(context, 380),
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SearchField(
              controller: _search,
              colors: colors,
              compact: true,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              '${entries.length} constellation'
              '${entries.length == 1 ? '' : 's'} in tonight’s candidates',
              style: NightshadeTypography.caption.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXs),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        'No constellation matches "$_query".',
                        style: NightshadeTypography.caption.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final (abbr, name) = matches[i];
                        final isSelected = widget.selected == abbr;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          title: Text(
                            '$name ($abbr)',
                            style: NightshadeTypography.bodySm.copyWith(
                              color: isSelected
                                  ? colors.primary
                                  : colors.textPrimary,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(abbr),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        NightshadeButton(
          label: 'Any constellation',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
          // Empty string, not null: null is what a barrier dismiss returns and
          // must stay distinguishable from "clear the filter".
          onPressed: () => Navigator.of(context).pop(''),
        ),
      ],
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
          isSet: active,
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state = notifier.state.copyWith(
            minCurrentAltitude: () => result.isNaN ? null : result,
          );
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
          isSet: active,
        );
        if (result != null) {
          final notifier = ref.read(suggestionFilterProvider.notifier);
          notifier.state = notifier.state.copyWith(
            minMoonDistance: () => result.isNaN ? null : result,
          );
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

    // Declare the chip. Read off the running app 2026-08-09, all six planner
    // filters — Type, Constellation, Magnitude, Size, Alt now, Moon — plus the
    // Sort control came off the accessibility tree as `[DISABLED]` while the
    // planner was fully live and the scheduler was returning picks. A bare
    // `InkWell` publishes a focusable node that never sets isEnabled, and
    // nothing in the subtree carries the on/off state either, so a
    // screen-reader user is told the filter row is dead and is never told
    // which filters are applied.
    return Semantics(
      container: true,
      button: true,
      enabled: true,
      selected: active,
      label: label,
      onTap: onTap,
      child: InkWell(
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
      ),
    );
  }
}

/// [isSet] tells the sheet whether the filter it edits is currently ACTIVE.
///
/// When it is not, the sheet must not present [initial] as if the user had
/// chosen it. The moon chip read "Moon: any" while this dialog opened with the
/// slider parked at 30 deg and the readout showing "30°", so pressing Apply
/// without touching anything silently changed the filter — live, the chip flipped
/// to "Moon >= 30" and the candidate count dropped from 1202 to 1174 on a value
/// the user never picked. [initial] is still honoured as the slider's STARTING
/// POSITION (a useful hint, and for altitude it is derived from the horizon
/// profile), but until the slider is actually moved the readout says "Any" and
/// Apply is disabled, so the only way to set a value is to choose one.
Future<double?> _showAngleSlider({
  required BuildContext context,
  required NightshadeColors colors,
  required String title,
  required String unit,
  required double initial,
  required double min,
  required double max,
  required bool isSet,
}) async {
  return showDialog<double>(
    context: context,
    builder: (dCtx) {
      double val = initial.clamp(min, max);
      // An already-set filter may be re-applied unchanged (a harmless no-op), so
      // only an UNSET one starts untouched.
      bool touched = isSet;
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
                  touched ? '${val.toStringAsFixed(0)}$unit' : 'Any',
                  style: NightshadeTypography.h4.copyWith(
                    color: touched ? colors.textPrimary : colors.textMuted,
                  ),
                ),
                Slider(
                  value: val,
                  min: min,
                  max: max,
                  divisions: (max - min).round(),
                  label: '${val.toStringAsFixed(0)}$unit',
                  onChanged: (v) => setDState(() {
                    val = v;
                    touched = true;
                  }),
                ),
                if (!touched)
                  Text(
                    'No limit is set. Drag the slider to choose one.',
                    style: NightshadeTypography.caption.copyWith(
                      color: colors.textMuted,
                    ),
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
                // Disabled until there is a real choice to apply, so Apply can
                // never commit a value the sheet invented.
                onPressed: touched ? () => Navigator.of(dCtx).pop(val) : null,
              ),
            ],
          );
        },
      );
    },
  ).then((value) {
    if (value == null) return null;
    // -1 sentinel from the Clear button → NaN tells the caller to clear the
    // filter, distinct from a null barrier-dismiss which is a no-op.
    if (value < 0) return double.nan;
    return value;
  });
}

/// Test-only seam exposing the shared angle-filter sheet.
///
/// The sheet is what regressed (it applied a value the user never chose), but it
/// is a private helper inside a `part` file, so the only other way to exercise it
/// is to pump the whole `PlannerScreen` — which runs a 1 s periodic sky clock and
/// therefore never settles, making such a test slow and flaky rather than
/// trustworthy. Driving the sheet from a bare host gives a fast, deterministic
/// test of the exact behaviour. Nothing in production calls this.
@visibleForTesting
Future<double?> showAngleSliderForTest({
  required BuildContext context,
  required NightshadeColors colors,
  required String title,
  required String unit,
  required double initial,
  required double min,
  required double max,
  required bool isSet,
}) {
  return _showAngleSlider(
    context: context,
    colors: colors,
    title: title,
    unit: unit,
    initial: initial,
    min: min,
    max: max,
    isSet: isSet,
  );
}
