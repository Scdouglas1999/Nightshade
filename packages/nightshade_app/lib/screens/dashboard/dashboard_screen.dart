import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart' hide sessionProgressProvider;
import '../../widgets/astro_image_viewer.dart';

// ============================================================================
// Device ID Formatting Helpers
// ============================================================================

/// Format a device ID into a user-friendly display name
String _formatDeviceId(String id) {
  final lowerId = id.toLowerCase();

  // Handle native device IDs: native:vendor:index or native:vendor_type:index
  if (lowerId.startsWith('native:')) {
    final parts = id.substring(7).split(':');
    if (parts.isNotEmpty) {
      final devicePart = parts[0];
      final index = parts.length > 1 ? int.tryParse(parts[1]) : null;

      if (devicePart.contains('_')) {
        final subParts = devicePart.split('_');
        final vendor = _capitalizeVendor(subParts[0]);
        final type = subParts.sublist(1).map((s) => s.toUpperCase()).join(' ');
        return '$vendor $type';
      }

      final vendor = _capitalizeVendor(devicePart);
      if (index != null) {
        return '$vendor #${index + 1}';
      }
      return vendor;
    }
  }

  // Handle ASCOM device IDs
  if (lowerId.startsWith('ascom:') || lowerId.startsWith('ascom.')) {
    final ascomId = lowerId.startsWith('ascom:') ? id.substring(6) : id;
    final parts = ascomId.split('.');
    if (parts.length >= 2) {
      final vendorPart = parts.length > 1 ? parts[1] : parts[0];
      return _formatAscomVendor(vendorPart);
    }
  }

  // Handle Alpaca device IDs
  if (lowerId.startsWith('alpaca:')) {
    return 'Alpaca: ${id.substring(7)}';
  }

  // Handle PHD2
  if (lowerId.contains('phd2') || lowerId.contains('phd 2')) {
    return 'PHD2';
  }

  // Handle underscore-separated IDs
  if (id.contains('_')) {
    return id.split('_').map(_capitalizeWord).join(' ');
  }

  return id;
}

String _capitalizeVendor(String vendor) {
  const knownVendors = {
    'zwo': 'ZWO',
    'asi': 'ZWO ASI',
    'qhy': 'QHY',
    'playerone': 'PlayerOne',
    'svbony': 'SVBony',
    'atik': 'Atik',
    'fli': 'FLI',
    'moravian': 'Moravian',
    'touptek': 'Touptek',
    'pegasus': 'Pegasus',
    'pegasusastro': 'Pegasus Astro',
    'ioptron': 'iOptron',
    'skywatcher': 'Sky-Watcher',
    'celestron': 'Celestron',
    'meade': 'Meade',
    'moonlite': 'MoonLite',
  };

  final lower = vendor.toLowerCase();
  if (knownVendors.containsKey(lower)) {
    return knownVendors[lower]!;
  }

  if (vendor.isEmpty) return vendor;
  return vendor[0].toUpperCase() + vendor.substring(1);
}

String _formatAscomVendor(String vendor) {
  final spaced = vendor.replaceAllMapped(
    RegExp(r'([a-z])([A-Z0-9])'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  return spaced;
}

String _capitalizeWord(String word) {
  if (word.isEmpty) return word;
  return word[0].toUpperCase() + word.substring(1).toLowerCase();
}

/// Get display name for a device
String _getDeviceDisplayName(String? deviceName, String? deviceId, String fallback) {
  if (deviceName != null && deviceName.isNotEmpty) {
    return deviceName;
  }
  if (deviceId != null && deviceId.isNotEmpty) {
    return _formatDeviceId(deviceId);
  }
  return fallback;
}

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    
    // Ensure PHD2 controller is active and listening to events
    ref.watch(phd2ControllerProvider);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome header with time
            _WelcomeHeader(colors: colors),

            const SizedBox(height: 24),

            // Main content grid
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column - 60%
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      // Live preview card
                      _LivePreviewCard(
                        colors: colors,
                        pulseController: _pulseController,
                      ),

                      const SizedBox(height: 20),

                      // Session progress
                      _SessionProgressCard(colors: colors),

                      const SizedBox(height: 20),

                      // Guiding graph
                      _GuidingCard(colors: colors),
                    ],
                  ),
                ),

                const SizedBox(width: 20),

                // Right column - 40%
                Expanded(
                  flex: 4,
                  child: Column(
                    children: [
                      // Equipment status
                      _EquipmentStatusCard(colors: colors),

                      const SizedBox(height: 20),

                      // Quick stats
                      _QuickStatsCard(colors: colors),

                      const SizedBox(height: 20),

                      // Tonight's conditions
                      _TonightCard(colors: colors),

                      const SizedBox(height: 20),

                      // Quick actions
                      _QuickActionsCard(colors: colors),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  final NightshadeColors colors;

  const _WelcomeHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Ready to capture the cosmos?',
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        _ClockWidget(colors: colors),
      ],
    );
  }
}

