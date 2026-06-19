part of '../sequence_executor.dart';

extension _SequenceExecutorSessionDiagnosticsOperations on SequenceExecutor {
  void _captureSessionStartHooks(String sequenceId) {
    _activeSequenceId = sequenceId;
    _sessionStartedAt = DateTime.now();

    // --- Notification router active-sequence override -----------------
    try {
      final router = _ref.read(notificationRouterProvider);
      router.setActiveSequence(sequenceId);
      _logger.debug(
        'NotificationRouter.setActiveSequence($sequenceId) at session start',
        source: 'SequenceExecutor',
      );
    } catch (e, st) {
      // Notification setup failure must never block imaging — log and
      // continue. The user gets a working sequence with global routing
      // rules instead of per-sequence overrides.
      _logger.warning(
        'Failed to register active sequence with NotificationRouter: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // --- Optical-train baseline capture -------------------------------
    try {
      final baseline = _captureOpticalTrainBaseline();
      if (baseline == null) {
        _logger.info(
          'Optical-train diagnostics unavailable at session start '
          '(no PSF tiles or solved frames yet); baseline will be '
          'captured at session end instead.',
          source: 'SequenceExecutor',
        );
      } else {
        _sessionStartBaseline = baseline;
        // Push to both the baseline provider (pre-flight comparison
        // source) and the current-snapshot provider (so the live
        // dashboard reflects the start-of-run state until a fresh
        // snapshot supersedes it mid-run).
        _ref.read(opticalTrainBaselineProvider.notifier).state = baseline;
        _ref.read(opticalTrainCurrentSnapshotProvider.notifier).state =
            baseline;
        _logger.debug(
          'Captured optical-train baseline at session start: '
          'tilt=${baseline.tiltScore.toStringAsFixed(1)}, '
          'collimation=${baseline.collimationScore.toStringAsFixed(1)}',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to capture optical-train baseline at session start: $e\n$st',
        source: 'SequenceExecutor',
      );
    }
  }

  /// Finalize post-session diagnostics + clear the notification router
  /// override at session end.
  ///
  /// Called exactly once per run via `_finalizeRun`. Safe to call when
  /// session hooks never fired (e.g. start failed mid-way): the
  /// `_activeSequenceId` guard short-circuits cleanly.
  void _captureSessionEndHooks() {
    final sequenceId = _activeSequenceId;
    final sessionStart = _sessionStartedAt;

    if (sequenceId == null) {
      // start() never finished its hooks (the run aborted before the
      // session-start phase). Nothing to tear down.
      _logger.debug(
        'Skipping session-end hooks: no active sequence id recorded',
        source: 'SequenceExecutor',
      );
      return;
    }

    // --- Notification router clear --------------------------------------
    try {
      final router = _ref.read(notificationRouterProvider);
      router.setActiveSequence(null);
      _logger.debug(
        'NotificationRouter.setActiveSequence(null) at session end '
        '(was: $sequenceId)',
        source: 'SequenceExecutor',
      );
    } catch (e) {
      _logger.warning(
        'Failed to clear active sequence on NotificationRouter: $e',
        source: 'SequenceExecutor',
      );
    }

    // --- Optical-train post-session snapshot + drift ------------------
    OpticalTrainBaseline? postSnapshot;
    try {
      postSnapshot = _captureOpticalTrainBaseline();
      if (postSnapshot != null) {
        _ref.read(opticalTrainCurrentSnapshotProvider.notifier).state =
            postSnapshot;
        // Promote the post-session snapshot to the new baseline for
        // the NEXT session's pre-flight comparison. Without this the
        // baseline would keep pointing at the start of the just-
        // finished run, so the second session would see no drift.
        _ref.read(opticalTrainBaselineProvider.notifier).state = postSnapshot;
        if (_sessionStartBaseline != null) {
          final drift = _sessionStartBaseline!.driftAgainst(
            OpticalTrainDiagnostics(
              tiltScore: postSnapshot.tiltScore,
              collimationScore: postSnapshot.collimationScore,
              dominantTiltDirection: 'unknown',
              issues: const [],
            ),
          );
          _logger.info(
            'Optical-train drift vs. session-start baseline: '
            '${drift.toStringAsFixed(2)} (tilt '
            '${_sessionStartBaseline!.tiltScore.toStringAsFixed(1)} → '
            '${postSnapshot.tiltScore.toStringAsFixed(1)}, '
            'collimation '
            '${_sessionStartBaseline!.collimationScore.toStringAsFixed(1)} → '
            '${postSnapshot.collimationScore.toStringAsFixed(1)})',
            source: 'SequenceExecutor',
          );
        }
        _logger.debug(
          'Captured optical-train post-session snapshot: '
          'tilt=${postSnapshot.tiltScore.toStringAsFixed(1)}, '
          'collimation=${postSnapshot.collimationScore.toStringAsFixed(1)}',
          source: 'SequenceExecutor',
        );
      } else {
        // No live PSF/residual data at session end — fall back to the
        // start-of-session baseline (if we captured one) so the
        // dashboard's current snapshot at least shows the entry
        // state instead of stale data from a previous run.
        if (_sessionStartBaseline != null) {
          _ref.read(opticalTrainCurrentSnapshotProvider.notifier).state =
              _sessionStartBaseline;
        }
        _logger.info(
          'Optical-train diagnostics unavailable at session end; '
          'post-session diagnostics will omit drift comparison.',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to capture optical-train post-session snapshot: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // --- Post-session health summary ---------------------------------
    try {
      final dbSessionId = _ref.read(sessionStateProvider).dbSessionId;
      if (dbSessionId == null) {
        _logger.info(
          'No active database session id at end of run; '
          'post-session diagnostics summary will not be published.',
          source: 'SequenceExecutor',
        );
      } else {
        final summary = _buildPostSessionHealthSummary(
          sessionStartedAt: sessionStart,
        );
        _ref
                .read(postSessionHealthSummaryProvider(dbSessionId).notifier)
                .state =
            summary;
        _logger.debug(
          'Published post-session diagnostics for session $dbSessionId: '
          'disconnects=${summary.disconnectsDuringSession}, '
          'focuserMoves=${summary.focuserMoves}, '
          'noticedConcerns=${summary.noticedConcerns.length}',
          source: 'SequenceExecutor',
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to publish post-session diagnostics: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // --- Per-session diagnostics persistence --------------------------
    // Recovery history + optical-train baseline/current live only in
    // volatile in-memory providers, which the NEXT run overwrites. Persist
    // them keyed to this session so a historical run report can reload THAT
    // session's recoveries and drift comparison instead of the live values.
    try {
      final dbSessionId = _ref.read(sessionStateProvider).dbSessionId;
      if (dbSessionId != null) {
        final recoveries = _ref.read(recoveryHistoryProvider);
        final recoveryHistoryJson = jsonEncode(
          recoveries.map((e) => e.toJson()).toList(),
        );
        final baselineJson = _sessionStartBaseline == null
            ? null
            : jsonEncode(_sessionStartBaseline!.toJson());
        final currentJson = postSnapshot == null
            ? null
            : jsonEncode(postSnapshot.toJson());
        // Resolve the logger synchronously, while the container is still
        // alive. The deferred catchError below runs after this method has
        // returned, by which point `_ref` may already be disposed (e.g. on
        // app shutdown right after a session ends) — re-reading a provider
        // from a disposed container would throw inside the async zone.
        final logger = _logger;
        unawaited(
          _ref
              .read(sessionDiagnosticsDaoProvider)
              .upsert(
                sessionId: dbSessionId,
                recoveryHistoryJson: recoveryHistoryJson,
                opticalTrainBaselineJson: baselineJson,
                opticalTrainCurrentJson: currentJson,
              )
              .catchError((Object e, StackTrace st) {
                logger.warning(
                  'Failed to persist per-session diagnostics: $e\n$st',
                  source: 'SequenceExecutor',
                );
              }),
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to schedule per-session diagnostics persistence: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // --- Smart Night guide-RMS history --------------------------------
    try {
      final dbSessionId = _ref.read(sessionStateProvider).dbSessionId;
      if (dbSessionId != null) {
        final mountState = _ref.read(mountStateProvider);
        final profileMountId = _ref
            .read(activeEquipmentProfileProvider)
            ?.mountId;
        final mountId =
            mountState.connectionState == DeviceConnectionState.connected
            ? mountState.deviceId
            : profileMountId;
        final collector = GuideRmsCollector(
          imagesDao: _ref.read(imagesDaoProvider),
          guideRmsHistoryDao: _ref.read(guideRmsHistoryDaoProvider),
        );
        // Resolve the logger synchronously (see note above): the deferred
        // catchError must not re-read from a possibly-disposed `_ref`.
        final logger = _logger;
        unawaited(
          collector
              .collectSession(
                sessionId: dbSessionId,
                mountId: mountId,
                recordedAt: DateTime.now(),
              )
              .catchError((Object e, StackTrace st) {
                logger.warning(
                  'Failed to collect Smart Night guide-RMS history: $e\n$st',
                  source: 'SequenceExecutor',
                );
                return null;
              }),
        );
      }
    } catch (e, st) {
      _logger.warning(
        'Failed to schedule Smart Night guide-RMS collection: $e\n$st',
        source: 'SequenceExecutor',
      );
    }

    // Reset for the next run. Don't clear `_sessionStartBaseline`
    // until here so the post-session hook above could reference it.
    _activeSequenceId = null;
    _sessionStartedAt = null;
    _sessionStartBaseline = null;
  }

  /// Snapshot the live optical-train diagnostics for the active session
  /// and convert to an [OpticalTrainBaseline]. Returns `null` when no
  /// diagnostics data is available (no solved frames yet, no PSF
  /// tiles, no live session).
  ///
  /// Uses the same data path as the analytics tab so the values shown
  /// in the History dialog match the live dashboard — pulled directly
  /// from the PSF / residual provider streams rather than re-running
  /// the analysis on raw FITS files.
  OpticalTrainBaseline? _captureOpticalTrainBaseline() {
    final dbSessionId = _ref.read(sessionStateProvider).dbSessionId;
    if (dbSessionId == null) return null;
    final psfTiles =
        _ref.read(sessionPsfTilesProvider(dbSessionId)).valueOrNull ?? const [];
    final residuals =
        _ref.read(sessionResidualVectorsProvider(dbSessionId)).valueOrNull ??
        const [];
    if (psfTiles.isEmpty) {
      // Nothing solved yet — calling analyze() would emit the
      // "No diagnostics data" placeholder, which has tilt=0 and
      // collimation=0 and would look like a "zero drift" baseline.
      // Returning null preserves the honest "no data" signal.
      return null;
    }
    final service = _ref.read(opticalTrainDiagnosticsServiceProvider);
    final diagnostics = service.analyze(
      psfTiles: psfTiles,
      residualVectors: residuals,
    );
    return OpticalTrainBaseline.fromDiagnostics(diagnostics);
  }

  /// Build the post-session diagnostics summary from the run stats +
  /// USB disconnect log.
  ///
  /// The summary surfaces:
  ///   * USB disconnects that occurred during this run (not the rolling
  ///     24 h window — the user already saw earlier flakes the last time
  ///     they opened the report).
  ///   * Total focuser moves recorded across the run (sourced from
  ///     `liveSequenceStatsProvider.autofocusRuns` — an autofocus run
  ///     equals N moves of the focuser).
  ///   * Verbatim warning messages collected by `SequenceRunStats`
  ///     during the run, including filter-lookup fallbacks and any
  ///     other "noticed but did not fire" concerns the executor saw.
  ///
  ///   * Cooler temperature samples outside the setpoint band.
  ///   * Sky-brightness min / max / median from the adaptive-exposure
  ///     tracker's calibrated mag/arcsecÂ² samples.
  PostSessionHealthSummary _buildPostSessionHealthSummary({
    DateTime? sessionStartedAt,
  }) {
    final stats = _ref.read(liveSequenceStatsProvider);
    final disconnectLog = _ref.read(usbDisconnectLogProvider);

    final disconnectsDuringSession = sessionStartedAt == null
        ? disconnectLog.totalLast24h()
        : disconnectLog.countSince(sessionStartedAt);

    final focuserMoves = stats?.autofocusRuns ?? 0;

    final noticedConcerns = <String>[];
    if (stats != null) {
      // Warnings collected via SequenceRunStats.recordWarning are
      // already deduplicated against consecutive identical messages,
      // so we surface them as-is.
      noticedConcerns.addAll(stats.warningMessages);
    }

    final skyStats = _skyBrightnessSummarySince(sessionStartedAt);

    return PostSessionHealthSummary(
      disconnectsDuringSession: disconnectsDuringSession,
      coolerOutOfBandSamples: _coolerOutOfBandSamplesSince(sessionStartedAt),
      focuserMoves: focuserMoves,
      skyBrightnessMin: skyStats?.min,
      skyBrightnessMax: skyStats?.max,
      skyBrightnessMedian: skyStats?.median,
      noticedConcerns: noticedConcerns,
    );
  }

  int _coolerOutOfBandSamplesSince(DateTime? sessionStartedAt) {
    final history = _ref.read(temperatureHistoryProvider);
    var count = 0;
    for (final point in history) {
      if (sessionStartedAt != null && point.time.isBefore(sessionStartedAt)) {
        continue;
      }
      final target = point.targetTemp;
      if (target == null) continue;
      if ((point.temperature - target).abs() > kCoolerSetpointBandDegC) {
        count++;
      }
    }
    return count;
  }

  ({double min, double max, double median})? _skyBrightnessSummarySince(
    DateTime? sessionStartedAt,
  ) {
    final samples =
        _ref
            .read(skyBrightnessTrackerProvider)
            .magSamplesSince(sessionStartedAt)
            .where((value) => value.isFinite)
            .toList()
          ..sort();
    if (samples.isEmpty) return null;

    final mid = samples.length ~/ 2;
    final median = samples.length.isOdd
        ? samples[mid]
        : (samples[mid - 1] + samples[mid]) / 2.0;
    return (min: samples.first, max: samples.last, median: median);
  }

  /// Fetch the last captured image and update the UI providers so the Imaging
  /// tab and Dashboard show sequence frames as they complete.
  void _fetchAndDisplaySequenceImage(double durationSecs) {
    // Fire-and-forget; image display is non-critical for sequence correctness.
    Future(() async {
      try {
        final cameraState = _ref.read(cameraStateProvider);
        final cameraDeviceId = cameraState.deviceId;
        if (cameraDeviceId == null || cameraDeviceId.isEmpty) {
          _logger.debug(
            'No camera device ID available, skipping image fetch',
            source: 'SequenceExecutor',
          );
          return;
        }
        final backend = _ref.read(backendProvider);
        final capturedImage = await backend.cameraGetLastImage(cameraDeviceId);
        if (capturedImage == null) {
          _logger.debug(
            'No image data available from camera',
            source: 'SequenceExecutor',
          );
          return;
        }

        final imageData = capturedImageDataFromResult(
          capturedImage: capturedImage,
          capturedAt: DateTime.now(),
          settings: ExposureSettings(
            exposureTime: durationSecs,
            gain: 0, // Not available from sequence event
            offset: 0,
            binningX: 1,
            binningY: 1,
            frameType: FrameType.light,
          ),
        );

        _ref
            .read(capturePreviewPublisherProvider)
            .publish(_ref, imageData, cameraDeviceId);
      } catch (e) {
        // Image display is non-critical; log only.
        _logger.warning(
          'Failed to fetch sequence image for display: $e',
          source: 'SequenceExecutor',
        );
      }
    });
  }
}
