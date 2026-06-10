import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:file_selector/file_selector.dart';

import '../../../widgets/remote_host_path_dialog.dart';
import 'settings_widgets.dart';

class CalibrationSettingsPage extends ConsumerWidget {
  final bool isMobile;

  const CalibrationSettingsPage({
    super.key,
    this.isMobile = false,
  });

  Future<void> _selectFitsFile(
    BuildContext context,
    WidgetRef ref,
    _CalFileType fileType,
  ) async {
    final calSettings = ref.read(calibrationSettingsProvider);
    final isRemote = ref.read(isRemoteModeProvider);
    String? filePath;

    if (isRemote) {
      final initialPath = switch (fileType) {
        _CalFileType.flat => calSettings.masterFlatPath,
        _CalFileType.bias => calSettings.masterBiasPath,
        _CalFileType.dark => calSettings.manualDarkPath,
      };
      filePath = await RemoteHostPathDialog.show(
        context,
        title: 'Master frame on host',
        initialPath: initialPath,
      );
    } else {
      const fitsGroup = XTypeGroup(
        label: 'FITS/XISF images',
        extensions: ['fits', 'fit', 'fts', 'xisf'],
      );
      final result = await openFile(acceptedTypeGroups: [fitsGroup]);
      filePath = result?.path;
    }

    if (filePath == null || filePath.isEmpty) return;

    final notifier = ref.read(calibrationSettingsProvider.notifier);

    switch (fileType) {
      case _CalFileType.flat:
        await notifier.setMasterFlatPath(filePath);
      case _CalFileType.bias:
        await notifier.setMasterBiasPath(filePath);
      case _CalFileType.dark:
        await notifier.setManualDarkPath(filePath);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final calSettings = ref.watch(calibrationSettingsProvider);
    final darkLibraryStats = ref.watch(darkLibraryStatsProvider);

    return SettingsPage(
      title: 'Calibration',
      description: 'Configure automatic image calibration pipeline',
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        // Auto-calibrate toggle
        SettingsSection(
          title: 'Auto-Calibration',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.zap,
              title: 'Auto-calibrate light frames',
              subtitle:
                  'Apply dark, flat, and bias correction to captured images automatically',
              trailing: SettingsSwitch(
                value: calSettings.autoCalibrate,
                onChanged: (value) {
                  ref
                      .read(calibrationSettingsProvider.notifier)
                      .setAutoCalibrate(value);
                },
              ),
              isMobile: isMobile,
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Calibration frame status overview
        SettingsSection(
          title: 'Calibration Frame Status',
          isMobile: isMobile,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _CalStatusCard(
                    label: 'Dark',
                    available: _isDarkAvailable(calSettings, darkLibraryStats),
                    detail: _darkDetail(calSettings, darkLibraryStats),
                    icon: LucideIcons.moon,
                  ),
                  const SizedBox(width: 12),
                  _CalStatusCard(
                    label: 'Flat',
                    available: calSettings.masterFlatPath != null &&
                        calSettings.masterFlatPath!.isNotEmpty,
                    detail: calSettings.masterFlatPath != null &&
                            calSettings.masterFlatPath!.isNotEmpty
                        ? _fileName(calSettings.masterFlatPath!)
                        : 'Not set',
                    icon: LucideIcons.sun,
                  ),
                  const SizedBox(width: 12),
                  _CalStatusCard(
                    label: 'Bias',
                    available: calSettings.masterBiasPath != null &&
                        calSettings.masterBiasPath!.isNotEmpty,
                    detail: calSettings.masterBiasPath != null &&
                            calSettings.masterBiasPath!.isNotEmpty
                        ? _fileName(calSettings.masterBiasPath!)
                        : 'Not set',
                    icon: LucideIcons.zap,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Dark frame source
        SettingsSection(
          title: 'Dark Frame',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.database,
              title: 'Auto-match from dark library',
              subtitle:
                  'Find the best matching dark frame based on exposure parameters',
              trailing: SettingsSwitch(
                value: calSettings.autoDarkFromLibrary,
                onChanged: (value) {
                  ref
                      .read(calibrationSettingsProvider.notifier)
                      .setAutoDarkFromLibrary(value);
                },
              ),
              isMobile: isMobile,
            ),
            if (!calSettings.autoDarkFromLibrary)
              SettingRow(
                icon: LucideIcons.fileInput,
                title: 'Manual dark frame',
                subtitle: calSettings.manualDarkPath != null &&
                        calSettings.manualDarkPath!.isNotEmpty
                    ? calSettings.manualDarkPath!
                    : 'No manual dark selected',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (calSettings.manualDarkPath != null &&
                        calSettings.manualDarkPath!.isNotEmpty)
                      IconButton(
                        icon:
                            Icon(LucideIcons.x, size: 16, color: colors.error),
                        tooltip: 'Clear dark path',
                        onPressed: () {
                          ref
                              .read(calibrationSettingsProvider.notifier)
                              .setManualDarkPath(null);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    const SizedBox(width: 8),
                    NightshadeButton(
                      onPressed: () =>
                          _selectFitsFile(context, ref, _CalFileType.dark),
                      icon: LucideIcons.folderOpen,
                      label: 'Browse',
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                    ),
                  ],
                ),
                isMobile: isMobile,
              ),
          ],
        ),

        const SizedBox(height: 16),

        // Master flat
        SettingsSection(
          title: 'Master Flat',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.sun,
              title: 'Master flat file',
              subtitle: calSettings.masterFlatPath != null &&
                      calSettings.masterFlatPath!.isNotEmpty
                  ? calSettings.masterFlatPath!
                  : 'No master flat selected',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (calSettings.masterFlatPath != null &&
                      calSettings.masterFlatPath!.isNotEmpty)
                    IconButton(
                      icon: Icon(LucideIcons.x, size: 16, color: colors.error),
                      tooltip: 'Clear flat path',
                      onPressed: () {
                        ref
                            .read(calibrationSettingsProvider.notifier)
                            .setMasterFlatPath(null);
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 8),
                  NightshadeButton(
                    onPressed: () =>
                        _selectFitsFile(context, ref, _CalFileType.flat),
                    icon: LucideIcons.folderOpen,
                    label: 'Browse',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                  ),
                ],
              ),
              isMobile: isMobile,
            ),
            if (calSettings.masterFlatPath != null &&
                calSettings.masterFlatPath!.isNotEmpty)
              _FileValidationRow(
                filePath: calSettings.masterFlatPath!,
              ),
          ],
        ),

        const SizedBox(height: 16),

        // Master bias
        SettingsSection(
          title: 'Master Bias',
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.zap,
              title: 'Master bias file',
              subtitle: calSettings.masterBiasPath != null &&
                      calSettings.masterBiasPath!.isNotEmpty
                  ? calSettings.masterBiasPath!
                  : 'No master bias selected',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (calSettings.masterBiasPath != null &&
                      calSettings.masterBiasPath!.isNotEmpty)
                    IconButton(
                      icon: Icon(LucideIcons.x, size: 16, color: colors.error),
                      tooltip: 'Clear bias path',
                      onPressed: () {
                        ref
                            .read(calibrationSettingsProvider.notifier)
                            .setMasterBiasPath(null);
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  const SizedBox(width: 8),
                  NightshadeButton(
                    onPressed: () =>
                        _selectFitsFile(context, ref, _CalFileType.bias),
                    icon: LucideIcons.folderOpen,
                    label: 'Browse',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                  ),
                ],
              ),
              isMobile: isMobile,
            ),
            if (calSettings.masterBiasPath != null &&
                calSettings.masterBiasPath!.isNotEmpty)
              _FileValidationRow(
                filePath: calSettings.masterBiasPath!,
              ),
          ],
        ),
      ],
    );
  }

  bool _isDarkAvailable(
    CalibrationSettings settings,
    AsyncValue<DarkLibraryStats> statsAsync,
  ) {
    // Manual dark path is set
    if (!settings.autoDarkFromLibrary &&
        settings.manualDarkPath != null &&
        settings.manualDarkPath!.isNotEmpty) {
      return true;
    }
    // Auto dark from library - check if library has any darks
    if (settings.autoDarkFromLibrary) {
      return statsAsync.when(
        data: (stats) => stats.darkCount > 0 || stats.masterCount > 0,
        loading: () => false,
        error: (_, __) => false,
      );
    }
    return false;
  }

  String _darkDetail(
    CalibrationSettings settings,
    AsyncValue<DarkLibraryStats> statsAsync,
  ) {
    if (!settings.autoDarkFromLibrary) {
      if (settings.manualDarkPath != null &&
          settings.manualDarkPath!.isNotEmpty) {
        return _fileName(settings.manualDarkPath!);
      }
      return 'Manual - not set';
    }
    return statsAsync.when(
      data: (stats) {
        if (stats.darkCount == 0 && stats.masterCount == 0) {
          return 'Library empty';
        }
        return '${stats.darkCount} darks, ${stats.masterCount} masters';
      },
      loading: () => 'Loading...',
      error: (_, __) => 'Error',
    );
  }

  String _fileName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.last;
  }
}

