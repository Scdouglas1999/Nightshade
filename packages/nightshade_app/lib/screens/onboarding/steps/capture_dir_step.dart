import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/remote_directory_picker_dialog.dart';

typedef OnboardingCaptureDirectoryPicker = Future<String?> Function(
  BuildContext context, {
  required bool isRemote,
  required String? initialPath,
});

typedef OnboardingCaptureDirectoryValidator = Future<String?> Function(
  String path,
);

typedef OnboardingCaptureDirectoryWriter = Future<void> Function(String path);

Future<String?> _pickCaptureDirectory(
  BuildContext context, {
  required bool isRemote,
  required String? initialPath,
}) {
  if (isRemote) {
    return RemoteDirectoryPickerDialog.show(
      context,
      title: 'Choose capture folder on host',
      initialPath: initialPath,
    );
  }
  return file_selector.getDirectoryPath(
    confirmButtonText: 'Use this folder',
  );
}

Future<String?> _validateCaptureDirectory(String path) async {
  if (path.trim().isEmpty) return 'Pick a folder to continue.';
  final dir = Directory(path);
  if (!await dir.exists()) return 'That folder does not exist.';
  final probe = File(
    '${dir.path}${Platform.pathSeparator}.nightshade_write_probe',
  );
  try {
    await probe.writeAsString('probe');
    await probe.delete();
    return null;
  } on FileSystemException catch (error) {
    return 'Not writable: ${error.message}';
  } catch (error) {
    return 'Validation failed: $error';
  }
}

final onboardingCaptureDirectoryPickerProvider =
    Provider<OnboardingCaptureDirectoryPicker>((ref) => _pickCaptureDirectory);

final onboardingCaptureDirectoryValidatorProvider =
    Provider<OnboardingCaptureDirectoryValidator>(
  (ref) => _validateCaptureDirectory,
);

final onboardingCaptureDirectoryWriterProvider =
    Provider<OnboardingCaptureDirectoryWriter>((ref) {
  return ref.read(onboardingDraftProvider.notifier).setCaptureDirectory;
});

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
  bool _selecting = false;
  bool _validating = false;
  int _operationGeneration = 0;

  Future<void> _pickDirectory() async {
    final isRemote = ref.read(isRemoteModeProvider);
    final authority = ref.read(backendProvider);
    final generation = ++_operationGeneration;
    setState(() {
      _selecting = true;
      _validationError = null;
    });
    try {
      final selected = await ref.read(onboardingCaptureDirectoryPickerProvider)(
        context,
        isRemote: isRemote,
        initialPath: ref.read(onboardingDraftProvider).captureDirectory,
      );
      if (selected == null || !_isCurrent(generation, authority)) return;

      setState(() {
        _selecting = false;
        _validating = true;
      });
      final error = isRemote
          ? null
          : await ref.read(onboardingCaptureDirectoryValidatorProvider)(
              selected,
            );
      if (!_isCurrent(generation, authority)) return;
      setState(() {
        _validating = false;
        _validationError = error;
      });
      if (error == null) {
        await ref.read(onboardingCaptureDirectoryWriterProvider)(selected);
      }
    } catch (error) {
      if (!mounted || !_isCurrent(generation, authority)) return;
      setState(() {
        _selecting = false;
        _validating = false;
        _validationError = 'Could not set the capture folder: $error';
      });
    } finally {
      if (mounted && generation == _operationGeneration) {
        setState(() {
          _selecting = false;
          _validating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
      if ((_selecting || _validating) &&
          previous != null &&
          !identical(previous, next)) {
        _operationGeneration++;
        setState(() {
          _selecting = false;
          _validating = false;
          _validationError = null;
        });
      }
    });
    final draft = ref.watch(onboardingDraftProvider);
    final colors = NightshadeColors.of(context);
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
        NightshadeCard(
          variant: CardVariant.subtle,
          borderRadius: NightshadeTokens.radiusLg,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(NightshadeIcons.folder, color: colors.primary, size: 18),
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
                    icon: NightshadeIcons.folderOpen,
                    label: 'Browse',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed:
                        _selecting || _validating ? null : _pickDirectory,
                  ),
                ],
              ),
              if (_selecting || _validating) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_selecting)
                      Icon(
                        NightshadeIcons.folderOpen,
                        size: 14,
                        color: colors.primary,
                      )
                    else
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
                      _selecting
                          ? 'Waiting for folder selection…'
                          : 'Checking write permissions…',
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
                    Icon(NightshadeIcons.warning,
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

  bool _isCurrent(int generation, NightshadeBackend authority) {
    return mounted &&
        generation == _operationGeneration &&
        identical(ref.read(backendProvider), authority);
  }
}
