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

class _OnboardingSummaryStepState
    extends ConsumerState<OnboardingSummaryStep> {
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    final imageScale = draft.imageScaleArcsecPerPixel;

    return Column(
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
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary),
            ),
            filled: true,
            fillColor: colors.surface,
          ),
          onChanged: (value) {
            ref
                .read(onboardingDraftProvider.notifier)
                .setProfileName(value);
          },
        ),
        const SizedBox(height: 18),
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
              _summaryRow(theme, colors, LucideIcons.camera, 'Camera',
                  draft.cameraName),
              _summaryRow(theme, colors, LucideIcons.compass, 'Mount',
                  draft.mountName),
              _summaryRow(theme, colors, LucideIcons.focus, 'Focuser',
                  draft.focuserName ?? '— not set —'),
              _summaryRow(theme, colors, LucideIcons.disc, 'Filter wheel',
                  draft.filterWheelName ?? '— not set —'),
              if (draft.filterNames.isNotEmpty)
                _summaryRow(theme, colors, LucideIcons.list, 'Filters',
                    draft.filterNames.join(', ')),
              _summaryRow(theme, colors, LucideIcons.crosshair, 'Guider',
                  draft.guiderName ?? '— not set —'),
              const Divider(height: 20),
              _summaryRow(theme, colors, LucideIcons.ruler, 'Focal length',
                  draft.focalLengthMm != null
                      ? '${draft.focalLengthMm!.toStringAsFixed(1)} mm × ${draft.reducerFactor.toStringAsFixed(2)}'
                      : null),
              _summaryRow(theme, colors, LucideIcons.aperture, 'Aperture',
                  draft.apertureMm != null
                      ? '${draft.apertureMm!.toStringAsFixed(1)} mm'
                      : null),
              _summaryRow(theme, colors, LucideIcons.move, 'Image scale',
                  imageScale != null
                      ? '${imageScale.toStringAsFixed(2)} arcsec/px'
                      : null),
              const Divider(height: 20),
              _summaryRow(theme, colors, LucideIcons.folder,
                  'Capture folder', draft.captureDirectory),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: colors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, color: colors.primary, size: 16),
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
    );
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
                color:
                    hasValue ? colors.textPrimary : colors.textMuted,
                fontWeight:
                    hasValue ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
