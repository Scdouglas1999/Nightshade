import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
// Outside the core barrel by design (it collides with `cameraPresetsProvider`),
// so imported by source path — the route the preset picker dialog takes too.
// ignore: implementation_imports
import 'package:nightshade_core/src/providers/hardware_presets_provider.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/help/field_help_label.dart';
import '../../../widgets/hardware/hardware_preset_picker_dialog.dart';

/// One-tap "use the library entry for the camera you already picked". Exposed
/// so tests can target it without matching on the camera's name.
const Key cameraDefaultsUseMatchedPresetKey =
    Key('onboarding.cameraDefaults.useMatchedPreset');

/// Camera-defaults step — the acquisition set-points (gain / offset /
/// binning / cooling) that the created equipment profile is seeded with.
///
/// New imagers routinely lose their first night hunting forum threads for the
/// "right" gain and offset. This step removes that friction: picking from the
/// built-in camera library (the [HardwarePresetPickerDialog], C10) prefills
/// every field with the community-standard set-point for that sensor, and the
/// user can accept them as-is or tweak any value. Each field carries an inline
/// [FieldHelpLabel] explaining what it does.
///
/// The step is optional — the wizard footer shows a "Skip this step" affordance
/// and validation always passes — because sensible defaults already exist.
class OnboardingCameraDefaultsStep extends ConsumerStatefulWidget {
  const OnboardingCameraDefaultsStep({super.key});

  @override
  ConsumerState<OnboardingCameraDefaultsStep> createState() =>
      _OnboardingCameraDefaultsStepState();
}

