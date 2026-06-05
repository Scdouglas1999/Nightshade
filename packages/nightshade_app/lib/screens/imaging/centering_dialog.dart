import 'dart:developer' as developer;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../utils/snackbar_helper.dart';
import '../../widgets/plate_solver_required_banner.dart';

part 'centering_dialog/image_canvas.dart';

/// Dialog for automated target centering with live image preview
class CenteringDialog extends ConsumerStatefulWidget {
  final double? targetRa;
  final double? targetDec;
  final String? targetName;

  const CenteringDialog({
    super.key,
    this.targetRa,
    this.targetDec,
    this.targetName,
  });

  @override
  ConsumerState<CenteringDialog> createState() => _CenteringDialogState();
}

class _CenteringDialogState extends ConsumerState<CenteringDialog> {
  bool _isCentering = false;
  // Latched while CenteringService.stop() is in flight so the user can't
  // double-click Abort and queue up two abortMountSlew calls.
  bool _abortInFlight = false;
  CenteringResult? _result;
  // Set when `_startCentering` detects no plate solver is configured.
  // Drives the inline `PlateSolverRequiredBanner` — the centering dialog
  // catches `SolverNotAvailableError` from `PlateSolveService` rather than
  // letting it surface as a generic snackbar.
  String? _solverMissingMessage;
  late final TextEditingController _exposureController;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(activeEquipmentProfileProvider);
    final defaultExposure = profile?.defaultCenteringExposure ?? 5.0;
    _exposureController = TextEditingController(
      text: defaultExposure.toString(),
    );
  }

  @override
  void dispose() {
    _exposureController.dispose();
    super.dispose();
  }

  CenteringConfig get _centeringConfig {
    final exposureTime = double.tryParse(_exposureController.text) ?? 5.0;
    final profile = ref.read(activeEquipmentProfileProvider);
    return CenteringConfig(
      maxIterations: 5,
      toleranceArcsec: 30.0,
      exposureTime: exposureTime > 0 ? exposureTime : 5.0,
      binning: profile?.defaultBinX ?? 2,
      gain: profile?.defaultGain ?? 100,
      syncMount: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final centeringStatus = ref.watch(centeringStatusProvider);
    final currentImage = ref.watch(currentImageProvider);
    final theme = Theme.of(context);
    final colors = context.nightshadeColors;

    // Block back-button / Escape dismissal mid-run; the only sanctioned exit
    // while centering is the Abort button, which also stops the service.
    final isWideLayout = _isCentering ||
        _result != null ||
        centeringStatus.iterationHistory.isNotEmpty;

    return PopScope(
      canPop: !_isCentering,
      child: Dialog(
        child: ConstrainedBox(
          constraints: Responsive.dialogConstraints(
            context,
            preferredWidth: isWideLayout ? 900 : 600,
            maxWidthPercent: 0.95,
            maxHeightPercent: 0.85,
            minWidth: 320,
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                _buildHeader(theme, colors),
                const SizedBox(height: 16),

                // Plate-solver missing banner (W6-SOLVER-UX §6.1). Surfaced
                // when `_startCentering` catches `SolverNotAvailableError`
                // before kicking off the centering loop. The banner exposes
                // a "Set up plate solver" CTA that go_routes to
                // /settings/plate-solving — clicking it pops this dialog and
                // hands the user off to the dedicated setup page.
                if (_solverMissingMessage != null) ...[
                  PlateSolverRequiredBanner(
                    contextMessage: _solverMissingMessage,
                  ),
                  const SizedBox(height: 16),
                ],

                // Main content area
                if (_isCentering ||
                    _result != null ||
                    centeringStatus.iterationHistory.isNotEmpty)
                  Flexible(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Image preview
                        if (currentImage != null &&
                            (_isCentering || _result != null))
                          Expanded(
                            flex: 1,
                            child:
                                _buildImagePreview(currentImage, colors, theme),
                          ),
                        if (currentImage != null &&
                            (_isCentering || _result != null))
                          const SizedBox(width: 16),

                        // Right: Status and info
                        Expanded(
                          flex: 1,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Coordinates
                                if (widget.targetRa != null &&
                                    widget.targetDec != null)
                                  _buildCoordinatesCompact(
                                      centeringStatus, colors, theme),

                                if (widget.targetRa != null &&
                                    widget.targetDec != null)
                                  const SizedBox(height: 12),

                                // Exposure settings
                                _buildExposureSettings(colors, theme),
                                const SizedBox(height: 12),

                                // Status section
                                if (_isCentering)
                                  _buildStatusSection(centeringStatus, colors),

                                // Result section
                                if (_result != null && !_isCentering)
                                  _buildResultSection(_result!, colors),

                                // Iteration history
                                if (centeringStatus
                                    .iterationHistory.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _buildIterationHistory(
                                      centeringStatus.iterationHistory, colors),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  // Pre-centering: simple vertical layout
                  if (widget.targetRa != null && widget.targetDec != null) ...[
                    _buildCoordinatesCompact(centeringStatus, colors, theme),
                    const SizedBox(height: 16),
                  ],
                  _buildExposureSettings(colors, theme),
                ],

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_isCentering)
                      NightshadeButton(
                        label: 'Abort',
                        icon: LucideIcons.octagon,
                        onPressed: _abortInFlight ? null : _abortCentering,
                        isLoading: _abortInFlight,
                        variant: ButtonVariant.destructive,
                      )
                    else ...[
                      NightshadeButton(
                        label: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        variant: ButtonVariant.outline,
                      ),
                      const SizedBox(width: 12),
                      NightshadeButton(
                        label: 'Start Centering',
                        icon: NightshadeIcons.target,
                        onPressed: _startCentering,
                        variant: ButtonVariant.primary,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, NightshadeColors colors) {
    return Row(
      children: [
        Icon(
          NightshadeIcons.target,
          color: colors.accent,
          size: 28,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Target Centering',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              if (widget.targetName != null)
                Text(
                  widget.targetName!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        // Footer Abort/Close handles dismissal; the header X used to be the
        // *only* exit but was disabled mid-run, trapping users. Drop it.
      ],
    );
  }

  Widget _buildImagePreview(
    CapturedImageData imageData,
    NightshadeColors colors,
    ThemeData theme,
  ) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: clampPanelWidth(
          MediaQuery.sizeOf(context).height,
          fraction: 0.45,
          min: 200,
          max: 400,
        ),
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(
          color: colors.border,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusButton),
        child: Stack(
          children: [
            // Image
            Center(
              child: _CenteringImageWidget(
                imageData: imageData.displayData,
                width: imageData.width,
                height: imageData.height,
              ),
            ),

            // Crosshair overlay
            Positioned.fill(
              child: CustomPaint(
                painter: _CrosshairPainter(
                  color: colors.accent.withValues(alpha: 0.5),
                ),
              ),
            ),

            // Image info badge
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  // absolute: HUD badge scrim over the preview image canvas
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                ),
                child: Text(
                  '${imageData.width}x${imageData.height}',
                  style: const TextStyle(
                    // absolute: HUD label over the preview image canvas
                    color: Colors.white70,
                    fontSize: NightshadeTypography.fontSize10,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordinatesCompact(
      CenteringStatus status, NightshadeColors colors, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(
          color: colors.border,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildCoordInfo(
                  'Target RA',
                  _formatRa(widget.targetRa!),
                  NightshadeIcons.compass,
                  colors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCoordInfo(
                  'Target Dec',
                  _formatDec(widget.targetDec!),
                  LucideIcons.moveVertical,
                  colors,
                ),
              ),
            ],
          ),
          if (status.solvedRa != null && status.solvedDec != null) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: colors.border),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildCoordInfo(
                    'Solved RA',
                    _formatRa(status.solvedRa!),
                    NightshadeIcons.sparkle,
                    colors,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCoordInfo(
                    'Solved Dec',
                    _formatDec(status.solvedDec!),
                    NightshadeIcons.sparkle,
                    colors,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExposureSettings(NightshadeColors colors, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(
          color: colors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(NightshadeIcons.camera, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Solve exposure:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            height: 32,
            child: TextField(
              controller: _exposureController,
              enabled: !_isCentering,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
                  borderSide: BorderSide(color: colors.accent),
                ),
                filled: true,
                fillColor: colors.surface,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            's',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordInfo(
    String label,
    String value,
    IconData icon,
    NightshadeColors colors,
  ) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.accent),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: NightshadeTypography.fontSize10,
                color: colors.textSecondary,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusSection(CenteringStatus status, NightshadeColors colors) {
    final theme = Theme.of(context);

    String stateText;
    IconData stateIcon;
    Color stateColor;

    switch (status.state) {
      case CenteringState.exposing:
        stateText = 'Capturing...';
        stateIcon = NightshadeIcons.camera;
        stateColor = colors.accent;
        break;
      case CenteringState.solving:
        stateText = 'Plate solving...';
        stateIcon = NightshadeIcons.sparkle;
        stateColor = colors.accent;
        break;
      case CenteringState.slewing:
        stateText = 'Correcting...';
        stateIcon = LucideIcons.moveHorizontal;
        stateColor = colors.accent;
        break;
      case CenteringState.verifying:
        stateText = 'Verifying...';
        stateIcon = NightshadeIcons.success;
        stateColor = colors.accent;
        break;
      case CenteringState.completed:
        stateText = 'Centered!';
        stateIcon = NightshadeIcons.success;
        stateColor = colors.success;
        break;
      case CenteringState.error:
        stateText = 'Error';
        stateIcon = LucideIcons.alertCircle;
        stateColor = colors.error;
        break;
      default:
        stateText = 'Ready';
        stateIcon = NightshadeIcons.circle;
        stateColor = colors.textMuted;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: NightshadeDecorations.statusChip(
        stateColor,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(stateIcon, color: stateColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  stateText,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: stateColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${status.currentIteration}/${status.maxIterations}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (status.currentOffsetArcmin != null) ...[
            const SizedBox(height: 8),
            // Offset bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
                    child: LinearProgressIndicator(
                      value: (status.currentOffsetArcsec! /
                                  _centeringConfig.toleranceArcsec)
                              .clamp(0.0, 2.0) /
                          2.0,
                      backgroundColor: colors.surfaceAlt,
                      color: status.currentOffsetArcsec! <=
                              _centeringConfig.toleranceArcsec
                          ? colors.success
                          : colors.accent,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${status.currentOffsetArcmin!.toStringAsFixed(2)}\'',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFeatures: [const FontFeature.tabularFigures()],
                    color: status.currentOffsetArcsec! <=
                            _centeringConfig.toleranceArcsec
                        ? colors.success
                        : colors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultSection(CenteringResult result, NightshadeColors colors) {
    final theme = Theme.of(context);
    final isSuccess = result.success;
    final icon = isSuccess ? NightshadeIcons.success : NightshadeIcons.error;
    final color = isSuccess ? colors.success : colors.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: NightshadeDecorations.statusChip(
        color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSuccess ? 'Centered!' : 'Centering Failed',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isSuccess && result.finalOffsetArcsec != null)
            Text(
              'Final offset: ${(result.finalOffsetArcsec! / 60.0).toStringAsFixed(2)}\' (${result.finalOffsetArcsec!.toStringAsFixed(1)}")',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.textPrimary,
              ),
            ),
          if (!isSuccess && result.errorMessage != null)
            Text(
              result.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          Text(
            '${result.iterations} iteration${result.iterations != 1 ? 's' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIterationHistory(
      List<CenteringIteration> history, NightshadeColors colors) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Iterations',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        ...history.map((iter) {
          final isSuccess = iter.plateSolveSuccess;
          final color = isSuccess ? colors.success : colors.error;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: NightshadeDecorations.tintedBadge(
                    color,
                    borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline11),
                  ),
                  child: Center(
                    child: Text(
                      '${iter.iterationNumber}',
                      style: TextStyle(
                        color: color,
                        fontSize: NightshadeTypography.fontSize11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: isSuccess
                      ? Text(
                          '${iter.offsetArcmin?.toStringAsFixed(2) ?? '?'}\' offset',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.textPrimary,
                            fontFeatures: [const FontFeature.tabularFigures()],
                          ),
                        )
                      : Text(
                          iter.errorMessage ?? 'Failed',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                if (isSuccess)
                  Icon(NightshadeIcons.success, size: 14, color: color),
                if (!isSuccess)
                  Icon(NightshadeIcons.error, size: 14, color: color),
              ],
            ),
          );
        }),
      ],
    );
  }

  // Abort path: latch _abortInFlight so the button disables immediately and
  // a second tap can't queue a duplicate stop() (which would also issue a
  // duplicate abortMountSlew). The centering loop's own _abortRequested
  // poll surfaces the cancellation as a CenteringResult.failure('Aborted by
  // user'), which _startCentering's normal completion path renders.
  Future<void> _abortCentering() async {
    setState(() => _abortInFlight = true);
    try {
      await ref.read(centeringServiceProvider).stop();
    } catch (e) {
      // Surface the failure rather than swallow it: per CLAUDE.md a silent
      // abort failure could leave the mount slewing after the user thinks
      // they aborted.
      if (mounted) {
        context.showErrorSnackBar('Abort failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _abortInFlight = false);
      }
    }
  }

  Future<void> _startCentering() async {
    if (widget.targetRa == null || widget.targetDec == null) {
      if (mounted) {
        context.showErrorSnackBar('No target coordinates specified');
      }
      return;
    }

    setState(() {
      _isCentering = true;
      _result = null;
      _solverMissingMessage = null;
    });

    final centeringService = ref.read(centeringServiceProvider);

    // Pre-flight: probe disk for ASTAP / Astrometry.net before spinning up
    // the centering loop. If neither is reachable, surface the
    // `PlateSolverRequiredBanner` and bail out — letting CenteringService
    // discover this later wastes one full exposure and produces a generic
    // "ASTAP not found" error that doesn't point users at the setup page.
    final solveService = ref.read(plateSolveServiceProvider);
    final PlateSolverDetection detection;
    try {
      detection = await solveService.detect();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCentering = false;
          _solverMissingMessage = 'Plate-solver detection failed: $e';
        });
      }
      return;
    }

    if (!detection.hasAnySolver) {
      if (mounted) {
        setState(() {
          _isCentering = false;
          _solverMissingMessage =
              'Centering needs ASTAP (or Astrometry.net) installed to '
              'compare the captured frame to the target coordinates. '
              'Configure one to continue.';
        });
      }
      return;
    }

    final appSettings = ref.read(appSettingsProvider).value;
    // Prefer the freshly-detected ASTAP path (which honours the new
    // platesolver.json override) over the legacy appSettings field. Fall
    // back to legacy + auto-detect if the new layer says nothing.
    final executablePath = detection.astapPath ??
        await PlateSolverUtils.findAstapExecutable(appSettings?.astapPath);

    if (executablePath == null || executablePath.isEmpty) {
      if (mounted) {
        setState(() {
          _isCentering = false;
          _solverMissingMessage =
              'ASTAP path is empty even though detection ran. Configure '
              'the ASTAP executable in Settings → Plate Solving.';
        });
      }
      return;
    }

    final solverConfig = PlateSolverConfig(
      type: PlateSolverType.astap,
      executablePath: executablePath,
      catalogPath: detection.catalogPath,
      timeoutSeconds: 60,
      searchRadius: 30.0,
    );

    try {
      final result = await centeringService.centerOnTarget(
        targetRa: widget.targetRa!,
        targetDec: widget.targetDec!,
        solverConfig: solverConfig,
        config: _centeringConfig,
        onStatusUpdate: (status) {
          ref.read(centeringStatusProvider.notifier).state = status;
        },
      );

      if (mounted) {
        setState(() {
          _result = result;
          _isCentering = false;
        });

        ref.read(lastCenteringResultProvider.notifier).state = result;
      }
    } on SolverNotAvailableError catch (e) {
      // Path the centering service can throw if a deeper layer surfaces
      // the missing-solver case after we already passed our pre-flight.
      // Render the same banner rather than a generic snackbar.
      if (mounted) {
        setState(() {
          _isCentering = false;
          _solverMissingMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = CenteringResult.failure(
            errorMessage: 'Centering error: $e',
            iterations: 0,
            iterationHistory: [],
          );
          _isCentering = false;
        });

        context.showErrorSnackBar('Centering failed: $e');
      }
    }
  }

  String _formatRa(double raHours) {
    final hours = raHours.floor();
    final minutes = ((raHours - hours) * 60).floor();
    final seconds = ((raHours - hours - minutes / 60) * 3600);
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toStringAsFixed(1).padLeft(4, '0')}s';
  }

  String _formatDec(double decDegrees) {
    final sign = decDegrees >= 0 ? '+' : '-';
    final absDec = decDegrees.abs();
    final degrees = absDec.floor();
    final minutes = ((absDec - degrees) * 60).floor();
    final seconds = ((absDec - degrees - minutes / 60) * 3600);
    return '$sign${degrees.toString().padLeft(2, '0')}° ${minutes.toString().padLeft(2, '0')}\' ${seconds.toStringAsFixed(1).padLeft(4, '0')}"';
  }
}
