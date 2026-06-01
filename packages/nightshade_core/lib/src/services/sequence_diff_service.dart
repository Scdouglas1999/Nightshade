import '../models/sequence/sequence_models.dart';

/// Wave 6 Agent 5 — structural diff between two [Sequence] snapshots.
///
/// The diff is tree-aware rather than text-based: comparing two stored
/// JSON blobs as strings is useless for the operator ("the order of
/// keys changed" is not actionable) so we walk the node graphs and
/// classify each node into [SequenceDiffChange.added],
/// [SequenceDiffChange.removed], or [SequenceDiffChange.modified] using
/// a stable identity strategy:
///
///   1. **Same node id in both**: candidate for "modified". We compare
///      every type-specific property (exposure duration, filter,
///      autofocus method, etc.) and produce a per-field
///      [FieldChange] entry. If every field is equal the node is not
///      emitted at all (no-op).
///   2. **Id only in old**: classified as removed.
///   3. **Id only in new**: classified as added.
///
/// Nodes carry a human label (e.g. "Exposure 60s · Lum" or "Loop x10")
/// so the dialog can render meaningful rows without re-running display
/// logic.
///
/// Semantic categories generated per-field example:
///   * Exposure duration changed from `60.0s` to `120.0s`
///   * Added 3 new TargetHeader nodes
///   * Removed HFR trigger from "Capture Hα"
///
/// We deliberately diff every SequenceNode subtype here so that adding
/// a new node kind to the sealed hierarchy generates a missed-case
/// compile-time error (the switch is exhaustive). That matches the
/// repository's persistence layer in `sequence_repository.dart` and
/// keeps the diff in lock-step with what is actually saved.
class SequenceDiffService {
  const SequenceDiffService();

  /// Compute the diff. Returns an empty [SequenceDiffResult] when the
  /// two sequences are structurally identical.
  ///
  /// [previous] and [current] may have unrelated `Sequence.id` values
  /// (we are comparing runs, not edit history) — the node-id-based
  /// matching depends on stable per-node UUIDs, which the sequence
  /// editor preserves on every edit (`copyWith` always keeps `id`).
  SequenceDiffResult diff({
    required Sequence previous,
    required Sequence current,
  }) {
    final previousIds = previous.nodes.keys.toSet();
    final currentIds = current.nodes.keys.toSet();

    final added = <NodeDiffEntry>[];
    final removed = <NodeDiffEntry>[];
    final modified = <NodeDiffEntry>[];

    for (final id in currentIds.difference(previousIds)) {
      final node = current.nodes[id]!;
      added.add(NodeDiffEntry(
        nodeId: id,
        nodeKind: node.nodeType,
        label: _describeNode(node),
        changes: const <FieldChange>[],
      ));
    }

    for (final id in previousIds.difference(currentIds)) {
      final node = previous.nodes[id]!;
      removed.add(NodeDiffEntry(
        nodeId: id,
        nodeKind: node.nodeType,
        label: _describeNode(node),
        changes: const <FieldChange>[],
      ));
    }

    for (final id in currentIds.intersection(previousIds)) {
      final before = previous.nodes[id]!;
      final after = current.nodes[id]!;
      final fieldChanges = _diffNodes(before, after);
      if (fieldChanges.isNotEmpty) {
        modified.add(NodeDiffEntry(
          nodeId: id,
          nodeKind: after.nodeType,
          label: _describeNode(after),
          changes: fieldChanges,
        ));
      }
    }

    // Stable display ordering: by label so the UI is diffable between
    // re-runs of the same comparison.
    int byLabel(NodeDiffEntry a, NodeDiffEntry b) =>
        a.label.compareTo(b.label);
    added.sort(byLabel);
    removed.sort(byLabel);
    modified.sort(byLabel);

    return SequenceDiffResult(
      previousName: previous.name,
      currentName: current.name,
      added: List.unmodifiable(added),
      removed: List.unmodifiable(removed),
      modified: List.unmodifiable(modified),
    );
  }

