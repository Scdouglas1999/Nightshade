part of '../diagnostics_screen.dart';

class _PsfFieldMapCard extends StatelessWidget {
  final List<PsfFieldTileRow> psfTiles;
  final NightshadeColors colors;

  const _PsfFieldMapCard({
    required this.psfTiles,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return _DiagCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.grid, size: 16, color: colors.primary),
              const SizedBox(width: 8),
              Text(
                'PSF Field Map',
                style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              Text(
                '${psfTiles.length} tiles',
                style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (psfTiles.isEmpty)
            // Shared EmptyState keeps diagnostics placeholders visually aligned
            // with the science analytics tabs that already use icon+title+body.
            const EmptyState(
              icon: LucideIcons.grid,
              title: 'No PSF field tile data for this session.',
              body: 'Capture plate-solved frames to generate PSF maps.',
              padding: EdgeInsets.symmetric(vertical: 32),
            )
          else
            AspectRatio(
              aspectRatio: 1.5,
              child: CustomPaint(
                painter: _PsfFieldMapPainter(
                  tiles: psfTiles,
                  goodColor: colors.success,
                  warnColor: colors.warning,
                  badColor: colors.error,
                  borderColor: colors.border,
                  textColor: colors.textPrimary,
                  bgColor: colors.surfaceAlt,
                ),
              ),
            ),
          if (psfTiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Color legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(
                  color: colors.success,
                  label: context.l10n.text('diagnosticsLowHfr'),
                ),
                const SizedBox(width: 16),
                _LegendDot(
                  color: colors.warning,
                  label: context.l10n.text('diagnosticsMedium'),
                ),
                const SizedBox(width: 16),
                _LegendDot(
                  color: colors.error,
                  label: context.l10n.text('diagnosticsHighHfr'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
        ),
      ],
    );
  }
}

class _PsfFieldMapPainter extends CustomPainter {
  final List<PsfFieldTileRow> tiles;
  final Color goodColor;
  final Color warnColor;
  final Color badColor;
  final Color borderColor;
  final Color textColor;
  final Color bgColor;

  _PsfFieldMapPainter({
    required this.tiles,
    required this.goodColor,
    required this.warnColor,
    required this.badColor,
    required this.borderColor,
    required this.textColor,
    required this.bgColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) return;

    final maxRow =
        tiles.map((t) => t.tileRow).fold<int>(0, (a, b) => a > b ? a : b);
    final maxCol =
        tiles.map((t) => t.tileCol).fold<int>(0, (a, b) => a > b ? a : b);
    final numRows = maxRow + 1;
    final numCols = maxCol + 1;

    if (numRows == 0 || numCols == 0) return;

    final cellWidth = size.width / numCols;
    final cellHeight = size.height / numRows;

    // Compute HFR range across all tiles for normalization
    final hfrValues =
        tiles.map((t) => t.medianHfr).where((v) => v > 0).toList();
    if (hfrValues.isEmpty) return;

    final minHfr = hfrValues.reduce(math.min);
    final maxHfr = hfrValues.reduce(math.max);
    final hfrRange = (maxHfr - minHfr).clamp(0.01, double.infinity);

    // Build lookup
    final lookup = <(int, int), PsfFieldTileRow>{};
    for (final tile in tiles) {
      lookup[(tile.tileRow, tile.tileCol)] = tile;
    }

    for (int row = 0; row < numRows; row++) {
      for (int col = 0; col < numCols; col++) {
        final rect = Rect.fromLTWH(
          col * cellWidth,
          row * cellHeight,
          cellWidth,
          cellHeight,
        );

        final tile = lookup[(row, col)];
        if (tile == null || tile.medianHfr <= 0) {
          // Empty tile
          final emptyPaint = Paint()..color = bgColor;
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(3)),
            emptyPaint,
          );
          continue;
        }

        // Normalize HFR to 0-1 (0 = best, 1 = worst)
        final normalized = (tile.medianHfr - minHfr) / hfrRange;

        // Interpolate color: green -> yellow -> red
        final color = Color.lerp(
          Color.lerp(goodColor, warnColor, (normalized * 2).clamp(0.0, 1.0)),
          badColor,
          ((normalized - 0.5) * 2).clamp(0.0, 1.0),
        )!;

        final cellPaint = Paint()..color = color.withValues(alpha: 0.7);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(3)),
          cellPaint,
        );

        // Draw border
        final borderPaint = Paint()
          ..color = borderColor.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(3)),
          borderPaint,
        );

        // Draw HFR value text if cell is big enough
        if (cellWidth > 40 && cellHeight > 25) {
          final span = TextSpan(
            text: tile.medianHfr.toStringAsFixed(1),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize10,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          );
          final painter = TextPainter(
            text: span,
            textDirection: TextDirection.ltr,
          )..layout();
          painter.paint(
            canvas,
            Offset(
              rect.center.dx - painter.width / 2,
              rect.center.dy - painter.height / 2,
            ),
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PsfFieldMapPainter old) => tiles != old.tiles;
}

// --- Residual Vector Card ---