class _ClockWidget extends ConsumerWidget {
  final NightshadeColors colors;

  const _ClockWidget({required this.colors});

  String _formatLST(double lstHours) {
    final h = lstHours.floor();
    final m = ((lstHours - h) * 60).floor();
    final s = (((lstHours - h) * 60 - m) * 60).floor();
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the observationTimeProvider for both local time and LST
    // This provider already updates every second, no need for a separate timer
    final timeState = ref.watch(observationTimeProvider);
    final now = timeState.time;
    final lst = ref.watch(localSiderealTimeProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.15),
            colors.accent.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.clock, size: 18, color: colors.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                'LST ${_formatLST(lst)}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live preview card - orchestrates smaller focused widgets
class _LivePreviewCard extends StatelessWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;

  const _LivePreviewCard({
    required this.colors,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - split into own widget for capture status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.image,
                      size: 16,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Live Preview',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              // Capture status indicator - watches its own providers
              _CaptureStatusIndicator(
                colors: colors,
                pulseController: pulseController,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Image preview area - watches currentImageProvider and cameraStateProvider
          _ImagePreviewArea(colors: colors),

          const SizedBox(height: 12),

          // Stats row - watches lastImageStatsProvider
          _ImageStatsRow(colors: colors),
        ],
      ),
    );
  }
}

/// Capture status indicator - only rebuilds when capture state changes
class _CaptureStatusIndicator extends ConsumerWidget {
  final NightshadeColors colors;
  final AnimationController pulseController;

