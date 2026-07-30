part of '../sequence_executor.dart';

extension _SequenceExecutorRuntimeConfigOperations on SequenceExecutor {
  Future<void> _startNativeExecution(
    Sequence sequence,
    AppSettingsState settings,
  ) async {
    final backend = _backend;

    // Sync observer location to Rust backend before starting sequence
    // This ensures the sequencer has access to the current location from settings
    _logger.debug(
      '_startNativeExecution: authoritative settings loaded',
      source: 'SequenceExecutor',
    );
    _logger.debug(
      'Location from settings: lat=${settings.latitude}, lon=${settings.longitude}, elev=${settings.elevation}',
      source: 'SequenceExecutor',
    );
    if (settings.latitude != 0.0 || settings.longitude != 0.0) {
      _logger.debug(
        'Syncing location to backend...',
        source: 'SequenceExecutor',
      );
      await backend.setLocation(
        ObserverLocation(
          latitude: settings.latitude,
          longitude: settings.longitude,
          elevation: settings.elevation,
        ),
      );
      _logger.debug('Location sync complete', source: 'SequenceExecutor');
    } else {
      _logger.debug(
        'Skipping location sync: location is 0,0',
        source: 'SequenceExecutor',
      );
    }

    await backend.sequencerSetSimulationMode(
      effectiveSimulationMode(settings.useSimulationMode),
    );

    await _pushEffectiveSafetyFailMode(backend, settings.safetyFailMode);

    final savePath = settings.imageOutputPath;
    if (savePath.isNotEmpty) {
      await backend.sequencerSetSavePath(savePath);
      _logger.debug('Save path set to: $savePath', source: 'SequenceExecutor');
    } else {
      await backend.sequencerSetSavePath(null);
      _logger.warning(
        'No save path configured - images will NOT be saved to disk!',
        source: 'SequenceExecutor',
      );
    }

    final cameraState = _ref.read(cameraStateProvider);
    final mountState = _ref.read(mountStateProvider);
    final focuserState = _ref.read(focuserStateProvider);
    final filterwheelState = _ref.read(filterWheelStateProvider);
    final rotatorState = _ref.read(rotatorStateProvider);

    final cameraId =
        cameraState.connectionState == DeviceConnectionState.connected
        ? cameraState.deviceId
        : null;
    final mountId =
        mountState.connectionState == DeviceConnectionState.connected
        ? mountState.deviceId
        : null;
    final focuserId =
        focuserState.connectionState == DeviceConnectionState.connected
        ? focuserState.deviceId
        : null;
    final filterwheelId =
        filterwheelState.connectionState == DeviceConnectionState.connected
        ? filterwheelState.deviceId
        : null;
    final rotatorId =
        rotatorState.connectionState == DeviceConnectionState.connected
        ? rotatorState.deviceId
        : null;

    await backend.sequencerSetDevices(
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterwheelId: filterwheelId,
      rotatorId: rotatorId,
    );

    // Tell the operator, in the run record, that automatic refocus is off for
    // this run. With no focuser connected the native executor disarms every
    // autofocus-action trigger (HFR degradation, temperature shift, focus
    // drift, the frame-interval refocus). That is the correct behaviour — an
    // autofocus is physically impossible — but it silently removes a
    // protection the sequence editor still advertises, so the run report has
    // to say so rather than look like a night with focus management running.
    // `persist: false` — this is a start-up fact, not a running statistic. It
    // reaches the DB via the final `finishRun` stats write like every other
    // warning; forcing an incremental `updateStats` here would add a second DB
    // round-trip before the first frame for a value that cannot change.
    if (focuserId == null) {
      _surfaceRunWarning(
        'No focuser is connected, so automatic refocus is disabled for this '
        'run (HFR-degradation, temperature-shift, focus-drift and '
        'interval refocus triggers are all inert). Focus will not be '
        'corrected automatically.',
        persist: false,
      );
    }

    // The native defect-map runtime slot is not restored from app_settings.
    // Seed it for every run so auto-apply survives restarts and headless starts.
    await seedDefectMapRuntimeForSequence(_ref);

    // Meridian nodes that opt into global defaults are serialized from this
    // provider. Wait for the DB/remote-host snapshot so a fast start after app
    // launch cannot bake factory defaults into the run while the real settings
    // are still loading in the background.
    await _ref.read(globalMeridianFlipSettingsProvider.notifier).ensureLoaded();
    final json = _sequenceToJson(sequence);
    await backend.sequencerLoadJson(json);

    // Seed RuntimeConfig from persisted user settings BEFORE
    // start() so the trigger monitor's first poll honours the user's cadence
    // / dither / location / filter-offsets values instead of the Rust
    // defaults (autofocus_interval_frames=25, dither pixels=5, location 0/0,
    // empty filter offsets). Previously these were only pushed by the live
    // settings watchers, which fire only on subsequent changes — so a
    // headless start that never visits the Settings UI ran with the wrong
    // cadence silently. Failures are surfaced (not swallowed); a bad seed
    // means the user wants those values to apply and we must abort start
    // rather than run with the wrong cadence.
    await _seedRuntimeConfigFromSettings(backend);

    // Consult the session-handoff decision for every
    // TargetHeader with an `integrationBudget` configured. The operator's
    // pre-flight decision (Resume / Restart / Continue New) decides how
    // the Rust `BudgetRegistry` is seeded for this run.
    //
    // Resume      → pre-credit per-filter integration from the prior
    //               session's carry-over so "Lum: 4h done / 8h target"
    //               persists into the new run.
    // Restart     → push an empty per-filter map so any stale checkpoint
    //               carry-over is overwritten with zeros.
    // ContinueNew → omit the target (default behaviour: tracker starts
    //               from zero without zeroing prior state).
    //
    // Done AFTER `_seedRuntimeConfigFromSettings` so the carry-over write
    // overrides any default the runtime-config push might re-stamp, and
    // BEFORE `sequencerStart()` so the consumption hook at the top of
    // the spawned executor task sees the freshly-staged map.
    await _seedIntegrationCarryOverFromHandoff(backend, sequence);

    // The FfiBackend eagerly initializes the event stream in its constructor,
    // so the Rust api_event_stream() function should already be running and
    // subscribed to the event bus. We just subscribe to the broadcast stream
    // here.
    _nativeEventSubscription = backend.eventStream.listen(
      _handleSequencerEvent,
      onError: (e) =>
          _logger.error('Event stream error: $e', source: 'SequenceExecutor'),
    );

    _startSettingsWatchers(backend);

    // Mark the native-launch boundary: a throw from here on may mean a partial
    // launch, so [_rollbackStart] will best-effort sequencerStop rather than
    // tear down blind.
    _nativeLaunchAttempted = true;
    await backend.sequencerStart();
  }

