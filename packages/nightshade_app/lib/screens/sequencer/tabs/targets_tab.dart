import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:intl/intl.dart';

import '../../../utils/snackbar_helper.dart';

class TargetsTab extends ConsumerWidget {
  const TargetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final sequence = ref.watch(currentSequenceProvider);
    final isMobile = Responsive.isMobile(context);

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          if (isMobile) ...[
            // Mobile: stack title and buttons vertically
            Text(
              'Session Planner',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (sequence != null && sequence.targetHeaders.length > 1)
                  Expanded(
                    child: NightshadeButton(
                      label: 'Optimize',
                      icon: LucideIcons.sparkles,
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => _OptimizeOrderDialog(
                            targets: sequence.targetHeaders,
                          ),
                        );
                      },
                    ),
                  ),
                if (sequence != null && sequence.targetHeaders.length > 1)
                  const SizedBox(width: 8),
                Expanded(
                  child: NightshadeButton(
                    label: 'Add Target',
                    icon: LucideIcons.plus,
                    size: ButtonSize.small,
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const _AddTargetDialog(),
                      );
                    },
                  ),
                ),
              ],
            ),
          ] else ...[
            // Desktop: row layout
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Planner',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Visualize and optimize your imaging session',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (sequence != null && sequence.targetHeaders.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: NightshadeButton(
                      label: 'Optimize Order',
                      icon: LucideIcons.sparkles,
                      variant: ButtonVariant.outline,
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (context) => _OptimizeOrderDialog(
                            targets: sequence.targetHeaders,
                          ),
                        );
                      },
                    ),
                  ),
                NightshadeButton(
                  label: 'Add Target',
                  icon: LucideIcons.plus,
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const _AddTargetDialog(),
                    );
                  },
                ),
              ],
            ),
          ],

          SizedBox(height: isMobile ? 16 : 24),

          // Timeline Chart
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const _NightTimeline(),
              ),
            ),
          ),

          SizedBox(height: isMobile ? 12 : 24),

          Text(
            'Scheduled Targets',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Active Target List
          Expanded(
            flex: 3,
            child: sequence == null || sequence.targetHeaders.isEmpty
                ? _EmptyState(colors: colors)
                : _ActiveTargetList(colors: colors, sequence: sequence),
          ),
        ],
      ),
    );
  }
}

class _NightTimeline extends ConsumerWidget {
  const _NightTimeline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final sequence = ref.watch(currentSequenceProvider);
    final location = ref.watch(observerLocationProvider);

