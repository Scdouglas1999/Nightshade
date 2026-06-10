import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'widgets/auto_save_settings.dart';
import 'widgets/autofocus_settings.dart';
import 'widgets/file_path_settings.dart';
import 'widgets/predictive_af_settings.dart';

/// Stacks two existing settings widgets into one section without nesting two
/// competing scroll views.
///
/// Each child page already manages its own vertical scroll (most return a
/// `SettingsPage`, i.e. a `SingleChildScrollView`; one returns a plain column we
/// wrap below). Placing two scrollables in the same unbounded outer column would
/// throw an unbounded-height error, and a single outer scroll wrapping them
/// would nest same-axis viewports. Instead we give each child an [Expanded]
/// slot of the available height with a labelled divider between them, so each
/// scrolls within its own region and nothing overflows.
class _MergedSection extends StatelessWidget {
  const _MergedSection({
    required this.isMobile,
    required this.firstLabel,
    required this.first,
    required this.secondLabel,
    required this.second,
  });

  final bool isMobile;
  final String firstLabel;
  final Widget first;
  final String secondLabel;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubHeader(label: firstLabel, isMobile: isMobile),
        Expanded(child: first),
        _SubHeader(label: secondLabel, isMobile: isMobile, withTopBorder: true),
        Expanded(child: second),
      ],
    );
  }
}

/// A labelled band that introduces one of the two stacked pages.
class _SubHeader extends StatelessWidget {
  const _SubHeader({
    required this.label,
    required this.isMobile,
    this.withTopBorder = false,
  });

  final String label;
  final bool isMobile;
  final bool withTopBorder;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? NightshadeTokens.space2xl : 32,
        vertical: NightshadeTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(
          top: withTopBorder
              ? BorderSide(color: colors.border)
              : BorderSide.none,
          bottom: BorderSide(color: colors.border),
        ),
      ),
      child: Text(
        label,
        style: NightshadeTypography.overline.copyWith(
          color: colors.textSecondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Files & Storage = file paths + auto-save (keys `file-paths` + `auto-save`).
class FilesAndStorageSettings extends StatelessWidget {
  const FilesAndStorageSettings({super.key, this.isMobile = false});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return _MergedSection(
      isMobile: isMobile,
      firstLabel: 'FILE PATHS',
      first: FilePathSettings(isMobile: isMobile),
      secondLabel: 'AUTO-SAVE & BACKUPS',
      second: AutoSaveSettings(isMobile: isMobile),
    );
  }
}

/// Autofocus = autofocus + predictive AF (keys `autofocus` + `predictive-af`).
class AutofocusMergedSettings extends StatelessWidget {
  const AutofocusMergedSettings({super.key, this.isMobile = false});

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return _MergedSection(
      isMobile: isMobile,
      firstLabel: 'AUTOFOCUS',
      first: AutofocusSettingsPage(isMobile: isMobile),
      secondLabel: 'PREDICTIVE AUTOFOCUS',
      second: PredictiveAfSettingsPage(isMobile: isMobile),
    );
  }
}
