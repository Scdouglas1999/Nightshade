import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

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
    
    // Initialize controller on build
    ref.watch(phd2ControllerProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header with connection status
          Row(
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
                      onPressed: () async {
                        // Get PHD2 settings from AppSettings
                        final settings = await ref.read(appSettingsProvider.future);
                        ref.read(phd2ControllerProvider).connect(
                          settings.phd2Host,
                          settings.phd2Port,
                        );
                      },
                    )
                  else
                    NightshadeButton(
                      label: 'Disconnect',
                      icon: LucideIcons.plugZap, // or similar
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: () {
                        ref.read(phd2ControllerProvider).disconnect();
                      },
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(LucideIcons.settings, color: colors.textSecondary),
                    onPressed: () => _showSettingsDialog(context, ref),
                  ),
                ],
              ),
            ],
          ),
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
                                    final starImage = ref.watch(starImageProvider);
                                    return starImage.when(
                                      data: (image) => GuideStarView(
                                        pixels: image.pixels,
                                        width: image.width,
                                        height: image.height,
                                        starX: image.starX,
                                        starY: image.starY,
                                        snr: ref.watch(guideStatsProvider).snr,
                                        placeholderMessage: 'No star selected',
                                      ),
                                      loading: () => const GuideStarView(
                                        placeholderMessage: 'Waiting for image...',
                                      ),
                                      error: (_, __) => const GuideStarView(
                                        placeholderMessage: 'No star selected',
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildStatRow('Star SNR:', statsAsync.snr.toStringAsFixed(1), colors),
                              const SizedBox(height: 4),
                              _buildStatRow('Star Mass:', statsAsync.starMass.toStringAsFixed(0), colors),
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
                              _buildStatRow('RA RMS:', '${statsAsync.rmsRa.toStringAsFixed(2)}"', colors),
                              const SizedBox(height: 8),
                              _buildStatRow('Dec RMS:', '${statsAsync.rmsDec.toStringAsFixed(2)}"', colors),
                              const SizedBox(height: 8),
                              Divider(color: colors.border),
                              const SizedBox(height: 8),
                              _buildStatRow('Total RMS:', '${statsAsync.rmsTotal.toStringAsFixed(2)}"', colors, isHighlight: true),
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
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                          label: ref.watch(showGridProvider) ? 'Hide Grid' : 'Show Grid',
                                          icon: LucideIcons.grid,
                                          size: ButtonSize.small,
                                          variant: ButtonVariant.ghost,
                                          onPressed: () {
                                            ref.read(showGridProvider.notifier).state =
                                                !ref.read(showGridProvider);
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        NightshadeButton(
                                          label: 'Clear',
                                          size: ButtonSize.small,
                                          variant: ButtonVariant.ghost,
                                          onPressed: () {
                                            ref.read(guideGraphProvider.notifier).clear();
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
                      
                      // Controls
                      NightshadeCard(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              NightshadeButton(
                                label: 'Start Guiding',
                                icon: LucideIcons.play,
                                onPressed: !isConnected || phd2State == Phd2State.guiding
                                    ? null
                                    : () {
                                        ref.read(phd2ControllerProvider).startGuiding();
                                      },
                              ),
                              const SizedBox(width: 12),
                              NightshadeButton(
                                label: 'Stop',
                                icon: LucideIcons.square,
                                variant: ButtonVariant.outline,
                                onPressed: !isConnected || phd2State == Phd2State.stopped
                                    ? null
                                    : () {
                                        ref.read(phd2ControllerProvider).stopGuiding();
                                      },
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 1,
                                height: 24,
                                color: colors.border,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Dithering',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: NightshadeTextField(
                                            initialValue: ref.watch(ditherAmountProvider).toString(),
                                            hint: 'Pixels',
                                            suffix: 'px',
                                            onChanged: (val) {
                                              final amount = double.tryParse(val);
                                              if (amount != null && amount > 0) {
                                                ref.read(ditherAmountProvider.notifier).state = amount;
                                              }
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        NightshadeButton(
                                          label: 'Dither Now',
                                          size: ButtonSize.small,
                                          variant: ButtonVariant.outline,
                                          onPressed: !isConnected || phd2State != Phd2State.guiding
                                              ? null
                                              : () {
                                                  final amount = ref.read(ditherAmountProvider);
                                                  ref.read(phd2ControllerProvider).dither(amount: amount);
                                                },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, NightshadeColors colors, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12, 
            color: colors.textSecondary,
            fontWeight: isHighlight ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isHighlight ? colors.primary : colors.textPrimary,
          ),
        ),
      ],
    );
  }

  void _showSettingsDialog(BuildContext context, WidgetRef ref) async {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Load current settings from AppSettings
    final settings = await ref.read(appSettingsProvider.future);
    final hostController = TextEditingController(text: settings.phd2Host);
    final portController = TextEditingController(text: settings.phd2Port.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'PHD2 Connection',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: hostController,
                    style: TextStyle(color: colors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Host',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: portController,
                    style: TextStyle(color: colors.textPrimary),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Port',
                      labelStyle: TextStyle(color: colors.textMuted),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: colors.primary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: colors.textMuted)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final host = hostController.text;
              final port = int.tryParse(portController.text) ?? 4400;

              // Save settings to AppSettings
              await ref.read(appSettingsProvider.notifier).setPhd2Host(host);
              await ref.read(appSettingsProvider.notifier).setPhd2Port(port);

              ref.read(phd2ControllerProvider).connect(host, port);
            },
            style: FilledButton.styleFrom(backgroundColor: colors.primary),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
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

    // Draw grid overlay if enabled
    if (showGrid) {
      // Horizontal grid lines (every 1 arcsec)
      const range = 4.0;
      final scaleY = size.height / (range * 2);

      for (int i = -4; i <= 4; i++) {
        if (i == 0) continue; // Skip zero line, drawn separately
        final y = centerY - (i * scaleY);
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

    // Scale
    // Assuming +/- 4 arcsec range for now
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

      if (i == 0 || x < stepX) { // Start of visible path
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
  bool shouldRepaint(covariant _GraphPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.showGrid != showGrid;
  }
}

