import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'snackbar_helper.dart';

/// Universal wrapper for sequence mutations originating from the UI.
///
/// The trust patch elevated several historically-silent failure modes in
/// `CurrentSequenceNotifier` into typed exceptions:
///
///   * [SequenceLockedException] — mutation attempted while the sequencer
///     is Running / Paused / Stopping. UI affordances *should* already be
///     disabled by [canEditSequenceProvider] but races (drag-drop already
///     in-flight when Start is pressed, etc.) can still hit it.
///   * [SnippetDeserializationException] — clipboard/snippet payload
///     contains a `nodeType` the editor doesn't recognise. Common when
///     pasting from a newer version of the app.
///   * [CrossParentReorderException] — Targets-tab reorder across two
///     parent containers; the bulk API can't express the desired semantic.
///   * [NoActiveSequenceException] — the user invoked a mutation before
///     opening or creating a sequence.
///   * [SequenceValidationFailedException] — the editor wrote OK but the
///     sequence won't round-trip through a file save / programmatic export.
///     Carries the full [ValidationIssue] list.
///
/// Before this helper, ~15 call sites in `nightshade_app` invoked
/// `currentSequenceProvider.notifier.X(...)` with no try/catch at all,
/// turning thrown exceptions into red-error overlays the user couldn't
/// dismiss. This helper centralises the catch + user-facing feedback so
/// every mutation site behaves identically.
///
/// Usage:
/// ```dart
/// await withSequenceMutation(
///   context,
///   ref,
///   operationName: 'Duplicate Node',
///   action: () async {
///     ref.read(currentSequenceProvider.notifier).duplicateNode(id);
///   },
/// );
/// ```
///
/// Returns `true` when the action completed without raising one of the
/// known editor exceptions; `false` when one of them was caught and
/// surfaced to the user (the helper has already shown the snackbar /
/// dialog). Synchronous throws from non-editor code (e.g. `StateError`)
/// are NOT swallowed — they bubble out to whatever try/catch the caller
/// has, or to the framework. This is deliberate: surprise crashes are
/// still bugs to fix, not user-facing errors to paper over.
Future<bool> withSequenceMutation(
  BuildContext context,
  WidgetRef ref, {
  required String operationName,
  required Future<void> Function() action,
}) async {
  try {
    await action();
    return true;
  } on SequenceLockedException catch (e) {
    if (!context.mounted) return false;
    context.showErrorSnackBar('Could not $operationName: ${e.message}');
    return false;
  } on NoActiveSequenceException catch (e) {
    if (!context.mounted) return false;
    context.showErrorSnackBar('Could not $operationName: ${e.message}');
    return false;
  } on CrossParentReorderException catch (e) {
    if (!context.mounted) return false;
    context.showErrorSnackBar('Could not $operationName: ${e.message}');
    return false;
  } on SnippetDeserializationException catch (e) {
    if (!context.mounted) return false;
    // Snippet/template imports get a dialog rather than a snackbar so
    // the user understands the snippet was rejected as a whole (not
    // imported partially). Wording mirrors the spec: "Snippet contains
    // unknown node type 'X' — this may be from a newer version of
    // Nightshade. The snippet was not imported."
    await _showSnippetRejectedDialog(context, e, operationName);
    return false;
  } on SequenceValidationFailedException catch (e) {
    if (!context.mounted) return false;
    // Validation failures get the rich preflight-style dialog with a
    // per-issue card and a "force action anyway" escape hatch.
    await showValidationIssueDialog(
      context,
      issues: e.issues,
      operationName: operationName,
      // No retry callback by default — caller can use
      // `showValidationIssueDialog` directly if they need the "force"
      // path (e.g. saveSequenceFile reruns with forceExport: true).
    );
    return false;
  }
}

Future<void> _showSnippetRejectedDialog(
  BuildContext context,
  SnippetDeserializationException e,
  String operationName,
) async {
  final colors = Theme.of(context).extension<NightshadeColors>()!;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Icon(LucideIcons.alertTriangle, color: colors.warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Could not $operationName',
              style: TextStyle(color: colors.textPrimary, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Snippet "${e.snippetName}" contains unknown node type '
            '"${e.unknownType}" — this may be from a newer version of '
            'Nightshade. The snippet was not imported.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
      actions: [
        NightshadeButton(
          onPressed: () => Navigator.of(ctx).pop(),
          label: 'OK',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
        ),
      ],
    ),
  );
}

/// Show a structured dialog listing each validation issue with severity
/// icon, category badge, description, and `resolutionHint`. Returns
/// `true` if the user clicked the "force" button — the caller is then
/// responsible for re-invoking whatever wanted to bypass the gate (e.g.
/// `exportSequence(forceExport: true)`).
///
/// Returns `false` (or `null`, treated as `false`) when the user
/// dismissed the dialog without choosing to force.
///
/// Pass [forceLabel] = `null` to suppress the force button entirely (used
/// when the calling operation has no "force anyway" mode — e.g. import).
Future<bool> showValidationIssueDialog(
  BuildContext context, {
  required List<ValidationIssue> issues,
  required String operationName,
  String? forceLabel = 'Force action anyway',
}) async {
  final colors = Theme.of(context).extension<NightshadeColors>()!;

  final errors =
      issues.where((i) => i.severity == ValidationSeverity.error).toList();
  final warnings =
      issues.where((i) => i.severity == ValidationSeverity.warning).toList();
  final infos =
      issues.where((i) => i.severity == ValidationSeverity.info).toList();

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ValidationDialogHeader(
                colors: colors,
                operationName: operationName,
                errorCount: errors.length,
                warningCount: warnings.length,
                infoCount: infos.length,
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final issue in issues)
                        _ValidationIssueCard(colors: colors, issue: issue),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    NightshadeButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      label: 'Cancel',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                    ),
                    if (forceLabel != null) ...[
                      const SizedBox(width: 12),
                      NightshadeButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        label: forceLabel,
                        variant: ButtonVariant.destructive,
                        size: ButtonSize.small,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result ?? false;
}

class _ValidationDialogHeader extends StatelessWidget {
  final NightshadeColors colors;
  final String operationName;
  final int errorCount;
  final int warningCount;
  final int infoCount;

  const _ValidationDialogHeader({
    required this.colors,
    required this.operationName,
    required this.errorCount,
    required this.warningCount,
    required this.infoCount,
  });

  @override
  Widget build(BuildContext context) {
    final hasErrors = errorCount > 0;
    final color = hasErrors ? colors.error : colors.warning;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              hasErrors ? LucideIcons.xCircle : LucideIcons.alertTriangle,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not $operationName',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasErrors
                      ? 'Sequence has $errorCount error(s) blocking this action.'
                      : 'Sequence has $warningCount warning(s).',
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
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}

class _ValidationIssueCard extends StatelessWidget {
  final NightshadeColors colors;
  final ValidationIssue issue;

  const _ValidationIssueCard({required this.colors, required this.issue});

  @override
  Widget build(BuildContext context) {
    Color severityColor;
    IconData severityIcon;
    switch (issue.severity) {
      case ValidationSeverity.error:
        severityColor = colors.error;
        severityIcon = LucideIcons.xCircle;
        break;
      case ValidationSeverity.warning:
        severityColor = colors.warning;
        severityIcon = LucideIcons.alertTriangle;
        break;
      case ValidationSeverity.info:
        severityColor = colors.info;
        severityIcon = LucideIcons.info;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(severityIcon, size: 14, color: severityColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        issue.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.surface,
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
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
}
