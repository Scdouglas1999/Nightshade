import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class ScienceSettingsPage extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const ScienceSettingsPage(
      {super.key, required this.colors, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scienceAsync = ref.watch(scienceSettingsProvider);
    final scienceNotifier = ref.read(scienceSettingsProvider.notifier);

    return scienceAsync.when(
      loading: () => SettingsLoadingState(
        colors: colors,
        isMobile: isMobile,
        message: 'Loading science settings...',
      ),
      error: (error, stack) => SettingsErrorState(
        colors: colors,
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(scienceSettingsProvider),
      ),
      data: (science) {
        return SettingsPage(
          title: 'Science',
          description:
              'Advanced, informational-only scientific analysis. No frames are auto-deleted.',
          colors: colors,
          isMobile: isMobile,
          hideHeader: isMobile,
          children: [
            SettingsSection(
              title: 'Mode',
              colors: colors,
              isMobile: isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.flaskConical,
                  title: 'Advanced Science Mode',
                  subtitle: 'Reveal science controls in Imaging and Analytics',
                  trailing: SettingsSwitch(
                    value: science.advancedModeEnabled,
                    onChanged: (value) =>
                        scienceNotifier.setAdvancedModeEnabled(value),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.layers,
                  title: 'Science overlays',
                  subtitle:
                      'Enable overlays such as PSF map, residual vectors, and tracks',
                  trailing: SettingsSwitch(
                    value: science.overlayEnabled,
                    onChanged: (value) =>
                        scienceNotifier.setOverlayEnabled(value),
                    colors: colors,
                  ),
                  isLast: true,
                  colors: colors,
                  isMobile: isMobile,
                ),
              ],
            ),
            SettingsSection(
              title: 'Features',
              colors: colors,
              isMobile: isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.activity,
                  title: 'Live differential photometry',
                  subtitle: 'Target/comparison tracking and live light curves',
                  trailing: SettingsSwitch(
                    value: science.photometryEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.photometry,
                      value,
                    ),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.gauge,
                  title: 'Per-frame photometric calibration',
                  subtitle: 'Compute zeropoint and limiting magnitude',
                  trailing: SettingsSwitch(
                    value: science.photometricCalibrationEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.photometricCalibration,
                      value,
                    ),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.cloud,
                  title: 'Transparency and extinction',
                  subtitle: 'Track atmospheric transparency over time',
                  trailing: SettingsSwitch(
                    value: science.transparencyEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.transparency,
                      value,
                    ),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.layoutGrid,
                  title: 'PSF field map',
                  subtitle: 'Analyze field-wide seeing and tilt patterns',
                  trailing: SettingsSwitch(
                    value: science.psfMapEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.psfMap,
                      value,
                    ),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.map,
                  title: 'Astrometric residuals',
                  subtitle: 'Build residual heatmaps and mount feedback',
                  trailing: SettingsSwitch(
                    value: science.astrometricResidualsEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.astrometricResiduals,
                      value,
                    ),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.rocket,
                  title: 'Moving object mode',
                  subtitle: 'Detect and track moving candidates',
                  trailing: SettingsSwitch(
                    value: science.movingObjectsEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.movingObjects,
                      value,
                    ),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.slidersHorizontal,
                  title: 'Narrowband line ratios',
                  subtitle: 'Generate SII/Ha, OIII/Ha, and SII/OIII products',
                  trailing: SettingsSwitch(
                    value: science.narrowbandRatiosEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.narrowbandRatios,
                      value,
                    ),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.layoutTemplate,
                  title: 'Frame quality maps',
                  subtitle:
                      'Compute clipping, uniformity, background and SNR tile maps',
                  trailing: SettingsSwitch(
                    value: science.frameQualityMapsEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.frameQualityMaps,
                      value,
                    ),
                    colors: colors,
                  ),
                  colors: colors,
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.boxSelect,
                  title: '3D science surfaces',
                  subtitle:
                      'Enable surface explorer and interactive mesh rendering',
                  trailing: SettingsSwitch(
                    value: science.surface3dEnabled,
                    onChanged: (value) => scienceNotifier.setFeatureEnabled(
                      ScienceFeature.surface3d,
                      value,
                    ),
                    colors: colors,
                  ),
                  isLast: true,
                  colors: colors,
                  isMobile: isMobile,
                ),
              ],
            ),
            SettingsSection(
              title: 'AAVSO',
              colors: colors,
              isMobile: isMobile,
              children: [
                _AavsoObserverCodeRow(colors: colors, isMobile: isMobile),
              ],
            ),
            SettingsSection(
              title: 'Minor Planet Center (MPC)',
              colors: colors,
              isMobile: isMobile,
              children: [
                _MpcObservatoryCodeRow(colors: colors, isMobile: isMobile),
              ],
            ),
            SettingsSection(
              title: 'Camera',
              colors: colors,
              isMobile: isMobile,
              children: [
                _ScienceReadNoiseRow(colors: colors, isMobile: isMobile),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AavsoObserverCodeRow extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;
  const _AavsoObserverCodeRow({required this.colors, this.isMobile = false});
  @override
  ConsumerState<_AavsoObserverCodeRow> createState() =>
      _AavsoObserverCodeRowState();
}

class _AavsoObserverCodeRowState extends ConsumerState<_AavsoObserverCodeRow> {
  late TextEditingController _controller;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadValue();
  }

  Future<void> _loadValue() async {
    final science = ref.read(scienceSettingsProvider).valueOrNull;
    if (science != null && science.aavsoObserverCode.isNotEmpty && mounted) {
      _controller.text = science.aavsoObserverCode;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: LucideIcons.userCheck,
      title: 'AAVSO observer code',
      subtitle: _validationError != null
          ? _validationError!
          : 'Your assigned AAVSO observer initials (1-5 chars, e.g., "XYZ")',
      trailing: SizedBox(
        width: 100,
        child: TextField(
          controller: _controller,
          maxLength: 5,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(
            color: widget.colors.textPrimary,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: 'e.g. XYZ',
            hintStyle: TextStyle(
              color: widget.colors.textMuted,
              fontSize: 13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: widget.colors.border),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: widget.colors.error),
            ),
          ),
          onSubmitted: (value) async {
            final trimmed = value.trim().toUpperCase();
            if (trimmed.isNotEmpty && trimmed.length > 5) {
              setState(() {
                _validationError =
                    'AAVSO codes must be 1-5 characters';
              });
              return;
            }
            setState(() => _validationError = null);
            final notifier = ref.read(scienceSettingsProvider.notifier);
            await notifier.setAavsoObserverCode(trimmed);
            if (mounted) {
              _controller.text = trimmed;
            }
          },
        ),
      ),
      isLast: true,
      colors: widget.colors,
      isMobile: widget.isMobile,
    );
  }
}

