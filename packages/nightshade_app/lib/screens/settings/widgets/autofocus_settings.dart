import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class AutofocusSettingsPage extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const AutofocusSettingsPage(
      {super.key, required this.colors, this.isMobile = false});

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
        colors: widget.colors,
        isMobile: widget.isMobile,
      ),
      error: (error, stack) => SettingsErrorState(
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: widget.isMobile,
          hideHeader: widget.isMobile,
          children: [
            SettingsSection(
              title: 'Autofocus',
              colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
                    colors: widget.colors,
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
          colors: widget.colors,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
        isMobile: true,
      ),
      SettingRow(
        icon: LucideIcons.pause,
        title: 'Disable guiding during AF',
        subtitle: 'Stop autoguider while focusing',
        trailing: SettingsSwitch(
          value: settings.afDisableGuidingDuringAf,
          onChanged: (value) => notifier.setAfDisableGuidingDuringAf(value),
          colors: widget.colors,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        isLast: true,
        colors: widget.colors,
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
                  color: widget.colors.border.withValues(alpha: 0.3),
                ),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: widget.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: widget.colors.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: widget.colors.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.colors.textMuted,
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
        colors: widget.colors,
        isMobile: widget.isMobile,
        children: [
          SettingRow(
            icon: LucideIcons.info,
            title: 'No filter wheel connected',
            subtitle:
                'Connect a filter wheel to configure per-filter autofocus settings.',
            trailing: const SizedBox.shrink(),
            isLast: true,
            colors: widget.colors,
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
      colors: widget.colors,
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
              bottom: BorderSide(color: widget.colors.border),
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
            colors: widget.colors,
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
              top: BorderSide(color: widget.colors.border),
            ),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.focus,
                  size: 16, color: widget.colors.textSecondary),
              const SizedBox(width: 10),
              Text(
                'Designated autofocus filter:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.colors.textPrimary,
                ),
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
                colors: widget.colors,
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
          colors: widget.colors,
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
          colors: widget.colors,
          isMobile: true,
        ),
        isLast: true,
        colors: widget.colors,
        isMobile: true,
      ),
    );

    return widgets;
  }

  Widget _tableHeader(String text, {double? width, int? flex}) {
    final child = Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: widget.colors.textSecondary,
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: child);
    }
    return Expanded(flex: flex ?? 1, child: child);
  }
}

/// A single row in the filter settings table (desktop).
class _FilterSettingsRow extends StatefulWidget {
  final int position;
  final String filterName;
  final FilterAutofocusConfig config;
  final List<String> allFilterNames;
  final NightshadeColors colors;
  final bool isLast;
  final ValueChanged<FilterAutofocusConfig> onConfigChanged;

  const _FilterSettingsRow({
    required this.position,
    required this.filterName,
    required this.config,
    required this.allFilterNames,
    required this.colors,
    required this.isLast,
    required this.onConfigChanged,
  });

  @override
  State<_FilterSettingsRow> createState() => _FilterSettingsRowState();
}

class _FilterSettingsRowState extends State<_FilterSettingsRow> {
  late TextEditingController _focusOffsetController;
  late TextEditingController _afExpTimeController;
  late TextEditingController _gainController;
  late TextEditingController _offsetController;

