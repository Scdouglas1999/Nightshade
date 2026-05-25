import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'run_dashboard/frame_detail_dialog.dart';

/// Wave 8 Replay Debug — retrospective decision-tree scrubber.
///
/// Opened from the history tab via "Replay" on each run row. Renders
/// every persisted [ReplayDecision] for the run in chronological order
/// with filter chips (by category), full-text search, and a time-range
/// slider that lets the user zoom into a specific window.
///
/// Each row exposes a "View details" expansion that pretty-prints the
/// structured `details` map. The "Add note at this time" action
/// pre-fills a Wave 6 Agent 5 [NotesService] note with the row's
/// timestamp + summary so journaling the night the next morning is
/// one click away.
class ReplayDebugScreen extends ConsumerStatefulWidget {
  const ReplayDebugScreen({
    required this.sequenceRunId,
    required this.sequenceName,
    this.startedAt,
    this.endedAt,
    super.key,
  });

  /// `sequence_runs.id` of the run to scrub.
  final int sequenceRunId;

  /// Display label for the app bar.
  final String sequenceName;

  /// Wall-clock anchors used by the time-range slider. Optional because
  /// older runs may not have populated the `ended_at` column.
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Convenience launcher — wraps the screen in a [MaterialPageRoute]
  /// and pushes it.
  static Future<void> push(
    BuildContext context, {
    required int sequenceRunId,
    required String sequenceName,
    DateTime? startedAt,
    DateTime? endedAt,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReplayDebugScreen(
          sequenceRunId: sequenceRunId,
          sequenceName: sequenceName,
          startedAt: startedAt,
          endedAt: endedAt,
        ),
      ),
    );
  }

  @override
  ConsumerState<ReplayDebugScreen> createState() => _ReplayDebugScreenState();
}

class _ReplayDebugScreenState extends ConsumerState<ReplayDebugScreen> {
  /// User-selected category filter. `null` = show all.
  DecisionCategory? _categoryFilter;

  /// Free-text search in the summary field.
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchTerm = '';

