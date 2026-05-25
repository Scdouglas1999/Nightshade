import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Wave 6 Agent 5 — embeddable notes UI used by the target header card,
/// the session report dialog, and the history tab.
///
/// Two public surfaces:
///   * [TargetNotesSection]: collapsed-by-default panel that shows the
///     latest N notes for a target, with "View all" / "Add note" actions.
///   * [RunNotesSection]: same shape but scoped to a specific
///     `sequence_runs.id` instead of a target.
///   * [NoteEditorDialog]: modal sheet for creating or editing a note.
///   * [NotesQuickPromptDialog]: post-run "how did it go?" prompt that
///     pre-fills body from the just-finished run stats.
///
/// Why one file: every UI surface here renders the same `JournalNote`
/// record with the same affordances (markdown body, tag chips,
/// timestamp, edit/delete). Keeping the layout primitives co-located
/// means a future tweak to the markdown renderer or tag chip styling
/// only has one place to land.

// =============================================================================
// Section widgets (embedded in TargetHeaderCard / SessionReportDialog / HistoryTab)
// =============================================================================

/// Notes section for a specific target. Shows the two newest notes
/// inline, plus a "View all" link that opens [TargetNotesDialog] with
/// the full chronological list and the "Add note" button.
class TargetNotesSection extends ConsumerWidget {
  /// Logical target id (catalog id like "M31" or display name when no
  /// catalog id is set).
  final String targetId;

  /// Optional title for the section header — defaults to "Notes".
  final String headerLabel;

  /// Optional explicit "create note" defaults — used by post-run flow
  /// to attach a freshly-created note to a specific run.
  final int? defaultSequenceRunId;

  final NightshadeColors colors;

  /// When true, omit the section heading + outer container — the
  /// parent (e.g. the session report dialog) is supplying its own.
  final bool embedded;

  const TargetNotesSection({
    super.key,
    required this.targetId,
    required this.colors,
    this.headerLabel = 'Notes',
    this.defaultSequenceRunId,
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesForTargetProvider(targetId));
    return notesAsync.when(
      data: (notes) => _buildBody(context, ref, notes),
      loading: () => Padding(
        padding: const EdgeInsets.all(8),
        child: SizedBox(
          height: 14,
          width: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: colors.primary,
          ),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Notes unavailable: $e',
          style: TextStyle(fontSize: 11, color: colors.error),
        ),
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, WidgetRef ref, List<JournalNote> notes) {
    final preview = notes.take(2).toList(growable: false);
    final header = Row(
      children: [
        Icon(LucideIcons.bookOpen, size: 14, color: colors.primary),
        const SizedBox(width: 6),
        Text(
          headerLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 8),
        if (notes.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${notes.length}',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
          ),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(LucideIcons.plus, size: 14),
          label: const Text('Add note'),
          onPressed: () => _openCreateDialog(context, ref),
        ),
        if (notes.length > 2)
          TextButton(
            onPressed: () => _openAllNotesDialog(context),
            child: Text('View all (${notes.length})'),
          ),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(
              'No notes yet. The first one is always the most useful.',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          )
        else
          for (final note in preview) ...[
            _NoteTile(
              note: note,
              colors: colors,
              maxBodyLines: 3,
              onEdit: () => _openEditDialog(context, ref, note),
              onDelete: () => _confirmDelete(context, ref, note),
            ),
            const SizedBox(height: 6),
          ],
      ],
    );

    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 6), body],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 6), body],
      ),
    );
  }

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    final created = await showDialog<JournalNote>(
      context: context,
      builder: (_) => NoteEditorDialog(
        targetId: targetId,
        sequenceRunId: defaultSequenceRunId,
      ),
    );
    if (created != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note saved'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _openAllNotesDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => TargetNotesDialog(
        targetId: targetId,
        colors: colors,
        defaultSequenceRunId: defaultSequenceRunId,
      ),
    );
  }

  Future<void> _openEditDialog(
      BuildContext context, WidgetRef ref, JournalNote note) async {
    await showDialog<JournalNote>(
      context: context,
      builder: (_) => NoteEditorDialog(
        targetId: targetId,
        sequenceRunId: note.sequenceRunId,
        existing: note,
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, JournalNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This note will be permanently removed.'),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          NightshadeButton(
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(notesServiceProvider).deleteNote(note.id);
    }
  }
}

