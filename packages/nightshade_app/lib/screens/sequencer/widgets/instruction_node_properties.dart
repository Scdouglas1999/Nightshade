import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../equipment/dialogs/profile_editor_dialog.dart';
import 'node_property_widgets.dart';

class ExposureProperties extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final ExposureNode node;

  const ExposureProperties({super.key, required this.colors, required this.node});

  @override
  ConsumerState<ExposureProperties> createState() =>
      _ExposurePropertiesState();
}

class _ExposurePropertiesState extends ConsumerState<ExposureProperties> {
  // Track whether values have been explicitly overridden by the user in this
  // editing session. When false, the displayed value is the profile default.
  // We use a Set of property names to track which properties the user has
  // explicitly touched during this session.
  final Set<String> _userOverrides = {};

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
                label: _isGainProfileDefault()
                    ? 'Gain (profile)'
                    : 'Gain',
                child: NodeNumberInputWithHint(
                  colors: colors,
                  value: _effectiveGain(profile).toDouble(),
                  min: 0,
                  max: 1000,
                  isProfileDefault: _isGainProfileDefault(),
                  hintText: _isGainProfileDefault() && profile?.defaultGain != null
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
                label: _isOffsetProfileDefault()
                    ? 'Offset (profile)'
                    : 'Offset',
                child: NodeNumberInputWithHint(
                  colors: colors,
                  value: _effectiveOffset(profile).toDouble(),
                  min: 0,
                  max: 1000,
                  isProfileDefault: _isOffsetProfileDefault(),
                  hintText:
                      _isOffsetProfileDefault() && profile?.defaultOffset != null
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
                  fontSize: Responsive.fontSize(context, 13),
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
                          child: Text(filter.index < 0 ? '(None)' : filter.name),
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

class CenterProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CenterNode node;

  const CenterProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Centering Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Use Target Coordinates',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.useTargetCoords,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(useTargetCoords: value),
                  );
            },
          ),
        ),
        if (!node.useTargetCoords) ...[
          Row(
            children: [
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'Custom RA (hours)',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.customRa ?? 0,
                    suffix: 'h',
                    min: 0,
                    max: 24,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(customRa: value),
                          );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'Custom Dec (deg)',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.customDec ?? 0,
                    suffix: '\u00B0',
                    min: -90,
                    max: 90,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(customDec: value),
                          );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
        NodePropertyField(
          colors: colors,
          label: 'Accuracy',
          child: NodeNumberInput(
            colors: colors,
            value: node.accuracyArcsec,
            suffix: '"',
            min: 0.1,
            max: 60,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(accuracyArcsec: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Max Attempts',
          child: NodeNumberInput(
            colors: colors,
            value: node.maxAttempts.toDouble(),
            min: 1,
            max: 20,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(maxAttempts: value.toInt()),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Solve Exposure',
          child: NodeNumberInput(
            colors: colors,
            value: node.exposureDuration,
            suffix: 's',
            min: 0.5,
            max: 30,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(exposureDuration: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Solve Filter',
          child: NodeTextInput(
            colors: colors,
            value: node.filter ?? '',
            hint: 'Current filter',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(filter: value.isEmpty ? null : value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class AutofocusProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final AutofocusNode node;

  const AutofocusProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final afSettings = ref.watch(autofocusSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Autofocus Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        // Use Settings Defaults toggle
        NodePropertyField(
          colors: colors,
          label: 'Use Settings Defaults',
          child: Row(
            children: [
              NodeToggleSwitch(
                colors: colors,
                value: node.useSettingsDefaults,
                onChanged: (value) {
                  ref.read(currentSequenceProvider.notifier).updateNode(
                        node.copyWith(useSettingsDefaults: value),
                      );
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.useSettingsDefaults
                      ? 'Using global AF settings'
                      : 'Using node overrides',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 11),
                    color: colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (node.useSettingsDefaults)
          // Read-only display of current global AF settings
          _buildDefaultsDisplay(context, afSettings)
        else
          // Editable per-node overrides
          _buildEditableFields(ref),

        const SizedBox(height: 8),
        // Max Duration is always node-specific (not from global settings)
        NodePropertyField(
          colors: colors,
          label: 'Max Duration',
          child: NodeNumberInput(
            colors: colors,
            value: node.maxDurationSecs,
            suffix: 's',
            min: 30,
            max: 3600,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(maxDurationSecs: value),
                  );
            },
          ),
        ),
        Text(
          'Autofocus will abort if it exceeds this duration (${(node.maxDurationSecs / 60).toStringAsFixed(0)} min)',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 11),
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }

  /// Displays the persisted global AF settings as read-only informational rows.
  Widget _buildDefaultsDisplay(BuildContext context, AutofocusSettings afSettings) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Global settings (edit in Settings > Autofocus)',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 11),
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(context, 'Method', afSettings.method),
          _buildInfoRow(context, 'Curve Fitting', afSettings.curveFitting),
          _buildInfoRow(context, 'Step Size', '${afSettings.stepSize}'),
          _buildInfoRow(context, 'Steps Out', '${afSettings.initialOffsetSteps}'),
          _buildInfoRow(context, 'Exposure', '${afSettings.exposureTime}s'),
          _buildInfoRow(context, 'Exposures/Point', '${afSettings.exposuresPerPoint}'),
          _buildInfoRow(context, 'Binning', '${afSettings.binning}x${afSettings.binning}'),
          _buildInfoRow(context, 'R\u00B2 Threshold', '${afSettings.rSquaredThreshold}'),
          _buildInfoRow(context, 'Backlash Comp', afSettings.backlashCompMethod),
          if (afSettings.disableGuidingDuringAf)
            _buildInfoRow(context, 'Guiding', 'Disabled during AF'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 12),
              color: colors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 12),
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Editable fields for per-node overrides (original behavior).
  Widget _buildEditableFields(WidgetRef ref) {
    return Column(
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Method',
          child: NodeDropdown<AutofocusMethod>(
            colors: colors,
            value: node.method,
            items: AutofocusMethod.values,
            labelBuilder: (m) {
              switch (m) {
                case AutofocusMethod.vCurve:
                  return 'V-Curve';
                case AutofocusMethod.hyperbolic:
                  return 'Hyperbolic';
                case AutofocusMethod.quadratic:
                  return 'Quadratic';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(method: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Step Size',
                child: NodeNumberInput(
                  colors: colors,
                  value: node.stepSize.toDouble(),
                  min: 1,
                  max: 1000,
                  onChanged: (value) {
                    final stepSize = value.toInt();
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(stepSize: stepSize),
                        );
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateAutofocusDefaults(
                          stepSize: stepSize,
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Steps Out',
                child: NodeNumberInput(
                  colors: colors,
                  value: node.stepsOut.toDouble(),
                  min: 3,
                  max: 15,
                  onChanged: (value) {
                    final stepsOut = value.toInt();
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(stepsOut: stepsOut),
                        );
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateAutofocusDefaults(
                          stepsOut: stepsOut,
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        NodePropertyField(
          colors: colors,
          label: 'Exposure Duration',
          child: NodeNumberInput(
            colors: colors,
            value: node.exposureDuration,
            suffix: 's',
            min: 0.5,
            max: 30,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(exposureDuration: value),
                  );
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateAutofocusDefaults(
                    exposureDuration: value,
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Exposures Per Point',
          child: NodeNumberInput(
            colors: colors,
            value: node.exposuresPerPoint.toDouble(),
            min: 1,
            max: 10,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(exposuresPerPoint: value.toInt()),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class CoolCameraProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CoolCameraNode node;

  const CoolCameraProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cooling Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Target Temperature',
          child: NodeNumberInput(
            colors: colors,
            value: node.targetTemp,
            suffix: '\u00B0C',
            min: -50,
            max: 30,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(targetTemp: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Max Duration',
          child: NodeNumberInput(
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

class FilterChangeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final FilterChangeNode node;

  const FilterChangeProperties({super.key, required this.colors, required this.node});

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
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Filter',
          child: filterOptions.isEmpty
              ? NodeTextInput(
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
      ],
    );
  }
}

class DelayProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final DelayNode node;

  const DelayProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delay Settings',
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
            value: node.seconds,
            suffix: 's',
            min: 0.1,
            max: 3600,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(seconds: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class StartGuidingProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final StartGuidingNode node;

  const StartGuidingProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guiding Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Settle Threshold',
          child: NodeNumberInput(
            colors: colors,
            value: node.settlePixels,
            suffix: 'px',
            min: 0.1,
            max: 10,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settlePixels: value),
                  );
              ref.read(sequencerDefaultsProvider.notifier).updateDitherDefaults(
                    settlePixels: value,
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Settle Time',
          child: NodeNumberInput(
            colors: colors,
            value: node.settleTime,
            suffix: 's',
            min: 1,
            max: 120,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settleTime: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Settle Timeout',
          child: NodeNumberInput(
            colors: colors,
            value: node.settleTimeout,
            suffix: 's',
            min: 10,
            max: 300,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settleTimeout: value),
                  );
              ref.read(sequencerDefaultsProvider.notifier).updateDitherDefaults(
                    settleTimeout: value,
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Auto-select Star',
          child: SizedBox(
            height: 28,
            child: Switch(
              value: node.autoSelectStar,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(autoSelectStar: value),
                    );
              },
              activeColor: colors.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}

class DitherProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final DitherNode node;

  const DitherProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dither Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Dither Amount',
          child: NodeNumberInput(
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
        NodePropertyField(
          colors: colors,
          label: 'Settle Time',
          child: NodeNumberInput(
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
        NodePropertyField(
          colors: colors,
          label: 'Settle Threshold',
          child: NodeNumberInput(
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
        NodePropertyField(
          colors: colors,
          label: 'Settle Timeout',
          child: NodeNumberInput(
            colors: colors,
            value: node.settleTimeout,
            suffix: 's',
            min: 10,
            max: 300,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settleTimeout: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'RA Only',
          child: SizedBox(
            height: 28,
            child: Switch(
              value: node.raOnly,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(raOnly: value),
                    );
                ref
                    .read(sequencerDefaultsProvider.notifier)
                    .updateDitherDefaults(raOnly: value);
              },
              activeColor: colors.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }
}

class WarmCameraProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final WarmCameraNode node;

  const WarmCameraProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Warming Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Warming Rate',
          child: NodeNumberInput(
            colors: colors,
            value: node.ratePerMin,
            suffix: '\u00B0C/min',
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
        NodePropertyField(
          colors: colors,
          label: 'Target Temp',
          child: NodeNumberInput(
            colors: colors,
            value: node.targetTemp,
            suffix: '\u00B0C',
            min: 0,
            max: 35,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(targetTemp: value),
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
                  'Gradual warming prevents thermal shock while warming toward ${node.targetTemp.toStringAsFixed(1)}°C',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
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

class RotatorProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final RotatorNode node;

  const RotatorProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rotator Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Target Angle',
          child: NodeNumberInput(
            colors: colors,
            value: node.targetAngle,
            suffix: '\u00B0',
            min: 0,
            max: 360,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(targetAngle: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Relative Movement',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.relative,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(relative: value),
                  );
            },
          ),
        ),
        Text(
          node.relative
              ? 'Rotates relative to current position'
              : 'Moves to absolute position angle',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 12),
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class SlewProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SlewNode node;

  const SlewProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Slew Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Use Target Coordinates',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.useTargetCoords,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(useTargetCoords: value),
                  );
            },
          ),
        ),
        if (!node.useTargetCoords) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'RA (hours)',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.customRa ?? 0,
                    suffix: 'h',
                    min: 0,
                    max: 24,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(customRa: value),
                          );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'Dec (degrees)',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.customDec ?? 0,
                    suffix: '\u00B0',
                    min: -90,
                    max: 90,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(customDec: value),
                          );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
        if (node.useTargetCoords) ...[
          Builder(
            builder: (context) {
              final sequence = ref.watch(currentSequenceProvider);
              TargetHeaderNode? targetGroup;

              if (sequence != null) {
                // Try to find parent target group first
                try {
                  targetGroup = sequence.nodes.values
                      .whereType<TargetHeaderNode>()
                      .where((n) => n.childIds.contains(node.id))
                      .first;
                } catch (e) {
                  // No direct parent found
                }

                // If no direct parent, use first target group in sequence
                if (targetGroup == null && sequence.targetHeaders.isNotEmpty) {
                  targetGroup = sequence.targetHeaders.first;
                }
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: targetGroup != null
                      ? colors.success.withValues(alpha: 0.1)
                      : colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      targetGroup != null
                          ? LucideIcons.checkCircle
                          : LucideIcons.alertCircle,
                      size: 14,
                      color:
                          targetGroup != null ? colors.success : colors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        targetGroup != null
                            ? 'Will use target: ${targetGroup.targetName}\nRA: ${targetGroup.raHours.toStringAsFixed(4)}h, Dec: ${targetGroup.decDegrees.toStringAsFixed(4)}\u00B0'
                            : 'No target group found in sequence',
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 12),
                          color: targetGroup != null
                              ? colors.success
                              : colors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class NotificationProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final NotificationNode node;

  const NotificationProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notification Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Title',
          child: NodeTextInput(
            colors: colors,
            value: node.title,
            hint: 'Notification title',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(title: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Message',
          child: NodeTextInput(
            colors: colors,
            value: node.message,
            hint: 'Notification message',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(message: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Level',
          child: NodeDropdown<NotificationLevel>(
            colors: colors,
            value: node.level,
            items: NotificationLevel.values,
            labelBuilder: (l) {
              switch (l) {
                case NotificationLevel.info:
                  return 'Info';
                case NotificationLevel.warning:
                  return 'Warning';
                case NotificationLevel.error:
                  return 'Error';
                case NotificationLevel.success:
                  return 'Success';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(level: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class ScriptProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ScriptNode node;

  const ScriptProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Script Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Script Path',
          child: NodeTextInput(
            colors: colors,
            value: node.scriptPath,
            hint: 'Path to script file',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(scriptPath: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Arguments',
          child: NodeTextInput(
            colors: colors,
            value: node.arguments.join(' '),
            hint: 'Space-separated arguments',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(
                        arguments: value
                            .split(' ')
                            .where((s) => s.isNotEmpty)
                            .toList()),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Timeout',
          child: NodeNumberInput(
            colors: colors,
            value: (node.timeoutSecs ?? 300).toDouble(),
            suffix: 's',
            min: 1,
            max: 3600,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.toInt()),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scripts run with sequence context variables available as environment variables',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
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

class SimpleInstructionInfo extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const SimpleInstructionInfo({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    final String description;
    final IconData icon;

    if (node is ParkNode) {
      description =
          'Parks the mount at its home position. The mount will not track after parking.';
      icon = LucideIcons.parkingCircle;
    } else if (node is UnparkNode) {
      description =
          'Unparks the mount and enables tracking. Required before slewing or imaging.';
      icon = LucideIcons.unlock;
    } else {
      description = 'This instruction has no additional settings.';
      icon = LucideIcons.settings;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 13),
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class MeridianFlipProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final MeridianFlipNode node;

  const MeridianFlipProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meridian Flip Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Trigger Method',
          child: NodeDropdown<MeridianTriggerMethod>(
            colors: colors,
            value: node.triggerMethod,
            items: MeridianTriggerMethod.values,
            labelBuilder: (m) {
              switch (m) {
                case MeridianTriggerMethod.minutesPastMeridian:
                  return 'Minutes Past Meridian';
                case MeridianTriggerMethod.minutesBeforeLimit:
                  return 'Minutes Before Limit';
                case MeridianTriggerMethod.hourAngleThreshold:
                  return 'Hour Angle Threshold';
                case MeridianTriggerMethod.onTrackingLimitHit:
                  return 'On Tracking Limit Hit';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(triggerMethod: value),
                  );
            },
          ),
        ),
        if (node.triggerMethod == MeridianTriggerMethod.minutesPastMeridian)
          NodePropertyField(
            colors: colors,
            label: 'Minutes Past Meridian',
            child: NodeNumberInput(
              colors: colors,
              value: node.minutesPastMeridian,
              suffix: 'min',
              min: 0,
              max: 60,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(minutesPastMeridian: value),
                    );
              },
            ),
          ),
        if (node.triggerMethod == MeridianTriggerMethod.minutesBeforeLimit)
          NodePropertyField(
            colors: colors,
            label: 'Minutes Before Limit',
            child: NodeNumberInput(
              colors: colors,
              value: node.minutesBeforeLimit,
              suffix: 'min',
              min: 1,
              max: 60,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(minutesBeforeLimit: value),
                    );
              },
            ),
          ),
        if (node.triggerMethod == MeridianTriggerMethod.hourAngleThreshold)
          NodePropertyField(
            colors: colors,
            label: 'Hour Angle Threshold',
            child: NodeNumberInput(
              colors: colors,
              value: node.hourAngleThreshold,
              suffix: 'h',
              min: 0.0,
              max: 6.0,
              decimals: 2,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(hourAngleThreshold: value),
                    );
              },
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Flip Sequence',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        NodePropertyField(
          colors: colors,
          label: 'Pause Guiding',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.pauseGuiding,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(pauseGuiding: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Auto Center After Flip',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.autoCenter,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(autoCenter: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Refocus After Flip',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.refocusAfter,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(refocusAfter: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Resume Guiding',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.resumeGuiding,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(resumeGuiding: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Settle Time',
          child: NodeNumberInput(
            colors: colors,
            value: node.settleTime,
            suffix: 's',
            min: 0,
            max: 120,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(settleTime: value),
                  );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Error Handling',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        NodePropertyField(
          colors: colors,
          label: 'Max Retries',
          child: NodeNumberInput(
            colors: colors,
            value: node.maxRetries.toDouble(),
            min: 0,
            max: 10,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(maxRetries: value.toInt()),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Failure Action',
          child: NodeDropdown<FlipFailureAction>(
            colors: colors,
            value: node.failureAction,
            items: FlipFailureAction.values,
            labelBuilder: (a) {
              switch (a) {
                case FlipFailureAction.pauseAndAlert:
                  return 'Pause & Alert';
                case FlipFailureAction.abortAndPark:
                  return 'Abort & Park';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(failureAction: value),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Performs pier flip when target crosses meridian. Pauses guiding, flips, then optionally re-centers and refocuses.',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    color: colors.info,
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

class DomeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const DomeProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title;
    final String description;
    final IconData icon;
    final bool shutterOnly;

    if (node is OpenDomeNode) {
      title = 'Open Dome Settings';
      description =
          'Opens the dome shutter to allow imaging. If not using shutter-only mode, will also rotate dome to tracking position.';
      icon = LucideIcons.doorOpen;
      shutterOnly = (node as OpenDomeNode).shutterOnly;
    } else if (node is CloseDomeNode) {
      title = 'Close Dome Settings';
      description =
          'Closes the dome shutter to protect equipment. Typically used at end of session or when weather becomes unsafe.';
      icon = LucideIcons.doorClosed;
      shutterOnly = (node as CloseDomeNode).shutterOnly;
    } else {
      title = 'Park Dome Settings';
      description =
          'Parks the dome at its home position. The dome will stop tracking the telescope.';
      icon = LucideIcons.parkingCircle;
      shutterOnly = (node as ParkDomeNode).shutterOnly;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Shutter Only',
          child: NodeToggleSwitch(
            colors: colors,
            value: shutterOnly,
            onChanged: (value) {
              if (node is OpenDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as OpenDomeNode).copyWith(shutterOnly: value),
                    );
              } else if (node is CloseDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as CloseDomeNode).copyWith(shutterOnly: value),
                    );
              } else if (node is ParkDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as ParkDomeNode).copyWith(shutterOnly: value),
                    );
              }
            },
          ),
        ),
        Text(
          shutterOnly
              ? 'Only operates the shutter, dome will not rotate'
              : 'Will operate both shutter and dome rotation',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 12),
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: colors.primary),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 13),
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class PolarAlignmentProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final PolarAlignmentNode node;

  const PolarAlignmentProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Polar Alignment Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Hemisphere',
          child: NodeDropdown<bool>(
            colors: colors,
            value: node.isNorth,
            items: const [true, false],
            labelBuilder: (v) => v ? 'Northern' : 'Southern',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(isNorth: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Exposure Duration',
                child: NodeNumberInput(
                  colors: colors,
                  value: node.exposureDuration,
                  suffix: 's',
                  min: 0.5,
                  max: 30,
                  decimals: 1,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(exposureDuration: value),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Binning',
                child: NodeNumberInput(
                  colors: colors,
                  value: node.binning.toDouble(),
                  min: 1,
                  max: 4,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(binning: value.toInt()),
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        NodePropertyField(
          colors: colors,
          label: 'Start Altitude',
          child: NodeNumberInput(
            colors: colors,
            value: node.startAltitude,
            suffix: '\u00B0',
            min: 20,
            max: 80,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(startAltitude: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Rotation Step',
          child: NodeNumberInput(
            colors: colors,
            value: node.rotationStep,
            suffix: '\u00B0',
            min: 10,
            max: 45,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(rotationStep: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Gain',
                child: NodeNumberInput(
                  colors: colors,
                  value: (node.gain ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(gain: value.toInt()),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Offset',
                child: NodeNumberInput(
                  colors: colors,
                  value: (node.offset ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(offset: value.toInt()),
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        NodePropertyField(
          colors: colors,
          label: 'Start From Current Position',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.startFromCurrent,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(startFromCurrent: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Manual Slew Mode',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.manualSlew,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(manualSlew: value),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.compass, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Three-point polar alignment using plate solving. Calculates polar error and guides adjustments.',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    color: colors.info,
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

class InstructionSetInfo extends StatelessWidget {
  final NightshadeColors colors;
  final InstructionSetNode node;

  const InstructionSetInfo({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.listTree, size: 32, color: colors.accent),
          const SizedBox(height: 12),
          Text(
            'Container for sequential instructions. All children execute in order from top to bottom.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 13),
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Builder(builder: (context) => Text(
            '${node.childIds.length} children',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 12),
              color: colors.textMuted,
            ),
          )),
        ],
      ),
    );
  }
}

// =============================================================================
// COVER CALIBRATOR / FLAT PANEL PROPERTIES
// =============================================================================

class OpenCoverProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final OpenCoverNode node;

  const OpenCoverProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Timeout (seconds)',
          child: NodeNumberInput(
            colors: colors,
            value: node.timeoutSecs.toDouble(),
            min: 5,
            max: 300,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.round()),
                  );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Opens the motorized dust cover or flat panel lid. Requires a cover calibrator device.',
                  style: TextStyle(fontSize: Responsive.fontSize(context, 12), color: colors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CloseCoverProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CloseCoverNode node;

  const CloseCoverProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Timeout (seconds)',
          child: NodeNumberInput(
            colors: colors,
            value: node.timeoutSecs.toDouble(),
            min: 5,
            max: 300,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.round()),
                  );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Closes the motorized dust cover or flat panel lid. Requires a cover calibrator device.',
                  style: TextStyle(fontSize: Responsive.fontSize(context, 12), color: colors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CalibratorOnProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CalibratorOnNode node;

  const CalibratorOnProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Brightness',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: node.brightness.toDouble(),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      onChanged: (value) {
                        ref.read(currentSequenceProvider.notifier).updateNode(
                              node.copyWith(brightness: value.round()),
                            );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${node.brightness}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 13),
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '0 = off, 255 = maximum brightness',
                style: TextStyle(fontSize: Responsive.fontSize(context, 11), color: colors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Timeout (seconds)',
          child: NodeNumberInput(
            colors: colors,
            value: node.timeoutSecs.toDouble(),
            min: 5,
            max: 120,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.round()),
                  );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Turns on the flat panel light at the specified brightness. Use with flat frame sequences.',
                  style: TextStyle(fontSize: Responsive.fontSize(context, 12), color: colors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CalibratorOffProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CalibratorOffNode node;

  const CalibratorOffProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Timeout (seconds)',
          child: NodeNumberInput(
            colors: colors,
            value: node.timeoutSecs.toDouble(),
            min: 5,
            max: 120,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.round()),
                  );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.info.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Turns off the flat panel light. Use after flat frame capture is complete.',
                  style: TextStyle(fontSize: Responsive.fontSize(context, 12), color: colors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
