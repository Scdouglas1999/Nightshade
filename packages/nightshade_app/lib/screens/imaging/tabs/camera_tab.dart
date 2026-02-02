import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:file_selector/file_selector.dart';

import '../../../utils/snackbar_helper.dart';

class CameraTab extends ConsumerWidget {
  const CameraTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: ResponsiveCardGrid(
        children: [
          _CoolingCard(),
          _SensorInfoCard(),
          _DebayeringCard(),
          _GainOffsetPresetsCard(),
          _DownloadSettingsCard(),
        ],
      ),
    );
  }
}

class _CoolingCard extends ConsumerStatefulWidget {
  const _CoolingCard();

  @override
  ConsumerState<_CoolingCard> createState() => _CoolingCardState();
}

class _CoolingCardState extends ConsumerState<_CoolingCard> {
  bool _isSetting = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final cameraState = ref.watch(cameraStateProvider);
    final isConnected = cameraState.connectionState == DeviceConnectionState.connected;
    // Use target temp from provider (persists across navigation)
    final targetTemp = cameraState.targetTemp;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Cooling',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                // Show cooling status indicator
                if (cameraState.isCooling)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.info.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'COOLING',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: colors.info,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Target temperature
            Row(
              children: [
                Text(
                  'Target:',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: colors.primary,
                      inactiveTrackColor: colors.surfaceAlt,
                      thumbColor: colors.primary,
                    ),
                    child: Slider(
                      value: targetTemp,
                      min: -40,
                      max: 20,
                      divisions: 60,
                      onChanged: isConnected ? (value) {
                        // Update provider so value persists across navigation
                        ref.read(cameraStateProvider.notifier).setTargetTemp(value);
                      } : null,
                    ),
                  ),
                ),
                Text(
                  '${targetTemp.toStringAsFixed(0)}°C',
                  style: NightshadeTypography.monoSm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Current readings
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ReadingItem(
                  label: 'Current',
                  value: isConnected && cameraState.temperature != null
                      ? '${cameraState.temperature!.toStringAsFixed(1)}°C'
                      : '---'
                ),
                _ReadingItem(
                  label: 'Power',
                  value: isConnected && cameraState.coolerPower != null
                      ? '${cameraState.coolerPower!.toStringAsFixed(0)}%'
                      : '---'
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Cooler controls
            Row(
              children: [
                Expanded(
                  child: NightshadeButton(
                    label: _isSetting ? 'Setting...' : 'Cooler ON',
                    onPressed: (isConnected && !_isSetting) ? () => _setCooling(true) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NightshadeButton(
                    label: 'Cooler OFF',
                    variant: ButtonVariant.outline,
                    onPressed: isConnected ? () => _setCooling(false) : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Temperature graph
            const _TemperatureGraph(),
          ],
        ),
      ),
    );
  }

  Future<void> _setCooling(bool enabled) async {
    setState(() => _isSetting = true);
    final targetTemp = ref.read(cameraStateProvider).targetTemp;
    try {
      await ref.read(deviceServiceProvider).setCameraCooling(
        enabled: enabled,
        targetTemp: targetTemp,
      );
      // Update cooling state in provider
      ref.read(cameraStateProvider.notifier).setCooling(enabled);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Failed to set cooling: $e');
      }
    } finally {
      if (mounted) setState(() => _isSetting = false);
    }
  }
}

class _SensorInfoCard extends StatelessWidget {
  const _SensorInfoCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sensor Info',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            const _InfoRow(label: 'Model', value: 'Not connected'),
            const _InfoRow(label: 'Resolution', value: '---'),
            const _InfoRow(label: 'Pixel Size', value: '---'),
            const _InfoRow(label: 'Sensor Size', value: '---'),
            const _InfoRow(label: 'Bayer Pattern', value: '---'),
            const _InfoRow(label: 'ADC', value: '---'),
          ],
        ),
      ),
    );
  }
}

class _DebayeringCard extends ConsumerWidget {
  const _DebayeringCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final debayerEnabled = ref.watch(debayerEnabledProvider);
    final bayerPattern = ref.watch(bayerPatternProvider);
    final debayerAlgorithm = ref.watch(debayerAlgorithmProvider);
    final autoDetectBayerPattern = ref.watch(autoDetectBayerPatternProvider);

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Debayering',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                Switch(
                  value: debayerEnabled,
                  onChanged: (value) {
                    ref.read(debayerEnabledProvider.notifier).state = value;
                  },
                  activeThumbColor: colors.primary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Enable for color cameras to convert raw Bayer data to RGB',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
            const SizedBox(height: 16),
            
