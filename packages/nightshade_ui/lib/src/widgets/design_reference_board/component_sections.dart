part of '../design_reference_board.dart';

// Components

class _ComponentsSection extends StatelessWidget {
  const _ComponentsSection({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection.boxed(
      title: 'Components',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SubLabel('Buttons', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              NightshadeButton(
                label: 'Capture',
                icon: LucideIcons.camera,
                onPressed: _noop,
              ),
              NightshadeButton(
                label: 'Settings',
                icon: LucideIcons.settings,
                variant: ButtonVariant.outline,
                onPressed: _noop,
              ),
              NightshadeButton(
                label: 'More',
                icon: LucideIcons.moreHorizontal,
                variant: ButtonVariant.ghost,
                onPressed: _noop,
              ),
              NightshadeButton(
                label: 'Stop',
                icon: LucideIcons.octagon,
                variant: ButtonVariant.destructive,
                onPressed: _noop,
              ),
              NightshadeButton(label: 'Disabled', icon: LucideIcons.lock),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Cards', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CardSpecimen(
                  title: 'STANDARD',
                  value: 'Ready',
                  variant: CardVariant.standard,
                ),
              ),
              SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: _CardSpecimen(
                  title: 'ELEVATED',
                  value: 'Guiding',
                  variant: CardVariant.elevated,
                ),
              ),
              SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: _CardSpecimen(
                  title: 'SELECTED',
                  value: 'Profile A',
                  variant: CardVariant.standard,
                  isSelected: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Inputs', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeTextField(
            label: 'Target',
            initialValue: 'M31',
            prefixIcon: LucideIcons.search,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeTextField(
            label: 'Exposure',
            initialValue: '120',
            suffix: 'sec',
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Row(
            children: [
              const NightshadeSwitch(value: true, onChanged: _noopBool),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Cooling',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              const NightshadeCheckbox(
                value: true,
                onChanged: _noopNullableBool,
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Autosave',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Sub-tabs', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Row(
            children: [
              SubTabButton(label: 'Capture', isSelected: true, onTap: _noop),
              SubTabButton(label: 'Focus', isSelected: false, onTap: _noop),
              SubTabButton(label: 'Guiding', isSelected: false, onTap: _noop),
            ],
          ),
        ],
      ),
    );
  }
}

// Status + feedback

class _StatusAndFeedbackSection extends StatelessWidget {
  const _StatusAndFeedbackSection({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return ShowcaseSection.boxed(
      title: 'Status & feedback',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SubLabel('Status pills', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              StatusPill(
                icon: LucideIcons.radio,
                label: 'Camera',
                value: 'Connected',
                status: StatusPillStatus.active,
              ),
              StatusPill(
                icon: LucideIcons.checkCircle2,
                label: 'Solver',
                value: 'Solved',
                status: StatusPillStatus.success,
              ),
              StatusPill(
                icon: LucideIcons.cloudRain,
                label: 'Weather',
                value: 'Warning',
                status: StatusPillStatus.warning,
              ),
              StatusPill(
                icon: LucideIcons.wifiOff,
                label: 'Mount',
                value: 'Offline',
                status: StatusPillStatus.error,
              ),
              StatusPill(
                icon: LucideIcons.circleDashed,
                label: 'Rotator',
                value: 'Idle',
                status: StatusPillStatus.inactive,
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Status dots', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Row(
            children: [
              StatusDot(color: colors.success),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Online',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              StatusDot(
                color: colors.warning,
                variant: StatusDotVariant.attention,
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Attention',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceLg),
              StatusDot(color: colors.error, variant: StatusDotVariant.urgent),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Urgent',
                style: NightshadeTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Progress', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeProgressBar(
            value: 0.64,
            label: 'Sequence progress',
            showPercentage: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          const NightshadeProgressBar(
            value: 0.4,
            state: NightshadeProgressState.warning,
            label: 'Disk usage',
            showPercentage: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _SubLabel('Alerts', colors: colors),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeAlert(
            title: 'Self-test complete',
            message: 'Backend, storage, and route metadata passed.',
            severity: NightshadeAlertSeverity.info,
            compact: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeAlert(
            title: 'Unsafe weather',
            message: 'Sequence start is blocked until safety clears.',
            severity: NightshadeAlertSeverity.warning,
            compact: true,
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          const NightshadeAlert(
            title: 'Restore failed',
            message: 'Backup file is missing a version field.',
            severity: NightshadeAlertSeverity.error,
            compact: true,
          ),
        ],
      ),
    );
  }
}

// Layout primitives (ScreenHeader / SectionHeader / SectionWell)

class _LayoutPrimitivesSection extends StatelessWidget {
  const _LayoutPrimitivesSection({required this.colors});

  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SubLabel('ScreenHeader', colors: colors),
        const SizedBox(height: NightshadeTokens.spaceSm),
        ClipRRect(
          borderRadius: NightshadeTokens.borderRadiusSm,
          child: const ScreenHeader(
            title: 'Sequencer',
            subtitle: 'Build and run unattended imaging sequences',
            icon: LucideIcons.listOrdered,
            trailing: NightshadeButton(
              label: 'Run',
              icon: LucideIcons.play,
              size: ButtonSize.small,
              onPressed: _noop,
            ),
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceLg),
        _SubLabel('SectionHeader + SectionWell', colors: colors),
        const SizedBox(height: NightshadeTokens.spaceSm),
        SectionWell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader(
                title: 'Cooling',
                subtitle: 'Set point and ramp behavior',
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Row(
                children: [
                  const NightshadeSwitch(value: true, onChanged: _noopBool),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Text(
                    'Cool camera before capture',
                    style: NightshadeTypography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
