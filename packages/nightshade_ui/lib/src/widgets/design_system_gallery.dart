import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../components/nightshade_alert.dart';
import '../components/nightshade_button.dart';
import '../components/nightshade_card.dart';
import '../components/nightshade_checkbox.dart';
import '../components/nightshade_dropdown.dart';
import '../components/nightshade_switch.dart';
import '../components/nightshade_text_field.dart';
import '../components/status_pill.dart';
import '../components/sub_tab_button.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// Renderable design-system gallery for release visual QA and widget snapshots.
class NightshadeDesignSystemGallery extends StatefulWidget {
  const NightshadeDesignSystemGallery({super.key});

  @override
  State<NightshadeDesignSystemGallery> createState() =>
      _NightshadeDesignSystemGalleryState();
}

class _NightshadeDesignSystemGalleryState
    extends State<NightshadeDesignSystemGallery> {
  bool _checkboxValue = true;
  bool _switchValue = true;
  String? _dropdownValue = 'Camera';
  int _selectedTab = 0;
  int _actionCount = 0;

  void _recordAction() {
    setState(() => _actionCount += 1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Design System Gallery',
                    style: NightshadeTypography.h2.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: NightshadeTokens.spaceSm),
                  Text(
                    'Sample actions: $_actionCount',
                    style: NightshadeTypography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: NightshadeTokens.spaceLg),
                  _GallerySection(
                    title: 'Buttons',
                    child: Wrap(
                      spacing: NightshadeTokens.spaceMd,
                      runSpacing: NightshadeTokens.spaceMd,
                      children: [
                        NightshadeButton(
                          key: const ValueKey('gallery-button-primary'),
                          label: 'Capture',
                          icon: LucideIcons.camera,
                          onPressed: _recordAction,
                        ),
                        NightshadeButton(
                          label: 'Secondary',
                          icon: LucideIcons.settings,
                          variant: ButtonVariant.outline,
                          onPressed: _recordAction,
                        ),
                        NightshadeButton(
                          label: 'Ghost',
                          icon: LucideIcons.moreHorizontal,
                          variant: ButtonVariant.ghost,
                          onPressed: _recordAction,
                        ),
                        NightshadeButton(
                          label: 'Stop',
                          icon: LucideIcons.octagon,
                          variant: ButtonVariant.destructive,
                          onPressed: _recordAction,
                        ),
                        NightshadeButton(
                          label: 'Saving',
                          icon: LucideIcons.save,
                          isLoading: true,
                          onPressed: _recordAction,
                        ),
                        const NightshadeButton(
                          label: 'Disabled',
                          icon: LucideIcons.lock,
                        ),
                      ],
                    ),
                  ),
                  _GallerySection(
                    title: 'Cards',
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth < 760 ? 1 : 3;
                        return GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: columns,
                          crossAxisSpacing: NightshadeTokens.spaceMd,
                          mainAxisSpacing: NightshadeTokens.spaceMd,
                          childAspectRatio: columns == 1 ? 3.8 : 2.1,
                          children: const [
                            _GalleryCardSpecimen(
                              title: 'Standard',
                              value: 'Ready',
                              variant: CardVariant.standard,
                            ),
                            _GalleryCardSpecimen(
                              title: 'Elevated',
                              value: 'Guiding',
                              variant: CardVariant.elevated,
                            ),
                            _GalleryCardSpecimen(
                              title: 'Selected',
                              value: 'Profile A',
                              isSelected: true,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  _GallerySection(
                    title: 'Inputs',
                    child: Wrap(
                      spacing: NightshadeTokens.spaceMd,
                      runSpacing: NightshadeTokens.spaceMd,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const SizedBox(
                          width: 260,
                          child: NightshadeTextField(
                            label: 'Target',
                            initialValue: 'M31',
                            prefixIcon: LucideIcons.search,
                          ),
                        ),
                        const SizedBox(
                          width: 260,
                          child: NightshadeTextField(
                            label: 'Exposure',
                            initialValue: '120',
                            suffix: 'sec',
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: NightshadeDropdown(
                            key: const ValueKey('gallery-dropdown'),
                            value: _dropdownValue,
                            items: const ['Camera', 'Mount', 'Focuser'],
                            onChanged: (value) {
                              setState(() => _dropdownValue = value);
                            },
                            isExpanded: true,
                          ),
                        ),
                        _ControlRow(
                          label: 'Autosave',
                          child: NightshadeCheckbox(
                            value: _checkboxValue,
                            onChanged: (value) {
                              setState(() => _checkboxValue = value ?? false);
                            },
                          ),
                        ),
                        _ControlRow(
                          label: 'Cooling',
                          child: NightshadeSwitch(
                            value: _switchValue,
                            onChanged: (value) {
                              setState(() => _switchValue = value);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  _GallerySection(
                    title: 'Tabs',
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final entry in const [
                            MapEntry(0, 'Capture'),
                            MapEntry(1, 'Focus'),
                            MapEntry(2, 'Guiding'),
                          ])
                            SubTabButton(
                              label: entry.value,
                              isSelected: _selectedTab == entry.key,
                              onTap: () {
                                setState(() => _selectedTab = entry.key);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  _GallerySection(
                    title: 'Chips and Status Pills',
                    child: Wrap(
                      spacing: NightshadeTokens.spaceMd,
                      runSpacing: NightshadeTokens.spaceMd,
                      children: [
                        _GalleryChip(
                          label: 'Luminance',
                          color: colors.primary,
                        ),
                        _GalleryChip(
                          label: 'Ha',
                          color: colors.error,
                        ),
                        _GalleryChip(
                          label: 'OIII',
                          color: colors.info,
                        ),
                        StatusPill(
                          key: const ValueKey('gallery-status-active'),
                          icon: LucideIcons.radio,
                          label: 'Camera',
                          value: 'Connected',
                          status: StatusPillStatus.active,
                          onTap: _recordAction,
                        ),
                        StatusPill(
                          key: const ValueKey('gallery-status-success'),
                          icon: LucideIcons.checkCircle2,
                          label: 'Solver',
                          value: 'Solved',
                          status: StatusPillStatus.success,
                          onTap: _recordAction,
                        ),
                        StatusPill(
                          icon: LucideIcons.cloudRain,
                          label: 'Weather',
                          value: 'Warning',
                          status: StatusPillStatus.warning,
                          onTap: _recordAction,
                        ),
                        StatusPill(
                          icon: LucideIcons.wifiOff,
                          label: 'Mount',
                          value: 'Offline',
                          status: StatusPillStatus.error,
                          onTap: _recordAction,
                        ),
                        StatusPill(
                          key: const ValueKey('gallery-status-inactive'),
                          icon: LucideIcons.circleDashed,
                          label: 'Rotator',
                          value: 'Idle',
                          status: StatusPillStatus.inactive,
                          onTap: _recordAction,
                        ),
                      ],
                    ),
                  ),
                  _GallerySection(
                    title: 'Alerts',
                    child: Column(
                      children: [
                        NightshadeAlert(
                          key: const ValueKey('gallery-alert-info'),
                          title: 'Self-test complete',
                          message:
                              'Backend, storage, and route metadata passed.',
                          severity: NightshadeAlertSeverity.info,
                          compact: true,
                          action: NightshadeButton(
                            label: 'View',
                            size: ButtonSize.small,
                            variant: ButtonVariant.outline,
                            onPressed: _recordAction,
                          ),
                        ),
                        const SizedBox(height: NightshadeTokens.spaceMd),
                        const NightshadeAlert(
                          title: 'Unsafe weather',
                          message:
                              'Sequence start is blocked until safety clears.',
                          severity: NightshadeAlertSeverity.warning,
                          compact: true,
                        ),
                        const SizedBox(height: NightshadeTokens.spaceMd),
                        const NightshadeAlert(
                          title: 'Restore failed',
                          message: 'Backup file is missing a version field.',
                          severity: NightshadeAlertSeverity.error,
                          compact: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GallerySection extends StatelessWidget {
  final String title;
  final Widget child;

  const _GallerySection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.space2xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: NightshadeTypography.h4.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          child,
        ],
      ),
    );
  }
}

class _GalleryCardSpecimen extends StatelessWidget {
  final String title;
  final String value;
  final CardVariant variant;
  final bool isSelected;

  const _GalleryCardSpecimen({
    required this.title,
    required this.value,
    this.variant = CardVariant.standard,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      variant: variant,
      isSelected: isSelected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: NightshadeTypography.label.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            value,
            style: NightshadeTypography.h4.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryChip extends StatelessWidget {
  final String label;
  final Color color;

  const _GalleryChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: NightshadeTokens.borderRadiusSm,
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: NightshadeTypography.caption.copyWith(
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _ControlRow({
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: NightshadeTypography.bodySm.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        child,
      ],
    );
  }
}
