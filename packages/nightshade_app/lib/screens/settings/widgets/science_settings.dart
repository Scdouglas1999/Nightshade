import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/user_facing_error.dart';
import 'settings_widgets.dart';

String? _validatePositiveScienceId(String value) {
  if (value.isEmpty) return null;
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    return 'Enter a positive whole-number ID';
  }
  return null;
}

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
                  validate: _validatePositiveScienceId,
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
                  validate: _validatePositiveScienceId,
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
                  validate: _validatePositiveScienceId,
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
  late FocusNode _focusNode;
  String? _validationError;
  bool _loading = true;
  String _lastCommitted = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()..addListener(_onFocusChange);
    _loadValue();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  Future<void> _loadValue() async {
    final science = ref.read(scienceSettingsProvider).valueOrNull;
    if (science != null && science.aavsoObserverCode.isNotEmpty && mounted) {
      _controller.text = science.aavsoObserverCode;
      _lastCommitted = science.aavsoObserverCode;
    }
    _loading = false;
  }

  Future<void> _commit() async {
    if (_loading) return;
    final trimmed = _controller.text.trim().toUpperCase();
    if (trimmed == _lastCommitted) return;
    if (trimmed.isNotEmpty && trimmed.length > 5) {
      setState(() {
        _validationError = 'AAVSO codes must be 1-5 characters';
      });
      return;
    }
    setState(() => _validationError = null);
    final notifier = ref.read(scienceSettingsProvider.notifier);
    final previous = _lastCommitted;
    _lastCommitted = trimmed;
    try {
      await notifier.setAavsoObserverCode(trimmed);
    } catch (_) {
      _lastCommitted = previous;
      rethrow;
    }
    if (mounted) {
      _controller.text = trimmed;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
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
          focusNode: _focusNode,
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
          onSubmitted: (_) => _commit(),
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
  late FocusNode _focusNode;
  String? _validationError;
  bool _loading = true;
  String _lastCommitted = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()..addListener(_onFocusChange);
    _loadValue();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  Future<void> _loadValue() async {
    final science = ref.read(scienceSettingsProvider).valueOrNull;
    if (science != null && science.mpcObservatoryCode.isNotEmpty && mounted) {
      _controller.text = science.mpcObservatoryCode;
      _lastCommitted = science.mpcObservatoryCode;
    }
    _loading = false;
  }

  Future<void> _commit() async {
    if (_loading) return;
    final trimmed = _controller.text.trim().toUpperCase();
    if (trimmed == _lastCommitted) return;
    if (trimmed.isNotEmpty &&
        (trimmed.length != 3 || !RegExp(r'^[A-Z0-9]{3}$').hasMatch(trimmed))) {
      setState(() {
        _validationError = 'MPC codes must be exactly 3 letters or digits';
      });
      return;
    }
    setState(() => _validationError = null);
    final notifier = ref.read(scienceSettingsProvider.notifier);
    final previous = _lastCommitted;
    _lastCommitted = trimmed;
    try {
      await notifier.setMpcObservatoryCode(trimmed);
    } catch (_) {
      _lastCommitted = previous;
      rethrow;
    }
    if (mounted) {
      _controller.text = trimmed;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: LucideIcons.star,
      title: 'MPC observatory code',
      subtitle: _validationError != null
          ? _validationError!
          : 'Your 3-character MPC observatory code (e.g., "G40"). Required for MPC report export.',
      trailing: SizedBox(
        width: 80,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
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
          onSubmitted: (_) => _commit(),
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
  final String? Function(String value)? validate;
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
    this.validate,
  });

  @override
  ConsumerState<_ScienceTextRow> createState() => _ScienceTextRowState();
}

class _ScienceTextRowState extends ConsumerState<_ScienceTextRow> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _loading = true;
  String _lastCommitted = '';
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()..addListener(_onFocusChange);
    _loadValue();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  Future<void> _loadValue() async {
    final science = ref.read(scienceSettingsProvider).valueOrNull;
    if (science != null && mounted) {
      final value = widget.read(science);
      if (value.isNotEmpty) {
        _controller.text = value;
        _lastCommitted = value;
      }
    }
    _loading = false;
  }

  Future<void> _commit() async {
    if (_loading) return;
    final trimmed = _controller.text.trim();
    if (trimmed == _lastCommitted) return;
    final validationError = widget.validate?.call(trimmed);
    if (validationError != null) {
      setState(() => _validationError = validationError);
      return;
    }
    setState(() => _validationError = null);
    final notifier = ref.read(scienceSettingsProvider.notifier);
    final previous = _lastCommitted;
    _lastCommitted = trimmed;
    try {
      await widget.write(notifier, trimmed);
    } catch (_) {
      _lastCommitted = previous;
      rethrow;
    }
    if (mounted) _controller.text = trimmed;
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: widget.icon,
      title: widget.title,
      subtitle: _validationError ?? widget.subtitle,
      trailing: SizedBox(
        width: widget.width,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
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
          onSubmitted: (_) => _commit(),
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
  late final FocusNode _focusNode;
  bool _hasKey = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChange);
    _loadHas();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  Future<void> _loadHas() async {
    final has = await ref.read(secretsStoreProvider).has(SecretField.tnsApiKey);
    if (mounted) setState(() => _hasKey = has);
  }

  Future<void> _commit() async {
    if (_saving) return;
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    _saving = true;
    try {
      await ref
          .read(secretsStoreProvider)
          .write(SecretField.tnsApiKey, trimmed);
      if (mounted) {
        _controller.clear();
        setState(() => _hasKey = true);
      }
    } finally {
      _saving = false;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
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
          focusNode: _focusNode,
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
          onSubmitted: (_) => _commit(),
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
  bool? _pendingValue;

  Future<void> _setEnabled(bool value) async {
    if (_pendingValue != null) return;
    setState(() => _pendingValue = value);
    try {
      await ref
          .read(scienceRawSettingsActionsProvider)
          .setOnlineCatalogEnabled(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Could not save catalog setting: ${userFacingError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingValue = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawSettings = ref.watch(scienceRawSettingsProvider).valueOrNull;
    final stored =
        rawSettings?[PhotometricCatalogService.onlineEnabledSettingKey];
    final enabled =
        _pendingValue ?? (stored == null || stored.toLowerCase() != 'false');
    return SettingRow(
      icon: LucideIcons.globe,
      title: 'Deep catalog lookups (APASS DR9)',
      subtitle: 'Fetch B/V photometry to ~mag 16 from VizieR for zero-point '
          'calibration and the transform wizard. Cached per field for '
          'offline reuse; falls back to the bundled star catalog when off '
          'or unreachable.',
      trailing: SettingsSwitch(
        value: enabled,
        onChanged: _setEnabled,
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
  bool? _pendingValue;

  Future<void> _setAutoManaged(bool value) async {
    if (_pendingValue != null) return;
    setState(() => _pendingValue = value);
    try {
      await ref
          .read(scienceRawSettingsActionsProvider)
          .setCameraAutoManaged(value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Could not save camera setting: ${userFacingError(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingValue = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawSettings = ref.watch(scienceRawSettingsProvider).valueOrNull;
    final storedManaged = rawSettings?[ScienceCameraAutoConfig.autoManagedKey];
    final autoManaged = _pendingValue ??
        (storedManaged == null || storedManaged.toLowerCase() != 'false');
    final source = rawSettings?[ScienceCameraAutoConfig.autoSourceKey];
    final subtitle = autoManaged
        ? (source == null || source.isEmpty
            ? 'Read noise, gain, and saturation follow the connected camera '
                'or active profile'
            : 'Following: $source')
        : 'Manual — values below are user-set and will not be overwritten';
    return SettingRow(
      icon: LucideIcons.wand2,
      title: 'Auto-configure from camera',
      subtitle: subtitle,
      trailing: SettingsSwitch(
        value: autoManaged,
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
  late FocusNode _focusNode;
  bool _loading = true;
  late String _lastCommitted;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.defaultText);
    _lastCommitted = widget.defaultText;
    _focusNode = FocusNode()..addListener(_onFocusChange);
    _loadValue();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) _commit();
  }

  Future<void> _loadValue() async {
    final settings = await ref.read(scienceRawSettingsProvider.future);
    if (!mounted) return;
    _syncCommittedValue(settings[widget.settingKey] ?? widget.defaultText);
    _loading = false;
  }

  void _syncCommittedValue(String stored) {
    if (_focusNode.hasFocus || _controller.text != _lastCommitted) return;
    _controller.text = stored;
    _lastCommitted = stored;
  }

  Future<void> _commit() async {
    if (_loading) return;
    final value = _controller.text.trim();
    if (value == _lastCommitted) return;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) {
      setState(() {
        _validationError = 'Enter a number from ${widget.min} to ${widget.max}';
      });
      return;
    }
    setState(() => _validationError = null);
    final clamped = parsed.clamp(widget.min, widget.max);
    final stored =
        widget.integer ? clamped.round().toString() : clamped.toString();
    final previous = _lastCommitted;
    _lastCommitted = stored;
    try {
      await ref
          .read(scienceRawSettingsActionsProvider)
          .setManualCameraValue(widget.settingKey, stored);
    } catch (error) {
      _lastCommitted = previous;
      ref.invalidate(scienceRawSettingsProvider);
      if (mounted) {
        setState(() {
          _controller.text = previous;
          _validationError = 'Could not save this value';
        });
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              'Could not save camera value: ${userFacingError(error)}',
            ),
          ),
        );
      }
      return;
    }
    if (mounted) {
      _controller.text = stored;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawSettings = ref.watch(scienceRawSettingsProvider);
    if (!rawSettings.isLoading) {
      final authoritative =
          rawSettings.valueOrNull?[widget.settingKey] ?? widget.defaultText;
      if (authoritative != _lastCommitted &&
          !_focusNode.hasFocus &&
          _controller.text == _lastCommitted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncCommittedValue(authoritative);
        });
      }
    }
    return SettingRow(
      icon: widget.icon,
      title: widget.title,
      subtitle: _validationError ?? widget.subtitle,
      trailing: SizedBox(
        width: 72,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
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
          onSubmitted: (_) => _commit(),
        ),
      ),
      isLast: widget.isLast,
      isMobile: widget.isMobile,
    );
  }
}
