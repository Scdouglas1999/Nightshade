import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class ScienceSurfaceExplorer extends StatefulWidget {
  final NightshadeColors colors;
  final List<ScienceTileMetricRow> tiles;

  const ScienceSurfaceExplorer({
    super.key,
    required this.colors,
    required this.tiles,
  });

  @override
  State<ScienceSurfaceExplorer> createState() => _ScienceSurfaceExplorerState();
}

class _ScienceSurfaceExplorerState extends State<ScienceSurfaceExplorer> {
  String _selectedLayer = ScienceLayerType.uniformity.dbValue;
  double _yaw = -0.55;
  double _pitch = 0.75;
  double _zExaggeration = 1.6;
  bool _showContour = false;

  @override
  Widget build(BuildContext context) {
    final layerNames = widget.tiles
        .map((tile) => tile.layerType)
        .toSet()
        .toList(growable: false)
      ..sort();
    if (layerNames.isNotEmpty && !layerNames.contains(_selectedLayer)) {
      _selectedLayer = layerNames.first;
    }
    final selectedTiles = widget.tiles
        .where((tile) => tile.layerType == _selectedLayer)
        .toList(growable: false);

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '3D Surface Explorer',
                  style: TextStyle(
                    color: widget.colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (layerNames.isNotEmpty)
                  DropdownButton<String>(
                    value: _selectedLayer,
                    items: layerNames
                        .map(
                          (layer) => DropdownMenuItem(
                            value: layer,
                            child: Text(_labelForLayer(layer)),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _selectedLayer = value);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 240,
              child: selectedTiles.isEmpty
                  ? Center(
                      child: Text(
                        'No tile metrics available for this frame.',
                        style: TextStyle(color: widget.colors.textMuted),
                      ),
                    )
                  : GestureDetector(
                      onPanUpdate: (details) {
                        setState(() {
                          _yaw += details.delta.dx * 0.01;
                          _pitch = (_pitch - details.delta.dy * 0.01)
                              .clamp(0.1, 1.45);
                        });
                      },
                      child: CustomPaint(
                        painter: _SurfacePainter(
                          tiles: selectedTiles,
                          yaw: _yaw,
                          pitch: _pitch,
                          zExaggeration: _zExaggeration,
                          showContour: _showContour,
                          colors: widget.colors,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _SliderLabeled(
                    label: 'Z Exaggeration',
                    value: _zExaggeration,
                    min: 0.6,
                    max: 3.2,
                    onChanged: (value) =>
                        setState(() => _zExaggeration = value),
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  selected: _showContour,
                  onSelected: (value) => setState(() => _showContour = value),
                  label: const Text('Contours'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _labelForLayer(String dbValue) {
    switch (dbValue) {
      case 'uniformity':
        return 'Uniformity';
      case 'clip_low':
        return 'Clip Low';
      case 'clip_high':
        return 'Clip High';
      case 'background':
        return 'Background';
      case 'snr':
        return 'SNR';
      case 'fwhm':
        return 'FWHM';
      case 'hfr':
        return 'HFR';
      case 'eccentricity':
        return 'Eccentricity';
      case 'residual_mag':
        return 'Residual';
      default:
        return dbValue;
    }
  }
}

class _SliderLabeled extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _SliderLabeled({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        Slider(
          min: min,
          max: max,
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SurfacePainter extends CustomPainter {
  final List<ScienceTileMetricRow> tiles;
  final double yaw;
  final double pitch;
  final double zExaggeration;
  final bool showContour;
  final NightshadeColors colors;

  _SurfacePainter({
    required this.tiles,
    required this.yaw,
    required this.pitch,
    required this.zExaggeration,
    required this.showContour,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) {
      return;
    }

    var maxRow = 0;
    var maxCol = 0;
    for (final tile in tiles) {
      if (tile.tileRow > maxRow) {
        maxRow = tile.tileRow;
      }
      if (tile.tileCol > maxCol) {
        maxCol = tile.tileCol;
      }
    }
    final rows = maxRow + 1;
    final cols = maxCol + 1;

    final values = tiles
        .map((tile) => tile.value)
        .where((value) => value.isFinite)
        .toList(growable: false)
      ..sort();
    final low = values.isEmpty ? 0.0 : values[(values.length * 0.05).floor()];
    final high = values.isEmpty
        ? 1.0
        : values[(values.length * 0.95).floor().clamp(0, values.length - 1)];
    final valueSpan = (high - low).abs() < 1e-6 ? 1.0 : (high - low);

    final points = <(Offset projected, double z, double norm)>[];
    for (final tile in tiles) {
      final nx = cols <= 1 ? 0.0 : (tile.tileCol / (cols - 1) - 0.5) * 2.0;
      final ny = rows <= 1 ? 0.0 : (tile.tileRow / (rows - 1) - 0.5) * 2.0;
      final norm = ((tile.value - low) / valueSpan).clamp(0.0, 1.0);
      final nz = (norm - 0.5) * zExaggeration;

      final rotYx = nx * math.cos(yaw) - nz * math.sin(yaw);
      final rotYz = nx * math.sin(yaw) + nz * math.cos(yaw);
      final rotXy = ny * math.cos(pitch) - rotYz * math.sin(pitch);
      final rotXz = ny * math.sin(pitch) + rotYz * math.cos(pitch);

      final sx = size.width * 0.5 + rotYx * size.width * 0.34;
      final sy = size.height * 0.56 + rotXy * size.height * 0.34;
      points.add((Offset(sx, sy), rotXz, norm));
    }

    points.sort((a, b) => a.$2.compareTo(b.$2));
    final pointPaint = Paint()..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final point in points) {
      final color = Color.lerp(
        const Color(0xFF1D4ED8),
        const Color(0xFFDC2626),
        point.$3,
      )!;
      pointPaint.color = color.withValues(alpha: 0.8);
      linePaint.color = color.withValues(alpha: showContour ? 0.6 : 0.3);
      canvas.drawCircle(point.$1, 4.2, pointPaint);
      if (showContour) {
        canvas.drawLine(
          Offset(point.$1.dx, point.$1.dy),
          Offset(point.$1.dx, size.height - 10),
          linePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SurfacePainter oldDelegate) {
    return tiles != oldDelegate.tiles ||
        yaw != oldDelegate.yaw ||
        pitch != oldDelegate.pitch ||
        zExaggeration != oldDelegate.zExaggeration ||
        showContour != oldDelegate.showContour;
  }
}
