import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../services/smart_night_plan_launcher.dart';
import '../../../utils/authority_bound_dialog.dart';
import '../../../utils/snackbar_helper.dart';
import '../../equipment/dialogs/profile_editor_dialog.dart';

part 'smart_night_dialog/inline_widgets.dart';
part 'smart_night_dialog/missing_specs_dialog.dart';
part 'smart_night_dialog/safety_watchdogs.dart';
part 'smart_night_dialog/step_views.dart';

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
  const SmartNightDialog({
    super.key,
    this.seedTargetIds,
    this.seedSourceLabel,
  });

  /// Optional set of target ids to pre-select on the Targets step (component
  /// C11 — Smart Night handoff from an active project). When provided and
  /// non-empty the wizard opens in hand-pick mode with exactly these targets
  /// selected, so an operator can one-click feed a campaign's still-incomplete
  /// targets into the planner instead of getting the generic "best of
  /// everything tonight" set. A given id only takes effect if it survives
  /// tonight's altitude/score cut-offs (the suggestion ranking is the source of
  /// truth for whether a target is imageable tonight); ids that don't appear in
  /// the ranking are surfaced honestly on the Targets step rather than silently
  /// dropped.
  final List<int>? seedTargetIds;

  /// Human-readable description of where [seedTargetIds] came from (e.g. the
  /// project name), shown as a banner on the Targets step. Null when the wizard
  /// was opened without a seed.
  final String? seedSourceLabel;

  @override
  ConsumerState<SmartNightDialog> createState() => _SmartNightDialogState();
}

/// Canonical entry point for the Smart Night "Plan Tonight" wizard.
///
/// Every "Plan Tonight" affordance across the app (dashboard, sequencer
/// toolbar, planner Projects tab, cockpit standby) funnels through this single
/// launcher so the flow, dialog, and behaviour can never drift between
/// entrances. Optional [seedTargetIds] / [seedSourceLabel] feed a campaign's
/// targets into the wizard (used by the Projects tab handoff); omit them for
/// the generic "best of tonight" plan.
Future<void> showSmartNightDialog(
  BuildContext context, {
  List<int>? seedTargetIds,
  String? seedSourceLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SmartNightDialog(
      seedTargetIds: seedTargetIds,
      seedSourceLabel: seedSourceLabel,
    ),
  );
}

class _SmartNightDialogState extends ConsumerState<SmartNightDialog> {
  int _step = 0;

  // ---- Step 1: window ---------------------------------------------------
  DateTime? _windowStart;
  DateTime? _windowEnd;
  bool _windowInitialised = false;
  String? _windowError;

  /// The computed astronomical-twilight (dark) window, cached on
  /// initialisation so [_validateWindow] can warn when the user narrows their
  /// imaging window wholly outside the dark hours (e.g. into daylight).
  DateTime? _twilightStart;
  DateTime? _twilightEnd;