  /// Time-range filter (0.0..1.0 fraction of the run span). `null` =
  /// no clamp. Initialised lazily once we know the run span.
  RangeValues? _timeRange;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final decisionsAsync =
        ref.watch(decisionsForRunProvider(widget.sequenceRunId));

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Replay — ${widget.sequenceName}'),
        backgroundColor: colors.surface,
        actions: [
          IconButton(
            tooltip: 'Clear filters',
            icon: const Icon(LucideIcons.x, size: 18),
            onPressed: _resetFilters,
          ),
        ],
      ),
      body: decisionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load replay log: $err',
                style: TextStyle(color: colors.error)),
          ),
        ),
        data: (decisions) {
          if (decisions.isEmpty) {
            return _emptyState(colors);
          }
          return _buildBody(colors, decisions);
        },
      ),
    );
  }

  Widget _emptyState(NightshadeColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.fileSearch, size: 56, color: colors.textMuted),
          const SizedBox(height: 12),
          Text(
            'No decisions recorded for this run.',
            style: TextStyle(fontSize: 14, color: colors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            'Older runs may pre-date the replay log.',
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    NightshadeColors colors,
    List<ReplayDecision> all,
  ) {
    final spanStart = widget.startedAt ?? all.first.timestamp;
    final spanEnd = widget.endedAt ?? all.last.timestamp;
    final spanMillis =
        spanEnd.millisecondsSinceEpoch - spanStart.millisecondsSinceEpoch;
    _timeRange ??= const RangeValues(0, 1);
    final filtered = _applyFilters(all, spanStart, spanMillis);

    return Column(
      children: [
        _filterBar(colors),
        if (spanMillis > 0) _timeRangeSlider(colors, spanStart, spanEnd),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(LucideIcons.list, size: 14, color: colors.textMuted),
              const SizedBox(width: 6),
              Text(
                '${filtered.length} of ${all.length} decisions',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final d = filtered[i];
              return _DecisionTile(
                decision: d,
                colors: colors,
                searchTerm: _searchTerm,
                onAddNote: () => _addNoteForDecision(d),
                onJumpToForensics: () => _jumpToForensicsForDecision(d),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterBar(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search.
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search summary…',
              prefixIcon:
                  Icon(LucideIcons.search, size: 16, color: colors.textMuted),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: _searchTerm.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(LucideIcons.x, size: 14),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchTerm = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _searchTerm = v.trim()),
          ),
          const SizedBox(height: 12),
          // Category chips.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('All'),
                selected: _categoryFilter == null,
                onSelected: (sel) => setState(() => _categoryFilter = null),
              ),
              ...DecisionCategory.values
                  .where((c) => c != DecisionCategory.unknown)
                  .map(
                    (c) => FilterChip(
                      label: Text(c.displayLabel),
                      selected: _categoryFilter == c,
                      selectedColor:
                          _categoryColor(c, colors).withValues(alpha: 0.3),
                      onSelected: (sel) =>
                          setState(() => _categoryFilter = sel ? c : null),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeRangeSlider(
    NightshadeColors colors,
    DateTime spanStart,
    DateTime spanEnd,
  ) {
    final range = _timeRange ?? const RangeValues(0, 1);
    final startLabel = DateFormat('HH:mm:ss')
        .format(_offsetFromFraction(spanStart, spanEnd, range.start));
    final endLabel = DateFormat('HH:mm:ss')
        .format(_offsetFromFraction(spanStart, spanEnd, range.end));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Time range: $startLabel — $endLabel',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (range.start > 0 || range.end < 1)
                TextButton(
                  onPressed: () =>
                      setState(() => _timeRange = const RangeValues(0, 1)),
                  child: const Text('Reset', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          RangeSlider(
            values: range,
            divisions: 100,
            onChanged: (v) => setState(() => _timeRange = v),
          ),
        ],
      ),
    );
  }

  DateTime _offsetFromFraction(
    DateTime spanStart,
    DateTime spanEnd,
    double frac,
  ) {
    final span =
        spanEnd.millisecondsSinceEpoch - spanStart.millisecondsSinceEpoch;
    final off = (span * frac).round();
    return DateTime.fromMillisecondsSinceEpoch(
      spanStart.millisecondsSinceEpoch + off,
      isUtc: spanStart.isUtc,
    );
  }

  List<ReplayDecision> _applyFilters(
    List<ReplayDecision> all,
    DateTime spanStart,
    int spanMillis,
  ) {
    final range = _timeRange;
    final minMillis = (range == null || spanMillis <= 0)
        ? spanStart.millisecondsSinceEpoch
        : spanStart.millisecondsSinceEpoch + (spanMillis * range.start).round();
    final maxMillis = (range == null || spanMillis <= 0)
        ? spanStart.millisecondsSinceEpoch + spanMillis
        : spanStart.millisecondsSinceEpoch + (spanMillis * range.end).round();

    final term = _searchTerm.toLowerCase();
    return all.where((d) {
      if (_categoryFilter != null && d.category != _categoryFilter) {
        return false;
      }
      if (term.isNotEmpty &&
          !d.summary.toLowerCase().contains(term) &&
          !(d.nodeId?.toLowerCase().contains(term) ?? false)) {
        return false;
      }
      final ms = d.timestamp.millisecondsSinceEpoch;
      if (ms < minMillis || ms > maxMillis) return false;
      return true;
    }).toList(growable: false);
  }

  void _resetFilters() {
    setState(() {
      _categoryFilter = null;
      _searchCtrl.clear();
      _searchTerm = '';
      _timeRange = const RangeValues(0, 1);
    });
  }

  /// Wave 6 Agent 5 cross-link — pre-fill a journal note with the
  /// decision's timestamp + summary. The note is saved immediately
  /// (silent insert) so the operator's next visit to the run's notes
  /// list shows the entry; a snackbar confirms.
  Future<void> _addNoteForDecision(ReplayDecision d) async {
    final notesService = ref.read(notesServiceProvider);
    final body = StringBuffer()
      ..writeln(
          'At ${DateFormat.yMd().add_Hms().format(d.timestamp.toLocal())}: ${d.summary}')
      ..writeln()
      ..writeln('Category: ${d.category.displayLabel}');
    if (d.nodeId != null) body.writeln('Node: ${d.nodeId}');
    if (d.details.isNotEmpty) {
      body.writeln();
      body.writeln('Details:');
      body.writeln(const JsonEncoder.withIndent('  ').convert(d.details));
    }
    // Target id is not part of a decision row; we file the note
    // against a synthetic "run-${runId}" target so the run-scoped
    // view (notesForRunProvider) surfaces it. The Wave 6 NotesService
    // requires a non-empty target id, so we use the run wrapper.
    await notesService.addNote(
      targetId: 'run-${widget.sequenceRunId}',
      title: 'Replay: ${d.category.displayLabel}',
      body: body.toString(),
      sequenceRunId: widget.sequenceRunId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Note added for this decision'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Wave 8 Forensics cross-link — open the same Frame Detail dialog
  /// used by the run dashboard when a replayed FrameRejected decision
  /// carries a captured-image id.
  Future<void> _jumpToForensicsForDecision(ReplayDecision d) async {
    final imageId = _readImageId(d.details['captured_image_id']) ??
        _readImageId(d.details['image_id']);
    if (!mounted) return;
    if (imageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No captured image id is linked to this row'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    await FrameDetailDialog.showForFrame(context, imageId: imageId);
  }

  int? _readImageId(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

/// Category-coded badge color. Stays consistent between the filter
/// chip and the row badge for visual continuity.
Color _categoryColor(DecisionCategory c, NightshadeColors colors) {
  switch (c) {
    case DecisionCategory.schedulerPick:
      return colors.primary;
    case DecisionCategory.triggerFired:
      return colors.warning;
    case DecisionCategory.recoveryEntered:
      return colors.error;
    case DecisionCategory.budgetMet:
      return colors.success;
    case DecisionCategory.adaptiveSwap:
      return colors.primary;
    case DecisionCategory.frameAccepted:
      return colors.success;
    case DecisionCategory.frameRejected:
      return colors.warning;
    case DecisionCategory.pluginNodeInvoked:
      return colors.textMuted;
    case DecisionCategory.manualIntervention:
      return colors.primary;
    case DecisionCategory.systemEvent:
      return colors.textMuted;
    case DecisionCategory.unknown:
      return colors.textMuted;
  }
}

class _DecisionTile extends StatefulWidget {
  const _DecisionTile({
    required this.decision,
    required this.colors,
    required this.searchTerm,
    required this.onAddNote,
    required this.onJumpToForensics,
  });

  final ReplayDecision decision;
  final NightshadeColors colors;
  final String searchTerm;
  final VoidCallback onAddNote;
  final VoidCallback onJumpToForensics;

  @override
  State<_DecisionTile> createState() => _DecisionTileState();
}

class _DecisionTileState extends State<_DecisionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final badgeColor = _categoryColor(widget.decision.category, c);
    final tsLocal = widget.decision.timestamp.toLocal();
    final timeLabel = DateFormat('HH:mm:ss').format(tsLocal);
    final isForensicsLinked =
        widget.decision.category == DecisionCategory.frameRejected ||
            widget.decision.details.containsKey('captured_image_id') ||
            widget.decision.details.containsKey('reject_path');

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: c.border.withValues(alpha: 0.5)),
          left: BorderSide(color: badgeColor, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 76,
                  child: Text(
                    timeLabel,
                    style: TextStyle(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: 12,
                      color: c.textMuted,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: NightshadeDecorations.statusChip(
                    badgeColor,
                    borderRadius: BorderRadius.circular(4),
                    bordered: false,
                  ),
                  child: Text(
                    widget.decision.category.displayLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.decision.summary,
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? 'Hide details' : 'View details',
                  icon: Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 16,
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.decision.nodeId != null)
                      Text('Node: ${widget.decision.nodeId}',
                          style: TextStyle(fontSize: 11, color: c.textMuted)),
                    if (widget.decision.details.isEmpty)
                      Text(
                        'No extra details.',
                        style: TextStyle(fontSize: 11, color: c.textMuted),
                      )
                    else
                      Text(
                        const JsonEncoder.withIndent('  ')
                            .convert(widget.decision.details),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: c.textPrimary,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [
                        TextButton.icon(
                          onPressed: widget.onAddNote,
                          icon: const Icon(LucideIcons.bookOpen, size: 12),
                          label: const Text('Add note',
                              style: TextStyle(fontSize: 11)),
                        ),
                        if (isForensicsLinked)
                          TextButton.icon(
                            onPressed: widget.onJumpToForensics,
                            icon: const Icon(LucideIcons.fileSearch, size: 12),
                            label: const Text('Forensics',
                                style: TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