class _OnboardingCameraDefaultsStepState
    extends ConsumerState<OnboardingCameraDefaultsStep> {
  /// Single home for the all-season cooled-CMOS default set-point. Routing the
  /// literal through one named constant (rather than scattering `-10.0`) means
  /// the forward-compat seam in [_resolveCoolingSeed] — which prefers the
  /// camera's [CameraRecommendedSettings.recommendedCoolingSetpointC] when a
  /// vendor SDK starts reporting it — has exactly one fallback to fall back to.
  static const double _kDefaultCoolingSetpointC = -10.0;

  late final TextEditingController _gainController;
  late final TextEditingController _offsetController;
  late final TextEditingController _binXController;
  late final TextEditingController _binYController;
  late final TextEditingController _coolingController;

  String? _gainError;
  String? _offsetError;
  String? _binXError;
  String? _binYError;
  String? _coolingError;

  /// Whether the regulated-cooling section is expanded.
  ///
  /// Seeded from the draft, then owned locally. It cannot be derived from
  /// `defaultCoolingTempC != null` any more: emptying the set-point field has
  /// to null the stored value (otherwise a blank box sits above a profile that
  /// still carries the old set-point), and deriving the toggle from that value
  /// would collapse the field out from under the user mid-edit.
  late bool _coolingOn;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingDraftProvider);
    _coolingOn = draft.defaultCoolingTempC != null;
    _gainController =
        TextEditingController(text: draft.defaultGain?.toString() ?? '');
    _offsetController =
        TextEditingController(text: draft.defaultOffset?.toString() ?? '');
    _binXController =
        TextEditingController(text: (draft.defaultBinX ?? 1).toString());
    _binYController =
        TextEditingController(text: (draft.defaultBinY ?? 1).toString());
    _coolingController = TextEditingController(
      text: draft.defaultCoolingTempC != null
          ? draft.defaultCoolingTempC!.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _gainController.dispose();
    _offsetController.dispose();
    _binXController.dispose();
    _binYController.dispose();
    _coolingController.dispose();
    super.dispose();
  }

  /// Push the edited integer set-points (gain/offset/binning) into the draft,
  /// validating each. Cooling is committed separately by [_commitCooling]
  /// because it is nullable and gated behind the cooling toggle.
  ///
  /// A field the user emptied is cleared, not left at its previous value: these
  /// numbers are copied verbatim into the created equipment profile, so a blank
  /// Gain box above a profile that still carries the preset's gain is the
  /// wizard telling the user something untrue about the rig it is about to
  /// build. A rejected value (a binning below 1) is likewise not stored — the
  /// red field message is the honest answer, and the profile falls back to its
  /// own default rather than recording a number the step refused.
  void _commitIntegers() {
    final gainRaw = _gainController.text.trim();
    final offsetRaw = _offsetController.text.trim();
    final binXRaw = _binXController.text.trim();
    final binYRaw = _binYController.text.trim();
    final gain = int.tryParse(gainRaw);
    final offset = int.tryParse(offsetRaw);
    final binX = int.tryParse(binXRaw);
    final binY = int.tryParse(binYRaw);

    setState(() {
      _gainError =
          gainRaw.isEmpty || gain != null ? null : 'Enter a whole number.';
      _offsetError =
          offsetRaw.isEmpty || offset != null ? null : 'Enter a whole number.';
      _binXError = (binX != null && binX >= 1) ? null : 'Binning is 1 or more.';
      _binYError = (binY != null && binY >= 1) ? null : 'Binning is 1 or more.';
    });

    final usableBinX = binX != null && binX >= 1;
    final usableBinY = binY != null && binY >= 1;
    ref.read(onboardingDraftProvider.notifier).setCameraDefaults(
          gain: gain,
          offset: offset,
          binX: usableBinX ? binX : null,
          binY: usableBinY ? binY : null,
          clearGain: gain == null,
          clearOffset: offset == null,
          clearBinX: !usableBinX,
          clearBinY: !usableBinY,
        );
  }

  void _commitCooling() {
    final raw = _coolingController.text.trim();
    final temp = double.tryParse(raw);
    setState(() {
      _coolingError = raw.isEmpty || temp != null
          ? null
          : 'Enter a temperature in °C (e.g. -10).';
    });
    if (temp != null) {
      ref
          .read(onboardingDraftProvider.notifier)
          .setCameraDefaults(coolingTempC: temp);
    } else {
      // Blank or half-typed ("-"): there is no set-point to save. Keep the
      // section open (the user is mid-edit) but do not leave a stale number on
      // record behind an empty box.
      ref
          .read(onboardingDraftProvider.notifier)
          .setCameraDefaults(clearCoolingTempC: true);
    }
  }

  /// Arm (or disarm) cool-on-connect for the profile this wizard will create.
  Future<void> _toggleCoolOnConnect(bool enabled) async {
    await ref
        .read(onboardingDraftProvider.notifier)
        .setCameraDefaults(coolOnConnect: enabled);
  }

  Future<void> _toggleCooling(bool enabled) async {
    final notifier = ref.read(onboardingDraftProvider.notifier);
    setState(() => _coolingOn = enabled);
    if (enabled) {
      // Seed a sensible set-point when the user turns cooling on and nothing is
      // entered yet. Prefer whatever is already typed; otherwise ask the
      // selected camera for its recommended set-point, falling back to the
      // built-in cooled-CMOS default.
      final existing = double.tryParse(_coolingController.text.trim());
      final seed = existing ?? await _resolveCoolingSeed();
      if (!mounted) return;
      _coolingController.text = seed.toStringAsFixed(0);
      setState(() => _coolingError = null);
      await notifier.setCameraDefaults(coolingTempC: seed);
    } else {
      _coolingController.clear();
      setState(() => _coolingError = null);
      await notifier.setCameraDefaults(clearCoolingTempC: true);
    }
  }

  /// Resolve the cooling set-point to seed when the user enables regulated
  /// cooling with no value yet entered.
  ///
  /// Forward-compat seam: when the draft has a selected camera we ask its
  /// vendor SDK (via the same recommended-settings path the equipment editor
  /// uses) for [CameraRecommendedSettings.recommendedCoolingSetpointC]. That
  /// field is `None` across every backend we currently bind, so today this is
  /// equivalent to [_kDefaultCoolingSetpointC] — but the literal lives in one
  /// place, and the instant a vendor SDK starts reporting a recommended
  /// set-point the onboarding seed picks it up with no further wiring.
  ///
  /// A query failure (camera not connected — common during setup — or an SDK
  /// that exposes no recommendation) is not an error here: it simply means
  /// "no recommendation", so we fall back to the built-in default.
  Future<double> _resolveCoolingSeed() async {
    final deviceId = ref.read(onboardingDraftProvider).cameraId;
    if (deviceId == null || deviceId.isEmpty) {
      return _kDefaultCoolingSetpointC;
    }
    try {
      final rec = await ref
          .read(deviceServiceProvider)
          .queryRecommendedCameraSettings(deviceId);
      return rec.recommendedCoolingSetpointC ?? _kDefaultCoolingSetpointC;
    } catch (_) {
      // No recommendation available (camera offline / SDK silent). Honest
      // fallback to the published default — never fabricated, never thrown.
      return _kDefaultCoolingSetpointC;
    }
  }

  /// The library entry for the camera picked at the camera step, when the name
  /// the driver reported resolves to exactly one. Null for an unrecognised
  /// camera — a wrong preset is worse than no preset.
  CameraDefaultsPreset? get _matchedPreset {
    final name = ref.watch(onboardingDraftProvider).cameraName;
    return ref.read(hardwarePresetsServiceProvider).matchCameraByName(name);
  }

  Future<void> _pickFromLibrary() async {
    final preset = await HardwarePresetPickerDialog.showCamera(context);
    if (preset == null || !mounted) return;
    await _applyPreset(preset);
  }

  Future<void> _applyPreset(CameraDefaultsPreset preset) async {
    await ref.read(onboardingDraftProvider.notifier).applyCameraPreset(preset);
    if (!mounted) return;

    // Reflect the applied preset in the editable fields.
    _gainController.text = preset.recommendedGain.toString();
    _offsetController.text = preset.recommendedOffset.toString();
    _binXController.text = preset.recommendedBinX.toString();
    _binYController.text = preset.recommendedBinY.toString();
    _coolingController.text = preset.recommendedCoolingTempC != null
        ? preset.recommendedCoolingTempC!.toStringAsFixed(0)
        : '';
    setState(() {
      // A DSLR preset (no regulated cooling) closes the section; a cooled preset
      // opens it on its recommended set-point.
      _coolingOn = preset.recommendedCoolingTempC != null;
      _gainError = null;
      _offsetError = null;
      _binXError = null;
      _binYError = null;
      _coolingError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    // Local, not derived from the stored set-point — see [_coolingOn].
    final coolingEnabled = _coolingOn;
    final coolOnConnect = draft.coolOnConnect;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your capture defaults',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs + 2),
          Text(
            'These seed every new sequence. Pick your camera to load the recommended set-points, then adjust to taste — you can change them any time later.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          // The camera was already named two steps ago. Making the user find it
          // again in a library the app can search itself was asking the same
          // question twice; when the match is unambiguous, offer it by name as
          // one tap. Still a tap, not a silent write — gain and offset are the
          // user's call, and the library only recommends.
          if (draft.cameraPresetId == null && _matchedPreset != null) ...[
            NightshadeButton(
              key: cameraDefaultsUseMatchedPresetKey,
              icon: NightshadeIcons.camera,
              label: 'Use ${_matchedPreset!.displayName} settings',
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: () => _applyPreset(_matchedPreset!),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
          ],
          Row(
            children: [
              NightshadeButton(
                icon: NightshadeIcons.camera,
                label: 'Choose from camera library',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: _pickFromLibrary,
              ),
              if (draft.cameraPresetId != null) ...[
                const SizedBox(width: NightshadeTokens.spaceMd),
                Icon(LucideIcons.checkCircle2,
                    size: NightshadeTokens.iconSm, color: colors.success),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Flexible(
                  child: Text(
                    'Defaults loaded from preset',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _NumberField(
                  controller: _gainController,
                  label: 'Gain',
                  help:
                      'Gain sets sensor amplification; for most CMOS the unity/recommended value is a good start.',
                  hint: 'e.g. 100',
                  allowNegative: false,
                  errorText: _gainError,
                  onChanged: _commitIntegers,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: _NumberField(
                  controller: _offsetController,
                  label: 'Offset',
                  help:
                      'Offset lifts the black point so darks are not clipped.',
                  hint: 'e.g. 50',
                  allowNegative: false,
                  errorText: _offsetError,
                  onChanged: _commitIntegers,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _NumberField(
                  controller: _binXController,
                  label: 'Bin X',
                  help:
                      'Horizontal pixel binning. 1 keeps full resolution; 2 combines 2×2 pixels for higher signal at lower resolution.',
                  hint: '1',
                  allowNegative: false,
                  errorText: _binXError,
                  onChanged: _commitIntegers,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: _NumberField(
                  controller: _binYController,
                  label: 'Bin Y',
                  help: 'Vertical pixel binning. Almost always matches Bin X.',
                  hint: '1',
                  allowNegative: false,
                  errorText: _binYError,
                  onChanged: _commitIntegers,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          NightshadeCard(
            variant: CardVariant.subtle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NightshadeSwitchRow(
                  label: 'Regulated cooling',
                  subtitle:
                      'Turn on for a cooled camera; leave off for a DSLR or an uncooled sensor.',
                  value: coolingEnabled,
                  onChanged: (v) => _toggleCooling(v),
                ),
                if (coolingEnabled) ...[
                  const SizedBox(height: NightshadeTokens.spaceMd),
                  _NumberField(
                    controller: _coolingController,
                    label: 'Cooling set-point',
                    help:
                        'Target sensor temperature in °C. −10 is a common all-season set-point; pick something your cooler can hold below ambient.',
                    hint: 'e.g. -10',
                    suffix: '°C',
                    allowNegative: true,
                    allowDecimal: true,
                    errorText: _coolingError,
                    onChanged: _commitCooling,
                  ),
                  const SizedBox(height: NightshadeTokens.spaceMd),
                  // Without this the wizard collected a set-point and then
                  // never used it: the profile was written with
                  // cool_on_connect = 0, the camera sat at ambient all night,
                  // and the only way to arm the cooler was a checkbox buried in
                  // Equipment > Edit Profile > Camera Defaults. Asked here,
                  // defaulted off — a rig set up at noon must not pin the TEC
                  // at full power for the afternoon.
                  NightshadeSwitchRow(
                    label: 'Start cooling when the camera connects',
                    subtitle: coolOnConnect
                        ? 'Nightshade will drive the sensor to the set-point as '
                            'soon as the camera connects.'
                        : 'Leave off to start the cooler yourself from the '
                            'Equipment screen when you are ready to image.',
                    value: coolOnConnect,
                    onChanged: _toggleCoolOnConnect,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled numeric input pairing a [FieldHelpLabel] with a
/// [NightshadeTextField]. Integer-only by default; pass [allowDecimal] /
/// [allowNegative] for the cooling set-point.
class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.help,
    required this.hint,
    required this.onChanged,
    this.suffix,
    this.errorText,
    this.allowNegative = false,
    this.allowDecimal = false,
  });

  final TextEditingController controller;
  final String label;
  final String help;
  final String hint;
  final String? suffix;
  final String? errorText;
  final bool allowNegative;
  final bool allowDecimal;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final pattern = StringBuffer('[0-9');
    if (allowNegative) pattern.write(r'\-');
    if (allowDecimal) pattern.write(r'\.');
    pattern.write(']');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldHelpLabel(label: label, help: help),
        const SizedBox(height: NightshadeTokens.spaceXs + 2),
        NightshadeTextField(
          controller: controller,
          hint: hint,
          suffix: suffix,
          errorText: errorText,
          keyboardType: TextInputType.numberWithOptions(
            decimal: allowDecimal,
            signed: allowNegative,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(pattern.toString())),
          ],
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}
