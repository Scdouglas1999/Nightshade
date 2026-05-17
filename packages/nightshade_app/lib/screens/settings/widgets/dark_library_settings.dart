import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class DarkLibrarySettings extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const DarkLibrarySettings({
    super.key,
    required this.colors,
    this.isMobile = false,
  });

  @override
  ConsumerState<DarkLibrarySettings> createState() =>
      _DarkLibrarySettingsState();
}

class _DarkLibrarySettingsState extends ConsumerState<DarkLibrarySettings> {
  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(darkLibraryEntriesProvider);
    final statsAsync = ref.watch(darkLibraryStatsProvider);
    final groupsAsync = ref.watch(darkLibraryGroupsProvider);
    final autoSubtract = ref.watch(autoDarkSubtractEnabledProvider);
    final tempTolerance = ref.watch(darkTempToleranceProvider);
    final uiState = ref.watch(darkLibraryNotifierProvider);

    return SettingsPage(
      title: 'Dark Library',
      description: 'Manage dark and bias calibration frames',
      colors: widget.colors,
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        // Settings section
        SettingsSection(
          title: 'Auto-Calibration',
          colors: widget.colors,
          isMobile: widget.isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.zap,
              title: 'Auto dark subtraction',
              subtitle:
                  'Automatically subtract matching darks from light frames',
              trailing: Switch(
                value: autoSubtract,
                onChanged: (value) {
                  // Why: the imaging pipeline reads
                  // `calibrationSettingsProvider.autoCalibrate` to decide
                  // whether to run dark/flat/bias correction on captured
                  // frames. Writing through the calibration notifier keeps
                  // the dark-library UI and the calibration pipeline in
                  // sync (audit-handoff §2.1 WIRE-UP item #6).
                  ref
                      .read(calibrationSettingsProvider.notifier)
                      .setAutoCalibrate(value);
                },
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
            ),
            SettingRow(
              icon: LucideIcons.thermometer,
              title: 'Temperature tolerance',
              subtitle: 'Maximum temperature difference for dark matching',
              trailing: SizedBox(
                width: 120,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 60,
                      child: SettingsDropdown(
                        value: tempTolerance.toStringAsFixed(1),
                        items: const ['0.5', '1.0', '1.5', '2.0', '3.0', '5.0'],
                        onChanged: (value) {
                          if (value != null) {
                            ref.read(settingsDaoProvider).setSetting(
                                  'dark_library.temp_tolerance',
                                  value,
                                );
                          }
                        },
                        colors: widget.colors,
                        isMobile: widget.isMobile,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '\u00b0C',
                      style: TextStyle(
                        color: widget.colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              colors: widget.colors,
              isMobile: widget.isMobile,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Library statistics
        SettingsSection(
          title: 'Library Statistics',
          colors: widget.colors,
          isMobile: widget.isMobile,
          children: [
            statsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error loading stats: $e',
                    style: TextStyle(color: widget.colors.error)),
              ),
              data: (stats) => Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _StatCard(
                      label: 'Dark Frames',
                      value: '${stats.darkCount}',
                      icon: LucideIcons.moon,
                      colors: widget.colors,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Bias Frames',
                      value: '${stats.biasCount}',
                      icon: LucideIcons.zap,
                      colors: widget.colors,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Master Darks',
                      value: '${stats.masterCount}',
                      icon: LucideIcons.layers,
                      colors: widget.colors,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Total',
                      value: '${stats.totalEntries}',
                      icon: LucideIcons.database,
                      colors: widget.colors,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Status/Error messages
        if (uiState.statusMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: widget.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: widget.colors.primary.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info,
                      size: 16, color: widget.colors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uiState.statusMessage!,
                      style: TextStyle(
                          color: widget.colors.textPrimary, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 14, color: widget.colors.textMuted),
                    onPressed: () => ref
                        .read(darkLibraryNotifierProvider.notifier)
                        .clearStatus(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),
        if (uiState.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: widget.colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: widget.colors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 16, color: widget.colors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uiState.errorMessage!,
                      style: TextStyle(
                          color: widget.colors.textPrimary, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 14, color: widget.colors.textMuted),
                    onPressed: () => ref
                        .read(darkLibraryNotifierProvider.notifier)
                        .clearError(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ),

        // Library actions
        SettingsSection(
          title: 'Library Management',
          colors: widget.colors,
          isMobile: widget.isMobile,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionButton(
                    icon: LucideIcons.scan,
                    label: 'Clean Orphans',
                    tooltip:
                        'Remove entries whose files no longer exist on disk',
                    onPressed: () => ref
                        .read(darkLibraryNotifierProvider.notifier)
                        .cleanOrphans(),
                    colors: widget.colors,
                  ),
                  _ActionButton(
                    icon: LucideIcons.trash2,
                    label: 'Clear Library',
                    tooltip: 'Remove all entries from the library',
                    onPressed: () => _showClearDialog(context),
                    colors: widget.colors,
                    isDanger: true,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Frame groups
        SettingsSection(
          title: 'Frame Groups',
          colors: widget.colors,
          isMobile: widget.isMobile,
          children: [
            groupsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: $e',
                    style: TextStyle(color: widget.colors.error)),
              ),
              data: (groups) {
                if (groups.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.moon,
                              size: 48,
                              color: widget.colors.textMuted
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No dark frames in library',
                            style: TextStyle(
                              color: widget.colors.textMuted,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Capture dark or bias frames to populate the library',
                            style: TextStyle(
                              color: widget.colors.textMuted
                                  .withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final group in groups)
                      _DarkGroupTile(
                        group: group,
                        colors: widget.colors,
                        onCreateMaster: () =>
                            _showCreateMasterDialog(context, group),
                        onDeleteGroup: () =>
                            _showDeleteGroupDialog(context, group),
                      ),
                  ],
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 16),

        // All entries list
        SettingsSection(
          title: 'All Entries',
          colors: widget.colors,
          isMobile: widget.isMobile,
          children: [
            entriesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: $e',
                    style: TextStyle(color: widget.colors.error)),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No entries',
                      style: TextStyle(color: widget.colors.textMuted),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final entry in entries)
                      _DarkEntryTile(
                        entry: entry,
                        colors: widget.colors,
                        onDelete: () => _showDeleteEntryDialog(context, entry),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  void _showClearDialog(BuildContext context) {
    bool deleteFiles = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Clear Dark Library'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Remove all entries from the dark library?'),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFiles,
                onChanged: (v) =>
                    setDialogState(() => deleteFiles = v ?? false),
                title: const Text('Also delete files from disk'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref
                    .read(darkLibraryNotifierProvider.notifier)
                    .clearLibrary(deleteFiles: deleteFiles);
              },
              child:
                  Text('Clear', style: TextStyle(color: widget.colors.error)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateMasterDialog(BuildContext context, DarkGroupKey group) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Master Dark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Median-combine all ${group.frameType} frames with:\n'
              '${group.exposureTime}s / gain ${group.gain} / ${group.binX}x${group.binY}',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Output file path',
                hintText: '/path/to/master_dark.fits',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isEmpty) return;
              Navigator.pop(ctx);
              ref.read(darkLibraryNotifierProvider.notifier).createMasterDark(
                    exposureTime: group.exposureTime,
                    gain: group.gain,
                    binX: group.binX,
                    binY: group.binY,
                    outputPath: path,
                    frameType: group.frameType,
                  );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDeleteGroupDialog(BuildContext context, DarkGroupKey group) {
    bool deleteFiles = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Delete all ${group.frameType} frames with:\n'
                '${group.exposureTime}s / gain ${group.gain} / ${group.binX}x${group.binY}?',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFiles,
                onChanged: (v) =>
                    setDialogState(() => deleteFiles = v ?? false),
                title: const Text('Also delete files from disk'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final service = ref.read(darkLibraryServiceProvider);
                final frames = await service.getMatchingFrames(
                  exposureTime: group.exposureTime,
                  gain: group.gain,
                  binX: group.binX,
                  binY: group.binY,
                  frameType: group.frameType,
                );
                final ids = frames.map((f) => f.id).toList();
                await service.deleteEntries(ids, deleteFile: deleteFiles);
              },
              child:
                  Text('Delete', style: TextStyle(color: widget.colors.error)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteEntryDialog(BuildContext context, DarkLibraryEntry entry) {
    bool deleteFile = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Delete Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Delete this ${entry.frameType} frame?'),
              const SizedBox(height: 4),
              Text(
                entry.filePath,
                style: TextStyle(fontSize: 11, color: widget.colors.textMuted),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: deleteFile,
                onChanged: (v) => setDialogState(() => deleteFile = v ?? false),
                title: const Text('Also delete file from disk'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                ref
                    .read(darkLibraryNotifierProvider.notifier)
                    .deleteEntry(entry.id, deleteFile: deleteFile);
              },
              child:
                  Text('Delete', style: TextStyle(color: widget.colors.error)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final NightshadeColors colors;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onPressed;
  final NightshadeColors colors;
  final bool isDanger;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    required this.colors,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: NightshadeButton(
        onPressed: onPressed,
        icon: icon,
        label: label,
        variant: isDanger ? ButtonVariant.destructive : ButtonVariant.outline,
      ),
    );
  }
}

class _DarkGroupTile extends StatelessWidget {
  final DarkGroupKey group;
  final NightshadeColors colors;
  final VoidCallback onCreateMaster;
  final VoidCallback onDeleteGroup;

  const _DarkGroupTile({
    required this.group,
    required this.colors,
    required this.onCreateMaster,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context) {
    final isD = group.frameType == 'dark';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(
            isD ? LucideIcons.moon : LucideIcons.zap,
            size: 18,
            color: isD ? colors.primary : colors.warning,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${group.frameType.toUpperCase()} - ${group.exposureTime}s',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Gain ${group.gain} | ${group.binX}x${group.binY}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.layers, size: 16, color: colors.primary),
            tooltip: 'Create master dark',
            onPressed: onCreateMaster,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(LucideIcons.trash2, size: 16, color: colors.error),
            tooltip: 'Delete group',
            onPressed: onDeleteGroup,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _DarkEntryTile extends StatelessWidget {
  final DarkLibraryEntry entry;
  final NightshadeColors colors;
  final VoidCallback onDelete;

  const _DarkEntryTile({
    required this.entry,
    required this.colors,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isMaster = entry.masterDarkPath != null;
    final isDark = entry.frameType == 'dark';

    // Extract just the filename from the path
    final fileName = entry.filePath.split('/').last.split('\\').last;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMaster
            ? colors.primary.withValues(alpha: 0.05)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isMaster
                ? LucideIcons.layers
                : isDark
                    ? LucideIcons.moon
                    : LucideIcons.zap,
            size: 14,
            color: isMaster
                ? colors.primary
                : isDark
                    ? colors.textSecondary
                    : colors.warning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMaster ? 'MASTER: $fileName' : fileName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isMaster ? FontWeight.w600 : FontWeight.w400,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${entry.exposureTime}s | '
                  'Gain ${entry.gain} | '
                  '${entry.binX}x${entry.binY}'
                  '${entry.temperature != null ? ' | ${entry.temperature!.toStringAsFixed(1)}\u00b0C' : ''}'
                  '${isMaster ? ' | ${entry.masterFrameCount} frames' : ''}',
                  style: TextStyle(fontSize: 11, color: colors.textMuted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.trash2, size: 14, color: colors.error),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Delete entry',
          ),
        ],
      ),
    );
  }
}
