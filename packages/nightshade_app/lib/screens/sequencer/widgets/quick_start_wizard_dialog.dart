import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../utils/snackbar_helper.dart';
import '../sequencer_screen.dart';

part 'quick_start_wizard_dialog/_wizard_shell.dart';
part 'quick_start_wizard_dialog/_target_step.dart';
part 'quick_start_wizard_dialog/_filter_step.dart';
part 'quick_start_wizard_dialog/_automation_step.dart';
part 'quick_start_wizard_dialog/_safety_step.dart';
part 'quick_start_wizard_dialog/_review_step.dart';

// =============================================================================
// WIZARD STATE
// =============================================================================

/// Fallback baselines used only when no matching setting / Smart-Night
/// recommendation is available. Named constants instead of bare magic
/// numbers so the wizard's intent is auditable and so a "fresh install"
/// fallback never silently masks a missing settings field.
///
/// Why these particular numbers:
///   * 120 s broadband is a standard LRGB sub for a tracked rig.
///   * 300 s narrowband is the historical default for Ha/OIII/SII at
///     f/5–f/7 in Bortle 6–8 — the regime most beginners point at.
///   * -10 C is the fallback cooler setpoint used only when the active
///     equipment profile doesn't carry a `defaultCoolingTemp`.
const double _kWizardBroadbandFallbackSecs = 120.0;
const double _kWizardNarrowbandFallbackSecs = 300.0;
const double _kWizardCoolingTempFallbackC = -10.0;

/// Fallback values used only when no matching settings field is wired in
/// or the user is on a fresh install. Kept here so a quick scan of the
/// wizard's constants explains every magic number the dialog can ship
/// with.
const int _kWizardAutofocusEveryFramesFallback = 30;
const double _kWizardDitherPixelsFallback = 5.0;
const int _kWizardExposureCountFallback = 10;
const double _kWizardDitherSettleSecondsFallback = 30.0;
const double _kWizardGuideSettlePixelsFallback = 1.5;
const double _kWizardGuideSettleSecondsFallback = 10.0;
const double _kWizardGuideSettleTimeoutFallback = 60.0;

/// Per-filter exposure configuration in the wizard
class _FilterExposureConfig {
  String filterName;
  int filterIndex;
  bool enabled;
  double exposureSecs;
  bool exposureEdited = false;
  int count;
  BinningMode binning = BinningMode.one;

  _FilterExposureConfig({
    required this.filterName,
    required this.filterIndex,
    this.enabled = true,
    this.exposureSecs = _kWizardBroadbandFallbackSecs,
    this.count = _kWizardExposureCountFallback,
  });

  double get totalSecs => exposureSecs * count;
}

/// Preset for common filter+exposure combinations
enum _ExposurePreset {
  lrgbBroadband,
  narrowbandSho,
  narrowbandHaOiii,
  oscNoFilter,
  custom,
}

extension _ExposurePresetLabel on _ExposurePreset {
  String get label {
    switch (this) {
      case _ExposurePreset.lrgbBroadband:
        return 'LRGB Broadband';
      case _ExposurePreset.narrowbandSho:
        return 'SHO Narrowband';
      case _ExposurePreset.narrowbandHaOiii:
        return 'Ha-OIII Bicolor';
      case _ExposurePreset.oscNoFilter:
        return 'OSC (No Filters)';
      case _ExposurePreset.custom:
        return 'Custom';
    }
  }

  String get description {
    switch (this) {
      case _ExposurePreset.lrgbBroadband:
        return 'Smart LRGB filter plan';
      case _ExposurePreset.narrowbandSho:
        return 'Smart SII/Ha/OIII plan';
      case _ExposurePreset.narrowbandHaOiii:
        return 'Smart Ha/OIII plan';
      case _ExposurePreset.oscNoFilter:
        return 'Smart single-filter plan';
      case _ExposurePreset.custom:
        return 'Configure manually';
    }
  }
}

// =============================================================================
// WIZARD DIALOG
// =============================================================================

class QuickStartWizardDialog extends ConsumerStatefulWidget {
  const QuickStartWizardDialog({super.key});

  @override
  ConsumerState<QuickStartWizardDialog> createState() =>
      _QuickStartWizardDialogState();
}

