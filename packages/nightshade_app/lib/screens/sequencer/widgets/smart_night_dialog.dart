import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/smart_night_plan_launcher.dart';
import '../../../utils/snackbar_helper.dart';

/// One-click "Plan tonight" wizard.
///
/// Reachable from the sequencer Builder tab toolbar. Walks the user
/// through six steps:
///
/// 1. Confirm tonight's window (sunset → sunrise of user's location;
///    user can narrow).
/// 2. Confirm equipment profile + camera + filter wheel.
/// 3. Choose targets — hand-pick from the saved/scored list OR let
///    the auto-builder pick the top-N by score.
/// 4. Choose strategy — auto LRGB / narrowband HOO / SHO / OSC /
///    mono LRGB.
/// 5. Preview the generated sequence (timeline + per-target / per-
///    filter breakdown). User can tweak counts before accepting.
/// 6. Accept → the new sequence is loaded into the editor and the
///    dialog closes.
class SmartNightDialog extends ConsumerStatefulWidget {
  const SmartNightDialog({super.key});

  @override
  ConsumerState<SmartNightDialog> createState() => _SmartNightDialogState();
}

class _SmartNightDialogState extends ConsumerState<SmartNightDialog> {
  int _step = 0;

  // ---- Step 1: window ---------------------------------------------------
  DateTime? _windowStart;
  DateTime? _windowEnd;
  bool _windowInitialised = false;

  // ---- Step 3: targets --------------------------------------------------
  /// User-selected target IDs. Empty → auto-pick top N by score.
  final Set<int> _selectedTargetIds = <int>{};
  bool _autoSelect = true;
  int _autoSelectCount = 2;

  // ---- Step 4: strategy -------------------------------------------------
  SmartNightStrategy _strategy = SmartNightStrategy.autoLrgb;

  // ---- Step 5: preview --------------------------------------------------
  SmartNightPlan? _preview;
  String? _previewError;
  String? _previewDraftId;

