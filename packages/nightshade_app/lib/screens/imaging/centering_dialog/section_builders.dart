// ignore_for_file: invalid_use_of_protected_member
// Part of ../centering_dialog.dart -- extracted for maintainability.
//
// Header, preview, coordinate, exposure, status, result and history section builders.
part of '../centering_dialog.dart';

extension _CenteringDialogSectionBuilders on _CenteringDialogState {
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
                  borderRadius:
                      BorderRadius.circular(NightshadeTokens.radiusInline4),
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
    return NightshadeCard(
      padding: const EdgeInsets.all(12),
      borderRadius: NightshadeTokens.radiusInline8,
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
    final hasError = _exposureError != null;
    return NightshadeCard(
      padding: const EdgeInsets.all(12),
      borderRadius: NightshadeTokens.radiusInline8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.camera,
                  size: 16, color: colors.textSecondary),
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
                  // Clear a stale validation error the moment the user starts
                  // fixing the field, so the entry stays live and editable.
                  onChanged: (_) {
                    if (_exposureError != null) {
                      setState(() => _exposureError = null);
                    }
                  },
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
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusMd),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusMd),
                      borderSide: BorderSide(
                          color: hasError ? colors.error : colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusMd),
                      borderSide: BorderSide(
                          color: hasError ? colors.error : colors.accent),
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
          if (hasError) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.alertCircle, size: 14, color: colors.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _exposureError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline11),
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
}