class _QuickStartWizardDialogState
    extends ConsumerState<QuickStartWizardDialog> {
  int _currentStep = 0;
  static const int _totalSteps = 5;

  // Step 1: Target
  final _targetNameController = TextEditingController();
  final _raController = TextEditingController();
  final _decController = TextEditingController();
  List<DbTarget> _searchResults = [];
  Timer? _searchDebounce;
  bool _isSearching = false;
  DbTarget? _selectedTarget;

  // Step 2: Filters & Exposures
  List<_FilterExposureConfig> _filterConfigs = [];
  _ExposurePreset _selectedPreset = _ExposurePreset.custom;
  SmartNightExposureContext? _exposureContext;
  LoopConditionType _loopType = LoopConditionType.count;
  int _loopCount = _kWizardExposureCountFallback;

  // Persistent text controllers for the numeric fields. Recreating these
  // inline in build() (the original behaviour) dropped the cursor and could
  // clobber an in-progress edit; lifting them into State keeps the field
  // alive across rebuilds. The source values only push back into a
  // controller when they change from *outside* the field (preset apply,
  // async smart-context load) and only when the text actually differs, so a
  // user mid-edit is never interrupted.
  final _loopCountController = TextEditingController();
  final _autofocusFramesController = TextEditingController();
  final _ditherPixelsController = TextEditingController();
  final _coolingTempController = TextEditingController();

  /// Per-filter-row controllers, keyed by filterIndex. Created in
  /// [_initFilterConfigs] and synced from outside in [_syncFilterControllers].
  final Map<int, ({TextEditingController exp, TextEditingController count})>
      _filterControllers = {};

  // Step 3: Automation
  bool _enableAutofocus = true;
  int _autofocusEveryFrames = _kWizardAutofocusEveryFramesFallback;
  bool _enableDithering = true;
  double _ditherPixels = _kWizardDitherPixelsFallback;
  bool _enableMeridianFlip = true;
  bool _enableAutoGuide = true;

  // Step 4: Safety
  bool _parkOnError = true;
  bool _weatherAbort = false;
  bool _dawnShutdown = true;
  bool _coolCamera = true;
  double _coolingTemp = _kWizardCoolingTempFallbackC;

  /// Tracks whether the wizard pre-populated any defaults from the user's
  /// Sequencer Settings / equipment profile. Drives the small
  /// "Using your saved defaults" hint surfaced near the relevant inputs so
  /// the user knows where numbers came from rather than being surprised.
  bool _populatedFromSavedDefaults = false;

  /// Opt-in: when true, [_createSequence] writes the user's wizard choices
  /// back into their persisted Sequencer Settings / app settings / equipment
  /// profile so the next launch pre-fills with them. Toggled on the Review
  /// step.
  bool _saveAsDefaults = false;

  @override
  void initState() {
    super.initState();
    _applyUserDefaults();
    _initFilterConfigs();
    _seedScalarControllers();
    _loadExposureContext();
  }

  /// Seed the State-level scalar controllers from the current source values.
  /// Called once in initState (after defaults are applied) and again whenever
  /// a source value changes from outside the field.
  void _seedScalarControllers() {
    _syncController(_loopCountController, _loopCount.toString());
    _syncController(
        _autofocusFramesController, _autofocusEveryFrames.toString());
    _syncController(_ditherPixelsController, _ditherPixels.round().toString());
    _syncController(_coolingTempController, _coolingTemp.round().toString());
  }

  /// Push [value] into [controller] only when it differs from what the field
  /// already shows. This guards against clobbering an in-progress edit while
  /// still letting external sources (presets, async smart-context) update the
  /// displayed text.
  void _syncController(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.text = value;
    }
  }

  /// Sync the per-filter exposure/count controllers from [_filterConfigs].
  /// Creates missing controllers and updates text only when it differs.
  void _syncFilterControllers() {
    for (final config in _filterConfigs) {
      final pair = _filterControllers.putIfAbsent(
        config.filterIndex,
        () => (
          exp: TextEditingController(),
          count: TextEditingController(),
        ),
      );
      _syncController(pair.exp, config.exposureSecs.round().toString());
      _syncController(pair.count, config.count.toString());
    }
  }

  /// Pulls the user's persisted Sequencer Settings / equipment profile /
  /// app settings once at wizard open and overwrites the in-class fallback
  /// constants. Read-only — the wizard is a one-shot dialog, so we don't
  /// need a stream subscription; reading once via `ref.read` keeps the
  /// state simple and consistent across the five steps.
  void _applyUserDefaults() {
    final sequencerDefaults = ref.read(sequencerDefaultsProvider);
    final appSettings = ref.read(appSettingsProvider).valueOrNull;
    final activeProfile = ref.read(activeEquipmentProfileProvider);

    bool populated = false;

    // Sequencer-Defaults-sourced values. These are always present (the
    // provider seeds defaults synchronously in its constructor) so we use
    // them unconditionally and only flip the hint if anything diverges
    // from the in-class fallbacks.
    if (sequencerDefaults.autofocusIntervalFrames > 0) {
      _autofocusEveryFrames = sequencerDefaults.autofocusIntervalFrames;
      if (sequencerDefaults.autofocusIntervalFrames !=
          _kWizardAutofocusEveryFramesFallback) {
        populated = true;
      }
    }
    if (sequencerDefaults.ditherPixels > 0) {
      _ditherPixels = sequencerDefaults.ditherPixels;
      if (sequencerDefaults.ditherPixels != _kWizardDitherPixelsFallback) {
        populated = true;
      }
    }
    if (sequencerDefaults.exposureCount > 0) {
      _loopCount = sequencerDefaults.exposureCount;
      if (sequencerDefaults.exposureCount != _kWizardExposureCountFallback) {
        populated = true;
      }
    }

    // App-Settings-sourced toggles. Skip if settings haven't loaded yet —
    // the dialog still opens and the fallback in-class defaults apply.
    if (appSettings != null) {
      _enableMeridianFlip = appSettings.enableMeridianFlip;
      _weatherAbort = appSettings.parkOnUnsafeWeather;
      _dawnShutdown = appSettings.parkBeforeDawn;
      populated = true;
    }

    // Cooling temp lives on the active equipment profile, not in app
    // settings. `defaultCoolingTemp` is nullable; the user may simply not
    // have set one yet, in which case the fallback constant kicks in.
    // The wizard's "Cool camera" toggle itself stays user-facing — the
    // profile's `coolOnConnect` is about device-connect behaviour, not
    // sequence-start behaviour, so we don't tie them together here.
    if (activeProfile != null) {
      final profileCoolingTemp = activeProfile.defaultCoolingTemp;
      if (profileCoolingTemp != null && profileCoolingTemp.isFinite) {
        _coolingTemp = profileCoolingTemp;
        populated = true;
      }
    }

    _populatedFromSavedDefaults = populated;
  }

  Future<void> _loadExposureContext() async {
    final SmartNightExposureContext? context;
    try {
      context = await ref.read(smartNightExposureContextProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted || context == null) return;
    setState(() {
      _exposureContext = context;
      for (final config in _filterConfigs) {
        if (!config.exposureEdited) {
          config.exposureSecs = _defaultExposureForFilter(config.filterName);
        }
      }
      // Async smart-context arrival is an external source; push the
      // recomputed exposures into the row controllers (guarded so any
      // user-edited row, which has exposureEdited=true, keeps its text).
      _syncFilterControllers();
    });
  }

  void _initFilterConfigs() {
    // Get filter names from the active equipment profile
    final filters = ref.read(profileFiltersProvider);
    // Per-filter sub-count default — honours the user's Sequencer Settings
    // exposure-count preference (already pulled into `_loopCount` by
    // `_applyUserDefaults`) so the wizard doesn't ship one number for the
    // loop and a different one for each filter row.
    final defaultCount =
        _loopCount > 0 ? _loopCount : _kWizardExposureCountFallback;

    if (filters.isEmpty) {
      // No filter wheel or no filters configured - default to a single "Light" entry
      _filterConfigs = [
        _FilterExposureConfig(
          filterName: 'Light',
          filterIndex: 0,
          enabled: true,
          exposureSecs: _defaultExposureForFilter('Light'),
          count: defaultCount,
        ),
      ];
    } else {
      _filterConfigs = filters.asMap().entries.map((entry) {
        return _FilterExposureConfig(
          filterName: entry.value,
          filterIndex: entry.key,
          enabled: _isCommonFilter(entry.value),
          exposureSecs: _defaultExposureForFilter(entry.value),
          count: defaultCount,
        );
      }).toList();
    }
    _syncFilterControllers();
  }

  bool _isCommonFilter(String name) {
    final lower = name.toLowerCase();
    return lower == 'l' ||
        lower == 'r' ||
        lower == 'g' ||
        lower == 'b' ||
        lower == 'ha' ||
        lower == 'h-alpha' ||
        lower == 'oiii' ||
        lower == 'sii';
  }

  double _defaultExposureForFilter(String name) {
    final smartExposure = _exposureContext?.recommendForFilter(name).seconds;
    if (smartExposure != null && smartExposure.isFinite && smartExposure > 0) {
      return smartExposure;
    }

    final lower = name.toLowerCase();
    if (lower == 'ha' ||
        lower == 'h-alpha' ||
        lower == 'oiii' ||
        lower == 'sii') {
      return _kWizardNarrowbandFallbackSecs; // 5 minutes for narrowband
    }
    return _kWizardBroadbandFallbackSecs; // 2 minutes for broadband
  }

  @override
  void dispose() {
    _targetNameController.dispose();
    _raController.dispose();
    _decController.dispose();
    _loopCountController.dispose();
    _autofocusFramesController.dispose();
    _ditherPixelsController.dispose();
    _coolingTempController.dispose();
    for (final pair in _filterControllers.values) {
      pair.exp.dispose();
      pair.count.dispose();
    }
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Target search
  // ---------------------------------------------------------------------------

  void _onTargetSearch(String query) {
    _searchDebounce?.cancel();
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final dao = ref.read(targetsDaoProvider);
        final results = await dao.searchTargets(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _searchResults = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  void _selectTarget(DbTarget target) {
    setState(() {
      _selectedTarget = target;
      _targetNameController.text = target.name;
      _raController.text = _formatRa(target.ra);
      _decController.text = _formatDec(target.dec);
      _searchResults = [];
    });
  }

  String _formatRa(double raHours) {
    final h = raHours.floor();
    final m = ((raHours - h) * 60).floor();
    final s = ((raHours - h - m / 60) * 3600).toStringAsFixed(1);
    return '${h}h ${m}m ${s}s';
  }

  String _formatDec(double decDeg) {
    final sign = decDeg >= 0 ? '+' : '-';
    final abs = decDeg.abs();
    final d = abs.floor();
    final m = ((abs - d) * 60).floor();
    final s = ((abs - d - m / 60) * 3600).toStringAsFixed(0);
    return "$sign${d}d $m' $s\"";
  }

  double? _parseRa(String text) {
    // Accept formats: "12.5", "12h 30m 0s", "12:30:00"
    text = text.trim();
    if (text.isEmpty) return null;

    // Try simple decimal
    final decimal = double.tryParse(text);
    if (decimal != null) return decimal;

    // Try HMS format: "12h 30m 0s" or "12:30:00"
    final hmsRegex =
        RegExp(r'(\d+)\s*[hH:]\s*(\d+)\s*[mM:]\s*([\d.]+)\s*[sS]?');
    final match = hmsRegex.firstMatch(text);
    if (match != null) {
      final h = int.parse(match.group(1)!);
      final m = int.parse(match.group(2)!);
      final s = double.parse(match.group(3)!);
      return h + m / 60.0 + s / 3600.0;
    }
    return null;
  }

  double? _parseDec(String text) {
    // Accept formats: "45.5", "+45d 30' 0\"", "+45:30:00"
    text = text.trim();
    if (text.isEmpty) return null;

    // Try simple decimal
    final decimal = double.tryParse(text);
    if (decimal != null) return decimal;

    // Try DMS format: "+45d 30' 0\"" or "+45:30:00"
    final dmsRegex = RegExp(
        r"""([+-]?)(\d+)\s*[dD:]\s*(\d+)\s*['mM:]\s*([\d.]+)\s*[\"sS]?""");
    final dmsMatch = dmsRegex.firstMatch(text);
    if (dmsMatch != null) {
      final sign = dmsMatch.group(1) == '-' ? -1.0 : 1.0;
      final d = int.parse(dmsMatch.group(2)!);
      final m = int.parse(dmsMatch.group(3)!);
      final s = double.parse(dmsMatch.group(4)!);
      return sign * (d + m / 60.0 + s / 3600.0);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Preset application
  // ---------------------------------------------------------------------------

  void _applyPreset(_ExposurePreset preset) {
    // Preset sub-counts scale off the user's exposure-count preference
    // (`_loopCount`, seeded from Sequencer Settings) rather than hardcoded
    // literals, so a user who keeps 20-sub sessions gets proportionally more
    // subs out of every preset. Narrowband presets bias higher (longer subs
    // need fewer frames per signal, but users typically want extra to fight
    // read noise on faint emission); the OSC preset banks everything into one
    // filter so it gets a heavier weight. Multipliers, not magic numbers.
    final base = _loopCount > 0 ? _loopCount : _kWizardExposureCountFallback;
    int scaled(double multiplier) => (base * multiplier).round().clamp(1, 9999);
    final broadbandCount = scaled(1.0);
    final shoCount = scaled(1.0);
    final haOiiiCount = scaled(1.5);
    final oscCount = scaled(2.0);

    setState(() {
      _selectedPreset = preset;

      for (final config in _filterConfigs) {
        final lower = config.filterName.toLowerCase();

        switch (preset) {
          case _ExposurePreset.lrgbBroadband:
            config.enabled =
                lower == 'l' || lower == 'r' || lower == 'g' || lower == 'b';
            config.exposureSecs = _defaultExposureForFilter(config.filterName);
            config.exposureEdited = false;
            config.count = broadbandCount;
            config.binning = BinningMode.one;

          case _ExposurePreset.narrowbandSho:
            config.enabled = lower == 'sii' ||
                lower == 'ha' ||
                lower == 'h-alpha' ||
                lower == 'oiii';
            config.exposureSecs = _defaultExposureForFilter(config.filterName);
            config.exposureEdited = false;
            config.count = shoCount;
            config.binning = BinningMode.one;

          case _ExposurePreset.narrowbandHaOiii:
            config.enabled =
                lower == 'ha' || lower == 'h-alpha' || lower == 'oiii';
            config.exposureSecs = _defaultExposureForFilter(config.filterName);
            config.exposureEdited = false;
            config.count = haOiiiCount;
            config.binning = BinningMode.one;

          case _ExposurePreset.oscNoFilter:
            config.enabled = config.filterIndex == 0;
            config.exposureSecs = _defaultExposureForFilter(config.filterName);
            config.exposureEdited = false;
            config.count = oscCount;
            config.binning = BinningMode.one;

          case _ExposurePreset.custom:
            // Don't change anything
            break;
        }
      }
      // Preset application is an external source — push the new
      // exposures/counts into the row controllers.
      _syncFilterControllers();
    });
  }

  // ---------------------------------------------------------------------------
  // Sequence generation
  // ---------------------------------------------------------------------------

  void _createSequence() => _finishWizard(asTemplate: false);

  /// Save the wizard's sequence as a reusable template instead of loading it
  /// into the editor. Persists via the sequence repository's template path.
  void _saveAsTemplate() => _finishWizard(asTemplate: true);

  void _finishWizard({required bool asTemplate}) {
    // Validate target
    final targetName = _targetNameController.text.trim();
    if (targetName.isEmpty) {
      context.showErrorSnackBar('Please enter a target name');
      return;
    }

    final ra = _selectedTarget?.ra ?? _parseRa(_raController.text);
    final dec = _selectedTarget?.dec ?? _parseDec(_decController.text);

    if (ra == null || dec == null) {
      context.showErrorSnackBar(
          'Please enter valid coordinates (or search for a target)');
      return;
    }

    final enabledFilters = _filterConfigs.where((f) => f.enabled).toList();
    if (enabledFilters.isEmpty) {
      context.showErrorSnackBar('Please enable at least one filter');
      return;
    }

    // Build the sequence tree
    final nodes = <String, SequenceNode>{};
    final rootId = const Uuid().v4();
    final rootChildIds = <String>[];
    var orderIndex = 0;

    // -- Cool camera
    if (_coolCamera) {
      final coolId = const Uuid().v4();
      nodes[coolId] = CoolCameraNode(
        id: coolId,
        targetTemp: _coolingTemp,
        parentId: rootId,
        orderIndex: orderIndex++,
      );
      rootChildIds.add(coolId);
    }

    // -- Slew to target
    final slewId = const Uuid().v4();
    nodes[slewId] = SlewNode(
      id: slewId,
      name: 'Slew to Target',
      parentId: rootId,
      orderIndex: orderIndex++,
    );
    rootChildIds.add(slewId);

    // -- Plate solve & center
    final centerId = const Uuid().v4();
    nodes[centerId] = CenterNode(
      id: centerId,
      name: 'Plate Solve & Center',
      parentId: rootId,
      orderIndex: orderIndex++,
    );
    rootChildIds.add(centerId);

    // -- Initial autofocus
    if (_enableAutofocus) {
      final afId = const Uuid().v4();
      nodes[afId] = AutofocusNode(
        id: afId,
        method: AutofocusMethod.vCurve,
        parentId: rootId,
        orderIndex: orderIndex++,
      );
      rootChildIds.add(afId);
    }

    // -- Start guiding
    if (_enableAutoGuide) {
      final guideId = const Uuid().v4();
      // Settle parameters honour the user's Sequencer Settings dither/
      // settle preferences (settlePixels + dither-settle-pixels share a
      // semantic). settleTime / settleTimeout don't yet have dedicated
      // start-guiding settings, so we use named fallback constants.
      final sequencerDefaults = ref.read(sequencerDefaultsProvider);
      nodes[guideId] = StartGuidingNode(
        id: guideId,
        name: 'Start Guiding',
        settlePixels: sequencerDefaults.ditherSettlePixels > 0
            ? sequencerDefaults.ditherSettlePixels
            : _kWizardGuideSettlePixelsFallback,
        settleTime: _kWizardGuideSettleSecondsFallback,
        settleTimeout: _kWizardGuideSettleTimeoutFallback,
        autoSelectStar: true,
        parentId: rootId,
        orderIndex: orderIndex++,
      );
      rootChildIds.add(guideId);
    }

    // -- Main capture loop
    final loopId = const Uuid().v4();
    final loopChildIds = <String>[];
    var loopOrderIndex = 0;

    // Build exposure nodes for each enabled filter inside the loop
    for (final filterConfig in enabledFilters) {
      final expId = const Uuid().v4();
      final hasFilterWheel = ref.read(profileFiltersProvider).isNotEmpty;

      nodes[expId] = ExposureNode(
        id: expId,
        name: filterConfig.filterName,
        durationSecs: filterConfig.exposureSecs,
        count: 1, // 1 per loop iteration; loop controls total count
        filter: hasFilterWheel ? filterConfig.filterName : null,
        filterIndex: hasFilterWheel ? filterConfig.filterIndex : null,
        binning: filterConfig.binning,
        parentId: loopId,
        orderIndex: loopOrderIndex++,
      );
      loopChildIds.add(expId);
    }

    // -- Dither after each loop iteration
    if (_enableDithering && _enableAutoGuide) {
      final ditherId = const Uuid().v4();
      final sequencerDefaults = ref.read(sequencerDefaultsProvider);
      nodes[ditherId] = DitherNode(
        id: ditherId,
        name: 'Dither',
        pixels: _ditherPixels,
        settleTime: sequencerDefaults.ditherSettleTime > 0
            ? sequencerDefaults.ditherSettleTime
            : _kWizardDitherSettleSecondsFallback,
        parentId: loopId,
        orderIndex: loopOrderIndex++,
      );
      loopChildIds.add(ditherId);
    }

    // Create the loop node
    nodes[loopId] = LoopNode(
      id: loopId,
      name: 'Capture Loop',
      conditionType: _loopType,
      repeatCount: _loopType == LoopConditionType.count ? _loopCount : null,
      parentId: rootId,
      orderIndex: orderIndex++,
      childIds: loopChildIds,
    );
    rootChildIds.add(loopId);

    // -- Stop guiding
    if (_enableAutoGuide) {
      final stopGuideId = const Uuid().v4();
      nodes[stopGuideId] = StopGuidingNode(
        id: stopGuideId,
        name: 'Stop Guiding',
        parentId: rootId,
        orderIndex: orderIndex++,
      );
      rootChildIds.add(stopGuideId);
    }

    // -- Warm camera
    if (_coolCamera) {
      final warmId = const Uuid().v4();
      nodes[warmId] = WarmCameraNode(
        id: warmId,
        ratePerMin: 5,
        parentId: rootId,
        orderIndex: orderIndex++,
      );
      rootChildIds.add(warmId);
    }

    // -- End-of-session park. This terminal ParkNode is paired with the
    // WarmCamera step above as the normal dawn-shutdown sequence. It runs
    // unconditionally at the end of a successful session and is driven ONLY
    // by the Dawn-Shutdown intent. "Park on error" is a different concern —
    // it's an unscheduled abort, handled below as a RecoveryNode trigger, not
    // a terminal step.
    if (_dawnShutdown) {
      final parkId = const Uuid().v4();
      nodes[parkId] = ParkNode(
        id: parkId,
        name: 'Park Mount',
        parentId: rootId,
        orderIndex: orderIndex++,
      );
      rootChildIds.add(parkId);
    }

    // -- Create the target header as root
    final targetHeaderId = const Uuid().v4();
    nodes[targetHeaderId] = TargetHeaderNode(
      id: targetHeaderId,
      name: targetName,
      targetName: targetName,
      raHours: ra,
      decDegrees: dec,
      childIds: [rootId],
      orderIndex: 0,
    );

    // -- Create the InstructionSet root inside the target
    nodes[rootId] = InstructionSetNode(
      id: rootId,
      name: 'Sequence',
      childIds: rootChildIds,
      parentId: targetHeaderId,
      orderIndex: 0,
    );

    // -- Create triggers as parallel watchdogs if needed
    // Triggers run alongside the capture loop
    if (_enableAutofocus && _autofocusEveryFrames > 0) {
      // HFR degradation trigger for refocusing
      final hfrTriggerId = const Uuid().v4();
      nodes[hfrTriggerId] = RecoveryNode(
        id: hfrTriggerId,
        name: 'HFR Refocus Trigger',
        triggerType: TriggerType.hfrDegraded,
        recoveryAction: RecoveryActionType.autofocus,
        hfrThresholdPercent: 20.0,
        hfrConsecutiveFrames: 3,
        maxRetries: 5,
        parentId: targetHeaderId,
        orderIndex: 1,
      );
      nodes[targetHeaderId] = (nodes[targetHeaderId] as TargetHeaderNode)
          .copyWith(childIds: [rootId, hfrTriggerId]);
    }

    if (_enableMeridianFlip) {
      final flipId = const Uuid().v4();
      nodes[flipId] = MeridianFlipNode(
        id: flipId,
        name: 'Meridian Flip',
        autoCenter: true,
        refocusAfter: _enableAutofocus,
        resumeGuiding: _enableAutoGuide,
        parentId: targetHeaderId,
        orderIndex: 2,
        // Why: the wizard reflects the user's explicit choices from earlier
        // pages (autofocus enabled, guiding enabled, etc.); persist those as
        // per-node overrides so subsequent changes in Sequencer Settings
        // don't quietly undo what the operator picked here (audit §1.2).
        useGlobalDefaults: false,
      );
      final currentTarget = nodes[targetHeaderId] as TargetHeaderNode;
      nodes[targetHeaderId] = currentTarget.copyWith(
        childIds: [...currentTarget.childIds, flipId],
      );
    }

    // -- Weather abort recovery
    if (_weatherAbort) {
      final weatherRecoveryId = const Uuid().v4();
      nodes[weatherRecoveryId] = RecoveryNode(
        id: weatherRecoveryId,
        name: 'Weather Safety',
        triggerType: TriggerType.weatherUnsafe,
        recoveryAction: RecoveryActionType.parkAndAbort,
        maxRetries: 1,
        parentId: targetHeaderId,
        orderIndex: 3,
      );
      final currentTarget = nodes[targetHeaderId] as TargetHeaderNode;
      nodes[targetHeaderId] = currentTarget.copyWith(
        childIds: [...currentTarget.childIds, weatherRecoveryId],
      );
    }

    // -- Park on unrecoverable error. The "Park on Error" safety toggle is an
    // *abort* concern, not an end-of-session step — so it's modelled as a
    // RecoveryNode trigger on the TargetHeader (mirroring the weather-abort
    // RecoveryNode above) rather than an unconditional terminal ParkNode. We
    // gate on a lost mount (the canonical unrecoverable hardware fault that
    // leaves the rig pointing somewhere unsafe) and park-and-abort so the
    // mount comes home instead of tracking into a pier/horizon.
    if (_parkOnError) {
      final errorRecoveryId = const Uuid().v4();
      nodes[errorRecoveryId] = RecoveryNode(
        id: errorRecoveryId,
        name: 'Park on Error',
        triggerType: TriggerType.mountTrackingLost,
        recoveryAction: RecoveryActionType.parkAndAbort,
        maxRetries: 1,
        parentId: targetHeaderId,
        orderIndex: 4,
      );
      final currentTarget = nodes[targetHeaderId] as TargetHeaderNode;
      nodes[targetHeaderId] = currentTarget.copyWith(
        childIds: [...currentTarget.childIds, errorRecoveryId],
      );
    }

    // Build the Sequence object
    final sequence = Sequence.create(
      name: '$targetName Sequence',
      description: _buildDescription(enabledFilters),
      nodes: nodes,
      rootNodeId: targetHeaderId,
      isTemplate: asTemplate,
    );

    // Opt-in: persist the user's wizard choices as their new defaults so the
    // next launch pre-fills with them.
    if (_saveAsDefaults) {
      _persistChoicesAsDefaults(enabledFilters);
    }

    if (asTemplate) {
      // Persist as a reusable template via the sequence repository instead of
      // loading it into the editor. Fire-and-forget with snackbar feedback.
      final repository = ref.read(sequenceRepositoryProvider);
      () async {
        try {
          await repository.saveSequence(sequence, isTemplate: true);
          if (!mounted) return;
          Navigator.of(context).pop();
          context.showSuccessSnackBar(
              'Saved "$targetName Sequence" as a template');
        } catch (e) {
          if (mounted) {
            context.showErrorSnackBar('Could not save template: $e');
          }
        }
      }();
      return;
    }

    // Load into editor and switch to Builder tab. The user just completed
    // the wizard so we treat that as explicit confirmation to replace the
    // current sequence — skip the unsaved-changes prompt.
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);
    sequenceNotifier.loadSequence(sequence, discardUnsaved: true);
    ref.read(sequencerTabProvider.notifier).state = 0;

    Navigator.of(context).pop();
    context.showSuccessSnackBar(
        'Created sequence for "$targetName" with ${enabledFilters.length} filter(s)');
  }

  /// Write the user's wizard choices back into their persisted Sequencer
  /// Settings / app settings so the next launch pre-fills with them. Mirrors
  /// Smart Night's fire-and-forget pattern: failures are swallowed because a
  /// failed preference write is a UX degradation, not a sequence-correctness
  /// issue, and the sequence has already been built either way.
  ///
  /// The equipment-profile cooling temperature is intentionally NOT persisted
  /// here — that lives on the freezed EquipmentProfileModel and is owned by
  /// the equipment area's profile DAO; persisting it would require touching
  /// that subsystem. The user can set it on the profile editor.
  void _persistChoicesAsDefaults(List<_FilterExposureConfig> enabledFilters) {
    final sequencerDefaults = ref.read(sequencerDefaultsProvider.notifier);
    final appSettings = ref.read(appSettingsProvider.notifier);
    // Derive a representative exposure count: the loop count is the wizard's
    // single iteration knob and is what the user most directly tuned.
    final exposureCount = _loopCount > 0 ? _loopCount : null;
    () async {
      try {
        await sequencerDefaults.updateAutofocusDefaults(
          intervalFrames: _autofocusEveryFrames,
        );
        await sequencerDefaults.updateDitherDefaults(pixels: _ditherPixels);
        if (exposureCount != null) {
          await sequencerDefaults.updateExposureDefaults(count: exposureCount);
        }
        await appSettings.setEnableMeridianFlip(_enableMeridianFlip);
        await appSettings.setParkOnUnsafeWeather(_weatherAbort);
        await appSettings.setParkBeforeDawn(_dawnShutdown);
      } catch (_) {
        // Persistence is best-effort; surfacing this would be noise.
      }
    }();
  }

  String _buildDescription(List<_FilterExposureConfig> enabledFilters) {
    final filterSummary = enabledFilters
        .map((f) => '${f.filterName}: ${f.count}x${f.exposureSecs.round()}s')
        .join(', ');
    final features = <String>[];
    if (_enableAutofocus) features.add('autofocus');
    if (_enableDithering) features.add('dithering');
    if (_enableMeridianFlip) features.add('meridian flip');
    if (_enableAutoGuide) features.add('auto-guide');
    if (_weatherAbort) features.add('weather safety');
    return '$filterSummary | ${features.join(", ")}';
  }

  // ---------------------------------------------------------------------------
  // Estimated time calculation
  // ---------------------------------------------------------------------------

  double _estimatedTotalSecs() {
    final enabledFilters = _filterConfigs.where((f) => f.enabled).toList();
    if (enabledFilters.isEmpty) return 0;

    // Per-iteration: sum of all filter exposures + dither settle time
    double perIterationSecs = 0;
    for (final f in enabledFilters) {
      perIterationSecs += f.exposureSecs;
    }
    if (_enableDithering) perIterationSecs += _ditherSettleSecsForEstimate();

    double totalSecs;
    if (_loopType == LoopConditionType.count) {
      totalSecs = perIterationSecs * _loopCount;
    } else {
      // For unbounded loops, show per-iteration time
      totalSecs = perIterationSecs;
    }

    // Add overhead: cooling ~5min, slew+center ~3min, autofocus ~2min, warm ~5min
    double overheadSecs = 0;
    if (_coolCamera) overheadSecs += 300;
    overheadSecs += 180; // slew + center
    if (_enableAutofocus) overheadSecs += 120;
    if (_coolCamera) overheadSecs += 300;

    return totalSecs + overheadSecs;
  }

  String _formatDuration(double totalSecs) {
    if (_loopType != LoopConditionType.count) {
      final perIter = _estimatedPerIterationSecs();
      final mins = (perIter / 60).round();
      return '~${mins}m/iteration (runs until stopped)';
    }
    final hours = (totalSecs / 3600).floor();
    final mins = ((totalSecs % 3600) / 60).round();
    if (hours > 0) {
      return '~${hours}h ${mins}m';
    }
    return '~${mins}m';
  }

  double _estimatedPerIterationSecs() {
    final enabledFilters = _filterConfigs.where((f) => f.enabled).toList();
    double perIter = 0;
    for (final f in enabledFilters) {
      perIter += f.exposureSecs;
    }
    if (_enableDithering) perIter += _ditherSettleSecsForEstimate();
    return perIter;
  }

  /// Per-iteration dither-settle estimate used by the duration preview.
  /// Reads the user's Sequencer-Defaults settle time so the wizard's
  /// "Estimated Duration" agrees with the value the sequence will
  /// actually run with.
  double _ditherSettleSecsForEstimate() {
    final sequencerDefaults = ref.read(sequencerDefaultsProvider);
    return sequencerDefaults.ditherSettleTime > 0
        ? sequencerDefaults.ditherSettleTime
        : _kWizardDitherSettleSecondsFallback;
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  bool _canAdvance() {
    switch (_currentStep) {
      case 0: // Target
        return _targetNameController.text.trim().isNotEmpty &&
            (_selectedTarget != null ||
                (_parseRa(_raController.text) != null &&
                    _parseDec(_decController.text) != null));
      case 1: // Filters
        return _filterConfigs.any((f) => f.enabled);
      case 2: // Automation
      case 3: // Safety
        return true;
      case 4: // Review
        return true;
      default:
        return false;
    }
  }

  void _update(VoidCallback callback) => setState(callback);

  /// Re-run the exposure recommendation against the latest
  /// [_exposureContext] and re-seed every non-user-edited filter row. Lets
  /// the user regenerate the preview after tweaking knobs on earlier steps.
  /// User-edited exposures (exposureEdited == true) are preserved.
  void _rePreviewExposures() {
    setState(() {
      for (final config in _filterConfigs) {
        if (!config.exposureEdited) {
          config.exposureSecs = _defaultExposureForFilter(config.filterName);
        }
      }
      _syncFilterControllers();
    });
    // Best-effort refresh of the smart context in case the active profile /
    // sky inputs changed since the wizard opened; its async arrival re-seeds
    // again via _loadExposureContext.
    _loadExposureContext();
  }

  @override
  Widget build(BuildContext context) => _buildDialog(context);
}