  // ---- Settings (defaults; wizard can override) ------------------------
  /// Local working copy of the wizard's [SmartNightSettings]. Seeded from
  /// the persisted defaults in [AppSettingsState] on first build; user
  /// changes are written back to settings so the next session pre-fills
  /// with the user's preferences (Wave 6 Pack O).
  SmartNightSettings _settings = const SmartNightSettings();
  bool _settingsSeededFromAppSettings = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    _ensureSettingsSeeded();
    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 880,
      designHeight: 720,
    );
    return Dialog(
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: NightshadeTokens.borderRadiusMd,
        side: BorderSide(color: colors.border),
      ),
      child: SizedBox(
        width: dialogSize.width,
        height: dialogSize.height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(colors),
              const SizedBox(height: 12),
              _buildStepIndicator(colors),
              const SizedBox(height: 16),
              Expanded(child: _buildStepBody(colors)),
              const SizedBox(height: 12),
              _buildFooter(colors),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Header / stepper / footer
  // ---------------------------------------------------------------------

  Widget _buildHeader(NightshadeColors colors) {
    return Row(
      children: [
        Icon(LucideIcons.sparkles, size: 22, color: colors.primary),
        const SizedBox(width: 10),
        Text(
          'Smart Night — Plan Tonight',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(LucideIcons.x, size: 18),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildStepIndicator(NightshadeColors colors) {
    const titles = [
      'Window',
      'Equipment',
      'Targets',
      'Strategy',
      'Preview',
      'Accept',
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < titles.length; i++) ...[
            _StepChip(
              label: '${i + 1}. ${titles[i]}',
              colors: colors,
              isActive: i == _step,
              isComplete: i < _step,
            ),
            if (i < titles.length - 1)
              Container(
                width: 12,
                height: 1,
                color: colors.border,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(NightshadeColors colors) {
    final isLast = _step == 5;
    return Row(
      children: [
        if (_step > 0)
          TextButton.icon(
            icon: const Icon(LucideIcons.chevronLeft, size: 16),
            label: const Text('Back'),
            onPressed: () => setState(() => _step--),
          ),
        const Spacer(),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          icon: Icon(
            isLast ? LucideIcons.play : LucideIcons.chevronRight,
            size: 16,
          ),
          label: Text(isLast ? 'Start Sequence' : 'Next'),
          onPressed: _onPrimaryPressed,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Step body
  // ---------------------------------------------------------------------

  Widget _buildStepBody(NightshadeColors colors) {
    switch (_step) {
      case 0:
        return _buildWindowStep(colors);
      case 1:
        return _buildEquipmentStep(colors);
      case 2:
        return _buildTargetsStep(colors);
      case 3:
        return _buildStrategyStep(colors);
      case 4:
        return _buildPreviewStep(colors);
      case 5:
        return _buildAcceptStep(colors);
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------- Step 1: window -------------------------------------------

  Widget _buildWindowStep(NightshadeColors colors) {
    _ensureWindowInitialised();
    final start = _windowStart;
    final end = _windowEnd;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tonight\'s dark window',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Computed from your location\'s astronomical twilight. '
            'You can narrow it if you don\'t want to image the full night.',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          if (start == null || end == null)
            _MissingLocationCard(colors: colors)
          else
            Container(
              padding: const EdgeInsets.all(14),
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
                      Icon(LucideIcons.sunset, size: 16, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Start: ${_formatDateTime(start)}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _pickDateTime(
                          initial: start,
                          onPicked: (dt) => setState(() => _windowStart = dt),
                        ),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Icon(LucideIcons.sunrise,
                          size: 16, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'End: ${_formatDateTime(end)}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _pickDateTime(
                          initial: end,
                          onPicked: (dt) => setState(() => _windowEnd = dt),
                        ),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${_formatDuration(end.difference(start))}',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          _SettingsRow(
            label: 'Max session length',
            colors: colors,
            child: _CompactNumberField(
              initial: _settings.maxSessionHours,
              suffix: 'h',
              onChanged: (v) {
                setState(() => _settings =
                    _settings.copyWith(maxSessionHours: v.clamp(1.0, 14.0)));
                // Persist the cap as a top-level setting too so the
                // setting survives even though the wizard's local
                // `_settings.maxSessionHours` is non-nullable.
                ref
                    .read(appSettingsProvider.notifier)
                    .setSmartNightMaxSessionHours(v.clamp(1.0, 14.0));
              },
            ),
          ),
          _SettingsRow(
            label: 'Min altitude',
            colors: colors,
            child: _CompactNumberField(
              initial: _settings.minAltitudeDeg,
              suffix: '°',
              onChanged: (v) => setState(() => _settings =
                  _settings.copyWith(minAltitudeDeg: v.clamp(10.0, 80.0))),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Step 2: equipment ----------------------------------------

  Widget _buildEquipmentStep(NightshadeColors colors) {
    final profile = ref.watch(activeEquipmentProfileProvider);
    if (profile == null) {
      return _MissingProfileCard(colors: colors);
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active equipment profile',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileRow(
                  icon: LucideIcons.tag,
                  label: 'Name',
                  value: profile.name,
                  colors: colors,
                ),
                _ProfileRow(
                  icon: LucideIcons.camera,
                  label: 'Camera',
                  value: profile.cameraName ?? '<no camera>',
                  colors: colors,
                ),
                _ProfileRow(
                  icon: LucideIcons.target,
                  label: 'OTA',
                  value: '${profile.telescopeName ?? "<no telescope>"} '
                      '(${profile.focalLength.toStringAsFixed(0)}mm @ '
                      'f/${(profile.calculatedFocalRatio ?? 0).toStringAsFixed(1)})',
                  colors: colors,
                ),
                _ProfileRow(
                  icon: LucideIcons.compass,
                  label: 'Mount',
                  value: profile.mountName ?? '<no mount>',
                  colors: colors,
                ),
                _ProfileRow(
                  icon: LucideIcons.layers,
                  label: 'Filters',
                  value: profile.filterNames.isEmpty
                      ? '<no filter wheel>'
                      : profile.filterNames.join(', '),
                  colors: colors,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SettingsRow(
            label: 'Cool to',
            colors: colors,
            child: _CompactNumberField(
              initial: _settings.coolDownTargetC,
              suffix: '°C',
              onChanged: (v) => setState(
                  () => _settings = _settings.copyWith(coolDownTargetC: v)),
            ),
          ),
          _SettingsRow(
            label: 'Has flat panel',
            colors: colors,
            child: NightshadeSwitch(
              value: _settings.hasCoverCalibrator,
              onChanged: (v) => setState(
                  () => _settings = _settings.copyWith(hasCoverCalibrator: v)),
            ),
          ),
          if (profile.coverCalibratorId != null &&
              !_settings.hasCoverCalibrator)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 6),
              child: Text(
                'A cover calibrator is bound to this profile — toggle '
                'this on to schedule auto-flats at session end.',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- Step 3: targets ------------------------------------------

  Widget _buildTargetsStep(NightshadeColors colors) {
    final suggestionsAsync = ref.watch(tonightSuggestionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pick tonight\'s targets',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              _autoSelect
                  ? 'Auto-pick the top'
                  : 'Hand-pick from suggestions below',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (_autoSelect) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: _CompactNumberField(
                  initial: _autoSelectCount.toDouble(),
                  suffix: '',
                  onChanged: (v) =>
                      setState(() => _autoSelectCount = v.round().clamp(1, 10)),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'by score',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            const Spacer(),
            FilterChip(
              label: const Text('Auto-pick'),
              selected: _autoSelect,
              onSelected: (v) => setState(() {
                _autoSelect = v;
                if (v) _selectedTargetIds.clear();
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: suggestionsAsync.when(
            data: (suggestions) {
              if (suggestions.isEmpty) {
                return _EmptyTargetsCard(colors: colors);
              }
              return ListView.builder(
                itemCount: suggestions.length,
                itemBuilder: (context, index) {
                  final s = suggestions[index];
                  return _TargetTile(
                    suggestion: s,
                    isSelected:
                        _autoSelect || _selectedTargetIds.contains(s.targetId),
                    isAutoMode: _autoSelect,
                    rank: index + 1,
                    autoPickedTop: _autoSelect && index < _autoSelectCount,
                    onToggle: () {
                      if (_autoSelect) return;
                      setState(() {
                        if (_selectedTargetIds.contains(s.targetId)) {
                          _selectedTargetIds.remove(s.targetId);
                        } else {
                          _selectedTargetIds.add(s.targetId);
                        }
                      });
                    },
                    colors: colors,
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                'Failed to load suggestions: $e',
                style: TextStyle(color: colors.error),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Step 4: strategy -----------------------------------------

  Widget _buildStrategyStep(NightshadeColors colors) {
    final profile = ref.watch(activeEquipmentProfileProvider);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose imaging strategy',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          for (final s in SmartNightStrategy.values)
            _StrategyTile(
              strategy: s,
              isSelected: _strategy == s,
              filtersAvailable: _strategyFitsProfile(s, profile),
              onSelected: () {
                setState(() => _strategy = s);
                _persistSettings();
              },
              colors: colors,
            ),
          const SizedBox(height: 18),
          Text(
            'Autofocus cadence',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          _AfCadenceSelector(
            value: _settings,
            onChanged: (v) {
              setState(() => _settings = v);
              _persistSettings();
            },
            colors: colors,
          ),
          const SizedBox(height: 18),
          _SettingsRow(
            label: 'Integration budget per target',
            colors: colors,
            child: _CompactNumberField(
              initial: _settings.defaultIntegrationBudgetHours,
              suffix: 'h',
              onChanged: (v) {
                setState(() => _settings =
                    _settings.copyWith(defaultIntegrationBudgetHours: v));
                _persistSettings();
              },
            ),
          ),
          _SettingsRow(
            label: 'Sub-exposure floor',
            colors: colors,
            child: _CompactNumberField(
              initial: _settings.subExposureFloorSecs,
              suffix: 's',
              onChanged: (v) => setState(() =>
                  _settings = _settings.copyWith(subExposureFloorSecs: v)),
            ),
          ),
          _SettingsRow(
            label: 'Sub-exposure ceiling',
            colors: colors,
            child: _CompactNumberField(
              initial: _settings.subExposureCeilingSecs,
              suffix: 's',
              onChanged: (v) => setState(() =>
                  _settings = _settings.copyWith(subExposureCeilingSecs: v)),
            ),
          ),
          _SettingsRow(
            label: 'Target SNR',
            colors: colors,
            child: _CompactNumberField(
              initial: _settings.targetSnr,
              suffix: '',
              onChanged: (v) {
                setState(() => _settings = _settings.copyWith(targetSnr: v));
                _persistSettings();
              },
            ),
          ),
          _SettingsRow(
            label: 'Auto flats at end',
            colors: colors,
            child: NightshadeSwitch(
              value: _settings.includeFlatsAtEnd,
              onChanged: (v) {
                setState(
                    () => _settings = _settings.copyWith(includeFlatsAtEnd: v));
                _persistSettings();
              },
            ),
          ),
          _SettingsRow(
            label: 'Auto-schedule missing darks',
            colors: colors,
            child: NightshadeSwitch(
              value: _settings.autoScheduleMissingDarks,
              onChanged: (v) {
                setState(() => _settings =
                    _settings.copyWith(autoScheduleMissingDarks: v));
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Step 5: preview ------------------------------------------

  Widget _buildPreviewStep(NightshadeColors colors) {
    if (_preview == null && _previewError == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_previewError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertCircle, size: 32, color: colors.error),
            const SizedBox(height: 8),
            Text(
              'Cannot build plan',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _previewError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(LucideIcons.chevronLeft, size: 14),
              label: const Text('Back to strategy'),
              onPressed: () => setState(() => _step = 3),
            ),
          ],
        ),
      );
    }
    final plan = _preview!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlanSummary(plan: plan),
          const SizedBox(height: 12),
          for (final p in plan.plannedTargets)
            _PlannedTargetCard(
              planned: p,
              colors: colors,
              onCountChanged: (filterIndex, delta) {
                _adjustFilterCount(p, filterIndex, delta);
              },
            ),
          SmartNightSafetyWatchdogsSection(plan: plan, colors: colors),
          if (plan.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Warnings',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            for (final w in plan.warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      size: 14,
                      color: colors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ---------- Step 6: accept -------------------------------------------

  Widget _buildAcceptStep(NightshadeColors colors) {
    final plan = _preview;
    if (plan == null) {
      return Center(
        child: Text(
          'No plan to load — please re-run preview.',
          style: TextStyle(color: colors.textSecondary),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
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
                    Icon(LucideIcons.checkCircle,
                        size: 20, color: colors.success),
                    const SizedBox(width: 10),
                    Text(
                      'Plan ready',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  plan.sequence.name,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  plan.sequence.description,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                _SummaryRow(
                  icon: LucideIcons.target,
                  label: 'Targets',
                  value: '${plan.plannedTargets.length}',
                  colors: colors,
                ),
                _SummaryRow(
                  icon: LucideIcons.camera,
                  label: 'Total integration',
                  value: _formatDuration(
                    Duration(seconds: plan.totalIntegrationSecs.round()),
                  ),
                  colors: colors,
                ),
                _SummaryRow(
                  icon: LucideIcons.clock,
                  label: 'Estimated wall-clock',
                  value: _formatDuration(
                    Duration(seconds: plan.estimatedWallClockSecs.round()),
                  ),
                  colors: colors,
                ),
                _SummaryRow(
                  icon: LucideIcons.list,
                  label: 'Sequence nodes',
                  value: '${plan.sequence.nodes.length}',
                  colors: colors,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Tapping "Start Sequence" replaces the current sequence with '
            'this plan, starts the executor, and opens the Imaging screen '
            'so you can monitor the run immediately.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Wiring + helpers
  // ---------------------------------------------------------------------

  void _ensureWindowInitialised() {
    if (_windowInitialised) return;
    final location = ref.read(appObserverLocationProvider);
    if (location == null) {
      _windowInitialised = true;
      return;
    }
    final svc = _buildService();
    final window = svc.calculateWindow(
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );
    _windowStart = window.start;
    _windowEnd = window.end;
    _windowInitialised = true;
  }

  /// Pull persisted wizard defaults from [AppSettingsState] and apply them
  /// to [_settings] on first build. The wizard mutates [_settings] in
  /// place as the user changes controls; persistent writes are pushed
  /// back through [_persistSettings] so the next launch pre-fills with
  /// the user's last choices.
  ///
  /// We also pre-select the persisted default strategy so step 4 lands
  /// on whatever the user picked last time.
  void _ensureSettingsSeeded() {
    if (_settingsSeededFromAppSettings) return;
    final app = ref.read(appSettingsProvider).valueOrNull;
    if (app == null) return; // try again next build once async loads
    _settingsSeededFromAppSettings = true;

    // Translate the persisted minutes/hours into the wizard's native
    // units. `null` => use SmartNightSettings constructor default
    // (12h cap for max session, infinite per-target budget capped by
    // window in practice).
    final maxHours = app.smartNightMaxSessionHours;
    final defaultIntegrationHours =
        app.smartNightDefaultIntegrationBudgetMinsPerTarget / 60.0;
    _settings = _settings.copyWith(
      maxSessionHours: maxHours ?? _settings.maxSessionHours,
      afEveryFrames: app.smartNightDefaultAfCadenceFrames,
      defaultIntegrationBudgetHours: defaultIntegrationHours,
      includeFlatsAtEnd: app.smartNightIncludeFlatsAtEnd,
      useSchedulerForMultiTarget: app.smartNightUseSchedulerForMultiTarget,
      schedulerTargetThreshold: app.smartNightSchedulerTargetThreshold,
      polarAlignmentStaleAfterDays: app.smartNightPolarAlignmentStaleAfterDays,
      subExposureFloorSecs: app.smartNightSubExposureFloorSecs,
      subExposureCeilingSecs: app.smartNightSubExposureCeilingSecs,
      targetSnr: app.smartNightTargetSnr,
    );
    _strategy = _strategyFromPersistedName(app.smartNightDefaultStrategy);
  }

  /// Translate the snake_case strategy id stored in app_settings back
  /// into a [SmartNightStrategy] enum value. Unknown strings fall back
  /// to [SmartNightStrategy.autoLrgb] (the constructor default).
  SmartNightStrategy _strategyFromPersistedName(String name) {
    switch (name) {
      case 'mono_lrgb':
        return SmartNightStrategy.monoLrgb;
      case 'narrowband_hoo':
        return SmartNightStrategy.narrowbandHoo;
      case 'narrowband_sho':
        return SmartNightStrategy.narrowbandSho;
      case 'osc_one_shot':
        return SmartNightStrategy.oscOneShot;
      case 'auto_lrgb':
      default:
        return SmartNightStrategy.autoLrgb;
    }
  }

  String _persistedNameForStrategy(SmartNightStrategy s) {
    switch (s) {
      case SmartNightStrategy.autoLrgb:
        return 'auto_lrgb';
      case SmartNightStrategy.monoLrgb:
        return 'mono_lrgb';
      case SmartNightStrategy.narrowbandHoo:
        return 'narrowband_hoo';
      case SmartNightStrategy.narrowbandSho:
        return 'narrowband_sho';
      case SmartNightStrategy.oscOneShot:
        return 'osc_one_shot';
    }
  }

  /// Best-effort writeback of the wizard's working [_settings] +
  /// [_strategy] into [AppSettingsState]. Called whenever the user
  /// changes a knob on steps 1/2/4 so the next launch pre-fills.
  ///
  /// Errors are swallowed (logged-only) because failing to persist a
  /// preference is a UX-degradation not a sequence-correctness issue:
  /// the user can still load the plan they've built; the next session
  /// just won't pre-fill with the same values. We surface no snackbar
  /// to avoid noise during normal usage.
  void _persistSettings() {
    if (!_settingsSeededFromAppSettings) return;
    final notifier = ref.read(appSettingsProvider.notifier);
    // Fire-and-forget — each setter writes through the DAO independently.
    // We don't await because the dialog's onChanged callbacks are sync.
    () async {
      try {
        await notifier
            .setSmartNightDefaultAfCadenceFrames(_settings.afEveryFrames);
        await notifier.setSmartNightDefaultIntegrationBudgetMinsPerTarget(
            (_settings.defaultIntegrationBudgetHours * 60).round());
        await notifier
            .setSmartNightIncludeFlatsAtEnd(_settings.includeFlatsAtEnd);
        await notifier.setSmartNightUseSchedulerForMultiTarget(
            _settings.useSchedulerForMultiTarget);
        await notifier.setSmartNightSchedulerTargetThreshold(
            _settings.schedulerTargetThreshold);
        await notifier.setSmartNightPolarAlignmentStaleAfterDays(
            _settings.polarAlignmentStaleAfterDays);
        await notifier
            .setSmartNightSubExposureFloorSecs(_settings.subExposureFloorSecs);
        await notifier.setSmartNightSubExposureCeilingSecs(
            _settings.subExposureCeilingSecs);
        await notifier.setSmartNightTargetSnr(_settings.targetSnr);
        await notifier
            .setSmartNightDefaultStrategy(_persistedNameForStrategy(_strategy));
      } catch (_) {
        // Persistence is a nice-to-have; surfacing this would be noisy.
      }
    }();
  }

  SmartNightService _buildService() {
    return SmartNightService(
      suggestionService: ref.read(targetSuggestionServiceProvider),
      logging: ref.read(loggingServiceProvider),
    );
  }

  void _onPrimaryPressed() async {
    switch (_step) {
      case 0:
        if (!_validateWindow()) return;
        setState(() => _step = 1);
        break;
      case 1:
        if (!_validateEquipment()) return;
        setState(() => _step = 2);
        break;
      case 2:
        if (!_validateTargets()) return;
        setState(() => _step = 3);
        break;
      case 3:
        if (!_validateStrategy()) return;
        await _buildPreview();
        if (mounted) setState(() => _step = 4);
        break;
      case 4:
        if (_preview == null) return;
        setState(() => _step = 5);
        break;
      case 5:
        await _startPlan();
        break;
    }
  }

  bool _validateWindow() {
    final start = _windowStart;
    final end = _windowEnd;
    if (start == null || end == null) {
      context.showErrorSnackBar(
        'Cannot determine tonight\'s window — set your latitude / '
        'longitude in Settings first.',
      );
      return false;
    }
    if (!end.isAfter(start)) {
      context.showErrorSnackBar(
        'Window end must be after window start.',
      );
      return false;
    }
    return true;
  }

  bool _validateEquipment() {
    final profile = ref.read(activeEquipmentProfileProvider);
    if (profile == null) {
      context.showErrorSnackBar(
        'No active equipment profile — select one on the Equipment '
        'screen first.',
      );
      return false;
    }
    if (profile.focalLength <= 0 && profile.telescopeFocalLength == null) {
      context.showErrorSnackBar(
        'Equipment profile is missing focal length — exposure '
        'recommendations need it.',
      );
      return false;
    }
    if (profile.aperture <= 0 && profile.telescopeAperture == null) {
      context.showErrorSnackBar(
        'Equipment profile is missing aperture — exposure '
        'recommendations need it.',
      );
      return false;
    }
    return true;
  }

  bool _validateTargets() {
    if (!_autoSelect && _selectedTargetIds.isEmpty) {
      context.showWarningSnackBar(
        'Pick at least one target, or switch to Auto-pick mode.',
      );
      return false;
    }
    return true;
  }

  bool _validateStrategy() {
    final profile = ref.read(activeEquipmentProfileProvider);
    final fits = _strategyFitsProfile(_strategy, profile);
    if (!fits) {
      context.showWarningSnackBar(
        'The selected strategy needs filters this profile doesn\'t '
        'have. Pick a different strategy or add filters to the profile.',
      );
      return false;
    }
    return true;
  }

  /// True if the selected strategy can find at least one usable filter
  /// in the active profile. We do a simple set intersection rather than
  /// reusing the service's internal helper because we want a synchronous
  /// validation before kicking the builder.
  bool _strategyFitsProfile(
    SmartNightStrategy strategy,
    EquipmentProfileModel? profile,
  ) {
    if (profile == null) return false;
    final names = profile.filterNames.map((n) => n.toLowerCase()).toSet();
    bool any(Iterable<String> wanted) => wanted.any(names.contains);
    switch (strategy) {
      case SmartNightStrategy.autoLrgb:
      case SmartNightStrategy.monoLrgb:
        return any({'l', 'lum', 'luminance', 'r', 'g', 'b'});
      case SmartNightStrategy.narrowbandHoo:
        return any({'ha', 'h-alpha', 'halpha'}) && any({'oiii', 'o3'});
      case SmartNightStrategy.narrowbandSho:
        return any({'ha', 'h-alpha', 'halpha'}) &&
            any({'oiii', 'o3'}) &&
            any({'sii', 's2'});
      case SmartNightStrategy.oscOneShot:
        // OSC works without a wheel — the service falls back to a
        // synthetic 'OSC' filter row.
        return true;
    }
  }

  Future<void> _buildPreview() async {
    setState(() {
      _preview = null;
      _previewError = null;
      _previewDraftId = null;
    });

    try {
      final profile = ref.read(activeEquipmentProfileProvider);
      if (profile == null) {
        setState(() => _previewError =
            'No active equipment profile — pick one on Equipment first.');
        return;
      }
      final location = ref.read(appObserverLocationProvider);
      if (location == null ||
          (location.latitude == 0.0 && location.longitude == 0.0)) {
        setState(() => _previewError =
            'No observer location set — configure latitude / longitude in '
                'Settings first.');
        return;
      }

      // Resolve the ranked candidate set; the service does NOT re-rank
      // when given a hand-picked list.
      final suggestions = ref.read(tonightSuggestionsProvider).valueOrNull;
      final ranked = suggestions ?? const [];
      List<TargetSuggestion> selected;
      if (_autoSelect) {
        selected = ranked.take(_autoSelectCount).toList();
      } else {
        selected = ranked
            .where((s) => _selectedTargetIds.contains(s.targetId))
            .toList();
        if (selected.isEmpty) {
          setState(() => _previewError =
              'No selected targets matched tonight\'s rankings. They may '
                  'be below the altitude / score cut-offs.');
          return;
        }
      }
      if (selected.isEmpty) {
        setState(() => _previewError =
            'No targets to plan with — saved targets list is empty or '
                'everything is below the altitude cut-off tonight.');
        return;
      }

      // Build the cross-system context. Weather forecast probability
      // and dark library coverage come from existing providers — we
      // resolve them best-effort and fall back to null when not
      // available.
      final settings = ref.read(appSettingsProvider).valueOrNull;
      final bortle = settings?.bortleClass ?? 5;
      final cloudCover = ref.read(cloudCoverPercentageProvider).valueOrNull;
      final cloudProb = cloudCover == null ? null : cloudCover / 100.0;

      // Polar alignment freshness (Wave 5).
      final lastPolarAlign =
          ref.read(lastPolarAlignmentProvider(profile.id)).valueOrNull;
      int? daysSinceLastPolar;
      if (lastPolarAlign != null) {
        daysSinceLastPolar =
            DateTime.now().difference(lastPolarAlign.completedAt).inDays;
      }

      final effectiveSettings = _settings.copyWith(
        hasCoverCalibrator:
            _settings.hasCoverCalibrator || profile.coverCalibratorId != null,
      );
      var exposureContext =
          await ref.read(smartNightExposureContextProvider.future);
      if (_shouldPromptForCameraSpecs(exposureContext)) {
        if (!mounted) return;
        final saved = await showDialog<bool>(
          context: this.context,
          builder: (_) => SmartNightMissingSpecsDialog(
            cameraName: profile.cameraName,
            defaultGain: profile.defaultGain,
            colors: NightshadeColors.dark,
          ),
        );
        if (saved == true) {
          ref.invalidate(smartNightExposureContextProvider);
          exposureContext =
              await ref.read(smartNightExposureContextProvider.future);
        }
      }

      final darkLibraryMissing = exposureContext == null
          ? const SmartNightDarkLibraryMissing.empty()
          : await SmartNightDarkLibraryCoverage(
              darkLibraryService: ref.read(darkLibraryServiceProvider),
            ).missing(
              profile: profile,
              strategy: _strategy,
              settings: effectiveSettings,
              exposureContext: exposureContext,
              minCoverage: settings?.darkLibraryMinCoverage ?? 10,
            );

      final context = SmartNightContext(
        windowStart: _windowStart!,
        windowEnd: _windowEnd!,
        rainOrCloudProbability: cloudProb,
        bortleClass: bortle,
        daysSinceLastPolarAlignment: daysSinceLastPolar,
        missingDarkLibraryNotes: darkLibraryMissing.notes,
        missingDarkRequirements: darkLibraryMissing.requirements,
      );

      final plan = _buildService().build(
        profile: profile,
        latitudeDeg: location.latitude,
        longitudeDeg: location.longitude,
        context: context,
        selectedSuggestions: selected,
        strategy: _strategy,
        settings: effectiveSettings,
        exposureContext: exposureContext,
      );
      final draft = await SmartNightDraftService(
        settingsDao: ref.read(settingsDaoProvider),
      ).savePending(
        profileId: profile.id.toString(),
        astronomicalDay: context.windowStart,
        plan: plan,
      );
      setState(() {
        _preview = plan;
        _previewDraftId = draft.id;
      });
    } on SmartNightBuildException catch (e) {
      setState(() => _previewError = e.message);
    } catch (e) {
      setState(() => _previewError = 'Unexpected error: $e');
    }
  }

  bool _shouldPromptForCameraSpecs(SmartNightExposureContext? context) {
    if (context == null) return false;
    return context.caveats.any((caveat) {
      final text = caveat.toLowerCase();
      return text.contains('camera read noise') ||
          text.contains('camera full well') ||
          text.contains('camera qe') ||
          text.contains('camera pixel size');
    });
  }

  Future<void> _adjustFilterCount(
    SmartNightPlannedTarget target,
    int filterIndex,
    int delta,
  ) async {
    final plan = _preview;
    if (plan == null) return;
    final newPlannedTargets = <SmartNightPlannedTarget>[];
    for (final p in plan.plannedTargets) {
      if (p == target) {
        final updatedFilters = <SmartNightFilterPlan>[];
        for (var i = 0; i < p.filterPlans.length; i++) {
          if (i == filterIndex) {
            final fp = p.filterPlans[i];
            final newCount = (fp.count + delta).clamp(1, 999).toInt();
            updatedFilters.add(SmartNightFilterPlan(
              filterName: fp.filterName,
              count: newCount,
              durationSecs: fp.durationSecs,
              recommendation: fp.recommendation,
            ));
          } else {
            updatedFilters.add(p.filterPlans[i]);
          }
        }
        final newIntegration = updatedFilters.fold<double>(
          0,
          (s, fp) => s + fp.integrationSecs,
        );
        newPlannedTargets.add(SmartNightPlannedTarget(
          suggestion: p.suggestion,
          windowStart: p.windowStart,
          windowEnd: p.windowEnd,
          filterPlans: updatedFilters,
          integrationSecs: newIntegration,
          rationale: p.rationale,
        ));
      } else {
        newPlannedTargets.add(p);
      }
    }

    // Mutating plan counts requires regenerating the underlying Sequence
    // so the per-target SmartExposureNode reflects the new counts. We
    // re-run the builder with hand-picked suggestions and current
    // settings; the same context + strategy + window stays.
    final profile = ref.read(activeEquipmentProfileProvider);
    final location = ref.read(appObserverLocationProvider);
    if (profile == null || location == null) return;
    try {
      final exposureContext =
          await ref.read(smartNightExposureContextProvider.future);
      final rebuilt = _buildService().build(
        profile: profile,
        latitudeDeg: location.latitude,
        longitudeDeg: location.longitude,
        context: plan.context,
        selectedSuggestions:
            newPlannedTargets.map((p) => p.suggestion).toList(growable: false),
        strategy: plan.strategy,
        // Inject the user's count tweaks via a custom settings clone
        // that scales the default-budget hour so the same per-filter
        // ratio reproduces the user's chosen counts. We can't pass the
        // counts directly because [build] composes the SmartExposure
        // plan internally; instead we override the duration / count
        // map by re-running with a per-target adjusted setting bag.
        settings: plan.settings,
        exposureContext: exposureContext,
      );
      // Replace per-target plans with the user-edited ones after the
      // rebuild so the wizard preview reflects exact user values.
      final patched = SmartNightPlan(
        sequence: _patchSequenceCounts(rebuilt.sequence, newPlannedTargets),
        plannedTargets: newPlannedTargets,
        totalIntegrationSecs: newPlannedTargets.fold<double>(
          0,
          (s, p) => s + p.integrationSecs,
        ),
        estimatedWallClockSecs: rebuilt.estimatedWallClockSecs,
        warnings: rebuilt.warnings,
        strategy: rebuilt.strategy,
        settings: rebuilt.settings,
        context: rebuilt.context,
      );
      final draft = await SmartNightDraftService(
        settingsDao: ref.read(settingsDaoProvider),
      ).savePending(
        profileId: profile.id.toString(),
        astronomicalDay: patched.context.windowStart,
        plan: patched,
      );
      if (!mounted) return;
      setState(() {
        _preview = patched;
        _previewDraftId = draft.id;
      });
    } catch (e) {
      // Don't show another error here — preview already validated the
      // sequence; surfacing a snackbar is enough.
      if (mounted) {
        context.showWarningSnackBar('Could not adjust counts: $e');
      }
    }
  }

  /// Walk every [SmartExposureNode] in `seq` and overwrite its
  /// per-filter counts with the user-tweaked values. We match by
  /// filter name within the same TargetHeader.
  Sequence _patchSequenceCounts(
    Sequence seq,
    List<SmartNightPlannedTarget> targets,
  ) {
    final byTargetName = <String, SmartNightPlannedTarget>{
      for (final t in targets) t.suggestion.targetName: t,
    };
    final newNodes = <String, SequenceNode>{...seq.nodes};
    for (final entry in seq.nodes.entries) {
      final node = entry.value;
      if (node is! SmartExposureNode) continue;
      // Walk up to find the parent TargetHeader to identify which
      // planned target this SmartExposure belongs to.
      String? parentId = node.parentId;
      String? targetName;
      while (parentId != null) {
        final parent = seq.nodes[parentId];
        if (parent is TargetHeaderNode) {
          targetName = parent.targetName;
          break;
        }
        parentId = parent?.parentId;
      }
      if (targetName == null) continue;
      final tweaked = byTargetName[targetName];
      if (tweaked == null) continue;
      final newPlans = <FilterPlan>[];
      for (final plan in node.plans) {
        final matchingTweak = tweaked.filterPlans.firstWhere(
          (fp) => fp.filterName == plan.filterName,
          orElse: () => SmartNightFilterPlan(
            filterName: plan.filterName,
            count: plan.count,
            durationSecs: plan.durationSecs,
          ),
        );
        newPlans.add(plan.copyWith(
          count: matchingTweak.count,
          durationSecs: matchingTweak.durationSecs,
        ));
      }
      newNodes[node.id] = node.copyWith(
        plans: newPlans,
        integrationBudgetSecs: tweaked.integrationSecs,
      );
    }
    return seq.copyWith(nodes: newNodes);
  }

  Future<void> _startPlan() async {
    final plan = _preview;
    if (plan == null) return;
    try {
      await const SmartNightPlanLauncher().launch(
        read: ref.read,
        plan: plan,
        draftId: _previewDraftId,
      );
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not start Smart Night sequence: $e');
      }
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    GoRouter.maybeOf(context)?.go('/imaging');
    context.showSuccessSnackBar(
      'Smart Night plan loaded — '
      '${plan.plannedTargets.length} target(s), '
      '${(plan.totalIntegrationSecs / 3600).toStringAsFixed(1)}h integration.',
    );
  }

  Future<void> _pickDateTime({
    required DateTime initial,
    required void Function(DateTime) onPicked,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: initial.subtract(const Duration(days: 1)),
      lastDate: initial.add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    onPicked(DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ));
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }
}

// =====================================================================
// Inline widgets
// =====================================================================

class _StepChip extends StatelessWidget {
  final String label;
  final NightshadeColors colors;
  final bool isActive;
  final bool isComplete;

  const _StepChip({
    required this.label,
    required this.colors,
    required this.isActive,
    required this.isComplete,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isActive
        ? colors.primary
        : (isComplete ? colors.surfaceAlt : Colors.transparent);
    final fg = isActive
        ? colors.onPrimary
        : (isComplete ? colors.textPrimary : colors.textSecondary);
    final border = isActive ? colors.primary : colors.border;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget child;
  final NightshadeColors colors;

  const _SettingsRow({
    required this.label,
    required this.child,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
              width: 140,
              child: Align(
                alignment: Alignment.centerRight,
                child: child,
              )),
        ],
      ),
    );
  }
}

class _CompactNumberField extends StatefulWidget {
  final double initial;
  final String suffix;
  final void Function(double) onChanged;

  const _CompactNumberField({
    required this.initial,
    required this.suffix,
    required this.onChanged,
  });

  @override
  State<_CompactNumberField> createState() => _CompactNumberFieldState();
}

class _CompactNumberFieldState extends State<_CompactNumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial.toStringAsFixed(0));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.right,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            onSubmitted: (text) {
              final v = double.tryParse(text.trim());
              if (v != null) widget.onChanged(v);
            },
            onEditingComplete: () {
              final v = double.tryParse(_controller.text.trim());
              if (v != null) widget.onChanged(v);
            },
          ),
        ),
        if (widget.suffix.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            widget.suffix,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _MissingLocationCard extends StatelessWidget {
  final NightshadeColors colors;
  const _MissingLocationCard({required this.colors});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: NightshadeDecorations.emphasisSurface(
        colors.warning,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.mapPin, color: colors.warning, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No observer location set — open Settings → Location and '
              'enter your latitude / longitude. Smart Night needs them to '
              'compute the dark window.',
              style: TextStyle(color: colors.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingProfileCard extends StatelessWidget {
  final NightshadeColors colors;
  const _MissingProfileCard({required this.colors});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.alertTriangle, size: 32, color: colors.error),
            const SizedBox(height: 10),
            Text(
              'No active equipment profile',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Open the Equipment screen and activate a profile before '
              'running Smart Night.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTargetsCard extends StatelessWidget {
  final NightshadeColors colors;
  const _EmptyTargetsCard({required this.colors});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.search, size: 28, color: colors.textMuted),
            const SizedBox(height: 8),
            Text(
              'No saved targets scored above the cut-off tonight',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add targets in the Targets tab or lower the min-altitude / '
              'min-score knobs in suggestion settings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: colors.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StrategyTile extends StatelessWidget {
  final SmartNightStrategy strategy;
  final bool isSelected;
  final bool filtersAvailable;
  final VoidCallback onSelected;
  final NightshadeColors colors;

  const _StrategyTile({
    required this.strategy,
    required this.isSelected,
    required this.filtersAvailable,
    required this.onSelected,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final descriptors = _descriptors(strategy);
    return InkWell(
      onTap: filtersAvailable ? onSelected : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius: BorderRadius.circular(8),
                ).color
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 18,
              color: isSelected ? colors.primary : colors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    descriptors.title,
                    style: TextStyle(
                      color: filtersAvailable
                          ? colors.textPrimary
                          : colors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descriptors.subtitle,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (!filtersAvailable)
              Tooltip(
                message: 'Needs filters this profile doesn\'t have',
                child: Icon(LucideIcons.alertTriangle,
                    size: 14, color: colors.warning),
              ),
          ],
        ),
      ),
    );
  }

  ({String title, String subtitle}) _descriptors(SmartNightStrategy s) {
    switch (s) {
      case SmartNightStrategy.autoLrgb:
        return (
          title: 'Auto-balance LRGB',
          subtitle: 'L weighted 2x R/G/B; default for broadband nights.',
        );
      case SmartNightStrategy.monoLrgb:
        return (
          title: 'Mono LRGB (even)',
          subtitle: 'Equal time per L/R/G/B; classic mono workflow.',
        );
      case SmartNightStrategy.narrowbandHoo:
        return (
          title: 'Narrowband HOO',
          subtitle: 'Ha + OIII bicolor — emission nebulae, bright-moon nights.',
        );
      case SmartNightStrategy.narrowbandSho:
        return (
          title: 'Narrowband SHO (Hubble)',
          subtitle: 'Ha + OIII + SII tricolor.',
        );
      case SmartNightStrategy.oscOneShot:
        return (
          title: 'OSC One-Shot',
          subtitle: 'Single light filter — Bayer cameras and L-eXtreme.',
        );
    }
  }
}

class _AfCadenceSelector extends StatelessWidget {
  final SmartNightSettings value;
  final void Function(SmartNightSettings) onChanged;
  final NightshadeColors colors;

  const _AfCadenceSelector({
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final c in SmartNightAfCadence.values)
          ChoiceChip(
            label: Text(_labelFor(c)),
            selected: value.afCadence == c,
            onSelected: (_) => onChanged(value.copyWith(afCadence: c)),
          ),
      ],
    );
  }

  String _labelFor(SmartNightAfCadence c) {
    switch (c) {
      case SmartNightAfCadence.everyNFrames:
        return 'Every ${value.afEveryFrames} frames';
      case SmartNightAfCadence.everyNMinutes:
        return 'Every ${value.afEveryMinutes} min';
      case SmartNightAfCadence.onTempDelta:
        return 'On Δ${value.afTempDeltaC.toStringAsFixed(1)}°C';
    }
  }
}

class _TargetTile extends StatelessWidget {
  final TargetSuggestion suggestion;
  final bool isSelected;
  final bool isAutoMode;
  final int rank;
  final bool autoPickedTop;
  final VoidCallback onToggle;
  final NightshadeColors colors;

  const _TargetTile({
    required this.suggestion,
    required this.isSelected,
    required this.isAutoMode,
    required this.rank,
    required this.autoPickedTop,
    required this.onToggle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final autoBorder = (isAutoMode && autoPickedTop);
    return InkWell(
      onTap: isAutoMode ? null : onToggle,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? NightshadeDecorations.tintedBadge(
                  colors.primary,
                  borderRadius: BorderRadius.circular(8),
                ).color
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: autoBorder
                ? colors.primary
                : (isSelected ? colors.primary : colors.border),
          ),
        ),
        child: Row(
          children: [
            if (!isAutoMode)
              NightshadeCheckbox(
                value: isSelected,
                onChanged: (_) => onToggle(),
              ),
            Container(
              width: 32,
              alignment: Alignment.center,
              child: Text(
                '#$rank',
                style: TextStyle(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.targetName,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    suggestion.reasoning.isEmpty
                        ? '${suggestion.objectType ?? "target"} · '
                            'score ${suggestion.totalScore.toStringAsFixed(0)}'
                        : suggestion.reasoning,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: NightshadeDecorations.emphasisSurface(
                colors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${suggestion.totalScore.toStringAsFixed(0)}/100',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  final SmartNightPlan plan;

  const _PlanSummary({required this.plan});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Tonight: ${plan.plannedTargets.length} target(s), '
              '${(plan.totalIntegrationSecs / 3600).toStringAsFixed(1)}h '
              'integration',
          subtitle: 'Estimated wall-clock: '
              '${(plan.estimatedWallClockSecs / 3600).toStringAsFixed(1)}h '
              '(includes slews, AF, dither, downloads).',
        ),
      ],
    );
  }
}

class _PlannedTargetCard extends StatelessWidget {
  final SmartNightPlannedTarget planned;
  final NightshadeColors colors;
  final void Function(int filterIndex, int delta) onCountChanged;

  const _PlannedTargetCard({
    required this.planned,
    required this.colors,
    required this.onCountChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              Icon(LucideIcons.target, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  planned.suggestion.targetName,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${planned.suggestion.totalScore.toStringAsFixed(0)}/100',
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            planned.rationale,
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 8),
          _WindowBar(
            start: planned.windowStart,
            end: planned.windowEnd,
            colors: colors,
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < planned.filterPlans.length; i++)
            _FilterRow(
              plan: planned.filterPlans[i],
              colors: colors,
              onAdjust: (delta) => onCountChanged(i, delta),
            ),
          if (planned.filterPlans.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Total: '
                '${(planned.integrationSecs / 3600).toStringAsFixed(1)}h '
                'across ${planned.filterPlans.length} filter(s).',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final SmartNightFilterPlan plan;
  final NightshadeColors colors;
  final void Function(int delta) onAdjust;

  const _FilterRow({
    required this.plan,
    required this.colors,
    required this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    final integrationMins = plan.integrationSecs / 60;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: NightshadeDecorations.tintedBadge(
              colors.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              plan.filterName,
              style: TextStyle(
                color: colors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(LucideIcons.minus, size: 14),
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove one frame',
            onPressed: () => onAdjust(-1),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '${plan.count} × ${plan.durationSecs.toStringAsFixed(0)}s',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus, size: 14),
            visualDensity: VisualDensity.compact,
            tooltip: 'Add one frame',
            onPressed: () => onAdjust(1),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${integrationMins.toStringAsFixed(0)} min '
              '${plan.recommendation == null ? "" : "· ${plan.recommendation!.rationale}"}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowBar extends StatelessWidget {
  final DateTime start;
  final DateTime end;
  final NightshadeColors colors;

  const _WindowBar({
    required this.start,
    required this.end,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final mins = end.difference(start).inMinutes;
    return Row(
      children: [
        Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Text(
          '${_format(start)} → ${_format(end)} '
          '(${(mins / 60).toStringAsFixed(1)}h)',
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  String _format(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: colors.textMuted),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class SmartNightMissingSpecsDialog extends ConsumerStatefulWidget {
  final String? cameraName;
  final int? defaultGain;
  final NightshadeColors colors;

  const SmartNightMissingSpecsDialog({
    super.key,
    required this.colors,
    this.cameraName,
    this.defaultGain,
  });

  @override
  ConsumerState<SmartNightMissingSpecsDialog> createState() =>
      _SmartNightMissingSpecsDialogState();
}

class _SmartNightMissingSpecsDialogState
    extends ConsumerState<SmartNightMissingSpecsDialog> {
  late final TextEditingController _modelController;
  late final TextEditingController _gainController;
  final _pixelSizeController = TextEditingController();
  final _readNoiseController = TextEditingController();
  final _fullWellController = TextEditingController();
  final _qeController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(
      text: widget.cameraName?.trim().isNotEmpty == true
          ? widget.cameraName!.trim()
          : '',
    );
    _gainController = TextEditingController(
      text: (widget.defaultGain ?? 100).toString(),
    );
  }

  @override
  void dispose() {
    _modelController.dispose();
    _gainController.dispose();
    _pixelSizeController.dispose();
    _readNoiseController.dispose();
    _fullWellController.dispose();
    _qeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Camera specs needed',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 460,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Smart Night can make better exposure recommendations with the camera values below.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _specField(
                controller: _modelController,
                label: 'Camera model',
                keyName: 'smart-night-spec-model',
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _gainController,
                label: 'Gain',
                keyName: 'smart-night-spec-gain',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _pixelSizeController,
                label: 'Pixel size (microns)',
                keyName: 'smart-night-spec-pixel-size',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _readNoiseController,
                label: 'Read noise (e-)',
                keyName: 'smart-night-spec-read-noise',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _fullWellController,
                label: 'Full well (e-)',
                keyName: 'smart-night-spec-full-well',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              _specField(
                controller: _qeController,
                label: 'QE peak (0-1)',
                keyName: 'smart-night-spec-qe',
                keyboardType: TextInputType.number,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save specs'),
        ),
      ],
    );
  }

  Widget _specField({
    required TextEditingController controller,
    required String label,
    required String keyName,
    TextInputType? keyboardType,
  }) {
    return TextField(
      key: Key(keyName),
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> _save() async {
    final model = _modelController.text.trim();
    final gain = int.tryParse(_gainController.text.trim());
    final pixelSize = double.tryParse(_pixelSizeController.text.trim());
    final readNoise = double.tryParse(_readNoiseController.text.trim());
    final fullWell = double.tryParse(_fullWellController.text.trim());
    final qe = double.tryParse(_qeController.text.trim());

    if (model.isEmpty ||
        gain == null ||
        pixelSize == null ||
        pixelSize <= 0 ||
        readNoise == null ||
        readNoise <= 0 ||
        fullWell == null ||
        fullWell <= 0 ||
        qe == null ||
        qe <= 0 ||
        qe > 1) {
      setState(() {
        _error =
            'Enter a model plus positive gain, pixel size, read noise, full well, and QE between 0 and 1.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final dao = ref.read(settingsDaoProvider);
      final raw =
          await dao.getSetting(HardwareSpecsService.cameraOverridesSettingKey);
      final existing = raw == null || raw.trim().isEmpty
          ? <CameraHardwareSpec>[]
          : HardwareSpecsService.cameraOverridesFromJson(jsonDecode(raw))
              .toList();
      final alias = widget.cameraName?.trim();
      final spec = CameraHardwareSpec(
        model: model,
        aliases: alias == null ||
                alias.isEmpty ||
                alias.toLowerCase() == model.toLowerCase()
            ? const []
            : [alias],
        pixelSizeMicrons: pixelSize,
        qePeak: qe,
        defaultGain: gain,
        gainPoints: [
          CameraGainPoint(
            gain: gain,
            readNoiseE: readNoise,
            fullWellE: fullWell,
          ),
        ],
      );
      existing.removeWhere(
        (entry) => entry.model.toLowerCase() == model.toLowerCase(),
      );
      existing.add(spec);
      await dao.setSetting(
        HardwareSpecsService.cameraOverridesSettingKey,
        jsonEncode(existing.map((entry) => entry.toJson()).toList()),
      );
      ref.invalidate(smartNightExposureContextProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save camera specs: $e';
      });
    }
  }
}

// =====================================================================
// Safety & Watchdogs preview section
// =====================================================================

/// A single parallel-watchdog callout surfaced in the plan preview.
///
/// These describe triggers the executor installs as siblings of the
/// imaging branch — they run in parallel and fire by hour-angle / sensor
/// state, not by list position. Surfacing them in the preview keeps the
/// user's mental model honest: a meridian flip or a weather-park can
/// interrupt the run at any point, regardless of where the target sits in
/// the sequence.
@immutable
class SmartNightWatchdog {
  const SmartNightWatchdog({required this.title, required this.detail});

  /// Short bold lead-in, e.g. "Meridian flip".
  final String title;

  /// Sentence explaining when/how it fires.
  final String detail;
}

/// Derives the parallel-watchdog callouts a [SmartNightPlan] installs,
/// purely from data already present on the plan.
///
/// The injection decisions are NOT re-implemented here — they delegate to
/// the authoritative predicates on [SmartNightService]
/// ([SmartNightService.willInjectMeridianFlip] and
/// [SmartNightService.willInjectWeatherRecovery]), which the builder
/// (`SmartNightService.build`) calls at the actual emit sites. That shared
/// source of truth is what guarantees the preview never claims a watchdog
/// the emitted sequence won't contain (and vice-versa): tuning the cloud
/// threshold or the meridian boundary in the service automatically moves
/// the preview with it.
///
/// Returned in install order (meridian flip, then weather recovery).
List<SmartNightWatchdog> smartNightWatchdogsFor(SmartNightPlan plan) {
  final watchdogs = <SmartNightWatchdog>[];

  final transitingCount = plan.plannedTargets
      .where(SmartNightService.willInjectMeridianFlip)
      .length;

  if (transitingCount > 0) {
    final plural = transitingCount == 1 ? 'target crosses' : 'targets cross';
    watchdogs.add(SmartNightWatchdog(
      title: 'Meridian flip',
      detail: 'Runs in parallel and fires the moment a target reaches the '
          'meridian (by hour-angle, not list position). $transitingCount '
          '$plural the meridian inside their imaging window tonight; the '
          'mount flips, re-centers, refocuses, and resumes guiding '
          'automatically.',
    ));
  }

  if (SmartNightService.willInjectWeatherRecovery(plan.context)) {
    final cloudProb = plan.context.rainOrCloudProbability!;
    final leadMinutes = plan.context.cloudArrivalLeadTimeMinutes;
    watchdogs.add(SmartNightWatchdog(
      title: 'Weather recovery',
      detail: 'Runs in parallel as a weather-unsafe watchdog. If cloud or '
          'rain arrives (forecast '
          '${(cloudProb * 100).toStringAsFixed(0)}% within $leadMinutes min) '
          'it parks the mount and aborts the run, no matter which target is '
          'imaging.',
    ));
  }

  return watchdogs;
}

/// Renders the "Safety & Watchdogs" block in the plan preview.
///
/// Explains the parallel triggers the plan installs so users understand
/// they fire regardless of where a target sits in the list. Renders
/// nothing when the plan installs no watchdogs (keeps the preview clean
/// for short single-target plans that never cross the meridian and have
/// no weather risk). Distinct from the Warnings block — these are
/// informational descriptions of always-on safety automation, not
/// problems with the plan.
class SmartNightSafetyWatchdogsSection extends StatelessWidget {
  const SmartNightSafetyWatchdogsSection({
    super.key,
    required this.plan,
    required this.colors,
  });

  final SmartNightPlan plan;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    final watchdogs = smartNightWatchdogsFor(plan);
    if (watchdogs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Safety & Watchdogs',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'These run in parallel with the imaging branch and fire by '
          'condition, not by list position.',
          style: TextStyle(
            fontSize: 11,
            color: colors.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        for (final w in watchdogs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  LucideIcons.shieldAlert,
                  size: 14,
                  color: colors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${w.title} — ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                        TextSpan(
                          text: w.detail,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
