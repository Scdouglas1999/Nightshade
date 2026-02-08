import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../utils/snackbar_helper.dart';

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
  CenteringResult? _result;
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
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: _isCentering || _result != null ? 900 : 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(theme, colorScheme),
            const SizedBox(height: 16),

            // Main content area
            if (_isCentering || _result != null || centeringStatus.iterationHistory.isNotEmpty)
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Image preview
                    if (currentImage != null && (_isCentering || _result != null))
                      Expanded(
                        flex: 1,
                        child: _buildImagePreview(currentImage, colorScheme, theme),
                      ),
                    if (currentImage != null && (_isCentering || _result != null))
                      const SizedBox(width: 16),

                    // Right: Status and info
                    Expanded(
                      flex: 1,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Coordinates
                            if (widget.targetRa != null && widget.targetDec != null)
                              _buildCoordinatesCompact(centeringStatus, colorScheme, theme),

                            if (widget.targetRa != null && widget.targetDec != null)
                              const SizedBox(height: 12),

                            // Exposure settings
                            _buildExposureSettings(colorScheme, theme),
                            const SizedBox(height: 12),

                            // Status section
                            if (_isCentering)
                              _buildStatusSection(centeringStatus, colorScheme),

                            // Result section
                            if (_result != null && !_isCentering)
                              _buildResultSection(_result!, colorScheme),

                            // Iteration history
                            if (centeringStatus.iterationHistory.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              _buildIterationHistory(centeringStatus.iterationHistory, colorScheme),
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
                _buildCoordinatesCompact(centeringStatus, colorScheme, theme),
                const SizedBox(height: 16),
              ],
              _buildExposureSettings(colorScheme, theme),
            ],

            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isCentering) ...[
                  NightshadeButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    variant: ButtonVariant.outline,
                  ),
                  const SizedBox(width: 12),
                ],
                NightshadeButton(
                  label: _isCentering ? 'Centering...' : 'Start Centering',
                  icon: _isCentering ? LucideIcons.loader2 : LucideIcons.target,
                  onPressed: _isCentering ? null : _startCentering,
                  isLoading: _isCentering,
                  variant: ButtonVariant.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(
          LucideIcons.target,
          color: colorScheme.primary,
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
                ),
              ),
              if (widget.targetName != null)
                Text(
                  widget.targetName!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: _isCentering ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildImagePreview(CapturedImageData imageData, ColorScheme colorScheme, ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
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
                  color: colorScheme.primary.withValues(alpha: 0.5),
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
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${imageData.width}x${imageData.height}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
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

  Widget _buildCoordinatesCompact(CenteringStatus status, ColorScheme colorScheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.3),
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
                  LucideIcons.compass,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCoordInfo(
                  'Target Dec',
                  _formatDec(widget.targetDec!),
                  LucideIcons.moveVertical,
                ),
              ),
            ],
          ),
          if (status.solvedRa != null && status.solvedDec != null) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: colorScheme.outline.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildCoordInfo(
                    'Solved RA',
                    _formatRa(status.solvedRa!),
                    LucideIcons.sparkles,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCoordInfo(
                    'Solved Dec',
                    _formatDec(status.solvedDec!),
                    LucideIcons.sparkles,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExposureSettings(ColorScheme colorScheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.camera, size: 16, color: colorScheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Text(
            'Solve exposure:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            height: 32,
            child: TextField(
              controller: _exposureController,
              enabled: !_isCentering,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: colorScheme.primary),
                ),
                filled: true,
                fillColor: colorScheme.surface,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            's',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordInfo(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
            ),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusSection(CenteringStatus status, ColorScheme colorScheme) {
    final theme = Theme.of(context);

    String stateText;
    IconData stateIcon;
    Color stateColor;

    switch (status.state) {
      case CenteringState.exposing:
        stateText = 'Capturing...';
        stateIcon = LucideIcons.camera;
        stateColor = colorScheme.primary;
        break;
      case CenteringState.solving:
        stateText = 'Plate solving...';
        stateIcon = LucideIcons.sparkles;
        stateColor = colorScheme.primary;
        break;
      case CenteringState.slewing:
        stateText = 'Correcting...';
        stateIcon = LucideIcons.moveHorizontal;
        stateColor = colorScheme.primary;
        break;
      case CenteringState.verifying:
        stateText = 'Verifying...';
        stateIcon = LucideIcons.checkCircle;
        stateColor = colorScheme.primary;
        break;
      case CenteringState.completed:
        stateText = 'Centered!';
        stateIcon = LucideIcons.checkCircle;
        stateColor = colorScheme.tertiary;
        break;
      case CenteringState.error:
        stateText = 'Error';
        stateIcon = LucideIcons.alertCircle;
        stateColor = colorScheme.error;
        break;
      default:
        stateText = 'Ready';
        stateIcon = LucideIcons.circle;
        stateColor = colorScheme.onSurface.withValues(alpha: 0.5);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: stateColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: stateColor.withValues(alpha: 0.3),
        ),
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
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
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
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (status.currentOffsetArcsec! / _centeringConfig.toleranceArcsec).clamp(0.0, 2.0) / 2.0,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: status.currentOffsetArcsec! <= _centeringConfig.toleranceArcsec
                          ? colorScheme.tertiary
                          : colorScheme.primary,
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
                    color: status.currentOffsetArcsec! <= _centeringConfig.toleranceArcsec
                        ? colorScheme.tertiary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultSection(CenteringResult result, ColorScheme colorScheme) {
    final theme = Theme.of(context);
    final isSuccess = result.success;
    final icon = isSuccess ? LucideIcons.checkCircle : LucideIcons.xCircle;
    final color = isSuccess ? colorScheme.tertiary : colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
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
              style: theme.textTheme.bodySmall,
            ),
          if (!isSuccess && result.errorMessage != null)
            Text(
              result.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          Text(
            '${result.iterations} iteration${result.iterations != 1 ? 's' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIterationHistory(List<CenteringIteration> history, ColorScheme colorScheme) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Iterations',
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 6),
        ...history.map((iter) {
          final isSuccess = iter.plateSolveSuccess;
          final color = isSuccess ? colorScheme.tertiary : colorScheme.error;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${iter.iterationNumber}',
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
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
                  Icon(LucideIcons.checkCircle, size: 14, color: color),
                if (!isSuccess)
                  Icon(LucideIcons.xCircle, size: 14, color: color),
              ],
            ),
          );
        }),
      ],
    );
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
    });

    final centeringService = ref.read(centeringServiceProvider);

    final appSettings = ref.read(appSettingsProvider).value;
    final executablePath = await PlateSolverUtils.findAstapExecutable(appSettings?.astapPath);

    final solverConfig = PlateSolverConfig(
      type: PlateSolverType.astap,
      executablePath: executablePath ?? '',
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

/// Efficiently renders RGBA image data without zoom/pan (simple fit display)
class _CenteringImageWidget extends StatefulWidget {
  final Uint8List imageData;
  final int width;
  final int height;

  const _CenteringImageWidget({
    required this.imageData,
    required this.width,
    required this.height,
  });

  @override
  State<_CenteringImageWidget> createState() => _CenteringImageWidgetState();
}

class _CenteringImageWidgetState extends State<_CenteringImageWidget> {
  ui.Image? _decodedImage;
  Uint8List? _lastData;

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  @override
  void didUpdateWidget(covariant _CenteringImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.imageData, _lastData)) {
      _decodeImage();
    }
  }

  Future<void> _decodeImage() async {
    _lastData = widget.imageData;
    try {
      final completer = ui.ImmutableBuffer.fromUint8List(widget.imageData);
      final buffer = await completer;
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: widget.width,
        height: widget.height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decodedImage?.dispose();
          _decodedImage = frame.image;
        });
      }
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    } catch (_) {
      // Decode failed silently
    }
  }

  @override
  void dispose() {
    _decodedImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_decodedImage == null) {
      return const SizedBox(
        width: 200,
        height: 200,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return RawImage(
      image: _decodedImage,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Crosshair overlay painter for centering image
class _CrosshairPainter extends CustomPainter {
  final Color color;

  _CrosshairPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Horizontal line
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), paint);
    // Vertical line
    canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), paint);

    // Center circle
    canvas.drawCircle(Offset(cx, cy), 20, paint);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.color != color;
}