  /// Resolve the safety fail mode the native executor must actually run with,
  /// given the operator's configured [configured] mode.
  ///
  /// When weather safety is DISABLED the operator has opted out of
  /// weather-driven aborts. The Rust safety poll fail-closes on a rig with no
  /// safety-monitor device, so pushing a stale `failClosed` would keep the
  /// always-armed in-sequencer `WeatherUnsafe` trigger firing (via
  /// `!weather_safe`) even with monitoring off — parking the mount and
  /// aborting every sequence within milliseconds of start. Force the executor
  /// poll permissive (`failOpen`) while disabled; the Dart verdict already
  /// abstains (see weather_safety_provider), so nothing drives an unsafe
  /// verdict. Re-enabling restores the configured mode on the next push.
  ///
  /// This lives in ONE place because three call sites push the fail mode —
  /// run start, checkpoint resume, and the mid-run settings watcher — and the
  /// resume path used to push the raw configured value, which is why resuming
  /// a crashed run on a rig with no safety monitor aborted instantly.
  SafetyFailMode _effectiveSafetyFailMode(SafetyFailMode configured) {
    final weatherSafetyEnabled = _ref
        .read(weatherSettingsProvider)
        .weatherSafetyEnabled;
    return weatherSafetyEnabled ? configured : SafetyFailMode.failOpen;
  }

  /// Push [configured] through [_effectiveSafetyFailMode] to the executor.
  Future<void> _pushEffectiveSafetyFailMode(
    NightshadeBackend backend,
    SafetyFailMode configured,
  ) async {
    final effective = _effectiveSafetyFailMode(configured);
    final wire = _safetyFailModeToBackendString(effective);
    await backend.sequencerSetSafetyFailMode(wire);
    _logger.debug(
      'Safety fail mode set to: $wire (configured=${configured.name})',
      source: 'SequenceExecutor',
    );
  }

