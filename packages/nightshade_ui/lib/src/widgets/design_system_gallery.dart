import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '_design_showcase_primitives.dart';
import '../components/nightshade_button.dart';
import '../components/nightshade_checkbox.dart';
import '../components/nightshade_dropdown.dart';
import '../components/nightshade_switch.dart';
import '../components/nightshade_switch_row.dart';
import '../components/nightshade_text_field.dart';
import '../components/status_dot.dart';
// Observatory wave 1
import '../components/instrument_pill.dart';
import '../components/page_header.dart';
import '../tokens/shell_chrome_metrics.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_decorations.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
// Observatory wave 2
import '../components/adaptive_tab_bar.dart';
import '../components/candidate_row.dart';
import '../components/checklist.dart';
import '../components/form_row.dart';
import '../components/glass.dart';
import '../components/list_rows.dart';
import '../components/night_band.dart';
import '../components/nightshade_banner.dart';
import '../components/nightshade_chip.dart';
import '../components/nightshade_icon_button.dart';
import '../components/nightshade_panel.dart';
import '../components/nightshade_toolbar.dart';
import '../components/readout.dart';
import '../components/section_title.dart';
import '../components/segmented_control.dart';
import '../dialogs/nightshade_dialog.dart';
import '../layout/side_panel.dart';
import 'empty_state.dart';

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
                          key: const ValueKey('gallery-button-secondary'),
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
                  // Observatory wave 2
                  const _ObservatorySections(),

                  // Observatory wave 1
                  ShowcaseSection.plain(
                    title: 'Instrument bar',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: ShellChromeMetrics.statusBarHeight,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            border: Border(
                              top: BorderSide(color: colors.border),
                            ),
                          ),
                          // The specimen scrolls the way the real bar's left
                          // group does, so a narrow gallery viewport shows a
                          // cut strip rather than an overflow stripe.
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: NightshadeTokens.spaceMd,
                            ),
                            children: [
                              InstrumentPill(
                                key: const ValueKey('gallery-instrument-pill'),
                                dotTone: InstrumentTone.success,
                                value: 'Running',
                                live: true,
                                onTap: _recordAction,
                              ),
                              const InstrumentSeparator(),
                              InstrumentPill(
                                icon: LucideIcons.camera,
                                dotTone: InstrumentTone.success,
                                value: 'ASI2600MM',
                                onTap: _recordAction,
                              ),
                              InstrumentPill(
                                icon: LucideIcons.mountain,
                                dotTone: InstrumentTone.success,
                                value: 'EQ6-R',
                                onTap: _recordAction,
                              ),
                              InstrumentPill(
                                icon: LucideIcons.crosshair,
                                dotTone: InstrumentTone.idle,
                                value: 'No guider',
                                onTap: _recordAction,
                              ),
                              const SizedBox(width: NightshadeTokens.space3xl),
                              const InstrumentPill(
                                icon: LucideIcons.thermometer,
                                value: '-10.0\u00B0C',
                                mono: true,
                              ),
                              const InstrumentSeparator(),
                              const InstrumentPill(
                                icon: LucideIcons.clock,
                                value: '22:41:08',
                                mono: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ShowcaseSection.plain(
                    title: 'Page header',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageHeader(
                          title: 'Sequencer',
                          icon: LucideIcons.listOrdered,
                          actions: [
                            NightshadeButton(
                              label: 'Start',
                              size: ButtonSize.small,
                              onPressed: _recordAction,
                            ),
                          ],
                        ),
                        const SizedBox(height: NightshadeTokens.spaceLg),
                        const PageHeader(
                          title: 'Equipment',
                          icon: LucideIcons.plug,
                          context: 'My Equipment',
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

// ---------------------------------------------------------------------------
// Observatory wave 2
// ---------------------------------------------------------------------------

/// Every component added or changed by 05-components.md, in one block.
///
/// Appended rather than woven into the sections above so the pre-overhaul
/// gallery keeps its evidence markers (the `design_system_gallery_missing`
/// audit rule reads this file for them) while the new kit gets a golden of its
/// own.
class _ObservatorySections extends StatefulWidget {
  const _ObservatorySections();

  @override
  State<_ObservatorySections> createState() => _ObservatorySectionsState();
}

class _ObservatorySectionsState extends State<_ObservatorySections> {
  /// How many sample controls have been pressed.
  ///
  /// The sheet's buttons need a REAL callback, not `() {}`: an empty callback
  /// is a dead control, `ui_consistency_audit`'s `empty_callback` rule counts
  /// every one of them, and a gallery that ships dead controls is teaching the
  /// pattern it exists to prevent.
  int _actions = 0;
  void _act() => setState(() => _actions += 1);
  void _actWith(Object? _) => _act();

  int _segment = 0;
  int _underlineTab = 0;
  int _stripSection = 1;
  bool _chipSelected = true;

  static final DateTime _sunset = DateTime(2026, 9, 9, 19, 12);
  static final DateTime _astroDark = DateTime(2026, 9, 9, 20, 48);
  static final DateTime _astroDawn = DateTime(2026, 9, 10, 4, 51);
  static final DateTime _sunrise = DateTime(2026, 9, 10, 6, 24);
  static final DateTime _now = DateTime(2026, 9, 9, 22, 41);

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
          child: Text(
            'Observatory sample actions: $_actions',
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Panels and wells',
          child: Wrap(
            spacing: NightshadeTokens.spaceMd,
            runSpacing: NightshadeTokens.spaceMd,
            children: [
              SizedBox(
                width: 260,
                child: NightshadePanel(
                  head: const PanelHead(
                    label: 'Equipment',
                    icon: LucideIcons.activity,
                  ),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: NightshadeDecorations.well(colors),
                    child: Text(
                      'well inside a panel (max depth)',
                      style: NightshadeTypography.caption.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: NightshadePanel(
                  selected: true,
                  head: const PanelHead(label: 'Selected panel'),
                  child: Text(
                    'A primary ring at 50%, not a tinted fill.',
                    style: NightshadeTypography.bodySm.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const ShowcaseSection.plain(
          title: 'Readouts',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NightshadePanel(
                child: ReadoutRow(
                  children: [
                    Readout(
                      value: '-10.0',
                      unit: '°C',
                      label: 'Sensor',
                      size: ReadoutSize.lg,
                    ),
                    Readout(
                      value: '2.49',
                      unit: 'px',
                      label: 'HFR',
                      size: ReadoutSize.lg,
                    ),
                    Readout(value: '0.42', unit: '"', label: 'RMS'),
                    Readout(value: '25 000', label: 'Position'),
                    Readout(
                      value: '13h 29m 54s',
                      label: 'RA',
                      size: ReadoutSize.sm,
                    ),
                    Readout(value: null, label: 'Guide star'),
                  ],
                ),
              ),
              SizedBox(height: NightshadeTokens.spaceMd),
              NightshadePanel(
                child: KeyValueList(
                  rows: [
                    ('Clouds', '4%'),
                    ('Wind', '6 km/h'),
                    ('Dew point margin', '5.3°'),
                  ],
                ),
              ),
            ],
          ),
        ),
        ShowcaseSection.plain(
          title: 'Underline tabs',
          child: SizedBox(
            height: 40,
            child: AdaptiveTabBar(
              horizontalPadding: 0,
              tabs: const [
                AdaptiveTab(label: 'Builder'),
                AdaptiveTab(label: 'Templates'),
                AdaptiveTab(label: 'Saved'),
                AdaptiveTab(label: 'History', count: '3'),
              ],
              selectedIndex: _underlineTab,
              onSelected: (i) => setState(() => _underlineTab = i),
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Segmented control',
          child: SegmentedControl(
            segments: const ['Nodes', 'Snippets', 'Queue'],
            selectedIndex: _segment,
            onSelected: (i) => setState(() => _segment = i),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Buttons and icon buttons',
          child: Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              NightshadeButton(
                label: 'Primary',
                icon: LucideIcons.play,
                onPressed: _act,
              ),
              NightshadeButton(
                label: 'Secondary',
                variant: ButtonVariant.secondary,
                onPressed: _act,
              ),
              NightshadeButton(
                label: 'Ghost',
                variant: ButtonVariant.ghost,
                onPressed: _act,
              ),
              NightshadeButton(
                label: 'Stop',
                icon: LucideIcons.square,
                variant: ButtonVariant.destructive,
                onPressed: _act,
              ),
              NightshadeButton(
                label: 'Start',
                icon: LucideIcons.play,
                variant: ButtonVariant.start,
                onPressed: _act,
              ),
              const NightshadeButton(label: 'Disabled'),
              NightshadeButton(
                label: 'Small',
                size: ButtonSize.small,
                variant: ButtonVariant.secondary,
                onPressed: _act,
              ),
              NightshadeButton(
                label: 'Large',
                size: ButtonSize.large,
                variant: ButtonVariant.secondary,
                onPressed: _act,
              ),
              NightshadeIconButton(
                icon: LucideIcons.settings,
                tooltip: 'Settings',
                onPressed: _act,
              ),
              NightshadeIconButton(
                icon: LucideIcons.layers,
                tooltip: 'Layers',
                selected: true,
                onPressed: _act,
              ),
            ],
          ),
        ),
        ShowcaseSection.plain(
          title: 'Toolbar',
          child: NightshadeToolbar(
            overflowIcon: LucideIcons.moreHorizontal,
            onOverflowPressed: _act,
            overflow: [
              NightshadeIconButton(
                icon: LucideIcons.share2,
                tooltip: 'Share',
                size: IconButtonSize.sm,
                onPressed: _act,
              ),
              NightshadeIconButton(
                icon: LucideIcons.download,
                tooltip: 'Export',
                size: IconButtonSize.sm,
                onPressed: _act,
              ),
            ],
            groups: [
              [
                NightshadeIconButton(
                  icon: LucideIcons.undo2,
                  tooltip: 'Undo',
                  size: IconButtonSize.sm,
                  onPressed: _act,
                ),
                NightshadeIconButton(
                  icon: LucideIcons.redo2,
                  tooltip: 'Redo',
                  size: IconButtonSize.sm,
                  onPressed: _act,
                ),
              ],
              [
                NightshadeButton(
                  label: 'Timeline',
                  icon: LucideIcons.clock,
                  size: ButtonSize.small,
                  variant: ButtonVariant.ghost,
                  onPressed: _act,
                ),
                NightshadeButton(
                  label: 'Map',
                  icon: LucideIcons.map,
                  size: ButtonSize.small,
                  variant: ButtonVariant.ghost,
                  onPressed: _act,
                ),
              ],
            ],
          ),
        ),
        ShowcaseSection.plain(
          title: 'Fields and form rows',
          // The gallery is rendered at 390px wide in one of its tests; the
          // fixed-width specimens scroll rather than overflow.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 360,
              child: Column(
                children: [
                  const FormRow(
                    label: 'Exposure',
                    child: NightshadeTextField(
                      initialValue: '120',
                      suffix: 's',
                      mono: true,
                    ),
                  ),
                  const SizedBox(height: FormRow.rowGap),
                  FormRow(
                    label: 'Frame type',
                    child: NightshadeDropdown(
                      value: 'Light',
                      items: const ['Light', 'Dark', 'Flat', 'Bias'],
                      onChanged: _actWith,
                    ),
                  ),
                  const SizedBox(height: FormRow.rowGap),
                  const FormRow(
                    label: 'Search',
                    child: NightshadeTextField(
                      hint: 'Search nodes…',
                      prefixIcon: LucideIcons.search,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Chips and status dots',
          child: Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const NightshadeChip(
                label: 'Connected',
                tone: ChipTone.success,
                dot: true,
              ),
              const NightshadeChip(
                label: 'Session only',
                tone: ChipTone.warning,
                dot: true,
              ),
              const NightshadeChip(
                label: 'Disconnected',
                tone: ChipTone.error,
                dot: true,
              ),
              NightshadeChip(
                label: 'Transit 01:08',
                tone: ChipTone.primary,
                selected: _chipSelected,
                onTap: () => setState(() => _chipSelected = !_chipSelected),
              ),
              const NightshadeChip(label: '27 nodes'),
              NightshadeFilterChip(
                label: 'Type: any',
                trailingIcon: LucideIcons.chevronDown,
                onTap: _act,
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusDot(color: colors.success, live: true),
                  const SizedBox(width: NightshadeChip.innerGap),
                  Text(
                    'Live dot',
                    style: NightshadeChip.textStyle().copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ShowcaseSection.plain(
          title: 'Banner',
          child: Column(
            children: [
              NightshadeBanner(
                title: 'Catalogs not installed.',
                message:
                    'Annotations and plate solving need HYG + OpenNGC (60 MB).',
                action: NightshadeButton(
                  label: 'Download',
                  size: ButtonSize.small,
                  onPressed: _act,
                ),
                onDismiss: _act,
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              const NightshadeBanner(
                title: 'Ends after astro dawn.',
                message: 'Reduce count to 32 to finish by 04:51.',
                tone: BannerTone.warning,
              ),
            ],
          ),
        ),
        ShowcaseSection.plain(
          title: 'Empty state',
          // A MINIMUM, not a fixed height: the sentence wraps to three lines at
          // the 390px width the gallery is also tested at, and a fixed box
          // would clip it there.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 170),
            child: NightshadePanel(
              child: EmptyState(
                icon: LucideIcons.folderOpen,
                title: 'Nothing captured yet',
                body:
                    'Start a capture or a sequence and this fills in as frames '
                    'arrive.',
                action: NightshadeButton(
                  label: 'Go to Imaging',
                  size: ButtonSize.small,
                  variant: ButtonVariant.secondary,
                  onPressed: _act,
                ),
              ),
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Dialog',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: NightshadeDialog.widthConfirm,
              child: NightshadeDialogSurface(
                framed: true,
                title: 'Replace the current sequence?',
                showCloseButton: false,
                actions: [
                  NightshadeButton(
                    label: 'Cancel',
                    variant: ButtonVariant.ghost,
                    onPressed: _act,
                  ),
                  NightshadeButton(
                    label: 'Save first',
                    variant: ButtonVariant.secondary,
                    onPressed: _act,
                  ),
                  NightshadeButton(label: 'Replace', onPressed: _act),
                ],
                child: Text(
                  'Loading “Mono LRGB M51” discards 3 unsaved changes '
                  'to “Untitled sequence”.',
                  style: NightshadeTypography.bodySm.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Glass',
          child: SizedBox(
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: NightshadeColors.dark.background,
                borderRadius: NightshadeTokens.borderRadiusLg,
              ),
              child: Stack(
                children: [
                  const Positioned(
                    left: NightshadeTokens.spaceMd,
                    bottom: NightshadeTokens.spaceMd,
                    child: Glass(
                      child: ReadoutRow(
                        gap: DeviceRow.readoutGap,
                        children: [
                          Readout(value: '2.49', unit: 'px', label: 'HFR'),
                          Readout(value: '43', label: 'Stars'),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: NightshadeTokens.spaceMd,
                    top: NightshadeTokens.spaceMd,
                    child: Glass(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusDot(color: colors.success, live: true),
                          const SizedBox(width: NightshadeTokens.spaceSm),
                          Text(
                            'Exposing 42 / 120 s',
                            style: NightshadeTypography.caption.copyWith(
                              color: NightshadeColors.dark.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Side panel',
          child: SizedBox(
            height: 280,
            child: Row(
              children: [
                const Spacer(),
                SidePanel(
                  sections: const [
                    SidePanelSection(
                      icon: LucideIcons.sliders,
                      tooltip: 'Capture',
                    ),
                    SidePanelSection(
                      icon: LucideIcons.target,
                      tooltip: 'Target',
                    ),
                    SidePanelSection(
                      icon: LucideIcons.history,
                      tooltip: 'History',
                    ),
                  ],
                  selectedSection: _stripSection,
                  onSectionSelected: (i) => setState(() => _stripSection = i),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle(
                        title: 'Target',
                        icon: LucideIcons.target,
                      ),
                      ListRow(
                        title: 'M51 Whirlpool',
                        icon: LucideIcons.star,
                        trailing: '22:41',
                        onTap: _act,
                      ),
                      ListRow(
                        title: 'NGC 7000',
                        icon: LucideIcons.star,
                        trailing: '23:04',
                        onTap: _act,
                      ),
                      const SizedBox(height: SidePanel.sectionGap),
                      const SectionTitle(
                        title: 'Devices',
                        icon: LucideIcons.aperture,
                      ),
                      DeviceRow(
                        name: 'Simulated camera',
                        leading: StatusDot(color: colors.success),
                        readouts: const [
                          Readout(
                            value: '-10.0',
                            unit: '°C',
                            label: 'Temp',
                            size: ReadoutSize.sm,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Candidate',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 560,
              child: Candidate(
                score: '94',
                name: 'M51 Whirlpool Galaxy',
                detail: 'Galaxy · 11.2 arcmin · mag 8.4',
                readouts: const [
                  Readout(value: '61', unit: '°', label: 'Alt'),
                  Readout(value: '01:08', label: 'Transit'),
                ],
                window: const CandidateWindow(start: 0.2, end: 0.8, now: 0.45),
                action: NightshadeButton(
                  label: 'Plan',
                  size: ButtonSize.small,
                  variant: ButtonVariant.secondary,
                  onPressed: _act,
                ),
              ),
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Checklist',
          child: NightshadePanel(
            child: Checklist(
              steps: [
                const ChecklistStep(
                  title: 'Set your observing site',
                  detail: 'Boston, 42.36 / -71.06',
                  state: ChecklistStepState.done,
                ),
                ChecklistStep(
                  title: 'Connect a camera and a mount',
                  detail: 'Nothing is connected yet.',
                  state: ChecklistStepState.next,
                  action: NightshadeButton(
                    label: 'Open Equipment',
                    size: ButtonSize.small,
                    variant: ButtonVariant.secondary,
                    onPressed: _act,
                  ),
                ),
                const ChecklistStep(
                  title: 'Install the catalogs',
                  detail: 'HYG + OpenNGC, 60 MB.',
                ),
              ],
            ),
          ),
        ),
        ShowcaseSection.plain(
          title: 'Night band',
          child: NightBand(
            sunset: _sunset,
            astroDark: _astroDark,
            astroDawn: _astroDawn,
            sunrise: _sunrise,
            now: _now,
            targetAltitudeCurve: const [
              0.1,
              0.3,
              0.55,
              0.74,
              0.86,
              0.9,
              0.82,
              0.63,
              0.4,
              0.18,
              0.05,
            ],
            imageableWindow: NightBandWindow(
              start: _astroDark,
              end: DateTime(2026, 9, 10, 3, 10),
            ),
            events: [
              NightBandEvent(time: _sunset, label: '19:12 sunset'),
              NightBandEvent(time: _astroDark, label: '20:48 astro dark'),
              NightBandEvent(time: _astroDawn, label: '04:51 astro dawn'),
              NightBandEvent(time: _sunrise, label: '06:24 sunrise'),
            ],
          ),
        ),
      ],
    );
  }
}
