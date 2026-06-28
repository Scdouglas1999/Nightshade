import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class ScienceSettingsPage extends ConsumerWidget {
  final bool isMobile;

  const ScienceSettingsPage({super.key, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scienceAsync = ref.watch(scienceSettingsProvider);
    final scienceNotifier = ref.read(scienceSettingsProvider.notifier);

    return scienceAsync.when(
      loading: () => SettingsLoadingState(
        isMobile: isMobile,
        message: 'Loading science settings...',
      ),
      error: (error, stack) => SettingsErrorState(
        isMobile: isMobile,
        error: error,
        onRetry: () => ref.invalidate(scienceSettingsProvider),
      ),
      data: (science) {
        return SettingsPage(
          title: 'Science',
          description:
              'Advanced, informational-only scientific analysis. No frames are auto-deleted.',
          isMobile: isMobile,
          hideHeader: isMobile,
          children: [
            SettingsSection(
              title: 'Mode',
              isMobile: isMobile,
              children: [
                SettingRow(
                  icon: LucideIcons.flaskConical,
                  title: 'Show advanced overlay controls',
                  subtitle:
                      'Adds PSF, residual, and tile-map layers to the Imaging overlays menu.',
                  trailing: SettingsSwitch(
                    value: science.advancedModeEnabled,
                    onChanged: (value) =>
                        scienceNotifier.setAdvancedModeEnabled(value),
                  ),
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
                  ),
                  isLast: true,
                  isMobile: isMobile,
                ),
              ],
            ),
            SettingsSection(
              title: 'Features',
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
                  ),
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
                  ),
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
                  ),
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
                  ),
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
                  ),
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
                  ),
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
                  ),
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
                  ),
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
                  ),
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.sliders,
                  title: 'Auto-reject bad frames',
                  subtitle:
                      'After each light frame, reject captures that exceed '
                      'the thresholds set in Analytics → Science → Grade frames. '
                      'Files are never deleted — only excluded from stacks.',
                  trailing: SettingsSwitch(
                    value: science.autoFrameGradingEnabled,
                    onChanged: scienceNotifier.setAutoFrameGradingEnabled,
                  ),
                  isMobile: isMobile,
                ),
                SettingRow(
                  icon: LucideIcons.fileText,
                  title: 'Write science keywords to FITS',
                  subtitle:
                      'Stamp MAGZP / MAGZPERR / TRANSPAR back into the FITS '
                      'header so PixInsight, AstroPixelProcessor, and Siril '
                      'can read Nightshade\'s photometric measurements '
                      'directly from the captured frame.',
                  trailing: SettingsSwitch(
                    value: science.fitsHeaderWritebackEnabled,
                    onChanged: scienceNotifier.setFitsHeaderWritebackEnabled,
                  ),
                  isLast: true,
                  isMobile: isMobile,
                ),
              ],
            ),
            SettingsSection(
              title: 'Photometric catalog',
              isMobile: isMobile,
              children: [
                _ScienceOnlineCatalogRow(isMobile: isMobile),
              ],
            ),
            SettingsSection(
              title: 'AAVSO',
              isMobile: isMobile,
              children: [
                _AavsoObserverCodeRow(isMobile: isMobile),
              ],
            ),
            SettingsSection(
              title: 'Minor Planet Center (MPC)',
              isMobile: isMobile,
              children: [
                _MpcObservatoryCodeRow(isMobile: isMobile),
                _ScienceTextRow(
                  isMobile: isMobile,
                  icon: LucideIcons.bookOpen,
                  title: 'Astrometric catalog',
                  subtitle:
                      'Reference catalog your solver uses (ADES astCat, e.g. '
                      '"Gaia2"). Blank reports as UNK.',
                  hint: 'e.g. Gaia2',
                  width: 110,
                  read: (s) => s.mpcAstrometricCatalog,
                  write: (n, v) => n.setMpcAstrometricCatalog(v),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Observer identity',
              isMobile: isMobile,
              children: [
                _ScienceTextRow(
                  isMobile: isMobile,
                  icon: LucideIcons.user,
                  title: 'Observer name',
                  subtitle:
                      'Written into MPC ADES headers and the TNS reporter '
                      'field.',
                  hint: 'e.g. Jane Doe',
                  width: 160,
                  read: (s) => s.observerName,
                  write: (n, v) => n.setObserverName(v),
                  isLast: true,
                ),
              ],
            ),
            SettingsSection(
              title: 'Transient Name Server (TNS)',
              isMobile: isMobile,
              children: [
                _ScienceTextRow(
                  isMobile: isMobile,
                  icon: LucideIcons.hash,
                  title: 'Bot id',
                  subtitle: 'Your TNS bot id (tns_marker tns_id).',
                  hint: 'e.g. 12345',
                  width: 100,
                  numeric: true,
                  read: (s) => s.tnsBotId == 0 ? '' : s.tnsBotId.toString(),
                  write: (n, v) => n.setTnsBotId(int.tryParse(v) ?? 0),
                ),
                _ScienceTextRow(
                  isMobile: isMobile,
                  icon: LucideIcons.bot,
                  title: 'Bot name',
                  subtitle: 'Your TNS bot name (tns_marker name).',
                  hint: 'e.g. NightshadeBot',
                  width: 160,
                  read: (s) => s.tnsBotName,
                  write: (n, v) => n.setTnsBotName(v),
                ),
                _ScienceTextRow(
                  isMobile: isMobile,
                  icon: LucideIcons.users,
                  title: 'Reporting group id',
                  subtitle: 'Your TNS reporting_group_id.',
                  hint: 'e.g. 42',
                  width: 100,
                  numeric: true,
                  read: (s) => s.tnsReportingGroupId == 0
                      ? ''
                      : s.tnsReportingGroupId.toString(),
                  write: (n, v) =>
                      n.setTnsReportingGroupId(int.tryParse(v) ?? 0),
                ),
                _ScienceTextRow(
                  isMobile: isMobile,
                  icon: LucideIcons.database,
                  title: 'Data source id',
                  subtitle: 'Your TNS discovery_data_source_id.',
                  hint: 'e.g. 7',
                  width: 100,
                  numeric: true,
                  read: (s) => s.tnsDataSourceId == 0
                      ? ''
                      : s.tnsDataSourceId.toString(),
                  write: (n, v) => n.setTnsDataSourceId(int.tryParse(v) ?? 0),
                ),
                _ScienceTextRow(
                  isMobile: isMobile,
                  icon: LucideIcons.edit3,
                  title: 'Reporter name',
                  subtitle: 'Reporter shown on TNS (falls back to observer '
                      'name).',
                  hint: 'e.g. Jane Doe',
                  width: 160,
                  read: (s) => s.tnsReporterName,
                  write: (n, v) => n.setTnsReporterName(v),
                ),
                const _TnsApiKeyRow(),
                _TnsSandboxRow(isMobile: isMobile),
              ],
            ),
            SettingsSection(
              title: 'Camera',
              isMobile: isMobile,
              children: [
                _ScienceCameraAutoRow(isMobile: isMobile),
                _ScienceCameraValueRow(
                  isMobile: isMobile,
                  settingKey: 'science.camera.read_noise_e',
                  icon: LucideIcons.zap,
                  title: 'Camera read noise (e⁻)',
                  subtitle:
                      'Used for limiting magnitude calculations (default 3.5)',
                  defaultText: '3.5',
                  min: 0.5,
                  max: 30.0,
                ),
                _ScienceCameraValueRow(
                  isMobile: isMobile,
                  settingKey: 'science.camera.gain_e_per_adu',
                  icon: LucideIcons.activity,
                  title: 'Camera gain (e⁻/ADU)',
                  subtitle: 'Converts sky background to electrons for limiting '
                      'magnitude (assumes 1.0 when unset)',
                  defaultText: '1.0',
                  min: 0.01,
                  max: 50.0,
                ),
                _ScienceCameraValueRow(
                  isMobile: isMobile,
                  settingKey: 'science.camera.saturation_adu',
                  icon: LucideIcons.sun,
                  title: 'Saturation level (ADU)',
                  subtitle: 'White level used to reject saturated stars from '
                      'photometry — 4095 for raw 12-bit, 16383 for 14-bit, '
                      '65535 for 16-bit output',
                  defaultText: '65535',
                  min: 255,
                  max: 65535,
                  integer: true,
                  isLast: true,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AavsoObserverCodeRow extends ConsumerStatefulWidget {
  final bool isMobile;
  const _AavsoObserverCodeRow({this.isMobile = false});
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
            color: NightshadeColors.of(context).textPrimary,
            fontSize: NightshadeTypography.fontSize13,
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: 'e.g. XYZ',
            hintStyle: TextStyle(
              color: NightshadeColors.of(context).textMuted,
              fontSize: NightshadeTypography.fontSize13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              borderSide:
                  BorderSide(color: NightshadeColors.of(context).border),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              borderSide: BorderSide(color: NightshadeColors.of(context).error),
            ),
          ),
          onSubmitted: (value) async {
            final trimmed = value.trim().toUpperCase();
            if (trimmed.isNotEmpty && trimmed.length > 5) {
              setState(() {
                _validationError = 'AAVSO codes must be 1-5 characters';
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
      isMobile: widget.isMobile,
    );
  }
}

class _MpcObservatoryCodeRow extends ConsumerStatefulWidget {
  final bool isMobile;
  const _MpcObservatoryCodeRow({this.isMobile = false});
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
            color: NightshadeColors.of(context).textPrimary,
            fontSize: NightshadeTypography.fontSize13,
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: 'e.g. G40',
            hintStyle: TextStyle(
              color: NightshadeColors.of(context).textMuted,
              fontSize: NightshadeTypography.fontSize13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              borderSide:
                  BorderSide(color: NightshadeColors.of(context).border),
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
      isMobile: widget.isMobile,
    );
  }
}

/// Generic single-line science-settings text row backed by a ScienceSettings
/// getter + a notifier setter. Used for the TNS bot identifiers and the
/// observer-name / astrometric-catalog fields (all non-secret, persisted via
/// the science settings keyring, master/slave-aware).
class _ScienceTextRow extends ConsumerStatefulWidget {
  final bool isMobile;
  final IconData icon;
  final String title;
  final String subtitle;
  final String hint;
  final double width;
  final bool numeric;
  final bool isLast;
  final String Function(ScienceSettings) read;
  final Future<void> Function(ScienceSettingsNotifier, String) write;

  const _ScienceTextRow({
    required this.isMobile,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.hint,
    required this.width,
    required this.read,
    required this.write,
    this.numeric = false,
    this.isLast = false,
  });

  @override
  ConsumerState<_ScienceTextRow> createState() => _ScienceTextRowState();
}

class _ScienceTextRowState extends ConsumerState<_ScienceTextRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _loadValue();
  }

  Future<void> _loadValue() async {
    final science = ref.read(scienceSettingsProvider).valueOrNull;
    if (science != null && mounted) {
      final value = widget.read(science);
      if (value.isNotEmpty) _controller.text = value;
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
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: SizedBox(
        width: widget.width,
        child: TextField(
          controller: _controller,
          keyboardType: widget.numeric ? TextInputType.number : null,
          style: TextStyle(
            color: NightshadeColors.of(context).textPrimary,
            fontSize: NightshadeTypography.fontSize13,
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: widget.hint,
            hintStyle: TextStyle(
              color: NightshadeColors.of(context).textMuted,
              fontSize: NightshadeTypography.fontSize13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              borderSide:
                  BorderSide(color: NightshadeColors.of(context).border),
            ),
          ),
          onSubmitted: (value) async {
            final trimmed = value.trim();
            final notifier = ref.read(scienceSettingsProvider.notifier);
            await widget.write(notifier, trimmed);
            if (mounted) _controller.text = trimmed;
          },
        ),
      ),
      isLast: widget.isLast,
      isMobile: widget.isMobile,
    );
  }
}

/// Secure-entry row for the TNS bot API key — stored in the keyring
/// (SecretField.tnsApiKey), NEVER in plaintext science settings / backup.
class _TnsApiKeyRow extends ConsumerStatefulWidget {
  const _TnsApiKeyRow();
  @override
  ConsumerState<_TnsApiKeyRow> createState() => _TnsApiKeyRowState();
}

class _TnsApiKeyRowState extends ConsumerState<_TnsApiKeyRow> {
  final _controller = TextEditingController();
  bool _hasKey = false;

  @override
  void initState() {
    super.initState();
    _loadHas();
  }

  Future<void> _loadHas() async {
    final has = await ref.read(secretsStoreProvider).has(SecretField.tnsApiKey);
    if (mounted) setState(() => _hasKey = has);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: LucideIcons.keyRound,
      title: 'Bot API key',
      subtitle: _hasKey
          ? 'Stored securely in the keyring. Enter a new value to replace it.'
          : 'Your TNS bot API key — stored securely, never in backups.',
      trailing: SizedBox(
        width: 180,
        child: TextField(
          controller: _controller,
          obscureText: true,
          style: TextStyle(
            color: NightshadeColors.of(context).textPrimary,
            fontSize: NightshadeTypography.fontSize13,
          ),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: _hasKey ? '•••••• (stored securely)' : 'paste key',
            hintStyle: TextStyle(
              color: NightshadeColors.of(context).textMuted,
              fontSize: NightshadeTypography.fontSize13,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              borderSide:
                  BorderSide(color: NightshadeColors.of(context).border),
            ),
          ),
          onSubmitted: (value) async {
            final trimmed = value.trim();
            if (trimmed.isEmpty) return;
            await ref
                .read(secretsStoreProvider)
                .write(SecretField.tnsApiKey, trimmed);
            if (mounted) {
              _controller.clear();
              setState(() => _hasKey = true);
            }
          },
        ),
      ),
      isMobile: false,
    );
  }
}

/// Toggle between the TNS production endpoint and the sandbox (for testing —
/// sandbox submits never create a public AT record).
class _TnsSandboxRow extends ConsumerWidget {
  final bool isMobile;
  const _TnsSandboxRow({required this.isMobile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final science = ref.watch(scienceSettingsProvider).valueOrNull ??
        const ScienceSettings();
    return SettingRow(
      icon: LucideIcons.flaskConical,
      title: 'Use TNS sandbox',
      subtitle:
          'Submit to the TNS sandbox instead of production (no public record).',
      trailing: SettingsSwitch(
        value: science.tnsUseSandbox,
        onChanged: (value) =>
            ref.read(scienceSettingsProvider.notifier).setTnsUseSandbox(value),
      ),
      isLast: true,
      isMobile: isMobile,
    );
  }
}

/// Toggle for online APASS DR9 cone searches. Downloads are cached per
/// field, so disabling this only stops NEW lookups — previously visited
/// fields keep their deep photometry offline, and everything else falls
/// back to the bundled HYG catalog.
class _ScienceOnlineCatalogRow extends ConsumerStatefulWidget {
  final bool isMobile;
  const _ScienceOnlineCatalogRow({this.isMobile = false});

  @override
  ConsumerState<_ScienceOnlineCatalogRow> createState() =>
      _ScienceOnlineCatalogRowState();
}

class _ScienceOnlineCatalogRowState
    extends ConsumerState<_ScienceOnlineCatalogRow> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stored = await ref
        .read(settingsDaoProvider)
        .getSetting(PhotometricCatalogService.onlineEnabledSettingKey);
    if (mounted) {
      setState(
        () => _enabled = stored == null || stored.toLowerCase() != 'false',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: LucideIcons.globe,
      title: 'Deep catalog lookups (APASS DR9)',
      subtitle: 'Fetch B/V photometry to ~mag 16 from VizieR for zero-point '
          'calibration and the transform wizard. Cached per field for '
          'offline reuse; falls back to the bundled star catalog when off '
          'or unreachable.',
      trailing: SettingsSwitch(
        value: _enabled,
        onChanged: (value) async {
          await ref.read(settingsDaoProvider).setSetting(
                PhotometricCatalogService.onlineEnabledSettingKey,
                value.toString(),
              );
          if (mounted) setState(() => _enabled = value);
        },
      ),
      isLast: true,
      isMobile: widget.isMobile,
    );
  }
}

/// "Auto-configure from camera" switch with provenance subtitle. When on,
/// [ScienceCameraAutoConfig] keeps the three numeric rows below in sync with
/// the connected camera (or active profile); manually editing any of them
/// flips this off so user values are never silently overwritten.
class _ScienceCameraAutoRow extends ConsumerStatefulWidget {
  final bool isMobile;
  const _ScienceCameraAutoRow({this.isMobile = false});

  @override
  ConsumerState<_ScienceCameraAutoRow> createState() =>
      _ScienceCameraAutoRowState();
}

class _ScienceCameraAutoRowState extends ConsumerState<_ScienceCameraAutoRow> {
  bool _autoManaged = true;
  String? _source;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dao = ref.read(settingsDaoProvider);
    final managed =
        await dao.getSetting(ScienceCameraAutoConfig.autoManagedKey);
    final source = await dao.getSetting(ScienceCameraAutoConfig.autoSourceKey);
    if (!mounted) return;
    setState(() {
      _autoManaged = managed == null || managed.toLowerCase() != 'false';
      _source = source;
    });
  }

  Future<void> _setAutoManaged(bool value) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(
      ScienceCameraAutoConfig.autoManagedKey,
      value.toString(),
    );
    if (value) {
      // Re-enable: immediately resync from the current camera/profile.
      await ref
          .read(scienceCameraAutoConfigProvider)
          .maybeSync(reason: 'auto-config re-enabled', force: true);
    }
    if (mounted) {
      setState(() => _autoManaged = value);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _autoManaged
        ? (_source == null || _source!.isEmpty
            ? 'Read noise, gain, and saturation follow the connected camera '
                'or active profile'
            : 'Following: $_source')
        : 'Manual — values below are user-set and will not be overwritten';
    return SettingRow(
      icon: LucideIcons.wand2,
      title: 'Auto-configure from camera',
      subtitle: subtitle,
      trailing: SettingsSwitch(
        value: _autoManaged,
        onChanged: _setAutoManaged,
      ),
      isMobile: widget.isMobile,
    );
  }
}