  /// Push every user-controlled RuntimeConfig field into the loaded executor.
  ///
  /// Why one method instead of inline: keeps the start path readable and
  /// makes the same seed sequence reusable from the headless start path
  /// (`DeviceService.sequencerStart`) once it grows past the simple wrapper.
  /// Each push is independent — a failure on one field still attempts the
  /// next, but the first failure is rethrown after the batch so the caller
  /// learns about the misconfiguration before sequencerStart() runs.
  Future<void> _seedRuntimeConfigFromSettings(NightshadeBackend backend) async {
    Object? firstError;
    StackTrace? firstStack;

    // Autofocus cadence: persisted in sequencer_autofocus_interval_frames; the
    // Rust default of 25 is wrong for both very-short and very-long subs.
    try {
      final defaults = _ref.read(sequencerDefaultsProvider);
      final frames = defaults.autofocusIntervalFrames < 1
          ? 1
          : defaults.autofocusIntervalFrames;
      await backend.sequencerUpdateAutofocusInterval(frames);
      _logger.debug(
        'Seeded autofocus interval: every $frames frames',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed autofocus interval: $e',
        source: 'SequenceExecutor',
      );
    }

    // Dither config: persisted in SequencerDefaults; the Rust defaults differ
    // from what the user sees in Settings, so without this seed an unattended
    // headless start uses a stale config.
    try {
      final defaults = _ref.read(sequencerDefaultsProvider);
      await backend.sequencerUpdateDitherConfig(
        pixels: defaults.ditherPixels,
        settlePixels: defaults.ditherSettlePixels,
        settleTime: defaults.ditherSettleTime,
        settleTimeout: defaults.ditherSettleTimeout,
        raOnly: defaults.ditherRaOnly,
      );
      _logger.debug(
        'Seeded dither config: pixels=${defaults.ditherPixels} settle=${defaults.ditherSettleTime}s',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed dither config: $e',
        source: 'SequenceExecutor',
      );
    }

    // Meridian-flip settings. The Rust `meridian_flip` trigger is seeded by
    // `TriggerManager::create_standard_triggers` with
    // `MeridianFlipConfig::default()`, and until this push existed NOTHING ever
    // replaced it — so every trigger-driven flip (the only flip that fires on
    // an unattended night) ignored the whole Settings -> Meridian Flip panel.
    // It hid because the Rust defaults happen to equal the panel's defaults;
    // only an operator who CHANGED a value was affected, and then silently.
    // Proven live: a run with `recenterAfterFlip: false` still ran
    // "Step 6/8: Plate solving and centering".
    try {
      await backend.sequencerUpdateMeridianFlipConfig(
        jsonEncode(buildGlobalMeridianFlipConfigJson()),
      );
      _logger.debug(
        'Seeded meridian-flip trigger config from user settings',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed meridian-flip config: $e',
        source: 'SequenceExecutor',
      );
    }

    // Observer location: distinct from setLocation() above (which sets the
    // higher-level NightshadeBackend location). The sequencer's RuntimeConfig
    // owns its own lat/lon used by meridian-flip and altitude calculations.
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        await backend.sequencerUpdateLocation(
          latitude: settings.latitude,
          longitude: settings.longitude,
        );
        _logger.debug(
          'Seeded sequencer location: lat=${settings.latitude} lon=${settings.longitude}',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed sequencer location: $e',
        source: 'SequenceExecutor',
      );
    }

