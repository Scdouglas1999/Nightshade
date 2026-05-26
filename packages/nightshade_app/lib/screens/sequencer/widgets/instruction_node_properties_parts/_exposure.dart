// Part of ../instruction_node_properties.dart -- extracted for maintainability.
//
// Exposure-node properties surface: ExposureProperties + state class, _ExposureRecommendationCard hint card, and the sky-brightness Adaptive Exposure section + per-filter override row.
part of '../instruction_node_properties.dart';

class ExposureProperties extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final ExposureNode node;

  const ExposureProperties(
      {super.key, required this.colors, required this.node});

  @override
  ConsumerState<ExposureProperties> createState() => _ExposurePropertiesState();
}

class _ExposurePropertiesState extends ConsumerState<ExposureProperties> {
  // Track whether values have been explicitly overridden by the user in this
  // editing session. When false, the displayed value is the profile default.
  // We use a Set of property names to track which properties the user has
  // explicitly touched during this session.
  final Set<String> _userOverrides = {};
  bool _isRunningTestExposure = false;

  @override
  void initState() {
    super.initState();
    _detectInitialOverrides();
  }

  @override
  void didUpdateWidget(ExposureProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _userOverrides.clear();
      _detectInitialOverrides();
    }
  }

  /// Determine which properties were explicitly set on the node (non-null
  /// values that differ from profile defaults). Properties that are null
  /// or match the profile default are treated as "using profile default".
  void _detectInitialOverrides() {
    final profile = ref.read(activeEquipmentProfileProvider);
    final node = widget.node;

    // Gain: null means "use profile default". A non-null value that differs
    // from the profile default is an explicit override.
    if (node.gain != null && node.gain != 0) {
      if (profile?.defaultGain == null || node.gain != profile!.defaultGain) {
        _userOverrides.add('gain');
      }
    }

    // Offset: same logic
    if (node.offset != null && node.offset != 0) {
      if (profile?.defaultOffset == null ||
          node.offset != profile!.defaultOffset) {
        _userOverrides.add('offset');
      }
    }

    // Binning: compare against profile default binning
    final profileBinning = profile?.defaultBinX ?? 1;
    final nodeBinning = _binningModeToInt(node.binning);
    if (nodeBinning != profileBinning) {
      _userOverrides.add('binning');
    }
  }

  bool _isGainProfileDefault() => !_userOverrides.contains('gain');
  bool _isOffsetProfileDefault() => !_userOverrides.contains('offset');
  bool _isBinningProfileDefault() => !_userOverrides.contains('binning');

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

  /// Get the effective gain value: use the node's explicit value if set,
  /// otherwise fall back to the profile default.
  int _effectiveGain(EquipmentProfileModel? profile) {
    if (_userOverrides.contains('gain') && widget.node.gain != null) {
      return widget.node.gain!;
    }
    return profile?.defaultGain ?? widget.node.gain ?? 0;
  }

  /// Get the effective offset value: use the node's explicit value if set,
  /// otherwise fall back to the profile default.
  int _effectiveOffset(EquipmentProfileModel? profile) {
    if (_userOverrides.contains('offset') && widget.node.offset != null) {
      return widget.node.offset!;
    }
    return profile?.defaultOffset ?? widget.node.offset ?? 0;
  }

  int _effectiveBinningX(EquipmentProfileModel? profile) {
    if (_isBinningProfileDefault()) {
      return profile?.defaultBinX ?? _binningModeToInt(widget.node.binning);
    }
    return _binningModeToInt(widget.node.binning);
  }

  int _effectiveBinningY(EquipmentProfileModel? profile) {
    if (_isBinningProfileDefault()) {
      return profile?.defaultBinY ?? _binningModeToInt(widget.node.binning);
    }
    return _binningModeToInt(widget.node.binning);
  }

  Future<void> _runTestExposure(EquipmentProfileModel? profile) async {
    if (_isRunningTestExposure) return;

    setState(() => _isRunningTestExposure = true);

    final node = widget.node;
    final settings = ExposureSettings(
      exposureTime: node.durationSecs,
      gain: _effectiveGain(profile),
      offset: _effectiveOffset(profile),
      binningX: _effectiveBinningX(profile),
      binningY: _effectiveBinningY(profile),
      filter: node.filter,
      frameType: FrameType.snapshot,
      fastReadout: false,
    );

    try {
      final image = await ref.read(imagingServiceProvider).captureImage(
            settings: settings,
            targetName: '${node.name} test',
          );

      if (image != null) {
        ref.read(currentImageProvider.notifier).state = image;
        ref.read(lastImageStatsProvider.notifier).state = image.stats;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            image == null ? 'Test exposure completed' : 'Test exposure saved',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test exposure failed: $error'),
          backgroundColor: widget.colors.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRunningTestExposure = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final node = widget.node;
    final profile = ref.watch(activeEquipmentProfileProvider);
    final exposureContext =
        ref.watch(smartNightExposureContextProvider).valueOrNull;
    final exposureRecommendation =
        exposureContext?.recommendForFilter(node.filter);
    // Trust-patch §B: belt-and-suspenders gate (parent
    // NodePropertiesPanel already wraps the editor body in AbsorbPointer
    // when running). Wrap the largest properties form in IgnorePointer
    // too so an extraction refactor can't un-gate the dozens of
    // inputs below.
    final canEdit = ref.watch(canEditSequenceProvider);

    return IgnorePointer(
      ignoring: !canEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exposure Settings',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 13),
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          NodePropertyField(
            colors: colors,
            label: 'Duration',
            child: NodeNumberInput(
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

          if (exposureRecommendation != null) ...[
            const SizedBox(height: 8),
            _ExposureRecommendationCard(
              colors: colors,
              recommendation: exposureRecommendation,
              currentDurationSecs: node.durationSecs,
              onApply: () {
                final seconds = exposureRecommendation.seconds;
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(durationSecs: seconds),
                    );
                ref
                    .read(sequencerDefaultsProvider.notifier)
                    .updateExposureDefaults(
                      duration: seconds,
                    );
              },
            ),
          ],

          NodePropertyField(
            colors: colors,
            label: 'Count',
            child: NodeNumberInput(
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

          NodePropertyField(
            colors: colors,
            label: 'Frame Type',
            child: NodeDropdown<FrameType>(
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
          NodePropertyField(
            colors: colors,
            label: _isBinningProfileDefault()
                ? 'Binning (profile default)'
                : 'Binning',
            child: NodeDropdown<BinningMode>(
              colors: colors,
              value: node.binning,
              items: BinningMode.values,
              labelBuilder: (b) => b.label,
              onChanged: (value) {
                setState(() => _userOverrides.add('binning'));
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
                child: NodePropertyField(
                  colors: colors,
                  label: _isGainProfileDefault() ? 'Gain (profile)' : 'Gain',
                  child: NodeNumberInputWithHint(
                    colors: colors,
                    value: _effectiveGain(profile).toDouble(),
                    min: 0,
                    max: 1000,
                    isProfileDefault: _isGainProfileDefault(),
                    hintText:
                        _isGainProfileDefault() && profile?.defaultGain != null
                            ? 'Profile: ${profile!.defaultGain}'
                            : null,
                    onChanged: (value) {
                      final gain = value.toInt();
                      setState(() => _userOverrides.add('gain'));
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
                child: NodePropertyField(
                  colors: colors,
                  label:
                      _isOffsetProfileDefault() ? 'Offset (profile)' : 'Offset',
                  child: NodeNumberInputWithHint(
                    colors: colors,
                    value: _effectiveOffset(profile).toDouble(),
                    min: 0,
                    max: 1000,
                    isProfileDefault: _isOffsetProfileDefault(),
                    hintText: _isOffsetProfileDefault() &&
                            profile?.defaultOffset != null
                        ? 'Profile: ${profile!.defaultOffset}'
                        : null,
                    onChanged: (value) {
                      final offset = value.toInt();
                      setState(() => _userOverrides.add('offset'));
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

          NodePropertyField(
            colors: colors,
            label: 'Dither Every',
            child: NodeNumberInput(
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

          // Wave 5 Agent 2 — sky-brightness adaptive exposure block.
          // Off by default; expanding shows the SNR / reference / min /
          // max controls + per-filter overrides.
          const SizedBox(height: 12),
          _AdaptiveExposureSection(
            colors: colors,
            node: node,
            profile: profile,
          ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isRunningTestExposure
                  ? null
                  : () => _runTestExposure(profile),
              icon: Icon(
                _isRunningTestExposure
                    ? LucideIcons.loader2
                    : LucideIcons.camera,
                size: 15,
              ),
              label: Text(
                _isRunningTestExposure
                    ? 'Running Test Exposure'
                    : 'Run Test Exposure',
              ),
            ),
          ),

          // Summary
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: NightshadeDecorations.tintedBadge(
              colors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.clock, size: 14, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Total: ${_formatDuration(node.totalDurationSecs)}',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 13),
                    fontWeight: FontWeight.w500,
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    developer.log(
        '_buildFilterDropdown: node.filter="${node.filter}" node.filterIndex=${node.filterIndex} filterNames=$filterNames',
        name: 'InstructionNodeProperties',
        level: 500);
    final currentFilter = filterOptions.firstWhere(
      (f) =>
          (node.filterIndex != null && f.index == node.filterIndex) ||
          (node.filterIndex == null && f.name == (node.filter ?? '')),
      orElse: () => filterOptions.first,
    );
    developer.log(
        '_buildFilterDropdown: currentFilter=(index:${currentFilter.index}, name:"${currentFilter.name}")',
        name: 'InstructionNodeProperties',
        level: 500);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Filter',
          child: filterNames.isEmpty
              ? NodeTextInput(
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
          onTap: () => ProfileEditorDialog.show(
            context,
            profile: ref.read(activeEquipmentProfileProvider),
          ),
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
                    fontSize: Responsive.fontSize(context, 12),
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

class _ExposureRecommendationCard extends StatelessWidget {
  final NightshadeColors colors;
  final ExposureRecommendation recommendation;
  final double currentDurationSecs;
  final VoidCallback onApply;

  const _ExposureRecommendationCard({
    required this.colors,
    required this.recommendation,
    required this.currentDurationSecs,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final recommended = recommendation.seconds;
    final differs = (recommended - currentDurationSecs).abs() > 0.5;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: NightshadeDecorations.iconChip(
        colors.primary,
        borderRadius: BorderRadius.circular(8),
        borderAlpha: 0.28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 14, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Recommended exposure',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: differs ? onApply : null,
                icon: Icon(
                  LucideIcons.check,
                  size: 13,
                  color: differs ? colors.primary : colors.textMuted,
                ),
                label: Text(
                  'Apply ${_formatSeconds(recommended)}',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    color: differs ? colors.primary : colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatSeconds(recommended)} · ${recommendation.limitingFactor}',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 12),
              color: colors.textSecondary,
            ),
          ),
          if (recommendation.rationale.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              recommendation.rationale,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 11),
                color: colors.textMuted,
              ),
            ),
          ],
          if (recommendation.caveats.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              recommendation.caveats.first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Responsive.fontSize(context, 11),
                color: colors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatSeconds(double seconds) {
    final rounded = seconds.roundToDouble();
    if ((seconds - rounded).abs() < 0.05) {
      return '${rounded.toInt()}s';
    }
    return '${seconds.toStringAsFixed(1)}s';
  }
}

// ============================================================================
// Wave 5 Agent 2 — Sky-brightness adaptive exposure UI block for the
// ExposureProperties panel. Off by default; expanding shows SNR / reference
// / min / max + per-filter overrides + a live preview the user can glance
// at to see what the next burst will actually capture at.
// ============================================================================

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
    ref.read(currentSequenceProvider.notifier).updateNode(
          widget.node.copyWith(clearAdaptiveExposure: true),
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.4),
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.barChart3, size: 14, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Adaptive Exposure (sky-brightness)',
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 12),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                _hasOverride ? 'Per-node' : 'Inherit',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
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
                style: TextStyle(fontSize: 11, color: colors.textMuted),
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
          style: TextStyle(fontSize: 11, color: colors.textMuted),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Per-filter overrides',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.lineChart, size: 12, color: color),
              const SizedBox(width: 6),
              Expanded(
                child:
                    Text(preview, style: TextStyle(fontSize: 11, color: color)),
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
                    style: TextStyle(fontSize: 11, color: colors.warning),
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
                fontSize: 11,
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