    // Calculate timeline range (Sunset to Sunrise, centered on midnight)
    // For simplicity in this view, we'll show 6pm to 6am local time
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 18);
    final end = start.add(const Duration(hours: 12));

    final targetGroups = sequence?.targetHeaders ?? [];

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _TimelinePainter(
            colors: colors,
            startTime: start,
            endTime: end,
            targets: targetGroups,
            latitude: location.latitude,
            longitude: location.longitude,
          ),
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final NightshadeColors colors;
  final DateTime startTime;
  final DateTime endTime;
  final List<TargetHeaderNode> targets;
  final double latitude;
  final double longitude;

  _TimelinePainter({
    required this.colors,
    required this.startTime,
    required this.endTime,
    required this.targets,
    required this.latitude,
    required this.longitude,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background (Sky gradient)
    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          colors.background.withValues(alpha: 0.8), // Zenith
          colors.surface, // Horizon
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // Draw Optimal Window (Alt > 30)
    _drawOptimalWindow(canvas, size);

    // Draw Grid lines
    _drawGrid(canvas, size);

    // Draw Moon Altitude Curve
    _drawMoonCurve(canvas, size);

    // Draw Target Altitude Curves
    for (int i = 0; i < targets.length; i++) {
      final target = targets[i];
      // Assign a color based on index
      final color = [
        colors.primary,
        colors.accent,
        colors.success,
        colors.warning,
        colors.info
      ][i % 5];

      _drawAltitudeCurve(canvas, size, target, color);
    }

    // Draw Current Time Indicator
    _drawCurrentTime(canvas, size);
  }

  void _drawOptimalWindow(Canvas canvas, Size size) {
    // Highlight area above 30 degrees
    final y30 = size.height - (30 / 90.0 * size.height);
    final paint = Paint()
      ..color = colors.success.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, y30), paint);

    // Draw clear 30 degree line
    final linePaint = Paint()
      ..color = colors.success.withValues(alpha: 0.3)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    // ..pathEffect = const DashPathEffect(5, 5); // Requires ui import or helper

    canvas.drawLine(Offset(0, y30), Offset(size.width, y30), linePaint);
  }

  void _drawMoonCurve(Canvas canvas, Size size) {
    final path = Path();
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // ..pathEffect = DashPathEffect(5, 5);

    final totalMinutes = endTime.difference(startTime).inMinutes;
    bool first = true;

    for (int i = 0; i <= totalMinutes; i += 10) {
      final time = startTime.add(Duration(minutes: i));
      final pos = AstronomyCalculations.moonPosition(time);
      final altAz = AstronomyCalculations.objectAltAz(
        raDeg: pos.$1 * 15.0,
        decDeg: pos.$2,
        dt: time,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      final x = (i / totalMinutes) * size.width;
      final y = size.height - (altAz.$1 / 90.0 * size.height);
      final clampedY = y.clamp(0.0, size.height);

      if (first) {
        path.moveTo(x, clampedY);
        first = false;
      } else {
        path.lineTo(x, clampedY);
      }
    }

    canvas.drawPath(path, paint);

    // Label for Moon
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Moon',
        style: TextStyle(color: Colors.white54, fontSize: 10),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - 40, 10));
  }

  void _drawGrid(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = colors.border.withValues(alpha: 0.5)
      ..strokeWidth = 1;

    final textStyle = TextStyle(
      color: colors.textMuted,
      fontSize: 10,
    );
    final textPainter = TextPainter(
      text: const TextSpan(text: ''),
      textDirection: ui.TextDirection.ltr,
    );

    // Horizontal lines (Altitude: 0, 30, 60, 90)
    for (int alt = 0; alt <= 90; alt += 30) {
      final y = size.height - (alt / 90.0 * size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

      textPainter.text = TextSpan(text: '$alt°', style: textStyle);
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, y - 12));
    }

    // Vertical lines (Time)
    final totalDuration = endTime.difference(startTime).inMinutes;
    for (int i = 0; i <= totalDuration; i += 60) {
      // Every hour
      final x = (i / totalDuration) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

      final time = startTime.add(Duration(minutes: i));
      textPainter.text = TextSpan(
        text: DateFormat('HH:mm').format(time),
        style: textStyle,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x + 4, size.height - 16));
    }
  }

  void _drawAltitudeCurve(
      Canvas canvas, Size size, TargetHeaderNode target, Color color) {
    final path = Path();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final shadowPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final totalMinutes = endTime.difference(startTime).inMinutes;

    // Calculate points every 10 minutes
    bool first = true;
    final shadowPath = Path();

    for (int i = 0; i <= totalMinutes; i += 10) {
      final time = startTime.add(Duration(minutes: i));
      final altAz = AstronomyCalculations.objectAltAz(
        raDeg: target.raHours * 15.0,
        decDeg: target.decDegrees,
        dt: time,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );

      final x = (i / totalMinutes) * size.width;
      final y = size.height - (altAz.$1 / 90.0 * size.height); // $1 is altitude

      // Clamp Y to not go below chart
      final clampedY = y.clamp(0.0, size.height);

      if (first) {
        path.moveTo(x, clampedY);
        shadowPath.moveTo(x, size.height);
        shadowPath.lineTo(x, clampedY);
        first = false;
      } else {
        path.lineTo(x, clampedY);
        shadowPath.lineTo(x, clampedY);
      }
    }

    shadowPath.lineTo(size.width, size.height);
    shadowPath.close();

    canvas.drawPath(shadowPath, shadowPaint);
    canvas.drawPath(path, paint);

    // Draw label near the highest altitude point (approximate transit).
    final textPainter = TextPainter(
      text: TextSpan(
        text: target.targetName,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(blurRadius: 2, color: Colors.black.withValues(alpha: 0.5)),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );

    // Find highest point on curve to place label
    // Re-calculate just the peak approx
    double peakAlt = -90;
    double peakX = 0;

    for (int i = 0; i <= totalMinutes; i += 30) {
      final time = startTime.add(Duration(minutes: i));
      final altAz = AstronomyCalculations.objectAltAz(
        raDeg: target.raHours * 15.0,
        decDeg: target.decDegrees,
        dt: time,
        latitudeDeg: latitude,
        longitudeDeg: longitude,
      );
      if (altAz.$1 > peakAlt) {
        peakAlt = altAz.$1;
        peakX = (i / totalMinutes) * size.width;
      }
    }

    if (peakAlt > 0) {
      final peakY = size.height - (peakAlt / 90.0 * size.height);
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(peakX - textPainter.width / 2, peakY - 20));
    }
  }

  void _drawCurrentTime(Canvas canvas, Size size) {
    final now = DateTime.now();
    if (now.isBefore(startTime) || now.isAfter(endTime)) return;

    final totalDuration = endTime.difference(startTime).inMinutes;
    final elapsed = now.difference(startTime).inMinutes;
    final x = (elapsed / totalDuration) * size.width;

    final paint = Paint()
      ..color = colors.error
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Now',
        style: TextStyle(color: colors.error, fontSize: 10),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x + 4, 4));
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.startTime != startTime || oldDelegate.targets != targets;
  }
}

