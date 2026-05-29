import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/help/field_help_label.dart';
import '../../../widgets/hardware/hardware_preset_picker_dialog.dart';

/// Optical train step — pixel size (microns), focal length (mm),
/// aperture (mm), reducer factor. The image scale (arcsec/px) is
/// auto-computed from pixel size + effective focal length.
///
/// Users can prefill the optics in one tap by picking from the built-in
/// telescope library (the [HardwarePresetPickerDialog], C10), or enter the
/// numbers manually. Either way the load-bearing fields — focal length,
/// aperture, pixel size — carry inline [FieldHelpLabel] hints so a first-time
/// imager understands where each value comes from without leaving the wizard.
///
/// This is the only step where focal length, aperture and pixel size are all
/// required, because the imaging stack needs them for plate solving, framing,
/// and FOV calculations. We surface the computed image scale in real time so
/// the user can sanity-check their numbers before moving on.
class OnboardingOpticalTrainStep extends ConsumerStatefulWidget {
  const OnboardingOpticalTrainStep({super.key});

  @override
  ConsumerState<OnboardingOpticalTrainStep> createState() =>
      _OnboardingOpticalTrainStepState();
}

class _OnboardingOpticalTrainStepState
    extends ConsumerState<OnboardingOpticalTrainStep> {
  late final TextEditingController _focalLengthController;
  late final TextEditingController _apertureController;
  late final TextEditingController _pixelSizeController;
  late final TextEditingController _reducerController;

  String? _focalLengthError;
  String? _apertureError;
  String? _pixelSizeError;
  String? _reducerError;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingDraftProvider);
    _focalLengthController = TextEditingController(
      text: draft.focalLengthMm?.toStringAsFixed(1) ?? '',
    );
    _apertureController = TextEditingController(
      text: draft.apertureMm?.toStringAsFixed(1) ?? '',
    );
    _pixelSizeController = TextEditingController(
      text: draft.pixelSizeMicrons?.toStringAsFixed(2) ?? '',
    );
    _reducerController = TextEditingController(
      text: draft.reducerFactor.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _focalLengthController.dispose();
    _apertureController.dispose();
    _pixelSizeController.dispose();
    _reducerController.dispose();
    super.dispose();
  }

  void _commit() {
    final fl = double.tryParse(_focalLengthController.text.trim());
    final ap = double.tryParse(_apertureController.text.trim());
    final px = double.tryParse(_pixelSizeController.text.trim());
    final rd = double.tryParse(_reducerController.text.trim());

    setState(() {
      _focalLengthError = (fl != null && fl > 0)
          ? null
          : 'Enter a positive focal length in mm.';
      _apertureError =
          (ap != null && ap > 0) ? null : 'Enter a positive aperture in mm.';
      _pixelSizeError = (px != null && px > 0)
          ? null
          : 'Enter a positive pixel size in microns.';
      _reducerError = (rd != null && rd > 0)
          ? null
          : 'Reducer must be > 0 (use 1.0 for no reducer).';
    });

    ref.read(onboardingDraftProvider.notifier).setOpticalTrain(
          focalLengthMm: fl,
          apertureMm: ap,
          pixelSizeMicrons: px,
          reducerFactor: rd,
        );
  }

  /// Open the telescope library and, on selection, apply the preset to the
  /// draft and reflect the new optics in the focal-length / aperture fields.
  /// The reducer and pixel size are intentionally left untouched — a reducer
  /// is a separate accessory and the pixel size comes from the camera, not the
  /// OTA.
  Future<void> _pickFromLibrary() async {
    final preset = await HardwarePresetPickerDialog.showTelescope(context);
    if (preset == null || !mounted) return;

    await ref
        .read(onboardingDraftProvider.notifier)
        .applyTelescopePreset(preset);
    if (!mounted) return;

    _focalLengthController.text = preset.focalLengthMm.toStringAsFixed(1);
    _apertureController.text = preset.apertureMm.toStringAsFixed(1);
    // Re-run validation so the inline errors clear for the now-valid optics.
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    final imageScale = draft.imageScaleArcsecPerPixel;
    final effectiveFocal = draft.effectiveFocalLengthMm;
    final fRatio = (draft.apertureMm != null &&
            draft.apertureMm! > 0 &&
            effectiveFocal != null)
        ? effectiveFocal / draft.apertureMm!
        : null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tell us about your optics',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs + 2),
          Text(
            'Image scale and field of view are computed from these numbers, so accurate values matter.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          // One-tap prefill from the built-in telescope catalog. Manual entry
          // below remains fully available regardless of whether a preset was
          // chosen.
          Row(
            children: [
              NightshadeButton(
                // lucide_icons 0.257.0 ships no `telescope` glyph; `aperture`
                // is this codebase's established optics/telescope icon
                // (equipment_profiles_screen, framing optical config panel).
                icon: LucideIcons.aperture,
                label: 'Choose from telescope library',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: _pickFromLibrary,
              ),
              if (draft.telescopeName != null) ...[
                const SizedBox(width: NightshadeTokens.spaceMd),
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.checkCircle2,
                          size: NightshadeTokens.iconSm, color: colors.success),
                      const SizedBox(width: NightshadeTokens.spaceSm),
                      Flexible(
                        child: Text(
                          draft.telescopeName!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          _NumericField(
            controller: _focalLengthController,
            label: 'Telescope focal length',
            help:
                "Focal length is the telescope's focal length in mm — found in its specs or on the OTA label.",
            hint: 'e.g. 500, 1000, 2000',
            suffix: 'mm',
            errorText: _focalLengthError,
            onChanged: _commit,
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _NumericField(
            controller: _apertureController,
            label: 'Aperture',
            help:
                'Aperture is the diameter of the telescope in mm — it sets the focal ratio (focal length ÷ aperture) and how much light you gather.',
            hint: 'e.g. 80, 102, 200',
            suffix: 'mm',
            errorText: _apertureError,
            onChanged: _commit,
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _NumericField(
            controller: _reducerController,
            label: 'Reducer / Barlow factor',
            help:
                'Multiplier applied to focal length: 1.0 = no reducer, 0.79 = a 0.79× reducer, 2.0 = a 2× Barlow.',
            hint: '1.0 = no reducer, 0.79 = 0.79x reducer, 2.0 = 2x Barlow',
            suffix: 'x',
            errorText: _reducerError,
            onChanged: _commit,
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _NumericField(
            controller: _pixelSizeController,
            label: 'Camera pixel size',
            help:
                "Pixel size in microns — from your camera's datasheet; sets your image scale.",
            hint: 'Look this up in your camera spec sheet',
            suffix: 'µm',
            errorText: _pixelSizeError,
            onChanged: _commit,
          ),
          const SizedBox(height: NightshadeTokens.spaceXl),
          // Live preview of derived values. Renders with placeholder "--"
          // when inputs are missing rather than fabricating a value.
          NightshadeCard(
            variant: CardVariant.subtle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Computed values',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: NightshadeTokens.spaceSm),
                _row(
                  theme,
                  colors,
                  'Effective focal length',
                  effectiveFocal != null
                      ? '${effectiveFocal.toStringAsFixed(1)} mm'
                      : null,
                ),
                _row(
                  theme,
                  colors,
                  'Focal ratio',
                  fRatio != null ? 'f/${fRatio.toStringAsFixed(2)}' : null,
                ),
                _row(
                  theme,
                  colors,
                  'Image scale',
                  imageScale != null
                      ? '${imageScale.toStringAsFixed(2)} arcsec/px'
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    NightshadeColors colors,
    String label,
    String? value,
  ) {
    final hasValue = value != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(LucideIcons.calculator,
              size: NightshadeTokens.iconXs, color: colors.textSecondary),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            hasValue ? value : 'Awaiting inputs…',
            // Numeric readouts use the mono type ramp so the digits line up
            // and the value reads as a computed quantity, not prose.
            style: hasValue
                ? NightshadeTypography.monoSm.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  )
                : theme.textTheme.bodySmall?.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// A labelled numeric input with an inline [FieldHelpLabel]. Mirrors the
/// onboarding wizard's existing field styling (dense outlined [TextField] on a
/// [NightshadeColors.surface] fill) so the optical-train step stays visually
/// consistent with the camera-defaults step and the rest of the flow.
class _NumericField extends StatelessWidget {
  const _NumericField({
    required this.controller,
    required this.label,
    required this.help,
    required this.hint,
    required this.suffix,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String help;
  final String hint;
  final String suffix;
  final String? errorText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldHelpLabel(label: label, help: help),
        const SizedBox(height: NightshadeTokens.spaceXs + 2),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: colors.textMuted),
            suffixText: suffix,
            suffixStyle: TextStyle(color: colors.textSecondary),
            errorText: errorText,
            enabledBorder: OutlineInputBorder(
              borderRadius: NightshadeTokens.borderRadiusMd,
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: NightshadeTokens.borderRadiusMd,
              borderSide: BorderSide(color: colors.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: NightshadeTokens.borderRadiusMd,
              borderSide: BorderSide(color: colors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: NightshadeTokens.borderRadiusMd,
              borderSide: BorderSide(color: colors.error),
            ),
            filled: true,
            fillColor: colors.surface,
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}
