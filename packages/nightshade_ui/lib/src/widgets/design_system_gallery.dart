import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '_design_showcase_primitives.dart';
import '../components/nightshade_alert.dart';
import '../components/nightshade_button.dart';
import '../components/nightshade_card.dart';
import '../components/nightshade_checkbox.dart';
import '../components/nightshade_dropdown.dart';
import '../components/nightshade_switch.dart';
import '../components/nightshade_switch_row.dart';
import '../components/nightshade_text_field.dart';
import '../components/nav_item.dart';
import '../components/status_pill.dart';
import '../components/status_dot.dart';
import '../components/sub_tab_button.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_decorations.dart';
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
  int _selectedNavItem = 0;
  bool _navExpanded = true;
  int _actionCount = 0;
  int _statusDotAttentionSeed = 0;

  void _recordAction() {
    setState(() => _actionCount += 1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

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
                  ShowcaseSection.plain(
                    title: 'Color Palette',
                    child: Wrap(
                      spacing: NightshadeTokens.spaceMd,
                      runSpacing: NightshadeTokens.spaceMd,
                      children: [
                        ShowcaseSwatch.gallery(
                          label: 'Primary',
                          color: colors.primary,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Accent',
                          color: colors.accent,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Background',
                          color: colors.background,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Surface',
                          color: colors.surface,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Surface Alt',
                          color: colors.surfaceAlt,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Success',
                          color: colors.success,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Warning',
                          color: colors.warning,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Error',
                          color: colors.error,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Info',
                          color: colors.info,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Text Primary',
                          color: colors.textPrimary,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Text Secondary',
                          color: colors.textSecondary,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Text Muted',
                          color: colors.textMuted,
                        ),
                        ShowcaseSwatch.gallery(
                          label: 'Border',
                          color: colors.border,
                        ),
                      ],
                    ),
                  ),
                  ShowcaseSection.plain(
                    title: 'Typography',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TypographySpecimen(
                          label: 'H2 — Section title',
                          sample: 'Sequence Run',
                          style: NightshadeTypography.h2,
                          colors: colors,
                        ),
                        _TypographySpecimen(
                          label: 'Telemetry Lg — Hero live values',
                          sample: '02:45',
                          style: NightshadeTypography.telemetryLg,
                          colors: colors,
                        ),
                        _TypographySpecimen(
                          label: 'Telemetry Md — Secondary live values',
                          sample: '18 min',
                          style: NightshadeTypography.telemetryMd,
                          colors: colors,
                        ),
                        _TypographySpecimen(
                          label: 'Label Quiet — Sidebar descriptions',
                          sample: 'Per-frame countdown and sequence totals',
                          style: NightshadeTypography.labelQuiet,
                          colors: colors,
                          muted: true,
                        ),
                        _TypographySpecimen(
                          label: 'Mono — Technical text',
                          sample: 'RA 05h 35m 17s',
                          style: NightshadeTypography.mono,
                          colors: colors,
                        ),
                      ],
                    ),
                  ),
                  ShowcaseSection.plain(
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
                  ShowcaseSection.plain(
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
                  ShowcaseSection.plain(
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
                            key: const ValueKey('gallery-switch'),
                            value: _switchValue,
                            onChanged: (value) {
                              setState(() => _switchValue = value);
                            },
                          ),
                        ),
                        const SizedBox(height: NightshadeTokens.spaceSm),
                        NightshadeSwitchRow(
                          label: 'Dew heater',
                          subtitle: 'Expanded row with label and subtitle',
                          value: _switchValue,
                          onChanged: (value) {
                            setState(() => _switchValue = value);
                          },
                        ),
                      ],
                    ),
                  ),
                  ShowcaseSection.plain(
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
                  ShowcaseSection.plain(
                    title: 'Navigation',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: NightshadeTokens.spaceMd,
                          runSpacing: NightshadeTokens.spaceSm,
                          children: [
                            NightshadeButton(
                              label: _navExpanded
                                  ? 'Collapse nav'
                                  : 'Expand nav',
                              icon: LucideIcons.panelLeftClose,
                              variant: ButtonVariant.outline,
                              onPressed: () {
                                setState(() => _navExpanded = !_navExpanded);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: NightshadeTokens.spaceMd),
                        Container(
                          width: _navExpanded ? 240 : 72,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: NightshadeTokens.borderRadiusMd,
                            border: Border.all(color: colors.border),
                          ),
                          child: Column(
                            children: [
                              for (final entry in const [
                                MapEntry(0, (
                                  LucideIcons.layoutDashboard,
                                  'Dashboard',
                                  'Overview and status',
                                )),
                                MapEntry(1, (
                                  LucideIcons.camera,
                                  'Imaging',
                                  'Capture and review',
                                )),
                                MapEntry(2, (
                                  LucideIcons.listOrdered,
                                  'Sequencer',
                                  'Run automation',
                                )),
                              ])
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    NightshadeTokens.spaceSm,
                                    NightshadeTokens.spaceXs,
                                    NightshadeTokens.spaceSm,
                                    0,
                                  ),
                                  child: NavItem(
                                    key: ValueKey(
                                      'gallery-nav-${entry.key}-'
                                      '${_navExpanded ? 'expanded' : 'collapsed'}',
                                    ),
                                    icon: entry.value.$1,
                                    label: entry.value.$2,
                                    description: entry.value.$3,
                                    isSelected: _selectedNavItem == entry.key,
                                    isExpanded: _navExpanded,
                                    onTap: () {
                                      setState(
                                        () => _selectedNavItem = entry.key,
                                      );
                                    },
                                  ),
                                ),
                              const SizedBox(height: NightshadeTokens.spaceSm),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ShowcaseSection.plain(
                    title: 'Decorations',
                    child: Wrap(
                      spacing: NightshadeTokens.spaceMd,
                      runSpacing: NightshadeTokens.spaceMd,
                      children: [
                        _DecorationSpecimen(
                          label: 'Nav Selected',
                          decoration: NightshadeDecorations.navSelected(colors),
                          width: 140,
                          height: 40,
                        ),
                        _DecorationSpecimen(
                          label: 'Card Selected',
                          decoration: NightshadeDecorations.cardSelected(
                            colors.primary,
                            background: colors.surface,
                          ),
                          width: 140,
                          height: 72,
                        ),
                        _DecorationSpecimen(
                          label: 'Card Hover',
                          decoration: NightshadeDecorations.cardHover(colors),
                          width: 140,
                          height: 72,
                        ),
                        _DecorationSpecimen(
                          label: 'Drag Feedback',
                          decoration: NightshadeDecorations.dragFeedback(
                            colors,
                          ),
                          width: 140,
                          height: 72,
                        ),
                        _DecorationSpecimen(
                          label: 'KPI Badge',
                          decoration: NightshadeDecorations.kpiBadge(
                            colors.success,
                          ),
                          width: 44,
                          height: 44,
                        ),
                      ],
                    ),
                  ),
                  ShowcaseSection.plain(
                    title: 'Chips and Status Pills',
                    child: Wrap(
                      spacing: NightshadeTokens.spaceMd,
                      runSpacing: NightshadeTokens.spaceMd,
                      children: [
                        _GalleryChip(label: 'Luminance', color: colors.primary),
                        _GalleryChip(label: 'Ha', color: colors.error),
                        _GalleryChip(label: 'OIII', color: colors.info),
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
                  ShowcaseSection.plain(
                    title: 'Status Dots',
                    child: Wrap(
                      spacing: NightshadeTokens.spaceLg,
                      runSpacing: NightshadeTokens.spaceMd,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StatusDotSample(
                          label: 'Static',
                          dot: StatusDot(
                            key: const ValueKey('gallery-status-dot-static'),
                            color: colors.success,
                          ),
                        ),
                        _StatusDotSample(
                          label: 'Attention',
                          dot: StatusDot(
                            key: ValueKey(
                              'gallery-status-dot-attention-'
                              '$_statusDotAttentionSeed',
                            ),
                            color: _statusDotAttentionSeed.isEven
                                ? colors.warning
                                : colors.error,
                            variant: StatusDotVariant.attention,
                          ),
                        ),
                        NightshadeButton(
                          key: const ValueKey('gallery-status-dot-flash'),
                          label: 'Flash',
                          size: ButtonSize.small,
                          variant: ButtonVariant.outline,
                          onPressed: () {
                            setState(() => _statusDotAttentionSeed += 1);
                          },
                        ),
                        _StatusDotSample(
                          label: 'Urgent',
                          dot: StatusDot(
                            key: const ValueKey('gallery-status-dot-urgent'),
                            color: colors.error,
                            variant: StatusDotVariant.urgent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ShowcaseSection.plain(
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

class _GalleryChip extends StatelessWidget {
  final String label;
  final Color color;

  const _GalleryChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: NightshadeDecorations.emphasisSurface(
        color,
        borderRadius: NightshadeTokens.borderRadiusSm,
      ),
      child: Text(
        label,
        style: NightshadeTypography.caption.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _ControlRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

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

class _DecorationSpecimen extends StatelessWidget {
  final String label;
  final BoxDecoration decoration;
  final double width;
  final double height;

  const _DecorationSpecimen({
    required this.label,
    required this.decoration,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: width, height: height, decoration: decoration),
        const SizedBox(height: NightshadeTokens.spaceXs),
        Text(
          label,
          style: NightshadeTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StatusDotSample extends StatelessWidget {
  final String label;
  final Widget dot;

  const _StatusDotSample({required this.label, required this.dot});

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          label,
          style: NightshadeTypography.caption.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _TypographySpecimen extends StatelessWidget {
  final String label;
  final String sample;
  final TextStyle style;
  final NightshadeColors colors;
  final bool muted;

  const _TypographySpecimen({
    required this.label,
    required this.sample,
    required this.style,
    required this.colors,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: NightshadeTypography.caption.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            sample,
            style: style.copyWith(
              color: muted ? colors.textMuted : colors.textPrimary,
            ),
          ),
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
    final colors = context.nightshadeColors;

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
            style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
