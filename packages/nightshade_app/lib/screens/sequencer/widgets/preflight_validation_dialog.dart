import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'mount_unpark_dialog.dart';
import 'sequence_diff_dialog.dart';
import 'session_handoff_dialog.dart';
import 'visual_timeline.dart';
part 'preflight_validation_dialog/simulation_widgets.dart';
part 'preflight_validation_dialog/action_widgets.dart';
part 'preflight_validation_dialog/issue_section.dart';

// =============================================================================
// PRE-FLIGHT VALIDATION DIALOG
// =============================================================================
//
// UI shell for the canonical sequence validator. The validation engine
// lives in `nightshade_core/.../sequence/sequence_validation.dart` â€” this
// file only renders the result.
//
// Previously this file defined its own ValidationIssue / ValidationSeverity
// / ValidationResult types. They were moved into the core engine and we
// now consume those directly to keep one source of truth for sequence
// validation across the app.

/// Pre-flight validation dialog
class PreFlightValidationDialog extends ConsumerStatefulWidget {
  final VoidCallback? onStartSequence;

  const PreFlightValidationDialog({
    super.key,
    this.onStartSequence,
  });

  @override
  ConsumerState<PreFlightValidationDialog> createState() =>
      _PreFlightValidationDialogState();
}

class _PreFlightValidationDialogState
    extends ConsumerState<PreFlightValidationDialog> {
  ValidationResult? _result;
  PreSessionSimulationResult? _simulation;
  String? _simulationUnavailableReason;
  bool _isValidating = true;

  /// Wave 6 Pack O â€” diff vs the most recent COMPLETED run of this
  /// sequence. `null` either means we haven't computed it yet, or there
  /// is no previous run to compare against (fresh sequence, or first
  /// successful run still pending). When non-null AND non-empty we
  /// surface a small info-banner near the top of the dialog with a
  /// "View N changes" link.
  SequenceDiffResult? _previousRunDiff;

  @override
  void initState() {
    super.initState();
    _runValidation();
    _computePreviousRunDiff();
  }

  Future<void> _runValidation() async {
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) {
      setState(() => _isValidating = false);
      return;
    }

    final validator = ref.read(sequenceValidatorProvider);
    final result = await validator.validate(sequence);
    final (simulation, simulationUnavailableReason) =
        await _simulateCurrentSequence(sequence);

    if (mounted) {
      setState(() {
        _result = result;
        _simulation = simulation;
        _simulationUnavailableReason = simulationUnavailableReason;
        _isValidating = false;
      });
    }
  }

  Future<(PreSessionSimulationResult?, String?)> _simulateCurrentSequence(
    Sequence sequence,
  ) async {
    final settings = await ref.read(appSettingsProvider.future);
    if (settings.latitude == 0.0 && settings.longitude == 0.0) {
      return (
        null,
        'Set observer latitude and longitude to simulate target visibility.',
      );
    }

    try {
      final twilight = ref.read(preSessionTwilightTimesProvider);
      final simulation = const PreSessionSimulator().simulate(
        sequence,
        start: DateTime.now(),
        latitude: settings.latitude,
        longitude: settings.longitude,
        minAltitude: settings.effectiveHorizonDeg,
        darkWindowStart: twilight?.astronomicalDusk,
        darkWindowEnd: twilight?.astronomicalDawn,
      );
      return (simulation, null);
    } catch (e) {
      return (null, 'Simulation failed: $e');
    }
  }

  /// Resolve the most recent COMPLETED run of the current sequence and
  /// compute a structural diff against the in-editor copy. The diff is
  /// informational only â€” pre-flight does NOT block on it; the link
  /// just lets the operator review what's changed since the last
  /// known-good run.
  ///
  /// We swallow errors quietly: a missing repository, missing DAO, or
  /// stale node-id mapping should not block the user from starting the
  /// sequence. The link simply won't appear in those cases.
  Future<void> _computePreviousRunDiff() async {
    try {
      final sequence = ref.read(currentSequenceProvider);
      if (sequence == null) return;
      final sequenceDbId = sequence.databaseId;
      if (sequenceDbId == null) {
        // Sequence has never been persisted â€” no run history to diff.
        return;
      }
      final dao = ref.read(sequenceRunsDaoProvider);
      final runs = await dao.getRunsForSequence(sequenceDbId);
      // Filter to "completed" runs only; failed / cancelled / running
      // runs are not the operator's reference point for "last known
      // good".
      SequenceRun? lastCompleted;
      for (final r in runs) {
        if (r.status == 'completed') {
          lastCompleted = r;
          break;
        }
      }
      if (lastCompleted == null) return;

      // We don't yet snapshot the sequence definition inside each run
      // row (see [SequenceDiffDialog.showForRun] for context), so the
      // diff against the persisted current sequence is the best we can
      // do. The diff service is structural by node id; if the user has
      // genuinely changed nothing, this returns an empty result and
      // we skip the banner.
      final repo = ref.read(sequenceRepositoryProvider);
      final persisted = await repo.loadSequence(sequenceDbId);
      if (persisted == null) return;
      final diffService = ref.read(sequenceDiffServiceProvider);
      final result = diffService.diff(
        previous: persisted,
        current: sequence,
      );
      if (result.isEmpty) return;
      if (!mounted) return;
      setState(() => _previousRunDiff = result);
    } catch (_) {
      // Quietly skip â€” pre-flight is not the place to bubble up
      // diff-resolution errors. The link just won't appear.
    }
  }

  /// Handle starting the sequence, checking for mount parking first.
  ///
  /// Wave 7 â€” Before kicking off the mount-unpark flow we surface the
  /// multi-night carry-over dialog when (a) at least one target has
  /// recent unfinished integration and (b) the
  /// `sessionHandoffAutoPrompt` setting is on. The decision is recorded
  /// in [sessionHandoffDecisionProvider]; the executor reads that value
  /// at sequence start so the IntegrationBudget tracker can either
  /// reuse or ignore the prior-session frames.
  Future<void> _handleStartSequence() async {
    // Check if a mount is connected and parked
    final mountState = ref.read(mountStateProvider);
    final isMountConnected =
        mountState.connectionState == DeviceConnectionState.connected;
    final isMountParked = mountState.isParked;

    // Close the preflight dialog first
    if (mounted) {
      Navigator.of(context).pop();
    }

    // Wave 7 â€” Surface the carry-over banner when enabled.
    if (mounted) {
      final autoPrompt = ref.read(sessionHandoffAutoPromptProvider);
      if (autoPrompt) {
        final carry = await ref
            .read(sessionCarryOverProvider.future)
            .catchError((_) => const <SessionCarryOver>[]);
        if (!mounted) return;
        if (carry.isNotEmpty) {
          final sequenceId = ref.read(currentSequenceProvider)?.databaseId;
          final decisions = await SessionHandoffDialog.show(
            context: context,
            sequenceId: sequenceId,
            carryOvers: carry,
          );
          // null = user dismissed; we still proceed with the run
          // because the carry-over is informational only.
          if (!mounted) return;
          if (decisions == null) {
            // User cancelled the handoff dialog entirely â€” abort the
            // sequence start in case they intended to back out.
            return;
          }
        }
      }
    }

    // If mount is connected and parked, show the unpark dialog
    if (isMountConnected && isMountParked) {
      if (!mounted) return;

      final result = await showMountUnparkDialog(context);

      // Only start the sequence if the user chose to unpark
      if (result == MountUnparkResult.unparkAndContinue) {
        widget.onStartSequence?.call();
      }
      // If cancelled, do nothing (sequence won't start)
    } else {
      // Mount is not parked or not connected, just start the sequence
      widget.onStartSequence?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 500,
      designHeight: 600,
    );

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: SizedBox(
        width: dialogSize.width,
        height: dialogSize.height,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // Header
            _buildHeader(colors),

            // Content
            Flexible(
              child: _isValidating
                  ? _buildLoadingState(colors)
                  : _result == null
                      ? _buildErrorState(colors)
                      : _buildResults(colors),
            ),

            // Actions
            _buildActions(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: NightshadeDecorations.tintedBadge(
              colors.primary,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
            ),
            child: Icon(LucideIcons.clipboardCheck,
                color: colors.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pre-Flight Validation',
                  style: NightshadeTypography.h4.copyWith(color: colors.textPrimary),
                ),
                Text(
                  'Checking sequence before execution',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.x, color: colors.textMuted, size: 18),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Running validation checks...',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize13,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 40, color: colors.error),
          const SizedBox(height: 16),
          Text(
            'No sequence to validate',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(NightshadeColors colors) {
    final result = _result!;
    final hasSimulationIssues = _simulation?.issues.isNotEmpty ?? false;

    // Wave 5 Agent 3 â€” partition issues into the three new pre-flight
    // groups (Dark Library, Equipment Health, Optical Train) so each
    // gets its own collapsible section, then a "General" bucket for
    // the existing categories (structure / equipment / settings / etc).
    final darkLibrary = result.issues
        .where((i) => i.category == ValidationCategory.darkLibrary)
        .toList(growable: false);
    final equipmentHealth = result.issues
        .where((i) => i.category == ValidationCategory.equipmentHealth)
        .toList(growable: false);
    final opticalTrain = result.issues
        .where((i) => i.category == ValidationCategory.opticalTrain)
        .toList(growable: false);
    final general = result.issues
        .where((i) =>
            i.category != ValidationCategory.darkLibrary &&
            i.category != ValidationCategory.equipmentHealth &&
            i.category != ValidationCategory.opticalTrain)
        .toList(growable: false);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Wave 6 Pack O â€” info banner when the sequence has changed
          // since the last completed run. Informational only; not a
          // pre-flight blocker.
          if (_previousRunDiff != null && !_previousRunDiff!.isEmpty) ...[
            _buildPreviousRunDiffBanner(colors, _previousRunDiff!),
            const SizedBox(height: 12),
          ],

          // Summary
          _buildSummary(colors, result, _simulation),
          const SizedBox(height: 20),
          _buildSimulationSection(colors),
          const SizedBox(height: 20),

          if (result.issues.isEmpty && !hasSimulationIssues) ...[
            _buildAllClearCard(colors),
          ] else ...[
            if (general.isNotEmpty) ...[
              Text(
                'General',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              ...general.map((issue) => _buildIssueCard(colors, issue)),
              const SizedBox(height: 8),
            ],
            if (darkLibrary.isNotEmpty)
              _PreflightSection(
                colors: colors,
                icon: LucideIcons.moon,
                title: 'Dark Library',
                issues: darkLibrary,
                trailing: TextButton.icon(
                  onPressed: _openCalibrationCenter,
                  icon: Icon(LucideIcons.cameraOff,
                      size: 14, color: colors.primary),
                  label: Text(
                    'Capture missing darks',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: NightshadeTypography.fontSize12,
                    ),
                  ),
                ),
              ),
            if (equipmentHealth.isNotEmpty)
              _PreflightSection(
                colors: colors,
                icon: LucideIcons.activity,
                title: 'Equipment Health',
                issues: equipmentHealth,
              ),
            if (opticalTrain.isNotEmpty)
              _PreflightSection(
                colors: colors,
                icon: LucideIcons.crosshair,
                title: 'Optical Train',
                issues: opticalTrain,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSimulationSection(NightshadeColors colors) {
    final simulation = _simulation;
    final unavailableReason = _simulationUnavailableReason;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.ganttChart, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'Simulation',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (simulation != null)
                Text(
                  'Ends ${_formatClock(simulation.end)}',
                  style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (simulation == null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 14, color: colors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unavailableReason ?? 'Simulation unavailable.',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SimulationMetric(
                  colors: colors,
                  label: 'Duration',
                  value: _formatDuration(simulation.duration),
                ),
                _SimulationMetric(
                  colors: colors,
                  label: 'Segments',
                  value: '${simulation.segments.length}',
                ),
                _SimulationMetric(
                  colors: colors,
                  label: 'Targets',
                  value: '${simulation.targetWindows.length}',
                ),
                _SimulationMetric(
                  colors: colors,
                  label: 'Issues',
                  value: '${simulation.issues.length}',
                  tone: simulation.hasBlockingIssues
                      ? colors.error
                      : simulation.issues.isEmpty
                          ? colors.success
                          : colors.warning,
                ),
              ],
            ),
            if (simulation.segments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SimulationTimeline(colors: colors, simulation: simulation),
            ],
            if (simulation.issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final issue in simulation.issues.take(3))
                _SimulationIssueRow(colors: colors, issue: issue),
            ],
          ],
        ],
      ),
    );
  }

  /// Deep-link to the dark library / calibration tools. The exact route
  /// name is defined in `apps/desktop/lib/app_routes.dart` (and matched
  /// on mobile). We deliberately do not build the capture sequence
  /// here â€” opening the existing tool keeps the responsibility with the
  /// dark-library screen.
  void _openCalibrationCenter() {
    Navigator.of(context).pop();
    // Use a name-based push so the dialog doesn't have to import the
    // route table. `pushNamed` silently no-ops if the name isn't
    // registered, which is the right behaviour on unit-test contexts
    // that don't install routes.
    Navigator.of(context).pushNamed('/calibration');
  }

  Widget _buildSummary(
    NightshadeColors colors,
    ValidationResult result,
    PreSessionSimulationResult? simulation,
  ) {
    final simulationErrorCount = simulation?.issues
            .where(
                (issue) => issue.severity == PreSessionSimulationSeverity.error)
            .length ??
        0;
    final simulationWarningCount = simulation?.issues
            .where((issue) =>
                issue.severity == PreSessionSimulationSeverity.warning)
            .length ??
        0;
    final simulationInfoCount = simulation?.issues
            .where(
                (issue) => issue.severity == PreSessionSimulationSeverity.info)
            .length ??
        0;

    final errorCount = result.errorCount + simulationErrorCount;
    final warningCount = result.warningCount + simulationWarningCount;
    final infoCount = result.infoCount + simulationInfoCount;
    final hasErrors = errorCount > 0;
    final hasWarnings = warningCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: NightshadeDecorations.emphasisSurface(
        hasErrors
            ? colors.error
            : hasWarnings
                ? colors.warning
                : colors.success,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        children: [
          Icon(
            hasErrors
                ? LucideIcons.xCircle
                : hasWarnings
                    ? LucideIcons.alertTriangle
                    : LucideIcons.checkCircle,
            size: 32,
            color: hasErrors
                ? colors.error
                : hasWarnings
                    ? colors.warning
                    : colors.success,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasErrors
                      ? 'Cannot Start Sequence'
                      : hasWarnings
                          ? 'Ready with Warnings'
                          : 'All Checks Passed',
                  style: NightshadeTypography.h5.copyWith(color: hasErrors
                        ? colors.error
                        : hasWarnings
                            ? colors.warning
                            : colors.success),
                ),
                Text(
                  hasErrors
                      ? 'Please fix $errorCount error(s) before starting'
                      : hasWarnings
                          ? '$warningCount warning(s) found'
                          : 'Sequence is ready to run',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Issue counts
          Row(
            children: [
              if (errorCount > 0)
                _CountBadge(
                  count: errorCount,
                  color: colors.error,
                  icon: LucideIcons.xCircle,
                ),
              if (warningCount > 0) ...[
                const SizedBox(width: 8),
                _CountBadge(
                  count: warningCount,
                  color: colors.warning,
                  icon: LucideIcons.alertTriangle,
                ),
              ],
              if (infoCount > 0) ...[
                const SizedBox(width: 8),
                _CountBadge(
                  count: infoCount,
                  color: colors.info,
                  icon: LucideIcons.info,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIssueCard(NightshadeColors colors, ValidationIssue issue) {
    final Color issueColor;
    final IconData issueIcon;

    switch (issue.severity) {
      case ValidationSeverity.error:
        issueColor = colors.error;
        issueIcon = LucideIcons.xCircle;
        break;
      case ValidationSeverity.warning:
        issueColor = colors.warning;
        issueIcon = LucideIcons.alertTriangle;
        break;
      case ValidationSeverity.info:
        issueColor = colors.info;
        issueIcon = LucideIcons.info;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: NightshadeDecorations.statusChip(
              issueColor,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              bordered: false,
            ),
            child: Icon(issueIcon, size: 14, color: issueColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      issue.title,
                      style: NightshadeTypography.labelStrong.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                      ),
                      child: Text(
                        issue.category.label,
                        style: TextStyle(
                          fontSize: NightshadeTypography.fontSize9,
                          fontWeight: FontWeight.w600,
                          color: colors.textMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  issue.description,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textSecondary,
                  ),
                ),
                if (issue.resolutionHint != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.lightbulb,
                          size: 12, color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          issue.resolutionHint!,
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize11,
                            color: colors.primary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Wave 6 Pack O â€” info-severity banner shown when the in-editor
  /// sequence differs structurally from the most recent COMPLETED run
  /// of the same sequence. Tapping "View N changes" pops the structural
  /// diff dialog.
  Widget _buildPreviousRunDiffBanner(
    NightshadeColors colors,
    SequenceDiffResult diff,
  ) {
    final changeCount =
        diff.added.length + diff.removed.length + diff.modified.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.info.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.gitCompare, size: 16, color: colors.info),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sequence has changed since last successful run',
                  style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '$changeCount change${changeCount == 1 ? '' : 's'} '
                  'across ${diff.added.length} added, '
                  '${diff.removed.length} removed, '
                  '${diff.modified.length} modified node(s).',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => SequenceDiffDialog.show(context, diff),
            icon: Icon(LucideIcons.eye, size: 14, color: colors.info),
            label: Text(
              'View changes',
              style: TextStyle(
                color: colors.info,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllClearCard(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.sparkles, size: 40, color: colors.success),
          const SizedBox(height: 12),
          Text(
            'Looking Good!',
            style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'No issues found. Your sequence is ready to run.',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(NightshadeColors colors) {
    final hasBlockingSimulationIssue = _simulation?.hasBlockingIssues ?? false;
    final hasSimulationWarnings = _simulation?.issues.any(
            (issue) => issue.severity != PreSessionSimulationSeverity.error) ??
        false;
    final canStart = (_result?.isValid ?? false) && !hasBlockingSimulationIssue;
    final hasWarningsOnly = _result != null &&
        !_result!.hasErrors &&
        !hasBlockingSimulationIssue &&
        (_result!.hasWarnings || hasSimulationWarnings);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 120,
            child: NightshadeButton(
              onPressed: () {
                setState(() => _isValidating = true);
                _runValidation();
              },
              icon: LucideIcons.refreshCw,
              label: 'Re-check',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NightshadeButton(
                onPressed: () => Navigator.of(context).pop(),
                label: 'Cancel',
                variant: ButtonVariant.ghost,
                size: ButtonSize.small,
              ),
              const SizedBox(width: 12),
              _StartSequenceButton(
                canStart: canStart,
                hasWarningsOnly: hasWarningsOnly,
                colors: colors,
                onPressed: (canStart || hasWarningsOnly)
                    ? () async {
                        await _handleStartSequence();
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatClock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${duration.inSeconds}s';
  }
}