  // ---------------------------------------------------------------------
  // Per-node field comparison
  // ---------------------------------------------------------------------

  /// Diff two nodes that share an id. The exhaustive switch ensures
  /// every node type contributes its own field comparisons; adding a
  /// new node subtype to the sealed hierarchy will fail to compile
  /// here, which is exactly what we want (silent identity for new
  /// node types would lose user-visible changes).
  List<FieldChange> _diffNodes(SequenceNode a, SequenceNode b) {
    final out = <FieldChange>[];

    // ---- Common base-class fields first ----
    if (a.name != b.name) {
      out.add(FieldChange('Name', a.name, b.name));
    }
    if (a.isEnabled != b.isEnabled) {
      out.add(FieldChange('Enabled', a.isEnabled, b.isEnabled));
    }
    if ((a.comment ?? '') != (b.comment ?? '')) {
      out.add(FieldChange('Comment', a.comment ?? '', b.comment ?? ''));
    }
    // ChildIds changes are recorded as a single summary entry — node-by-
    // node child diffs are out of scope here; the per-child diff is
    // already covered by the top-level added/removed lists.
    if (!_listEquals(a.childIds, b.childIds)) {
      out.add(FieldChange(
        'Children',
        '${a.childIds.length} children',
        '${b.childIds.length} children',
      ));
    }

    // If the runtime types disagree the user replaced one node with
    // a different kind under the same id (rare; the editor's mutator
    // doesn't do this, but imports may). Flag it as a kind change and
    // skip type-specific comparison.
    if (a.runtimeType != b.runtimeType) {
      out.add(FieldChange('Node kind', a.nodeType, b.nodeType));
      return out;
    }

    // ---- Type-specific comparisons. Sealed switch ensures exhaustiveness. ----
    switch (a) {
      case ExposureNode():
        final na = a, nb = b as ExposureNode;
        _addIfChanged(out, 'Exposure duration',
            '${na.durationSecs}s', '${nb.durationSecs}s',
            equalIf: na.durationSecs == nb.durationSecs);
        _addIfChanged(out, 'Frame count',
            na.count.toString(), nb.count.toString(),
            equalIf: na.count == nb.count);
        _addIfChanged(out, 'Frame type',
            na.frameType.name, nb.frameType.name,
            equalIf: na.frameType == nb.frameType);
        _addIfChanged(out, 'Filter',
            na.filter ?? '(none)', nb.filter ?? '(none)',
            equalIf: na.filter == nb.filter);
        _addIfChanged(out, 'Filter index',
            na.filterIndex?.toString() ?? '(auto)',
            nb.filterIndex?.toString() ?? '(auto)',
            equalIf: na.filterIndex == nb.filterIndex);
        _addIfChanged(out, 'Gain',
            na.gain?.toString() ?? '(default)',
            nb.gain?.toString() ?? '(default)',
            equalIf: na.gain == nb.gain);
        _addIfChanged(out, 'Offset',
            na.offset?.toString() ?? '(default)',
            nb.offset?.toString() ?? '(default)',
            equalIf: na.offset == nb.offset);
        _addIfChanged(out, 'Binning',
            na.binning.name, nb.binning.name,
            equalIf: na.binning == nb.binning);
        _addIfChanged(out, 'Dither every',
            na.ditherEvery?.toString() ?? '(off)',
            nb.ditherEvery?.toString() ?? '(off)',
            equalIf: na.ditherEvery == nb.ditherEvery);
        if (na.triggers.length != nb.triggers.length) {
          out.add(FieldChange(
            'Triggers',
            '${na.triggers.length}',
            '${nb.triggers.length}',
          ));
        }
        break;
      case TargetHeaderNode():
        final na = a, nb = b as TargetHeaderNode;
        _addIfChanged(out, 'Target name', na.targetName, nb.targetName,
            equalIf: na.targetName == nb.targetName);
        _addIfChanged(out, 'RA (hours)',
            na.raHours.toStringAsFixed(4), nb.raHours.toStringAsFixed(4),
            equalIf: na.raHours == nb.raHours);
        _addIfChanged(out, 'Dec (degrees)',
            na.decDegrees.toStringAsFixed(4),
            nb.decDegrees.toStringAsFixed(4),
            equalIf: na.decDegrees == nb.decDegrees);
        _addIfChanged(out, 'Rotation',
            na.rotation?.toStringAsFixed(2) ?? '(none)',
            nb.rotation?.toStringAsFixed(2) ?? '(none)',
            equalIf: na.rotation == nb.rotation);
        _addIfChanged(out, 'Priority',
            na.priority.toString(), nb.priority.toString(),
            equalIf: na.priority == nb.priority);
        _addIfChanged(out, 'Min altitude',
            na.minAltitude?.toStringAsFixed(0) ?? '(none)',
            nb.minAltitude?.toStringAsFixed(0) ?? '(none)',
            equalIf: na.minAltitude == nb.minAltitude);
        _addIfChanged(out, 'Max altitude',
            na.maxAltitude?.toStringAsFixed(0) ?? '(none)',
            nb.maxAltitude?.toStringAsFixed(0) ?? '(none)',
            equalIf: na.maxAltitude == nb.maxAltitude);
        _addIfChanged(out, 'Integration budget',
            na.integrationBudget == null ? '(none)' : 'set',
            nb.integrationBudget == null ? '(none)' : 'set',
            equalIf: (na.integrationBudget == null) ==
                (nb.integrationBudget == null));
        break;
      case LoopNode():
        final na = a, nb = b as LoopNode;
        _addIfChanged(out, 'Loop condition',
            na.conditionType.name, nb.conditionType.name,
            equalIf: na.conditionType == nb.conditionType);
        _addIfChanged(out, 'Repeat count',
            na.repeatCount?.toString() ?? '(none)',
            nb.repeatCount?.toString() ?? '(none)',
            equalIf: na.repeatCount == nb.repeatCount);
        _addIfChanged(out, 'Repeat until altitude',
            na.repeatUntilAltitude?.toString() ?? '(none)',
            nb.repeatUntilAltitude?.toString() ?? '(none)',
            equalIf: na.repeatUntilAltitude == nb.repeatUntilAltitude);
        _addIfChanged(out, 'Integration target (s)',
            na.integrationTimeTarget?.toString() ?? '(none)',
            nb.integrationTimeTarget?.toString() ?? '(none)',
            equalIf: na.integrationTimeTarget == nb.integrationTimeTarget);
        break;
      case ParallelNode():
        final na = a, nb = b as ParallelNode;
        _addIfChanged(out, 'Required successes',
            na.requiredSuccesses?.toString() ?? '(all)',
            nb.requiredSuccesses?.toString() ?? '(all)',
            equalIf: na.requiredSuccesses == nb.requiredSuccesses);
        break;
      case ConditionalNode():
        final na = a, nb = b as ConditionalNode;
        _addIfChanged(out, 'Condition',
            na.conditionType.name, nb.conditionType.name,
            equalIf: na.conditionType == nb.conditionType);
        _addIfChanged(out, 'Threshold',
            na.thresholdValue?.toString() ?? '(none)',
            nb.thresholdValue?.toString() ?? '(none)',
            equalIf: na.thresholdValue == nb.thresholdValue);
        // Audit C2 — surface multi-safety-monitor target changes in diffs.
        _addIfChanged(out, 'Safety monitor',
            na.safetyMonitorId ?? '(default)',
            nb.safetyMonitorId ?? '(default)',
            equalIf: na.safetyMonitorId == nb.safetyMonitorId);
        break;
      case RecoveryNode():
        final na = a, nb = b as RecoveryNode;
        _addIfChanged(out, 'Recovery action',
            na.recoveryAction.name, nb.recoveryAction.name,
            equalIf: na.recoveryAction == nb.recoveryAction);
        _addIfChanged(out, 'Max retries',
            na.maxRetries.toString(), nb.maxRetries.toString(),
            equalIf: na.maxRetries == nb.maxRetries);
        break;
      case AutofocusNode():
        final na = a, nb = b as AutofocusNode;
        _addIfChanged(out, 'Method', na.method.name, nb.method.name,
            equalIf: na.method == nb.method);
        _addIfChanged(out, 'Step size',
            na.stepSize.toString(), nb.stepSize.toString(),
            equalIf: na.stepSize == nb.stepSize);
        _addIfChanged(out, 'Exposure',
            '${na.exposureDuration}s', '${nb.exposureDuration}s',
            equalIf: na.exposureDuration == nb.exposureDuration);
        break;
      case DitherNode():
        final na = a, nb = b as DitherNode;
        _addIfChanged(out, 'Pixels',
            na.pixels.toString(), nb.pixels.toString(),
            equalIf: na.pixels == nb.pixels);
        _addIfChanged(out, 'Settle pixels',
            na.settlePixels.toString(), nb.settlePixels.toString(),
            equalIf: na.settlePixels == nb.settlePixels);
        _addIfChanged(out, 'RA only',
            na.raOnly.toString(), nb.raOnly.toString(),
            equalIf: na.raOnly == nb.raOnly);
        _addIfChanged(out, 'Pattern',
            na.pattern.name, nb.pattern.name,
            equalIf: na.pattern == nb.pattern);
        _addIfChanged(out, 'Grid size',
            '${na.gridSize}x${na.gridSize}', '${nb.gridSize}x${nb.gridSize}',
            equalIf: na.gridSize == nb.gridSize);
        break;
      case FilterChangeNode():
        final na = a, nb = b as FilterChangeNode;
        _addIfChanged(out, 'Filter name', na.filterName, nb.filterName,
            equalIf: na.filterName == nb.filterName);
        _addIfChanged(out, 'Filter position',
            na.filterPosition?.toString() ?? '(by name)',
            nb.filterPosition?.toString() ?? '(by name)',
            equalIf: na.filterPosition == nb.filterPosition);
        break;
      case SlewNode():
        final na = a, nb = b as SlewNode;
        _addIfChanged(out, 'Uses target coords',
            na.useTargetCoords.toString(),
            nb.useTargetCoords.toString(),
            equalIf: na.useTargetCoords == nb.useTargetCoords);
        _addIfChanged(out, 'Custom RA',
            na.customRa?.toString() ?? '(none)',
            nb.customRa?.toString() ?? '(none)',
            equalIf: na.customRa == nb.customRa);
        _addIfChanged(out, 'Custom Dec',
            na.customDec?.toString() ?? '(none)',
            nb.customDec?.toString() ?? '(none)',
            equalIf: na.customDec == nb.customDec);
        break;
      case CenterNode():
        final na = a, nb = b as CenterNode;
        _addIfChanged(out, 'Accuracy (arcsec)',
            na.accuracyArcsec.toString(), nb.accuracyArcsec.toString(),
            equalIf: na.accuracyArcsec == nb.accuracyArcsec);
        _addIfChanged(out, 'Max attempts',
            na.maxAttempts.toString(), nb.maxAttempts.toString(),
            equalIf: na.maxAttempts == nb.maxAttempts);
        break;
      case CoolCameraNode():
        final na = a, nb = b as CoolCameraNode;
        _addIfChanged(out, 'Target temp',
            '${na.targetTemp}C', '${nb.targetTemp}C',
            equalIf: na.targetTemp == nb.targetTemp);
        _addIfChanged(out, 'Duration (min)',
            na.durationMins.toString(), nb.durationMins.toString(),
            equalIf: na.durationMins == nb.durationMins);
        break;
      case WarmCameraNode():
        final na = a, nb = b as WarmCameraNode;
        _addIfChanged(out, 'Rate (C/min)',
            na.ratePerMin.toString(), nb.ratePerMin.toString(),
            equalIf: na.ratePerMin == nb.ratePerMin);
        _addIfChanged(out, 'Target temp',
            '${na.targetTemp}C', '${nb.targetTemp}C',
            equalIf: na.targetTemp == nb.targetTemp);
        break;
      case RotatorNode():
        final na = a, nb = b as RotatorNode;
        _addIfChanged(out, 'Target angle',
            '${na.targetAngle}°', '${nb.targetAngle}°',
            equalIf: na.targetAngle == nb.targetAngle);
        _addIfChanged(out, 'Relative',
            na.relative.toString(), nb.relative.toString(),
            equalIf: na.relative == nb.relative);
        break;
      case WaitTimeNode():
        final na = a, nb = b as WaitTimeNode;
        _addIfChanged(out, 'Wait until',
            na.waitUntil?.toIso8601String() ?? '(none)',
            nb.waitUntil?.toIso8601String() ?? '(none)',
            equalIf: na.waitUntil == nb.waitUntil);
        _addIfChanged(out, 'Wait for twilight',
            na.waitForTwilight?.name ?? '(none)',
            nb.waitForTwilight?.name ?? '(none)',
            equalIf: na.waitForTwilight == nb.waitForTwilight);
        break;
      case DelayNode():
        final na = a, nb = b as DelayNode;
        _addIfChanged(out, 'Seconds',
            na.seconds.toString(), nb.seconds.toString(),
            equalIf: na.seconds == nb.seconds);
        break;
      case NotificationNode():
        final na = a, nb = b as NotificationNode;
        _addIfChanged(out, 'Title', na.title, nb.title,
            equalIf: na.title == nb.title);
        _addIfChanged(out, 'Message', na.message, nb.message,
            equalIf: na.message == nb.message);
        _addIfChanged(out, 'Level', na.level.name, nb.level.name,
            equalIf: na.level == nb.level);
        break;
      case ScriptNode():
        final na = a, nb = b as ScriptNode;
        _addIfChanged(out, 'Script path', na.scriptPath, nb.scriptPath,
            equalIf: na.scriptPath == nb.scriptPath);
        _addIfChanged(out, 'Timeout (s)',
            na.timeoutSecs.toString(), nb.timeoutSecs.toString(),
            equalIf: na.timeoutSecs == nb.timeoutSecs);
        break;
      case MeridianFlipNode():
        final na = a, nb = b as MeridianFlipNode;
        _addIfChanged(out, 'Trigger method',
            na.triggerMethod.name, nb.triggerMethod.name,
            equalIf: na.triggerMethod == nb.triggerMethod);
        _addIfChanged(out, 'Minutes past meridian',
            na.minutesPastMeridian.toString(),
            nb.minutesPastMeridian.toString(),
            equalIf: na.minutesPastMeridian == nb.minutesPastMeridian);
        _addIfChanged(out, 'Pause guiding',
            na.pauseGuiding.toString(), nb.pauseGuiding.toString(),
            equalIf: na.pauseGuiding == nb.pauseGuiding);
        break;
      case PolarAlignmentNode():
        final na = a, nb = b as PolarAlignmentNode;
        _addIfChanged(out, 'Exposure',
            '${na.exposureDuration}s', '${nb.exposureDuration}s',
            equalIf: na.exposureDuration == nb.exposureDuration);
        _addIfChanged(out, 'Start altitude',
            '${na.startAltitude}°', '${nb.startAltitude}°',
            equalIf: na.startAltitude == nb.startAltitude);
        _addIfChanged(out, 'Is north',
            na.isNorth.toString(), nb.isNorth.toString(),
            equalIf: na.isNorth == nb.isNorth);
        break;
      case StartGuidingNode():
        final na = a, nb = b as StartGuidingNode;
        _addIfChanged(out, 'Settle pixels',
            na.settlePixels.toString(), nb.settlePixels.toString(),
            equalIf: na.settlePixels == nb.settlePixels);
        _addIfChanged(out, 'Settle time',
            '${na.settleTime}s', '${nb.settleTime}s',
            equalIf: na.settleTime == nb.settleTime);
        _addIfChanged(out, 'Auto select star',
            na.autoSelectStar.toString(), nb.autoSelectStar.toString(),
            equalIf: na.autoSelectStar == nb.autoSelectStar);
        break;
      case TargetSchedulerNode():
        final na = a, nb = b as TargetSchedulerNode;
        _addIfChanged(out, 'Altitude weight',
            na.altitudeWeight.toString(), nb.altitudeWeight.toString(),
            equalIf: na.altitudeWeight == nb.altitudeWeight);
        _addIfChanged(out, 'Moon-distance weight',
            na.moonDistanceWeight.toString(),
            nb.moonDistanceWeight.toString(),
            equalIf: na.moonDistanceWeight == nb.moonDistanceWeight);
        _addIfChanged(out, 'Min score',
            na.minScoreToRun.toString(), nb.minScoreToRun.toString(),
            equalIf: na.minScoreToRun == nb.minScoreToRun);
        break;
      case SmartExposureNode():
        final na = a, nb = b as SmartExposureNode;
        if (na.plans.length != nb.plans.length) {
          out.add(FieldChange('Plan count',
              na.plans.length.toString(), nb.plans.length.toString()));
        }
        _addIfChanged(out, 'Rotate filters',
            na.rotateFilters.toString(), nb.rotateFilters.toString(),
            equalIf: na.rotateFilters == nb.rotateFilters);
        _addIfChanged(out, 'Integration budget (s)',
            na.integrationBudgetSecs.toString(),
            nb.integrationBudgetSecs.toString(),
            equalIf: na.integrationBudgetSecs == nb.integrationBudgetSecs);
        _addIfChanged(out, 'Loop until stopped',
            na.loopUntilStopped.toString(), nb.loopUntilStopped.toString(),
            equalIf: na.loopUntilStopped == nb.loopUntilStopped);
        break;
      case LiveStackingNode():
        final na = a, nb = b as LiveStackingNode;
        _addIfChanged(out, 'Mode', na.mode.label, nb.mode.label,
            equalIf: na.mode == nb.mode);
        _addIfChanged(out, 'Stack method',
            na.stackMethod.label, nb.stackMethod.label,
            equalIf: na.stackMethod == nb.stackMethod);
        _addIfChanged(out, 'Broadcast port',
            na.broadcastPort.toString(), nb.broadcastPort.toString(),
            equalIf: na.broadcastPort == nb.broadcastPort);
        _addIfChanged(out, 'Broadcast enabled',
            na.broadcastEnabled.toString(), nb.broadcastEnabled.toString(),
            equalIf: na.broadcastEnabled == nb.broadcastEnabled);
        _addIfChanged(out, 'Public access',
            na.isPublic.toString(), nb.isPublic.toString(),
            equalIf: na.isPublic == nb.isPublic);
        _addIfChanged(out, 'Watermark',
            na.watermarkText ?? '(none)',
            nb.watermarkText ?? '(none)',
            equalIf: na.watermarkText == nb.watermarkText);
        break;
      case SciencePhotometryNode():
        final na = a, nb = b as SciencePhotometryNode;
        _addIfChanged(out, 'Target designation',
            na.targetDesignation, nb.targetDesignation,
            equalIf: na.targetDesignation == nb.targetDesignation);
        _addIfChanged(out, 'Filter', na.filter, nb.filter,
            equalIf: na.filter == nb.filter);
        _addIfChanged(out, 'Exposure (s)',
            na.exposureSecs.toString(), nb.exposureSecs.toString(),
            equalIf: na.exposureSecs == nb.exposureSecs);
        _addIfChanged(out, 'Count',
            na.count.toString(), nb.count.toString(),
            equalIf: na.count == nb.count);
        _addIfChanged(out, 'Cadence gap (s)',
            na.maxCadenceGapSecs.toString(),
            nb.maxCadenceGapSecs.toString(),
            equalIf: na.maxCadenceGapSecs == nb.maxCadenceGapSecs);
        _addIfChanged(out, 'Reference stars',
            na.referenceStars.join(','),
            nb.referenceStars.join(','),
            equalIf: na.referenceStars.join(',') ==
                nb.referenceStars.join(','));
        break;
      // Audit §11 — plugin-contributed instruction. Diff the plugin
      // identity AND the opaque config JSON; either changing is a
      // meaningful edit the user wants surfaced in the diff dialog.
      case PluginInstructionNode():
        final na = a, nb = b as PluginInstructionNode;
        _addIfChanged(out, 'Plugin id', na.pluginId, nb.pluginId,
            equalIf: na.pluginId == nb.pluginId);
        _addIfChanged(out, 'Node type id', na.nodeTypeId, nb.nodeTypeId,
            equalIf: na.nodeTypeId == nb.nodeTypeId);
        _addIfChanged(out, 'Config', na.configJson, nb.configJson,
            equalIf: na.configJson == nb.configJson);
        _addIfChanged(out, 'Timeout (s)',
            na.timeoutSecs?.toString() ?? '(default)',
            nb.timeoutSecs?.toString() ?? '(default)',
            equalIf: na.timeoutSecs == nb.timeoutSecs);
        break;
      // Side-effect-only nodes have no type-specific properties beyond
      // the common base fields handled above.
      case InstructionSetNode():
      case StopGuidingNode():
      case ParkNode():
      case UnparkNode():
      case OpenCoverNode():
      case CloseCoverNode():
      case CalibratorOnNode():
      case CalibratorOffNode():
      case OpenDomeNode():
      case CloseDomeNode():
      case ParkDomeNode():
        // No-op: base-class diff above already covers every field.
        break;
    }
    return out;
  }

