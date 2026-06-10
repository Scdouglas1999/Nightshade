import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'settings_widgets.dart';

/// Calibration Library Manager — the unified browse / tag / auto-match
/// surface over the master calibration artifacts the imaging pipeline
/// records (darks, biases, master flats, defect maps), joined with the v46
/// user-tag / notes layer.
///
/// Three panes:
///  * filter bar (type / camera / filter) over a list of master tiles;
///  * each tile shows type badge, key capture params, age/freshness, tags,
///    and edit / delete actions;
///  * a collapsible matching-preview that takes a light-frame context and
///    shows which master auto-selects per type and exactly why.
class CalibrationLibrarySettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const CalibrationLibrarySettings({super.key, this.isMobile = false});

  @override
  ConsumerState<CalibrationLibrarySettings> createState() =>
      _CalibrationLibrarySettingsState();
}

class _CalibrationLibrarySettingsState
    extends ConsumerState<CalibrationLibrarySettings> {
  CalibrationMasterType? _typeFilter;
  bool _loading = true;
  Object? _error;
  List<CalibrationMasterRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  CalibrationLibraryService get _service =>
      ref.read(calibrationLibraryServiceProvider);

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _service.listMasters(
        filter: CalibrationLibraryFilter(type: _typeFilter),
      );
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Calibration Library',
      description: 'Browse, tag, and auto-match master darks, flats, '
          'biases, and defect maps',
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        SettingsSection(
          title: 'Masters',
          isMobile: widget.isMobile,
          children: [
            _buildFilterBar(context),
            const SizedBox(height: 12),
            _buildList(context),
          ],
        ),
        SettingsSection(
          title: 'Matching Preview',
          isMobile: widget.isMobile,
          children: [
            _MatchingPreview(service: _service),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<CalibrationMasterType?>(
            initialValue: _typeFilter,
            decoration: const InputDecoration(
              labelText: 'Type',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All types')),
              for (final type in CalibrationMasterType.values)
                DropdownMenuItem(
                    value: type, child: Text(_typeLabel(type))),
            ],
            onChanged: (value) {
              setState(() => _typeFilter = value);
              _reload();
            },
          ),
        ),
        const SizedBox(width: 12),
        Text('${_records.length} master${_records.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall),
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          onPressed: _loading ? null : _reload,
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load calibration library: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
      );
    }
    if (_records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text('No calibration masters yet. Stacked darks, flats, '
              'and defect maps appear here automatically.'),
        ),
      );
    }
    return Column(
      children: [
        for (final record in _records)
          _MasterTile(
            record: record,
            onEditTags: () => _editTags(record),
            onDelete: () => _confirmDelete(record),
          ),
      ],
    );
  }

  Future<void> _editTags(CalibrationMasterRecord record) async {
    final tagsController =
        TextEditingController(text: record.tags.join(', '));
    final notesController = TextEditingController(text: record.notes ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tags — ${_typeLabel(record.type)} #${record.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (comma-separated)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;

    final tags = tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    await _service.setTags(record.type, record.id, tags);
    await _service.setNotes(record.type, record.id, notesController.text);
    await _reload();
  }

  Future<void> _confirmDelete(CalibrationMasterRecord record) async {
    var deleteFile = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete calibration master?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_typeLabel(record.type)} #${record.id} will be removed '
                  'from the library.'),
              if (record.filePath != null) ...[
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deleteFile,
                  title: const Text('Also delete the file from disk'),
                  subtitle: Text(record.filePath!,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onChanged: (v) =>
                      setDialogState(() => deleteFile = v ?? false),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    await _service.deleteMaster(record.type, record.id,
        deleteFile: deleteFile);
    await _reload();
  }
}

/// One master row: type badge, capture params, freshness, tags, actions.
class _MasterTile extends StatelessWidget {
  final CalibrationMasterRecord record;
  final VoidCallback onEditTags;
  final VoidCallback onDelete;

