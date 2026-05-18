import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'mount_unpark_dialog.dart';

// =============================================================================
// PRE-FLIGHT VALIDATION DIALOG
// =============================================================================
//
// UI shell for the canonical sequence validator. The validation engine
// lives in `nightshade_core/.../sequence/sequence_validation.dart` — this
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
  bool _isValidating = true;

  @override
  void initState() {
    super.initState();
    _runValidation();
  }

  Future<void> _runValidation() async {
    final sequence = ref.read(currentSequenceProvider);
    if (sequence == null) {
      setState(() => _isValidating = false);
      return;
    }

    final validator = ref.read(sequenceValidatorProvider);
    final result = await validator.validate(sequence);

    if (mounted) {
      setState(() {
        _result = result;
        _isValidating = false;
      });
    }
  }

  /// Handle starting the sequence, checking for mount parking first
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  'Checking sequence before execution',
                  style: TextStyle(
                    fontSize: 12,
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
              fontSize: 13,
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
              fontSize: 14,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(NightshadeColors colors) {
    final result = _result!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          _buildSummary(colors, result),
          const SizedBox(height: 20),

          // Issues list
          if (result.issues.isNotEmpty) ...[
            Text(
              'Issues Found',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            ...result.issues.map((issue) => _buildIssueCard(colors, issue)),
          ] else ...[
            _buildAllClearCard(colors),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(NightshadeColors colors, ValidationResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: result.hasErrors
            ? colors.error.withValues(alpha: 0.1)
            : result.hasWarnings
                ? colors.warning.withValues(alpha: 0.1)
                : colors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: result.hasErrors
              ? colors.error.withValues(alpha: 0.3)
              : result.hasWarnings
                  ? colors.warning.withValues(alpha: 0.3)
                  : colors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            result.hasErrors
                ? LucideIcons.xCircle
                : result.hasWarnings
                    ? LucideIcons.alertTriangle
                    : LucideIcons.checkCircle,
            size: 32,
            color: result.hasErrors
                ? colors.error
                : result.hasWarnings
                    ? colors.warning
                    : colors.success,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.hasErrors
                      ? 'Cannot Start Sequence'
                      : result.hasWarnings
                          ? 'Ready with Warnings'
                          : 'All Checks Passed',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: result.hasErrors
                        ? colors.error
                        : result.hasWarnings
                            ? colors.warning
                            : colors.success,
                  ),
                ),
                Text(
                  result.hasErrors
                      ? 'Please fix ${result.errorCount} error(s) before starting'
                      : result.hasWarnings
                          ? '${result.warningCount} warning(s) found'
                          : 'Sequence is ready to run',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Issue counts
          Row(
            children: [
              if (result.errorCount > 0)
                _CountBadge(
                  count: result.errorCount,
                  color: colors.error,
                  icon: LucideIcons.xCircle,
                ),
              if (result.warningCount > 0) ...[
                const SizedBox(width: 8),
                _CountBadge(
                  count: result.warningCount,
                  color: colors.warning,
                  icon: LucideIcons.alertTriangle,
                ),
              ],
              if (result.infoCount > 0) ...[
                const SizedBox(width: 8),
                _CountBadge(
                  count: result.infoCount,
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: issueColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
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
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        issue.category.label,
                        style: TextStyle(
                          fontSize: 9,
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
                    fontSize: 12,
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
                            fontSize: 11,
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

  Widget _buildAllClearCard(NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.sparkles, size: 40, color: colors.success),
          const SizedBox(height: 12),
          Text(
            'Looking Good!',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No issues found. Your sequence is ready to run.',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(NightshadeColors colors) {
    final canStart = _result?.isValid ?? false;
    final hasWarningsOnly =
        _result != null && !_result!.hasErrors && _result!.hasWarnings;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Refresh button
          NightshadeButton(
            onPressed: () {
              setState(() => _isValidating = true);
              _runValidation();
            },
            icon: LucideIcons.refreshCw,
            label: 'Re-check',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),

          const Spacer(),

          // Cancel button
          NightshadeButton(
            onPressed: () => Navigator.of(context).pop(),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          const SizedBox(width: 12),

          // Start button
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
    );
  }
}

/// Small count badge widget
class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  final IconData icon;

  const _CountBadge({
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom start sequence button with muted gradient styling
class _StartSequenceButton extends StatefulWidget {
  final bool canStart;
  final bool hasWarningsOnly;
  final NightshadeColors colors;
  final VoidCallback? onPressed;

  const _StartSequenceButton({
    required this.canStart,
    required this.hasWarningsOnly,
    required this.colors,
    this.onPressed,
  });

  @override
  State<_StartSequenceButton> createState() => _StartSequenceButtonState();
}

class _StartSequenceButtonState extends State<_StartSequenceButton> {
  bool _isHovered = false;

  /// Creates a slightly darker shade of the given color
  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final baseColor = widget.canStart
        ? widget.colors.success
        : widget.hasWarningsOnly
            ? widget.colors.warning
            : widget.colors.textMuted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor:
          isEnabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: isEnabled
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      baseColor,
                      _darkenColor(baseColor, 0.08),
                    ],
                  )
                : null,
            color: isEnabled ? null : baseColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            boxShadow: isEnabled && _isHovered
                ? [
                    BoxShadow(
                      color: baseColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.canStart ? LucideIcons.play : LucideIcons.alertTriangle,
                size: 16,
                color: onPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                widget.hasWarningsOnly ? 'Start Anyway' : 'Start Sequence',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
