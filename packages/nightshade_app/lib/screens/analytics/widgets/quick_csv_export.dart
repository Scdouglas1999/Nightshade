import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../utils/snackbar_helper.dart';

/// Quick one-click CSV export for a dataset.
///
/// Takes a list of rows (first row is the header) and exports them as CSV
/// to the standard Nightshade exports directory.
Future<void> quickCsvExport({
  required BuildContext context,
  required String filePrefix,
  required List<List<dynamic>> rows,
}) async {
  if (rows.length <= 1) {
    if (context.mounted) {
      context.showInfoSnackBar('No data to export.');
    }
    return;
  }

  try {
    final csv = const ListToCsvConverter().convert(rows);
    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir =
        Directory(path.join(docsDir.path, 'Nightshade', 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final fileName = '${filePrefix}_$timestamp.csv';
    final filePath = path.join(exportDir.path, fileName);
    final file = File(filePath);
    await file.writeAsString(csv);

    if (context.mounted) {
      context
          .showSuccessSnackBar('Exported ${rows.length - 1} rows to $filePath');
    }
  } catch (e) {
    if (context.mounted) {
      context.showErrorSnackBar('Export failed: $e');
    }
  }
}

/// Small icon button for quick export from a chart card header row.
class QuickExportButton extends StatefulWidget {
  final String tooltip;
  final Future<List<List<dynamic>>> Function() buildRows;
  final String filePrefix;

  const QuickExportButton({
    super.key,
    required this.tooltip,
    required this.buildRows,
    required this.filePrefix,
  });

  @override
  State<QuickExportButton> createState() => _QuickExportButtonState();
}

class _QuickExportButtonState extends State<QuickExportButton> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        onTap: _isExporting ? null : _export,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: _isExporting
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.textMuted,
                  ),
                )
              : Icon(
                  LucideIcons.download,
                  size: 14,
                  color: colors.textMuted,
                ),
        ),
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final rows = await widget.buildRows();
      if (mounted) {
        await quickCsvExport(
          context: context,
          filePrefix: widget.filePrefix,
          rows: rows,
        );
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }
}