    // Filter focus offsets: merge the equipment profile table with non-zero
    // per-filter AF overrides (the same precedence DeviceService uses). Honor
    // the user's master toggle by sending an empty map when disabled.
    try {
      final profile = _ref.read(activeEquipmentProfileProvider);
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings == null) {
        throw StateError(
          'AppSettings is not loaded; filter focus-offset behavior is unknown.',
        );
      }
      final offsets = <String, int>{};
      if (settings.useFilterFocusOffsets) {
        offsets.addAll(profile?.filterFocusOffsets ?? const <String, int>{});
        final autofocusFilters = AutofocusSettings.parseFilterSettingsJson(
          settings.afFilterSettingsJson,
        );
        for (final entry in autofocusFilters.entries) {
          if (entry.value.focusOffset != 0) {
            offsets[entry.key] = entry.value.focusOffset;
          }
        }
      }
      await backend.sequencerUpdateFilterOffsets(offsets);
      _logger.debug(
        'Seeded filter focus offsets: ${offsets.length} entries',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed filter focus offsets: $e',
        source: 'SequenceExecutor',
      );
    }

    // Default image-grading thresholds + reject folder. Without
    // this seed the executor's RuntimeConfig stays at the all-None
    // default and "Enable image grading" in Settings has no effect on the
    // next sequence start.
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        await backend.sequencerUpdateDefaultQualityCheck(
          hfrThreshold: settings.imageGradingHfrThresholdPx,
          hfrBaselinePercent: settings.imageGradingHfrBaselinePercent,
          eccentricityThreshold: settings.imageGradingEccentricityThreshold,
          starCountMin: settings.imageGradingStarCountMin,
          maxConsecutiveRejects: settings.imageGradingMaxConsecutiveRejects,
          enabled: settings.enableImageGrading,
        );
        _logger.debug(
          'Seeded default_quality_check: enabled=${settings.enableImageGrading}, hfr=${settings.imageGradingHfrThresholdPx}px, baseline=${settings.imageGradingHfrBaselinePercent}%',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed default_quality_check: $e',
        source: 'SequenceExecutor',
      );
    }

    // Reject folder path.
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        await backend.sequencerUpdateRejectFolderPath(
          settings.imageGradingRejectFolderPath,
        );
        _logger.debug(
          'Seeded reject_folder_path: ${settings.imageGradingRejectFolderPath ?? "<default>"}',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed reject_folder_path: $e',
        source: 'SequenceExecutor',
      );
    }

    // Observer / equipment identification so FITS headers carry
    // OBSERVER, TELESCOP, FOCALLEN, APTDIA, INSTRUME, SITEELEV. The
    // observer name comes from app settings; everything else from the
    // active equipment profile. Null / empty fields are honestly omitted
    // from FITS rather than emitted as sentinels.
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      final profile = _ref.read(activeEquipmentProfileProvider);

      // Camera split: profile.cameraName is typically the user-friendly
      // device label (e.g. "ZWO ASI2600MM Pro"). We split on first space
      // for INSTRUME consumers; if there's no space the whole string
      // becomes the model and make is null.
      String? cameraMake;
      String? cameraModel;
      final rawCameraName = profile?.cameraName?.trim();
      if (rawCameraName != null && rawCameraName.isNotEmpty) {
        final spaceIdx = rawCameraName.indexOf(' ');
        if (spaceIdx > 0) {
          cameraMake = rawCameraName.substring(0, spaceIdx).trim();
          cameraModel = rawCameraName.substring(spaceIdx + 1).trim();
        } else {
          cameraModel = rawCameraName;
        }
      }

      // Telescope focal length / aperture: prefer the dedicated
      // telescope_* fields; fall back to focalLength / aperture (the
      // legacy generic fields on EquipmentProfileModel). 0.0 means
      // "not configured" — emit null in that case.
      double? focalLength;
      double? aperture;
      if (profile != null) {
        final tfl = profile.telescopeFocalLength;
        final fl = profile.focalLength;
        if (tfl != null && tfl > 0) {
          focalLength = tfl;
        } else if (fl > 0) {
          focalLength = fl;
        }

        // Aperture needs the SAME legacy fallback as focal length above: a
        // profile built through the generic optics fields has
        // telescopeAperture == 0 and the real value in `aperture`, so reading
        // only telescopeAperture dropped it and every frame was written with
        // FOCALLEN but no APTDIA — an aperture the operator had configured,
        // missing from the FITS header that photometry reads.
        final ta = profile.telescopeAperture;
        final ap = profile.aperture;
        if (ta != null && ta > 0) {
          aperture = ta;
        } else if (ap > 0) {
          aperture = ap;
        }
      }

      await backend.sequencerUpdateObserverProfile(
        observerName: (settings == null || settings.observerName.isEmpty)
            ? null
            : settings.observerName,
        siteElevationM: (settings != null && settings.elevation > 0)
            ? settings.elevation
            : null,
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        telescopeName: profile?.telescopeName,
        telescopeFocalLengthMm: focalLength,
        telescopeApertureMm: aperture,
      );
      _logger.debug(
        'Seeded observer_profile: observer=${settings?.observerName}, telescope=${profile?.telescopeName}, camera=$cameraMake $cameraModel, focal=${focalLength}mm, aperture=${aperture}mm',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed observer_profile: $e',
        source: 'SequenceExecutor',
      );
    }

    // Seed the global default sky-brightness adaptive
    // exposure config from app settings so a sequence start without a
    // settings round-trip still honours the user's choice. When the
    // master switch is off we explicitly clear the executor's value
    // (avoids a stale config sticking around from a prior run).
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        if (settings.adaptiveExposureEnabled) {
          await backend.sequencerUpdateDefaultAdaptiveExposure(
            enabled: settings.adaptiveExposureEnabled,
            targetSnr: settings.adaptiveExposureTargetSnr,
            referenceSkyBrightnessMag: settings.adaptiveExposureReferenceMag,
            minExposureSecs: settings.adaptiveExposureMinSecs,
            maxExposureSecs: settings.adaptiveExposureMaxSecs,
            perFilterEnabled: settings.adaptiveExposurePerFilterEnabled,
            perFilterMinSecs: settings.adaptiveExposurePerFilterMinSecs,
            perFilterMaxSecs: settings.adaptiveExposurePerFilterMaxSecs,
          );
          _logger.debug(
            'Seeded default_adaptive_exposure: enabled=${settings.adaptiveExposureEnabled}, ref=${settings.adaptiveExposureReferenceMag} mag/arcsecÂ², min=${settings.adaptiveExposureMinSecs}s, max=${settings.adaptiveExposureMaxSecs}s',
            source: 'SequenceExecutor',
          );
        } else {
          await backend.sequencerClearDefaultAdaptiveExposure();
          _logger.debug(
            'Cleared default_adaptive_exposure (disabled in settings)',
            source: 'SequenceExecutor',
          );
        }
      }
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed default_adaptive_exposure: $e',
        source: 'SequenceExecutor',
      );
    }

    // Replay Debug — seed the decision-logging enabled flag from
    // the ACTIVE authority's setting before start. `replayDebugEnabledProvider`
    // branches on backend: on the host it reads the local `replay_debug.enabled`
    // app-setting; on a remote client it reads the host's authoritative value.
    // Pushing it through `backend.sequencerSetDecisionLoggingEnabled` reconciles
    // the executor's runtime flag to that persisted policy for both paths. A
    // corrupt/unreadable setting throws (strict parse) and, via `firstError`,
    // aborts the start so we never begin a run under the wrong logging policy.
    try {
      final enabled = await _ref.read(replayDebugEnabledProvider.future);
      await backend.sequencerSetDecisionLoggingEnabled(enabled);
      _logger.debug(
        'Seeded replay decision logging: enabled=$enabled',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      firstError ??= e;
      firstStack ??= st;
      _logger.error(
        'Failed to seed replay decision logging: $e',
        source: 'SequenceExecutor',
      );
    }

    if (firstError != null) {
      // Rethrow so sequencerStart() does not silently proceed with a partial
      // runtime config. The rule "errors are a feature" requires
      // the caller to learn about misconfiguration immediately.
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  /// Consume `sessionHandoffDecisionProvider` for every
  /// TargetHeader and push the resolved per-filter carry-over map to
  /// the Rust executor's `BudgetRegistry` seed.
  ///
  /// Three-way semantics, mirroring `SessionHandoffDecision`:
  ///
  ///   * `Resume`     → write the operator's
  ///                    `SessionCarryOver.perFilterIntegrationSecs` into
  ///                    the carry-over map. The Rust side credits those
  ///                    frames against the configured budget so the
  ///                    very first IntegrationBudget tick reads
  ///                    "Lum: 4h done / 8h target", not "Lum: 0h done".
  ///   * `Restart`    → write an explicit empty map for the target id
  ///                    so any pre-existing checkpoint state is
  ///                    overwritten with zeros.
  ///   * `ContinueNew` → omit the target entirely (no carry-over, no
  ///                    zeroing). Same effect as no prior decision.
  ///
  /// Joins `SessionCarryOver.targetName` against the sequence's
  /// `TargetHeaderNode.targetName` (case-insensitive) to resolve the
  /// Rust-side `TargetHeaderNode.id` that the BudgetRegistry keys on.
  ///
  /// Failure policy: a missing decision for a target is a no-op (the
  /// pre-flight dialog might have been dismissed); any other error is
  /// rethrown so the caller learns about misconfiguration before
  /// `sequencerStart()` runs (errors are a feature here).
  Future<void> _seedIntegrationCarryOverFromHandoff(
    NightshadeBackend backend,
    Sequence sequence,
  ) async {
    final headers = sequence.targetHeaders;
    if (headers.isEmpty) return;

    // Pull the carry-over snapshot. The provider is autoDispose +
    // FutureProvider; reading `.future` blocks until the first build
    // completes. An empty list means no prior session work to consider.
    final List<SessionCarryOver> carryOvers;
    try {
      carryOvers = await _ref.read(sessionCarryOverProvider.future);
      // A transient failure may have recovered between the pre-flight prompt
      // and executor setup. Consume the one-shot anyway and use the real data.
      if (_ref.read(sessionHandoffIgnoreUnavailableOnceProvider)) {
        _ref.read(sessionHandoffIgnoreUnavailableOnceProvider.notifier).state =
            false;
      }
    } catch (e, st) {
      // History-unavailable is not equivalent to no history. Surface it before
      // native start so a direct/API launch cannot silently reset a multi-night
      // integration budget to zero.
      if (_ref.read(sessionHandoffIgnoreUnavailableOnceProvider)) {
        _ref.read(sessionHandoffIgnoreUnavailableOnceProvider.notifier).state =
            false;
        _logger.warning(
          'Starting without session carry-over after explicit operator '
          'confirmation: $e',
          source: 'SequenceExecutor',
        );
        return;
      }
      _logger.error(
        'Failed to read session carry-over snapshot: $e',
        source: 'SequenceExecutor',
      );
      Error.throwWithStackTrace(e, st);
    }
    if (carryOvers.isEmpty) return;

    // Build a name-keyed lookup so the matching step is O(carryOvers).
    // `TargetHeaderNode.targetName` is the display name we matched
    // against in `SessionHandoffService.detectCarryOver`, so the
    // case-insensitive comparison reproduces the same join.
    final headersByName = <String, TargetHeaderNode>{};
    for (final h in headers) {
      headersByName[h.targetName.toLowerCase()] = h;
    }

    final carryOverPayload = <String, Map<String, double>>{};
    for (final entry in carryOvers) {
      final header = headersByName[entry.targetName.toLowerCase()];
      if (header == null) {
        // The carry-over targets something the current sequence does
        // not image. Skip; the operator can't have meant to seed it.
        continue;
      }
      final key = (sequenceId: sequence.databaseId, targetId: entry.targetId);
      final decision = _ref.read(sessionHandoffDecisionProvider(key));
      if (decision == null) {
        // No pre-flight decision recorded (dialog dismissed) — leave
        // the BudgetRegistry to its default zero-credit behaviour.
        continue;
      }
      switch (decision) {
        case SessionHandoffDecision.resume:
          // Copy the per-filter totals verbatim. The Rust side filters
          // non-finite / non-positive values defensively; we still
          // forward the operator's measurement honestly.
          carryOverPayload[header.id] = Map<String, double>.from(
            entry.perFilterIntegrationSecs,
          );
          break;
        case SessionHandoffDecision.restart:
          // Empty map → Rust zeroes any prior per-target state. This is
          // distinct from "omit", which would leave a stale checkpoint
          // entry untouched.
          carryOverPayload[header.id] = const <String, double>{};
          break;
        case SessionHandoffDecision.continueNew:
          // Acknowledged but not reused — neither seed nor zero.
          break;
      }
    }

    if (carryOverPayload.isEmpty) return;
    try {
      await backend.sequencerUpdatePendingIntegrationCarryOver(
        carryOverPayload,
      );
      _logger.info(
        'Staged integration carry-over for ${carryOverPayload.length} '
        'target(s) (handoff decisions applied)',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      _logger.error(
        'Failed to stage integration carry-over: $e',
        source: 'SequenceExecutor',
      );
      Error.throwWithStackTrace(e, st);
    }
  }

  /// Start watching for settings changes that should be propagated to the
  /// backend executor during sequence execution (dither config, location,
  /// filter offsets).
  void _startSettingsWatchers(NightshadeBackend backend) {
    _stopSettingsWatchers();
    // Kick off the sky-brightness poll. The first
    // tick fires 10 s after start (matching the timer cadence); the
    // first user-visible adaptive-exposure decision uses whatever the
    // tracker has at TakeExposure time.
    _startSkyBrightnessPoll(backend);

    _settingsSubscriptions.add(
      _ref.listen(sequencerDefaultsProvider, (previous, next) {
        if (previous == null) return;
        if (previous.ditherPixels != next.ditherPixels ||
            previous.ditherSettlePixels != next.ditherSettlePixels ||
            previous.ditherSettleTime != next.ditherSettleTime ||
            previous.ditherSettleTimeout != next.ditherSettleTimeout ||
            previous.ditherRaOnly != next.ditherRaOnly) {
          _logger.debug(
            'Dither settings changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateDitherConfig(
            pixels: next.ditherPixels,
            settlePixels: next.ditherSettlePixels,
            settleTime: next.ditherSettleTime,
            settleTimeout: next.ditherSettleTimeout,
            raOnly: next.ditherRaOnly,
          );
        }
      }),
    );

    _settingsSubscriptions.add(
      _ref.listen(appSettingsProvider, (previous, next) {
        final prevSettings = previous?.valueOrNull;
        final nextSettings = next.valueOrNull;
        if (prevSettings == null || nextSettings == null) return;
        if (prevSettings.latitude != nextSettings.latitude ||
            prevSettings.longitude != nextSettings.longitude) {
          _logger.debug(
            'Location changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateLocation(
            latitude: nextSettings.latitude,
            longitude: nextSettings.longitude,
          );
        }

        if (prevSettings.safetyFailMode != nextSettings.safetyFailMode) {
          _logger.debug(
            'Safety fail mode changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          // Same weather-safety guard as the start path: a mid-run switch to
          // failClosed on a rig with weather safety disabled would otherwise
          // arm the WeatherUnsafe trigger and abort the running sequence.
          _pushEffectiveSafetyFailMode(backend, nextSettings.safetyFailMode);
        }

        // Propagate image-grading changes mid-run so the next
        // exposure honours the user's new thresholds.
        final gradingChanged =
            prevSettings.enableImageGrading !=
                nextSettings.enableImageGrading ||
            prevSettings.imageGradingHfrThresholdPx !=
                nextSettings.imageGradingHfrThresholdPx ||
            prevSettings.imageGradingHfrBaselinePercent !=
                nextSettings.imageGradingHfrBaselinePercent ||
            prevSettings.imageGradingEccentricityThreshold !=
                nextSettings.imageGradingEccentricityThreshold ||
            prevSettings.imageGradingStarCountMin !=
                nextSettings.imageGradingStarCountMin ||
            prevSettings.imageGradingMaxConsecutiveRejects !=
                nextSettings.imageGradingMaxConsecutiveRejects;
        if (gradingChanged) {
          _logger.debug(
            'Image-grading settings changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateDefaultQualityCheck(
            hfrThreshold: nextSettings.imageGradingHfrThresholdPx,
            hfrBaselinePercent: nextSettings.imageGradingHfrBaselinePercent,
            eccentricityThreshold:
                nextSettings.imageGradingEccentricityThreshold,
            starCountMin: nextSettings.imageGradingStarCountMin,
            maxConsecutiveRejects:
                nextSettings.imageGradingMaxConsecutiveRejects,
            enabled: nextSettings.enableImageGrading,
          );
        }
        if (prevSettings.imageGradingRejectFolderPath !=
            nextSettings.imageGradingRejectFolderPath) {
          _logger.debug(
            'Reject folder path changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateRejectFolderPath(
            nextSettings.imageGradingRejectFolderPath,
          );
        }

        // Propagate observer name + elevation changes so FITS
        // headers stay in sync if the user edits Settings mid-run.
        if (prevSettings.observerName != nextSettings.observerName ||
            prevSettings.elevation != nextSettings.elevation) {
          _logger.debug(
            'Observer name / elevation changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          _pushObserverProfile(backend);
        }

        // Propagate global adaptive-exposure setting
        // changes so the next exposure honours the user's edit. We
        // compare all eight inputs in one pass because the executor
        // expects the full config object on every push.
        final adaptiveChanged =
            prevSettings.adaptiveExposureEnabled !=
                nextSettings.adaptiveExposureEnabled ||
            prevSettings.adaptiveExposureTargetSnr !=
                nextSettings.adaptiveExposureTargetSnr ||
            prevSettings.adaptiveExposureReferenceMag !=
                nextSettings.adaptiveExposureReferenceMag ||
            prevSettings.adaptiveExposureMinSecs !=
                nextSettings.adaptiveExposureMinSecs ||
            prevSettings.adaptiveExposureMaxSecs !=
                nextSettings.adaptiveExposureMaxSecs ||
            !mapEquals(
              prevSettings.adaptiveExposurePerFilterEnabled,
              nextSettings.adaptiveExposurePerFilterEnabled,
            ) ||
            !mapEquals(
              prevSettings.adaptiveExposurePerFilterMinSecs,
              nextSettings.adaptiveExposurePerFilterMinSecs,
            ) ||
            !mapEquals(
              prevSettings.adaptiveExposurePerFilterMaxSecs,
              nextSettings.adaptiveExposurePerFilterMaxSecs,
            );
        if (adaptiveChanged) {
          _logger.debug(
            'Adaptive-exposure settings changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          if (nextSettings.adaptiveExposureEnabled) {
            backend.sequencerUpdateDefaultAdaptiveExposure(
              enabled: nextSettings.adaptiveExposureEnabled,
              targetSnr: nextSettings.adaptiveExposureTargetSnr,
              referenceSkyBrightnessMag:
                  nextSettings.adaptiveExposureReferenceMag,
              minExposureSecs: nextSettings.adaptiveExposureMinSecs,
              maxExposureSecs: nextSettings.adaptiveExposureMaxSecs,
              perFilterEnabled: nextSettings.adaptiveExposurePerFilterEnabled,
              perFilterMinSecs: nextSettings.adaptiveExposurePerFilterMinSecs,
              perFilterMaxSecs: nextSettings.adaptiveExposurePerFilterMaxSecs,
            );
          } else {
            backend.sequencerClearDefaultAdaptiveExposure();
          }
        }
      }),
    );

    _settingsSubscriptions.add(
      _ref.listen(activeEquipmentProfileProvider, (previous, next) {
        if (previous == null || next == null) return;
        // EquipmentProfileModel.filterFocusOffsets is already a
        // Map<String,int> in memory; the legacy version of this code
        // decoded it as JSON which was a runtime bug — the analyzer now
        // catches that. Use map equality directly.
        final prevOffsets = previous.filterFocusOffsets;
        final nextOffsets = next.filterFocusOffsets;
        if (!mapEquals(prevOffsets, nextOffsets)) {
          _logger.debug(
            'Filter focus offsets changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          backend.sequencerUpdateFilterOffsets(nextOffsets);
        }

        // Propagate telescope / camera identity changes so FITS
        // headers reflect the active equipment profile mid-run (rare but
        // possible when the user swaps profiles between targets).
        if (previous.cameraName != next.cameraName ||
            previous.telescopeName != next.telescopeName ||
            previous.telescopeFocalLength != next.telescopeFocalLength ||
            previous.telescopeAperture != next.telescopeAperture ||
            previous.focalLength != next.focalLength) {
          _logger.debug(
            'Equipment profile identity changed during execution, propagating to backend',
            source: 'SequenceExecutor',
          );
          _pushObserverProfile(backend);
        }
      }),
    );
  }

  /// Helper that recomputes the observer profile from the
  /// current settings + active equipment profile and pushes it to the
  /// backend. Used by both the appSettingsProvider and
  /// activeEquipmentProfileProvider watchers because the FITS observer
  /// profile is a *cross-product* of both sources.
  void _pushObserverProfile(NightshadeBackend backend) {
    try {
      final settings = _ref.read(appSettingsProvider).valueOrNull;
      final profile = _ref.read(activeEquipmentProfileProvider);

      String? cameraMake;
      String? cameraModel;
      final rawCameraName = profile?.cameraName?.trim();
      if (rawCameraName != null && rawCameraName.isNotEmpty) {
        final spaceIdx = rawCameraName.indexOf(' ');
        if (spaceIdx > 0) {
          cameraMake = rawCameraName.substring(0, spaceIdx).trim();
          cameraModel = rawCameraName.substring(spaceIdx + 1).trim();
        } else {
          cameraModel = rawCameraName;
        }
      }

      double? focalLength;
      double? aperture;
      if (profile != null) {
        final tfl = profile.telescopeFocalLength;
        final fl = profile.focalLength;
        if (tfl != null && tfl > 0) {
          focalLength = tfl;
        } else if (fl > 0) {
          focalLength = fl;
        }

        // Aperture needs the SAME legacy fallback as focal length above: a
        // profile built through the generic optics fields has
        // telescopeAperture == 0 and the real value in `aperture`, so reading
        // only telescopeAperture dropped it and every frame was written with
        // FOCALLEN but no APTDIA — an aperture the operator had configured,
        // missing from the FITS header that photometry reads.
        final ta = profile.telescopeAperture;
        final ap = profile.aperture;
        if (ta != null && ta > 0) {
          aperture = ta;
        } else if (ap > 0) {
          aperture = ap;
        }
      }

      backend.sequencerUpdateObserverProfile(
        observerName: (settings == null || settings.observerName.isEmpty)
            ? null
            : settings.observerName,
        siteElevationM: (settings != null && settings.elevation > 0)
            ? settings.elevation
            : null,
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        telescopeName: profile?.telescopeName,
        telescopeFocalLengthMm: focalLength,
        telescopeApertureMm: aperture,
      );
    } catch (e) {
      _logger.error(
        'Failed to propagate observer_profile mid-run: $e',
        source: 'SequenceExecutor',
      );
    }
  }

  void _stopSettingsWatchers() {
    for (final sub in _settingsSubscriptions) {
      sub.close();
    }
    _settingsSubscriptions.clear();
    // Tear down the sky-brightness poll so a stopped
    // executor stops pushing readings to the (possibly torn-down)
    // backend.
    _skyBrightnessPollTimer?.cancel();
    _skyBrightnessPollTimer = null;
    _lastPushedSkyMag = null;
  }

  /// Start the periodic poll that watches the
  /// `SkyBrightnessTracker` and pushes its mag/arcsecÂ² reading to the
  /// executor whenever it changes. Suppresses redundant pushes so the
  /// runtime config event stream stays quiet under steady conditions.
  void _startSkyBrightnessPoll(NightshadeBackend backend) {
    _skyBrightnessPollTimer?.cancel();
    // Capture the logger ONCE, here. It is a provider read, and the tick below
    // outlives the container: reading it from inside the catch block meant the
    // error handler ITSELF threw ("Tried to read a provider from a
    // ProviderContainer that was already disposed"), escaping the try and
    // surfacing as an unhandled async error every 10 seconds. A catch that can
    // throw is not a guard. Same idiom the frame-registration path already uses.
    final logger = _logger;
    _skyBrightnessPollTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) {
      // Self-cancel if the executor went away between ticks, so a leaked timer
      // can never keep touching a torn-down Ref.
      if (_disposed) {
        timer.cancel();
        return;
      }
      try {
        final tracker = _ref.read(skyBrightnessTrackerProvider);
        final mag = tracker.currentMagPerArcsec2();
        // Throttle on absolute change > 0.05 mag/arcsecÂ²; smaller
        // wobble is observational noise that the adapter doesn't need
        // to see on every tick.
        if (mag != _lastPushedSkyMag) {
          final changed =
              _lastPushedSkyMag == null ||
              mag == null ||
              (mag - (_lastPushedSkyMag ?? 0)).abs() > 0.05;
          if (changed) {
            _lastPushedSkyMag = mag;
            backend.sequencerUpdateSkyBrightness(mag: mag);
            logger.debug(
              'Pushed sky brightness to executor: ${mag?.toStringAsFixed(2) ?? "<none>"} mag/arcsecÂ²',
              source: 'SequenceExecutor',
            );
          }
        }
      } catch (e) {
        // Don't let a tracker read failure kill the periodic timer —
        // log and keep going. "Errors are a feature" applies to user-
        // visible faults; this is best-effort telemetry.
        logger.debug(
          'Sky brightness poll failed: $e',
          source: 'SequenceExecutor',
        );
      }
    });
  }

  /// Handle events from the backend (native or remote)
}
