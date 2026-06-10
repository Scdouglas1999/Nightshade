part of '../sequence_executor.dart';

extension _SequenceExecutorEventOperations on SequenceExecutor {
  void _handleSequencerEvent(NightshadeEvent event) {
    _logger.debug(
      'Received event: type=${event.eventType}, category=${event.category}',
      source: 'SequenceExecutor',
    );

    // Handle imaging events for image preview during sequences.
    // This MUST be before the category filter since ExposureComplete has
    // category=imaging.
    if (event.category == EventCategory.imaging &&
        event.eventType == 'ExposureComplete') {
      _logger.debug(
        'ExposureComplete imaging event received - fetching image for preview',
        source: 'SequenceExecutor',
      );
      final durationSecs =
          (event.data['duration_secs'] as num?)?.toDouble() ?? 2.0;
      _fetchAndDisplaySequenceImage(durationSecs);
      return;
    }

    // Only process sequencer events for progress tracking
    if (event.category != EventCategory.sequencer) return;

    final progressNotifier = _ref.read(sequenceProgressProvider.notifier);

    switch (event.eventType) {
      case 'NodeStarted':
        final nodeId =
            event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
        final nodeName =
            event.data['node_type'] as String? ??
            event.data['nodeName'] as String?;
        if (nodeId != null) {
          progressNotifier.updateProgress(
            currentNodeId: nodeId,
            currentNodeName: nodeName,
            currentNodeStatus: NodeStatus.running,
          );
          progressNotifier.updateNodeStatus(nodeId, NodeStatus.running);
        }
        break;

      case 'NodeCompleted':
        final nodeId =
            event.data['node_id'] as String? ?? event.data['nodeId'] as String?;
        final statusStr = event.data['status'] as String? ?? 'failed';
        final nodeStatus = switch (statusStr) {
          'success' => NodeStatus.success,
          'skipped' => NodeStatus.skipped,
          'cancelled' => NodeStatus.skipped,
          _ => NodeStatus.failure,
        };
        if (nodeId != null) {
          progressNotifier.updateNodeStatus(nodeId, nodeStatus);
        }
        break;

      case 'ExposureStarted':
        final frame = event.data['frame'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 0;
        final filter = event.data['filter'] as String?;
        final exposureDetail =
            'Frame $frame/$total${filter != null ? ' ($filter)' : ''}';
        progressNotifier.updateProgress(
          message: 'Exposing $exposureDetail',
          currentFilter: filter,
        );
        final exposureNodeId = _ref
            .read(sequenceProgressProvider)
            .currentNodeId;
        if (exposureNodeId != null && total > 0) {
          // frame-1 because exposure just started
          final exposurePercent = (frame - 1) / total * 100.0;
          progressNotifier.updateNodeProgress(
            exposureNodeId,
            exposurePercent,
            exposureDetail,
          );
        }
        break;

      case 'ExposureCompleted':
        final frame = event.data['frame'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 1;
        final durationSecs =
            (event.data['duration_secs'] as num?)?.toDouble() ?? 0.0;
        _recordRunFrame(
          exposureSecs: durationSecs,
          filter: event.data['filter'] as String?,
          accepted: true,
        );
        final newCompletedIntegration =
            _ref.read(sequenceProgressProvider).completedIntegrationSecs +
            durationSecs;
        progressNotifier.updateProgress(
          completedExposures: frame,
          completedIntegrationSecs: newCompletedIntegration,
        );
        final completedNodeId = _ref
            .read(sequenceProgressProvider)
            .currentNodeId;
        if (completedNodeId != null) {
          final completedPercent = total > 0 ? (frame / total * 100.0) : 100.0;
          progressNotifier.updateNodeProgress(
            completedNodeId,
            completedPercent,
            'Completed $frame/$total',
          );
        }

        _fetchAndDisplaySequenceImage(durationSecs);
        break;

      case 'Progress':
        final current = event.data['current'] as int? ?? 0;
        final total = event.data['total'] as int? ?? 0;
        progressNotifier.updateProgress(
          completedExposures: current,
          message: 'Progress: $current/$total exposures',
        );
        break;

      case 'TargetStarted':
      case 'TargetChanged':
        final name =
            event.data['target_name'] as String? ??
            event.data['name'] as String?;
        final ra = (event.data['ra'] as num?)?.toDouble();
        final dec = (event.data['dec'] as num?)?.toDouble();
        progressNotifier.updateProgress(
          currentTarget: name,
          message: name != null ? 'Started target: $name' : null,
        );
        if (name != null && ra != null && dec != null) {
          _logger.debug(
            'Target changed: $name (RA=${ra.toStringAsFixed(4)}h, Dec=${dec.toStringAsFixed(4)}°)',
            source: 'SequenceExecutor',
          );
          final sessionNotifier = _ref.read(sessionStateProvider.notifier);
          sessionNotifier.updateTargetCoordinates(ra: ra, dec: dec);
        }
        break;

      case 'TargetCompleted':
        final name =
            event.data['target_name'] as String? ??
            event.data['name'] as String?;
        progressNotifier.updateProgress(
          message: 'Completed target: ${name ?? 'unknown'}',
        );
        break;

      case 'Error':
        final message = event.data['message'] as String? ?? 'Unknown error';
        _recordRunError(message);
        progressNotifier.updateProgress(message: 'Error: $message');
        final errorNodeId = _ref.read(sequenceProgressProvider).currentNodeId;
        if (errorNodeId != null) {
          progressNotifier.updateNodeProgress(
            errorNodeId,
            0.0,
            'Error: $message',
          );
        }
        break;

      case 'InstructionProgressStructured':
        final nodeId = event.data['node_id'] as String?;
        final instruction = event.data['instruction'] as String? ?? '';
        final progressPercent =
            (event.data['progress_percent'] as num?)?.toDouble() ?? 0.0;
        final detailKind = event.data['detail_kind'] as String? ?? 'Unknown';
        final detailJson = _decodeStructuredProgressJson(
          event.data['detail_json'],
        );
        final detail = InstructionProgressDetail.fromStructuredData(
          detailKind: detailKind,
          detailJson: detailJson,
        );

        final targetNodeId =
            nodeId ?? _ref.read(sequenceProgressProvider).currentNodeId;
        if (targetNodeId != null) {
          progressNotifier.updateNodeStructuredProgress(
            targetNodeId,
            progressPercent,
            detail,
          );
          progressNotifier.updateProgress(message: '$instruction: $detailKind');
        }
        break;

      case 'InstructionProgress':
        final nodeId = event.data['node_id'] as String?;
        final instruction = event.data['instruction'] as String? ?? '';
        final progressPercent =
            (event.data['progress_percent'] as num?)?.toDouble() ?? 0.0;
        final detail = event.data['detail'] as String? ?? '';

        _logger.debug(
          'InstructionProgress: nodeId=$nodeId, instruction=$instruction, progress=$progressPercent%, detail=$detail',
          source: 'SequenceExecutor',
        );

        // Use node_id from event, fallback to currentNodeId for backwards compatibility
        final targetNodeId =
            nodeId ?? _ref.read(sequenceProgressProvider).currentNodeId;
        _logger.debug(
          'Updating node progress for: $targetNodeId',
          source: 'SequenceExecutor',
        );
        if (targetNodeId != null) {
          progressNotifier.updateNodeProgress(
            targetNodeId,
            progressPercent,
            detail,
          );
          progressNotifier.updateProgress(message: '$instruction: $detail');
        }
        break;

      case 'TriggerFired':
        final triggerName =
            event.data['trigger_name'] as String? ?? 'Unknown trigger';
        final action = event.data['action'] as String? ?? '';
        _incrementRunStat((stats) => stats.recordTriggerFire());
        _logger.info(
          'Trigger fired: $triggerName -> $action',
          source: 'SequenceExecutor',
        );
        progressNotifier.updateProgress(
          message: 'Trigger "$triggerName" fired: $action',
        );
        break;

      case 'Started':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        break;

      case 'Paused':
        progressNotifier.updateState(SequenceExecutionState.paused);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.paused;
        break;

      case 'Resumed':
        progressNotifier.updateState(SequenceExecutionState.running);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.running;
        break;

      case 'Completed':
      case 'SequenceCompleted':
        _progressTimer?.cancel();
        _stopSettingsWatchers();
        _finalizeRun('completed');
        unawaited(_teardownLiveStacking());
        progressNotifier.updateState(SequenceExecutionState.completed);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.completed;
        break;

      case 'SequenceFailed':
        final error = event.data['error'] as String? ?? 'Unknown error';
        _stopSettingsWatchers();
        _recordRunError(error);
        _finalizeRun('failed');
        unawaited(_teardownLiveStacking());
        progressNotifier.updateProgress(message: error);
        progressNotifier.updateState(SequenceExecutionState.failed);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.failed;
        break;

      case 'Stopped':
      case 'SequenceStopped':
        _progressTimer?.cancel();
        _stopSettingsWatchers();
        _finalizeRun('stopped');
        unawaited(_teardownLiveStacking());
        progressNotifier.updateState(SequenceExecutionState.idle);
        _ref.read(sequenceExecutionStateProvider.notifier).state =
            SequenceExecutionState.idle;
        break;

      case 'FrameAccepted':
        // Wave 6 Pack P — the Rust grader now ships `save_path` for
        // accepted frames as well (it already did for rejected
        // frames). The thumbnail strip uses the on-disk path to load
        // an inline preview the same way it does for rejected frames
        // via `reject_path`.
        _registerSequenceFrame(event: event, isAccepted: true, grade: 'pass');
        // 2026-06-04 follow-up — auto-feed live stacking. When the
        // running sequence contains an enabled LiveStackingNode, every
        // accepted frame is fed into the live stacker + LAN broadcast
        // (the first becomes the reference automatically). Manual mode
        // still requires a hand-picked reference; this is the
        // unattended-run path.
        _maybeFeedLiveStacking(event);
        break;

      case 'FrameRejected':
        // Wave 6 Thumbnails — same as FrameAccepted, but with the
        // reject_path the Rust grader already ships so the strip can
        // surface a "REJECTED" tile that opens the actual file when
        // tapped.
        _registerSequenceFrame(
          event: event,
          isAccepted: false,
          grade: 'reject',
        );
        break;

      case 'PluginNodeRequested':
        // Wave 6 Pack P — the Rust executor reached a
        // `NodeType::PluginNode` and is waiting for us to run the
        // plugin and reply with the verdict. Route through the
        // dispatcher provider (overridden by the app layer to plug in
        // the real `PluginNodeExecutor`); the default stub fails
        // loudly so an un-wired environment surfaces immediately
        // instead of hanging until Rust's 10-minute timeout.
        _dispatchPluginNode(event);
        break;

      case 'PluginNodeProgress':
        // Wave 6 Pack P — informational; plugin-authored intermediate
        // progress payload. The run dashboard's plugin-node panel
        // listens via its own provider; the sequence executor just
        // logs it so the timeline has the breadcrumb.
        final pluginId = event.data['plugin_id'] as String? ?? '';
        final nodeTypeId = event.data['node_type_id'] as String? ?? '';
        final detailJson = event.data['detail_json'] as String? ?? '';
        _logger.debug(
          'PluginNodeProgress: $pluginId/$nodeTypeId $detailJson',
          source: 'SequenceExecutor',
        );
        break;

      case 'DecisionLogged':
        // Wave 8 Replay Debug — persist the structured decision into
        // the `sequence_decisions` Drift table so the Replay screen
        // can scrub through the run later.
        _persistReplayDecision(event);
        break;
    }
  }

  /// Wave 8 Replay Debug — persist a `DecisionLogged` payload into
  /// the `sequence_decisions` table via the [ReplayDebugService].
  /// `unawaited` because the executor's event loop must keep pumping;
  /// the service handles its own change-notification, and a write
  /// failure is logged at warn-level (loud-fail per CLAUDE.md without
  /// taking the executor down).
  Object? _decodeStructuredProgressJson(Object? raw) {
    if (raw is String) {
      if (raw.trim().isEmpty) return const <String, Object?>{};
      try {
        return jsonDecode(raw);
      } catch (_) {
        return {'raw': raw};
      }
    }
    return raw;
  }

  void _persistReplayDecision(NightshadeEvent event) {
    final timestampIso = event.data['timestamp_iso'] as String? ?? '';
    final category = event.data['category'] as String? ?? '';
    final summary = event.data['summary'] as String? ?? '';
    final detailsJson = event.data['details_json'] as String? ?? '{}';
    final nodeId = event.data['node_id'] as String?;
    final rustRunId = event.data['sequence_run_id'] as int?;
    final effectiveRunId = rustRunId ?? _ref.read(currentRunIdProvider);
    if (effectiveRunId == null) {
      // No active run id — the very first lifecycle "Sequence started"
      // decision falls into this window before the Dart row insert
      // completes. We intentionally drop these so the replay log never
      // has dangling rows that can't be joined back to a run.
      _logger.debug(
        'DecisionLogged dropped: no active sequence_run_id '
        '($category: $summary)',
        source: 'SequenceExecutor',
      );
      return;
    }
    final service = _ref.read(replayDebugServiceProvider);
    unawaited(
      service
          .persistFromBridgeEvent(
            timestampIso: timestampIso,
            categoryWireKey: category,
            summary: summary,
            detailsJson: detailsJson,
            nodeId: nodeId,
            sequenceRunId: effectiveRunId,
          )
          .catchError((Object e, StackTrace st) {
            _logger.warning(
              'Failed to persist replay decision ($category: $summary): $e',
              source: 'SequenceExecutor',
            );
            return -1;
          }),
    );
  }

  /// Wave 6 Pack P — route a `PluginNodeRequested` event into the
  /// configured dispatcher and post the verdict back through the
  /// bridge.
  ///
  /// Implementation contract:
  ///   * The dispatcher MUST not throw. If it does (e.g. provider
  ///     overrides went wrong), we still post a failure verdict so
  ///     the executor unblocks instead of timing out at the 10-minute
  ///     default.
  ///   * The verdict is posted via
  ///     `backend.sequencerPluginNodeFinished` — same channel pattern
  ///     as every other sequencer command.
  ///   * We fire-and-forget; the caller (`_handleSequencerEvent`)
  ///     returns immediately so other events keep flowing.
  void _dispatchPluginNode(NightshadeEvent event) {
    final nodeId = event.data['node_id'] as String? ?? '';
    final pluginId = event.data['plugin_id'] as String? ?? '';
    final nodeTypeId = event.data['node_type_id'] as String? ?? '';
    final configJson = event.data['config_json'] as String? ?? '';
    final displayName = event.data['display_name'] as String?;
    final timeoutSecs = event.data['timeout_secs'] as int? ?? 600;

    if (nodeId.isEmpty) {
      _logger.warning(
        'PluginNodeRequested event missing node_id; cannot dispatch '
        '(plugin=$pluginId, node_type=$nodeTypeId)',
        source: 'SequenceExecutor',
      );
      return;
    }

    final backend = _ref.read(backendProvider);
    if (!backend.dispatchPluginNodesLocally) {
      _logger.debug(
        'PluginNodeRequested ignored locally because the backend '
        'delegates plugin dispatch to the remote host '
        '(plugin=$pluginId, node_type=$nodeTypeId, node_id=$nodeId)',
        source: 'SequenceExecutor',
      );
      return;
    }

    final coordinator = _ref.read(pluginNodeDispatchCoordinatorProvider);
    if (!coordinator.claim(nodeId)) {
      _logger.debug(
        'PluginNodeRequested ignored because another local listener is '
        'already dispatching node_id=$nodeId',
        source: 'SequenceExecutor',
      );
      return;
    }
    final dispatcher = _ref.read(pluginNodeDispatcherProvider);

    unawaited(() async {
      late PluginNodeDispatchResult result;
      try {
        result = await dispatcher(
          PluginNodeDispatchRequest(
            nodeId: nodeId,
            pluginId: pluginId,
            nodeTypeId: nodeTypeId,
            configJson: configJson,
            displayName: displayName,
            timeoutSecs: timeoutSecs,
          ),
        );
      } catch (e, st) {
        _logger.error(
          'Plugin node dispatcher threw for $pluginId/$nodeTypeId '
          '(node_id=$nodeId): $e\n$st',
          source: 'SequenceExecutor',
        );
        result = PluginNodeDispatchResult(
          success: false,
          message: 'dispatcher threw: $e',
        );
      }

      try {
        await backend.sequencerPluginNodeFinished(
          nodeId: nodeId,
          success: result.success,
          message: result.message,
          structuredDetailJson: result.structuredDetailJson,
        );
      } catch (e, st) {
        // The reply itself failed. The Rust executor will time out
        // the node at the configured timeout and surface its own
        // error — but we log loudly here so the operator sees the
        // cause-of-cause.
        _logger.error(
          'Failed to deliver plugin node verdict for $pluginId/$nodeTypeId '
          '(node_id=$nodeId): $e\n$st',
          source: 'SequenceExecutor',
        );
      } finally {
        coordinator.release(nodeId);
      }
    }());
  }

  /// Wave 6 Thumbnails — translate a typed FrameAccepted / FrameRejected
  /// event into a captured_images row tagged with the producing node id.
  /// Fire-and-forget; failures are logged so the strip's "errors are a
  /// feature" contract holds, but they never block the run.
  void _registerSequenceFrame({
    required NightshadeEvent event,
    required bool isAccepted,
    required String grade,
  }) {
    final nodeId = event.data['node_id'] as String?;
    if (nodeId == null || nodeId.isEmpty) {
      // No producing node — typically a wizard-driven capture (flat
      // wizard, polar-align). Nothing for the sequence-tree strip to
      // hang the row off of, so we skip.
      return;
    }
    final hfr = (event.data['hfr'] as num?)?.toDouble();
    final eccentricity = (event.data['eccentricity'] as num?)?.toDouble();
    final starCount = event.data['star_count'] as int?;
    // Wave 6 Pack P — accepted frames now carry the on-disk save_path
    // alongside the existing rejected-frame reject_path. The thumbnail
    // strip uses whichever field is populated to load the inline
    // preview. `save_path` may legitimately be null on legacy emit
    // sites that did not thread the path through (defaulting to empty
    // string preserves the old "no thumbnail yet" colour-bordered
    // tile fallback rather than skipping the row entirely).
    final filePath = isAccepted
        ? (event.data['save_path'] as String? ?? '')
        : (event.data['reject_path'] as String? ?? '');
    final fileName = filePath.isEmpty ? '' : p.basename(filePath);
    final rejectionReason = isAccepted
        ? null
        : (event.data['reason'] as String?);
    final progress = _ref.read(sequenceProgressProvider);
    final filter = progress.currentFilter;
    final runId = _ref.read(currentRunIdProvider);
    final runIdString = runId?.toString();
    final dao = _ref.read(imagesDaoProvider);
    final sidecarService = _ref.read(thumbnailSidecarServiceProvider);

    // Attribute this frame to its catalog target row and real exposure length
    // by walking the loaded sequence tree from the producing node. Replaces
    // the former hardcoded target_id=NULL + exposureDuration=1.0, which broke
    // per-target integration-goal completion (the scheduler imaged one target
    // all night) and corrupted every integration-time total. Computed
    // synchronously here so it reflects the sequence as it was when the frame
    // was produced, not whatever is loaded by the time the async insert runs.
    final loadedSequence = _ref.read(currentSequenceProvider);
    final attribution = loadedSequence == null
        ? const FrameAttribution()
        : resolveFrameAttribution(
            loadedSequence,
            nodeId,
            currentFilter: filter,
          );
    if (attribution.exposureSecs == null) {
      _logger.warning(
        'Sequence frame from node $nodeId has no resolvable exposure duration '
        '(producing node is not an ExposureNode); recording 0s rather than a '
        'fabricated value.',
        source: 'SequenceExecutor',
      );
    }

    unawaited(() async {
      try {
        await dao.insertSequenceFrame(
          filePath: filePath,
          fileName: fileName,
          fileFormat: filePath.toLowerCase().endsWith('.xisf')
              ? 'xisf'
              : 'fits',
          // Real exposure length from the producing ExposureNode —
          // (see the resolved `attribution` above; column is NOT NULL).
          exposureDuration: attribution.exposureSecs ?? 0.0,
          targetId: attribution.targetId,
          capturedAt: DateTime.now(),
          isAccepted: isAccepted,
          producingNodeId: nodeId,
          producingRunId: runIdString,
          runtimeGrade: grade,
          rejectionReason: rejectionReason,
          filter: filter,
          frameType: 'light',
          hfr: hfr,
          starCount: starCount,
          eccentricity: eccentricity,
          logger: _logger,
          sidecarService: sidecarService,
        );
        // Phase B (v43) — ADDITIVE durable-campaign bookkeeping. When an
        // accepted light frame attributes to a catalog target and a filter,
        // credit one accepted frame to the durable NINA-style `campaigns`
        // counter and stamp its last-capture date. This is a denormalized
        // companion to the live `integration_goals` derivation the scheduler
        // reads — it never feeds the engine's goals-complete reject and never
        // touches frame attribution; rejected frames (`isAccepted == false`)
        // are skipped so the counter only advances on acceptance.
        if (isAccepted &&
            attribution.targetId != null &&
            filter != null &&
            filter.isNotEmpty) {
          try {
            await _ref
                .read(campaignsDaoProvider)
                .recordAccepted(
                  targetId: attribution.targetId!,
                  filter: filter,
                  capturedAt: DateTime.now(),
                );
          } catch (e) {
            _logger.warning(
              'Phase B: failed to credit campaign for target '
              '${attribution.targetId} filter $filter: $e',
              source: 'SequenceExecutor',
            );
          }
        }
      } catch (e) {
        _logger.warning(
          'Wave 6 Thumbnails: failed to register sequence frame for '
          'node $nodeId ($grade): $e',
          source: 'SequenceExecutor',
        );
      }
    }());
  }

  void _recordRunFrame({
    required double exposureSecs,
    required bool accepted,
    String? filter,
  }) {
    _incrementRunStat((stats) {
      final progress = _ref.read(sequenceProgressProvider);
      stats.recordFrame(
        target:
            progress.currentTarget ??
            _ref.read(currentSequenceProvider)?.name ??
            'Sequence',
        filter: (filter != null && filter.isNotEmpty) ? filter : 'Unknown',
        exposureSecs: exposureSecs,
        accepted: accepted,
      );
    });
  }

  void _recordRunError(String message) {
    _incrementRunStat((stats) => stats.recordError(message));
  }

  void _incrementRunStat(void Function(SequenceRunStats stats) update) {
    final stats = _ref.read(liveSequenceStatsProvider);
    if (stats == null) {
      return;
    }
    update(stats);
    _ref.read(liveSequenceStatsProvider.notifier).state = stats;
    _persistLiveRunStats();
  }

  void _persistLiveRunStats() {
    final runId = _ref.read(currentRunIdProvider);
    final stats = _ref.read(liveSequenceStatsProvider);
    if (runId == null || stats == null) {
      return;
    }
    unawaited(
      _ref.read(sequenceRunsDaoProvider).updateStats(runId, stats.toJson()),
    );
  }

  void _finalizeRun(String status) {
    if (_runFinalized) {
      return;
    }
    final runId = _ref.read(currentRunIdProvider);
    final stats = _ref.read(liveSequenceStatsProvider);
    if (runId == null || stats == null) {
      return;
    }
    _runFinalized = true;
    stats.endTime = DateTime.now();
    final statsJson = stats.toJson();
    unawaited(
      _ref.read(sequenceRunsDaoProvider).finishRun(runId, status, statsJson),
    );
    // Wave 5.5 — surface post-session diagnostics + clear the
    // NotificationRouter override. `_finalizeRun` already early-returns
    // when called twice so these hooks fire exactly once per run.
    _captureSessionEndHooks();
  }

  // =========================================================================
  // 2026-06-04 follow-up — live-stacking auto-feed
  //
  // The Rust `LiveStacking` instruction node is arm-only: it registers a
  // broadcast session on the Rust side and returns immediately, delegating
  // frame ingestion to Dart (see the OSC-scope note in
  // `native/.../node/instructions/live_stacking.rs`). Before this wiring
  // existed, nothing on the Dart side ever fed accepted frames into the
  // stacker/broadcast, so the feature was inert during real runs and the
  // LAN broadcast served `{"active": false}` forever. This closes that gap:
  // each accepted sequence frame is registered with the in-process stacker
  // (first frame == reference, automatically) and the rendered stack is
  // published to `LiveStackingBroadcastService` for the HTTP endpoints.
  // =========================================================================

  /// Locate the enabled [LiveStackingNode] in the running sequence, if any.
  /// Returns the first enabled live-stacking node found; `null` means the
  /// running sequence does not use live stacking, so the accepted-frame
  /// feed is a no-op (NOT an error).
  LiveStackingNode? _findActiveLiveStackingNode() {
    final sequence = _ref.read(currentSequenceProvider);
    if (sequence == null) return null;
    for (final node in sequence.nodes.values) {
      if (node is LiveStackingNode && node.isEnabled) {
        return node;
      }
    }
    return null;
  }

  /// Map a [LiveStackingNode]'s combine method onto the engine config.
  /// The native stacker exposes sigma-clip as its only rejection knob, so
  /// `average` runs with rejection off and `medianRej`/`sigma` run with it
  /// on — matching the documented mapping in `BroadcastSessionState`.
  LiveStackingConfig _liveStackingConfigFor(LiveStackingNode node) {
    final sigmaClip = node.stackMethod != LiveStackingMethod.average;
    return LiveStackingConfig(sigmaClipEnabled: sigmaClip);
  }

  /// Auto-feed entry point invoked for every `FrameAccepted` event while a
  /// sequence runs. Serialises feeds onto [_liveStackingFeedChain] so a
  /// fast cadence cannot interleave the reference-frame start with a later
  /// add (which would corrupt the stack's coordinate system).
  void _maybeFeedLiveStacking(NightshadeEvent event) {
    final node = _findActiveLiveStackingNode();
    if (node == null) return; // Sequence has no live stacking — nothing to do.

    final savePath = event.data['save_path'] as String?;
    if (savePath == null || savePath.isEmpty) {
      // An accepted frame with no on-disk path cannot be fed. This is a
      // real wiring problem (the Rust grader is expected to ship
      // `save_path` for accepted frames), so we fail LOUD rather than
      // silently dropping the frame from the live stack.
      _logger.error(
        'Live-stacking auto-feed: accepted frame from node '
        '${event.data['node_id']} carried no save_path; cannot add it to the '
        'live stack. The broadcast stack will be missing this frame.',
        source: 'SequenceExecutor',
      );
      return;
    }

    final exposureSecs = _resolveLiveStackExposureSecs(event);
    final previous = _liveStackingFeedChain ?? Future<void>.value();
    _liveStackingFeedChain = previous.then(
      (_) => _feedLiveStackingFrame(
        node: node,
        savePath: savePath,
        exposureSecs: exposureSecs,
      ),
    );
  }

  /// Resolve the real exposure length for the accepted frame so the
  /// broadcast's integration counter is accurate. Prefers the producing
  /// node's attribution (the same source the captured-images row uses);
  /// falls back to the event's `duration_secs` payload.
  double _resolveLiveStackExposureSecs(NightshadeEvent event) {
    final nodeId = event.data['node_id'] as String?;
    final loadedSequence = _ref.read(currentSequenceProvider);
    if (nodeId != null && loadedSequence != null) {
      final attribution = resolveFrameAttribution(
        loadedSequence,
        nodeId,
        currentFilter: _ref.read(sequenceProgressProvider).currentFilter,
      );
      if (attribution.exposureSecs != null) {
        return attribution.exposureSecs!;
      }
    }
    return (event.data['duration_secs'] as num?)?.toDouble() ?? 0.0;
  }

  /// Add one accepted frame to the live stack and publish the rendered
  /// result to the broadcast. Arms the stacker + broadcast lazily on the
  /// first frame of the run (the frame becomes the reference). Honours the
  /// node's [LiveStackingNode.maxFramesToStack] cap. Failures are logged
  /// LOUD — a frame that cannot be fed is never silently dropped.
  Future<void> _feedLiveStackingFrame({
    required LiveStackingNode node,
    required String savePath,
    required double exposureSecs,
  }) async {
    final broadcast = _ref.read(liveStackingBroadcastServiceProvider);
    final notifier = _ref.read(liveStackingProvider.notifier);

    try {
      if (!_liveStackingArmedForRun) {
        // First accepted frame of the run → arm the broadcast (Dart side)
        // and start the stacker from this file. The file becomes the
        // reference automatically; no hand-picked reference is required.
        broadcast.activate(node);
        broadcast.updateCurrentTarget(
          _ref.read(sequenceProgressProvider).currentTarget,
        );
        await notifier.startFromFile(
          savePath,
          config: _liveStackingConfigFor(node),
        );
        final started =
            _ref.read(liveStackingProvider).status ==
            LiveStackingStatus.running;
        if (!started) {
          final err = _ref.read(liveStackingProvider).errorMessage;
          _logger.error(
            'Live-stacking auto-feed: failed to start the stacker from the '
            'first accepted frame ($savePath): ${err ?? 'unknown error'}. '
            'Live stack/broadcast will not run for this sequence.',
            source: 'SequenceExecutor',
          );
          broadcast.deactivate();
          return;
        }
        _liveStackingArmedForRun = true;
        _logger.info(
          'Live-stacking auto-feed armed: reference frame $savePath '
          '(method=${node.stackMethod.label}, broadcast port '
          '${node.broadcastPort})',
          source: 'SequenceExecutor',
        );
      } else {
        // Honour the frame cap. `0` means unlimited.
        final cap = node.maxFramesToStack;
        if (cap > 0 &&
            _ref.read(liveStackingProvider).stats.stackedFrameCount >= cap) {
          _logger.debug(
            'Live-stacking auto-feed: frame cap ($cap) reached; not adding '
            '$savePath to the stack.',
            source: 'SequenceExecutor',
          );
          return;
        }
        broadcast.updateCurrentTarget(
          _ref.read(sequenceProgressProvider).currentTarget,
        );
        await notifier.addFrameFromFile(savePath);
      }

      // Publish the freshly-updated stack to the broadcast. Read the
      // engine's current preview from the notifier state (populated by
      // both startFromFile and addFrameFromFile).
      final stackState = _ref.read(liveStackingProvider);
      final preview = stackState.previewData;
      if (preview == null ||
          stackState.previewWidth <= 0 ||
          stackState.previewHeight <= 0) {
        _logger.warning(
          'Live-stacking auto-feed: stack has no preview after feeding '
          '$savePath; broadcast image not updated this frame.',
          source: 'SequenceExecutor',
        );
        return;
      }
      broadcast.publishFrame(
        width: stackState.previewWidth,
        height: stackState.previewHeight,
        previewData: preview,
        exposureSecs: exposureSecs,
      );
    } catch (e, st) {
      // Loud-fail per CLAUDE.md: a frame that cannot be fed is surfaced,
      // not swallowed. The run itself keeps going (imaging must not stop
      // because the outreach broadcast hiccuped), but the operator sees
      // exactly which frame was lost and why.
      _logger.error(
        'Live-stacking auto-feed: failed to add accepted frame $savePath to '
        'the live stack: $e\n$st',
        source: 'SequenceExecutor',
      );
    }
  }

  /// Tear down the live-stacking auto-feed at the end of a run: stop the
  /// LAN broadcast and the stacking engine so the next run starts from a
  /// clean reference and a stopped public run cannot keep serving a stale
  /// stack. Idempotent — safe to call from both `stop()` and the terminal
  /// event handlers.
  Future<void> _teardownLiveStacking() async {
    if (!_liveStackingArmedForRun) {
      // Still deactivate the broadcast defensively in case it was armed
      // without a successful stacker start (e.g. activate() then start
      // failed); `deactivate()` is a no-op when nothing is active.
      _ref.read(liveStackingBroadcastServiceProvider).deactivate();
      return;
    }
    _liveStackingArmedForRun = false;
    // Drain any in-flight feed so we don't stop the engine out from under
    // a pending add.
    final chain = _liveStackingFeedChain;
    _liveStackingFeedChain = null;
    if (chain != null) {
      try {
        await chain;
      } catch (_) {
        // Feed errors are already logged in `_feedLiveStackingFrame`.
      }
    }
    _ref.read(liveStackingBroadcastServiceProvider).deactivate();
    try {
      await _ref.read(liveStackingProvider.notifier).stop();
    } catch (e) {
      _logger.warning(
        'Live-stacking auto-feed: failed to stop the stacker on teardown: $e',
        source: 'SequenceExecutor',
      );
    }
  }

  // =========================================================================
  // Wave 5.5 — session lifecycle hooks
  // =========================================================================

  /// Capture the optical-train baseline + register the active sequence
  /// with the notification router at session start.
  ///
  /// Each step is wrapped in try/catch because failure is non-fatal:
  /// the user wants imaging to proceed even when diagnostics or
  /// notifications are unavailable. We surface a single info-level
  /// log per failure so the user can still trace why their post-
  /// session report is empty.
}
