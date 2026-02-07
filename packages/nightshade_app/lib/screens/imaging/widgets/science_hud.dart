import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../imaging_science_state.dart';

class ScienceHudPanel extends ConsumerWidget {
  final NightshadeColors colors;

  const ScienceHudPanel({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modeState = ref.watch(scienceModeStateProvider);
    final overlayState = ref.watch(scienceOverlayStateProvider);
    final settings = ref.watch(scienceSettingsProvider).valueOrNull ??
        const ScienceSettings();
    final photometrySelection =
        ref.watch(sciencePhotometrySelectionProvider).valueOrNull ??
            const SciencePhotometrySelection();
    final sessionConfig =
        ref.watch(activeScienceSessionConfigProvider).valueOrNull ??
            const ScienceSessionConfig();
    final selectedObject = ref.watch(selectedAnnotationObjectProvider);
    final photometryTarget = photometrySelection.target;
    final comparisonAnchors = photometrySelection.comparisons;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.flaskConical, size: 15, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Science HUD',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                Text(
                  'Informational only',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _FeatureToggle(
              colors: colors,
              title: 'Moving object mode',
              value: sessionConfig.movingObjectsEnabled,
              onChanged: (value) {
                ref.read(scienceModeStateProvider.notifier).state =
                    modeState.copyWith(movingObjectModeEnabled: value);
                _updateSessionConfig(
                  ref,
                  sessionConfig.copyWith(movingObjectsEnabled: value),
                );
              },
            ),
            _FeatureToggle(
              colors: colors,
              title: 'Session photometry',
              value: sessionConfig.photometryEnabled,
              onChanged: (value) => _updateSessionConfig(
                  ref, sessionConfig.copyWith(photometryEnabled: value)),
            ),
            _FeatureToggle(
              colors: colors,
              title: 'Photometric calibration',
              value: sessionConfig.calibrationEnabled,
              onChanged: (value) => _updateSessionConfig(
                ref,
                sessionConfig.copyWith(calibrationEnabled: value),
              ),
            ),
            _FeatureToggle(
              colors: colors,
              title: 'Transparency model',
              value: sessionConfig.transparencyEnabled,
              onChanged: (value) => _updateSessionConfig(
                ref,
                sessionConfig.copyWith(transparencyEnabled: value),
              ),
            ),
            _FeatureToggle(
              colors: colors,
              title: 'PSF map',
              value: sessionConfig.psfMapEnabled,
              onChanged: (value) => _updateSessionConfig(
                  ref, sessionConfig.copyWith(psfMapEnabled: value)),
            ),
            _FeatureToggle(
              colors: colors,
              title: 'Astrometric residuals',
              value: sessionConfig.residualsEnabled,
              onChanged: (value) => _updateSessionConfig(
                ref,
                sessionConfig.copyWith(residualsEnabled: value),
              ),
            ),
            _FeatureToggle(
              colors: colors,
              title: 'Narrowband tools',
              value: sessionConfig.narrowbandEnabled,
              onChanged: (value) => _updateSessionConfig(
                ref,
                sessionConfig.copyWith(narrowbandEnabled: value),
              ),
            ),
            const Divider(height: 18),
            Text(
              'Overlay layers',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _OverlayChip(
                  colors: colors,
                  label: 'PSF Heatmap',
                  active: overlayState.showPsfHeatmap,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showPsfHeatmap: !overlayState.showPsfHeatmap,
                    );
                  },
                ),
                _OverlayChip(
                  colors: colors,
                  label: 'Residual Vectors',
                  active: overlayState.showResidualVectors,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showResidualVectors: !overlayState.showResidualVectors,
                    );
                  },
                ),
                _OverlayChip(
                  colors: colors,
                  label: 'Object Tracks',
                  active: overlayState.showMovingObjectTracks,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showMovingObjectTracks:
                          !overlayState.showMovingObjectTracks,
                    );
                  },
                ),
                _OverlayChip(
                  colors: colors,
                  label: 'Uniformity',
                  active: overlayState.showUniformityMap,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showUniformityMap: !overlayState.showUniformityMap,
                    );
                  },
                ),
                _OverlayChip(
                  colors: colors,
                  label: 'Clip High',
                  active: overlayState.showClipHighMap,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showClipHighMap: !overlayState.showClipHighMap,
                    );
                  },
                ),
                _OverlayChip(
                  colors: colors,
                  label: 'Clip Low',
                  active: overlayState.showClipLowMap,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showClipLowMap: !overlayState.showClipLowMap,
                    );
                  },
                ),
                _OverlayChip(
                  colors: colors,
                  label: 'FWHM Surface',
                  active: overlayState.showFwhmSurface,
                  onTap: () {
                    ref.read(scienceOverlayStateProvider.notifier).state =
                        overlayState.copyWith(
                      showFwhmSurface: !overlayState.showFwhmSurface,
                    );
                  },
                ),
              ],
            ),
            const Divider(height: 18),
            Text(
              'Differential photometry',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            if (selectedObject != null)
              Text(
                'Selected: ${selectedObject.commonName ?? selectedObject.name}',
                style: TextStyle(color: colors.textPrimary, fontSize: 11),
              )
            else
              Text(
                'Click an annotated object to select it.',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: NightshadeButton(
                    onPressed: selectedObject == null
                        ? null
                        : () async {
                            await ref
                                .read(
                                    sciencePhotometrySelectionProvider.notifier)
                                .setTarget(
                                  PhotometryAnchor(
                                    objectId: selectedObject.id,
                                    label: selectedObject.commonName ??
                                        selectedObject.name,
                                    raDegrees: selectedObject.ra,
                                    decDegrees: selectedObject.dec,
                                  ),
                                );
                          },
                    label: 'Set Target',
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NightshadeButton(
                    onPressed: selectedObject == null
                        ? null
                        : () async {
                            await ref
                                .read(
                                    sciencePhotometrySelectionProvider.notifier)
                                .toggleComparison(
                                  PhotometryAnchor(
                                    objectId: selectedObject.id,
                                    label: selectedObject.commonName ??
                                        selectedObject.name,
                                    raDegrees: selectedObject.ra,
                                    decDegrees: selectedObject.dec,
                                  ),
                                );
                          },
                    label: 'Toggle Comp',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: NightshadeButton(
                    onPressed: () async {
                      await ref
                          .read(sciencePhotometrySelectionProvider.notifier)
                          .setTarget(null);
                    },
                    label: 'Clear Target',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NightshadeButton(
                    onPressed: () async {
                      await ref
                          .read(sciencePhotometrySelectionProvider.notifier)
                          .clearComparisons();
                    },
                    label: 'Clear Comps',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Target: ${photometryTarget?.label ?? 'auto-target'}',
              style: TextStyle(color: colors.textMuted, fontSize: 10),
            ),
            Text(
              'Comparisons: ${comparisonAnchors.isEmpty ? 'auto' : comparisonAnchors.length}',
              style: TextStyle(color: colors.textMuted, fontSize: 10),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: settings.photometryEnabled
                    ? () async {
                        final nextEnabled =
                            !photometrySelection.differentialEnabled;
                        await ref
                            .read(sciencePhotometrySelectionProvider.notifier)
                            .setDifferentialEnabled(nextEnabled);
                        ref.read(scienceModeStateProvider.notifier).state =
                            modeState.copyWith(
                          differentialPhotometryActive: nextEnabled,
                        );
                      }
                    : null,
                label: photometrySelection.differentialEnabled
                    ? 'Stop Differential Photometry'
                    : 'Start Differential Photometry',
                variant: photometrySelection.differentialEnabled
                    ? ButtonVariant.destructive
                    : ButtonVariant.primary,
                size: ButtonSize.small,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateSessionConfig(
    WidgetRef ref,
    ScienceSessionConfig config,
  ) async {
    final sessionId = ref.read(sessionStateProvider).dbSessionId;
    if (sessionId == null) {
      return;
    }
    await ref
        .read(scienceSessionConfigControllerProvider)
        .save(sessionId, config);
  }
}

class _FeatureToggle extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FeatureToggle({
    required this.colors,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

class _OverlayChip extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _OverlayChip({
    required this.colors,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? colors.primary.withValues(alpha: 0.2)
              : colors.surfaceAlt.withValues(alpha: 0.8),
          border: Border.all(
            color: active ? colors.primary : colors.border,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? colors.primary : colors.textSecondary,
            fontSize: 10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