  @override
  void initState() {
    super.initState();
    _focusOffsetController = TextEditingController(
      text: widget.config.focusOffset.toString(),
    );
    _afExpTimeController = TextEditingController(
      text: widget.config.afExposureTime?.toString() ?? '',
    );
    _gainController = TextEditingController(
      text: widget.config.gain?.toString() ?? '',
    );
    _offsetController = TextEditingController(
      text: widget.config.offset?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(_FilterSettingsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _focusOffsetController.text = widget.config.focusOffset.toString();
      _afExpTimeController.text =
          widget.config.afExposureTime?.toString() ?? '';
      _gainController.text = widget.config.gain?.toString() ?? '';
      _offsetController.text = widget.config.offset?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _focusOffsetController.dispose();
    _afExpTimeController.dispose();
    _gainController.dispose();
    _offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final afFilterName = widget.config.afFilterName ?? 'Default';
    final binningStr = '${widget.config.binning}x${widget.config.binning}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: widget.colors.border.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Row(
        children: [
          // Position
          SizedBox(
            width: 40,
            child: Text(
              '${widget.position}',
              style: TextStyle(
                fontSize: 12,
                color: widget.colors.textSecondary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // Name
          Expanded(
            flex: 2,
            child: Text(
              widget.filterName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: widget.colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Focus offset
          Expanded(
            flex: 2,
            child: _buildCompactNumberInput(
              controller: _focusOffsetController,
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null) {
                  widget.onConfigChanged(
                    widget.config.copyWith(focusOffset: parsed),
                  );
                }
              },
            ),
          ),
          // AF Exposure Time
          Expanded(
            flex: 2,
            child: _buildCompactNumberInput(
              controller: _afExpTimeController,
              hint: 'default',
              onChanged: (value) {
                if (value.isEmpty) {
                  widget.onConfigChanged(
                    widget.config.copyWith(clearAfExposureTime: true),
                  );
                } else {
                  final parsed = double.tryParse(value);
                  if (parsed != null) {
                    widget.onConfigChanged(
                      widget.config.copyWith(afExposureTime: parsed),
                    );
                  }
                }
              },
            ),
          ),
          // AF Filter
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SettingsDropdown(
                value: afFilterName,
                items: ['Default', ...widget.allFilterNames],
                onChanged: (value) {
                  if (value != null) {
                    if (value == 'Default') {
                      widget.onConfigChanged(
                        widget.config.copyWith(clearAfFilterName: true),
                      );
                    } else {
                      widget.onConfigChanged(
                        widget.config.copyWith(afFilterName: value),
                      );
                    }
                  }
                },
                colors: widget.colors,
              ),
            ),
          ),
          // Binning
          SizedBox(
            width: 70,
            child: SettingsDropdown(
              value: binningStr,
              items: const ['1x1', '2x2', '3x3', '4x4'],
              onChanged: (value) {
                if (value != null) {
                  final binVal = int.tryParse(value.split('x').first) ?? 1;
                  widget.onConfigChanged(
                    widget.config.copyWith(binning: binVal),
                  );
                }
              },
              colors: widget.colors,
            ),
          ),
          // Gain
          Expanded(
            flex: 1,
            child: _buildCompactNumberInput(
              controller: _gainController,
              hint: 'def',
              onChanged: (value) {
                if (value.isEmpty) {
                  widget.onConfigChanged(
                    widget.config.copyWith(clearGain: true),
                  );
                } else {
                  final parsed = int.tryParse(value);
                  if (parsed != null) {
                    widget.onConfigChanged(
                      widget.config.copyWith(gain: parsed),
                    );
                  }
                }
              },
            ),
          ),
          // Offset
          Expanded(
            flex: 1,
            child: _buildCompactNumberInput(
              controller: _offsetController,
              hint: 'def',
              onChanged: (value) {
                if (value.isEmpty) {
                  widget.onConfigChanged(
                    widget.config.copyWith(clearOffset: true),
                  );
                } else {
                  final parsed = int.tryParse(value);
                  if (parsed != null) {
                    widget.onConfigChanged(
                      widget.config.copyWith(offset: parsed),
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactNumberInput({
    required TextEditingController controller,
    String? hint,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Container(
        height: 28,
        decoration: BoxDecoration(
          color: widget.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: widget.colors.border),
        ),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
          ],
          style: TextStyle(
            fontSize: 11,
            color: widget.colors.textPrimary,
          ),
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 10,
              color: widget.colors.textMuted,
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Mobile card for per-filter AF settings (used instead of table on small screens).
class _FilterSettingsMobileCard extends StatefulWidget {
  final int position;
  final String filterName;
  final FilterAutofocusConfig config;
  final List<String> allFilterNames;
  final NightshadeColors colors;
  final bool isLast;
  final ValueChanged<FilterAutofocusConfig> onConfigChanged;

  const _FilterSettingsMobileCard({
    required this.position,
    required this.filterName,
    required this.config,
    required this.allFilterNames,
    required this.colors,
    required this.isLast,
    required this.onConfigChanged,
  });

  @override
  State<_FilterSettingsMobileCard> createState() =>
      _FilterSettingsMobileCardState();
}

class _FilterSettingsMobileCardState extends State<_FilterSettingsMobileCard> {
  late TextEditingController _focusOffsetController;
  late TextEditingController _afExpTimeController;
  late TextEditingController _gainController;
  late TextEditingController _offsetController;

  @override
  void initState() {
    super.initState();
    _focusOffsetController = TextEditingController(
      text: widget.config.focusOffset.toString(),
    );
    _afExpTimeController = TextEditingController(
      text: widget.config.afExposureTime?.toString() ?? '',
    );
    _gainController = TextEditingController(
      text: widget.config.gain?.toString() ?? '',
    );
    _offsetController = TextEditingController(
      text: widget.config.offset?.toString() ?? '',
    );
  }

  @override
  void didUpdateWidget(_FilterSettingsMobileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _focusOffsetController.text = widget.config.focusOffset.toString();
      _afExpTimeController.text =
          widget.config.afExposureTime?.toString() ?? '';
      _gainController.text = widget.config.gain?.toString() ?? '';
      _offsetController.text = widget.config.offset?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _focusOffsetController.dispose();
    _afExpTimeController.dispose();
    _gainController.dispose();
    _offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final afFilterName = widget.config.afFilterName ?? 'Default';
    final binningStr = '${widget.config.binning}x${widget.config.binning}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: widget.isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: widget.colors.border.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: position + name
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: widget.colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '${widget.position}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: widget.colors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.filterName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Settings grid (2 columns)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _buildMobileField(
                'Focus Offset',
                _buildCompactNumberInput(
                  controller: _focusOffsetController,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      widget.onConfigChanged(
                        widget.config.copyWith(focusOffset: parsed),
                      );
                    }
                  },
                ),
              ),
              _buildMobileField(
                'AF Exp Time',
                _buildCompactNumberInput(
                  controller: _afExpTimeController,
                  hint: 'default',
                  onChanged: (value) {
                    if (value.isEmpty) {
                      widget.onConfigChanged(
                        widget.config.copyWith(clearAfExposureTime: true),
                      );
                    } else {
                      final parsed = double.tryParse(value);
                      if (parsed != null) {
                        widget.onConfigChanged(
                          widget.config.copyWith(afExposureTime: parsed),
                        );
                      }
                    }
                  },
                ),
              ),
              _buildMobileField(
                'AF Filter',
                SettingsDropdown(
                  value: afFilterName,
                  items: ['Default', ...widget.allFilterNames],
                  onChanged: (value) {
                    if (value != null) {
                      if (value == 'Default') {
                        widget.onConfigChanged(
                          widget.config.copyWith(clearAfFilterName: true),
                        );
                      } else {
                        widget.onConfigChanged(
                          widget.config.copyWith(afFilterName: value),
                        );
                      }
                    }
                  },
                  colors: widget.colors,
                  isMobile: true,
                  flexible: true,
                ),
              ),
              _buildMobileField(
                'Binning',
                SettingsDropdown(
                  value: binningStr,
                  items: const ['1x1', '2x2', '3x3', '4x4'],
                  onChanged: (value) {
                    if (value != null) {
                      final binVal = int.tryParse(value.split('x').first) ?? 1;
                      widget.onConfigChanged(
                        widget.config.copyWith(binning: binVal),
                      );
                    }
                  },
                  colors: widget.colors,
                  isMobile: true,
                  flexible: true,
                ),
              ),
              _buildMobileField(
                'Gain',
                _buildCompactNumberInput(
                  controller: _gainController,
                  hint: 'default',
                  onChanged: (value) {
                    if (value.isEmpty) {
                      widget.onConfigChanged(
                        widget.config.copyWith(clearGain: true),
                      );
                    } else {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        widget.onConfigChanged(
                          widget.config.copyWith(gain: parsed),
                        );
                      }
                    }
                  },
                ),
              ),
              _buildMobileField(
                'Offset',
                _buildCompactNumberInput(
                  controller: _offsetController,
                  hint: 'default',
                  onChanged: (value) {
                    if (value.isEmpty) {
                      widget.onConfigChanged(
                        widget.config.copyWith(clearOffset: true),
                      );
                    } else {
                      final parsed = int.tryParse(value);
                      if (parsed != null) {
                        widget.onConfigChanged(
                          widget.config.copyWith(offset: parsed),
                        );
                      }
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMobileField(String label, Widget input) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: widget.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          input,
        ],
      ),
    );
  }

  Widget _buildCompactNumberInput({
    required TextEditingController controller,
    String? hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: widget.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: widget.colors.border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        style: TextStyle(
          fontSize: 12,
          color: widget.colors.textPrimary,
        ),
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 10,
            color: widget.colors.textMuted,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}
