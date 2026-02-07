import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart'
    hide Phd2GuidingState, GuideErrorPoint;
import 'package:nightshade_ui/nightshade_ui.dart' as ui
    show Phd2GuidingState, GuideControlsPanel;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show Phd2State;
import 'package:nightshade_app/widgets/phd2_connection_dialog.dart';
import 'package:nightshade_app/utils/phd2_helper.dart';

/// Provider for grid overlay toggle
final showGridProvider = StateProvider<bool>((ref) => true);

/// Provider for dither amount in pixels
final ditherAmountProvider = StateProvider<double>((ref) => 5.0);

class GuidingTab extends ConsumerWidget {
  const GuidingTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isConnected = ref.watch(phd2ConnectedProvider);
    final phd2State = ref.watch(phd2StateProvider);
    final statsAsync = ref.watch(guideStatsProvider);
    final isMobile = Responsive.isMobile(context);

    // Initialize controller on build
    ref.watch(phd2ControllerProvider);

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: isMobile
          ? _buildMobileLayout(
              context, ref, colors, isConnected, phd2State, statsAsync)
          : _buildDesktopLayout(
              context, ref, colors, isConnected, phd2State, statsAsync),
    );
  }

  /// Mobile layout: Vertical scrolling layout
  Widget _buildMobileLayout(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
    Phd2GuideStats statsAsync,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact header with connection status
          _buildConnectionHeader(context, ref, colors, isConnected, phd2State,
              isMobile: true),
          const SizedBox(height: 12),

          // Guide star view and stats in a row on mobile
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Guide star view (smaller on mobile)
              Expanded(
                child: NightshadeCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guide Star',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AspectRatio(
                          aspectRatio: 1,
                          child: Consumer(
                            builder: (context, ref, _) {
                              final starImage = ref.watch(starImageProvider);
                              return starImage.when(
                                data: (image) => GuideStarView(
                                  pixels: image.pixels,
                                  width: image.width,
                                  height: image.height,
                                  starX: image.starX,
                                  starY: image.starY,
                                  snr: ref.watch(guideStatsProvider).snr,
                                  statusMessage: 'No star',
                                ),
                                loading: () => const GuideStarView(
                                  statusMessage: 'Waiting...',
                                ),
                                error: (_, __) => const GuideStarView(
                                  statusMessage: 'No star',
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Guiding stats (compact)
              Expanded(
                child: NightshadeCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Stats',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStatRow(
                            'SNR:', statsAsync.snr.toStringAsFixed(1), colors),
                        const SizedBox(height: 4),
                        _buildStatRow('RA RMS:',
                            '${statsAsync.rmsRa.toStringAsFixed(2)}"', colors),
                        const SizedBox(height: 4),
                        _buildStatRow('Dec RMS:',
                            '${statsAsync.rmsDec.toStringAsFixed(2)}"', colors),
                        const SizedBox(height: 4),
                        Divider(color: colors.border, height: 8),
                        _buildStatRow(
                            'Total:',
                            '${statsAsync.rmsTotal.toStringAsFixed(2)}"',
                            colors,
                            isHighlight: true),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Guiding graph (fixed height on mobile)
          NightshadeCard(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Guiding Graph',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              ref.read(showGridProvider.notifier).state =
                                  !ref.read(showGridProvider);
                            },
                            child: Icon(
                              LucideIcons.grid,
                              size: 16,
                              color: ref.watch(showGridProvider)
                                  ? colors.primary
                                  : colors.textMuted,
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () =>
                                ref.read(guideGraphProvider.notifier).clear(),
                            child: Icon(LucideIcons.trash2,
                                size: 16, color: colors.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 150,
                    child: _GuidingGraph(
                      data: ref.watch(guideGraphProvider),
                      colors: colors,
                      showGrid: ref.watch(showGridProvider),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Controls panel (scrollable)
          ui.GuideControlsPanel(
            state: _mapPhd2State(phd2State, isConnected),
            isConnected: isConnected,
            onStartGuiding: () =>
                ref.read(phd2ControllerProvider).startGuiding(),
            onStopGuiding: () => ref.read(phd2ControllerProvider).stopGuiding(),
            onLoop: () => ref.read(phd2ControllerProvider).loop(),
            onFindStar: () =>
                ref.read(lockPositionProvider.notifier).findStar(),
            onDeselectStar: () =>
                ref.read(lockPositionProvider.notifier).deselectStar(),
            ditherAmount: ref.watch(ditherAmountProvider),
            onDitherAmountChanged: (amount) =>
                ref.read(ditherAmountProvider.notifier).state = amount,
            onDither: () => ref
                .read(phd2ControllerProvider)
                .dither(amount: ref.read(ditherAmountProvider)),
          ),
        ],
      ),
    );
  }

  /// Desktop layout: Side-by-side with fixed left column
  Widget _buildDesktopLayout(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State,
    Phd2GuideStats statsAsync,
  ) {
    return Column(
      children: [
        // Header with connection status
        _buildConnectionHeader(context, ref, colors, isConnected, phd2State,
            isMobile: false),
        const SizedBox(height: 16),

        // Main Content
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column: Guide Star & Stats
              SizedBox(
                width: 250,
                child: Column(
                  children: [
                    // Guide star view
                    NightshadeCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guide Star View',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            AspectRatio(
                              aspectRatio: 1,
                              child: Consumer(
                                builder: (context, ref, _) {
                                  final starImage =
                                      ref.watch(starImageProvider);
                                  return starImage.when(
                                    data: (image) => GuideStarView(
                                      pixels: image.pixels,
                                      width: image.width,
                                      height: image.height,
                                      starX: image.starX,
                                      starY: image.starY,
                                      snr: ref.watch(guideStatsProvider).snr,
                                      statusMessage: 'No star selected',
                                    ),
                                    loading: () => const GuideStarView(
                                      statusMessage: 'Waiting for image...',
                                    ),
                                    error: (_, __) => const GuideStarView(
                                      statusMessage: 'No star selected',
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildStatRow('Star SNR:',
                                statsAsync.snr.toStringAsFixed(1), colors),
                            const SizedBox(height: 4),
                            _buildStatRow('Star Mass:',
                                statsAsync.starMass.toStringAsFixed(0), colors),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Guiding Stats
                    NightshadeCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Guiding Stats',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildStatRow(
                                'RA RMS:',
                                '${statsAsync.rmsRa.toStringAsFixed(2)}"',
                                colors),
                            const SizedBox(height: 8),
                            _buildStatRow(
                                'Dec RMS:',
                                '${statsAsync.rmsDec.toStringAsFixed(2)}"',
                                colors),
                            const SizedBox(height: 8),
                            Divider(color: colors.border),
                            const SizedBox(height: 8),
                            _buildStatRow(
                                'Total RMS:',
                                '${statsAsync.rmsTotal.toStringAsFixed(2)}"',
                                colors,
                                isHighlight: true),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Right column: Graph & Controls
              Expanded(
                child: Column(
                  children: [
                    // Graph
                    Expanded(
                      child: NightshadeCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Guiding Graph',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      NightshadeButton(
                                        label: ref.watch(showGridProvider)
                                            ? 'Hide Grid'
                                            : 'Show Grid',
                                        icon: LucideIcons.grid,
                                        size: ButtonSize.small,
                                        variant: ButtonVariant.ghost,
                                        onPressed: () {
                                          ref
                                                  .read(showGridProvider.notifier)
                                                  .state =
                                              !ref.read(showGridProvider);
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      NightshadeButton(
                                        label: 'Clear',
                                        size: ButtonSize.small,
                                        variant: ButtonVariant.ghost,
                                        onPressed: () {
                                          ref
                                              .read(guideGraphProvider.notifier)
                                              .clear();
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: _GuidingGraph(
                                  data: ref.watch(guideGraphProvider),
                                  colors: colors,
                                  showGrid: ref.watch(showGridProvider),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Controls - using shared GuideControlsPanel widget
                    SizedBox(
                      height: 280,
                      child: ui.GuideControlsPanel(
                        state: _mapPhd2State(phd2State, isConnected),
                        isConnected: isConnected,
                        onStartGuiding: () =>
                            ref.read(phd2ControllerProvider).startGuiding(),
                        onStopGuiding: () =>
                            ref.read(phd2ControllerProvider).stopGuiding(),
                        onLoop: () => ref.read(phd2ControllerProvider).loop(),
                        onFindStar: () =>
                            ref.read(lockPositionProvider.notifier).findStar(),
                        onDeselectStar: () => ref
                            .read(lockPositionProvider.notifier)
                            .deselectStar(),
                        ditherAmount: ref.watch(ditherAmountProvider),
                        onDitherAmountChanged: (amount) => ref
                            .read(ditherAmountProvider.notifier)
                            .state = amount,
                        onDither: () => ref
                            .read(phd2ControllerProvider)
                            .dither(amount: ref.read(ditherAmountProvider)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds the connection header (shared between mobile and desktop)
  Widget _buildConnectionHeader(
    BuildContext context,
    WidgetRef ref,
    NightshadeColors colors,
    bool isConnected,
    Phd2State phd2State, {
    required bool isMobile,
  }) {
    if (isMobile) {
      // Compact header for mobile
      return Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? colors.success : colors.error,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isConnected ? 'PHD2 (${phd2State.name})' : 'Disconnected',
              style: TextStyle(
                fontSize: 12,
                color: colors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isConnected)
            NightshadeButton(
              label: 'Connect',
              icon: LucideIcons.plug,
              size: ButtonSize.small,
              onPressed: () => connectPhd2(ref, context: context),
            )
          else
            NightshadeButton(
              label: 'Disconnect',
              size: ButtonSize.small,
              variant: ButtonVariant.outline,
              onPressed: () => disconnectPhd2(ref),
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(LucideIcons.settings,
                size: 18, color: colors.textSecondary),
            onPressed: () => _showSettingsDialog(context, ref),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      );
    }

    // Standard desktop header
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? colors.success : colors.error,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isConnected
                  ? 'Connected to PHD2 (${phd2State.name})'
                  : 'Disconnected from PHD2',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Row(
          children: [
            if (!isConnected)
              NightshadeButton(
                label: 'Connect',
                icon: LucideIcons.plug,
                size: ButtonSize.small,
                onPressed: () => connectPhd2(ref, context: context),
              )
            else
              NightshadeButton(
                label: 'Disconnect',
                icon: LucideIcons.plugZap,
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: () => disconnectPhd2(ref),
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(LucideIcons.settings, color: colors.textSecondary),
              onPressed: () => _showSettingsDialog(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, NightshadeColors colors,
      {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 0,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isHighlight ? colors.primary : colors.textPrimary,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  void _showSettingsDialog(BuildContext context, WidgetRef ref) {
    Phd2ConnectionDialog.show(context, ref);
  }

  ui.Phd2GuidingState _mapPhd2State(Phd2State state, bool isConnected) {
    if (!isConnected) {
      return ui.Phd2GuidingState.disconnected;
    }
    switch (state) {
      case Phd2State.stopped:
        return ui.Phd2GuidingState.stopped;
      case Phd2State.looping:
        return ui.Phd2GuidingState.looping;
      case Phd2State.calibrating:
        return ui.Phd2GuidingState.calibrating;
      case Phd2State.guiding:
        return ui.Phd2GuidingState.guiding;
      case Phd2State.paused:
        return ui.Phd2GuidingState.paused;
      case Phd2State.settling:
        return ui.Phd2GuidingState.settling;
      case Phd2State.lostLock:
        return ui.Phd2GuidingState.lostLock;
      default:
        return ui.Phd2GuidingState.disconnected;
    }
  }
}

class _GuidingGraph extends StatelessWidget {
  final List<GuideGraphPoint> data;
  final NightshadeColors colors;
  final bool showGrid;

  const _GuidingGraph({
    required this.data,
    required this.colors,
    required this.showGrid,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: CustomPaint(
        painter: _GraphPainter(
          data: data,
          colors: colors,
          showGrid: showGrid,
        ),
        child: Container(),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<GuideGraphPoint> data;
  final NightshadeColors colors;
  final bool showGrid;

  _GraphPainter({
    required this.data,
    required this.colors,
    required this.showGrid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintGrid = Paint()
      ..color = colors.border.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    final paintZero = Paint()
      ..color = colors.textMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    final centerY = size.height / 2;
    final range = _computeDisplayRange();
    final scaleY = size.height / (range * 2);

    // Draw grid overlay if enabled
    if (showGrid) {
      final gridStep = _selectGridStep(range);
      final maxGridIndex = (range / gridStep).ceil();

      for (int i = -maxGridIndex; i <= maxGridIndex; i++) {
        if (i == 0) continue; // Skip zero line, drawn separately
        final value = i * gridStep;
        if (value.abs() > range + 1e-6) {
          continue;
        }
        final y = centerY - (value * scaleY);
        if (y >= 0 && y <= size.height) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
        }
      }

      // Vertical grid lines (every 10 time steps)
      final stepX = size.width / 100;
      for (int i = 0; i <= 10; i++) {
        final x = i * stepX * 10;
        if (x >= 0 && x <= size.width) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paintGrid);
        }
      }
    }

    // Draw zero line (always visible)
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), paintZero);

    // Early return if no data
    if (data.isEmpty) return;

    final paintRa = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintDec = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Scale to the observed guide-error envelope for the currently visible data.
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
        // Start of visible path
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

  double _computeDisplayRange() {
    if (data.isEmpty) {
      return 1.0;
    }

    final visibleStart = data.length > 100 ? data.length - 100 : 0;
    double maxAbs = 0.0;
    for (int i = visibleStart; i < data.length; i++) {
      final point = data[i];
      final absRa = point.ra.abs();
      final absDec = point.dec.abs();
      if (absRa > maxAbs) {
        maxAbs = absRa;
      }
      if (absDec > maxAbs) {
        maxAbs = absDec;
      }
    }

    if (maxAbs <= 0) {
      return 1.0;
    }

    // Add headroom so traces don't hug the chart edge.
    return (maxAbs * 1.2).clamp(0.5, 30.0);
  }

  double _selectGridStep(double range) {
    const candidateSteps = <double>[0.1, 0.2, 0.5, 1, 2, 5, 10];
    final target = range / 4;
    for (final step in candidateSteps) {
      if (step >= target) {
        return step;
      }
    }
    return 10.0;
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.showGrid != showGrid;
  }
}