/// Notes section scoped to a single sequence run. Renders identically
/// to [TargetNotesSection] except the queries pull from
/// `notes_journal.sequence_run_id` and the "Add note" call attaches the
/// resulting record to that run id.
class RunNotesSection extends ConsumerWidget {
  final int sequenceRunId;
  final String targetId;
  final NightshadeColors colors;
  final String headerLabel;
  final bool embedded;

  const RunNotesSection({
    super.key,
    required this.sequenceRunId,
    required this.targetId,
    required this.colors,
    this.headerLabel = 'Notes',
    this.embedded = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(notesForRunProvider(sequenceRunId));
    return notesAsync.when(
      data: (notes) => _NotesPanelLayout(
        title: headerLabel,
        notes: notes,
        colors: colors,
        embedded: embedded,
        emptyHint: 'No notes for this run yet. Add one to record what worked.',
        onAdd: () => _openCreateDialog(context, ref),
        onEdit: (n) => _openEditDialog(context, ref, n),
        onDelete: (n) => _confirmDelete(context, ref, n),
      ),
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Text(
        'Notes unavailable: $e',
        style: TextStyle(fontSize: 11, color: colors.error),
      ),
    );
  }

  Future<void> _openCreateDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<JournalNote>(
      context: context,
      builder: (_) => NoteEditorDialog(
        targetId: targetId,
        sequenceRunId: sequenceRunId,
      ),
    );
  }

  Future<void> _openEditDialog(
      BuildContext context, WidgetRef ref, JournalNote note) async {
    await showDialog<JournalNote>(
      context: context,
      builder: (_) => NoteEditorDialog(
        targetId: targetId,
        sequenceRunId: sequenceRunId,
        existing: note,
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, JournalNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This note will be permanently removed.'),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          NightshadeButton(
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(notesServiceProvider).deleteNote(note.id);
    }
  }
}

/// Shared layout for the per-section "Notes" panel. Extracted so the
/// run and target variants stay visually identical.
class _NotesPanelLayout extends StatelessWidget {
  final String title;
  final List<JournalNote> notes;
  final NightshadeColors colors;
  final bool embedded;
  final String emptyHint;
  final VoidCallback onAdd;
  final void Function(JournalNote) onEdit;
  final void Function(JournalNote) onDelete;

  const _NotesPanelLayout({
    required this.title,
    required this.notes,
    required this.colors,
    required this.embedded,
    required this.emptyHint,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Icon(LucideIcons.bookOpen, size: 14, color: colors.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 8),
        if (notes.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${notes.length}',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
            ),
          ),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(LucideIcons.plus, size: 14),
          label: const Text('Add note'),
          onPressed: onAdd,
        ),
      ],
    );

    final body = notes.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Text(
              emptyHint,
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final n in notes) ...[
                _NoteTile(
                  note: n,
                  colors: colors,
                  maxBodyLines: 5,
                  onEdit: () => onEdit(n),
                  onDelete: () => onDelete(n),
                ),
                const SizedBox(height: 6),
              ],
            ],
          );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, const SizedBox(height: 6), body],
    );
    if (embedded) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: content,
    );
  }
}

// =============================================================================
// "View all" dialog
// =============================================================================

/// Modal that lists every note for a target chronologically with
/// search + tag filter and an "Add note" affordance.
class TargetNotesDialog extends ConsumerStatefulWidget {
  final String targetId;
  final NightshadeColors colors;
  final int? defaultSequenceRunId;

  const TargetNotesDialog({
    super.key,
    required this.targetId,
    required this.colors,
    this.defaultSequenceRunId,
  });

  @override
  ConsumerState<TargetNotesDialog> createState() => _TargetNotesDialogState();
}

