import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';
part 'autofocus_settings/filter_settings_row.dart';
part 'autofocus_settings/filter_settings_mobile_card.dart';

class AutofocusSettingsPage extends ConsumerStatefulWidget {
  final bool isMobile;

  /// When true, render without an own scroll view (embedded in a merged
  /// section's single outer scroll) and without the page header.
  final bool embedded;

  const AutofocusSettingsPage({
    super.key,
    this.isMobile = false,
    this.embedded = false,
  });

  @override
  ConsumerState<AutofocusSettingsPage> createState() =>
      _AutofocusSettingsState();
}

class _AutofocusSettingsState extends ConsumerState<AutofocusSettingsPage> {
  // General AF controllers
  final _initialOffsetStepsController = TextEditingController();
  final _stepSizeController = TextEditingController();
  final _exposureTimeController = TextEditingController();
  final _numberOfAttemptsController = TextEditingController();
  final _brightestNStarsController = TextEditingController();
  final _outerCropRatioController = TextEditingController();
  final _innerCropRatioController = TextEditingController();
  final _binningController = TextEditingController();
  final _rSquaredThresholdController = TextEditingController();
  final _failureToleranceController = TextEditingController();
  final _focuserSettleTimeController = TextEditingController();
  final _exposuresPerPointController = TextEditingController();
  final _backlashInController = TextEditingController();
  final _backlashOutController = TextEditingController();

  late AppSettingsState _renderedSettings;
  late Object _renderedAuthority;

  @override
  void dispose() {
    _initialOffsetStepsController.dispose();
    _stepSizeController.dispose();
    _exposureTimeController.dispose();
    _numberOfAttemptsController.dispose();
    _brightestNStarsController.dispose();
    _outerCropRatioController.dispose();
    _innerCropRatioController.dispose();
    _binningController.dispose();
    _rSquaredThresholdController.dispose();
    _failureToleranceController.dispose();
    _focuserSettleTimeController.dispose();
    _exposuresPerPointController.dispose();
    _backlashInController.dispose();
    _backlashOutController.dispose();
    super.dispose();
  }