  const _CaptureStatusIndicator({
    required this.colors,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exposurePercent = ref.watch(exposureProgressProvider.select((s) => s.percent));
    final isDownloading = ref.watch(exposureProgressProvider.select((s) => s.isDownloading));
    final isSessionCapturing = ref.watch(sessionStateProvider.select((s) => s.isCapturing));

    final isCapturing = isSessionCapturing || exposurePercent > 0 || isDownloading;

    return Row(
      children: [
        AnimatedBuilder(
          animation: pulseController,
          builder: (context, child) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isCapturing
                    ? colors.success.withValues(alpha: 0.3 + pulseController.value * 0.4)
                    : colors.textMuted.withValues(alpha: 0.3 + pulseController.value * 0.4),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          isCapturing ? 'Capturing' : 'Idle',
          style: TextStyle(
            fontSize: 12,
            color: isCapturing ? colors.success : colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Image preview area - only rebuilds when image or camera connection changes
class _ImagePreviewArea extends ConsumerWidget {
  final NightshadeColors colors;

  const _ImagePreviewArea({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentImage = ref.watch(currentImageProvider);
    final isConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final cameraDeviceName = ref.watch(cameraStateProvider.select((s) => s.deviceName));

    // Get resolution from camera state or image
    String resolutionText = '--- × ---';
    if (currentImage != null) {
      resolutionText = '${currentImage.width} × ${currentImage.height}';
    } else if (isConnected && cameraDeviceName != null) {
      resolutionText = 'Connected';
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Stack(
          children: [
            // Display actual image if available
            if (currentImage != null)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _DashboardImageDisplay(
                    imageData: currentImage,
                  ),
                ),
              )
            else
              // Star field background animation (placeholder when no image)
              CustomPaint(
                painter: _StarFieldPainter(colors: colors),
                size: Size.infinite,
              ),

            // Center content (only show when no image)
            if (currentImage == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.border,
                        ),
                      ),
                      child: Icon(
                        LucideIcons.camera,
                        size: 32,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isConnected ? 'No Image' : 'No Camera Connected',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isConnected
                          ? 'Start a sequence or take a snapshot'
                          : 'Connect a camera in Equipment settings',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

            // Corner overlays
            Positioned(
              left: 12,
              top: 12,
              child: _OverlayChip(
                icon: LucideIcons.maximize2,
                label: resolutionText,
                colors: colors,
              ),
            ),
            if (currentImage != null)
              Positioned(
                right: 12,
                top: 12,
                child: _OverlayChip(
                  icon: LucideIcons.crosshair,
                  label: 'Crosshair',
                  colors: colors,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Image stats row - only rebuilds when image stats change
class _ImageStatsRow extends ConsumerWidget {
  final NightshadeColors colors;

  const _ImageStatsRow({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastStats = ref.watch(lastImageStatsProvider);

    return Row(
      children: [
        _MiniStat(
          label: 'HFR',
          value: lastStats?.hfr?.toStringAsFixed(2) ?? '---',
          colors: colors,
        ),
        _MiniStat(
          label: 'Stars',
          value: lastStats?.starCount?.toString() ?? '---',
          colors: colors,
        ),
        _MiniStat(
          label: 'Median',
          value: lastStats?.median?.toStringAsFixed(0) ?? '---',
          colors: colors,
        ),
        _MiniStat(
          label: 'Noise',
          value: lastStats?.noise?.toStringAsFixed(1) ?? '---',
          colors: colors,
        ),
      ],
    );
  }
}

// Image display for dashboard with zoom/pan support
class _DashboardImageDisplay extends StatelessWidget {
  final CapturedImageData imageData;

  const _DashboardImageDisplay({required this.imageData});

  @override
  Widget build(BuildContext context) {
    return AstroImageViewer(
      imageData: imageData.displayData,
      width: imageData.width,
      height: imageData.height,
      isColor: imageData.isColor,
      minScale: 0.5,
      maxScale: 10.0,
      enableInteraction: true,
    );
  }
}

class _StarFieldPainter extends CustomPainter {
  final NightshadeColors colors;

  _StarFieldPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    final paint = Paint();

    for (var i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final brightness = random.nextDouble() * 0.3 + 0.1;
      final radius = random.nextDouble() * 1.5 + 0.5;

      paint.color = Colors.white.withValues(alpha: brightness);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _OverlayChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _OverlayChip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionProgressCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _SessionProgressCard({required this.colors});

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  String _formatIntegrationTime(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    return _formatDuration(duration);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionState = ref.watch(sessionStateProvider);
    final progress = ref.watch(sessionProgressProvider);
    
    final isActive = sessionState.isActive;
    final progressValue = progress.clamp(0.0, 1.0);
    
    // Format exposure count
    final exposureText = '${sessionState.completedExposures} / ${sessionState.totalExposures}';
    
    // Format integration time
    final integrationText = sessionState.totalIntegrationSecs > 0
        ? _formatIntegrationTime(sessionState.totalIntegrationSecs)
        : '0h 0m';
    
    // Format elapsed time
    final elapsedText = sessionState.startTime != null
        ? _formatDuration(DateTime.now().difference(sessionState.startTime!))
        : '0h 0m';
    
    // Calculate remaining time (estimate based on progress)
    String remainingText = '---';
    if (isActive && progressValue > 0 && progressValue < 1.0 && sessionState.startTime != null) {
      final elapsed = DateTime.now().difference(sessionState.startTime!);
      final estimatedTotal = Duration(
        milliseconds: (elapsed.inMilliseconds / progressValue).round(),
      );
      final remaining = estimatedTotal - elapsed;
      if (remaining.inMilliseconds > 0) {
        remainingText = _formatDuration(remaining);
      }
    }

    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.listOrdered,
                      size: 16,
                      color: colors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Session Progress',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              if (!isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'No active sequence',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 20),

          // Progress bar
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(4),
            ),
            child: FractionallySizedBox(
              widthFactor: progressValue,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colors.primary, colors.accent],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SessionStat(
                icon: LucideIcons.image,
                label: 'Exposures',
                value: exposureText,
                colors: colors,
              ),
              _SessionStat(
                icon: LucideIcons.timer,
                label: 'Integration',
                value: integrationText,
                colors: colors,
              ),
              _SessionStat(
                icon: LucideIcons.clock,
                label: 'Elapsed',
                value: elapsedText,
                colors: colors,
              ),
              _SessionStat(
                icon: LucideIcons.hourglass,
                label: 'Remaining',
                value: remainingText,
                colors: colors,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SessionStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _SessionStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GuidingCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _GuidingCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use select() to only watch specific fields we need
    final isConnected = ref.watch(guiderStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final isGuiding = ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final rmsValue = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));
    final guideGraphData = ref.watch(guideGraphProvider);

    final rmsTotal = rmsValue?.toStringAsFixed(2) ?? '---';

    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.crosshair,
                      size: 16,
                      color: colors.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Guiding',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'RMS: ',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  Text(
                    rmsTotal,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Graph
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: isConnected && guideGraphData.isNotEmpty
                ? ClipRect(
                    child: CustomPaint(
                      painter: _DashboardGuidingGraphPainter(
                        data: guideGraphData,
                        colors: colors,
                      ),
                      child: Container(),
                    ),
                  )
                : Center(
                    child: Text(
                      isConnected 
                          ? (isGuiding ? 'Guiding active' : 'Start guiding to see graph')
                          : 'Connect guider to see graph',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              const _LegendItem(color: Colors.redAccent, label: 'RA'),
              const SizedBox(width: 16),
              const _LegendItem(color: Colors.blueAccent, label: 'Dec'),
              const Spacer(),
              Text(
                'Scale: ±4"',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
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
      ..color = Colors.redAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final paintDec = Paint()
      ..color = Colors.blueAccent
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

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Row(
      children: [
        Container(
          width: 12,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _EquipmentStatusCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _EquipmentStatusCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use select() to only rebuild when connection state, device name, or device ID changes
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final cameraName = ref.watch(cameraStateProvider.select((s) => s.deviceName));
    final cameraId = ref.watch(cameraStateProvider.select((s) => s.deviceId));

    final mountConnected = ref.watch(mountStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final mountName = ref.watch(mountStateProvider.select((s) => s.deviceName));
    final mountId = ref.watch(mountStateProvider.select((s) => s.deviceId));

    final guiderConnected = ref.watch(guiderStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final guiderIsGuiding = ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderName = ref.watch(guiderStateProvider.select((s) => s.deviceName));
    final guiderId = ref.watch(guiderStateProvider.select((s) => s.deviceId));

    final focuserConnected = ref.watch(focuserStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final focuserName = ref.watch(focuserStateProvider.select((s) => s.deviceName));
    final focuserId = ref.watch(focuserStateProvider.select((s) => s.deviceId));

    final filterWheelConnected = ref.watch(filterWheelStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final filterWheelName = ref.watch(filterWheelStateProvider.select((s) => s.deviceName));
    final filterWheelId = ref.watch(filterWheelStateProvider.select((s) => s.deviceId));

    final connectedCount = [cameraConnected, mountConnected, guiderConnected, focuserConnected, filterWheelConnected]
        .where((c) => c).length;

    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      LucideIcons.plug,
                      size: 16,
                      color: colors.success,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Equipment',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
              Text(
                '$connectedCount/5 connected',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Equipment items (DYNAMIC)
          _EquipmentItem(
            icon: LucideIcons.camera,
            name: 'Camera',
            status: cameraConnected
                ? _getDeviceDisplayName(cameraName, cameraId, 'Connected')
                : 'Disconnected',
            isConnected: cameraConnected,
            colors: colors,
          ),
          _EquipmentItem(
            icon: LucideIcons.move3d,
            name: 'Mount',
            status: mountConnected
                ? _getDeviceDisplayName(mountName, mountId, 'Connected')
                : 'Disconnected',
            isConnected: mountConnected,
            colors: colors,
          ),
          _EquipmentItem(
            icon: LucideIcons.crosshair,
            name: 'Guider',
            status: guiderConnected
                ? (guiderIsGuiding ? 'Guiding' : _getDeviceDisplayName(guiderName, guiderId, 'Connected'))
                : 'Disconnected',
            isConnected: guiderConnected,
            colors: colors,
          ),
          _EquipmentItem(
            icon: LucideIcons.focus,
            name: 'Focuser',
            status: focuserConnected
                ? _getDeviceDisplayName(focuserName, focuserId, 'Connected')
                : 'Disconnected',
            isConnected: focuserConnected,
            colors: colors,
          ),
          _EquipmentItem(
            icon: LucideIcons.circle,
            name: 'Filter Wheel',
            status: filterWheelConnected
                ? _getDeviceDisplayName(filterWheelName, filterWheelId, 'Connected')
                : 'Disconnected',
            isConnected: filterWheelConnected,
            colors: colors,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _EquipmentItem extends StatelessWidget {
  final IconData icon;
  final String name;
  final String status;
  final bool isConnected;
  final NightshadeColors colors;
  final bool isLast;

  const _EquipmentItem({
    required this.icon,
    required this.name,
    required this.status,
    required this.isConnected,
    required this.colors,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: colors.border.withValues(alpha: 0.5),
                ),
              ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: isConnected ? colors.success : colors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                color: colors.textPrimary,
              ),
            ),
          ),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConnected ? colors.success : colors.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickStatsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickStatsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use select() to only rebuild when specific fields change
    final cameraConnected = ref.watch(cameraStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final cameraTemp = ref.watch(cameraStateProvider.select((s) => s.temperature));

    final guiderConnected = ref.watch(guiderStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final guiderIsGuiding = ref.watch(guiderStateProvider.select((s) => s.isGuiding));
    final guiderRms = ref.watch(guiderStateProvider.select((s) => s.rmsTotal));

    final hfr = ref.watch(lastImageStatsProvider.select((s) => s?.hfr));

    final focuserConnected = ref.watch(focuserStateProvider.select((s) => s.connectionState)) == DeviceConnectionState.connected;
    final focuserPosition = ref.watch(focuserStateProvider.select((s) => s.position));

    // Format temperature (same logic as Imaging tab)
    String tempValue = '---';
    if (cameraConnected) {
      if (cameraTemp != null) {
        tempValue = '${cameraTemp.toStringAsFixed(1)}°C';
      } else {
        tempValue = 'N/A';
      }
    }

    // Format RMS (same logic as Imaging tab)
    String rmsValue = '---';
    if (guiderConnected && guiderIsGuiding && guiderRms != null) {
      rmsValue = '${guiderRms.toStringAsFixed(2)}"';
    }

    // Format HFR (same logic as Imaging tab)
    String hfrValue = '---';
    if (hfr != null) {
      hfrValue = hfr.toStringAsFixed(2);
    }

    // Format Focus position
    String focusValue = '---';
    if (focuserConnected) {
      if (focuserPosition != null) {
        focusValue = focuserPosition.toString();
      } else {
        focusValue = 'N/A';
      }
    }

    return _GlassCard(
      colors: colors,
      padding: const EdgeInsets.all(0),
      child: Row(
        children: [
          _QuickStatItem(
            icon: LucideIcons.thermometer,
            label: 'Sensor',
            value: tempValue,
            colors: colors,
            isFirst: true,
          ),
          _QuickStatItem(
            icon: LucideIcons.focus,
            label: 'Focus',
            value: focusValue,
            colors: colors,
          ),
          _QuickStatItem(
            icon: LucideIcons.target,
            label: 'HFR',
            value: hfrValue,
            colors: colors,
          ),
          _QuickStatItem(
            icon: LucideIcons.activity,
            label: 'RMS',
            value: rmsValue,
            colors: colors,
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _QuickStatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool isFirst;
  final bool isLast;

  const _QuickStatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  right: BorderSide(
                    color: colors.border.withValues(alpha: 0.5),
                  ),
                ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: colors.primary),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TonightCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _TonightCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twilight = ref.watch(twilightTimesProvider);
    final moonInfo = ref.watch(moonInfoProvider);

    // Use select() to only watch the time field
    final now = ref.watch(observationTimeProvider.select((s) => s.time));
    
    // Format astro twilight time
    String astroTwilightTime = '--:--';
    if (twilight.astronomicalDusk != null) {
      final dusk = twilight.astronomicalDusk!;
      // If dusk is in the future (relative to simulation time), show it
      if (dusk.isAfter(now)) {
        astroTwilightTime = '${dusk.hour.toString().padLeft(2, '0')}:${dusk.minute.toString().padLeft(2, '0')}';
      } else {
        // Dusk already passed, show dawn
        if (twilight.astronomicalDawn != null) {
          final dawn = twilight.astronomicalDawn!;
          astroTwilightTime = '${dawn.hour.toString().padLeft(2, '0')}:${dawn.minute.toString().padLeft(2, '0')}';
        }
      }
    }
    
    // Format moon info
    String moonValue = '${moonInfo.illumination.toStringAsFixed(0)}%';
    if (moonInfo.moonrise != null) {
      final rise = moonInfo.moonrise!;
      moonValue += ' @ ${rise.hour.toString().padLeft(2, '0')}:${rise.minute.toString().padLeft(2, '0')}';
    }
    
    // Calculate imaging window (darkness duration)
    String imagingWindow = '--:--';
    if (twilight.astronomicalDusk != null && twilight.astronomicalDawn != null) {
      final duration = twilight.astronomicalDawn!.difference(twilight.astronomicalDusk!);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      imagingWindow = '${hours}h ${minutes}m';
    }
    
    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.moon,
                  size: 16,
                  color: colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Tonight',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          _TonightRow(
            icon: LucideIcons.sunset,
            label: 'Astro Twilight',
            value: astroTwilightTime,
            colors: colors,
          ),
          const SizedBox(height: 8),
          _TonightRow(
            icon: LucideIcons.moonStar,
            label: 'Moon',
            value: moonValue,
            colors: colors,
          ),
          const SizedBox(height: 8),
          _TonightRow(
            icon: LucideIcons.timer,
            label: 'Imaging Window',
            value: imagingWindow,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _TonightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _TonightRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _QuickActionsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const _QuickActionsCard({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch mount capabilities to gate Park button
    final mountState = ref.watch(mountStateProvider);
    final mountCapabilitiesAsync = ref.watch(
        mountCapabilitiesProvider(mountState.deviceId ?? ''));
    final mountCapabilities = mountCapabilitiesAsync.valueOrNull;

    return _GlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.camera,
                  label: 'Snapshot',
                  colors: colors,
                  onTap: () async {
                    try {
                      final settings = ref.read(exposureSettingsProvider);
                      final imagingService = ref.read(imagingServiceProvider);
                      final sessionNotifier = ref.read(sessionStateProvider.notifier);
                      
                      sessionNotifier.setCapturing(true);
                      
                      final result = await imagingService.captureImage(
                        settings: settings,
                        targetName: ref.read(sessionStateProvider).targetName,
                      );
                      
                      if (result != null) {
                        ref.read(currentImageProvider.notifier).state = result;
                        ref.read(lastImageStatsProvider.notifier).state = result.stats;
                        sessionNotifier.recordExposureComplete(
                          exposureTime: settings.exposureTime,
                          hfr: result.stats.hfr,
                        );
                        
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Snapshot captured')),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Snapshot failed: $e')),
                        );
                      }
                    } finally {
                      ref.read(sessionStateProvider.notifier).setCapturing(false);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.focus,
                  label: 'Autofocus',
                  colors: colors,
                  onTap: () async {
                    final cameraState = ref.read(cameraStateProvider);
                    final focuserState = ref.read(focuserStateProvider);
                    
                    if (cameraState.connectionState != DeviceConnectionState.connected) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Camera not connected')),
                        );
                      }
                      return;
                    }
                    
                    if (focuserState.connectionState != DeviceConnectionState.connected) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Focuser not connected')),
                        );
                      }
                      return;
                    }
                    
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Autofocus: Use Sequencer for full autofocus routine'),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.crosshair,
                  label: 'Center',
                  colors: colors,
                  onTap: () async {
                    // Check if we have a target set
                    final session = ref.read(sessionStateProvider);
                    final targetRa = session.targetRa;
                    final targetDec = session.targetDec;
                    
                    if (targetRa == null || targetDec == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No target set. Please set a target first.'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                      return;
                    }
                    
                    // Show centering dialog
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => _CenteringDialog(
                          ref: ref,
                          targetRa: targetRa,
                          targetDec: targetDec,
                          targetName: session.targetName ?? 'Target',
                          colors: colors,
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: LucideIcons.parkingCircle,
                  label: 'Park',
                  colors: colors,
                  // Gate on canPark capability
                  onTap: (mountCapabilities?.canPark ?? true)
                      ? () async {
                          try {
                            final deviceService = ref.read(deviceServiceProvider);
                            await deviceService.parkMount();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Mount parked')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to park mount: $e')),
                              );
                            }
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.colors,
    this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.colors.primary.withValues(alpha: 0.1)
                : widget.colors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered ? widget.colors.primary : widget.colors.border,
            ),
          ),
          child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              size: 16,
              color: _isHovered
                  ? widget.colors.primary
                  : widget.colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _isHovered
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;
  final EdgeInsets padding;

  const _GlassCard({
    required this.colors,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Centering dialog for plate solving and centering on target
class _CenteringDialog extends StatefulWidget {
  final WidgetRef ref;
  final double targetRa;
  final double targetDec;
  final String targetName;
  final NightshadeColors colors;

  const _CenteringDialog({
    required this.ref,
    required this.targetRa,
    required this.targetDec,
    required this.targetName,
    required this.colors,
  });

  @override
  State<_CenteringDialog> createState() => _CenteringDialogState();
}

class _CenteringDialogState extends State<_CenteringDialog> {
  String _status = 'Initializing...';
  bool _isRunning = true;
  int _iteration = 0;
  static const int _maxIterations = 3;
  double? _lastRaError;
  double? _lastDecError;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _runCentering();
  }

  Future<void> _runCentering() async {
    try {
      final imagingService = widget.ref.read(imagingServiceProvider);
      final deviceService = widget.ref.read(deviceServiceProvider);
      final settings = widget.ref.read(appSettingsProvider).value;
      final astapPath = settings?.astapPath ?? '';

      // Use user-configured exposure settings for centering captures
      final userSettings = widget.ref.read(exposureSettingsProvider);
      final centeringSettings = ExposureSettings(
        exposureTime: userSettings.exposureTime > 0 ? userSettings.exposureTime : 5.0,
        gain: userSettings.gain,
        offset: userSettings.offset,
        binningX: userSettings.binningX > 0 ? userSettings.binningX : 2,
        binningY: userSettings.binningY > 0 ? userSettings.binningY : 2,
      );

      while (_iteration < _maxIterations && _isRunning) {
        _iteration++;

        // Step 1: Take an image
        setState(() => _status = 'Capturing image (attempt $_iteration/$_maxIterations)...');

        final image = await imagingService.captureImage(
          settings: centeringSettings,
          targetName: 'center_${widget.targetName}',
        );
        
        if (image == null || image.filePath == null) {
          setState(() => _status = 'Failed to capture image');
          return;
        }
        
        // Step 2: Plate solve
        setState(() => _status = 'Plate solving...');

        // PlateSolveService tries backend.plateSolve() first (works for both local and remote)
        // Only falls back to local solver if backend fails
        final executablePath = await PlateSolverUtils.findAstapExecutable(astapPath);

        final result = await widget.ref.read(plateSolveServiceProvider).solve(
          image.filePath!,
          PlateSolverConfig(
            type: PlateSolverType.astap,
            hintRa: widget.targetRa,
            hintDec: widget.targetDec,
            searchRadius: 15.0,
            // Provide path for local fallback - backend is tried first
            executablePath: executablePath ?? '',
          ),
        );
        
        if (!result.success || result.ra == null || result.dec == null) {
          setState(() => _status = 'Plate solve failed: ${result.errorMessage ?? "Unknown error"}');
          return;
        }
        
        // Step 3: Calculate error
        // RA is in hours, Dec is in degrees. Convert both to arcsec for display.
        // 1 hour RA = 15 degrees = 54000 arcsec
        final raErrorArcsec = (result.ra! - widget.targetRa) * 15.0 * 3600.0; // hours to arcsec
        final decErrorArcsec = (result.dec! - widget.targetDec) * 3600.0; // degrees to arcsec
        final totalErrorArcsec = math.sqrt(raErrorArcsec * raErrorArcsec + decErrorArcsec * decErrorArcsec);
        
        setState(() {
          _lastRaError = raErrorArcsec;
          _lastDecError = decErrorArcsec;
          _status = 'Error: ${totalErrorArcsec.toStringAsFixed(1)}" (RA: ${raErrorArcsec.toStringAsFixed(1)}", Dec: ${decErrorArcsec.toStringAsFixed(1)}")';
        });
        
        // Check if centered enough (within 30 arcseconds)
        if (totalErrorArcsec < 30.0) {
          setState(() {
            _success = true;
            _status = 'Centered! Error: ${totalErrorArcsec.toStringAsFixed(1)}"';
          });
          break;
        }
        
        // Step 4: Slew to corrected position
        setState(() => _status = 'Slewing to corrected position...');

        // Convert arcsec error back to coordinate units for correction
        // RA: arcsec / (15 * 3600) = hours, Dec: arcsec / 3600 = degrees
        final newRa = widget.targetRa - (raErrorArcsec / (15.0 * 3600.0)); // Correct for offset (hours)
        final newDec = widget.targetDec - (decErrorArcsec / 3600.0); // Correct for offset (degrees)
        
        await deviceService.slewMountToCoordinates(newRa, newDec);
        
        // Wait for slew to complete
        await Future.delayed(const Duration(seconds: 2));
        
        // Small delay before next iteration
        await Future.delayed(const Duration(seconds: 1));
      }
      
      if (!_success && _iteration >= _maxIterations) {
        setState(() {
          _status = 'Max iterations reached. Last error: RA ${_lastRaError?.toStringAsFixed(1)}", Dec ${_lastDecError?.toStringAsFixed(1)}"';
        });
      }
      
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: widget.colors.border),
      ),
      title: Row(
        children: [
          Icon(
            _success ? LucideIcons.checkCircle : LucideIcons.crosshair,
            color: _success ? widget.colors.success : widget.colors.primary,
          ),
          const SizedBox(width: 12),
          Text(
            'Centering on ${widget.targetName}',
            style: TextStyle(
              color: widget.colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isRunning)
            const LinearProgressIndicator()
          else if (_success)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.colors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.colors.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.checkCircle, color: widget.colors.success, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Target centered successfully!',
                      style: TextStyle(color: widget.colors.success, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text(
            _status,
            style: TextStyle(color: widget.colors.textSecondary, fontSize: 14),
          ),
          if (_lastRaError != null || _lastDecError != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('RA Error:', style: TextStyle(color: widget.colors.textMuted, fontSize: 12)),
                Text('${_lastRaError?.toStringAsFixed(1) ?? "---"}"', 
                     style: TextStyle(color: widget.colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dec Error:', style: TextStyle(color: widget.colors.textMuted, fontSize: 12)),
                Text('${_lastDecError?.toStringAsFixed(1) ?? "---"}"', 
                     style: TextStyle(color: widget.colors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Iteration: $_iteration / $_maxIterations',
            style: TextStyle(color: widget.colors.textMuted, fontSize: 12),
          ),
        ],
      ),
      actions: [
        if (_isRunning)
          TextButton(
            onPressed: () {
              setState(() => _isRunning = false);
            },
            child: Text('Cancel', style: TextStyle(color: widget.colors.error)),
          )
        else
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close', style: TextStyle(color: widget.colors.primary)),
          ),
      ],
    );
  }
}