enum _CalFileType { flat, bias, dark }

/// Card showing availability status of a calibration frame type.
class _CalStatusCard extends StatelessWidget {
  final String label;
  final bool available;
  final String detail;
  final IconData icon;

  const _CalStatusCard({
    required this.label,
    required this.available,
    required this.detail,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: available
            ? NightshadeDecorations.emphasisSurface(
                colors.success,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
              )
            : BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
                border: Border.all(color: colors.border),
              ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: available ? colors.success : colors.textMuted,
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  available ? LucideIcons.checkCircle : LucideIcons.circle,
                  size: 12,
                  color: available ? colors.success : colors.textMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: NightshadeTypography.labelStrong.copyWith(
                      color: available ? colors.success : colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize10,
                color: colors.textMuted,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Row that validates whether a calibration file exists on disk.
class _FileValidationRow extends ConsumerWidget {
  final String filePath;

  const _FileValidationRow({
    required this.filePath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    if (ref.watch(isRemoteModeProvider)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(LucideIcons.server, size: 14, color: colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Path is validated on the imaging host when calibrating',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<bool>(
      future: File(filePath).exists(),
      builder: (context, snapshot) {
        final exists = snapshot.data ?? false;
        final isLoading = !snapshot.hasData;

        if (isLoading) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Icon(
                exists ? LucideIcons.checkCircle : LucideIcons.alertTriangle,
                size: 14,
                color: exists ? colors.success : colors.error,
              ),
              const SizedBox(width: 8),
              Text(
                exists ? 'File found on disk' : 'File not found on disk',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: exists ? colors.success : colors.error,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
