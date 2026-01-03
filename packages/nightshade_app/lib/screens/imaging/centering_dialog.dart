import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Dialog for automated target centering
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
  final _centeringConfig = const CenteringConfig(
    maxIterations: 5,
    toleranceArcsec: 30.0,
    exposureTime: 3.0,
    binning: 2,
    gain: 100,
    syncMount: false,
  );

  @override
  Widget build(BuildContext context) {
    final centeringStatus = ref.watch(centeringStatusProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
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
                            color: colorScheme.onSurface.withOpacity(0.7),
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
            ),
            const SizedBox(height: 24),

            // Target coordinates display
            if (widget.targetRa != null && widget.targetDec != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildCoordInfo(
                            'RA',
                            _formatRa(widget.targetRa!),
                            LucideIcons.compass,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildCoordInfo(
                            'Dec',
                            _formatDec(widget.targetDec!),
                            LucideIcons.moveVertical,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Status section
            if (_isCentering) ...[
              _buildStatusSection(centeringStatus, colorScheme),
              const SizedBox(height: 24),
            ],

            // Result section
            if (_result != null && !_isCentering) ...[
              _buildResultSection(_result!, colorScheme),
              const SizedBox(height: 24),
            ],

            // Iteration history
            if (centeringStatus.iterationHistory.isNotEmpty) ...[
              _buildIterationHistory(centeringStatus.iterationHistory, colorScheme),
              const SizedBox(height: 24),
            ],

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!_isCentering) ...[
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 12),
                ],
                FilledButton.icon(
                  onPressed: _isCentering ? null : _startCentering,
                  icon: Icon(
                    _isCentering ? LucideIcons.loader2 : LucideIcons.target,
                  ),
                  label: Text(_isCentering ? 'Centering...' : 'Start Centering'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoordInfo(String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall,
            ),
            Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(
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
        stateText = 'Taking image...';
        stateIcon = LucideIcons.camera;
        stateColor = colorScheme.primary;
        break;
      case CenteringState.solving:
        stateText = 'Plate solving...';
        stateIcon = LucideIcons.sparkles;
        stateColor = colorScheme.primary;
        break;
      case CenteringState.slewing:
        stateText = 'Slewing to target...';
        stateIcon = LucideIcons.moveHorizontal;
        stateColor = colorScheme.primary;
        break;
      case CenteringState.verifying:
        stateText = 'Verifying position...';
        stateIcon = LucideIcons.checkCircle;
        stateColor = colorScheme.primary;
        break;
      case CenteringState.completed:
        stateText = 'Completed!';
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
        stateColor = colorScheme.onSurface.withOpacity(0.5);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: stateColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: stateColor.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(stateIcon, color: stateColor, size: 20),
              const SizedBox(width: 8),
              Text(
                stateText,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: stateColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Iteration ${status.currentIteration}/${status.maxIterations}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
          if (status.message != null) ...[
            const SizedBox(height: 8),
            Text(
              status.message!,
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (status.currentOffsetArcmin != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: status.currentOffsetArcsec! / _centeringConfig.toleranceArcsec,
              backgroundColor: colorScheme.surfaceContainerHighest,
              color: status.currentOffsetArcsec! <= _centeringConfig.toleranceArcsec
                  ? colorScheme.tertiary
                  : colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Offset: ${status.currentOffsetArcmin!.toStringAsFixed(2)} arcmin',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  'Target: ${(_centeringConfig.toleranceArcsec / 60.0).toStringAsFixed(2)} arcmin',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isSuccess ? 'Target Centered Successfully!' : 'Centering Failed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isSuccess && result.finalOffsetArcsec != null)
            Text(
              'Final offset: ${(result.finalOffsetArcsec! / 60.0).toStringAsFixed(2)} arcmin (${result.finalOffsetArcsec!.toStringAsFixed(1)}")',
              style: theme.textTheme.bodyMedium,
            ),
          if (!isSuccess && result.errorMessage != null)
            Text(
              result.errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          const SizedBox(height: 8),
          Text(
            'Completed in ${result.iterations} iteration${result.iterations != 1 ? 's' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIterationHistory(List<CenteringIteration> history, ColorScheme colorScheme) {
    final theme = Theme.of(context);

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Iteration History',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(8),
              itemCount: history.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final iteration = history[index];
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: iteration.plateSolveSuccess
                        ? colorScheme.tertiary.withOpacity(0.2)
                        : colorScheme.error.withOpacity(0.2),
                    child: Text(
                      '${iteration.iterationNumber}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: iteration.plateSolveSuccess
                            ? colorScheme.tertiary
                            : colorScheme.error,
                      ),
                    ),
                  ),
                  title: iteration.plateSolveSuccess
                      ? Text(
                          'Offset: ${iteration.offsetArcmin?.toStringAsFixed(2) ?? '?'} arcmin',
                          style: theme.textTheme.bodyMedium,
                        )
                      : Text(
                          'Failed',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                  subtitle: iteration.errorMessage != null
                      ? Text(
                          iteration.errorMessage!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  trailing: iteration.plateSolveSuccess
                      ? Icon(
                          LucideIcons.checkCircle,
                          size: 16,
                          color: colorScheme.tertiary,
                        )
                      : Icon(
                          LucideIcons.xCircle,
                          size: 16,
                          color: colorScheme.error,
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startCentering() async {
    if (widget.targetRa == null || widget.targetDec == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No target coordinates specified')),
        );
      }
      return;
    }

    setState(() {
      _isCentering = true;
      _result = null;
    });

    final centeringService = ref.read(centeringServiceProvider);

    // Get plate solver config from settings
    // For now, use a default ASTAP config - this should come from user settings
    const solverConfig = PlateSolverConfig(
      type: PlateSolverType.astap,
      executablePath: 'C:\\Program Files\\astap\\astap.exe', // TODO: Get from settings
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

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Centering failed: $e')),
        );
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
