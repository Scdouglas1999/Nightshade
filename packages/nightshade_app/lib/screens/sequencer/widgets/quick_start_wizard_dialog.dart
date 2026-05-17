import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
// ignore: implementation_imports
import 'package:nightshade_core/src/database/database.dart' show Target;
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../utils/snackbar_helper.dart';
import '../sequencer_screen.dart';

// =============================================================================
// WIZARD STATE
// =============================================================================

/// Per-filter exposure configuration in the wizard
class _FilterExposureConfig {
  String filterName;
  int filterIndex;
  bool enabled;
  double exposureSecs;
  int count;
  BinningMode binning = BinningMode.one;

  _FilterExposureConfig({
    required this.filterName,
    required this.filterIndex,
    this.enabled = true,
    this.exposureSecs = 120.0,
    this.count = 10,
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
        return 'L: 120s, R/G/B: 120s each';
      case _ExposurePreset.narrowbandSho:
        return 'SII/Ha/OIII: 300s each';
      case _ExposurePreset.narrowbandHaOiii:
        return 'Ha/OIII: 180s each';
      case _ExposurePreset.oscNoFilter:
        return 'Single filter, 120s exposures';
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
  List<Target> _searchResults = [];
  Timer? _searchDebounce;
  bool _isSearching = false;
  Target? _selectedTarget;

  // Step 2: Filters & Exposures
  List<_FilterExposureConfig> _filterConfigs = [];
  _ExposurePreset _selectedPreset = _ExposurePreset.custom;
  LoopConditionType _loopType = LoopConditionType.count;
  int _loopCount = 10;

  // Step 3: Automation
  bool _enableAutofocus = true;
  int _autofocusEveryFrames = 30;
  bool _enableDithering = true;
  double _ditherPixels = 5.0;
  bool _enableMeridianFlip = true;
  bool _enableAutoGuide = true;

  // Step 4: Safety
  bool _parkOnError = true;
  bool _weatherAbort = false;
  bool _dawnShutdown = true;
  bool _coolCamera = true;
  double _coolingTemp = -10.0;

  @override
  void initState() {
    super.initState();
    _initFilterConfigs();
  }

  void _initFilterConfigs() {
    // Get filter names from the active equipment profile
    final filters = ref.read(profileFiltersProvider);

    if (filters.isEmpty) {
      // No filter wheel or no filters configured - default to a single "Light" entry
      _filterConfigs = [
        _FilterExposureConfig(
          filterName: 'Light',
          filterIndex: 0,
          enabled: true,
          exposureSecs: 120.0,
          count: 10,
        ),
      ];
    } else {
      _filterConfigs = filters.asMap().entries.map((entry) {
        return _FilterExposureConfig(
          filterName: entry.value,
          filterIndex: entry.key,
          enabled: _isCommonFilter(entry.value),
          exposureSecs: _defaultExposureForFilter(entry.value),
          count: 10,
        );
      }).toList();
    }
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
    final lower = name.toLowerCase();
    if (lower == 'ha' ||
        lower == 'h-alpha' ||
        lower == 'oiii' ||
        lower == 'sii') {
      return 300.0; // 5 minutes for narrowband
    }
    return 120.0; // 2 minutes for broadband
  }

  @override
  void dispose() {
    _targetNameController.dispose();
    _raController.dispose();
    _decController.dispose();
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

  void _selectTarget(Target target) {
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
    setState(() {
      _selectedPreset = preset;

      for (final config in _filterConfigs) {
        final lower = config.filterName.toLowerCase();

        switch (preset) {
          case _ExposurePreset.lrgbBroadband:
            config.enabled =
                lower == 'l' || lower == 'r' || lower == 'g' || lower == 'b';
            config.exposureSecs = 120.0;
            config.count = 10;
            config.binning = BinningMode.one;

          case _ExposurePreset.narrowbandSho:
            config.enabled = lower == 'sii' ||
                lower == 'ha' ||
                lower == 'h-alpha' ||
                lower == 'oiii';
            config.exposureSecs = 300.0;
            config.count = 10;
            config.binning = BinningMode.one;

          case _ExposurePreset.narrowbandHaOiii:
            config.enabled =
                lower == 'ha' || lower == 'h-alpha' || lower == 'oiii';
            config.exposureSecs = 180.0;
            config.count = 15;
            config.binning = BinningMode.one;

          case _ExposurePreset.oscNoFilter:
            config.enabled = config.filterIndex == 0;
            config.exposureSecs = 120.0;
            config.count = 20;
            config.binning = BinningMode.one;

          case _ExposurePreset.custom:
            // Don't change anything
            break;
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Sequence generation
  // ---------------------------------------------------------------------------

  void _createSequence() {
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
      nodes[guideId] = StartGuidingNode(
        id: guideId,
        name: 'Start Guiding',
        settlePixels: 1.5,
        settleTime: 10.0,
        settleTimeout: 60.0,
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
      nodes[ditherId] = DitherNode(
        id: ditherId,
        name: 'Dither',
        pixels: _ditherPixels,
        settleTime: 30.0,
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

    // -- Park on completion (always good practice, user can disable)
    if (_parkOnError || _dawnShutdown) {
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

    // Build the Sequence object
    final sequence = Sequence(
      name: '$targetName Sequence',
      description: _buildDescription(enabledFilters),
      nodes: nodes,
      rootNodeId: targetHeaderId,
      isTemplate: false,
    );

    // Load into editor and switch to Builder tab
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);
    sequenceNotifier.loadSequence(sequence);
    ref.read(sequencerTabProvider.notifier).state = 0;

    Navigator.of(context).pop();
    context.showSuccessSnackBar(
        'Created sequence for "$targetName" with ${enabledFilters.length} filter(s)');
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
    if (_enableDithering) perIterationSecs += 30; // dither settle

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
    if (_enableDithering) perIter += 30;
    return perIter;
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

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(colors),
            _buildStepIndicator(colors),
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: _buildCurrentStep(colors),
              ),
            ),
            _buildFooter(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.wand2, color: colors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick-Start Sequence Wizard',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _stepTitle(_currentStep),
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, color: colors.textSecondary, size: 20),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  String _stepTitle(int step) {
    switch (step) {
      case 0:
        return 'Step 1 of 5: Choose Your Target';
      case 1:
        return 'Step 2 of 5: Filters & Exposures';
      case 2:
        return 'Step 3 of 5: Automation';
      case 3:
        return 'Step 4 of 5: Safety';
      case 4:
        return 'Step 5 of 5: Review & Create';
      default:
        return '';
    }
  }

  Widget _buildStepIndicator(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isCompleted = index < _currentStep;
          final isCurrent = index == _currentStep;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: isCompleted || isCurrent
                          ? colors.primary
                          : colors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (index < _totalSteps - 1) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep(NightshadeColors colors) {
    switch (_currentStep) {
      case 0:
        return _buildTargetStep(colors);
      case 1:
        return _buildFiltersStep(colors);
      case 2:
        return _buildAutomationStep(colors);
      case 3:
        return _buildSafetyStep(colors);
      case 4:
        return _buildReviewStep(colors);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFooter(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            TextButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: Icon(LucideIcons.chevronLeft,
                  size: 16, color: colors.textSecondary),
              label:
                  Text('Back', style: TextStyle(color: colors.textSecondary)),
            )
          else
            const SizedBox.shrink(),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child:
                    Text('Cancel', style: TextStyle(color: colors.textMuted)),
              ),
              const SizedBox(width: 12),
              if (_currentStep < _totalSteps - 1)
                NightshadeButton(
                  onPressed: _canAdvance()
                      ? () => setState(() => _currentStep++)
                      : null,
                  icon: LucideIcons.chevronRight,
                  label: 'Next',
                )
              else
                NightshadeButton(
                  onPressed: _canAdvance() ? _createSequence : null,
                  icon: LucideIcons.sparkles,
                  label: 'Create Sequence',
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STEP 1: TARGET
  // ===========================================================================

  Widget _buildTargetStep(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search for a target or enter coordinates manually.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Target name / search
        TextField(
          controller: _targetNameController,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Target Name',
            hintText: 'e.g., M42, NGC 7000, Orion Nebula',
            prefixIcon: Icon(LucideIcons.search, color: colors.textMuted),
            suffixIcon: _isSearching
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            filled: true,
            fillColor: colors.surfaceAlt,
            labelStyle: TextStyle(color: colors.textSecondary),
            hintStyle: TextStyle(color: colors.textMuted),
          ),
          onChanged: _onTargetSearch,
        ),

        // Search results
        if (_searchResults.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final target = _searchResults[index];
                return ListTile(
                  dense: true,
                  title: Text(
                    target.name,
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${target.catalogId ?? ""} | RA: ${_formatRa(target.ra)} Dec: ${_formatDec(target.dec)}',
                    style: TextStyle(color: colors.textMuted, fontSize: 11),
                  ),
                  trailing: target.magnitude != null
                      ? Text(
                          'mag ${target.magnitude!.toStringAsFixed(1)}',
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 11),
                        )
                      : null,
                  onTap: () => _selectTarget(target),
                );
              },
            ),
          ),

        const SizedBox(height: 20),

        // Coordinates
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _raController,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Right Ascension',
                  hintText: '12h 30m 0s or 12.5',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  labelStyle: TextStyle(color: colors.textSecondary),
                  hintStyle: TextStyle(color: colors.textMuted),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _decController,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Declination',
                  hintText: "+45d 30' 0\" or 45.5",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.primary),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  labelStyle: TextStyle(color: colors.textSecondary),
                  hintStyle: TextStyle(color: colors.textMuted),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),

        if (_selectedTarget != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: colors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Selected: ${_selectedTarget!.name}'
                    '${_selectedTarget!.objectType != null ? " (${_selectedTarget!.objectType})" : ""}',
                    style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // STEP 2: FILTERS & EXPOSURES
  // ===========================================================================

  Widget _buildFiltersStep(NightshadeColors colors) {
    final hasFilters = ref.watch(profileFiltersProvider).isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasFilters) ...[
          Text(
            'Quick Presets',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ExposurePreset.values.map((preset) {
              final isSelected = _selectedPreset == preset;
              return InkWell(
                onTap: () => _applyPreset(preset),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.primary.withValues(alpha: 0.15)
                        : colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? colors.primary : colors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.label,
                        style: TextStyle(
                          color:
                              isSelected ? colors.primary : colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        preset.description,
                        style: TextStyle(color: colors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],

        Text(
          hasFilters ? 'Filter Exposures' : 'Exposure Settings',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),

        // Column headers
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text('Filter',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ),
              Expanded(
                flex: 2,
                child: Text('Exposure',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ),
              Expanded(
                flex: 2,
                child: Text('Count',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ),
              Expanded(
                flex: 2,
                child: Text('Binning',
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ),
              const SizedBox(width: 60),
            ],
          ),
        ),
        const SizedBox(height: 4),

        ...List.generate(_filterConfigs.length, (index) {
          final config = _filterConfigs[index];
          return _buildFilterRow(config, colors);
        }),

        const SizedBox(height: 20),

        // Loop settings
        Text(
          'Loop Settings',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<LoopConditionType>(
                initialValue: _loopType,
                dropdownColor: colors.surfaceAlt,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Loop Type',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  labelStyle: TextStyle(color: colors.textSecondary),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: [
                  LoopConditionType.count,
                  LoopConditionType.forever,
                  LoopConditionType.whileDark,
                ].map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(
                      type == LoopConditionType.count
                          ? 'Fixed Count'
                          : type == LoopConditionType.forever
                              ? 'Run Forever'
                              : 'While Dark',
                      style: TextStyle(color: colors.textPrimary),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _loopType = value);
                },
              ),
            ),
            if (_loopType == LoopConditionType.count) ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: TextField(
                  controller:
                      TextEditingController(text: _loopCount.toString()),
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Iterations',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    labelStyle: TextStyle(color: colors.textSecondary),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed > 0) {
                      setState(() => _loopCount = parsed);
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFilterRow(
      _FilterExposureConfig config, NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Checkbox(
              value: config.enabled,
              onChanged: (value) {
                setState(() {
                  config.enabled = value ?? false;
                  _selectedPreset = _ExposurePreset.custom;
                });
              },
              activeColor: colors.primary,
              side: BorderSide(color: colors.border),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              config.filterName,
              style: TextStyle(
                color: config.enabled ? colors.textPrimary : colors.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller: TextEditingController(
                    text: config.exposureSecs.round().toString()),
                enabled: config.enabled,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  suffixText: 's',
                  suffixStyle: TextStyle(color: colors.textMuted, fontSize: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                onChanged: (value) {
                  final parsed = double.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    config.exposureSecs = parsed;
                    _selectedPreset = _ExposurePreset.custom;
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextField(
                controller:
                    TextEditingController(text: config.count.toString()),
                enabled: config.enabled,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    config.count = parsed;
                    _selectedPreset = _ExposurePreset.custom;
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: DropdownButtonFormField<BinningMode>(
                initialValue: config.binning,
                dropdownColor: colors.surfaceAlt,
                style: TextStyle(color: colors.textPrimary, fontSize: 12),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: colors.border),
                  ),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                items: BinningMode.values.map((mode) {
                  return DropdownMenuItem(
                    value: mode,
                    child: Text(mode.label,
                        style: TextStyle(color: colors.textPrimary)),
                  );
                }).toList(),
                onChanged: config.enabled
                    ? (value) {
                        if (value != null) {
                          setState(() {
                            config.binning = value;
                            _selectedPreset = _ExposurePreset.custom;
                          });
                        }
                      }
                    : null,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              _formatFilterTotal(config),
              style: TextStyle(
                color: config.enabled ? colors.textSecondary : colors.textMuted,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFilterTotal(_FilterExposureConfig config) {
    if (!config.enabled) return '';
    final totalMins = (config.totalSecs / 60).round();
    return '${totalMins}m';
  }

  // ===========================================================================
  // STEP 3: AUTOMATION
  // ===========================================================================

  Widget _buildAutomationStep(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure automation features for your imaging session.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.focus,
          title: 'Autofocus',
          subtitle:
              'Run autofocus before imaging and trigger refocus on HFR degradation',
          value: _enableAutofocus,
          onChanged: (v) => setState(() => _enableAutofocus = v),
        ),
        if (_enableAutofocus) ...[
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              children: [
                Text('Refocus trigger:',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  height: 32,
                  child: TextField(
                    controller: TextEditingController(
                        text: _autofocusEveryFrames.toString()),
                    style: TextStyle(color: colors.textPrimary, fontSize: 12),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      filled: true,
                      fillColor: colors.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    onChanged: (value) {
                      final parsed = int.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        setState(() => _autofocusEveryFrames = parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text('frames (HFR-based)',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.shuffle,
          title: 'Dithering',
          subtitle:
              'Shift the image slightly between exposures to reduce noise patterns',
          value: _enableDithering,
          onChanged: (v) => setState(() => _enableDithering = v),
        ),
        if (_enableDithering) ...[
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              children: [
                Text('Dither amount:',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  height: 32,
                  child: TextField(
                    controller: TextEditingController(
                        text: _ditherPixels.round().toString()),
                    style: TextStyle(color: colors.textPrimary, fontSize: 12),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      suffixText: 'px',
                      suffixStyle:
                          TextStyle(color: colors.textMuted, fontSize: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      filled: true,
                      fillColor: colors.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null && parsed > 0) {
                        setState(() => _ditherPixels = parsed);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.refreshCw,
          title: 'Meridian Flip',
          subtitle: 'Automatically flip the mount when crossing the meridian',
          value: _enableMeridianFlip,
          onChanged: (v) => setState(() => _enableMeridianFlip = v),
        ),
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.crosshair,
          title: 'Auto-Guide',
          subtitle: 'Start PHD2 guiding before imaging and stop after',
          value: _enableAutoGuide,
          onChanged: (v) => setState(() => _enableAutoGuide = v),
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required NightshadeColors colors,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon,
              color: value ? colors.primary : colors.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    )),
                Text(subtitle,
                    style: TextStyle(color: colors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: colors.primary,
            thumbColor: WidgetStateProperty.all(Colors.white),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STEP 4: SAFETY
  // ===========================================================================

  Widget _buildSafetyStep(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure safety and shutdown behavior.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.snowflake,
          title: 'Cool Camera',
          subtitle: 'Cool the camera sensor before imaging and warm after',
          value: _coolCamera,
          onChanged: (v) => setState(() => _coolCamera = v),
        ),
        if (_coolCamera) ...[
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              children: [
                Text('Target temperature:',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  height: 32,
                  child: TextField(
                    controller: TextEditingController(
                        text: _coolingTemp.round().toString()),
                    style: TextStyle(color: colors.textPrimary, fontSize: 12),
                    keyboardType:
                        const TextInputType.numberWithOptions(signed: true),
                    decoration: InputDecoration(
                      suffixText: 'C',
                      suffixStyle:
                          TextStyle(color: colors.textMuted, fontSize: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: colors.border),
                      ),
                      filled: true,
                      fillColor: colors.surfaceAlt,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    onChanged: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null) {
                        setState(() => _coolingTemp = parsed);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.parkingCircle,
          title: 'Park on Error',
          subtitle: 'Park the mount if an unrecoverable error occurs',
          value: _parkOnError,
          onChanged: (v) => setState(() => _parkOnError = v),
        ),
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.cloudRain,
          title: 'Weather Abort',
          subtitle: 'Park and abort if the weather becomes unsafe',
          value: _weatherAbort,
          onChanged: (v) => setState(() => _weatherAbort = v),
        ),
        _buildToggleRow(
          colors: colors,
          icon: LucideIcons.sunrise,
          title: 'Dawn Shutdown',
          subtitle: 'Warm camera and park mount at the end of the session',
          value: _dawnShutdown,
          onChanged: (v) => setState(() => _dawnShutdown = v),
        ),
      ],
    );
  }

  // ===========================================================================
  // STEP 5: REVIEW
  // ===========================================================================

  Widget _buildReviewStep(NightshadeColors colors) {
    final enabledFilters = _filterConfigs.where((f) => f.enabled).toList();
    final totalSecs = _estimatedTotalSecs();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review your sequence before creating it.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Target summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.target,
          title: 'Target',
          children: [
            _reviewRow(colors, 'Name', _targetNameController.text),
            _reviewRow(colors, 'RA', _raController.text),
            _reviewRow(colors, 'Dec', _decController.text),
          ],
        ),

        const SizedBox(height: 12),

        // Filters summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.camera,
          title:
              'Exposures (${enabledFilters.length} filter${enabledFilters.length != 1 ? "s" : ""})',
          children: enabledFilters.map((f) {
            return _reviewRow(
              colors,
              f.filterName,
              '${f.count}x ${f.exposureSecs.round()}s (${f.binning.label})',
            );
          }).toList(),
        ),

        const SizedBox(height: 12),

        // Loop summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.repeat,
          title: 'Loop',
          children: [
            _reviewRow(
              colors,
              'Type',
              _loopType == LoopConditionType.count
                  ? '$_loopCount iterations'
                  : _loopType == LoopConditionType.forever
                      ? 'Run forever'
                      : 'While dark',
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Automation summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.settings,
          title: 'Automation',
          children: [
            _reviewRow(colors, 'Autofocus',
                _enableAutofocus ? 'Enabled (HFR-based)' : 'Disabled'),
            _reviewRow(colors, 'Dithering',
                _enableDithering ? '${_ditherPixels.round()}px' : 'Disabled'),
            _reviewRow(colors, 'Meridian Flip',
                _enableMeridianFlip ? 'Enabled' : 'Disabled'),
            _reviewRow(colors, 'Auto-Guide',
                _enableAutoGuide ? 'Enabled' : 'Disabled'),
          ],
        ),

        const SizedBox(height: 12),

        // Safety summary
        _buildReviewSection(
          colors: colors,
          icon: LucideIcons.shield,
          title: 'Safety',
          children: [
            _reviewRow(colors, 'Cool Camera',
                _coolCamera ? '${_coolingTemp.round()}C' : 'Disabled'),
            _reviewRow(
                colors, 'Park on Error', _parkOnError ? 'Enabled' : 'Disabled'),
            _reviewRow(colors, 'Weather Abort',
                _weatherAbort ? 'Enabled' : 'Disabled'),
            _reviewRow(colors, 'Dawn Shutdown',
                _dawnShutdown ? 'Enabled' : 'Disabled'),
          ],
        ),

        const SizedBox(height: 16),

        // Estimated time
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.clock, color: colors.primary, size: 20),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated Duration',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _formatDuration(totalSecs),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Tree preview
        _buildTreePreview(colors, enabledFilters),
      ],
    );
  }

  Widget _buildReviewSection({
    required NightshadeColors colors,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  Widget _reviewRow(NightshadeColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(color: colors.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(color: colors.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTreePreview(
      NightshadeColors colors, List<_FilterExposureConfig> enabledFilters) {
    // Build a visual tree preview of what will be created
    final treeLines = <_TreeLine>[];

    treeLines.add(_TreeLine(
      'Target: ${_targetNameController.text}',
      LucideIcons.target,
      0,
    ));

    if (_coolCamera) {
      treeLines.add(_TreeLine(
          'Cool Camera (${_coolingTemp.round()}C)', LucideIcons.snowflake, 1));
    }
    treeLines.add(_TreeLine('Slew to Target', LucideIcons.compass, 1));
    treeLines.add(_TreeLine('Plate Solve & Center', LucideIcons.crosshair, 1));
    if (_enableAutofocus) {
      treeLines.add(_TreeLine('Autofocus', LucideIcons.focus, 1));
    }
    if (_enableAutoGuide) {
      treeLines.add(_TreeLine('Start Guiding', LucideIcons.crosshair, 1));
    }

    final loopLabel = _loopType == LoopConditionType.count
        ? 'Capture Loop (x$_loopCount)'
        : _loopType == LoopConditionType.forever
            ? 'Capture Loop (forever)'
            : 'Capture Loop (while dark)';
    treeLines.add(_TreeLine(loopLabel, LucideIcons.repeat, 1));

    for (final f in enabledFilters) {
      treeLines.add(_TreeLine(
        '${f.filterName}: ${f.exposureSecs.round()}s',
        LucideIcons.camera,
        2,
      ));
    }
    if (_enableDithering && _enableAutoGuide) {
      treeLines.add(_TreeLine('Dither', LucideIcons.shuffle, 2));
    }

    if (_enableAutoGuide) {
      treeLines.add(_TreeLine('Stop Guiding', LucideIcons.xCircle, 1));
    }
    if (_coolCamera) {
      treeLines.add(_TreeLine('Warm Camera', LucideIcons.flame, 1));
    }
    if (_parkOnError || _dawnShutdown) {
      treeLines.add(_TreeLine('Park Mount', LucideIcons.parkingCircle, 1));
    }

    // Triggers
    if (_enableAutofocus) {
      treeLines
          .add(_TreeLine('HFR Refocus Trigger', LucideIcons.shieldCheck, 1));
    }
    if (_enableMeridianFlip) {
      treeLines.add(_TreeLine('Meridian Flip', LucideIcons.refreshCw, 1));
    }
    if (_weatherAbort) {
      treeLines.add(_TreeLine('Weather Safety', LucideIcons.cloudRain, 1));
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sequence Tree Preview',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...treeLines.map((line) {
            return Padding(
              padding: EdgeInsets.only(left: line.depth * 20.0, bottom: 2),
              child: Row(
                children: [
                  Icon(line.icon, color: colors.textMuted, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    line.label,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TreeLine {
  final String label;
  final IconData icon;
  final int depth;

  _TreeLine(this.label, this.icon, this.depth);
}
