import 'dart:async';
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

/// What the step currently knows about the chosen folder.
///
/// The green "Folder is writable." line used to be derived from
/// `draft.captureDirectory != null` — i.e. from the mere existence of a
/// remembered path. The draft survives app restarts and host switches, so the
/// step asserted writability for folders it had never touched: a resumed draft
/// whose external drive was unplugged, or a host path shown after dropping back
/// to the local backend, both rendered a green tick. Writability is a claim
/// about the filesystem *now*, so it is tracked as the outcome of an actual
/// check and never inferred from a stored string.
enum _FolderCheck {
  /// A check is in flight.
  checking,

  /// A check passed for [_OnboardingCaptureDirStepState._checkedPath].
  writable,

  /// A check ran and rejected the folder.
  failed,

  /// No check could be made (the host is unreachable). Reported as unknown
  /// rather than dressed up as either outcome.
  unverified,
}

/// Capture-directory step.
///
/// Lets the user pick a folder where Nightshade will save captures.
/// Validation runs immediately on the chosen path:
///   * the path must exist (or be creatable),
///   * the process must be able to write a probe file there.
/// Both checks happen against the real filesystem — no shortcuts — so
/// the user discovers permission issues before their first session
/// instead of mid-capture.
///
/// The same checks re-run when the step is re-entered carrying a remembered
/// path, and after a host switch, so the confirmation on screen always
/// describes a check that actually happened against the filesystem the captures
/// will land on.
class OnboardingCaptureDirStep extends ConsumerStatefulWidget {
  const OnboardingCaptureDirStep({super.key});

  @override
  ConsumerState<OnboardingCaptureDirStep> createState() =>
      _OnboardingCaptureDirStepState();
}

