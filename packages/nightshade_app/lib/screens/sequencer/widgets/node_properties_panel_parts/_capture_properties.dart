// Part of ../node_properties_panel.dart -- extracted for maintainability.
//
// Properties widgets for the imaging loop's capture-side nodes: exposure (with its complex state class), cool/warm camera, filter change, and dither.
part of '../node_properties_panel.dart';

class _ExposureProperties extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final ExposureNode node;

  const _ExposureProperties({required this.colors, required this.node});

  @override
  ConsumerState<_ExposureProperties> createState() =>
      _ExposurePropertiesState();
}

class _ExposurePropertiesState extends ConsumerState<_ExposureProperties> {
  // Track whether values are using profile defaults (not explicitly set)
  bool _gainIsProfileDefault = false;
  bool _offsetIsProfileDefault = false;
  bool _binningIsProfileDefault = false;

  @override
  void initState() {
    super.initState();
    _checkProfileDefaults();
  }

  @override
  void didUpdateWidget(_ExposureProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _checkProfileDefaults();
    }
  }

  void _checkProfileDefaults() {
    final profile = ref.read(activeEquipmentProfileProvider);
    final node = widget.node;

    // Check if gain matches profile default (or is null/0 and profile has a default)
    _gainIsProfileDefault = node.gain == null ||
        (profile?.defaultGain != null && node.gain == profile!.defaultGain);

    // Check if offset matches profile default
    _offsetIsProfileDefault = node.offset == null ||
        (profile?.defaultOffset != null &&
            node.offset == profile!.defaultOffset);

    // Check if binning matches profile default
    final profileBinning = profile?.defaultBinX ?? 1;
    final nodeBinningValue = _binningModeToInt(node.binning);
    _binningIsProfileDefault = nodeBinningValue == profileBinning;
  }

  int _binningModeToInt(BinningMode mode) {
    switch (mode) {
      case BinningMode.one:
        return 1;
      case BinningMode.two:
        return 2;
      case BinningMode.three:
        return 3;
      case BinningMode.four:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final node = widget.node;
    final profile = ref.watch(activeEquipmentProfileProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exposure Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        _PropertyField(
          colors: colors,
          label: 'Duration',
          child: _NumberInput(
            colors: colors,
            value: node.durationSecs,
            suffix: 's',
            min: 0.001,
            max: 3600,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(durationSecs: value),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateExposureDefaults(
                    duration: value,
                  );
            },
          ),
        ),

        _PropertyField(
          colors: colors,
          label: 'Count',
          child: _NumberInput(
            colors: colors,
            value: node.count.toDouble(),
            min: 1,
            max: 9999,
            onChanged: (value) {
              final count = value.toInt();
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(count: count),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateExposureDefaults(
                    count: count,
                  );
            },
          ),
        ),

        _PropertyField(
          colors: colors,
          label: 'Frame Type',
          child: _Dropdown<FrameType>(
            colors: colors,
            value: node.frameType,
            items: FrameType.values,
            labelBuilder: (t) => t.name.toUpperCase(),
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(frameType: value),
                  );
            },
          ),
        ),

        _buildFilterDropdown(context),

        // Binning with profile default indicator
        _PropertyField(
          colors: colors,
          label: _binningIsProfileDefault
              ? 'Binning (profile default)'
              : 'Binning',
          child: _Dropdown<BinningMode>(
            colors: colors,
            value: node.binning,
            items: BinningMode.values,
            labelBuilder: (b) => b.label,
            onChanged: (value) {
              setState(() => _binningIsProfileDefault = false);
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(binning: value),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateExposureDefaults(
                    binning: value,
                  );
            },
          ),
        ),

        // Gain and Offset with profile default indicators
        Row(
          children: [
            Expanded(
              child: _PropertyField(
                colors: colors,
                label:
                    _gainIsProfileDefault ? 'Gain (profile default)' : 'Gain',
                child: _NumberInputWithHint(
                  colors: colors,
                  value: (node.gain ?? profile?.defaultGain ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  hintText:
                      _gainIsProfileDefault && profile?.defaultGain != null
                          ? '(profile: ${profile!.defaultGain})'
                          : null,
                  onChanged: (value) {
                    final gain = value.toInt();
                    setState(() => _gainIsProfileDefault = false);
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(gain: gain),
                        );
                    // Save as default for future nodes
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateExposureDefaults(
                          gain: gain,
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: _offsetIsProfileDefault
                    ? 'Offset (profile default)'
                    : 'Offset',
                child: _NumberInputWithHint(
                  colors: colors,
                  value:
                      (node.offset ?? profile?.defaultOffset ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  hintText:
                      _offsetIsProfileDefault && profile?.defaultOffset != null
                          ? '(profile: ${profile!.defaultOffset})'
                          : null,
                  onChanged: (value) {
                    final offset = value.toInt();
                    setState(() => _offsetIsProfileDefault = false);
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(offset: offset),
                        );
                    // Save as default for future nodes
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateExposureDefaults(
                          offset: offset,
                        );
                  },
                ),
              ),
            ),
          ],
        ),

        _PropertyField(
          colors: colors,
          label: 'Dither Every',
          child: _NumberInput(
            colors: colors,
            value: (node.ditherEvery ?? 0).toDouble(),
            suffix: ' frames',
            min: 0,
            max: 100,
            onChanged: (value) {
              final ditherEvery = value.toInt();
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(ditherEvery: ditherEvery),
                  );
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateExposureDefaults(
                    ditherEvery: ditherEvery,
                  );
            },
          ),
        ),

        // Summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.clock, size: 14, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Total: ${_formatDuration(node.totalDurationSecs)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterDropdown(BuildContext context) {
    final colors = widget.colors;
    final node = widget.node;

    // Get filter names from active profile
    final profile = ref.watch(activeEquipmentProfileProvider);
    final filterNames = profile?.filterNames ?? <String>[];

    // Build list of filter options with their indices
    final filterOptions = <({int index, String name})>[
      (index: -1, name: ''), // No filter option
      for (int i = 0; i < filterNames.length; i++)
        (index: i, name: filterNames[i]),
    ];

    // Find current selection
    final currentFilter = filterOptions.firstWhere(
      (f) =>
          (node.filterIndex != null && f.index == node.filterIndex) ||
          (node.filterIndex == null && f.name == (node.filter ?? '')),
      orElse: () => filterOptions.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PropertyField(
          colors: colors,
          label: 'Filter',
          child: filterNames.isEmpty
              ? _TextInput(
                  colors: colors,
                  value: node.filter ?? '',
                  hint: 'No filters in profile',
                  onChanged: (value) {
                    final filter = value.isEmpty ? null : value;
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(filter: filter),
                        );
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateExposureDefaults(
                          filter: filter,
                        );
                  },
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<({int index, String name})>(
                      value: currentFilter,
                      isExpanded: true,
                      icon: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: colors.textMuted,
                      ),
                      dropdownColor: colors.surface,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textPrimary,
                      ),
                      items: filterOptions.map((filter) {
                        return DropdownMenuItem(
                          value: filter,
                          child:
                              Text(filter.index < 0 ? '(None)' : filter.name),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          final filter =
                              newValue.index < 0 ? null : newValue.name;
                          final filterIndex =
                              newValue.index < 0 ? null : newValue.index;
                          ref.read(currentSequenceProvider.notifier).updateNode(
                                node.copyWith(
                                  filter: filter,
                                  filterIndex: filterIndex,
                                ),
                              );
                          ref
                              .read(sequencerDefaultsProvider.notifier)
                              .updateExposureDefaults(
                                filter: filter,
                              );
                        }
                      },
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => ProfileEditorDialog.show(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.settings, size: 12, color: colors.textMuted),
                const SizedBox(width: 4),
                Text(
                  'Edit filters...',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _formatDuration(double secs) {
    if (secs < 60) return '${secs.toStringAsFixed(1)}s';
    if (secs < 3600) return '${(secs / 60).toStringAsFixed(1)}m';
    return '${(secs / 3600).toStringAsFixed(1)}h';
  }
}

class _CoolCameraProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CoolCameraNode node;

  const _CoolCameraProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cooling Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Target Temperature',
          child: _NumberInput(
            colors: colors,
            value: node.targetTemp,
            suffix: '°C',
            min: -50,
            max: 30,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(targetTemp: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Max Duration',
          child: _NumberInput(
            colors: colors,
            value: node.durationMins ?? 10,
            suffix: 'min',
            min: 1,
            max: 60,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(durationMins: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChangeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final FilterChangeNode node;

  const _FilterChangeProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get filter names from active profile
    final profile = ref.watch(activeEquipmentProfileProvider);
    final filterNames = profile?.filterNames ?? <String>[];

    // Build list of filter options with their indices
    // Each item is a record of (index, name)
    final filterOptions = <({int index, String name})>[
      for (int i = 0; i < filterNames.length; i++)
        (index: i, name: filterNames[i]),
    ];

    // Find current selection, or default to first if not found
    final currentFilter = filterOptions.isEmpty
        ? null
        : filterOptions.firstWhere(
            (f) => f.name == node.filterName || f.index == node.filterPosition,
            orElse: () => filterOptions.first,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Filter Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Filter',
          child: filterOptions.isEmpty
              ? _TextInput(
                  colors: colors,
                  value: node.filterName,
                  hint: 'No filters in profile',
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(filterName: value),
                        );
                  },
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<({int index, String name})>(
                      value: currentFilter,
                      isExpanded: true,
                      icon: Icon(
                        LucideIcons.chevronDown,
                        size: 16,
                        color: colors.textMuted,
                      ),
                      dropdownColor: colors.surface,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textPrimary,
                      ),
                      items: filterOptions.map((filter) {
                        return DropdownMenuItem(
                          value: filter,
                          child: Text(filter.name),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          // Set BOTH name and position for reliable filter changes
                          ref.read(currentSequenceProvider.notifier).updateNode(
                                node.copyWith(
                                  filterName: newValue.name,
                                  filterPosition: newValue.index,
                                ),
                              );
                        }
                      },
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => ProfileEditorDialog.show(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.settings, size: 12, color: colors.textMuted),
                const SizedBox(width: 4),
                Text(
                  'Edit filters...',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DitherProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final DitherNode node;

  const _DitherProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dither Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Dither Amount',
          child: _NumberInput(
            colors: colors,
            value: node.pixels,
            suffix: 'px',
            min: 1,
            max: 50,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(pixels: value),
                  );
              // Save as default for future nodes
              ref.read(sequencerDefaultsProvider.notifier).updateDitherDefaults(
                    pixels: value,
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Settle Time',
          child: _NumberInput(
            colors: colors,
            value: node.settleTime,
            suffix: 's',
            min: 5,
            max: 120,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settleTime: value),
                  );
              // Save as default for future nodes
              ref.read(sequencerDefaultsProvider.notifier).updateDitherDefaults(
                    settleTime: value,
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Settle Threshold',
          child: _NumberInput(
            colors: colors,
            value: node.settlePixels,
            suffix: 'px',
            min: 0.1,
            max: 5,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settlePixels: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Pattern',
          child: _Dropdown<DitherPattern>(
            colors: colors,
            value: node.pattern,
            items: const [DitherPattern.random, DitherPattern.grid],
            labelBuilder: (p) => switch (p) {
              DitherPattern.random => 'Random (classic)',
              DitherPattern.grid => 'Grid (systematic NxN)',
            },
            onChanged: (newPattern) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(pattern: newPattern),
                  );
            },
          ),
        ),
        if (node.pattern == DitherPattern.grid)
          _PropertyField(
            colors: colors,
            label: 'Grid Size (N)',
            child: _NumberInput(
              colors: colors,
              value: node.gridSize.toDouble(),
              min: 2,
              max: 9,
              suffix: 'x N',
              onChanged: (value) {
                final n = value.round().clamp(2, 9);
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(gridSize: n),
                    );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            node.pattern == DitherPattern.grid
                ? 'Walks a ${node.gridSize}x${node.gridSize} grid — visits ${node.gridSize * node.gridSize} positions before cycling. Best for uniform sky coverage.'
                : 'Random offsets each dither. Best for averaging out fixed-pattern noise; classic choice.',
            style: TextStyle(
              fontSize: 11,
              color: colors.textMuted,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

class _WarmCameraProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final WarmCameraNode node;

  const _WarmCameraProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Warming Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Warming Rate',
          child: _NumberInput(
            colors: colors,
            value: node.ratePerMin,
            suffix: '°C/min',
            min: 0.5,
            max: 10,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(ratePerMin: value),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gradual warming prevents thermal shock to the sensor',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
