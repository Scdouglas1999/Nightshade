// Part of ../node_properties_panel.dart -- extracted for maintainability.
//
// Properties widgets for the guiding instruction nodes: StartGuiding (settle
// pixels/time/timeout + auto-select star) and StopGuiding (a descriptive
// info card; the node has no configurable fields). These were previously
// missing from the dispatcher and fell through to the "No property editor"
// fallback (audit P1-19).
part of '../node_properties_panel.dart';

class _StartGuidingProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final StartGuidingNode node;

  const _StartGuidingProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Guiding Settings',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Settle Threshold',
          child: _NumberInput(
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
        _PropertyField(
          colors: colors,
          label: 'Settle Time',
          child: _NumberInput(
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
              ref.read(sequencerDefaultsProvider.notifier).updateDitherDefaults(
                    settleTime: value,
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Settle Timeout',
          child: _NumberInput(
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
        _PropertyField(
          colors: colors,
          label: 'Auto-select Star',
          child: _ToggleSwitch(
            colors: colors,
            value: node.autoSelectStar,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(autoSelectStar: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _StopGuidingProperties extends StatelessWidget {
  final NightshadeColors colors;
  final StopGuidingNode node;

  const _StopGuidingProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.xCircle, size: 32, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            'Stops PHD2 guiding. The mount continues tracking, but guide '
            'corrections are no longer applied. This instruction has no '
            'additional settings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