class _ActiveTargetList extends ConsumerWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _ActiveTargetList({required this.colors, required this.sequence});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      itemCount: sequence.targetHeaders.length,
      proxyDecorator: (child, index, animation) {
        return Material(
          color: Colors.transparent,
          child: child,
        );
      },
      itemBuilder: (context, index) {
        final target = sequence.targetHeaders[index];
        // Use index-based color matching the chart
        final color = [
          colors.primary,
          colors.accent,
          colors.success,
          colors.warning,
          colors.info
        ][index % 5];

        return _TargetListItem(
          key: ValueKey(target.id),
          colors: colors,
          target: target,
          color: color,
          index: index,
          onDelete: () {
            ref.read(currentSequenceProvider.notifier).removeNode(target.id);
          },
        );
      },
      onReorder: (oldIndex, newIndex) {
        ref
            .read(currentSequenceProvider.notifier)
            .reorderTargets(oldIndex, newIndex);
      },
    );
  }
}

class _TargetListItem extends StatelessWidget {
  final NightshadeColors colors;
  final TargetHeaderNode target;
  final Color color;
  final int index;
  final VoidCallback onDelete;

  const _TargetListItem({
    super.key,
    required this.colors,
    required this.target,
    required this.color,
    required this.index,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isVeryNarrow = MediaQuery.of(context).size.width < 360;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 16,
          vertical: isMobile ? 6 : 8,
        ),
        leading: Container(
          width: isMobile ? 36 : 40,
          height: isMobile ? 36 : 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
          ),
          child: Center(
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: isMobile ? 12 : 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        title: Text(
          target.targetName,
          style: TextStyle(
            fontSize: isMobile ? 14 : 16,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          isVeryNarrow
              ? '${target.raHours.toStringAsFixed(2)}h / ${target.decDegrees.toStringAsFixed(2)}°'
              : 'RA: ${target.raHours.toStringAsFixed(4)}h  Dec: ${target.decDegrees.toStringAsFixed(4)}°',
          style: TextStyle(
              color: colors.textSecondary, fontSize: isMobile ? 11 : 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(LucideIcons.trash2,
                  size: isMobile ? 16 : 18, color: colors.error),
              onPressed: onDelete,
              tooltip: 'Remove Target',
              visualDensity:
                  isMobile ? VisualDensity.compact : VisualDensity.standard,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            if (!isVeryNarrow) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.gripVertical,
                  color: colors.textMuted, size: isMobile ? 18 : 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final NightshadeColors colors;

  const _EmptyState({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.calendarClock, size: 48, color: colors.textMuted),
          const SizedBox(height: 16),
          Text(
            'No targets scheduled',
            style: TextStyle(
              fontSize: 16,
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a target to see the plan',
            style: TextStyle(
              fontSize: 12,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTargetDialog extends ConsumerStatefulWidget {
  const _AddTargetDialog();

  @override
  ConsumerState<_AddTargetDialog> createState() => _AddTargetDialogState();
}

class _AddTargetDialogState extends ConsumerState<_AddTargetDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final searchState = ref.watch(objectSearchProvider);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 500,
          preferredHeight: 600,
          minWidth: 350,
          minHeight: 400,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Target to Session',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              // Search Bar
              TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search object (e.g. M42, NGC 7000)...',
                  hintStyle: TextStyle(color: colors.textMuted),
                  prefixIcon: Icon(LucideIcons.search, color: colors.textMuted),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) {
                  ref.read(objectSearchProvider.notifier).search(value);
                },
              ),

              const SizedBox(height: 16),

              // Results
              Expanded(
                child: searchState.isSearching
                    ? Center(
                        child: CircularProgressIndicator(color: colors.primary))
                    : searchState.results.isEmpty
                        ? Center(
                            child: Text(
                              _searchController.text.isEmpty
                                  ? 'Type to search...'
                                  : 'No results found',
                              style: TextStyle(color: colors.textMuted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: searchState.results.length,
                            separatorBuilder: (_, __) =>
                                Divider(color: colors.border, height: 1),
                            itemBuilder: (context, index) {
                              final obj = searchState.results[index];
                              return ListTile(
                                title: Text(
                                  obj.name,
                                  style: TextStyle(color: colors.textPrimary),
                                ),
                                subtitle: Text(
                                  obj.id != obj.name ? obj.id : '',
                                  style: TextStyle(color: colors.textSecondary),
                                ),
                                trailing: NightshadeButton(
                                  label: 'Add',
                                  icon: LucideIcons.plus,
                                  variant: ButtonVariant.ghost,
                                  size: ButtonSize.small,
                                  onPressed: () {
                                    ref
                                        .read(currentSequenceProvider.notifier)
                                        .addNode(
                                          TargetHeaderNode(
                                            targetName: obj.name,
                                            raHours: obj.coordinates.ra,
                                            decDegrees: obj.coordinates.dec,
                                          ),
                                        );
                                    Navigator.pop(context);
                                    if (context.mounted) {
                                      context.showSuccessSnackBar(
                                          'Added ${obj.name} to sequence');
                                    }
                                  },
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptimizeOrderDialog extends ConsumerStatefulWidget {
  final List<TargetHeaderNode> targets;

  const _OptimizeOrderDialog({required this.targets});

  @override
  ConsumerState<_OptimizeOrderDialog> createState() =>
      _OptimizeOrderDialogState();
}

class _OptimizeOrderDialogState extends ConsumerState<_OptimizeOrderDialog> {
  OptimizationStrategy _strategy = OptimizationStrategy.settingFirst;
  double _minAltitude = 30.0;
  List<AltitudeData>? _previewData;
  List<TargetHeaderNode>? _optimizedOrder;

  @override
  void initState() {
    super.initState();
    _calculatePreview();
  }

  void _calculatePreview() {
    final scheduler = ref.read(schedulerServiceProvider);
    final location = ref.read(observerLocationProvider);
    final now = DateTime.now();

    _previewData = scheduler.calculateTargetAltitudes(
      targets: widget.targets,
      observationTime: now,
      latitudeDegrees: location.latitude,
      longitudeDegrees: location.longitude,
      minAltitude: _minAltitude,
    );

    _optimizedOrder = scheduler.optimizeTargetOrder(
      targets: widget.targets,
      strategy: _strategy,
      observationTime: now,
      latitudeDegrees: location.latitude,
      longitudeDegrees: location.longitude,
      minAltitude: _minAltitude,
    );

    setState(() {});
  }

  void _applyOptimization() {
    if (_optimizedOrder == null) return;

    final notifier = ref.read(currentSequenceProvider.notifier);

    // Reorder targets to match optimized order
    for (int i = 0; i < _optimizedOrder!.length; i++) {
      final target = _optimizedOrder![i];
      final currentIndex = widget.targets.indexWhere((t) => t.id == target.id);
      if (currentIndex != i && currentIndex != -1) {
        notifier.reorderTargets(currentIndex, i);
      }
    }

    Navigator.of(context).pop();
    if (context.mounted) {
      context.showSuccessSnackBar('Target order optimized');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: Responsive.dialogConstraints(
          context,
          preferredWidth: 700,
          preferredHeight: 600,
          minWidth: 500,
          minHeight: 450,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.sparkles, color: colors.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Optimize Target Order',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Strategy Selection
              Text('Optimization Strategy', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: OptimizationStrategy.values.map((strategy) {
                  final isSelected = _strategy == strategy;
                  return ChoiceChip(
                    label: Text(_strategyLabel(strategy)),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _strategy = strategy);
                      _calculatePreview();
                    },
                    selectedColor: colors.primary.withValues(alpha: 0.3),
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // Min Altitude Slider
              Row(
                children: [
                  Text('Minimum Altitude: ${_minAltitude.toStringAsFixed(0)}°'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Slider(
                      value: _minAltitude,
                      min: 0,
                      max: 60,
                      divisions: 12,
                      onChanged: (v) {
                        setState(() => _minAltitude = v);
                        _calculatePreview();
                      },
                      activeColor: colors.primary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Preview
              Text('Preview Order', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: _optimizedOrder == null
                      ? const Center(child: CircularProgressIndicator())
                      : ListView.builder(
                          itemCount: _optimizedOrder!.length,
                          itemBuilder: (context, index) {
                            final target = _optimizedOrder![index];
                            final data = _previewData?.firstWhere(
                              (d) => d.targetId == target.id,
                            );
                            return ListTile(
                              leading: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: colors.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: colors.primary,
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(target.targetName),
                              subtitle: data != null
                                  ? Text(
                                      'Alt: ${data.currentAltitude.toStringAsFixed(1)}° '
                                      '(${data.isRising ? "Rising" : "Setting"}) '
                                      '• Transit: ${DateFormat('HH:mm').format(data.transitTime)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
                                      ),
                                    )
                                  : null,
                              trailing: Icon(
                                data?.isRising == true
                                    ? LucideIcons.trendingUp
                                    : LucideIcons.trendingDown,
                                color: data?.isRising == true
                                    ? colors.success
                                    : colors.warning,
                                size: 18,
                              ),
                            );
                          },
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  NightshadeButton(
                    onPressed: () => Navigator.of(context).pop(),
                    label: 'Cancel',
                    variant: ButtonVariant.ghost,
                    size: ButtonSize.small,
                  ),
                  const SizedBox(width: 12),
                  NightshadeButton(
                    onPressed: _applyOptimization,
                    icon: LucideIcons.check,
                    label: 'Apply Order',
                    variant: ButtonVariant.primary,
                    size: ButtonSize.small,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _strategyLabel(OptimizationStrategy strategy) {
    switch (strategy) {
      case OptimizationStrategy.transitTime:
        return 'By Transit Time';
      case OptimizationStrategy.currentAltitude:
        return 'By Current Altitude';
      case OptimizationStrategy.risingFirst:
        return 'Rising First';
      case OptimizationStrategy.settingFirst:
        return 'Setting First (Recommended)';
      case OptimizationStrategy.priority:
        return 'By Priority';
    }
  }
}
