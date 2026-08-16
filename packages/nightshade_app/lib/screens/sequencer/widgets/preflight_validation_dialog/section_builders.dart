// ignore_for_file: invalid_use_of_protected_member
// Header, state, results, simulation, summary and action section builders.
part of '../preflight_validation_dialog.dart';

extension _PreFlightSectionBuilders on _PreFlightValidationDialogState {
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
                  style: NightshadeTypography.h4
                      .copyWith(color: colors.textPrimary),
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
            onPressed: _preparing ? null : () => Navigator.of(context).pop(),
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

  Widget _buildPreparingState(NightshadeColors colors) {
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
            'Preparing to start…',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize13,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Checking for unfinished integration to carry over.',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(NightshadeColors colors) {
    final error = _validationError;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.alertCircle, size: 40, color: colors.error),
          const SizedBox(height: 16),
          Text(
            error == null
                ? 'No sequence to validate'
                : 'Could not validate sequence',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              color: colors.textPrimary,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            NightshadeButton(
              label: 'Retry validation',
              icon: LucideIcons.refreshCw,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: _retryValidation,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResults(NightshadeColors colors) {
    final result = _result!;
    final hasSimulationIssues = _simulation?.issues.isNotEmpty ?? false;

    // Partition issues into the Dark Library, Equipment Health, and
    // Optical Train groups so each gets its own collapsible section,
    // then a "General" bucket for the remaining categories
    // (structure / equipment / settings / etc).
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
          // Info banner when the sequence has changed since the last
          // completed run. Informational only; not a pre-flight blocker.
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
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted),
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
                  value: DurationFormat.of(simulation.duration,
                      style: DurationStyle.compact),
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
                  // Green only when the simulation actually walked something.
                  // An empty sequence simulates to 0 segments and therefore 0
                  // issues, which would paint a reassuring green "0" inside a
                  // dialog headed "Cannot Start Sequence": the simulation did
                  // not clear the run, it did not evaluate it.
                  tone: simulation.hasBlockingIssues
                      ? colors.error
                      : simulation.issues.isNotEmpty
                          ? colors.warning
                          : simulation.segments.isEmpty
                              ? colors.textMuted
                              : colors.success,
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

  /// Deep-link to the dark-library settings section. We deliberately do not
  /// build the capture sequence here — opening the existing tool keeps the
  /// responsibility with the dark-library screen.
  void _openCalibrationCenter() {
    // Capture the router before closing so the dialog's context isn't defunct
    // by the time we navigate.
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.go('/settings?section=dark-library');
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
                  style: NightshadeTypography.h5.copyWith(
                      color: hasErrors
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
                      style: NightshadeTypography.labelStrong
                          .copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(
                            NightshadeTokens.radiusInline4),
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

  /// Info-severity banner shown when the in-editor sequence differs
  /// structurally from the most recent COMPLETED run
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
                  style: NightshadeTypography.h6
                      .copyWith(color: colors.textPrimary),
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

  /// Why Start cannot run, as a sentence fragment for [GatedAction.announce] —
  /// or null when it can.
  ///
  /// With errors on the board the primary is inert. Left undeclared it
  /// publishes a plain `button: Start Sequence` beside its live siblings
  /// `Re-check` and `Cancel` — clicking does nothing and says nothing, so a
  /// blocked dialog is indistinguishable from a working one for anyone reading
  /// the screen through assistive tech.
  String? _startBlockedReason({
    required bool canStart,
    required bool hasWarningsOnly,
    required bool hasBlockingSimulationIssue,
  }) {
    if (canStart || hasWarningsOnly) return null;
    final result = _result;
    if (result == null) {
      return _isValidating
          ? 'the pre-flight checks have not finished'
          : 'the pre-flight checks have not run yet';
    }
    if (result.hasErrors) {
      final count = result.errorCount;
      return 'fix the $count pre-flight '
          '${count == 1 ? 'error' : 'errors'} above first';
    }
    if (hasBlockingSimulationIssue) {
      return 'the run simulation found a blocking issue';
    }
    return 'the pre-flight checks have not cleared this run';
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
                setState(() {
                  _validationError = null;
                  _isValidating = true;
                });
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
                blockedReason: _startBlockedReason(
                  canStart: canStart,
                  hasWarningsOnly: hasWarningsOnly,
                  hasBlockingSimulationIssue: hasBlockingSimulationIssue,
                ),
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
}
