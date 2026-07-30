import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Summary + Save step.
///
/// Reviews the draft, lets the user name the profile, then commits it on
/// "Save profile". The Save action is wired in [OnboardingScreen]; here
/// we only render the review UI plus the name field.
class OnboardingSummaryStep extends ConsumerStatefulWidget {
  const OnboardingSummaryStep({super.key});

  @override
  ConsumerState<OnboardingSummaryStep> createState() =>
      _OnboardingSummaryStepState();
}

class _OnboardingSummaryStepState extends ConsumerState<OnboardingSummaryStep> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(onboardingDraftProvider);
    _nameController = TextEditingController(
      text: draft.profileName ?? 'My First Rig',
    );
    // Push the seeded name into the draft so the Save action picks it up
    // even if the user never modifies the field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(onboardingDraftProvider).profileName == null ||
          ref.read(onboardingDraftProvider).profileName!.trim().isEmpty) {
        ref
            .read(onboardingDraftProvider.notifier)
            .setProfileName(_nameController.text);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingDraftProvider);
    final colors = NightshadeColors.of(context);
    final theme = Theme.of(context);

    final imageScale = draft.imageScaleArcsecPerPixel;

    // The observing site lives in app settings (not the draft) because it is a
    // global observer setting. lat/lon both 0.0 is the "null island" default,
    // which we surface as "— not set —" rather than a bogus 0/0 coordinate.
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final siteSet = settings != null &&
        (settings.latitude != 0.0 || settings.longitude != 0.0);
    final siteValue = siteSet
        ? '${settings.latitude.toStringAsFixed(4)}°, '
            '${settings.longitude.toStringAsFixed(4)}°'
        : null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review and save',
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This creates your first equipment profile. You can edit any of these later.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Profile name',
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'My First Rig',
              hintStyle: TextStyle(color: colors.textMuted),
              enabledBorder: OutlineInputBorder(
                borderRadius: NightshadeTokens.borderRadiusInline8,
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: NightshadeTokens.borderRadiusInline8,
                borderSide: BorderSide(color: colors.primary),
              ),
              filled: true,
              fillColor: colors.surface,
            ),
            onChanged: (value) {
              ref.read(onboardingDraftProvider.notifier).setProfileName(value);
            },
          ),
          const SizedBox(height: 18),
          NightshadeCard(
            variant: CardVariant.subtle,
            borderRadius: NightshadeTokens.radiusLg,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(theme, colors, NightshadeIcons.camera, 'Camera',
                    draft.cameraName),
                _summaryRow(theme, colors, NightshadeIcons.compass, 'Mount',
                    draft.mountName),
                _summaryRow(theme, colors, NightshadeIcons.focuser, 'Focuser',
                    draft.focuserName ?? '— not set —'),
                _summaryRow(theme, colors, NightshadeIcons.filterWheel,
                    'Filter wheel', draft.filterWheelName ?? '— not set —'),
                if (draft.filterNames.isNotEmpty)
                  _summaryRow(theme, colors, NightshadeIcons.list, 'Filters',
                      draft.filterNames.join(', ')),
                _summaryRow(theme, colors, NightshadeIcons.crosshair, 'Guider',
                    draft.guiderName ?? '— not set —'),
                const Divider(height: 20),
                _summaryRow(
                    theme,
                    colors,
                    LucideIcons.ruler,
                    'Focal length',
                    draft.focalLengthMm != null
                        ? '${draft.focalLengthMm!.toStringAsFixed(1)} mm × ${draft.reducerFactor.toStringAsFixed(2)}'
                        : null),
                _summaryRow(
                    theme,
                    colors,
                    NightshadeIcons.aperture,
                    'Aperture',
                    draft.apertureMm != null
                        ? '${draft.apertureMm!.toStringAsFixed(1)} mm'
                        : null),
                _summaryRow(
                    theme,
                    colors,
                    NightshadeIcons.move,
                    'Image scale',
                    imageScale != null
                        ? '${imageScale.toStringAsFixed(2)} arcsec/px'
                        : null),
                const Divider(height: 20),
                // The camera-defaults step's set-points go straight into the
                // profile, so a review screen that omitted them was hiding a
                // whole step's worth of decisions from the last look the user
                // gets before the rig is created.
                _summaryRow(theme, colors, NightshadeIcons.sliders,
                    'Capture defaults', _captureDefaults(draft)),
                _summaryRow(theme, colors, NightshadeIcons.folder,
                    'Capture folder', draft.captureDirectory),
                _summaryRow(
                    theme, colors, LucideIcons.mapPin, 'Site', siteValue),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.primary,
              borderRadius: NightshadeTokens.borderRadiusLg,
            ),
            child: Row(
              children: [
                Icon(NightshadeIcons.info, color: colors.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Need polar alignment? Open Polar Alignment from the side nav after finishing.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The acquisition set-points as one line, listing only what is actually on
  /// record. Returns null (rendered "— not set —") when the user supplied
  /// nothing, rather than printing invented gain/offset numbers the profile does
  /// not carry.
  static String? _captureDefaults(OnboardingDraft draft) {
    final parts = <String>[
      if (draft.defaultGain != null) 'gain ${draft.defaultGain}',
      if (draft.defaultOffset != null) 'offset ${draft.defaultOffset}',
      if (draft.defaultBinX != null || draft.defaultBinY != null)
        'bin ${draft.defaultBinX ?? 1}×${draft.defaultBinY ?? 1}',
      if (draft.defaultCoolingTempC != null)
        '${draft.defaultCoolingTempC!.toStringAsFixed(0)} °C',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _summaryRow(ThemeData theme, NightshadeColors colors, IconData icon,
      String label, String? value) {
    final hasValue = value != null && value.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              hasValue ? value : '— not set —',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasValue ? colors.textPrimary : colors.textMuted,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