class _TargetNotesDialogState extends ConsumerState<TargetNotesDialog> {
  String _query = '';
  final Set<String> _selectedTags = {};

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final notesAsync = ref.watch(notesForTargetProvider(widget.targetId));
    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 720,
      designHeight: 720,
    );
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: SizedBox(
        width: dialogSize.width,
        height: dialogSize.height,
        child: notesAsync.when(
          data: (notes) {
            // Collect all tags across notes for the chip filter row.
            final allTags = <String>{};
            for (final n in notes) {
              allTags.addAll(n.tags);
            }
            final filtered = notes.where((n) {
              if (_selectedTags.isNotEmpty &&
                  !_selectedTags.any((t) => n.tags.contains(t))) {
                return false;
              }
              if (_query.isEmpty) return true;
              final q = _query.toLowerCase();
              return n.body.toLowerCase().contains(q) ||
                  (n.title?.toLowerCase().contains(q) ?? false);
            }).toList(growable: false);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(notes.length, colors),
                _buildSearchRow(allTags, colors),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              notes.isEmpty
                                  ? 'No notes yet for this target.'
                                  : 'No notes match the current filter.',
                              style: TextStyle(
                                  fontSize: 13, color: colors.textMuted),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            return _NoteTile(
                              note: filtered[i],
                              colors: colors,
                              maxBodyLines: 10,
                              onEdit: () => _openEditor(context, filtered[i]),
                              onDelete: () =>
                                  _confirmDelete(context, filtered[i]),
                            );
                          },
                        ),
                ),
                _buildFooter(context, colors),
              ],
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: colors.primary),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load notes: $e',
              style: TextStyle(color: colors.error),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(int total, NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.bookOpen, size: 22, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notes — ${widget.targetId}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '$total note${total == 1 ? '' : 's'} on this target',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(LucideIcons.x, color: colors.textMuted),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchRow(Set<String> tags, NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search note bodies / titles',
              isDense: true,
              prefixIcon:
                  Icon(LucideIcons.search, size: 16, color: colors.textMuted),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final tag in tags)
                  FilterChip(
                    label: Text(tag),
                    selected: _selectedTags.contains(tag),
                    visualDensity: VisualDensity.compact,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedTags.add(tag);
                        } else {
                          _selectedTags.remove(tag);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, NightshadeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          FilledButton.icon(
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Add note'),
            onPressed: () async {
              final created = await showDialog<JournalNote>(
                context: context,
                builder: (_) => NoteEditorDialog(
                  targetId: widget.targetId,
                  sequenceRunId: widget.defaultSequenceRunId,
                ),
              );
              if (created != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Note saved'),
                      duration: Duration(seconds: 2)),
                );
              }
            },
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, JournalNote note) async {
    await showDialog<JournalNote>(
      context: context,
      builder: (_) => NoteEditorDialog(
        targetId: widget.targetId,
        sequenceRunId: note.sequenceRunId,
        existing: note,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, JournalNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => NightshadeDialog(
        title: 'Delete note?',
        icon: LucideIcons.trash2,
        width: 420,
        bodyPadding: const EdgeInsets.all(NightshadeTokens.spaceXl),
        actions: [
          NightshadeButton(
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          NightshadeButton(
            label: 'Delete',
            variant: ButtonVariant.destructive,
            size: ButtonSize.small,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: Text(
          'This note will be permanently removed.',
          style: TextStyle(color: widget.colors.textSecondary),
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(notesServiceProvider).deleteNote(note.id);
    }
  }
}

// =============================================================================
// Note tile (single-row preview)
// =============================================================================

class _NoteTile extends StatelessWidget {
  final JournalNote note;
  final NightshadeColors colors;
  final int maxBodyLines;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _NoteTile({
    required this.note,
    required this.colors,
    required this.maxBodyLines,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d, yyyy · HH:mm');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (note.sentiment != null) ...[
                Text(note.sentiment!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
              ],
              if (note.title != null && note.title!.isNotEmpty)
                Expanded(
                  child: Text(
                    note.title!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
              else
                Expanded(
                  child: Text(
                    dateFormat.format(note.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              if (note.sequenceRunId != null)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: NightshadeDecorations.statusChip(
                    colors.accent,
                    borderRadius: BorderRadius.circular(4),
                    bordered: false,
                  ),
                  child: Text(
                    'run #${note.sequenceRunId}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(LucideIcons.edit3, size: 14),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Edit',
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(LucideIcons.trash2, size: 14),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Delete',
                color: colors.error,
              ),
            ],
          ),
          if (note.title != null && note.title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                dateFormat.format(note.createdAt),
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            ),
          if (note.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            // Wave 6 Pack O — render note bodies as markdown so **bold**,
            // links, code-fences, and bullet lists land the way the user
            // typed them. `MarkdownBody` does not support a hard
            // `maxLines` clamp; we approximate it by truncating the
            // input string to ~80 characters per line of the requested
            // maxBodyLines and tagging an ellipsis when we cut.
            // `selectable: false` keeps the tile's onTap pass through
            // to the underlying NoteTile gesture; the full editor
            // dialog rehydrates the entire body.
            MarkdownBody(
              data: _truncateForPreview(note.body, maxBodyLines),
              shrinkWrap: true,
              fitContent: true,
              styleSheet: _noteBodyMarkdownStyle(context, colors),
              onTapLink: (_, href, __) {
                // Notes are local journal entries; opening external
                // links from a non-trusted source unilaterally would be
                // a UX surprise. Defer to the editor where the user can
                // copy URLs manually if they need to.
                if (href != null && href.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Open in editor to follow: $href'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
          if (note.tags.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final tag in note.tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: NightshadeDecorations.tintedBadge(
                      colors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '#$tag',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: colors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (note.attachments.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final path in note.attachments)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.paperclip,
                          size: 11, color: colors.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        path.split(RegExp(r'[\\/]')).last,
                        style: TextStyle(fontSize: 10, color: colors.textMuted),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Wave 6 Pack O — Markdown rendering helpers for _NoteTile
// =============================================================================

/// Truncate the note body to ~`maxLines * 80` characters before passing
/// it to [MarkdownBody], appending an ellipsis when we cut. We do this
/// rather than relying on `MarkdownBody`'s built-in clamping (it has
/// none) because the tile is a fixed-height preview that needs to fit
/// alongside the title row + tag chips + edit/delete affordances.
///
/// The constant 80 chars/line is a deliberate over-estimate so wide
/// markdown blocks (e.g. tables, code) still get a reasonable preview
/// without growing past the tile bounds.
String _truncateForPreview(String body, int maxLines) {
  final softLimit = maxLines * 80;
  if (body.length <= softLimit) return body;
  // Cut at the last newline before the soft limit so we don't bisect a
  // markdown structure (bullet, table row, fenced block).
  var cut = body.lastIndexOf('\n', softLimit);
  if (cut < softLimit ~/ 2) cut = softLimit; // give up on line-aware cut
  return '${body.substring(0, cut).trimRight()}…';
}

/// Build a [MarkdownStyleSheet] that pulls from the design-system
/// tokens so note bodies match the rest of the app. We keep the same
/// 12 pt body font as the original `Text` widget for visual parity
/// with previous releases.
MarkdownStyleSheet _noteBodyMarkdownStyle(
  BuildContext context,
  NightshadeColors colors,
) {
  final base = TextStyle(fontSize: 12, color: colors.textPrimary);
  return MarkdownStyleSheet(
    p: base,
    h1: base.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
    h2: base.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
    h3: base.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
    em: base.copyWith(fontStyle: FontStyle.italic),
    strong: base.copyWith(fontWeight: FontWeight.w700),
    code: base.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
      backgroundColor: colors.surfaceAlt,
      color: colors.accent,
    ),
    codeblockDecoration: BoxDecoration(
      color: colors.surfaceAlt,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: colors.border),
    ),
    codeblockPadding: const EdgeInsets.all(6),
    a: base.copyWith(
      color: colors.primary,
      decoration: TextDecoration.underline,
    ),
    blockquoteDecoration: BoxDecoration(
      color: colors.surfaceAlt,
      border: Border(
        left: BorderSide(color: colors.primary, width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    listBullet: base,
    tableHead: base.copyWith(fontWeight: FontWeight.w600),
    tableBody: base,
    tableBorder: TableBorder.all(color: colors.border, width: 0.5),
  );
}

// =============================================================================
// Note editor dialog (create + edit)
// =============================================================================

/// Modal for creating or editing a [JournalNote]. Returns the saved
/// note via `Navigator.pop`, or `null` when the user cancels.
class NoteEditorDialog extends ConsumerStatefulWidget {
  final String targetId;
  final int? sequenceRunId;
  final JournalNote? existing;
  final String? initialBody;
  final String? initialTitle;
  final String? initialSentiment;

  const NoteEditorDialog({
    super.key,
    required this.targetId,
    this.sequenceRunId,
    this.existing,
    this.initialBody,
    this.initialTitle,
    this.initialSentiment,
  });

  @override
  ConsumerState<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends ConsumerState<NoteEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _tagCtrl;
  late List<String> _tags;
  String? _sentiment;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
      text: widget.existing?.title ?? widget.initialTitle ?? '',
    );
    _bodyCtrl = TextEditingController(
      text: widget.existing?.body ?? widget.initialBody ?? '',
    );
    _tagCtrl = TextEditingController();
    _tags = List<String>.from(widget.existing?.tags ?? const <String>[]);
    _sentiment = widget.existing?.sentiment ?? widget.initialSentiment;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isEditing = widget.existing != null;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 560,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.bookOpen, size: 20, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit note' : 'New note',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (widget.sequenceRunId != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        'attached to run #${widget.sequenceRunId}',
                        style: TextStyle(fontSize: 11, color: colors.textMuted),
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, color: colors.textMuted),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _titleCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Title (optional)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _SentimentPicker(
                        value: _sentiment,
                        onChanged: (v) => setState(() => _sentiment = v),
                        colors: colors,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bodyCtrl,
                    minLines: 6,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Body (markdown supported)',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Add tag and press Enter',
                          ),
                          onSubmitted: _addTag,
                        ),
                      ),
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in _tags)
                          InputChip(
                            label: Text('#$tag'),
                            onDeleted: () => setState(() => _tags.remove(tag)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  if (isEditing)
                    TextButton.icon(
                      icon: const Icon(LucideIcons.trash2, size: 14),
                      label: const Text('Delete'),
                      onPressed: _saving ? null : _delete,
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(LucideIcons.save, size: 14),
                    label: Text(isEditing ? 'Save changes' : 'Save note'),
                    onPressed: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addTag(String raw) {
    final cleaned = raw.trim().replaceAll('#', '');
    if (cleaned.isEmpty) return;
    if (!_tags.contains(cleaned)) {
      setState(() {
        _tags.add(cleaned);
        _tagCtrl.clear();
      });
    } else {
      _tagCtrl.clear();
    }
  }

  Future<void> _save() async {
    final body = _bodyCtrl.text.trim();
    final title = _titleCtrl.text.trim();
    // Require either a body or sentiment so we never persist an
    // empty stub note that the user can't find later.
    if (body.isEmpty && _sentiment == null && title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a title, body, or sentiment before saving.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final service = ref.read(notesServiceProvider);
      final JournalNote saved;
      if (widget.existing == null) {
        saved = await service.addNote(
          targetId: widget.targetId,
          sequenceRunId: widget.sequenceRunId,
          body: body,
          title: title.isEmpty ? null : title,
          tags: _tags,
          sentiment: _sentiment,
        );
      } else {
        saved = await service.updateNote(
          widget.existing!.id,
          body: body,
          title: title.isEmpty ? null : title,
          tags: _tags,
          sentiment: _sentiment,
          clearTitle: title.isEmpty,
          clearSentiment: _sentiment == null,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save note: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(notesServiceProvider).deleteNote(existing.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SentimentPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final NightshadeColors colors;

  const _SentimentPicker({
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    const options = ['😊', '😐', '😞'];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final opt in options)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: InkWell(
              onTap: () => onChanged(value == opt ? null : opt),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: value == opt
                      ? NightshadeDecorations.selectedSurface(
                          colors.primary,
                          borderRadius: BorderRadius.circular(6),
                          fillAlpha: 0.18,
                        ).color
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: value == opt ? colors.primary : colors.border,
                  ),
                ),
                child: Text(opt, style: const TextStyle(fontSize: 18)),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Auto-prompt dialog (post-run "How did this go?" sheet)
// =============================================================================

/// Auto-prompt that appears after a run completes (when the
/// `notes.prompt_after_run` setting is true). Pre-fills body from run
/// stats and routes through the same [NoteEditorDialog] save path.
///
/// The dialog is intentionally a thin wrapper around [NoteEditorDialog]
/// that pre-populates fields — splitting them keeps the editor logic
/// in one place and means "edit note" / "create note" / "auto-prompt"
/// all behave identically.
class NotesQuickPromptDialog extends ConsumerWidget {
  final String targetId;
  final int? sequenceRunId;
  final String prefilledBody;
  final String? prefilledTitle;

  const NotesQuickPromptDialog({
    super.key,
    required this.targetId,
    required this.sequenceRunId,
    required this.prefilledBody,
    this.prefilledTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 560,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.messageCircle,
                      size: 22, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'How did this run go?',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(LucideIcons.x, color: colors.textMuted),
                    tooltip: 'Skip',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'A quick note now is worth a long memory later.',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                icon: const Icon(LucideIcons.pencil, size: 14),
                label: const Text('Write note'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await showDialog<JournalNote>(
                    context: context,
                    builder: (_) => NoteEditorDialog(
                      targetId: targetId,
                      sequenceRunId: sequenceRunId,
                      initialBody: prefilledBody,
                      initialTitle: prefilledTitle,
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  // "Don't ask again" disables the prompt for the
                  // current user globally; they can re-enable it from
                  // Settings → Sequencer → Notes.
                  await ref.read(notesPromptToggleProvider)(false);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text("Don't ask again"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