class _OnboardingCaptureDirStepState
    extends ConsumerState<OnboardingCaptureDirStep> {
  /// Outcome of the most recent check, or null when there is no folder to
  /// report on.
  _FolderCheck? _check;

  /// The folder [_check] describes. A draft path that does not match this has
  /// not been checked in this session, so no verdict is shown for it.
  String? _checkedPath;

  /// Why the folder was rejected, or why it could not be checked.
  String? _checkDetail;

  bool _selecting = false;
  bool _validating = false;
  int _operationGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Re-check a remembered path on entry. The draft persists across restarts
    // and the user reaches this step again by walking Back through the wizard;
    // in both cases the folder may have moved, been deleted, or belong to a
    // different machine since it was picked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final path = ref.read(onboardingDraftProvider).captureDirectory;
      if (path == null || path.trim().isEmpty) return;
      unawaited(_verify(path.trim()));
    });
  }

  /// Re-run the writability check for [path] and record the outcome.
  ///
  /// Local paths go through the same probe the picker uses. A host path is
  /// checked by the host itself; when there is no host to ask the result is
  /// [_FolderCheck.unverified] — the step says it does not know rather than
  /// claiming a folder on a machine it cannot reach is fine.
  Future<void> _verify(String path) async {
    final isRemote = ref.read(isRemoteModeProvider);
    final authority = ref.read(backendProvider);
    final generation = ++_operationGeneration;
    setState(() {
      _check = _FolderCheck.checking;
      _checkedPath = path;
      _checkDetail = null;
    });

    _FolderCheck outcome;
    String? detail;
    if (isRemote) {
      if (authority is NetworkBackend) {
        try {
          final result = await authority.validateRemoteDirectory(
            path,
            mustExist: true,
            mustBeWritable: true,
          );
          if (result['valid'] == true) {
            outcome = _FolderCheck.writable;
            detail = null;
          } else {
            final reason = result['error'];
            outcome = _FolderCheck.failed;
            detail = reason is String && reason.trim().isNotEmpty
                ? reason.trim()
                : 'The host rejected this folder.';
          }
        } catch (error) {
          outcome = _FolderCheck.unverified;
          detail = 'Could not ask the imaging host about this folder: $error';
        }
      } else {
        outcome = _FolderCheck.unverified;
        detail = 'This folder is on the imaging host, which is not connected '
            'right now.';
      }
    } else {
      try {
        final error =
            await ref.read(onboardingCaptureDirectoryValidatorProvider)(path);
        outcome = error == null ? _FolderCheck.writable : _FolderCheck.failed;
        detail = error;
      } catch (error) {
        outcome = _FolderCheck.unverified;
        detail = 'Could not check this folder: $error';
      }
    }

    if (!_isCurrent(generation, authority)) return;
    setState(() {
      _check = outcome;
      _checkDetail = detail;
    });
  }

  Future<void> _pickDirectory() async {
    final isRemote = ref.read(isRemoteModeProvider);
    final authority = ref.read(backendProvider);
    final generation = ++_operationGeneration;
    setState(() {
      _selecting = true;
      _check = null;
      _checkedPath = null;
      _checkDetail = null;
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
      // Remote paths are validated by the host inside the picker dialog, which
      // only returns a path after `validateRemoteDirectory(mustExist,
      // mustBeWritable)` passes — so a returned remote path is already checked
      // and re-asking would double the round-trip.
      final error = isRemote
          ? null
          : await ref.read(onboardingCaptureDirectoryValidatorProvider)(
              selected,
            );
      if (!_isCurrent(generation, authority)) return;
      setState(() {
        _validating = false;
        _checkedPath = selected;
        _check = error == null ? _FolderCheck.writable : _FolderCheck.failed;
        _checkDetail = error;
      });
      if (error == null) {
        await ref.read(onboardingCaptureDirectoryWriterProvider)(selected);
      }
    } catch (error) {
      if (!mounted || !_isCurrent(generation, authority)) return;
      setState(() {
        _selecting = false;
        _validating = false;
        _check = _FolderCheck.failed;
        _checkDetail = 'Could not set the capture folder: $error';
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
      if (previous == null || identical(previous, next)) return;
      // A verdict earned against the previous host says nothing about this one:
      // /mnt/captures may be a real, writable folder on the Pi and not exist at
      // all on the laptop the app just fell back to. Drop the outcome and
      // re-check the remembered path against whoever is answering now.
      _operationGeneration++;
      setState(() {
        _selecting = false;
        _validating = false;
        _check = null;
        _checkedPath = null;
        _checkDetail = null;
      });
      final path = ref.read(onboardingDraftProvider).captureDirectory;
      if (path != null && path.trim().isNotEmpty) {
        unawaited(_verify(path.trim()));
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
              if (_selecting ||
                  _validating ||
                  _check == _FolderCheck.checking) ...[
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
              ] else
                ..._buildVerdict(theme, colors, draft.captureDirectory),
            ],
          ),
        ),
      ],
    );
  }

  /// The one line under the folder row that states what is known about it.
  ///
  /// Every branch is backed by a check that ran: the success line appears only
  /// for the folder the last passing check actually looked at, and a folder that
  /// could not be reached is reported as unknown instead of being folded into
  /// either verdict.
  List<Widget> _buildVerdict(
    ThemeData theme,
    NightshadeColors colors,
    String? draftPath,
  ) {
    Widget line(IconData icon, Color color, String message) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ),
            ],
          ),
        );

    switch (_check) {
      case _FolderCheck.failed:
        return [
          line(
            NightshadeIcons.warning,
            colors.error,
            _checkDetail ?? 'That folder cannot be used.',
          ),
        ];
      case _FolderCheck.unverified:
        return [
          line(
            NightshadeIcons.info,
            colors.warning,
            '${_checkDetail ?? 'This folder could not be checked.'} '
            'Nightshade has not confirmed it is writable.',
          ),
        ];
      case _FolderCheck.writable:
        // Only for the folder the check examined. A draft path that has since
        // changed has not been checked, and silence is honest where a green
        // tick would not be.
        if (draftPath != null && draftPath.trim() == _checkedPath) {
          return [
            line(
                LucideIcons.checkCircle2, colors.success, 'Folder is writable.')
          ];
        }
        return const [];
      case _FolderCheck.checking:
      case null:
        return const [];
    }
  }

  bool _isCurrent(int generation, NightshadeBackend authority) {
    return mounted &&
        generation == _operationGeneration &&
        identical(ref.read(backendProvider), authority);
  }
}