  /// Display label for a node — the same string the dialog renders next
  /// to its kind icon. Keep concise; the body of the diff is the per-
  /// field [FieldChange] list, not this label.
  String _describeNode(SequenceNode node) {
    switch (node) {
      case ExposureNode():
        final filter = (node.filter == null || node.filter!.isEmpty)
            ? 'Unfiltered'
            : node.filter!;
        return 'Exposure ${node.durationSecs.toStringAsFixed(0)}s x${node.count} ($filter)';
      case TargetHeaderNode():
        return 'Target "${node.targetName}"';
      case LoopNode():
        if (node.conditionType == LoopConditionType.count &&
            node.repeatCount != null) {
          return 'Loop x${node.repeatCount}';
        }
        return 'Loop (${node.conditionType.name})';
      case AutofocusNode():
        return 'Autofocus (${node.method.name})';
      case DitherNode():
        return 'Dither ${node.pixels.toStringAsFixed(1)}px';
      case FilterChangeNode():
        return 'Filter change → ${node.filterName}';
      case SlewNode():
        return node.useTargetCoords
            ? 'Slew (target coords)'
            : 'Slew (RA ${node.customRa}, Dec ${node.customDec})';
      case CenterNode():
        return 'Center (${node.accuracyArcsec}″)';
      case CoolCameraNode():
        return 'Cool camera → ${node.targetTemp}C';
      case WarmCameraNode():
        return 'Warm camera → ${node.targetTemp}C';
      case RotatorNode():
        return 'Rotate to ${node.targetAngle}°';
      case WaitTimeNode():
        if (node.waitUntil != null) {
          return 'Wait until ${node.waitUntil!.toIso8601String()}';
        }
        if (node.waitForTwilight != null) {
          return 'Wait for ${node.waitForTwilight!.name} twilight';
        }
        return 'Wait';
      case DelayNode():
        return 'Delay ${node.seconds}s';
      case NotificationNode():
        return 'Notification "${node.title}"';
      case ScriptNode():
        return 'Script ${node.scriptPath}';
      case MeridianFlipNode():
        return 'Meridian flip';
      case PolarAlignmentNode():
        return 'Polar alignment';
      case TargetSchedulerNode():
        return 'Target scheduler';
      case SmartExposureNode():
        return 'Smart exposure (${node.plans.length} plans)';
      case LiveStackingNode():
        final access = node.isPublic ? 'public' : 'private';
        return 'Live stacking (port ${node.broadcastPort}, $access)';
      case SciencePhotometryNode():
        return 'Photometry (${node.targetDesignation}, ${node.filter}, '
            '${node.count}x${node.exposureSecs.toStringAsFixed(0)}s)';
      case ParallelNode():
        return 'Parallel';
      case ConditionalNode():
        return 'Conditional (${node.conditionType.name})';
      case RecoveryNode():
        return 'Recovery (${node.recoveryAction.name})';
      case StartGuidingNode():
        return 'Start guiding';
      case InstructionSetNode():
        return node.name;
      case StopGuidingNode():
        return 'Stop guiding';
      case ParkNode():
        return 'Park mount';
      case UnparkNode():
        return 'Unpark mount';
      case OpenCoverNode():
        return 'Open dust cover';
      case CloseCoverNode():
        return 'Close dust cover';
      case CalibratorOnNode():
        return 'Calibrator on';
      case CalibratorOffNode():
        return 'Calibrator off';
      case OpenDomeNode():
        return 'Open dome';
      case CloseDomeNode():
        return 'Close dome';
      case ParkDomeNode():
        return 'Park dome';
      case PluginInstructionNode():
        // Audit §11 — show the friendly node name AND the source plugin
        // so users distinguish identical-named nodes from different
        // plugins in the diff dialog.
        final source = node.pluginName.isEmpty ? node.pluginId : node.pluginName;
        return 'Plugin: ${node.name} ($source)';
    }
  }

