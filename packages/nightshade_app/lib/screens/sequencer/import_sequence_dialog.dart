import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../utils/snackbar_helper.dart';
import 'dialogs/import_summary_dialog.dart';

/// Top-level entry point for importing a NINA / SGP sequence.
///
/// Flow:
///   1. Open a file picker (.json / .sgf).
///   2. Read the file, detect format, parse + map (strict).
///   3. If [UnsupportedNodeError]: ask the user if they want to force-import
///      (which drops the unsupported nodes). If yes, retry in force mode.
///   4. Show [ImportSummaryDialog]. On confirm, persist to library +
///      optionally load into editor.
class ImportSequenceFlow {
  ImportSequenceFlow._();

  /// Run the full flow. Returns `true` if a sequence was imported (and saved
  /// and/or loaded into the editor), `false` if the user cancelled or an
  /// error occurred.
  static Future<bool> run(BuildContext context, WidgetRef ref) async {
    // Loop until the user either picks a file or explicitly cancels via the
    // "No file selected" prompt — silently aborting on first dismissal made
    // it look like the menu item was broken.
    file_selector.XFile? file;
    while (file == null) {
      file = await file_selector.openFile(
        acceptedTypeGroups: const [
          file_selector.XTypeGroup(
            label: 'NINA / SGP sequence',
            extensions: ['json', 'sgf'],
          ),
        ],
      );
      if (file != null) break;
      if (!context.mounted) return false;
      final retry = await _promptNoFileSelected(context);
      if (retry != true) return false;
      if (!context.mounted) return false;
    }

    final content = await File(file.path).readAsString();
    final importer = ref.read(sequenceImporterProvider);
    final defaultName = _basename(file.name);

    if (!context.mounted) return false;
    // First, try a strict (no-force) import.
    final ImportResult? result =
        await _parseWithRetry(context, importer, content, defaultName);
    if (result == null) return false;

    if (!context.mounted) return false;
    final decision = await ImportSummaryDialog.show(context, result: result);
    if (decision == null || decision.cancelled) return false;

    var sequence = result.sequence;
    if (decision.sequenceName.isNotEmpty &&
        decision.sequenceName != sequence.name) {
      sequence = sequence.copyWith(name: decision.sequenceName);
    }

    // Persist to library. Both destinations save — the only difference is
    // whether we also load the imported sequence into the editor.
    final repo = ref.read(sequenceRepositoryProvider);
    final int dbId;
    try {
      dbId = await repo.saveSequence(sequence);
      sequence = sequence.copyWith(databaseId: dbId);
    } catch (e) {
      if (!context.mounted) return false;
      context.showErrorSnackBar('Failed to save imported sequence: $e');
      return false;
    }

    final fmt = result.sourceFormat.displayName;
    switch (decision.destination!) {
      case ImportDestination.openInEditor:
        ref.read(currentSequenceProvider.notifier).loadSequence(sequence);
        if (!context.mounted) return true;
        context.showSuccessSnackBar(
            'Imported "${sequence.name}" ($fmt) and opened in editor');
        break;
      case ImportDestination.saveToLibrary:
        if (!context.mounted) return true;
        context.showSuccessSnackBar(
            'Saved "${sequence.name}" ($fmt) to library');
        break;
    }
    return true;
  }

  /// Parse [content]. If the strict parse fails with [UnsupportedNodeError],
  /// prompt the user to force-import (dropping the unsupported nodes) and
  /// retry in force mode. Returns `null` if the user cancelled or the file
  /// was otherwise unimportable.
  static Future<ImportResult?> _parseWithRetry(
    BuildContext context,
    SequenceImporter importer,
    String content,
    String defaultName,
  ) async {
    try {
      return importer.importFromString(
        content,
        forceUnsupported: false,
        sequenceName: defaultName,
      );
    } on UnknownFormatError catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar(
            'Could not identify file format: ${e.message}');
      }
      return null;
    } on MalformedSourceError catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('File is malformed: ${e.message}');
      }
      return null;
    } on UnsupportedNodeError catch (e) {
      if (!context.mounted) return null;
      final force = await _confirmForceImport(context, e.unsupported);
      if (force != true) return null;
      try {
        return importer.importFromString(
          content,
          forceUnsupported: true,
          sequenceName: defaultName,
        );
      } on UnknownFormatError catch (err) {
        if (context.mounted) {
          context.showErrorSnackBar('Force import failed: ${err.message}');
        }
        return null;
      } on MalformedSourceError catch (err) {
        if (context.mounted) {
          context.showErrorSnackBar('Force import failed: ${err.message}');
        }
        return null;
      }
    }
  }

  /// Shown after the user dismisses the file picker without selecting a
  /// file. Returns `true` if the user wants to reopen the picker, `false`
  /// if they want to cancel the import entirely.
  static Future<bool?> _promptNoFileSelected(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.fileX,
                        size: 18, color: colors.warning),
                    const SizedBox(width: 8),
                    Text(
                      'No file selected',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a NINA .json or SGP .sgf export to import.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    NightshadeButton(
                      label: 'Cancel',
                      variant: ButtonVariant.ghost,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                    const SizedBox(width: 8),
                    NightshadeButton(
                      label: 'Pick a file',
                      icon: LucideIcons.folderOpen,
                      size: ButtonSize.small,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _basename(String path) {
    final lastSep = path.lastIndexOf(RegExp(r'[\\/]'));
    final base = lastSep >= 0 ? path.substring(lastSep + 1) : path;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  static Future<bool?> _confirmForceImport(
    BuildContext context,
    List<UnsupportedNodeRecord> unsupported,
  ) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Row(
          children: [
            Icon(LucideIcons.alertTriangle, color: colors.warning, size: 18),
            const SizedBox(width: 8),
            const Text('Unsupported nodes'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This file uses ${unsupported.length} node type(s) Nightshade '
                "doesn't support. Importing them as-is would leave your "
                'sequence incomplete.',
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
              for (final u in unsupported.take(8))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text('- ${u.sourceType} - ${u.name}',
                      style: TextStyle(
                          fontSize: 12, color: colors.textSecondary)),
                ),
              if (unsupported.length > 8)
                Text('  ... and ${unsupported.length - 8} more',
                    style: TextStyle(
                        fontSize: 12, color: colors.textMuted)),
              const SizedBox(height: 12),
              Text(
                'You can force-import anyway. Unsupported nodes will be '
                'dropped and listed in the summary so you can re-create them '
                'manually.',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Force import'),
          ),
        ],
      ),
    );
  }
}
