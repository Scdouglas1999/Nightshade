import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../accessible_dropdown.dart';
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
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (identical(previous, next) || !mounted) return;
        _loadGeneration++;
        setState(() {
          _records = const [];
          _error = null;
          _loading = true;
        });
        unawaited(_reload());
      },
    );
    unawaited(_reload());
  }

  @override
  void dispose() {
    _backendSubscription?.close();
    super.dispose();
  }

  CalibrationLibraryService get _service =>
      ref.read(calibrationLibraryServiceProvider);

  int get _masterCount => _records.length;

  Future<void> _reload() async {
    final backend = ref.read(backendProvider);
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (backend is NetworkBackend) {
        // Remote: read the APPLIANCE's master library over REST so a tablet
        // sees the rig's actual darks/flats/biases, not this device's library.
        // The maps are the host's `CalibrationMasterRecord.toJson`, so we
        // rebuild typed records and drive the same edit/delete actions — the
        // service routes those mutations back to the appliance.
        final masters = await backend.getCalibrationMasters(
          type: _typeFilter == null
              ? null
              : calibrationMasterTypeWireName(_typeFilter!),
        );
        if (!_isCurrentLoad(backend, generation)) return;
        setState(() {
          _records = [
            for (final m in masters) CalibrationMasterRecord.fromJson(m),
          ];
          _loading = false;
        });
      } else {
        final records = await _service.listMasters(
          filter: CalibrationLibraryFilter(type: _typeFilter),
        );
        if (!_isCurrentLoad(backend, generation)) return;
        setState(() {
          _records = records;
          _loading = false;
        });
      }
    } catch (e) {
      if (!_isCurrentLoad(backend, generation)) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  bool _isCurrentLoad(NightshadeBackend backend, int generation) =>
      mounted &&
      generation == _loadGeneration &&
      identical(ref.read(backendProvider), backend);

  bool _isCurrentAuthority(NightshadeBackend authority) =>
      mounted && identical(ref.read(backendProvider), authority);

  void _showAuthorityChanged(String action) {
    _showMessage(
      'The imaging host changed while $action. The action was cancelled.',
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Both local and remote share the same panes: locally the records come
    // from this device's Drift DB; remotely they are the APPLIANCE's masters
    // read over `/api/calibration-library`, and the edit / delete / match
    // actions route back to the appliance through CalibrationLibraryService.
    final backend = ref.watch(backendProvider);
    final isRemote = backend is NetworkBackend;

    return SettingsPage(
      title: 'Calibration Library',
      description: 'Browse, tag, and auto-match master darks, flats, '
          'biases, and defect maps',
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        SettingsSection(
          title: isRemote ? 'Appliance Masters' : 'Masters',
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
            _MatchingPreview(
              key: ValueKey(backend),
              service: _service,
              onAccept: _accept,
            ),
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
          child: AccessibleDropdownFormField<CalibrationMasterType?>(
            initialValue: _typeFilter,
            decoration: const InputDecoration(
              labelText: 'Type',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All types')),
              for (final type in CalibrationMasterType.values)
                DropdownMenuItem(value: type, child: Text(_typeLabel(type))),
            ],
            onChanged: (value) {
              setState(() => _typeFilter = value);
              _reload();
            },
          ),
        ),
        const SizedBox(width: 12),
        Text('$_masterCount master${_masterCount == 1 ? '' : 's'}',
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
            // Sharing applies only to a stacked master of a shareable type that
            // lives locally (a remote candidate is pulled, not re-shared here).
            onPublish: (record.isMaster &&
                    !record.isRemote &&
                    !record.isPublished &&
                    record.type != CalibrationMasterType.defectMap)
                ? () => _publish(record)
                : null,
            // Un-share (retract) is offered for a master the user has published
            // to the hub (carries a retract handle) and lives locally.
            onRetract: (record.isPublished && !record.isRemote)
                ? () => _retract(record)
                : null,
          ),
      ],
    );
  }

  Future<void> _editTags(CalibrationMasterRecord record) async {
    final authority = ref.read(backendProvider);
    var tagsText = record.tags.join(', ');
    var notesText = record.notes ?? '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tags — ${_typeLabel(record.type)} #${record.id}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: tagsText,
              onChanged: (value) => tagsText = value,
              decoration: const InputDecoration(
                labelText: 'Tags (comma-separated)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: notesText,
              onChanged: (value) => notesText = value,
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
    if (!_isCurrentAuthority(authority)) {
      _showAuthorityChanged('editing the master');
      return;
    }

    final tags = tagsText
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    try {
      if (authority is NetworkBackend) {
        final type = calibrationMasterTypeWireName(record.type);
        await authority.setCalibrationMasterTags(
          type: type,
          id: record.id,
          tags: tags,
        );
        await authority.setCalibrationMasterNotes(
          type: type,
          id: record.id,
          notes: notesText.trim(),
        );
      } else {
        await _service.setTags(record.type, record.id, tags);
        if (!_isCurrentAuthority(authority)) return;
        await _service.setNotes(record.type, record.id, notesText);
      }
      if (!_isCurrentAuthority(authority)) return;
      await _reload();
    } catch (e) {
      if (!_isCurrentAuthority(authority)) return;
      _showMessage('Could not save tags: $e', isError: true);
    }
  }

  Future<void> _confirmDelete(CalibrationMasterRecord record) async {
    final authority = ref.read(backendProvider);
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
            NightshadeButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              label: 'Cancel',
              variant: ButtonVariant.ghost,
              size: ButtonSize.small,
            ),
            NightshadeButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              label: 'Delete',
              variant: ButtonVariant.destructive,
              size: ButtonSize.small,
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (!_isCurrentAuthority(authority)) {
      _showAuthorityChanged('deleting the master');
      return;
    }
    try {
      if (authority is NetworkBackend) {
        await authority.deleteCalibrationMaster(
          type: calibrationMasterTypeWireName(record.type),
          id: record.id,
          deleteFile: deleteFile,
        );
      } else {
        await _service.deleteMaster(
          record.type,
          record.id,
          deleteFile: deleteFile,
        );
      }
      if (!_isCurrentAuthority(authority)) return;
      await _reload();
    } catch (e) {
      if (!_isCurrentAuthority(authority)) return;
      _showMessage('Could not delete master: $e', isError: true);
    }
  }

  /// Publish a local master to the configured hub (WS1 share) after collecting
  /// the consent/license. On a remote client the action routes to the appliance
  /// over REST; locally it goes straight through [CalibrationLibraryService].
  Future<void> _publish(CalibrationMasterRecord record) async {
    final authority = ref.read(backendProvider);
    final consent = await _collectConsent(record);
    if (consent == null) return;
    if (!_isCurrentAuthority(authority)) {
      _showAuthorityChanged('sharing the master');
      return;
    }
    try {
      if (authority is NetworkBackend) {
        await authority.publishCalibrationMaster(
          type: calibrationMasterTypeWireName(record.type),
          id: record.id,
          license: consent.license.wireName,
          attributionName: consent.attributionName,
        );
      } else {
        await _service.publishMaster(record, consent: consent);
      }
      if (!_isCurrentAuthority(authority)) return;
      _showMessage('Shared ${_typeLabel(record.type)} #${record.id} '
          'under ${consent.license.wireName}.');
      // Reload so the now-published master surfaces its un-share affordance.
      await _reload();
    } catch (e) {
      if (!_isCurrentAuthority(authority)) return;
      _showMessage('Could not share master: $e', isError: true);
    }
  }

  /// Retract (un-share) a master the user previously published to the hub. On a
  /// remote client the action routes to the appliance over REST; locally it goes
  /// straight through [CalibrationLibraryService].
  Future<void> _retract(CalibrationMasterRecord record) async {
    final authority = ref.read(backendProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Un-share calibration master?'),
        content: Text(
          'Stop sharing ${_typeLabel(record.type)} #${record.id} on your hub. '
          'Members can no longer pull it; your local copy is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Un-share'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!_isCurrentAuthority(authority)) {
      _showAuthorityChanged('un-sharing the master');
      return;
    }
    try {
      if (authority is NetworkBackend) {
        await authority.retractCalibrationMaster(
          type: calibrationMasterTypeWireName(record.type),
          id: record.id,
        );
      } else {
        await _service.retractPublishedMaster(record);
      }
      if (!_isCurrentAuthority(authority)) return;
      _showMessage('Un-shared ${_typeLabel(record.type)} #${record.id}.');
      await _reload();
    } catch (e) {
      if (!_isCurrentAuthority(authority)) return;
      _showMessage('Could not un-share master: $e', isError: true);
    }
  }

  /// Download + merge a REMOTE shared master surfaced by the matching preview.
  Future<void> _accept(CalibrationMasterRecord remote) async {
    final authority = ref.read(backendProvider);
    try {
      final String message;
      if (authority is NetworkBackend) {
        final outcome = await authority.acceptRemoteCalibrationMaster(remote);
        message = _acceptOutcomeMessage(
          outcome['kind'] as String?,
          outcome['reason'] as String?,
        );
      } else {
        final outcome = await _service.acceptRemoteMaster(remote);
        message = _acceptOutcomeMessage(outcome.kind.name, outcome.reason);
      }
      if (!_isCurrentAuthority(authority)) return;
      _showMessage(message);
      await _reload();
    } catch (e) {
      if (!_isCurrentAuthority(authority)) return;
      _showMessage('Could not pull shared master: $e', isError: true);
    }
  }

  String _acceptOutcomeMessage(String? kind, String? reason) {
    switch (kind) {
      case 'merged':
        return 'Shared master downloaded into your library.';
      case 'preferredLocal':
        return 'You already have an equivalent local master — kept yours.';
      case 'refused':
        return 'Master refused: ${reason ?? 'failed the quality/consent gate'}.';
      default:
        return 'Accept finished (${kind ?? 'unknown'}).';
    }
  }

  /// Prompt for the reuse license + attribution name before sharing. Returns null
  /// when the user cancels.
  Future<ContributionConsent?> _collectConsent(
    CalibrationMasterRecord record,
  ) async {
    var license = ContributionLicense.ccBy;
    var attribution = '';
    return showDialog<ContributionConsent>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Share ${_typeLabel(record.type)} #${record.id}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Choose a reuse license. Anyone on your hub with a '
                  'matching sensor can then pull this master.'),
              const SizedBox(height: 12),
              AccessibleDropdownFormField<ContributionLicense>(
                initialValue: license,
                decoration: const InputDecoration(
                  labelText: 'License',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final l in ContributionLicense.values)
                    if (l.isShareable)
                      DropdownMenuItem(value: l, child: Text(l.wireName)),
                ],
                onChanged: (v) => setDialogState(
                    () => license = v ?? ContributionLicense.ccBy),
              ),
              const SizedBox(height: 12),
              TextFormField(
                onChanged: (value) => attribution = value,
                decoration: const InputDecoration(
                  labelText: 'Attribution name (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(
                ContributionConsent(
                  license: license,
                  attributionName:
                      attribution.trim().isEmpty ? null : attribution.trim(),
                  consentedAt: DateTime.now(),
                ),
              ),
              child: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

/// One master row: type badge, capture params, freshness, tags, actions.
class _MasterTile extends StatelessWidget {
  final CalibrationMasterRecord record;
  final VoidCallback onEditTags;
  final VoidCallback onDelete;

  /// Share-to-hub action, or null when this master is not shareable (a remote
  /// candidate, a defect map, a raw frame, or one already published).
  final VoidCallback? onPublish;

  /// Un-share (retract) action, or null when this master is not currently
  /// published to the hub.
  final VoidCallback? onRetract;

  const _MasterTile({
    required this.record,
    required this.onEditTags,
    required this.onDelete,
    this.onPublish,
    this.onRetract,
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
                  child:
                      Text(_summary(record), style: theme.textTheme.bodyMedium),
                ),
                _FreshnessChip(freshness: freshness, ageDays: age),
                if (onPublish != null)
                  IconButton(
                    tooltip: 'Share to hub',
                    icon: const Icon(LucideIcons.share2, size: 18),
                    onPressed: onPublish,
                  ),
                if (onRetract != null)
                  IconButton(
                    tooltip: 'Un-share from hub',
                    icon: const Icon(LucideIcons.link2Off, size: 18),
                    onPressed: onRetract,
                  ),
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
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    final colors = NightshadeColors.of(context);
    final color = switch (freshness) {
      CalibrationFreshness.fresh => colors.success,
      CalibrationFreshness.aging => colors.warning,
      CalibrationFreshness.stale => colors.error,
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
            Text('${ageDays}d', style: TextStyle(color: color, fontSize: 12)),
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

  /// Download + merge a REMOTE shared candidate the preview surfaced.
  final Future<void> Function(CalibrationMasterRecord) onAccept;

  const _MatchingPreview({
    super.key,
    required this.service,
    required this.onAccept,
  });

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
  // Camera + sensor geometry feed the WS1 quality gate: a shared master is only
  // foldable when shot on the same camera + sensor dimensions, so leaving these
  // blank refuses every remote candidate (the gate fails closed).
  final _camera = TextEditingController();
  final _sensorWidth = TextEditingController();
  final _sensorHeight = TextEditingController();
  final _opticalTrain = TextEditingController();

  bool _running = false;
  Object? _error;
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
    _camera.dispose();
    _sensorWidth.dispose();
    _sensorHeight.dispose();
    _opticalTrain.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    final lightContext = _validatedContext();
    if (lightContext == null) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final result = await widget.service.match(lightContext);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  LightFrameContext? _validatedContext() {
    final errors = <String>[];

    int? wholeNumber(
      TextEditingController controller,
      String label, {
      required int minimum,
      int? maximum,
      bool optional = false,
    }) {
      final text = controller.text.trim();
      if (optional && text.isEmpty) return null;
      final value = int.tryParse(text);
      if (value == null ||
          value < minimum ||
          (maximum != null && value > maximum)) {
        final range =
            maximum == null ? '$minimum or greater' : '$minimum–$maximum';
        errors.add('$label must be a whole number ($range).');
        return null;
      }
      return value;
    }

    final gain = wholeNumber(_gain, 'Gain', minimum: 0);
    final offset = wholeNumber(_offset, 'Offset', minimum: 0);
    final binX = wholeNumber(_binX, 'Bin X', minimum: 1, maximum: 16);
    final binY = wholeNumber(_binY, 'Bin Y', minimum: 1, maximum: 16);
    final sensorWidth = wholeNumber(
      _sensorWidth,
      'Sensor width',
      minimum: 1,
      optional: true,
    );
    final sensorHeight = wholeNumber(
      _sensorHeight,
      'Sensor height',
      minimum: 1,
      optional: true,
    );
    if ((_sensorWidth.text.trim().isEmpty) !=
        (_sensorHeight.text.trim().isEmpty)) {
      errors.add(
          'Enter both sensor width and sensor height, or leave both blank.');
    }

    final exposureText = _exposure.text.trim();
    final exposure = double.tryParse(exposureText);
    if (exposure == null || !exposure.isFinite || exposure <= 0) {
      errors.add('Exposure must be a finite number greater than 0 seconds.');
    }

    double? temperature;
    final temperatureText = _temp.text.trim();
    if (temperatureText.isNotEmpty) {
      temperature = double.tryParse(temperatureText);
      if (temperature == null || !temperature.isFinite) {
        errors.add('Temperature must be a finite number or left blank.');
      }
    }

    if (errors.isNotEmpty) {
      setState(() {
        _error = errors.join(' ');
        _result = null;
      });
      return null;
    }

    return LightFrameContext(
      gain: gain!,
      offset: offset!,
      exposureSeconds: exposure!,
      temperature: temperature,
      filter: _filter.text.trim().isEmpty ? null : _filter.text.trim(),
      binX: binX!,
      binY: binY!,
      cameraId: _camera.text.trim().isEmpty ? null : _camera.text.trim(),
      sensorWidth: sensorWidth,
      sensorHeight: sensorHeight,
      opticalTrainId:
          _opticalTrain.text.trim().isEmpty ? null : _opticalTrain.text.trim(),
    );
  }

  Future<void> _accept(CalibrationMasterRecord remote) async {
    await widget.onAccept(remote);
    if (!mounted) return;
    // Re-run the preview so the now-local master (or refusal) is reflected.
    await _run();
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
            _field(_camera, 'Camera', 140),
            _field(_sensorWidth, 'Sensor W', 90),
            _field(_sensorHeight, 'Sensor H', 90),
            _field(_opticalTrain, 'Optical train', 140),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(LucideIcons.search, size: 16),
          label: const Text('Preview auto-selection'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.alertTriangle,
                  size: 14, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Preview failed: $_error',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ],
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
        enabled: !_running,
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
    final colors = NightshadeColors.of(context);
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
                if (match.record.isRemote) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(LucideIcons.download, size: 15),
                    label: const Text('Pull'),
                    onPressed: () => _accept(match.record),
                  ),
                ],
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
                    Icon(LucideIcons.check, size: 13, color: colors.success),
                    const SizedBox(width: 6),
                    Expanded(child: Text(r, style: theme.textTheme.bodySmall)),
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
