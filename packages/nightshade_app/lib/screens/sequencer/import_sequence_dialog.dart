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
///   4. Show [ImportSummaryDialog]. On confirm, persist + load into editor.
class ImportSequenceFlow {
  ImportSequenceFlow._();

  /// Run the full flow. Returns `true` if a sequence was imported and loaded
  /// into the current sequence provider, `false` otherwise.
  static Future<bool> run(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final file = await file_selector.openFile(
      acceptedTypeGroups: const [
        file_selector.XTypeGroup(
          label: 'NINA / SGP sequence',
          extensions: ['json', 'sgf'],
        ),
      ],
    );
    if (file == null) return false;

    final content = await File(file.path).readAsString();
    final importer = ref.read(sequenceImporterProvider);
    final defaultName = _basename(file.name);

    ImportResult result;
    try {
      result = importer.importFromString(
        content,
        forceUnsupported: false,
        sequenceName: defaultName,
      );
    } on UnknownFormatError catch (e) {
      _showError(messenger,
          'Could not identify file format: ${e.message}');
      return false;
    } on MalformedSourceError catch (e) {
      _showError(messenger, 'File is malformed: ${e.message}');
      return false;
    } on UnsupportedNodeError catch (e) {
      final force = await _confirmForceImport(navigator.context, e.unsupported);
      if (force != true) return false;
      try {
        result = importer.importFromString(
          content,
          forceUnsupported: true,
          sequenceName: defaultName,
        );
      } catch (err) {
        _showError(messenger, 'Force import failed: $err');
        return false;
      }
    } catch (e) {
      _showError(messenger, 'Import failed: $e');
      return false;
    }

    if (!navigator.context.mounted) return false;
    final decision = await ImportSummaryDialog.show(
      navigator.context,
      result: result,
    );
    if (decision == null || decision.cancelled) return false;

    // Rename the sequence per user's edit (default kept if they didn't change
    // it).
    var sequence = result.sequence;
    if (decision.sequenceName != sequence.name) {
      sequence = sequence.copyWith(name: decision.sequenceName);
    }

    // Persist if requested.
    if (decision.destination == ImportDestination.saveAndOpen) {
      try {
        final repo = ref.read(sequenceRepositoryProvider);
        final dbId = await repo.saveSequence(sequence);
        sequence = sequence.copyWith(databaseId: dbId);
      } catch (e) {
        _showError(messenger, 'Failed to save imported sequence: $e');
        return false;
      }
    }

    // Load into the editor.
    ref.read(currentSequenceProvider.notifier).loadSequence(sequence);

    if (context.mounted) {
      context.showSuccessSnackBar(
          'Imported "${sequence.name}" (${result.sourceFormat.displayName})');
    }
    return true;
  }

  static String _basename(String path) {
    final lastSep = path.lastIndexOf(RegExp(r'[\\/]'));
    final base = lastSep >= 0 ? path.substring(lastSep + 1) : path;
    final dot = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  static void _showError(ScaffoldMessengerState m, String msg) {
    m.showSnackBar(SnackBar(content: Text(msg)));
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
                  child: Text('• ${u.sourceType} — ${u.name}',
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