  void _addIfChanged(
    List<FieldChange> out,
    String field,
    String oldValue,
    String newValue, {
    required bool equalIf,
  }) {
    if (equalIf) return;
    out.add(FieldChange(field, oldValue, newValue));
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Result of [SequenceDiffService.diff].
class SequenceDiffResult {
  final String previousName;
  final String currentName;
  final List<NodeDiffEntry> added;
  final List<NodeDiffEntry> removed;
  final List<NodeDiffEntry> modified;

  const SequenceDiffResult({
    required this.previousName,
    required this.currentName,
    required this.added,
    required this.removed,
    required this.modified,
  });

  bool get isEmpty =>
      added.isEmpty && removed.isEmpty && modified.isEmpty;

  /// Concise headline (used in the dialog title / preflight banner).
  String get summary {
    if (isEmpty) return 'No changes';
    final parts = <String>[];
    if (added.isNotEmpty) parts.add('+${added.length}');
    if (removed.isNotEmpty) parts.add('-${removed.length}');
    if (modified.isNotEmpty) parts.add('~${modified.length}');
    return parts.join('  ');
  }
}

/// One entry in the diff: either an added node, a removed node, or a
/// modified node carrying its per-field [changes] list.
class NodeDiffEntry {
  final String nodeId;
  final String nodeKind;
  final String label;
  final List<FieldChange> changes;

  const NodeDiffEntry({
    required this.nodeId,
    required this.nodeKind,
    required this.label,
    required this.changes,
  });
}

/// One field-level change inside a modified node.
class FieldChange {
  final String field;
  final Object? oldValue;
  final Object? newValue;

  const FieldChange(this.field, this.oldValue, this.newValue);

  /// Human-readable line (used by tests and the markdown export).
  String describe() => '$field: $oldValue → $newValue';
}
