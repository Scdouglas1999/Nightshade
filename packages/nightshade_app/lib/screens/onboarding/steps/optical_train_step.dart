import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Optical train step — pixel size (microns), focal length (mm),
/// aperture (mm), reducer factor. The image scale (arcsec/px) is
/// auto-computed from pixel size + effective focal length.
///
/// This is the only step where every field is required, because the
/// imaging stack needs these numbers to do plate solving, framing, and
/// FOV calculations correctly. We surface the computed image scale in
/// real time so the user can sanity-check their numbers before moving on.
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
      _apertureError = (ap != null && ap > 0)
          ? null
          : 'Enter a positive aperture in mm.';
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

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    final imageScale = draft.imageScaleArcsecPerPixel;
    final effectiveFocal = draft.effectiveFocalLengthMm;
    final fRatio = (draft.apertureMm != null &&
            draft.apertureMm! > 0 &&
            effectiveFocal != null)
        ? effectiveFocal / draft.apertureMm!
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tell us about your optics',
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Image scale and field of view are computed from these numbers, so accurate values matter.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        _NumericField(
          controller: _focalLengthController,
          label: 'Telescope focal length',
          hint: 'e.g. 500, 1000, 2000',
          suffix: 'mm',
          errorText: _focalLengthError,
          onChanged: _commit,
        ),
        const SizedBox(height: 12),
        _NumericField(
          controller: _apertureController,
          label: 'Aperture',
          hint: 'e.g. 80, 102, 200',
          suffix: 'mm',
          errorText: _apertureError,
          onChanged: _commit,
        ),
        const SizedBox(height: 12),
        _NumericField(
          controller: _reducerController,
          label: 'Reducer / Barlow factor',
          hint: '1.0 = no reducer, 0.79 = 0.79x reducer, 2.0 = 2x Barlow',
          suffix: 'x',
          errorText: _reducerError,
          onChanged: _commit,
        ),
        const SizedBox(height: 12),
        _NumericField(
          controller: _pixelSizeController,
          label: 'Camera pixel size',
          hint: 'Look this up in your camera spec sheet',
          suffix: 'µm',
          errorText: _pixelSizeError,
          onChanged: _commit,
        ),
        const SizedBox(height: 20),
        // Live preview of derived values. Renders with placeholder "--"
        // when inputs are missing rather than fabricating a value.
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
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
              const SizedBox(height: 10),
              _row(theme, colors, 'Effective focal length',
                  effectiveFocal != null
                      ? '${effectiveFocal.toStringAsFixed(1)} mm'
                      : '--'),
              _row(theme, colors, 'Focal ratio',
                  fRatio != null
                      ? 'f/${fRatio.toStringAsFixed(2)}'
                      : '--'),
              _row(
                theme,
                colors,
                'Image scale',
                imageScale != null
                    ? '${imageScale.toStringAsFixed(2)} arcsec/px'
                    : '--',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(ThemeData theme, NightshadeColors colors, String label,
      String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(LucideIcons.calculator,
              size: 14, color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NumericField extends StatelessWidget {
  const _NumericField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.suffix,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String suffix;
  final String? errorText;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: colors.textMuted),
            suffixText: suffix,
            suffixStyle: TextStyle(color: colors.textSecondary),
            errorText: errorText,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
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
