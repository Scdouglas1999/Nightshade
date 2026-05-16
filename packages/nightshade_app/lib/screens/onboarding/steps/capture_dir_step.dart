import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Capture-directory step.
///
/// Lets the user pick a folder where Nightshade will save captures.
/// Validation runs immediately on the chosen path:
///   * the path must exist (or be creatable),
///   * the process must be able to write a probe file there.
/// Both checks happen against the real filesystem — no shortcuts — so
/// the user discovers permission issues before their first session
/// instead of mid-capture.
class OnboardingCaptureDirStep extends ConsumerStatefulWidget {
  const OnboardingCaptureDirStep({super.key});

  @override
  ConsumerState<OnboardingCaptureDirStep> createState() =>
      _OnboardingCaptureDirStepState();
}

class _OnboardingCaptureDirStepState
    extends ConsumerState<OnboardingCaptureDirStep> {
  String? _validationError;
  bool _validating = false;

  Future<void> _pickDirectory() async {
    final selected = await file_selector.getDirectoryPath(
      confirmButtonText: 'Use this folder',
    );
    if (selected == null) return;
    await _setAndValidate(selected);
  }

  Future<void> _setAndValidate(String path) async {
    setState(() {
      _validating = true;
      _validationError = null;
    });
    final error = await _validateDirectory(path);
    if (!mounted) return;
    setState(() {
      _validating = false;
      _validationError = error;
    });
    if (error == null) {
      await ref
          .read(onboardingDraftProvider.notifier)
          .setCaptureDirectory(path);
    }
  }

  /// Validate that [path] is writable. Returns null on success or a
  /// human-readable error message describing what went wrong. We
  /// deliberately do not silently create the directory if it's missing —
  /// the user picked it, so we expect it to exist. We do, however, write
  /// and immediately delete a probe file so we know the directory is
  /// actually writable, not just listable.
  Future<String?> _validateDirectory(String path) async {
    if (path.trim().isEmpty) {
      return 'Pick a folder to continue.';
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      return 'That folder does not exist.';
    }
    final probe = File(
      '${dir.path}${Platform.pathSeparator}.nightshade_write_probe',
    );
    try {
      await probe.writeAsString('probe');
      await probe.delete();
      return null;
    } on FileSystemException catch (e) {
      return 'Not writable: ${e.message}';
    } catch (e) {
      return 'Validation failed: $e';
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Where should we save captures?',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Sessions will be organized into target/date subfolders under this directory.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.folder,
                      color: colors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      draft.captureDirectory ?? 'No folder selected yet',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: draft.captureDirectory != null
                            ? colors.textPrimary
                            : colors.textMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  NightshadeButton(
                    icon: LucideIcons.folderOpen,
                    label: 'Browse',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: _validating ? null : _pickDirectory,
                  ),
                ],
              ),
              if (_validating) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Checking write permissions…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
              if (_validationError != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(LucideIcons.alertTriangle,
                        size: 16, color: colors.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _validationError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else if (draft.captureDirectory != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(LucideIcons.checkCircle2,
                        size: 16, color: colors.success),
                    const SizedBox(width: 8),
                    Text(
                      'Folder is writable.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.success,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
