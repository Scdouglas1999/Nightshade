import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/help/field_help_copy.dart';
import 'settings_widgets.dart';

class DarkLibrarySettings extends ConsumerStatefulWidget {
  final bool isMobile;

  const DarkLibrarySettings({
    super.key,
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
      isMobile: widget.isMobile,
      hideHeader: widget.isMobile,
      children: [
        // Settings section
        SettingsSection(
          title: 'Auto-Calibration',
          isMobile: widget.isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.zap,
              title: 'Auto dark subtraction',
              subtitle:
                  'Automatically subtract matching darks from light frames',
              trailing: SettingsSwitch(
                value: autoSubtract,
                onChanged: (value) {
                  // Why: the imaging pipeline reads
                  // `calibrationSettingsProvider.autoCalibrate` to decide
                  // whether to run dark/flat/bias correction on captured
                  // frames. Writing through the calibration notifier keeps
                  // the dark-library UI and the calibration pipeline in
                  // sync.
                  ref
                      .read(calibrationSettingsProvider.notifier)
                      .setAutoCalibrate(value);
                },
              ),
              isMobile: widget.isMobile,
            ),
            SettingRow(
              icon: LucideIcons.thermometer,
              title: 'Temperature tolerance',
              helpId: FieldHelpId.darkLibraryMatching,
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
                        isMobile: widget.isMobile,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '\u00b0C',
                      style: TextStyle(
                        color: NightshadeColors.of(context).textSecondary,
                        fontSize: NightshadeTypography.fontSize13,
                      ),
                    ),
                  ],
                ),
              ),
              isMobile: widget.isMobile,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Library statistics
        SettingsSection(
          title: 'Library Statistics',
          isMobile: widget.isMobile,
          children: [
            statsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load dark library stats.',
                    style:
                        TextStyle(color: NightshadeColors.of(context).error)),
              ),
              data: (stats) => Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _StatCard(
                      label: 'Dark Frames',
                      value: '${stats.darkCount}',
                      icon: LucideIcons.moon,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Bias Frames',
                      value: '${stats.biasCount}',
                      icon: LucideIcons.zap,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Master Darks',
                      value: '${stats.masterCount}',
                      icon: LucideIcons.layers,
                    ),
                    const SizedBox(width: 12),
                    _StatCard(
                      label: 'Total',
                      value: '${stats.totalEntries}',
                      icon: LucideIcons.database,
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
              decoration: NightshadeDecorations.emphasisSurface(
                NightshadeColors.of(context).primary,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.info,
                      size: 16, color: NightshadeColors.of(context).primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uiState.statusMessage!,
                      style: TextStyle(
                          color: NightshadeColors.of(context).textPrimary,
                          fontSize: NightshadeTypography.fontSize13),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 14,
                        color: NightshadeColors.of(context).textMuted),
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
              decoration: NightshadeDecorations.emphasisSurface(
                NightshadeColors.of(context).error,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 16, color: NightshadeColors.of(context).error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      uiState.errorMessage!,
                      style: TextStyle(
                          color: NightshadeColors.of(context).textPrimary,
                          fontSize: NightshadeTypography.fontSize13),
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.x,
                        size: 14,
                        color: NightshadeColors.of(context).textMuted),
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
                  ),
                  _ActionButton(
                    icon: LucideIcons.trash2,
                    label: 'Clear Library',
                    tooltip: 'Remove all entries from the library',
                    onPressed: () => _showClearDialog(context),
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
          isMobile: widget.isMobile,
          children: [
            groupsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load dark frame groups.',
                    style:
                        TextStyle(color: NightshadeColors.of(context).error)),
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
                              color: NightshadeColors.of(context)
                                  .textMuted
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No dark frames in library',
                            style: TextStyle(
                              color: NightshadeColors.of(context).textMuted,
                              fontSize: NightshadeTypography.fontSize14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Capture dark or bias frames to populate the library',
                            style: TextStyle(
                              color: NightshadeColors.of(context)
                                  .textMuted
                                  .withValues(alpha: 0.7),
                              fontSize: NightshadeTypography.fontSize12,
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
          isMobile: widget.isMobile,
          children: [
            entriesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load dark library entries.',
                    style:
                        TextStyle(color: NightshadeColors.of(context).error)),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No entries',
                      style: TextStyle(
                          color: NightshadeColors.of(context).textMuted),
                    ),
                  );
                }

                return Column(
                  children: [
                    for (final entry in entries)
                      _DarkEntryTile(
                        entry: entry,
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
              child: Text('Clear',
                  style: TextStyle(color: NightshadeColors.of(context).error)),
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
              child: Text('Delete',
                  style: TextStyle(color: NightshadeColors.of(context).error)),
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
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: NightshadeColors.of(context).textMuted),
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
              child: Text('Delete',
                  style: TextStyle(color: NightshadeColors.of(context).error)),
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

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Expanded(
      child: NightshadeCard(
        variant: CardVariant.standard,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize11,
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
  final bool isDanger;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
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
  final VoidCallback onCreateMaster;
  final VoidCallback onDeleteGroup;

  const _DarkGroupTile({
    required this.group,
    required this.onCreateMaster,
    required this.onDeleteGroup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isD = group.frameType == 'dark';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: NightshadeCard(
        variant: CardVariant.standard,
        borderRadius: NightshadeTokens.radiusInline8,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    style: NightshadeTypography.labelStrong
                        .copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gain ${group.gain} | ${group.binX}x${group.binY}',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
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
      ),
    );
  }
}

class _DarkEntryTile extends StatelessWidget {
  final DarkLibraryEntry entry;
  final VoidCallback onDelete;

  const _DarkEntryTile({
    required this.entry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isMaster = entry.masterDarkPath != null;
    final isDark = entry.frameType == 'dark';

    // Extract just the filename from the path
    final fileName = entry.filePath.split('/').last.split('\\').last;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isMaster
            ? NightshadeDecorations.tintedBadge(
                colors.primary,
                borderRadius: BorderRadius.zero,
              ).color
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
                    fontSize: NightshadeTypography.fontSize12,
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
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textMuted),
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
