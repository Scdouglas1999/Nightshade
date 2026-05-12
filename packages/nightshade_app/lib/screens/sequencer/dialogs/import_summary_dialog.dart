import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// What the user chose to do with an imported sequence once they've reviewed
/// the parse summary.
enum ImportDestination {
  /// Persist into the sequences table via [SequenceRepository] and then load
  /// into the editor.
  saveAndOpen,

  /// Load into the editor only — the user can save later through the normal
  /// save flow.
  openOnly,
}

/// Decision the user made in the dialog. `null` `destination` means the user
/// cancelled.
class ImportSummaryDecision {
  final ImportDestination? destination;
  final String sequenceName;

  const ImportSummaryDecision({
    required this.destination,
    required this.sequenceName,
  });

  bool get cancelled => destination == null;
}

/// Post-parse summary dialog. Shows what was found in the source file, what
/// got dropped/unsupported, and lets the user pick where the imported
/// sequence should land.
class ImportSummaryDialog extends StatefulWidget {
  final ImportResult result;

  const ImportSummaryDialog({super.key, required this.result});

  @override
  State<ImportSummaryDialog> createState() => _ImportSummaryDialogState();

  /// Convenience for callers: show the dialog and await its
  /// [ImportSummaryDecision].
  static Future<ImportSummaryDecision?> show(
    BuildContext context, {
    required ImportResult result,
  }) {
    return showDialog<ImportSummaryDecision>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportSummaryDialog(result: result),
    );
  }
}

