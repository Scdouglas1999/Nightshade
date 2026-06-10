import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../localization/nightshade_localizations.dart';
import 'glass_card.dart';

class GuidingCard extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const GuidingCard({super.key, required this.colors});

  @override
  ConsumerState<GuidingCard> createState() => _GuidingCardState();
}

class _GuidingCardState extends ConsumerState<GuidingCard> {
  bool _isStartingOrStopping = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final guiderState = ref.watch(guiderStateProvider);
    final guideGraphData = ref.watch(guideGraphProvider);

    final isConnected =
        guiderState.connectionState == DeviceConnectionState.connected;
    final isGuiding = guiderState.isGuiding;
    final rmsTotal = guiderState.rmsTotal?.toStringAsFixed(2) ?? '---';
    final rmsRa = guiderState.rmsRa?.toStringAsFixed(2) ?? '---';
    final rmsDec = guiderState.rmsDec?.toStringAsFixed(2) ?? '---';

    final l10n = context.l10n;
    // Guiding state text
    final stateText = !isConnected
        ? l10n.text('disconnected')
        : _isStartingOrStopping
            ? (isGuiding ? l10n.text('stopping') : l10n.text('starting'))
            : isGuiding
                ? l10n.text('guiding')
                : l10n.text('idle');

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with state and RMS inline
          DashboardCardHeader(
            colors: colors,
            icon: LucideIcons.crosshair,
            title: l10n.text('guiding'),
            accent: isGuiding ? colors.success : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Inline RMS values
                Text(
                  '$rmsTotal"',
                  style: NightshadeTypography.h6.copyWith(
                    color: isGuiding ? colors.primary : colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                DashboardStatusChip(
                  colors: colors,
                  label: stateText,
                  active: isGuiding,
                ),
              ],
            ),
          ),

          const SizedBox(height: DashboardCardStyle.headerGap),

          // Graph - compact height
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline4),
            ),
            child: isConnected && guideGraphData.isNotEmpty
                ? ClipRRect(
                    borderRadius:
                        BorderRadius.circular(NightshadeTokens.radiusInline4),
                    child: CustomPaint(
                      painter: _DashboardGuidingGraphPainter(
                          data: guideGraphData, colors: colors),
                      child: const SizedBox.expand(),
                    ),
                  )
                : Center(
                    child: Text(
                      isConnected
                          ? l10n.text('clickStartToBegin')
                          : l10n.text('connectGuider'),
                      style: TextStyle(
                          fontSize: NightshadeTypography.fontSize10,
                          color: colors.textMuted),
                    ),
                  ),
          ),

          const SizedBox(height: 6),

          // Control button row
          Row(
            children: [
              // Stats row with legend
              Container(
                  width: 10, height: 2, color: NightshadeChartColors.seriesRed),
              const SizedBox(width: 3),
              Text('$rmsRa"',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      color: colors.textSecondary)),
              const SizedBox(width: 8),
              Container(
                  width: 10,
                  height: 2,
                  color: NightshadeChartColors.seriesBlue),
              const SizedBox(width: 3),
              Text('$rmsDec"',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize10,
                      color: colors.textSecondary)),
              const Spacer(),
              // Start/Stop button
              SizedBox(
                height: 24,
                child: NightshadeButton(
                  label: isGuiding ? l10n.text('stop') : l10n.text('start'),
                  icon: isGuiding ? LucideIcons.square : LucideIcons.play,
                  variant:
                      isGuiding ? ButtonVariant.outline : ButtonVariant.primary,
                  size: ButtonSize.small,
                  onPressed: (!isConnected || _isStartingOrStopping)
                      ? null
                      : () => _toggleGuiding(isGuiding),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleGuiding(bool isCurrentlyGuiding) async {
    setState(() => _isStartingOrStopping = true);
    try {
      final phd2Controller = ref.read(phd2ControllerProvider);
      if (isCurrentlyGuiding) {
        await phd2Controller.stopGuiding();
      } else {
        await phd2Controller.startGuiding();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to ${isCurrentlyGuiding ? 'stop' : 'start'} guiding: $e'),
            backgroundColor: widget.colors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isStartingOrStopping = false);
      }
    }
  }
}

class _DashboardGuidingGraphPainter extends CustomPainter {
  final List<GuideGraphPoint> data;
  final NightshadeColors colors;

  _DashboardGuidingGraphPainter({required this.data, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paintRa = Paint()
      ..color = NightshadeChartColors.seriesRed
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintDec = Paint()
      ..color = NightshadeChartColors.seriesBlue
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintZero = Paint()
      ..color = colors.textMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    // Draw zero line
    final centerY = size.height / 2;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paintZero);

    // Scale: +/- 4 arcsec range
    const range = 4.0;
    final scaleY = size.height / (range * 2);
    final stepX = size.width / 100; // Show last 100 points

    // Draw paths
    final pathRa = Path();
    final pathDec = Path();

    for (int i = 0; i < data.length; i++) {
      final point = data[i];
      final x = size.width - ((data.length - 1 - i) * stepX);

      if (x < 0) continue;

      // Clamp values to range
      final raY = centerY - (point.ra.clamp(-range, range) * scaleY);
      final decY = centerY - (point.dec.clamp(-range, range) * scaleY);

      if (i == 0 || x < stepX) {
        pathRa.moveTo(x, raY);
        pathDec.moveTo(x, decY);
      } else {
        pathRa.lineTo(x, raY);
        pathDec.lineTo(x, decY);
      }
    }

    canvas.drawPath(pathRa, paintRa);
    canvas.drawPath(pathDec, paintDec);
  }

  @override
  bool shouldRepaint(covariant _DashboardGuidingGraphPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