/// Numeric camera-property row backed by a raw settings key. Shared by the
/// read-noise, gain, and saturation rows so all three validate and persist
/// identically.
class _ScienceCameraValueRow extends ConsumerStatefulWidget {
  final bool isMobile;
  final String settingKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final String defaultText;
  final double min;
  final double max;
  final bool integer;
  final bool isLast;

  const _ScienceCameraValueRow({
    required this.settingKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.defaultText,
    required this.min,
    required this.max,
    this.integer = false,
    this.isLast = false,
    this.isMobile = false,
  });

  @override
  ConsumerState<_ScienceCameraValueRow> createState() =>
      _ScienceCameraValueRowState();
}

class _ScienceCameraValueRowState
    extends ConsumerState<_ScienceCameraValueRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultText);
    _loadValue();
  }

  Future<void> _loadValue() async {
    final dao = ref.read(settingsDaoProvider);
    final stored = await dao.getSetting(widget.settingKey);
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
      icon: widget.icon,
      title: widget.title,
      subtitle: widget.subtitle,
      trailing: SizedBox(
        width: 72,
        child: TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            color: NightshadeColors.of(context).textPrimary,
            fontSize: NightshadeTypography.fontSize13,
          ),
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
              borderSide:
                  BorderSide(color: NightshadeColors.of(context).border),
            ),
          ),
          onSubmitted: (value) async {
            final parsed = double.tryParse(value);
            if (parsed != null && parsed > 0 && parsed.isFinite) {
              final clamped = parsed.clamp(widget.min, widget.max);
              final stored = widget.integer
                  ? clamped.round().toString()
                  : clamped.toString();
              final dao = ref.read(settingsDaoProvider);
              await dao.setSetting(widget.settingKey, stored);
              // A hand-entered value is an explicit override — stop the
              // auto-config service from replacing it on the next camera
              // event. The user can flip auto back on in the row above.
              await dao.setSetting(
                ScienceCameraAutoConfig.autoManagedKey,
                'false',
              );
              if (mounted) {
                _controller.text = stored;
              }
            }
          },
        ),
      ),
      isLast: widget.isLast,
      isMobile: widget.isMobile,
    );
  }
}