class _ImportSummaryDialogState extends State<ImportSummaryDialog> {
  late TextEditingController _nameController;
  ImportDestination _destination = ImportDestination.saveAndOpen;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.result.sequence.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final result = widget.result;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(colors: colors, result: result),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _NameField(
                      controller: _nameController,
                      colors: colors,
                    ),
                    const SizedBox(height: 16),
                    _OverviewRow(colors: colors, result: result),
                    const SizedBox(height: 16),
                    _MappingTable(colors: colors, rows: result.mappingTable),
                    if (result.droppedNodes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _DroppedSection(
                          colors: colors, dropped: result.droppedNodes),
                    ],
                    if (result.unsupportedNodes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _UnsupportedSection(
                          colors: colors,
                          unsupported: result.unsupportedNodes,
                          forced: result.forcedImport),
                    ],
                    const SizedBox(height: 16),
                    _DestinationPicker(
                      colors: colors,
                      destination: _destination,
                      onChanged: (d) => setState(() => _destination = d),
                    ),
                  ],
                ),
              ),
            ),
            _Footer(
              colors: colors,
              onCancel: () => Navigator.of(context).pop(
                  const ImportSummaryDecision(
                      destination: null, sequenceName: '')),
              onImport: () {
                Navigator.of(context).pop(ImportSummaryDecision(
                  destination: _destination,
                  sequenceName: _nameController.text.trim().isEmpty
                      ? widget.result.sequence.name
                      : _nameController.text.trim(),
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final NightshadeColors colors;
  final ImportResult result;
  const _Header({required this.colors, required this.result});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.fileInput, size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Sequence — ${result.sourceFormat.displayName}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${result.totalNodes} source nodes parsed',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
          if (result.forcedImport)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: colors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 12, color: colors.warning),
                  const SizedBox(width: 4),
                  Text('Force import',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colors.warning)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NameField extends StatelessWidget {
  final TextEditingController controller;
  final NightshadeColors colors;
  const _NameField({required this.controller, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sequence name',
            style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: colors.border)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _OverviewRow extends StatelessWidget {
  final NightshadeColors colors;
  final ImportResult result;
  const _OverviewRow({required this.colors, required this.result});

  @override
  Widget build(BuildContext context) {
    final mapped = result.mappingTable
        .where((r) => r.nightshadeType != null)
        .fold<int>(0, (a, b) => a + b.count);
    return Row(
      children: [
        _Pill(
          label: 'Mapped',
          value: '$mapped',
          color: colors.success,
        ),
        const SizedBox(width: 10),
        _Pill(
          label: 'Dropped',
          value: '${result.droppedNodes.length}',
          color: colors.textMuted,
        ),
        const SizedBox(width: 10),
        _Pill(
          label: 'Unsupported',
          value: '${result.unsupportedNodes.length}',
          color: result.unsupportedNodes.isEmpty
              ? colors.textMuted
              : colors.warning,
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Pill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MappingTable extends StatelessWidget {
  final NightshadeColors colors;
  final List<MappingTableRow> rows;
  const _MappingTable({required this.colors, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text('No mappings were recorded.',
          style: TextStyle(fontSize: 12, color: colors.textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mapping',
            style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: i == rows.length - 1
                        ? null
                        : Border(
                            bottom: BorderSide(color: colors.border)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Text(rows[i].sourceType,
                            style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary)),
                      ),
                      Icon(LucideIcons.arrowRight,
                          size: 14, color: colors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: Text(
                          rows[i].nightshadeType ?? '<dropped>',
                          style: TextStyle(
                              fontSize: 12,
                              color: rows[i].nightshadeType == null
                                  ? colors.textMuted
                                  : colors.textPrimary,
                              fontStyle: rows[i].nightshadeType == null
                                  ? FontStyle.italic
                                  : FontStyle.normal),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${rows[i].count}',
                            style: TextStyle(
                                fontSize: 11,
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DroppedSection extends StatelessWidget {
  final NightshadeColors colors;
  final List<DroppedNodeRecord> dropped;
  const _DroppedSection({required this.colors, required this.dropped});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dropped (${dropped.length})',
            style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (final d in dropped)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(LucideIcons.x, size: 12, color: colors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${d.sourceType} — ${d.name} (${_reasonLabel(d.reason)})',
                    style: TextStyle(
                        fontSize: 12, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _reasonLabel(DropReason r) {
    switch (r) {
      case DropReason.decorative:
        return 'non-functional';
      case DropReason.disabled:
        return 'disabled in source';
      case DropReason.unsupported:
        return 'unsupported, forced';
    }
  }
}

class _UnsupportedSection extends StatelessWidget {
  final NightshadeColors colors;
  final List<UnsupportedNodeRecord> unsupported;
  final bool forced;
  const _UnsupportedSection({
    required this.colors,
    required this.unsupported,
    required this.forced,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        border: Border.all(color: colors.warning.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.alertTriangle,
                  size: 14, color: colors.warning),
              const SizedBox(width: 6),
              Text('Unsupported nodes (${unsupported.length})',
                  style: TextStyle(
                      fontSize: 12,
                      color: colors.warning,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          if (forced)
            Text(
              'These were skipped because force-import was requested. '
              'Your sequence will run without them.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            )
          else
            Text(
              'These would have aborted the import in strict mode.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          const SizedBox(height: 6),
          for (final u in unsupported)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('• ${u.sourceType} — ${u.name}',
                  style: TextStyle(
                      fontSize: 12, color: colors.textSecondary)),
            ),
        ],
      ),
    );
  }
}

class _DestinationPicker extends StatelessWidget {
  final NightshadeColors colors;
  final ImportDestination destination;
  final ValueChanged<ImportDestination> onChanged;
  const _DestinationPicker({
    required this.colors,
    required this.destination,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('After import',
            style: TextStyle(
                fontSize: 12,
                color: colors.textMuted,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        RadioListTile<ImportDestination>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: ImportDestination.saveAndOpen,
          groupValue: destination,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          title: Text('Save to library and open in editor',
              style:
                  TextStyle(fontSize: 13, color: colors.textPrimary)),
        ),
        RadioListTile<ImportDestination>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: ImportDestination.openOnly,
          groupValue: destination,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          title: Text('Open in editor only (don\'t save yet)',
              style:
                  TextStyle(fontSize: 13, color: colors.textPrimary)),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  final NightshadeColors colors;
  final VoidCallback onCancel;
  final VoidCallback onImport;
  const _Footer({
    required this.colors,
    required this.onCancel,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: onCancel,
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(LucideIcons.check, size: 14),
            label: const Text('Import'),
          ),
        ],
      ),
    );
  }
}
