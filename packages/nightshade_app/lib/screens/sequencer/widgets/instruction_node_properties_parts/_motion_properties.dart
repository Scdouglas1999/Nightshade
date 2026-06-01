// Part of ../instruction_node_properties.dart -- extracted for maintainability.
//
// Mount/optics motion properties widgets: CenterProperties, AutofocusProperties, RotatorProperties, SlewProperties, MeridianFlipProperties, PolarAlignmentProperties.
part of '../instruction_node_properties.dart';

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

  const AutofocusProperties(
      {super.key, required this.colors, required this.node});

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
  Widget _buildDefaultsDisplay(
      BuildContext context, AutofocusSettings afSettings) {
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
          _buildInfoRow(
              context, 'Steps Out', '${afSettings.initialOffsetSteps}'),
          _buildInfoRow(context, 'Exposure', '${afSettings.exposureTime}s'),
          _buildInfoRow(
              context, 'Exposures/Point', '${afSettings.exposuresPerPoint}'),
          _buildInfoRow(context, 'Binning',
              '${afSettings.binning}x${afSettings.binning}'),
          _buildInfoRow(
              context, 'R\u00B2 Threshold', '${afSettings.rSquaredThreshold}'),
          _buildInfoRow(
              context, 'Backlash Comp', afSettings.backlashCompMethod),
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