  const _MasterTile({
    required this.record,
    required this.onEditTags,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final age = record.ageDays(now);
    final freshness = record.freshness(now);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TypeBadge(type: record.type),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_summary(record),
                      style: theme.textTheme.bodyMedium),
                ),
                _FreshnessChip(freshness: freshness, ageDays: age),
                IconButton(
                  tooltip: 'Edit tags / notes',
                  icon: const Icon(LucideIcons.tag, size: 18),
                  onPressed: onEditTags,
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(LucideIcons.trash2,
                      size: 18, color: theme.colorScheme.error),
                  onPressed: onDelete,
                ),
              ],
            ),
            if (record.filePath != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(record.filePath!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ),
            if (record.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in record.tags)
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
            if (record.notes != null && record.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(record.notes!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }

  static String _summary(CalibrationMasterRecord r) {
    final parts = <String>[];
    if (r.exposureSeconds != null) {
      parts.add(_fmtSecs(r.exposureSeconds!));
    }
    if (r.gain != null) parts.add('gain ${r.gain}');
    if (r.offset != null) parts.add('offset ${r.offset}');
    parts.add('bin ${r.binX}x${r.binY}');
    if (r.temperature != null) {
      parts.add('${r.temperature!.toStringAsFixed(1)}°C');
    }
    if (r.filter != null && r.filter!.isNotEmpty) parts.add(r.filter!);
    if (r.cameraId != null && r.cameraId!.isNotEmpty) parts.add(r.cameraId!);
    if (r.frameCount != null) parts.add('${r.frameCount} frames');
    return parts.join(' · ');
  }

  static String _fmtSecs(double secs) =>
      secs == secs.roundToDouble() ? '${secs.round()}s' : '${secs}s';
}

class _TypeBadge extends StatelessWidget {
  final CalibrationMasterType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (type) {
      CalibrationMasterType.dark => (scheme.primary, 'DARK'),
      CalibrationMasterType.bias => (scheme.tertiary, 'BIAS'),
      CalibrationMasterType.flat => (scheme.secondary, 'FLAT'),
      CalibrationMasterType.defectMap => (scheme.error, 'DEFECT'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}

class _FreshnessChip extends StatelessWidget {
  final CalibrationFreshness freshness;
  final int ageDays;
  const _FreshnessChip({required this.freshness, required this.ageDays});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (freshness) {
      CalibrationFreshness.fresh => Colors.green,
      CalibrationFreshness.aging => Colors.orange,
      CalibrationFreshness.stale => scheme.error,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: freshness.name,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.clock, size: 13, color: color),
            const SizedBox(width: 3),
            Text('${ageDays}d',
                style: TextStyle(color: color, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Matching-preview pane: enter a light-frame context, see the auto-pick per
/// type with scores, reasons, and warnings.
class _MatchingPreview extends StatefulWidget {
  final CalibrationLibraryService service;
  const _MatchingPreview({required this.service});

  @override
  State<_MatchingPreview> createState() => _MatchingPreviewState();
}

class _MatchingPreviewState extends State<_MatchingPreview> {
  final _gain = TextEditingController(text: '100');
  final _offset = TextEditingController(text: '50');
  final _exposure = TextEditingController(text: '300');
  final _temp = TextEditingController(text: '-10');
  final _filter = TextEditingController();
  final _binX = TextEditingController(text: '1');
  final _binY = TextEditingController(text: '1');

  bool _running = false;
  CalibrationMatchSet? _result;

  @override
  void dispose() {
    _gain.dispose();
    _offset.dispose();
    _exposure.dispose();
    _temp.dispose();
    _filter.dispose();
    _binX.dispose();
    _binY.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() => _running = true);
    final context = LightFrameContext(
      gain: int.tryParse(_gain.text) ?? 0,
      offset: int.tryParse(_offset.text) ?? 0,
      exposureSeconds: double.tryParse(_exposure.text) ?? 0,
      temperature: double.tryParse(_temp.text),
      filter: _filter.text.trim().isEmpty ? null : _filter.text.trim(),
      binX: int.tryParse(_binX.text) ?? 1,
      binY: int.tryParse(_binY.text) ?? 1,
    );
    final result = await widget.service.match(context);
    if (!mounted) return;
    setState(() {
      _result = result;
      _running = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _field(_gain, 'Gain', 90),
            _field(_offset, 'Offset', 90),
            _field(_exposure, 'Exposure (s)', 110),
            _field(_temp, 'Temp (°C)', 90),
            _field(_filter, 'Filter', 110),
            _field(_binX, 'Bin X', 70),
            _field(_binY, 'Bin Y', 70),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(LucideIcons.search, size: 16),
          label: const Text('Preview auto-selection'),
        ),
        if (_result != null) ...[
          const SizedBox(height: 16),
          _buildResult(context, _result!),
        ],
      ],
    );
  }

  Widget _field(TextEditingController c, String label, double width) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context, CalibrationMatchSet set) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _matchCard(context, 'Dark', set.dark),
        _matchCard(context, 'Bias', set.bias),
        _matchCard(context, 'Flat', set.flat),
        _matchCard(context, 'Defect map', set.defectMap),
        if (set.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final w in set.warnings)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 14, color: theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(w,
                        style: TextStyle(color: theme.colorScheme.error))),
              ],
            ),
        ],
      ],
    );
  }

  Widget _matchCard(
      BuildContext context, String label, CalibrationMatch? match) {
    final theme = Theme.of(context);
    if (match == null) {
      return ListTile(
        dense: true,
        leading: const Icon(LucideIcons.minusCircle, size: 18),
        title: Text('$label: no match'),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$label  ·  ${match.score.toStringAsFixed(0)}/100',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                if (match.exposureScaled)
                  Chip(
                    label: Text(match.exposureScaleFactor != null
                        ? 'scaled ${match.exposureScaleFactor!.toStringAsFixed(2)}x'
                        : 'scaled'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
            if (match.record.filePath != null)
              Text(match.record.filePath!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.hintColor)),
            for (final r in match.reasons)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.check,
                        size: 13, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(r, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            for (final w in match.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(LucideIcons.alertTriangle,
                        size: 13, color: theme.colorScheme.error),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(w,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _typeLabel(CalibrationMasterType type) => switch (type) {
      CalibrationMasterType.dark => 'Dark',
      CalibrationMasterType.bias => 'Bias',
      CalibrationMasterType.flat => 'Flat',
      CalibrationMasterType.defectMap => 'Defect map',
    };