  // ---- Step 3: targets --------------------------------------------------
  /// User-selected target IDs. Empty → auto-pick top N by score.
  final Set<int> _selectedTargetIds = <int>{};
  bool _autoSelect = true;
  int _autoSelectCount = 2;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  int _authorityGeneration = 0;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        _authorityGeneration++;
        _countDraftDebounce?.cancel();
        closeAuthorityBoundDialog(context);
      },
    );
    // C11 handoff: when the dialog is opened seeded from an active project,
    // start in hand-pick mode with the project's incomplete targets selected.
    final seed = widget.seedTargetIds;
    if (seed != null && seed.isNotEmpty) {
      _autoSelect = false;
      _selectedTargetIds.addAll(seed);
    }
  }

  void _update(VoidCallback callback) => setState(callback);

  @override
  void dispose() {
    _backendSubscription?.close();
    _countDraftDebounce?.cancel();
    super.dispose();
  }

  bool _isCurrentAuthority(NightshadeBackend backend, int generation) =>
      mounted &&
      generation == _authorityGeneration &&
      identical(ref.read(backendProvider), backend);

  // ---- Step 4: strategy -------------------------------------------------
  SmartNightStrategy _strategy = SmartNightStrategy.autoLrgb;

  // ---- Step 5: preview --------------------------------------------------
  SmartNightPlan? _preview;
  String? _previewError;
  String? _previewDraftId;

  /// True while the (heavy) plan builder is running. Drives the primary
  /// button's busy/disabled state and guards [_onPrimaryPressed] against
  /// re-entry.
  bool _isBuildingPreview = false;

  /// True while the final plan is being launched (or saved as a template).
  /// Guards the terminal Start Sequence / Save-as-template actions against a
  /// double-tap re-entering the launcher before the dialog closes.
  bool _isStarting = false;

  /// Debounce timer for persisting count-tweak drafts. Each +/- tap patches
  /// the plan locally and immediately; the DB draft write is coalesced so a
  /// rapid burst of taps only persists the final count.
  Timer? _countDraftDebounce;

  // ---- Settings (defaults; wizard can override) ------------------------
  /// Local working copy of the wizard's [SmartNightSettings]. Seeded from
  /// the persisted defaults in [AppSettingsState] on first build; user
  /// changes are written back to settings so the next session pre-fills
  /// with the user's preferences.
  SmartNightSettings _settings = const SmartNightSettings();
  bool _settingsSeededFromAppSettings = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final appSettingsAsync = ref.watch(appSettingsProvider);
    if (appSettingsAsync.hasError) {
      return _buildSettingsGate(
        colors: colors,
        error: appSettingsAsync.error,
      );
    }
    final appSettings = appSettingsAsync.valueOrNull;
    if (appSettings == null) {
      return _buildSettingsGate(colors: colors);
    }
    _ensureSettingsSeeded(appSettings);
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

  Widget _buildSettingsGate({
    required NightshadeColors colors,
    Object? error,
  }) {
    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 560,
      designHeight: 300,
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.sparkles, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Smart Night — Plan Tonight',
                      style: NightshadeTypography.h4
                          .copyWith(color: colors.textPrimary),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const Spacer(),
              if (error == null) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 14),
                Text(
                  'Loading Smart Night settings…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.textSecondary),
                ),
              ] else ...[
                Icon(
                  LucideIcons.alertTriangle,
                  size: 30,
                  color: colors.error,
                ),
                const SizedBox(height: 10),
                Text(
                  'Cannot load Smart Night settings',
                  textAlign: TextAlign.center,
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  '$error',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary),
                ),
                const SizedBox(height: 12),
                Center(
                  child: NightshadeButton(
                    label: 'Retry',
                    icon: LucideIcons.refreshCw,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: () => ref.invalidate(appSettingsProvider),
                  ),
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Header / stepper / footer
  // ---------------------------------------------------------------------

  void _ensureWindowInitialised() {
    if (_windowInitialised) return;
    final location = ref.read(appObserverLocationProvider);
    if (location == null) {
      _windowInitialised = true;
      return;
    }
    try {
      final window = _buildService().calculateWindow(
        latitudeDeg: location.latitude,
        longitudeDeg: location.longitude,
      );
      _windowStart = window.start;
      _windowEnd = window.end;
      _twilightStart = window.start;
      _twilightEnd = window.end;
    } on SmartNightBuildException catch (error) {
      _windowError = error.message;
    }
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
  void _ensureSettingsSeeded(AppSettingsState app) {
    if (_settingsSeededFromAppSettings) return;
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
    final seed = widget.seedTargetIds;
    if (seed == null || seed.isEmpty) {
      _autoSelect = app.smartNightAutoSelect;
      _autoSelectCount = app.smartNightAutoSelectCount.clamp(1, 10);
    }
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
        await notifier.updateSmartNightWizardDefaults(
          maxSessionHours: _settings.maxSessionHours,
          afCadenceFrames: _settings.afEveryFrames,
          integrationBudgetMinsPerTarget:
              (_settings.defaultIntegrationBudgetHours * 60).round(),
          includeFlatsAtEnd: _settings.includeFlatsAtEnd,
          useSchedulerForMultiTarget: _settings.useSchedulerForMultiTarget,
          schedulerTargetThreshold: _settings.schedulerTargetThreshold,
          polarAlignmentStaleAfterDays: _settings.polarAlignmentStaleAfterDays,
          subExposureFloorSecs: _settings.subExposureFloorSecs,
          subExposureCeilingSecs: _settings.subExposureCeilingSecs,
          targetSnr: _settings.targetSnr,
          strategy: _persistedNameForStrategy(_strategy),
          autoSelect: _autoSelect,
          autoSelectCount: _autoSelectCount,
        );
      } catch (error, stack) {
        ref.read(loggingServiceProvider).warning(
              'Could not persist Smart Night wizard defaults: $error\n$stack',
              source: 'SmartNightDialog',
            );
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
    // Guard re-entry: the strategy step kicks off the heavy builder and
    // disables the primary button, but a double-tap could still slip through
    // before the rebuild lands.
    if (_isBuildingPreview || _isStarting) return;
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
        setState(() => _isBuildingPreview = true);
        try {
          final completed = await _buildPreview();
          if (mounted && completed) setState(() => _step = 4);
        } finally {
          if (mounted) setState(() => _isBuildingPreview = false);
        }
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
        _windowError ??
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
    // Non-blocking twilight sanity check: if the user has narrowed the window
    // so it no longer overlaps tonight's astronomical-dark window at all, the
    // plan will be all-daylight/twilight. Warn up front rather than letting
    // the preview silently produce an unusable plan. We still let them
    // proceed — civil-twilight wide-field / solar-system work is legitimate.
    final twiStart = _twilightStart;
    final twiEnd = _twilightEnd;
    if (twiStart != null && twiEnd != null) {
      final overlaps = start.isBefore(twiEnd) && end.isAfter(twiStart);
      if (!overlaps) {
        context.showWarningSnackBar(
          'Your chosen window falls outside tonight\'s dark window '
          '(${_formatDateTime(twiStart)} – ${_formatDateTime(twiEnd)}). '
          'Exposures will be in twilight or daylight.',
        );
      }
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
    final suggestionsAsync = ref.read(tonightSuggestionsProvider);
    if (suggestionsAsync.hasError) {
      context.showErrorSnackBar(
        'Could not load target suggestions: ${suggestionsAsync.error}',
      );
      return false;
    }
    final suggestions = suggestionsAsync.valueOrNull;
    if (suggestions == null) {
      context.showInfoSnackBar('Target suggestions are still loading.');
      return false;
    }
    if (suggestions.isEmpty) {
      context.showWarningSnackBar(
        'No targets meet tonight\'s altitude and score cut-offs.',
      );
      return false;
    }
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
        // OSC works without a wheel — the service plans a single unfiltered
        // row and emits an ExposureNode with no filter selection.
        return true;
    }
  }

  /// Returns false only when the dialog's rig authority was invalidated.
  /// Ordinary build failures return true after populating [_previewError] so
  /// the Preview step can show its actionable error and Back affordance.
  Future<bool> _buildPreview() async {
    final backend = ref.read(backendProvider);
    final generation = _authorityGeneration;
    setState(() {
      _preview = null;
      _previewError = null;
      _previewDraftId = null;
    });

    try {
      var profile = ref.read(activeEquipmentProfileProvider);
      if (profile == null) {
        final profilesState = await ref.read(equipmentProfilesProvider.future);
        profile = profilesState.activeProfile;
      }
      if (profile == null) {
        setState(() => _previewError =
            'No active equipment profile — pick one on Equipment first.');
        return true;
      }
      final activeProfile = profile;
      final location = ref.read(appObserverLocationProvider);
      if (location == null ||
          (location.latitude == 0.0 && location.longitude == 0.0)) {
        setState(() => _previewError =
            'No observer location set — configure latitude / longitude in '
                'Settings first.');
        return true;
      }

      // Resolve the ranked candidate set; the service does NOT re-rank
      // when given a hand-picked list.
      final ranked = await ref.read(tonightSuggestionsProvider.future);
      if (!_isCurrentAuthority(backend, generation)) return false;
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
          return true;
        }
      }
      if (selected.isEmpty) {
        setState(() => _previewError =
            'No targets to plan with — saved targets list is empty or '
                'everything is below the altitude cut-off tonight.');
        return true;
      }

      // Build the cross-system context. Weather forecast probability
      // and dark library coverage come from existing providers — we
      // resolve them best-effort and fall back to null when not
      // available.
      final settings = await ref.read(appSettingsProvider.future);
      if (!_isCurrentAuthority(backend, generation)) return false;
      final bortle = settings.bortleClass;
      final cloudCover = ref.read(cloudCoverPercentageProvider).valueOrNull;
      final cloudProb = cloudCover == null ? null : cloudCover / 100.0;

      // Polar alignment freshness.
      final lastPolarAlign =
          ref.read(lastPolarAlignmentProvider(activeProfile.id)).valueOrNull;
      int? daysSinceLastPolar;
      if (lastPolarAlign != null) {
        daysSinceLastPolar =
            DateTime.now().difference(lastPolarAlign.completedAt).inDays;
      }

      final effectiveSettings = _settings.copyWith(
        hasCoverCalibrator: _settings.hasCoverCalibrator ||
            activeProfile.coverCalibratorId != null,
      );
      var exposureContext =
          await ref.read(smartNightExposureContextProvider.future);
      if (!_isCurrentAuthority(backend, generation)) return false;
      if (_shouldPromptForCameraSpecs(exposureContext)) {
        if (!mounted || !_isCurrentAuthority(backend, generation)) return false;
        final saved = await showDialog<bool>(
          context: this.context,
          builder: (_) => SmartNightMissingSpecsDialog(
            cameraName: activeProfile.cameraName,
            defaultGain: activeProfile.defaultGain,
            colors: NightshadeColors.dark,
          ),
        );
        if (!_isCurrentAuthority(backend, generation)) return false;
        if (saved == true) {
          ref.invalidate(smartNightExposureContextProvider);
          exposureContext =
              await ref.read(smartNightExposureContextProvider.future);
          if (!_isCurrentAuthority(backend, generation)) return false;
        }
      }

      // On a remote client the local dark library is the tablet's — empty —
      // not the rig's. Evaluating coverage against it would falsely report
      // every dark as missing and, with auto-schedule enabled, waste rig time
      // re-capturing darks the appliance already has. The rig owns its
      // calibration library, so skip the meaningless local computation here
      // (the plan's exposures/timing/targets come from synced settings +
      // profile and are unaffected). Browse the rig's darks via the
      // Calibration Library screen instead.
      final isRemoteBackend = ref.read(backendProvider) is NetworkBackend;
      final SmartNightDarkLibraryMissing darkLibraryMissing;
      if (exposureContext == null || isRemoteBackend) {
        darkLibraryMissing = const SmartNightDarkLibraryMissing.empty();
      } else {
        darkLibraryMissing = await SmartNightDarkLibraryCoverage(
          darkLibraryService: ref.read(darkLibraryServiceProvider),
        ).missing(
          profile: activeProfile,
          strategy: _strategy,
          settings: effectiveSettings,
          exposureContext: exposureContext,
          minCoverage: settings.darkLibraryMinCoverage,
        );
        if (!_isCurrentAuthority(backend, generation)) return false;
      }

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
        profile: activeProfile,
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
        profileId: activeProfile.id.toString(),
        astronomicalDay: context.windowStart,
        plan: plan,
      );
      if (!_isCurrentAuthority(backend, generation)) return false;
      setState(() {
        _preview = plan;
        _previewDraftId = draft.id;
      });
      return true;
    } on SmartNightBuildException catch (e) {
      if (!_isCurrentAuthority(backend, generation)) return false;
      setState(() => _previewError = e.message);
      return true;
    } catch (e) {
      if (!_isCurrentAuthority(backend, generation)) return false;
      setState(() => _previewError = 'Unexpected error: $e');
      return true;
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

  void _adjustFilterCount(
    SmartNightPlannedTarget target,
    int filterIndex,
    int delta,
  ) {
    final plan = _preview;
    if (plan == null) return;

    // Capture-time delta in seconds for this single edit. Wall-clock is
    // capture time plus a fixed per-target/per-filter overhead model the
    // builder applies; that overhead does not change when only a frame count
    // changes, so we can adjust wall-clock by the same capture delta rather
    // than re-running the (heavy) builder for every tap.
    var wallClockDeltaSecs = 0.0;

    final newPlannedTargets = <SmartNightPlannedTarget>[];
    for (final p in plan.plannedTargets) {
      if (p == target) {
        final updatedFilters = <SmartNightFilterPlan>[];
        for (var i = 0; i < p.filterPlans.length; i++) {
          if (i == filterIndex) {
            final fp = p.filterPlans[i];
            final newCount = (fp.count + delta).clamp(1, 999).toInt();
            wallClockDeltaSecs += (newCount - fp.count) * fp.durationSecs;
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

    // Patch the existing plan's sequence in place — no full rebuild. The
    // SmartExposureNode counts/integration are overwritten directly, and we
    // recompute totals + wall-clock locally so the preview is internally
    // consistent (no longer borrowing wall-clock from a rebuild that used the
    // un-tweaked counts).
    final patched = SmartNightPlan(
      sequence: _patchSequenceCounts(plan.sequence, newPlannedTargets),
      plannedTargets: newPlannedTargets,
      totalIntegrationSecs: newPlannedTargets.fold<double>(
        0,
        (s, p) => s + p.integrationSecs,
      ),
      estimatedWallClockSecs: (plan.estimatedWallClockSecs + wallClockDeltaSecs)
          .clamp(0, double.infinity),
      warnings: plan.warnings,
      strategy: plan.strategy,
      settings: plan.settings,
      context: plan.context,
    );

    setState(() => _preview = patched);

    // Debounce the durable draft write so a burst of +/- taps only persists
    // the final count, not one row per tap.
    final profile = ref.read(activeEquipmentProfileProvider);
    if (profile == null) return;
    _countDraftDebounce?.cancel();
    _countDraftDebounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final draft = await SmartNightDraftService(
          settingsDao: ref.read(settingsDaoProvider),
        ).savePending(
          profileId: profile.id.toString(),
          astronomicalDay: patched.context.windowStart,
          plan: patched,
        );
        if (!mounted) return;
        setState(() => _previewDraftId = draft.id);
      } catch (e) {
        if (mounted) {
          context.showWarningSnackBar('Could not save adjusted counts: $e');
        }
      }
    });
  }

  /// Walk every capture node in `seq` and overwrite its per-filter counts
  /// with the user-tweaked values. We match by filter name within the same
  /// TargetHeader. A wheel-less target emits a single unfiltered
  /// [ExposureNode] instead of a [SmartExposureNode]; its count is patched
  /// from the target's one filter plan.
  Sequence _patchSequenceCounts(
    Sequence seq,
    List<SmartNightPlannedTarget> targets,
  ) {
    final byTargetName = <String, SmartNightPlannedTarget>{
      for (final t in targets) t.suggestion.targetName: t,
    };
    final newNodes = <String, SequenceNode>{...seq.nodes};

    String? targetNameFor(SequenceNode node) {
      String? parentId = node.parentId;
      while (parentId != null) {
        final parent = seq.nodes[parentId];
        if (parent is TargetHeaderNode) return parent.targetName;
        parentId = parent?.parentId;
      }
      return null;
    }

    for (final entry in seq.nodes.entries) {
      final node = entry.value;
      if (node is ExposureNode && node.frameType == FrameType.light) {
        final targetName = targetNameFor(node);
        if (targetName == null) continue;
        final tweaked = byTargetName[targetName];
        if (tweaked == null || !tweaked.isUnfiltered) continue;
        final plan = tweaked.filterPlans.single;
        newNodes[node.id] = node.copyWith(
          count: plan.count,
          durationSecs: plan.durationSecs,
        );
        continue;
      }
      if (node is! SmartExposureNode) continue;
      // Walk up to find the parent TargetHeader to identify which
      // planned target this SmartExposure belongs to.
      final targetName = targetNameFor(node);
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
    if (_isStarting) return;
    final plan = _preview;
    if (plan == null) return;
    setState(() => _isStarting = true);
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
    } finally {
      if (mounted) setState(() => _isStarting = false);
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

  /// Persist the built plan's sequence as a reusable template via the
  /// sequence repository, instead of starting it. The Sequence is already
  /// assembled in [plan]; we just flag it as a template and save.
  Future<void> _savePlanAsTemplate(SmartNightPlan plan) async {
    if (_isStarting) return;
    setState(() => _isStarting = true);
    try {
      await ref
          .read(sequenceRepositoryProvider)
          .saveSequence(plan.sequence, isTemplate: true);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Could not save template: $e');
      }
      return;
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    context.showSuccessSnackBar(
      'Saved "${plan.sequence.name}" as a template.',
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

  String _formatDuration(Duration d) =>
      DurationFormat.of(d, style: DurationStyle.compact);

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}
