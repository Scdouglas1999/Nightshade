import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../analytics/widgets/science_status_banner.dart';
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
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(NightshadeIcons.science, size: 15, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Science HUD',
                  style: NightshadeTypography.labelStrong.copyWith(color: colors.textPrimary),
                ),
                const Spacer(),
                Text(
                  'Informational only',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // P0.2: status banner — collapses to a single line when there is
            // nothing in flight, expands when science is working. Hidden
            // entirely if the pipeline is idle AND empty.
            const ScienceStatusBanner(hideWhenIdle: true),
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
            // P3.1: contextual suggestions. Watches the current session's
            // image list and offers one-tap enable for features the user
            // looks ready for (multi-frame for moving objects, NB filter
            // set for line ratios). Hidden when the feature is already on.
            _ContextualOffers(
              colors: colors,
              sessionConfig: sessionConfig,
              onEnableMovingObjects: () => _updateSessionConfig(
                ref,
                sessionConfig.copyWith(movingObjectsEnabled: true),
              ),
              onEnableNarrowband: () => _updateSessionConfig(
                ref,
                sessionConfig.copyWith(narrowbandEnabled: true),
              ),
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
            // P3.2: transparency unlock progress — surfaces the
            // "N more calibrated frames" hint directly in the HUD so the
            // user understands why the transparency reading is blank.
            if (sessionConfig.transparencyEnabled)
              _TransparencyUnlockProgress(colors: colors),
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
                fontSize: NightshadeTypography.fontSize11,
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
                fontSize: NightshadeTypography.fontSize11,
              ),
            ),
            const SizedBox(height: 6),
            if (selectedObject != null)
              Text(
                'Selected: ${selectedObject.commonName ?? selectedObject.name}',
                style: TextStyle(color: colors.textPrimary, fontSize: NightshadeTypography.fontSize11),
              )
            else
              Text(
                'Click an annotated object to select it.',
                style: TextStyle(color: colors.textMuted, fontSize: NightshadeTypography.fontSize11),
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
              style: TextStyle(color: colors.textMuted, fontSize: NightshadeTypography.fontSize10),
            ),
            Text(
              'Comparisons: ${comparisonAnchors.isEmpty ? 'auto' : comparisonAnchors.length}',
              style: TextStyle(color: colors.textMuted, fontSize: NightshadeTypography.fontSize10),
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
                fontSize: NightshadeTypography.fontSize11,
              ),
            ),
          ),
          NightshadeSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Contextual one-tap suggestions for the imaging HUD. Implements P3.1.
///
/// Two rules today:
///   * **Moving objects**: when the session has 3+ light frames in the same
///     filter we offer to enable moving-object mode, since the detector
///     needs multiple frames to work.
///   * **Narrowband ratios**: when the session contains at least one frame
///     in each of Ha / OIII / SII we offer to enable narrowband tools.
///
/// Both suggestions self-suppress as soon as the corresponding feature is
/// enabled, so they're informational nudges rather than recurring nags.
class _ContextualOffers extends ConsumerWidget {
  final NightshadeColors colors;
  final ScienceSessionConfig sessionConfig;
  final VoidCallback onEnableMovingObjects;
  final VoidCallback onEnableNarrowband;

  const _ContextualOffers({
    required this.colors,
    required this.sessionConfig,
    required this.onEnableMovingObjects,
    required this.onEnableNarrowband,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = ref.watch(sessionStateProvider).dbSessionId;
    if (sessionId == null) return const SizedBox.shrink();

    final imageStream = ref.watch(_huddedImagesProvider(sessionId));
    final images = imageStream.valueOrNull ?? const <DbCapturedImage>[];
    if (images.isEmpty) return const SizedBox.shrink();

    final lights = images
        .where((image) => image.frameType.toLowerCase() == 'light')
        .toList(growable: false);

    final filterCounts = <String, int>{};
    for (final image in lights) {
      final f = (image.filter ?? '').toUpperCase();
      if (f.isEmpty) continue;
      filterCounts[f] = (filterCounts[f] ?? 0) + 1;
    }

    final hasNarrowband = _hasFilter(filterCounts, ['HA', 'H-ALPHA']) &&
        _hasFilter(filterCounts, ['OIII', 'O3']) &&
        _hasFilter(filterCounts, ['SII', 'S2']);

    final tiles = <Widget>[];

    if (!sessionConfig.movingObjectsEnabled && lights.length >= 3) {
      tiles.add(_OfferTile(
        colors: colors,
        icon: LucideIcons.rocket,
        title: 'Enable moving-object detection?',
        body:
            'You have ${lights.length} light frames — enough for the detector to spot drifting candidates.',
        onAccept: onEnableMovingObjects,
      ));
    }

    if (!sessionConfig.narrowbandEnabled && hasNarrowband) {
      tiles.add(_OfferTile(
        colors: colors,
        icon: LucideIcons.slidersHorizontal,
        title: 'Enable narrowband ratios?',
        body:
            'Ha, OIII, and SII frames are all present — Nightshade can produce line ratios from this session.',
        onAccept: onEnableNarrowband,
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(children: tiles),
    );
  }

  bool _hasFilter(Map<String, int> counts, List<String> aliases) {
    for (final alias in aliases) {
      if ((counts[alias] ?? 0) > 0) return true;
    }
    return false;
  }
}

/// Internal family provider so the contextual offers widget only fetches the
/// session's image list once per session id change. Drift de-dupes parallel
/// watchers automatically.
final _huddedImagesProvider =
    StreamProvider.family<List<DbCapturedImage>, int>((ref, sessionId) {
  return ref.watch(imagesDaoProvider).watchImagesForSession(sessionId);
});

class _OfferTile extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onAccept;

  const _OfferTile({
    required this.colors,
    required this.icon,
    required this.title,
    required this.body,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: NightshadeDecorations.emphasisSurface(
          colors.info,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: colors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: NightshadeTypography.labelStrongSm.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: NightshadeTypography.fontSize10,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            NightshadeButton(
              onPressed: onAccept,
              label: 'Enable',
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny progress indicator that surfaces how many more calibrated frames are
/// needed before transparency estimates stabilise. Implements P3.2.
class _TransparencyUnlockProgress extends ConsumerWidget {
  final NightshadeColors colors;

  const _TransparencyUnlockProgress({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = ref.watch(sessionStateProvider).dbSessionId;
    if (sessionId == null) return const SizedBox.shrink();

    final calibrationRows =
        ref.watch(sessionFrameCalibrationsProvider(sessionId)).valueOrNull ??
            const <FramePhotometricCalibrationRow>[];
    final transparency = ref
            .watch(sessionTransparencySamplesProvider(sessionId))
            .valueOrNull ??
        const <TransparencySampleRow>[];
    if (transparency.isNotEmpty) return const SizedBox.shrink();

    final calibrated =
        calibrationRows.where((row) => row.isCalibrated).length;
    const target = ScienceInsightsEngine.minCalibratedForTransparency;
    if (calibrated >= target) return const SizedBox.shrink();
    final ratio = (calibrated / target).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.cloud, size: 11, color: colors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Transparency unlocks at $calibrated / $target calibrated frames',
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: NightshadeTypography.fontSize10,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              backgroundColor: colors.surfaceAlt,
              valueColor:
                  AlwaysStoppedAnimation<Color>(colors.info.withValues(alpha: 0.8)),
            ),
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
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: active
            ? NightshadeDecorations.selectedSurface(
                colors.primary,
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
                fillAlpha: 0.2,
              )
            : BoxDecoration(
                color: colors.surfaceAlt,
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
              ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? colors.primary : colors.textSecondary,
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
