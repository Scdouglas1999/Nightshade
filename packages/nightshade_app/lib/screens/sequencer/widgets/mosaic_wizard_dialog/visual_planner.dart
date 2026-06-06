part of '../mosaic_wizard_dialog.dart';

class _VisualMosaicPlanner extends StatefulWidget {
  final NightshadeColors colors;
  final double centerRa;
  final double centerDec;
  final List<_PanelPosition> panels;
  final double panelWidthArcmin;
  final double panelHeightArcmin;
  final double rotation;
  final ValueChanged<int> onPanelToggle;

  /// Drag callback: (deltaRaHours, deltaDecDegrees).
  final void Function(double dRaHours, double dDecDeg) onDragCenter;

  const _VisualMosaicPlanner({
    super.key,
    required this.colors,
    required this.centerRa,
    required this.centerDec,
    required this.panels,
    required this.panelWidthArcmin,
    required this.panelHeightArcmin,
    required this.rotation,
    required this.onPanelToggle,
    required this.onDragCenter,
  });

  @override
  State<_VisualMosaicPlanner> createState() => _VisualMosaicPlannerState();
}

class _VisualMosaicPlannerState extends State<_VisualMosaicPlanner> {
  double _zoom = 1.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final basePxPerDeg = math.min(
              constraints.maxWidth,
              constraints.maxHeight,
            ) /
            8.0;
        final pxPerDeg = basePxPerDeg * _zoom;

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _StarFieldPainter(),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _RaDecGridPainter(
                  pxPerDeg: pxPerDeg,
                ),
              ),
            ),
            Positioned.fill(
              child: _PanelLayer(
                colors: widget.colors,
                centerRa: widget.centerRa,
                centerDec: widget.centerDec,
                panels: widget.panels,
                panelWidthArcmin: widget.panelWidthArcmin,
                panelHeightArcmin: widget.panelHeightArcmin,
                rotation: widget.rotation,
                pxPerDeg: pxPerDeg,
                onPanelToggle: widget.onPanelToggle,
                onDragCenter: widget.onDragCenter,
              ),
            ),
            Positioned(
              left: 10,
              top: 10,
              child: _CoordHud(
                ra: widget.centerRa,
                dec: widget.centerDec,
                rotation: widget.rotation,
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: _ZoomControls(
                zoom: _zoom,
                onZoomIn: () =>
                    setState(() => _zoom = (_zoom * 1.4).clamp(0.25, 4.0)),
                onZoomOut: () =>
                    setState(() => _zoom = (_zoom / 1.4).clamp(0.25, 4.0)),
                onReset: () => setState(() => _zoom = 1.0),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: _Legend(colors: widget.colors),
            ),
          ],
        );
      },
    );
  }
}

class _CoordHud extends StatelessWidget {
  final double ra;
  final double dec;
  final double rotation;

  const _CoordHud({
    required this.ra,
    required this.dec,
    required this.rotation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        // absolute: HUD scrim over the dark sky planner canvas
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      ),
      child: Text(
        'RA ${ra.toStringAsFixed(3)}h   Dec ${dec.toStringAsFixed(2)}°   '
        'Rot ${rotation.toStringAsFixed(0)}°',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: NightshadeTypography.fontSize11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final NightshadeColors colors;
  const _Legend({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        // absolute: HUD scrim over the dark sky planner canvas
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.move, size: 11, color: colors.primary),
          const SizedBox(width: 4),
          // absolute: HUD label over the dark sky planner canvas
          const Text('Drag centre',
              style: TextStyle(color: Colors.white70, fontSize: NightshadeTypography.fontSize10)),
          const SizedBox(width: 12),
          Icon(LucideIcons.mousePointerClick, size: 11, color: colors.accent),
          const SizedBox(width: 4),
          // absolute: HUD label over the dark sky planner canvas
          const Text('Tap panel to toggle',
              style: TextStyle(color: Colors.white70, fontSize: NightshadeTypography.fontSize10)),
        ],
      ),
    );
  }
}