  Widget _afNumberInput({
    Key? key,
    required TextEditingController controller,
    required String suffix,
    required double min,
    required double max,
    required int decimals,
    required FutureOr<void> Function(double) onChanged,
    double? width,
    bool isMobile = false,
  }) {
    final settings = _renderedSettings;
    final authoritativeValue = switch (controller) {
      _ when identical(controller, _initialOffsetStepsController) =>
        settings.afInitialOffsetSteps.toDouble(),
      _ when identical(controller, _stepSizeController) =>
        settings.afStepSize.toDouble(),
      _ when identical(controller, _exposureTimeController) =>
        settings.afExposureTime,
      _ when identical(controller, _numberOfAttemptsController) =>
        settings.afNumberOfAttempts.toDouble(),
      _ when identical(controller, _brightestNStarsController) =>
        settings.afUseBrightestNStars.toDouble(),
      _ when identical(controller, _outerCropRatioController) =>
        settings.afOuterCropRatio,
      _ when identical(controller, _innerCropRatioController) =>
        settings.afInnerCropRatio,
      _ when identical(controller, _binningController) =>
        settings.afBinning.toDouble(),
      _ when identical(controller, _rSquaredThresholdController) =>
        settings.afRSquaredThreshold,
      _ when identical(controller, _failureToleranceController) =>
        settings.afFailureHfrToleranceRatio,
      _ when identical(controller, _focuserSettleTimeController) =>
        settings.afFocuserSettleTimeMs.toDouble(),
      _ when identical(controller, _exposuresPerPointController) =>
        settings.afExposuresPerPoint.toDouble(),
      _ when identical(controller, _backlashInController) =>
        settings.afBacklashIn.toDouble(),
      _ when identical(controller, _backlashOutController) =>
        settings.afBacklashOut.toDouble(),
      _ => throw StateError('Unknown autofocus settings controller'),
    };
    return SettingsNumberInput(
      key: key,
      controller: controller,
      authoritativeValue: authoritativeValue,
      authorityKey: _renderedAuthority,
      suffix: suffix,
      min: min,
      max: max,
      decimals: decimals,
      onChanged: onChanged,
      width: width,
      isMobile: isMobile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final filterWheelState = ref.watch(filterWheelStateProvider);

    return settingsAsync.when(
      loading: () => SettingsLoadingState(
        isMobile: widget.isMobile,
        scrollable: !widget.embedded,
      ),
      error: (error, stack) => SettingsErrorState(
        isMobile: widget.isMobile,
        error: error,
        onRetry: () => ref.invalidate(appSettingsProvider),
      ),
      data: (settings) {
        _renderedSettings = settings;
        _renderedAuthority = ref.watch(backendProvider);
        final notifier = ref.read(appSettingsProvider.notifier);

        return SettingsPage(
          title: 'Autofocus',
          description:
              'Configure autofocus behavior, curve fitting, and per-filter settings',
          isMobile: widget.isMobile,
          hideHeader: widget.isMobile || widget.embedded,
          scrollable: !widget.embedded,
          children: [
            SettingsSection(
              title: 'Autofocus',
              isMobile: widget.isMobile,
              children: [
                if (!widget.isMobile)
                  _buildDesktopTwoColumnLayout(settings, notifier)
                else
                  ..._buildMobileLayout(settings, notifier),
              ],
            ),
            _buildFilterSettingsSection(settings, notifier, filterWheelState),
          ],
        );
      },
    );
  }

  Widget _buildDesktopTwoColumnLayout(
      AppSettingsState settings, AppSettingsNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column
          Expanded(
            child: Column(
              children: [
                _buildAfSettingRow(
                  icon: LucideIcons.filter,
                  title: 'Use filter offsets',
                  subtitle: 'Apply focus offsets when changing filters',
                  trailing: SettingsSwitch(
                    value: settings.useFilterFocusOffsets,
                    onChanged: (value) =>
                        notifier.setUseFilterFocusOffsets(value),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.arrowUpDown,
                  title: 'Initial offset steps',
                  subtitle: 'Steps out from center for V-curve',
                  trailing: _afNumberInput(
                    controller: _initialOffsetStepsController,
                    suffix: '',
                    min: 1,
                    max: 20,
                    decimals: 0,
                    onChanged: (value) =>
                        notifier.setAfInitialOffsetSteps(value.toInt()),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.activity,
                  title: 'Autofocus method',
                  trailing: SettingsDropdown(
                    value: settings.afMethod,
                    items: const ['Star HFR'],
                    onChanged: (value) {
                      return notifier.setAfMethod(value);
                    },
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.trendingUp,
                  title: 'Curve fitting strategy',
                  trailing: SettingsDropdown(
                    value: settings.afCurveFitting,
                    items: AutofocusSettings.curveFittingOptions,
                    onChanged: (value) {
                      return notifier.setAfCurveFitting(value);
                    },
                    width: 150,
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.repeat,
                  title: 'Number of attempts',
                  subtitle: 'Retry count on failure',
                  trailing: _afNumberInput(
                    controller: _numberOfAttemptsController,
                    suffix: '',
                    min: 1,
                    max: 10,
                    decimals: 0,
                    onChanged: (value) =>
                        notifier.setAfNumberOfAttempts(value.toInt()),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.sparkles,
                  title: 'Use brightest n stars',
                  subtitle: '0 = use all detected stars',
                  trailing: _afNumberInput(
                    controller: _brightestNStarsController,
                    suffix: '',
                    min: 0,
                    max: 500,
                    decimals: 0,
                    onChanged: (value) =>
                        notifier.setAfUseBrightestNStars(value.toInt()),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.maximize2,
                  title: 'Outer crop ratio',
                  subtitle: 'Must be greater than the inner crop ratio',
                  trailing: _afNumberInput(
                    controller: _outerCropRatioController,
                    suffix: '',
                    min: 0.01,
                    max: 1.0,
                    decimals: 2,
                    onChanged: (value) => notifier.setAfOuterCropRatio(value),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.grid,
                  title: 'Binning',
                  trailing: _afNumberInput(
                    controller: _binningController,
                    suffix: '',
                    min: 1,
                    max: 4,
                    decimals: 0,
                    onChanged: (value) => notifier.setAfBinning(value.toInt()),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.checkCircle,
                  title: 'R\u00B2 threshold',
                  subtitle: 'Minimum acceptable curve fit quality',
                  trailing: _afNumberInput(
                    controller: _rSquaredThresholdController,
                    suffix: '',
                    min: 0.0,
                    max: 1.0,
                    decimals: 2,
                    onChanged: (value) =>
                        notifier.setAfRSquaredThreshold(value),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.alertTriangle,
                  title: 'HFR tolerance on failure',
                  subtitle:
                      'Keep imaging while HFR stays within this multiple of '
                      'your good HFR. 0 = stop on any failure',
                  trailing: _afNumberInput(
                    controller: _failureToleranceController,
                    suffix: '\u00D7',
                    min: 0.0,
                    max: 10.0,
                    decimals: 2,
                    onChanged: (value) =>
                        notifier.setAfFailureHfrToleranceRatio(value),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.octagon,
                  title: 'If focus is past tolerance',
                  subtitle: 'What an unattended run does when focus is lost',
                  trailing: SettingsDropdown(
                    value: AutofocusSettings.failureActionLabel(
                      settings.afFailureAction,
                    ),
                    items: AutofocusSettings.failureActionLabels.values
                        .toList(),
                    onChanged: (value) => notifier.setAfFailureAction(
                      AutofocusSettings.failureActionFromLabel(value),
                    ),
                    width: 200,
                  ),
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right column
          Expanded(
            child: Column(
              children: [
                _buildAfSettingRow(
                  icon: LucideIcons.moveVertical,
                  title: 'Step size',
                  subtitle: 'Focuser steps between measurement points',
                  trailing: _afNumberInput(
                    controller: _stepSizeController,
                    suffix: '',
                    min: 1,
                    max: 10000,
                    decimals: 0,
                    onChanged: (value) => notifier.setAfStepSize(value.toInt()),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.timer,
                  title: 'Exposure time',
                  subtitle: 'Default AF frame exposure',
                  trailing: _afNumberInput(
                    controller: _exposureTimeController,
                    suffix: 's',
                    min: 0.1,
                    max: 300,
                    decimals: 1,
                    onChanged: (value) => notifier.setAfExposureTime(value),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.pause,
                  title: 'Disable guiding during AF',
                  subtitle: 'Stop autoguider while focusing',
                  trailing: SettingsSwitch(
                    value: settings.afDisableGuidingDuringAf,
                    onChanged: (value) =>
                        notifier.setAfDisableGuidingDuringAf(value),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.clock,
                  title: 'Focuser settle time',
                  subtitle: 'Wait after focuser move',
                  trailing: _afNumberInput(
                    controller: _focuserSettleTimeController,
                    suffix: 'ms',
                    min: 0,
                    max: 10000,
                    decimals: 0,
                    onChanged: (value) =>
                        notifier.setAfFocuserSettleTimeMs(value.toInt()),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.layers,
                  title: 'Exposures per point',
                  subtitle: 'Frames to average per focus position',
                  trailing: _afNumberInput(
                    controller: _exposuresPerPointController,
                    suffix: '',
                    min: 1,
                    max: 20,
                    decimals: 0,
                    onChanged: (value) =>
                        notifier.setAfExposuresPerPoint(value.toInt()),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.minimize2,
                  title: 'Inner crop ratio',
                  subtitle: 'Central exclusion; must be smaller than outer',
                  trailing: _afNumberInput(
                    controller: _innerCropRatioController,
                    suffix: '',
                    min: 0.0,
                    max: 1.0,
                    decimals: 2,
                    onChanged: (value) => notifier.setAfInnerCropRatio(value),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.arrowLeftRight,
                  title: 'Backlash compensation',
                  trailing: SettingsDropdown(
                    value: settings.afBacklashCompMethod,
                    items: const ['None', 'Overshoot', 'Absolute'],
                    onChanged: (value) {
                      return notifier.setAfBacklashCompMethod(value);
                    },
                    width: 150,
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.arrowLeft,
                  title: 'Backlash IN',
                  trailing: _afNumberInput(
                    controller: _backlashInController,
                    suffix: '',
                    min: 0,
                    max: 10000,
                    decimals: 0,
                    onChanged: (value) =>
                        notifier.setAfBacklashIn(value.toInt()),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.arrowRight,
                  title: 'Backlash OUT',
                  trailing: _afNumberInput(
                    controller: _backlashOutController,
                    suffix: '',
                    min: 0,
                    max: 10000,
                    decimals: 0,
                    onChanged: (value) =>
                        notifier.setAfBacklashOut(value.toInt()),
                  ),
                  isLast: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMobileLayout(
      AppSettingsState settings, AppSettingsNotifier notifier) {
    return [
      SettingRow(
        icon: LucideIcons.filter,
        title: 'Use filter offsets',
        subtitle: 'Apply focus offsets when changing filters',
        trailing: SettingsSwitch(
          value: settings.useFilterFocusOffsets,
          onChanged: (value) => notifier.setUseFilterFocusOffsets(value),
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.arrowUpDown,
        title: 'Initial offset steps',
        subtitle: 'Steps out from center for V-curve',
        trailing: _afNumberInput(
          controller: _initialOffsetStepsController,
          suffix: '',
          min: 1,
          max: 20,
          decimals: 0,
          onChanged: (value) => notifier.setAfInitialOffsetSteps(value.toInt()),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.activity,
        title: 'Autofocus method',
        trailing: SettingsDropdown(
          value: settings.afMethod,
          items: const ['Star HFR'],
          onChanged: (value) {
            return notifier.setAfMethod(value);
          },
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.trendingUp,
        title: 'Curve fitting strategy',
        trailing: SettingsDropdown(
          value: settings.afCurveFitting,
          items: AutofocusSettings.curveFittingOptions,
          onChanged: (value) {
            return notifier.setAfCurveFitting(value);
          },
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.moveVertical,
        title: 'Step size',
        subtitle: 'Focuser steps between measurement points',
        trailing: _afNumberInput(
          controller: _stepSizeController,
          suffix: '',
          min: 1,
          max: 10000,
          decimals: 0,
          onChanged: (value) => notifier.setAfStepSize(value.toInt()),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.timer,
        title: 'Exposure time',
        subtitle: 'Default AF frame exposure',
        trailing: _afNumberInput(
          controller: _exposureTimeController,
          suffix: 's',
          min: 0.1,
          max: 300,
          decimals: 1,
          onChanged: (value) => notifier.setAfExposureTime(value),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.pause,
        title: 'Disable guiding during AF',
        subtitle: 'Stop autoguider while focusing',
        trailing: SettingsSwitch(
          value: settings.afDisableGuidingDuringAf,
          onChanged: (value) => notifier.setAfDisableGuidingDuringAf(value),
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.repeat,
        title: 'Number of attempts',
        subtitle: 'Retry count on failure',
        trailing: _afNumberInput(
          controller: _numberOfAttemptsController,
          suffix: '',
          min: 1,
          max: 10,
          decimals: 0,
          onChanged: (value) => notifier.setAfNumberOfAttempts(value.toInt()),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.sparkles,
        title: 'Use brightest n stars',
        subtitle: '0 = use all detected stars',
        trailing: _afNumberInput(
          controller: _brightestNStarsController,
          suffix: '',
          min: 0,
          max: 500,
          decimals: 0,
          onChanged: (value) => notifier.setAfUseBrightestNStars(value.toInt()),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.maximize2,
        title: 'Outer crop ratio',
        subtitle: 'Must be greater than the inner crop ratio',
        trailing: _afNumberInput(
          controller: _outerCropRatioController,
          suffix: '',
          min: 0.01,
          max: 1.0,
          decimals: 2,
          onChanged: (value) => notifier.setAfOuterCropRatio(value),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.minimize2,
        title: 'Inner crop ratio',
        subtitle: 'Central exclusion; must be smaller than outer',
        trailing: _afNumberInput(
          controller: _innerCropRatioController,
          suffix: '',
          min: 0.0,
          max: 1.0,
          decimals: 2,
          onChanged: (value) => notifier.setAfInnerCropRatio(value),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.grid,
        title: 'Binning',
        trailing: _afNumberInput(
          controller: _binningController,
          suffix: '',
          min: 1,
          max: 4,
          decimals: 0,
          onChanged: (value) => notifier.setAfBinning(value.toInt()),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.checkCircle,
        title: 'R\u00B2 threshold',
        subtitle: 'Minimum acceptable curve fit quality',
        trailing: _afNumberInput(
          controller: _rSquaredThresholdController,
          suffix: '',
          min: 0.0,
          max: 1.0,
          decimals: 2,
          onChanged: (value) => notifier.setAfRSquaredThreshold(value),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.alertTriangle,
        title: 'HFR tolerance on failure',
        subtitle:
            'Keep imaging while HFR stays within this multiple of your good '
            'HFR. 0 = stop on any failure',
        trailing: _afNumberInput(
          controller: _failureToleranceController,
          suffix: '\u00D7',
          min: 0.0,
          max: 10.0,
          decimals: 2,
          onChanged: (value) => notifier.setAfFailureHfrToleranceRatio(value),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.octagon,
        title: 'If focus is past tolerance',
        subtitle: 'What an unattended run does when focus is lost',
        trailing: SettingsDropdown(
          value: AutofocusSettings.failureActionLabel(settings.afFailureAction),
          items: AutofocusSettings.failureActionLabels.values.toList(),
          onChanged: (value) => notifier.setAfFailureAction(
            AutofocusSettings.failureActionFromLabel(value),
          ),
          width: 200,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.clock,
        title: 'Focuser settle time',
        subtitle: 'Wait after focuser move',
        trailing: _afNumberInput(
          controller: _focuserSettleTimeController,
          suffix: 'ms',
          min: 0,
          max: 10000,
          decimals: 0,
          onChanged: (value) =>
              notifier.setAfFocuserSettleTimeMs(value.toInt()),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.layers,
        title: 'Exposures per point',
        subtitle: 'Frames to average per focus position',
        trailing: _afNumberInput(
          controller: _exposuresPerPointController,
          suffix: '',
          min: 1,
          max: 20,
          decimals: 0,
          onChanged: (value) => notifier.setAfExposuresPerPoint(value.toInt()),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.arrowLeftRight,
        title: 'Backlash compensation',
        trailing: SettingsDropdown(
          value: settings.afBacklashCompMethod,
          items: const ['None', 'Overshoot', 'Absolute'],
          onChanged: (value) {
            return notifier.setAfBacklashCompMethod(value);
          },
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.arrowLeft,
        title: 'Backlash IN',
        trailing: _afNumberInput(
          controller: _backlashInController,
          suffix: '',
          min: 0,
          max: 10000,
          decimals: 0,
          onChanged: (value) => notifier.setAfBacklashIn(value.toInt()),
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.arrowRight,
        title: 'Backlash OUT',
        trailing: _afNumberInput(
          controller: _backlashOutController,
          suffix: '',
          min: 0,
          max: 10000,
          decimals: 0,
          onChanged: (value) => notifier.setAfBacklashOut(value.toInt()),
          isMobile: true,
        ),
        isLast: true,
        isMobile: true,
      ),
    ];
  }

  /// Helper to build a compact setting row for the two-column desktop layout.
  Widget _buildAfSettingRow({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: NightshadeColors.of(context)
                      .border
                      .withValues(alpha: 0.3),
                ),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: NightshadeColors.of(context).surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusButton),
            ),
            child: Icon(icon,
                size: 14, color: NightshadeColors.of(context).textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: NightshadeTypography.labelSm.copyWith(
                      color: NightshadeColors.of(context).textPrimary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      color: NightshadeColors.of(context).textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }

  Widget _buildFilterSettingsSection(
    AppSettingsState settings,
    AppSettingsNotifier notifier,
    FilterWheelState filterWheelState,
  ) {
    final filterNames = filterWheelState.filterNames;
    final isConnected =
        filterWheelState.connectionState == DeviceConnectionState.connected;

    if (!isConnected || filterNames.isEmpty) {
      return SettingsSection(
        title: 'Autofocus Filter Settings',
        isMobile: widget.isMobile,
        children: [
          SettingRow(
            icon: LucideIcons.info,
            title: 'No filter wheel connected',
            subtitle:
                'Connect a filter wheel to configure per-filter autofocus settings.',
            trailing: const SizedBox.shrink(),
            isLast: true,
            isMobile: widget.isMobile,
          ),
        ],
      );
    }

    // Parse the current per-filter settings JSON
    final filterSettingsMap = AutofocusSettings.parseFilterSettingsJson(
      settings.afFilterSettingsJson,
    );

    return SettingsSection(
      title: 'Autofocus Filter Settings',
      isMobile: widget.isMobile,
      children: [
        if (widget.isMobile)
          ..._buildFilterSettingsMobile(
              filterNames, filterSettingsMap, notifier, settings)
        else
          _buildFilterSettingsTable(
              filterNames, filterSettingsMap, notifier, settings),
      ],
    );
  }

  Widget _buildFilterSettingsTable(
    List<String> filterNames,
    Map<String, FilterAutofocusConfig> filterSettingsMap,
    AppSettingsNotifier notifier,
    AppSettingsState settings,
  ) {
    return Column(
      children: [
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: NightshadeColors.of(context).border),
            ),
          ),
          child: Row(
            children: [
              _tableHeader('Pos', width: 40),
              _tableHeader('Name', flex: 2),
              _tableHeader('Focus Offset', flex: 2),
              _tableHeader('AF Exp Time', flex: 2),
              _tableHeader('AF Filter', flex: 2),
              _tableHeader('Binning', width: 70),
              _tableHeader('Gain', flex: 1),
              _tableHeader('Offset', flex: 1),
            ],
          ),
        ),
        // Table rows
        ...List.generate(filterNames.length, (index) {
          final filterName = filterNames[index];
          final config =
              filterSettingsMap[filterName] ?? const FilterAutofocusConfig();
          final isLast = index == filterNames.length - 1;

          return _FilterSettingsRow(
            position: index + 1,
            filterName: filterName,
            config: config,
            allFilterNames: filterNames,
            isLast: isLast,
            onConfigChanged: (update) =>
                notifier.updateFilterAutofocusConfig(filterName, update),
          );
        }),
        // Autofocus filter selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: NightshadeColors.of(context).border),
            ),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.focus,
                  size: 16, color: NightshadeColors.of(context).textSecondary),
              const SizedBox(width: 10),
              Text(
                'Designated autofocus filter:',
                style: NightshadeTypography.labelSm
                    .copyWith(color: NightshadeColors.of(context).textPrimary),
              ),
              const SizedBox(width: 12),
              SettingsDropdown(
                value: settings.afAutofocusFilterName.isEmpty
                    ? 'Current filter'
                    : settings.afAutofocusFilterName,
                items: ['Current filter', ...filterNames],
                onChanged: (value) {
                  return notifier.setAfAutofocusFilterName(
                    value == 'Current filter' ? '' : value,
                  );
                },
                width: 180,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildFilterSettingsMobile(
    List<String> filterNames,
    Map<String, FilterAutofocusConfig> filterSettingsMap,
    AppSettingsNotifier notifier,
    AppSettingsState settings,
  ) {
    final widgets = <Widget>[];

    for (int index = 0; index < filterNames.length; index++) {
      final filterName = filterNames[index];
      final config =
          filterSettingsMap[filterName] ?? const FilterAutofocusConfig();

      widgets.add(
        _FilterSettingsMobileCard(
          position: index + 1,
          filterName: filterName,
          config: config,
          allFilterNames: filterNames,
          isLast: index == filterNames.length - 1,
          onConfigChanged: (update) =>
              notifier.updateFilterAutofocusConfig(filterName, update),
        ),
      );
    }

    // Autofocus filter selector
    widgets.add(
      SettingRow(
        icon: LucideIcons.focus,
        title: 'Designated autofocus filter',
        subtitle: 'Filter to switch to for AF runs',
        trailing: SettingsDropdown(
          value: settings.afAutofocusFilterName.isEmpty
              ? 'Current filter'
              : settings.afAutofocusFilterName,
          items: ['Current filter', ...filterNames],
          onChanged: (value) {
            return notifier.setAfAutofocusFilterName(
              value == 'Current filter' ? '' : value,
            );
          },
          isMobile: true,
        ),
        isLast: true,
        isMobile: true,
      ),
    );

    return widgets;
  }

  Widget _tableHeader(String text, {double? width, int? flex}) {
    final child = Text(
      text,
      style: NightshadeTypography.labelStrongSm
          .copyWith(color: NightshadeColors.of(context).textSecondary),
    );

    if (width != null) {
      return SizedBox(width: width, child: child);
    }
    return Expanded(flex: flex ?? 1, child: child);
  }
}

/// A single row in the filter settings table (desktop).
