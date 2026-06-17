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
  final _focuserSettleTimeController = TextEditingController();
  final _exposuresPerPointController = TextEditingController();
  final _backlashInController = TextEditingController();
  final _backlashOutController = TextEditingController();

  bool _initialized = false;

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
    _focuserSettleTimeController.dispose();
    _exposuresPerPointController.dispose();
    _backlashInController.dispose();
    _backlashOutController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _initialOffsetStepsController.text =
          settings.afInitialOffsetSteps.toString();
      _stepSizeController.text = settings.afStepSize.toString();
      _exposureTimeController.text = settings.afExposureTime.toString();
      _numberOfAttemptsController.text = settings.afNumberOfAttempts.toString();
      _brightestNStarsController.text =
          settings.afUseBrightestNStars.toString();
      _outerCropRatioController.text = settings.afOuterCropRatio.toString();
      _innerCropRatioController.text = settings.afInnerCropRatio.toString();
      _binningController.text = settings.afBinning.toString();
      _rSquaredThresholdController.text =
          settings.afRSquaredThreshold.toString();
      _focuserSettleTimeController.text =
          settings.afFocuserSettleTimeMs.toString();
      _exposuresPerPointController.text =
          settings.afExposuresPerPoint.toString();
      _backlashInController.text = settings.afBacklashIn.toString();
      _backlashOutController.text = settings.afBacklashOut.toString();
      _initialized = true;
    }
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
        _initControllers(settings);
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
                  trailing: SettingsNumberInput(
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
                      if (value != null) notifier.setAfMethod(value);
                    },
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.trendingUp,
                  title: 'Curve fitting strategy',
                  trailing: SettingsDropdown(
                    value: settings.afCurveFitting,
                    items: const ['Hyperbolic', 'Parabolic', 'Trend Lines'],
                    onChanged: (value) {
                      if (value != null) notifier.setAfCurveFitting(value);
                    },
                    width: 150,
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.repeat,
                  title: 'Number of attempts',
                  subtitle: 'Retry count on failure',
                  trailing: SettingsNumberInput(
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
                  trailing: SettingsNumberInput(
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
                  trailing: SettingsNumberInput(
                    controller: _outerCropRatioController,
                    suffix: '',
                    min: 0.0,
                    max: 1.0,
                    decimals: 2,
                    onChanged: (value) => notifier.setAfOuterCropRatio(value),
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.grid,
                  title: 'Binning',
                  trailing: SettingsNumberInput(
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
                  trailing: SettingsNumberInput(
                    controller: _rSquaredThresholdController,
                    suffix: '',
                    min: 0.0,
                    max: 1.0,
                    decimals: 2,
                    onChanged: (value) =>
                        notifier.setAfRSquaredThreshold(value),
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
                  trailing: SettingsNumberInput(
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
                  trailing: SettingsNumberInput(
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
                  trailing: SettingsNumberInput(
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
                  trailing: SettingsNumberInput(
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
                  trailing: SettingsNumberInput(
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
                      if (value != null) {
                        notifier.setAfBacklashCompMethod(value);
                      }
                    },
                    width: 150,
                  ),
                ),
                _buildAfSettingRow(
                  icon: LucideIcons.arrowLeft,
                  title: 'Backlash IN',
                  trailing: SettingsNumberInput(
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
                  trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
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
            if (value != null) notifier.setAfMethod(value);
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
          items: const ['Hyperbolic', 'Parabolic', 'Trend Lines'],
          onChanged: (value) {
            if (value != null) notifier.setAfCurveFitting(value);
          },
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.moveVertical,
        title: 'Step size',
        subtitle: 'Focuser steps between measurement points',
        trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
          controller: _outerCropRatioController,
          suffix: '',
          min: 0.0,
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
        trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
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
        icon: LucideIcons.clock,
        title: 'Focuser settle time',
        subtitle: 'Wait after focuser move',
        trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
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
            if (value != null) notifier.setAfBacklashCompMethod(value);
          },
          isMobile: true,
        ),
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.arrowLeft,
        title: 'Backlash IN',
        trailing: SettingsNumberInput(
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
        trailing: SettingsNumberInput(
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
            onConfigChanged: (newConfig) {
              notifier.setFilterAutofocusConfig(filterName, newConfig);
            },
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
                  if (value != null) {
                    notifier.setAfAutofocusFilterName(
                      value == 'Current filter' ? '' : value,
                    );
                  }
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
          onConfigChanged: (newConfig) {
            notifier.setFilterAutofocusConfig(filterName, newConfig);
          },
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
            if (value != null) {
              notifier.setAfAutofocusFilterName(
                value == 'Current filter' ? '' : value,
              );
            }
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