class _ZoomControls extends StatelessWidget {
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _ZoomControls({
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // absolute: HUD scrim over the dark sky planner canvas
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(NightshadeIcons.add, size: 14),
            onPressed: onZoomIn,
            // absolute: HUD control over the dark sky planner canvas
            color: Colors.white70,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
          Text('${(zoom * 100).round()}%',
              // absolute: HUD label over the dark sky planner canvas
              style: const TextStyle(color: Colors.white54, fontSize: NightshadeTypography.fontSize9)),
          IconButton(
            icon: const Icon(NightshadeIcons.remove, size: 14),
            onPressed: onZoomOut,
            // absolute: HUD control over the dark sky planner canvas
            color: Colors.white70,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
          IconButton(
            icon: const Icon(NightshadeIcons.crosshair, size: 14),
            onPressed: onReset,
            // absolute: HUD control over the dark sky planner canvas
            color: Colors.white70,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }
}

class _PanelLayer extends StatelessWidget {
  final NightshadeColors colors;
  final double centerRa;
  final double centerDec;
  final List<_PanelPosition> panels;
  final double panelWidthArcmin;
  final double panelHeightArcmin;
  final double rotation;
  final double pxPerDeg;
  final ValueChanged<int> onPanelToggle;
  final void Function(double dRaHours, double dDecDeg) onDragCenter;

  const _PanelLayer({
    required this.colors,
    required this.centerRa,
    required this.centerDec,
    required this.panels,
    required this.panelWidthArcmin,
    required this.panelHeightArcmin,
    required this.rotation,
    required this.pxPerDeg,
    required this.onPanelToggle,
    required this.onDragCenter,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final centerPx = Offset(
        constraints.maxWidth / 2,
        constraints.maxHeight / 2,
      );

      return GestureDetector(
        onPanUpdate: (details) {
          final dxDeg = details.delta.dx / pxPerDeg;
          final dyDeg = details.delta.dy / pxPerDeg;
          final decRad = centerDec * math.pi / 180.0;
          final cosDec =
              math.cos(decRad).abs() < 0.001 ? 0.001 : math.cos(decRad);
          // Dragging right moves the visible sky right, i.e. the
          // mosaic centre shifts to lower RA. dy follows screen
          // coordinates (down = negative dec).
          final dRaHours = -dxDeg / 15.0 / cosDec;
          final dDecDeg = dyDeg;
          onDragCenter(dRaHours, dDecDeg);
        },
        child: Stack(
          children: [
            for (final p in panels) _panelWidget(p, centerPx),
            Positioned(
              left: centerPx.dx - 6,
              top: centerPx.dy - 6,
              child: IgnorePointer(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.textPrimary, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _panelWidget(_PanelPosition p, Offset centerPx) {
    final dRaDeg = (p.ra - centerRa) * 15;
    final dDecDeg = p.dec - centerDec;
    final decRad = centerDec * math.pi / 180.0;
    final cosDec = math.cos(decRad);
    final dxDeg = dRaDeg * cosDec;
    final dyDeg = -dDecDeg;

    final panelCenterPx = centerPx +
        Offset(
          dxDeg * pxPerDeg,
          dyDeg * pxPerDeg,
        );
    final pxWidth = (panelWidthArcmin / 60.0) * pxPerDeg;
    final pxHeight = (panelHeightArcmin / 60.0) * pxPerDeg;

    return Positioned(
      left: panelCenterPx.dx - pxWidth / 2,
      top: panelCenterPx.dy - pxHeight / 2,
      child: Transform.rotate(
        angle: rotation * math.pi / 180.0,
        child: GestureDetector(
          onTap: () => onPanelToggle(p.index),
          child: Container(
            width: pxWidth,
            height: pxHeight,
            decoration: BoxDecoration(
              color: p.enabled
                  ? colors.primary.withValues(alpha: 0.18)
                  // absolute: disabled panel over the dark sky planner canvas
                  : Colors.grey.withValues(alpha: 0.05),
              border: Border.all(
                color: p.enabled
                    ? colors.primary
                    // absolute: disabled panel over the dark sky planner canvas
                    : Colors.grey.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                '${p.index + 1}',
                style: TextStyle(
                  fontSize: math.max(10, pxWidth * 0.12),
                  // absolute: disabled panel index over the dark sky canvas
                  color: p.enabled ? colors.textPrimary : Colors.white24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Painters
// ============================================================================
