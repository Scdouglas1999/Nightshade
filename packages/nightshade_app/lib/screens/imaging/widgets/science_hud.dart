import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../analytics/widgets/science_status_banner.dart';
import '../imaging_science_state.dart';

part 'science_hud_parts/_offers_and_chips.dart';

class ScienceHudPanel extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const ScienceHudPanel({super.key, required this.colors});

  @override
  ConsumerState<ScienceHudPanel> createState() => _ScienceHudPanelState();
}

class _ScienceHudPanelState extends ConsumerState<ScienceHudPanel> {
  bool _isSavingSessionConfig = false;
  bool _isSavingSelection = false;
  int _authorityGeneration = 0;
  int _configOperationGeneration = 0;
  int _selectionOperationGeneration = 0;
  ProviderSubscription<NightshadeBackend>? _backendSubscription;
  ProviderSubscription<SessionState>? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    _backendSubscription = ref.listenManual<NightshadeBackend>(
      backendProvider,
      (previous, next) {
        if (previous != null && !identical(previous, next)) {
          _retireHostOperations();
        }
      },
    );
    _sessionSubscription = ref.listenManual<SessionState>(
      sessionStateProvider,
      (previous, next) {
        if (previous?.dbSessionId != next.dbSessionId) {
          _retireHostOperations();
        }
      },
    );
  }

  @override
  void dispose() {
    _authorityGeneration++;
    _configOperationGeneration++;
    _selectionOperationGeneration++;
    _backendSubscription?.close();
    _sessionSubscription?.close();
    super.dispose();
  }

  void _retireHostOperations() {
    _authorityGeneration++;
    _configOperationGeneration++;
    _selectionOperationGeneration++;
    if (mounted && (_isSavingSessionConfig || _isSavingSelection)) {
      setState(() {
        _isSavingSessionConfig = false;
        _isSavingSelection = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final overlayState = ref.watch(scienceOverlayStateProvider);
    final settingsAsync = ref.watch(scienceSettingsProvider);
    final selectionAsync = ref.watch(sciencePhotometrySelectionProvider);
    final sessionConfigAsync = ref.watch(activeScienceSessionConfigProvider);
    final settings = settingsAsync.valueOrNull ?? const ScienceSettings();
    final photometrySelection =
        selectionAsync.valueOrNull ?? const SciencePhotometrySelection();
    final sessionConfig =
        sessionConfigAsync.valueOrNull ?? const ScienceSessionConfig();
    final sessionId = ref.watch(sessionStateProvider).dbSessionId;
    final hasSession = sessionId != null;
    final settingsReady = settingsAsync.hasValue &&
        !settingsAsync.isLoading &&
        !settingsAsync.hasError;
    final selectionReady = selectionAsync.hasValue &&
        !selectionAsync.isLoading &&
        !selectionAsync.hasError;
    final sessionConfigReady = hasSession &&
        sessionConfigAsync.hasValue &&
        !sessionConfigAsync.isLoading &&
        !sessionConfigAsync.hasError;
    final configControlsEnabled = sessionConfigReady && !_isSavingSessionConfig;
    final authoritySources = <AsyncValue<Object?>>[
      settingsAsync,
      selectionAsync,
      if (hasSession) sessionConfigAsync,
    ];
    final authorityErrors = authoritySources
        .where((source) => source.hasError && source.error != null)
        .map((source) => source.error!)
        .toList(growable: false);
    final authorityLoading = authoritySources.any(
      (source) => source.isLoading || (!source.hasValue && !source.hasError),
    );
    final selectedObject = ref.watch(selectedAnnotationObjectProvider);
    final photometryTarget = photometrySelection.target;
    final comparisonAnchors = photometrySelection.comparisons;

    return NightshadeCard(
      backgroundColor: colors.surface,
      borderRadius: NightshadeTokens.radiusLg,
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.science, size: 15, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'Science HUD',
                style: NightshadeTypography.labelStrong
                    .copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              Text(
                'Live session controls',
                style: NightshadeTypography.captionSm
                    .copyWith(color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          InkWell(
            onTap: () => context.go('/science'),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Open in Science analytics',
                    style: NightshadeTypography.labelSm.copyWith(
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceXs),
                  Icon(LucideIcons.arrowRight,
                      size: NightshadeTokens.iconXs, color: colors.primary),
                ],
              ),
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          // P0.2: status banner — collapses to a single line when there is
          // nothing in flight, expands when science is working. Hidden
          // entirely if the pipeline is idle AND empty.
          const ScienceStatusBanner(hideWhenIdle: true),
          const SizedBox(height: NightshadeTokens.spaceSm),
          if (authorityErrors.isNotEmpty) ...[
            _ScienceHudAuthorityNotice(
              colors: colors,
              error: authorityErrors.first,
              additionalErrorCount: authorityErrors.length - 1,
              onRetry: () => _retryAuthorities(sessionId),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
          ] else if (authorityLoading) ...[
            LinearProgressIndicator(
              minHeight: 2,
              color: colors.primary,
              backgroundColor: colors.border,
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
          ],
          if (!hasSession)
            Padding(
              padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
              child: Text(
                'Science features attach to a capture session. Start or open a '
                'session to configure them.',
                style: NightshadeTypography.captionSm
                    .copyWith(color: colors.textMuted),
              ),
            ),
          _FeatureToggle(
            colors: colors,
            enabled: configControlsEnabled,
            title: 'Moving object mode',
            value: sessionConfig.movingObjectsEnabled,
            onChanged: (value) {
              unawaited(
                _saveSessionConfig(
                  sessionConfig.copyWith(movingObjectsEnabled: value),
                  movingObjectModeEnabled: value,
                ),
              );
            },
          ),
          // P3.1: contextual suggestions. Watches the current session's
          // image list and offers one-tap enable for features the user
          // looks ready for (multi-frame for moving objects, NB filter
          // set for line ratios). Hidden when the feature is already on.
          if (sessionConfigReady)
            _ContextualOffers(
              colors: colors,
              sessionConfig: sessionConfig,
              actionsEnabled: !_isSavingSessionConfig,
              onEnableMovingObjects: () => unawaited(
                _saveSessionConfig(
                  sessionConfig.copyWith(movingObjectsEnabled: true),
                  movingObjectModeEnabled: true,
                ),
              ),
              onEnableNarrowband: () => unawaited(
                _saveSessionConfig(
                  sessionConfig.copyWith(narrowbandEnabled: true),
                ),
              ),
            ),
          _FeatureToggle(
            colors: colors,
            enabled: configControlsEnabled,
            title: 'Session photometry',
            value: sessionConfig.photometryEnabled,
            onChanged: (value) => unawaited(
              _saveSessionConfig(
                sessionConfig.copyWith(photometryEnabled: value),
              ),
            ),
          ),
          _FeatureToggle(
            colors: colors,
            enabled: configControlsEnabled,
            title: 'Photometric calibration',
            value: sessionConfig.calibrationEnabled,
            onChanged: (value) => unawaited(
              _saveSessionConfig(
                sessionConfig.copyWith(calibrationEnabled: value),
              ),
            ),
          ),
          _FeatureToggle(
            colors: colors,
            enabled: configControlsEnabled,
            title: 'Transparency model',
            value: sessionConfig.transparencyEnabled,
            onChanged: (value) => unawaited(
              _saveSessionConfig(
                sessionConfig.copyWith(transparencyEnabled: value),
              ),
            ),
          ),
          // P3.2: transparency unlock progress — surfaces the
          // "N more calibrated frames" hint directly in the HUD so the
          // user understands why the transparency reading is blank.
          if (sessionConfigReady && sessionConfig.transparencyEnabled)
            _TransparencyUnlockProgress(colors: colors),
          _FeatureToggle(
            colors: colors,
            enabled: configControlsEnabled,
            title: 'PSF map',
            value: sessionConfig.psfMapEnabled,
            onChanged: (value) => unawaited(
              _saveSessionConfig(
                sessionConfig.copyWith(psfMapEnabled: value),
              ),
            ),
          ),
          _FeatureToggle(
            colors: colors,
            enabled: configControlsEnabled,
            title: 'Astrometric residuals',
            value: sessionConfig.residualsEnabled,
            onChanged: (value) => unawaited(
              _saveSessionConfig(
                sessionConfig.copyWith(residualsEnabled: value),
              ),
            ),
          ),
          _FeatureToggle(
            colors: colors,
            enabled: configControlsEnabled,
            title: 'Narrowband tools',
            value: sessionConfig.narrowbandEnabled,
            onChanged: (value) => unawaited(
              _saveSessionConfig(
                sessionConfig.copyWith(narrowbandEnabled: value),
              ),
            ),
          ),
          const Divider(height: 18),
          Text(
            'Overlay layers',
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
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
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 6),
          if (selectedObject != null)
            Text(
              'Selected: ${selectedObject.commonName ?? selectedObject.name}',
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.textPrimary),
            )
          else
            Text(
              'Click an annotated object to select it.',
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.textMuted),
            ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          Row(
            children: [
              Expanded(
                child: NightshadeButton(
                  onPressed: selectedObject == null ||
                          !selectionReady ||
                          _isSavingSelection
                      ? null
                      : () {
                          unawaited(
                            _runSelectionAction(
                              () => ref
                                  .read(sciencePhotometrySelectionProvider
                                      .notifier)
                                  .setTarget(
                                    PhotometryAnchor(
                                      objectId: selectedObject.id,
                                      label: selectedObject.commonName ??
                                          selectedObject.name,
                                      raDegrees: selectedObject.ra,
                                      decDegrees: selectedObject.dec,
                                    ),
                                  ),
                            ),
                          );
                        },
                  label: 'Set Target',
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: NightshadeButton(
                  onPressed: selectedObject == null ||
                          !selectionReady ||
                          _isSavingSelection
                      ? null
                      : () {
                          unawaited(
                            _runSelectionAction(
                              () => ref
                                  .read(sciencePhotometrySelectionProvider
                                      .notifier)
                                  .toggleComparison(
                                    PhotometryAnchor(
                                      objectId: selectedObject.id,
                                      label: selectedObject.commonName ??
                                          selectedObject.name,
                                      raDegrees: selectedObject.ra,
                                      decDegrees: selectedObject.dec,
                                    ),
                                  ),
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
                  onPressed: !selectionReady ||
                          _isSavingSelection ||
                          photometryTarget == null
                      ? null
                      : () => unawaited(
                            _runSelectionAction(
                              () => ref
                                  .read(sciencePhotometrySelectionProvider
                                      .notifier)
                                  .setTarget(null),
                            ),
                          ),
                  label: 'Clear Target',
                  variant: ButtonVariant.ghost,
                  size: ButtonSize.small,
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: NightshadeButton(
                  onPressed: !selectionReady ||
                          _isSavingSelection ||
                          comparisonAnchors.isEmpty
                      ? null
                      : () => unawaited(
                            _runSelectionAction(
                              () => ref
                                  .read(sciencePhotometrySelectionProvider
                                      .notifier)
                                  .clearComparisons(),
                            ),
                          ),
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
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textMuted),
          ),
          Text(
            'Comparisons: ${comparisonAnchors.isEmpty ? 'auto' : comparisonAnchors.length}',
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: NightshadeTokens.spaceSm),
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              onPressed: settingsReady &&
                      selectionReady &&
                      !_isSavingSelection &&
                      settings.photometryEnabled
                  ? () {
                      final nextEnabled =
                          !photometrySelection.differentialEnabled;
                      unawaited(
                        _runSelectionAction(
                          () => ref
                              .read(sciencePhotometrySelectionProvider.notifier)
                              .setDifferentialEnabled(nextEnabled),
                          onSuccess: () {
                            final currentMode =
                                ref.read(scienceModeStateProvider);
                            ref.read(scienceModeStateProvider.notifier).state =
                                currentMode.copyWith(
                              differentialPhotometryActive: nextEnabled,
                            );
                          },
                        ),
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
    );
  }

  Future<void> _saveSessionConfig(
    ScienceSessionConfig config, {
    bool? movingObjectModeEnabled,
  }) async {
    if (_isSavingSessionConfig) return;
    final sessionId = ref.read(sessionStateProvider).dbSessionId;
    if (sessionId == null) return;
    final backend = ref.read(backendProvider);
    final authorityGeneration = _authorityGeneration;
    final operationGeneration = ++_configOperationGeneration;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSavingSessionConfig = true);
    try {
      await ref
          .read(scienceSessionConfigControllerProvider)
          .save(sessionId, config);
      if (!_isCurrentConfigOperation(
        backend,
        sessionId,
        authorityGeneration,
        operationGeneration,
      )) {
        return;
      }
      ref.invalidate(scienceSessionConfigProvider(sessionId));
      ref.invalidate(activeScienceSessionConfigProvider);
      if (movingObjectModeEnabled != null) {
        final currentMode = ref.read(scienceModeStateProvider);
        ref.read(scienceModeStateProvider.notifier).state =
            currentMode.copyWith(
          movingObjectModeEnabled: movingObjectModeEnabled,
        );
      }
    } catch (error) {
      if (_isCurrentConfigOperation(
        backend,
        sessionId,
        authorityGeneration,
        operationGeneration,
      )) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save science session: $error')),
        );
      }
    } finally {
      if (_isCurrentConfigOperation(
        backend,
        sessionId,
        authorityGeneration,
        operationGeneration,
      )) {
        setState(() => _isSavingSessionConfig = false);
      }
    }
  }

  Future<void> _runSelectionAction(
    Future<void> Function() action, {
    VoidCallback? onSuccess,
  }) async {
    if (_isSavingSelection) return;
    final backend = ref.read(backendProvider);
    final sessionId = ref.read(sessionStateProvider).dbSessionId;
    final authorityGeneration = _authorityGeneration;
    final operationGeneration = ++_selectionOperationGeneration;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSavingSelection = true);
    try {
      await action();
      if (!_isCurrentSelectionOperation(
        backend,
        sessionId,
        authorityGeneration,
        operationGeneration,
      )) {
        return;
      }
      onSuccess?.call();
    } catch (error) {
      if (_isCurrentSelectionOperation(
        backend,
        sessionId,
        authorityGeneration,
        operationGeneration,
      )) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save photometry setup: $error')),
        );
      }
    } finally {
      if (_isCurrentSelectionOperation(
        backend,
        sessionId,
        authorityGeneration,
        operationGeneration,
      )) {
        setState(() => _isSavingSelection = false);
      }
    }
  }

  bool _isCurrentConfigOperation(
    NightshadeBackend backend,
    int sessionId,
    int authorityGeneration,
    int operationGeneration,
  ) {
    return mounted &&
        authorityGeneration == _authorityGeneration &&
        operationGeneration == _configOperationGeneration &&
        identical(ref.read(backendProvider), backend) &&
        ref.read(sessionStateProvider).dbSessionId == sessionId;
  }

  bool _isCurrentSelectionOperation(
    NightshadeBackend backend,
    int? sessionId,
    int authorityGeneration,
    int operationGeneration,
  ) {
    return mounted &&
        authorityGeneration == _authorityGeneration &&
        operationGeneration == _selectionOperationGeneration &&
        identical(ref.read(backendProvider), backend) &&
        ref.read(sessionStateProvider).dbSessionId == sessionId;
  }

  void _retryAuthorities(int? sessionId) {
    ref.invalidate(scienceSettingsProvider);
    ref.invalidate(sciencePhotometrySelectionProvider);
    if (sessionId != null) {
      ref.invalidate(scienceSessionConfigProvider(sessionId));
    }
    ref.invalidate(activeScienceSessionConfigProvider);
  }
}