class _MpcObservatoryCodeRow extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;
  const _MpcObservatoryCodeRow({required this.colors, this.isMobile = false});
  @override
  ConsumerState<_MpcObservatoryCodeRow> createState() =>
      _MpcObservatoryCodeRowState();
}

class _MpcObservatoryCodeRowState
    extends ConsumerState<_MpcObservatoryCodeRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadValue();
  }

  Future<void> _loadValue() async {
    final science = ref.read(scienceSettingsProvider).valueOrNull;
    if (science != null && science.mpcObservatoryCode.isNotEmpty && mounted) {
      _controller.text = science.mpcObservatoryCode;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: LucideIcons.star,
      title: 'MPC observatory code',
      subtitle:
          'Your 3-character MPC observatory code (e.g., "G40"). Required for MPC report export.',
      trailing: SizedBox(
        width: 80,
        child: TextField(
          controller: _controller,
          maxLength: 3,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(
            color: widget.colors.textPrimary,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: 'e.g. G40',
            hintStyle: TextStyle(
              color: widget.colors.textMuted,
              fontSize: 13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: widget.colors.border),
            ),
          ),
          onSubmitted: (value) async {
            final trimmed = value.trim().toUpperCase();
            if (trimmed.isNotEmpty && trimmed.length != 3) {
              // MPC codes must be exactly 3 characters
              return;
            }
            final notifier = ref.read(scienceSettingsProvider.notifier);
            await notifier.setMpcObservatoryCode(trimmed);
            if (mounted) {
              _controller.text = trimmed;
            }
          },
        ),
      ),
      isLast: true,
      colors: widget.colors,
      isMobile: widget.isMobile,
    );
  }
}

class _ScienceReadNoiseRow extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final bool isMobile;
  const _ScienceReadNoiseRow({required this.colors, this.isMobile = false});
  @override
  ConsumerState<_ScienceReadNoiseRow> createState() =>
      _ScienceReadNoiseRowState();
}

class _ScienceReadNoiseRowState extends ConsumerState<_ScienceReadNoiseRow> {
  late TextEditingController _controller;
  static const _key = 'science.camera.read_noise_e';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '3.5');
    _loadValue();
  }

  Future<void> _loadValue() async {
    final dao = ref.read(settingsDaoProvider);
    final stored = await dao.getSetting(_key);
    if (stored != null && stored.isNotEmpty && mounted) {
      _controller.text = stored;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: LucideIcons.zap,
      title: 'Camera read noise (e\u207B)',
      subtitle: 'Used for limiting magnitude calculations (default 3.5)',
      trailing: SizedBox(
        width: 72,
        child: TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            color: widget.colors.textPrimary,
            fontSize: 13,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: widget.colors.border),
            ),
          ),
          onSubmitted: (value) async {
            final parsed = double.tryParse(value);
            if (parsed != null && parsed > 0 && parsed.isFinite) {
              final dao = ref.read(settingsDaoProvider);
              await dao.setSetting(_key, parsed.clamp(0.5, 30.0).toString());
            }
          },
        ),
      ),
      isLast: true,
      colors: widget.colors,
      isMobile: widget.isMobile,
    );
  }
}
