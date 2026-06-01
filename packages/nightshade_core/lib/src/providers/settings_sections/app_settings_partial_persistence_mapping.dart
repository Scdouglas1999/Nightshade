part of '../settings_provider.dart';

extension _AppSettingsPartialPersistenceMapping on AppSettingsNotifier {
  AppSettingsState _applySettingsMap(
    AppSettingsState current,
    Map<String, String> settings,
  ) {
    return current.copyWith(
      startMinimized: settings.containsKey('start_minimized')
          ? _parseBool(settings['start_minimized'], current.startMinimized)
          : null,
      autoConnectEquipment: settings.containsKey('auto_connect_equipment')
          ? _parseBool(
              settings['auto_connect_equipment'],
              current.autoConnectEquipment,
            )
          : null,
      autoSaveSequences: settings.containsKey('auto_save_sequences')
          ? _parseBool(
              settings['auto_save_sequences'],
              current.autoSaveSequences,
            )
          : null,
      confirmBeforeClosing: settings.containsKey('confirm_before_closing')
          ? _parseBool(
              settings['confirm_before_closing'],
              current.confirmBeforeClosing,
            )
          : null,
      autoDiscoverOnLaunch: settings.containsKey('auto_discover_on_launch')
          ? _parseBool(
              settings['auto_discover_on_launch'],
              current.autoDiscoverOnLaunch,
            )
          : null,
      theme: settings['theme'],
      language: settings['language'],
      accentColor: settings['accent_color'],
      fontSize: settings['font_size'],
      sidebarCollapsed: settings.containsKey('sidebar_collapsed')
          ? _parseBool(settings['sidebar_collapsed'], current.sidebarCollapsed)
          : null,
      latitude: settings.containsKey('observer_latitude')
          ? _parseDouble(settings['observer_latitude'], current.latitude)
          : null,
      longitude: settings.containsKey('observer_longitude')
          ? _parseDouble(settings['observer_longitude'], current.longitude)
          : null,
      elevation: settings.containsKey('observer_elevation')
          ? _parseDouble(settings['observer_elevation'], current.elevation)
          : null,
      timezone: settings['timezone'],
      useSystemTime: settings.containsKey('use_system_time')
          ? _parseBool(settings['use_system_time'], current.useSystemTime)
          : null,
      imageFormat: settings['image_format'],
      fileNamingPattern: settings['file_naming_pattern'],
      bitDepth: settings['bit_depth'],
      parkOnUnsafeWeather: settings.containsKey('park_on_unsafe_weather')
          ? _parseBool(
              settings['park_on_unsafe_weather'],
              current.parkOnUnsafeWeather,
            )
          : null,
      parkBeforeDawn: settings.containsKey('park_before_dawn')
          ? _parseBool(settings['park_before_dawn'], current.parkBeforeDawn)
          : null,
      meridianFlipMinutes: settings.containsKey('meridian_flip_minutes')
          ? _parseInt(
              settings['meridian_flip_minutes'],
              current.meridianFlipMinutes,
            )
          : null,
      autoFocusOnFilterChange:
          settings.containsKey('auto_focus_on_filter_change')
              ? _parseBool(
                  settings['auto_focus_on_filter_change'],
                  current.autoFocusOnFilterChange,
                )
              : null,
      useFilterFocusOffsets: settings.containsKey('use_filter_focus_offsets')
          ? _parseBool(
              settings['use_filter_focus_offsets'],
              current.useFilterFocusOffsets,
            )
          : null,
      autoFocusEveryMinutes: settings.containsKey('auto_focus_every_minutes')
          ? _parseInt(
              settings['auto_focus_every_minutes'],
              current.autoFocusEveryMinutes,
            )
          : null,
      ditherEnabled: settings.containsKey('dither_enabled')
          ? _parseBool(settings['dither_enabled'], current.ditherEnabled)
          : null,
      ditherEveryFrames: settings.containsKey('dither_every_frames')
          ? _parseInt(
              settings['dither_every_frames'],
              current.ditherEveryFrames,
            )
          : null,
      safetyFailMode: settings.containsKey('safety_fail_mode')
          ? _parseSafetyFailMode(settings['safety_fail_mode'])
          : null,
      plateSolver: settings['plate_solver'],
      astapPath: settings['astap_path'],
      astrometryPath: settings['astrometry_path'],
      plateSolveTimeout: settings.containsKey('plate_solve_timeout')
          ? _parseInt(
              settings['plate_solve_timeout'],
              current.plateSolveTimeout,
            )
          : null,
      plateSolveSearchRadius: settings.containsKey('plate_solve_search_radius')
          ? _parseDouble(
              settings['plate_solve_search_radius'],
              current.plateSolveSearchRadius,
            )
          : null,
      blindSolve: settings.containsKey('blind_solve')
          ? _parseBool(settings['blind_solve'], current.blindSolve)
          : null,
      phd2Path: settings['phd2_path'],
      phd2Host: settings['phd2_host'],
      phd2Port: settings.containsKey('phd2_port')
          ? _parseInt(settings['phd2_port'], current.phd2Port)
          : null,
      notificationsEnabled: settings.containsKey('notifications_enabled')
          ? _parseBool(
              settings['notifications_enabled'],
              current.notificationsEnabled,
            )
          : null,
      discordWebhook: settings['discord_webhook'],
      pushoverKey: settings['pushover_key'],
      pushoverUser: settings['pushover_user'],
      notifyOnSequenceComplete:
          settings.containsKey('notify_on_sequence_complete')
              ? _parseBool(
                  settings['notify_on_sequence_complete'],
                  current.notifyOnSequenceComplete,
                )
              : null,
      notifyOnError: settings.containsKey('notify_on_error')
          ? _parseBool(settings['notify_on_error'], current.notifyOnError)
          : null,
      notifyOnMeridianFlip: settings.containsKey('notify_on_meridian_flip')
          ? _parseBool(
              settings['notify_on_meridian_flip'],
              current.notifyOnMeridianFlip,
            )
          : null,
      soundEnabled: settings.containsKey('sound_enabled')
          ? _parseBool(settings['sound_enabled'], current.soundEnabled)
          : null,
      imageOutputPath: settings['image_output_path'],
      sequencesPath: settings['sequences_path'],
      databasePath: settings['database_path'],
      logsPath: settings['logs_path'],
      indiServerHost: settings['indi_server_host'],
      indiServerPort: settings.containsKey('indi_server_port')
          ? _parseInt(settings['indi_server_port'], current.indiServerPort)
          : null,
      indiAutoConnect: settings.containsKey('indi_auto_connect')
          ? _parseBool(settings['indi_auto_connect'], current.indiAutoConnect)
          : null,
      alpacaServerHost: settings['alpaca_server_host'],
      alpacaServerPort: settings.containsKey('alpaca_server_port')
          ? _parseInt(settings['alpaca_server_port'], current.alpacaServerPort)
          : null,
      alpacaAutoDiscover: settings.containsKey('alpaca_auto_discover')
          ? _parseBool(
              settings['alpaca_auto_discover'],
              current.alpacaAutoDiscover,
            )
          : null,
      useNativeExecution: settings.containsKey('use_native_execution')
          ? _parseBool(
              settings['use_native_execution'],
              current.useNativeExecution,
            )
          : null,
      useSimulationMode: settings.containsKey('use_simulation_mode')
          ? _parseBool(
              settings['use_simulation_mode'],
              current.useSimulationMode,
            )
          : null,
      webServerEnabled: settings.containsKey('web_server_enabled')
          ? _parseBool(settings['web_server_enabled'], current.webServerEnabled)
          : null,
      webServerPort: settings.containsKey('web_server_port')
          ? _parseInt(settings['web_server_port'], current.webServerPort)
          : null,
      coolingBehavior: settings['cooling_behavior'],
      defaultGain: settings.containsKey('default_gain')
          ? _parseInt(settings['default_gain'], current.defaultGain)
          : null,
      defaultOffset: settings.containsKey('default_offset')
          ? _parseInt(settings['default_offset'], current.defaultOffset)
          : null,
      enableMeridianFlip: settings.containsKey('enable_meridian_flip')
          ? _parseBool(
              settings['enable_meridian_flip'],
              current.enableMeridianFlip,
            )
          : null,
      tempCompensation: settings.containsKey('temp_compensation')
          ? _parseBool(
              settings['temp_compensation'],
              current.tempCompensation,
            )
          : null,
      tempCoefficient: settings.containsKey('temp_coefficient')
          ? _parseDouble(
              settings['temp_coefficient'],
              current.tempCoefficient,
            )
          : null,
      backlashCompensation: settings.containsKey('backlash_compensation')
          ? _parseInt(
              settings['backlash_compensation'],
              current.backlashCompensation,
            )
          : null,
      ditherScale: settings['dither_scale'],
      settleThreshold: settings.containsKey('settle_threshold')
          ? _parseDouble(settings['settle_threshold'], current.settleThreshold)
          : null,
      settleTimeout: settings.containsKey('settle_timeout')
          ? _parseInt(settings['settle_timeout'], current.settleTimeout)
          : null,
      bortleClass: settings.containsKey('bortle_class')
          ? _parseInt(settings['bortle_class'], current.bortleClass)
          : null,
      horizonProfileJson: settings['horizon_profile_json'],
      effectiveHorizonDeg: settings.containsKey('effective_horizon_deg')
          ? _parseDouble(
              settings['effective_horizon_deg'],
              current.effectiveHorizonDeg,
            )
          : null,
      audibleAlertsOnCritical:
          settings.containsKey('audible_alerts_on_critical')
              ? _parseBool(
                  settings['audible_alerts_on_critical'],
                  current.audibleAlertsOnCritical,
                )
              : null,
      criticalAlertSound: settings.containsKey('critical_alert_sound')
          ? _normaliseCriticalAlertSound(settings['critical_alert_sound'])
          : null,
      pushCriticalAlerts: settings.containsKey('push_critical_alerts')
          ? _parseBool(
              settings['push_critical_alerts'],
              current.pushCriticalAlerts,
            )
          : null,
      renderingPlatform: settings.containsKey('rendering_platform')
          ? RenderingPlatform.parseStored(settings['rendering_platform'])
          : null,
      // Wave 4 Recovery Mode â€” partial-update path. Each key is only
      // honoured if present in the patch, mirroring the rest of this
      // helper.
      recoveryDefaultRetryIntervalMins:
          settings.containsKey('recovery_default_retry_interval_mins')
              ? _parseDouble(
                  settings['recovery_default_retry_interval_mins'],
                  current.recoveryDefaultRetryIntervalMins,
                )
              : null,
      recoveryDefaultMaxDurationMins:
          settings.containsKey('recovery_default_max_duration_mins')
              ? _parseDouble(
                  settings['recovery_default_max_duration_mins'],
                  current.recoveryDefaultMaxDurationMins,
                )
              : null,
      recoveryStopTrackingDuringRecovery:
          settings.containsKey('recovery_stop_tracking_during_recovery')
              ? _parseBool(
                  settings['recovery_stop_tracking_during_recovery'],
                  current.recoveryStopTrackingDuringRecovery,
                )
              : null,
      recoveryAbortOnMeridian:
          settings.containsKey('recovery_abort_on_meridian')
              ? _parseBool(
                  settings['recovery_abort_on_meridian'],
                  current.recoveryAbortOnMeridian,
                )
              : null,
      recoveryAudibleAlertWhenEntered:
          settings.containsKey('recovery_audible_alert_when_entered')
              ? _parseBool(
                  settings['recovery_audible_alert_when_entered'],
                  current.recoveryAudibleAlertWhenEntered,
                )
              : null,
      afMethod: settings['af_method'],
      afCurveFitting: settings['af_curve_fitting'],
      afStepSize: settings.containsKey('af_step_size')
          ? _parseInt(settings['af_step_size'], current.afStepSize)
          : null,
      afExposureTime: settings.containsKey('af_exposure_time')
          ? _parseDouble(settings['af_exposure_time'], current.afExposureTime)
          : null,
      afInitialOffsetSteps: settings.containsKey('af_initial_offset_steps')
          ? _parseInt(
              settings['af_initial_offset_steps'],
              current.afInitialOffsetSteps,
            )
          : null,
      afNumberOfAttempts: settings.containsKey('af_number_of_attempts')
          ? _parseInt(
              settings['af_number_of_attempts'],
              current.afNumberOfAttempts,
            )
          : null,
      afUseBrightestNStars: settings.containsKey('af_use_brightest_n_stars')
          ? _parseInt(
              settings['af_use_brightest_n_stars'],
              current.afUseBrightestNStars,
            )
          : null,
      afOuterCropRatio: settings.containsKey('af_outer_crop_ratio')
          ? _parseDouble(
              settings['af_outer_crop_ratio'],
              current.afOuterCropRatio,
            )
          : null,
      afInnerCropRatio: settings.containsKey('af_inner_crop_ratio')
          ? _parseDouble(
              settings['af_inner_crop_ratio'],
              current.afInnerCropRatio,
            )
          : null,
      afBinning: settings.containsKey('af_binning')
          ? _parseInt(settings['af_binning'], current.afBinning)
          : null,
      afRSquaredThreshold: settings.containsKey('af_r_squared_threshold')
          ? _parseDouble(
              settings['af_r_squared_threshold'],
              current.afRSquaredThreshold,
            )
          : null,
      afDisableGuidingDuringAf:
          settings.containsKey('af_disable_guiding_during_af')
              ? _parseBool(
                  settings['af_disable_guiding_during_af'],
                  current.afDisableGuidingDuringAf,
                )
              : null,
      afFocuserSettleTimeMs: settings.containsKey('af_focuser_settle_time_ms')
          ? _parseInt(
              settings['af_focuser_settle_time_ms'],
              current.afFocuserSettleTimeMs,
            )
          : null,
      afExposuresPerPoint: settings.containsKey('af_exposures_per_point')
          ? _parseInt(
              settings['af_exposures_per_point'],
              current.afExposuresPerPoint,
            )
          : null,
      afBacklashCompMethod: settings['af_backlash_comp_method'],
      afBacklashIn: settings.containsKey('af_backlash_in')
          ? _parseInt(settings['af_backlash_in'], current.afBacklashIn)
          : null,
      afBacklashOut: settings.containsKey('af_backlash_out')
          ? _parseInt(settings['af_backlash_out'], current.afBacklashOut)
          : null,
      afAutofocusFilterName: settings['af_autofocus_filter_name'],
      afFilterSettingsJson: settings['af_filter_settings'],
      // Pack G â€” observer name (FITS OBSERVER).
      observerName: settings['observer_name'],
      // Pack G â€” Wave 3 Image Grading. Nullable double / int fields use
      // the `_unset` sentinel for "no change"; an explicit "null" string
      // clears the field.
      enableImageGrading: settings.containsKey('image_grading_enabled')
          ? _parseBool(
              settings['image_grading_enabled'],
              current.enableImageGrading,
            )
          : null,
      imageGradingHfrThresholdPx:
          settings.containsKey('image_grading_hfr_threshold_px')
              ? _parseNullableDouble(
                  settings['image_grading_hfr_threshold_px'],
                  current.imageGradingHfrThresholdPx,
                )
              : _unset,
      imageGradingHfrBaselinePercent:
          settings.containsKey('image_grading_hfr_baseline_percent')
              ? _parseNullableDouble(
                  settings['image_grading_hfr_baseline_percent'],
                  current.imageGradingHfrBaselinePercent,
                )
              : _unset,
      imageGradingEccentricityThreshold:
          settings.containsKey('image_grading_eccentricity_threshold')
              ? _parseNullableDouble(
                  settings['image_grading_eccentricity_threshold'],
                  current.imageGradingEccentricityThreshold,
                )
              : _unset,
      imageGradingStarCountMin:
          settings.containsKey('image_grading_star_count_min')
              ? _parseNullableInt(
                  settings['image_grading_star_count_min'],
                  current.imageGradingStarCountMin,
                )
              : _unset,
      imageGradingMaxConsecutiveRejects:
          settings.containsKey('image_grading_max_consecutive_rejects')
              ? _parseInt(
                  settings['image_grading_max_consecutive_rejects'],
                  current.imageGradingMaxConsecutiveRejects,
                )
              : null,
      imageGradingRejectFolderPath:
          settings.containsKey('image_grading_reject_folder_path')
              ? (settings['image_grading_reject_folder_path']?.isEmpty ?? true
                  ? null
                  : settings['image_grading_reject_folder_path'])
              : _unset,
      // Wave 5 Agent 3 â€” Pre-flight partial-update wire-up.
      preflightStrictness: settings.containsKey('preflight_strictness')
          ? _parsePreflightStrictness(settings['preflight_strictness'])
          : null,
      polarAlignmentMaxAgeDays:
          settings.containsKey('polar_alignment_max_age_days')
              ? _parseInt(
                  settings['polar_alignment_max_age_days'],
                  current.polarAlignmentMaxAgeDays,
                )
              : null,
      darkLibraryMinCoverage: settings.containsKey('dark_library_min_coverage')
          ? _parseInt(
              settings['dark_library_min_coverage'],
              current.darkLibraryMinCoverage,
            )
          : null,
      opticalTrainDriftThreshold:
          settings.containsKey('optical_train_drift_threshold')
              ? _parseDouble(
                  settings['optical_train_drift_threshold'],
                  current.opticalTrainDriftThreshold,
                )
              : null,
      // Wave 6 Agent 1 â€” Smart Night partial-update wiring. The nullable
      // session-hours knob uses the `_unset` sentinel so a patch can
      // either leave it alone (omit the key) or clear it back to
      // "use full dark window" (pass the literal string "null").
      smartNightMaxSessionHours:
          settings.containsKey('smart_night_max_session_hours')
              ? _parseNullableDouble(
                  settings['smart_night_max_session_hours'],
                  current.smartNightMaxSessionHours,
                )
              : _unset,
      smartNightDefaultAfCadenceFrames:
          settings.containsKey('smart_night_default_af_cadence_frames')
              ? _parseInt(
                  settings['smart_night_default_af_cadence_frames'],
                  current.smartNightDefaultAfCadenceFrames,
                )
              : null,
      smartNightDefaultIntegrationBudgetMinsPerTarget: settings.containsKey(
              'smart_night_default_integration_budget_mins_per_target')
          ? _parseInt(
              settings[
                  'smart_night_default_integration_budget_mins_per_target'],
              current.smartNightDefaultIntegrationBudgetMinsPerTarget,
            )
          : null,
      smartNightIncludeFlatsAtEnd:
          settings.containsKey('smart_night_include_flats_at_end')
              ? _parseBool(
                  settings['smart_night_include_flats_at_end'],
                  current.smartNightIncludeFlatsAtEnd,
                )
              : null,
      smartNightUseSchedulerForMultiTarget:
          settings.containsKey('smart_night_use_scheduler_for_multi_target')
              ? _parseBool(
                  settings['smart_night_use_scheduler_for_multi_target'],
                  current.smartNightUseSchedulerForMultiTarget,
                )
              : null,
      smartNightSchedulerTargetThreshold:
          settings.containsKey('smart_night_scheduler_target_threshold')
              ? _parseInt(
                  settings['smart_night_scheduler_target_threshold'],
                  current.smartNightSchedulerTargetThreshold,
                )
              : null,
      smartNightDefaultStrategy: settings['smart_night_default_strategy'],
      smartNightPolarAlignmentStaleAfterDays:
          settings.containsKey('smart_night_polar_alignment_stale_after_days')
              ? _parseInt(
                  settings['smart_night_polar_alignment_stale_after_days'],
                  current.smartNightPolarAlignmentStaleAfterDays,
                )
              : null,
      // Wave 6 Agent 5 â€” Notes prompt opt-out.
      smartNightSubExposureFloorSecs:
          settings.containsKey('smart_night_sub_exposure_floor_secs')
              ? _parseDouble(
                  settings['smart_night_sub_exposure_floor_secs'],
                  current.smartNightSubExposureFloorSecs,
                )
              : null,
      smartNightSubExposureCeilingSecs:
          settings.containsKey('smart_night_sub_exposure_ceiling_secs')
              ? _parseDouble(
                  settings['smart_night_sub_exposure_ceiling_secs'],
                  current.smartNightSubExposureCeilingSecs,
                )
              : null,
      smartNightTargetSnr: settings.containsKey('smart_night_target_snr')
          ? _parseDouble(
              settings['smart_night_target_snr'],
              current.smartNightTargetSnr,
            )
          : null,
      smartNightAutoPromptEnabled:
          settings.containsKey('smart_night.auto_prompt_enabled')
              ? _parseBool(
                  settings['smart_night.auto_prompt_enabled'],
                  current.smartNightAutoPromptEnabled,
                )
              : null,
      promptForNotesAfterRun: settings.containsKey('notes.prompt_after_run')
          ? _parseBool(
              settings['notes.prompt_after_run'],
              current.promptForNotesAfterRun,
            )
          : null,
      // Wave 7 â€” Session lifecycle. Each key gates the field so a
      // partial patch can update one knob without resetting the others.
      sessionHandoffAutoPrompt:
          settings.containsKey('session.handoff_auto_prompt')
              ? _parseBool(
                  settings['session.handoff_auto_prompt'],
                  current.sessionHandoffAutoPrompt,
                )
              : null,
      campaignRollupSurfaceTargetsTab:
          settings.containsKey('campaign_rollup.surface_targets_tab')
              ? _parseBool(
                  settings['campaign_rollup.surface_targets_tab'],
                  current.campaignRollupSurfaceTargetsTab,
                )
              : null,
      campaignRollupGroupingMode:
          settings.containsKey('campaign_rollup.grouping_mode')
              ? _parseCampaignGroupingMode(
                  settings['campaign_rollup.grouping_mode'])
              : null,
    );
  }

  /// Pack G â€” string -> nullable double for the grading settings.
  /// Empty / "null" string => null (the user cleared the field); a parse
  /// failure falls back to the prior value to avoid silently zeroing a
  /// threshold.
  double? _parseNullableDouble(String? value, double? previous) {
    if (value == null || value.isEmpty || value == 'null') return null;
    return double.tryParse(value) ?? previous;
  }

  int? _parseNullableInt(String? value, int? previous) {
    if (value == null || value.isEmpty || value == 'null') return null;
    return int.tryParse(value) ?? previous;
  }
}
