import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Correct the sensor values the app resolved for a camera.
///
/// Every field arrives filled in with whatever the resolution chain found and
/// labelled with where that came from, so this is a correction surface rather
/// than a datasheet transcription exercise: the user changes the one figure
/// they disagree with and leaves the rest. What they type becomes tier (a) of
/// the chain and is never overwritten by a reading or a published figure.
///
/// Reachable from the Plan screen (where the numbers are used) and from the
/// Smart Night builder (where a missing one stops a plan).
class CameraSensorSpecsDialog extends ConsumerStatefulWidget {
  const CameraSensorSpecsDialog({super.key, required this.specs});

  /// What the chain resolved, which is what the fields start from.
  final ResolvedCameraSensorSpecs specs;

  /// Shows the dialog for the active camera. Resolves to true when the user
  /// saved, so the caller can re-read the chain.
  static Future<bool> show(
      BuildContext context, ResolvedCameraSensorSpecs specs) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CameraSensorSpecsDialog(specs: specs),
    );
    return saved ?? false;
  }

  @override
  ConsumerState<CameraSensorSpecsDialog> createState() =>
      _CameraSensorSpecsDialogState();
}

class _CameraSensorSpecsDialogState
    extends ConsumerState<CameraSensorSpecsDialog> {
  /// Field keys are part of the widget test contract for this dialog.
  static const _pixelSizeKey = Key('camera-sensor-spec-pixel-size');
  static const _widthKey = Key('camera-sensor-spec-width');
  static const _heightKey = Key('camera-sensor-spec-height');
  static const _readNoiseKey = Key('camera-sensor-spec-read-noise');
  static const _fullWellKey = Key('camera-sensor-spec-full-well');
  static const _qeKey = Key('camera-sensor-spec-qe');
  static const _gainKey = Key('camera-sensor-spec-gain');
  static const _modelKey = Key('camera-sensor-spec-model');

  late final TextEditingController _model;
  late final TextEditingController _gain;
  late final TextEditingController _pixelSize;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _readNoise;
  late final TextEditingController _fullWell;
  late final TextEditingController _qe;

  String? _error;
  bool _saving = false;

  ResolvedCameraSensorSpecs get _specs => widget.specs;

  @override
  void initState() {
    super.initState();
    final entry = _specs.databaseEntry;
    _model = TextEditingController(
      text: entry?.model ?? _specs.reportedModel ?? '',
    );
    _gain = TextEditingController(text: _quotedGain()?.toString() ?? '');
    _pixelSize = _prefilled(_specs.pixelSizeMicrons, decimals: 3);
    _width = _prefilled(_specs.sensorWidthPx);
    _height = _prefilled(_specs.sensorHeightPx);
    _readNoise = _prefilled(_specs.readNoiseE, decimals: 2);
    _fullWell = _prefilled(_specs.fullWellE);
    _qe = _prefilled(_specs.qePeakFraction, decimals: 2);
  }

  /// The driver gain a published figure was quoted at, when there is one, so
  /// the user's entry is stored against the same operating point rather than a
  /// default that does not match it.
  int? _quotedGain() {
    for (final figure in [
      ..._specs.databaseEntry?.readNoiseE ?? const <PublishedFigure>[],
      ..._specs.databaseEntry?.fullWellE ?? const <PublishedFigure>[],
    ]) {
      if (figure.driverGain != null) return figure.driverGain;
    }
    return null;
  }

  static TextEditingController _prefilled(
    SensorSpecValue<Object>? value, {
    int? decimals,
  }) {
    final raw = value?.value;
    if (raw == null) return TextEditingController();
    if (raw is int) return TextEditingController(text: raw.toString());
    final number = raw as double;
    if (decimals == null) {
      return TextEditingController(text: number.round().toString());
    }
    var text = number.toStringAsFixed(decimals);
    while (text.contains('.') && (text.endsWith('0') || text.endsWith('.'))) {
      text = text.substring(0, text.length - 1);
    }
    return TextEditingController(text: text);
  }

  @override
  void dispose() {
    for (final controller in [
      _model,
      _gain,
      _pixelSize,
      _width,
      _height,
      _readNoise,
      _fullWell,
      _qe,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;
    final camera =
        _specs.databaseEntry?.model ?? _specs.reportedModel ?? 'this camera';

    final dialog = AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        'Camera sensor specs',
        style: NightshadeTypography.sectionTitle.copyWith(
          color: colors.textPrimary,
        ),
      ),
      // A definite width, not a max: the content column stretches its fields
      // to the dialog's width, and AlertDialog measures its child's intrinsic
      // width, which an unbounded stretch cannot answer.
      content: SizedBox(
        width: AdaptiveDialogConstraints.dialogSize(
          context,
          designWidth: _dialogWidth,
        ).width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _specs.isEmpty
                    ? 'Nothing is published for $camera. Enter what you know '
                        'and planning uses it from now on.'
                    : 'These are the values planning is using for $camera. '
                        'Change any you disagree with; yours win from then '
                        'on.',
                style: NightshadeTypography.bodySm.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              if (_specs.databaseEntry?.note case final note?) ...[
                const SizedBox(height: NightshadeTokens.spaceSm),
                NightshadeBanner(
                  title: 'About these figures',
                  message: note,
                  tone: BannerTone.info,
                ),
              ],
              const SizedBox(height: NightshadeTokens.spaceMd),
              _field(
                fieldKey: _modelKey,
                controller: _model,
                label: 'Camera model',
                provenance:
                    'The name these values are stored against. Leave it as '
                    'the model your driver reports.',
              ),
              _field(
                fieldKey: _gainKey,
                controller: _gain,
                label: 'Gain these values are for',
                numeric: true,
                integer: true,
                provenance:
                    'Read noise and full well change with gain, so they are '
                    'stored against one. Blank means your profile default.',
              ),
              _field(
                fieldKey: _pixelSizeKey,
                controller: _pixelSize,
                label: 'Pixel size (µm)',
                numeric: true,
                provenance: _provenanceOf(SensorSpecField.pixelSize),
              ),
              _field(
                fieldKey: _widthKey,
                controller: _width,
                label: 'Sensor width (px)',
                numeric: true,
                integer: true,
                provenance: _provenanceOf(SensorSpecField.sensorWidth),
              ),
              _field(
                fieldKey: _heightKey,
                controller: _height,
                label: 'Sensor height (px)',
                numeric: true,
                integer: true,
                provenance: _provenanceOf(SensorSpecField.sensorHeight),
              ),
              _field(
                fieldKey: _readNoiseKey,
                controller: _readNoise,
                label: 'Read noise (e⁻)',
                numeric: true,
                provenance: _provenanceOf(SensorSpecField.readNoise),
              ),
              _field(
                fieldKey: _fullWellKey,
                controller: _fullWell,
                label: 'Full well (e⁻)',
                numeric: true,
                provenance: _provenanceOf(SensorSpecField.fullWell),
              ),
              _field(
                fieldKey: _qeKey,
                controller: _qe,
                label: 'Peak QE (0–1)',
                numeric: true,
                provenance: _provenanceOf(SensorSpecField.qePeak),
                isLast: true,
              ),
              if (_error case final error?) ...[
                const SizedBox(height: NightshadeTokens.spaceMd),
                NightshadeBanner(
                  title: error,
                  tone: BannerTone.error,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        ),
        NightshadeButton(
          label: 'Save specs',
          variant: ButtonVariant.primary,
          size: ButtonSize.small,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
    return PopScope(canPop: !_saving, child: dialog);
  }

  /// The dialog's design width. Wide enough for a provenance sentence under
  /// each field without it wrapping to three lines.
  static const double _dialogWidth = 480;

  /// What the chain says about one field, as the sentence under its input.
  String _provenanceOf(SensorSpecField field) {
    final value = _specs[field];
    if (value == null) {
      return 'Not published for this camera. Planning falls back to a '
          'conservative estimate until you fill it in.';
    }
    final sentence = value.provenance;
    return '${sentence[0].toUpperCase()}${sentence.substring(1)}.';
  }

  Widget _field({
    required Key fieldKey,
    required TextEditingController controller,
    required String label,
    required String provenance,
    bool numeric = false,
    bool integer = false,
    bool isLast = false,
  }) {
    final colors = context.nightshadeColors;
    return Padding(
      padding: EdgeInsets.only(
        bottom: isLast ? 0 : NightshadeTokens.spaceMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NightshadeTextField(
            key: fieldKey,
            controller: controller,
            label: label,
            dense: true,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
            inputFormatters: numeric
                ? [
                    FilteringTextInputFormatter.allow(
                      integer ? RegExp(r'[0-9]') : RegExp(r'[0-9.]'),
                    ),
                  ]
                : null,
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            provenance,
            style: NightshadeTypography.caption.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  double? _number(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  Future<void> _save() async {
    final model = _model.text.trim();
    if (model.isEmpty) {
      setState(() => _error = 'Name the camera these values belong to.');
      return;
    }
    final pixelSize = _number(_pixelSize);
    final width = _number(_width);
    final height = _number(_height);
    final readNoise = _number(_readNoise);
    final fullWell = _number(_fullWell);
    final qe = _number(_qe);

    if (qe != null && qe > 1) {
      setState(() => _error = 'Peak QE is a fraction: 0.6 means 60%.');
      return;
    }
    // Read noise and full well are stored as one point on a gain curve, so a
    // value without its gain would be a figure with no operating point — the
    // exact thing the published database refuses to invent.
    final gain = int.tryParse(_gain.text.trim());
    if ((readNoise != null || fullWell != null) && gain == null) {
      setState(
        () => _error =
            'Give the gain that read noise and full well were measured at.',
      );
      return;
    }
    if (readNoise != null && fullWell == null) {
      setState(() => _error = 'Enter full well as well as read noise.');
      return;
    }
    if (fullWell != null && readNoise == null) {
      setState(() => _error = 'Enter read noise as well as full well.');
      return;
    }
    if (pixelSize == null &&
        width == null &&
        height == null &&
        readNoise == null &&
        qe == null) {
      setState(() => _error = 'Fill in at least one value.');
      return;
    }
    // The stored shape carries a pixel pitch and a QE alongside the gain
    // points, so those two need a value even when the user only came to fix
    // read noise. Falling back to what the chain already resolved keeps the
    // saved row equal to what was on screen.
    final effectivePixelSize = pixelSize ?? _specs.pixelSizeMicrons?.value;
    final effectiveQe = qe ?? _specs.qePeakFraction?.value;
    if (effectivePixelSize == null) {
      setState(
        () => _error =
            'Enter the pixel size: nothing else can be scaled without it.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final existing = await _loadExisting();
      final alias = _specs.reportedModel?.trim();
      final resolvedGain = gain ?? _quotedGain() ?? _fallbackGain;
      final spec = CameraHardwareSpec(
        model: model,
        aliases: alias == null ||
                alias.isEmpty ||
                alias.toLowerCase() == model.toLowerCase()
            ? const []
            : [alias],
        pixelSizeMicrons: effectivePixelSize,
        qePeak: effectiveQe ?? _fallbackQePeak,
        defaultGain: resolvedGain,
        sensorWidthPx: width?.round(),
        sensorHeightPx: height?.round(),
        gainPoints: [
          CameraGainPoint(
            gain: resolvedGain,
            readNoiseE:
                readNoise ?? _specs.readNoiseE?.value ?? _fallbackReadNoiseE,
            fullWellE:
                fullWell ?? _specs.fullWellE?.value ?? _fallbackFullWellE,
          ),
        ],
      );
      existing.removeWhere(
        (entry) => entry.model.toLowerCase() == model.toLowerCase(),
      );
      existing.add(spec);
      await _persist(existing);
      ref.invalidate(activeCameraSensorSpecsProvider);
      ref.invalidate(smartNightExposureContextProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save camera specs: $error';
      });
    }
  }

  /// Stand-ins for the two fields the stored shape requires but the user may
  /// not have supplied and the chain could not resolve. Same conservative
  /// planning estimates the exposure context falls back to, so an override
  /// that only fixes pixel size does not quietly improve the noise model.
  static const int _fallbackGain = 100;
  static const double _fallbackQePeak = 0.65;
  static const double _fallbackReadNoiseE = 3.5;
  static const double _fallbackFullWellE = 18000;

  Future<List<CameraHardwareSpec>> _loadExisting() async {
    final backend = ref.read(backendProvider);
    final raw = backend is NetworkBackend
        ? (await backend.getSmartNightSettings())[
            HardwareSpecsService.cameraOverridesSettingKey]
        : await ref
            .read(settingsDaoProvider)
            .getSetting(HardwareSpecsService.cameraOverridesSettingKey);
    if (raw == null || raw.trim().isEmpty) return [];
    return HardwareSpecsService.cameraOverridesFromJson(
      jsonDecode(raw),
    ).toList();
  }

  Future<void> _persist(List<CameraHardwareSpec> specs) async {
    final encoded = jsonEncode(specs.map((spec) => spec.toJson()).toList());
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      await backend.updateSmartNightSettings({
        HardwareSpecsService.cameraOverridesSettingKey: encoded,
      });
      return;
    }
    await ref.read(settingsDaoProvider).setSetting(
          HardwareSpecsService.cameraOverridesSettingKey,
          encoded,
        );
  }
}

/// The one action that fixes an unresolved sensor spec, for a banner.
///
/// Lives here so the Plan screen and the Smart Night builder offer the same
/// remedy with the same words.
class CameraSensorSpecsAction extends ConsumerWidget {
  const CameraSensorSpecsAction({
    super.key,
    required this.specs,
    this.label = 'Enter camera specs',
  });

  final ResolvedCameraSensorSpecs specs;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NightshadeButton(
      label: label,
      icon: LucideIcons.sliders,
      variant: ButtonVariant.secondary,
      size: ButtonSize.small,
      onPressed: () => CameraSensorSpecsDialog.show(context, specs),
    );
  }
}