            // Algorithm selection
            _SettingRow(
              label: 'Algorithm',
              child: NightshadeDropdown(
                value: debayerAlgorithm.displayName,
                items: DebayerAlgorithm.values.map((a) => a.displayName).toList(),
                onChanged: debayerEnabled ? (value) {
                  final algorithm = DebayerAlgorithm.values.firstWhere(
                    (a) => a.displayName == value,
                    orElse: () => DebayerAlgorithm.bilinear,
                  );
                  ref.read(debayerAlgorithmProvider.notifier).state = algorithm;
                } : null,
              ),
            ),
            const SizedBox(height: 12),
            
            // Bayer pattern selection
            _SettingRow(
              label: 'Pattern',
              child: NightshadeDropdown(
                value: bayerPattern.displayName,
                items: BayerPattern.values.map((p) => p.displayName).toList(),
                onChanged: (debayerEnabled && !autoDetectBayerPattern) ? (value) {
                  final pattern = BayerPattern.values.firstWhere(
                    (p) => p.displayName == value,
                    orElse: () => BayerPattern.rggb,
                  );
                  ref.read(bayerPatternProvider.notifier).state = pattern;
                } : null,
              ),
            ),
            const SizedBox(height: 12),
            
            // Auto-detect option
            Row(
              children: [
                NightshadeCheckbox(
                  value: autoDetectBayerPattern,
                  onChanged: debayerEnabled ? (value) {
                    if (value != null) {
                      ref.read(autoDetectBayerPatternProvider.notifier).state = value;
                    }
                  } : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Auto-detect from FITS header',
                    style: TextStyle(
                      fontSize: 12,
                      color: debayerEnabled ? colors.textSecondary : colors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Info about algorithms
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Algorithm Info',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• Bilinear: Fast, good for previews\n'
                    '• VNG: Better quality, slower\n'
                    '• Super Pixel: 2x2 binning, fastest',
                    style: TextStyle(fontSize: 10, color: colors.textMuted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GainOffsetPresetsCard extends ConsumerWidget {
  const _GainOffsetPresetsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final presetsAsync = ref.watch(cameraPresetsProvider);
    final selectedPresetId = ref.watch(selectedPresetIdProvider);

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Gain / Offset Presets',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                NightshadeButton(
                  label: 'Add',
                  size: ButtonSize.small,
                  onPressed: () => _showAddPresetDialog(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 16),
            presetsAsync.when(
              data: (presets) {
                if (presets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No presets yet. Add one to get started.',
                        style: TextStyle(fontSize: 12, color: colors.textMuted),
                      ),
                    ),
                  );
                }

                return Column(
                  children: presets.asMap().entries.map((entry) {
                    final preset = entry.value;
                    final isLast = entry.key == presets.length - 1;

                    return Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
                      child: _PresetItem(
                        preset: preset,
                        isSelected: selectedPresetId == preset.id,
                        onTap: () => ref.read(cameraPresetsProvider.notifier).applyPreset(preset.id),
                        onDelete: () => _deletePreset(context, ref, preset),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Error loading presets: $error',
                    style: TextStyle(fontSize: 12, color: colors.error),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddPresetDialog(BuildContext context, WidgetRef ref) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final nameController = TextEditingController();
    final gainController = TextEditingController();
    final offsetController = TextEditingController();

    // Get current exposure settings as defaults
    final currentSettings = ref.read(exposureSettingsProvider);
    gainController.text = currentSettings.gain.toString();
    offsetController.text = currentSettings.offset.toString();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Add Camera Preset',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preset Name',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                autofocus: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'e.g., Low Noise Mode',
                  hintStyle: TextStyle(color: colors.textMuted),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Gain',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: gainController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: '0-300',
                  hintStyle: TextStyle(color: colors.textMuted),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Offset',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: offsetController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: '0-100',
                  hintStyle: TextStyle(color: colors.textMuted),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          NightshadeButton(
            label: 'Add Preset',
            size: ButtonSize.small,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      final name = nameController.text.trim();
      final gain = int.tryParse(gainController.text);
      final offset = int.tryParse(offsetController.text);

      if (name.isEmpty) {
        context.showErrorSnackBar('Please enter a preset name');
        return;
      }

      if (gain == null || gain < 0 || gain > 500) {
        context.showErrorSnackBar('Gain must be between 0 and 500');
        return;
      }

      if (offset == null || offset < 0 || offset > 100) {
        context.showErrorSnackBar('Offset must be between 0 and 100');
        return;
      }

      try {
        final preset = CameraPreset(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: name,
          gain: gain,
          offset: offset,
          createdAt: DateTime.now(),
        );

        await ref.read(cameraPresetsProvider.notifier).addPreset(preset);

        if (context.mounted) {
          context.showSuccessSnackBar('Preset "$name" added successfully');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to add preset: $e');
        }
      }
    }

    nameController.dispose();
    gainController.dispose();
    offsetController.dispose();
  }

  Future<void> _deletePreset(BuildContext context, WidgetRef ref, CameraPreset preset) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Delete Preset',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to delete "${preset.name}"?',
          style: TextStyle(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          NightshadeButton(
            label: 'Delete',
            size: ButtonSize.small,
            variant: ButtonVariant.outline,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ref.read(cameraPresetsProvider.notifier).deletePreset(preset.id);
        if (context.mounted) {
          context.showInfoSnackBar('Preset "${preset.name}" deleted');
        }
      } catch (e) {
        if (context.mounted) {
          context.showErrorSnackBar('Failed to delete preset: $e');
        }
      }
    }
  }
}

class _DownloadSettingsCard extends ConsumerWidget {
  const _DownloadSettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final settingsAsync = ref.watch(appSettingsProvider);
    final outputAsync = ref.watch(outputSettingsProvider);

    final settings = settingsAsync.valueOrNull;
    final output = outputAsync.valueOrNull;

    final imageFormat = settings?.imageFormat ?? output?.format ?? 'FITS';
    final bitDepth = settings?.bitDepth ?? output?.bitDepth ?? '16-bit';
    final savePath = settings?.imageOutputPath ?? output?.savePath ?? '';
    final includeTimestamp = output?.includeTimestamp ?? true;
    final includeFilter = output?.includeFilter ?? true;

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download Settings',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            _SettingRow(
              label: 'Format',
              child: NightshadeDropdown(
                value: imageFormat,
                items: const ['FITS', 'XISF', 'TIFF'],
                onChanged: (value) async {
                  if (value != null) {
                    await ref.read(appSettingsProvider.notifier).setImageFormat(value);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            _SettingRow(
              label: 'Bit Depth',
              child: NightshadeDropdown(
                value: bitDepth,
                items: const ['16-bit', '32-bit'],
                onChanged: (value) async {
                  if (value != null) {
                    await ref.read(appSettingsProvider.notifier).setBitDepth(value);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            _SettingRow(
              label: 'Save Path',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      savePath.isEmpty ? 'Not set' : savePath,
                      style: TextStyle(
                        fontSize: 12,
                        color: savePath.isEmpty ? colors.textMuted : colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  NightshadeButton(
                    label: 'Browse',
                    size: ButtonSize.small,
                    variant: ButtonVariant.outline,
                    onPressed: () => _browseSavePath(context, ref),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                NightshadeCheckbox(
                  value: includeTimestamp,
                  onChanged: (v) async {
                    if (v != null) {
                      await ref.read(outputSettingsProvider.notifier).updateOutput(
                        includeTimestamp: v,
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  'Include timestamp',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                NightshadeCheckbox(
                  value: includeFilter,
                  onChanged: (v) async {
                    if (v != null) {
                      await ref.read(outputSettingsProvider.notifier).updateOutput(
                        includeFilter: v,
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  'Include filter name',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _browseSavePath(BuildContext context, WidgetRef ref) async {
    try {
      final directoryPath = await getDirectoryPath(
        confirmButtonText: 'Select',
      );

      if (directoryPath != null) {
        await ref.read(appSettingsProvider.notifier).setImageOutputPath(directoryPath);
        await ref.read(outputSettingsProvider.notifier).updateOutput(
          savePath: directoryPath,
        );

        if (context.mounted) {
          context.showInfoSnackBar('Save path updated: $directoryPath');
        }
      }
    } catch (e) {
      if (context.mounted) {
        context.showErrorSnackBar('Failed to select directory: $e');
      }
    }
  }
}

class _ReadingItem extends StatelessWidget {
  final String label;
  final String value;

  const _ReadingItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: colors.textMuted)),
        AnimatedValue(
          value: value,
          style: ValueAnimationStyle.directional,
          textStyle: NightshadeTypography.mono.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetItem extends StatelessWidget {
  final CameraPreset preset;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _PresetItem({
    required this.preset,
    required this.isSelected,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.1) : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? colors.primary : colors.border,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preset.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    'Gain: ${preset.gain}, Offset: ${preset.offset}',
                    style: NightshadeTypography.monoXs.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: colors.textMuted),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Delete preset',
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String label;
  final Widget child;

  const _SettingRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

// =============================================================================
// TEMPERATURE GRAPH WIDGET
// =============================================================================

class _TemperatureGraph extends ConsumerWidget {
  const _TemperatureGraph();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final history = ref.watch(temperatureHistoryProvider);
    
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: history.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.thermostat_outlined,
                      size: 24,
                      color: colors.textMuted,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'No temperature data',
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                  ],
                ),
              )
            : CustomPaint(
                painter: _TemperatureGraphPainter(
                  data: history,
                  colors: colors,
                ),
                size: Size.infinite,
              ),
      ),
    );
  }
}

class _TemperatureGraphPainter extends CustomPainter {
  final List<TemperaturePoint> data;
  final NightshadeColors colors;

  _TemperatureGraphPainter({required this.data, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paintTemp = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintTarget = Paint()
      ..color = colors.primary.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final paintPower = Paint()
      ..color = Colors.orange.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintGrid = Paint()
      ..color = colors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Calculate temperature range
    double minTemp = data.first.temperature;
    double maxTemp = data.first.temperature;
    
    for (final point in data) {
      if (point.temperature < minTemp) minTemp = point.temperature;
      if (point.temperature > maxTemp) maxTemp = point.temperature;
      if (point.targetTemp != null) {
        if (point.targetTemp! < minTemp) minTemp = point.targetTemp!;
        if (point.targetTemp! > maxTemp) maxTemp = point.targetTemp!;
      }
    }
    
    // Add padding
    final range = (maxTemp - minTemp).abs();
    final padding = range < 5 ? 5.0 : range * 0.2;
    minTemp -= padding;
    maxTemp += padding;

    // Draw horizontal grid lines and labels
    final tempRange = maxTemp - minTemp;
    final gridStep = tempRange > 20 ? 10.0 : 5.0;
    
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    
    for (double t = (minTemp / gridStep).ceil() * gridStep; t <= maxTemp; t += gridStep) {
      final y = size.height - ((t - minTemp) / tempRange * size.height);
      canvas.drawLine(Offset(30, y), Offset(size.width, y), paintGrid);
      
      textPainter.text = TextSpan(
        text: '${t.toInt()}°',
        style: TextStyle(fontSize: 8, color: colors.textMuted),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(2, y - 6));
    }

    final stepX = (size.width - 35) / 120; // Match maxPoints

    // Draw temperature path
    final tempPath = Path();
    final targetPath = Path();
    final powerPath = Path();
    
    bool tempFirst = true;
    bool targetFirst = true;
    bool powerFirst = true;

    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      final x = 35 + (i * stepX);
      
      // Temperature
      final tempY = size.height - ((point.temperature - minTemp) / tempRange * size.height);
      if (tempFirst) {
        tempPath.moveTo(x, tempY);
        tempFirst = false;
      } else {
        tempPath.lineTo(x, tempY);
      }
      
      // Target temperature
      if (point.targetTemp != null) {
        final targetY = size.height - ((point.targetTemp! - minTemp) / tempRange * size.height);
        if (targetFirst) {
          targetPath.moveTo(x, targetY);
          targetFirst = false;
        } else {
          targetPath.lineTo(x, targetY);
        }
      }
      
      // Cooler power (0-100 mapped to height)
      if (point.coolerPower != null) {
        final powerY = size.height - (point.coolerPower! / 100.0 * size.height);
        if (powerFirst) {
          powerPath.moveTo(x, powerY);
          powerFirst = false;
        } else {
          powerPath.lineTo(x, powerY);
        }
      }
    }

    // Draw paths in order: power, target, then temperature (on top)
    if (!powerFirst) canvas.drawPath(powerPath, paintPower);
    if (!targetFirst) canvas.drawPath(targetPath, paintTarget);
    canvas.drawPath(tempPath, paintTemp);

    // Draw legend
    const legendY = 8.0;
    
    // Temperature legend
    canvas.drawLine(Offset(size.width - 80, legendY), Offset(size.width - 68, legendY), paintTemp);
    textPainter.text = TextSpan(text: 'Temp', style: TextStyle(fontSize: 8, color: colors.textMuted));
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 65, legendY - 5));
    
    // Power legend
    canvas.drawLine(Offset(size.width - 45, legendY), Offset(size.width - 33, legendY), paintPower);
    textPainter.text = TextSpan(text: 'PWR', style: TextStyle(fontSize: 8, color: colors.textMuted));
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 30, legendY - 5));
  }

  @override
  bool shouldRepaint(covariant _TemperatureGraphPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}



