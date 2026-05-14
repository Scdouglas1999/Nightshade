import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../utils/snackbar_helper.dart';

/// Panel showing focus model temperature compensation data, scatter plot,
/// prediction readout, and per-filter model tabs.
class FocusModelPanel extends ConsumerStatefulWidget {
  const FocusModelPanel({super.key});

  @override
  ConsumerState<FocusModelPanel> createState() => _FocusModelPanelState();
}

class _FocusModelPanelState extends ConsumerState<FocusModelPanel> {
  bool _isExpanded = true;
  String? _selectedFilter;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isMobile = Responsive.isMobile(context);

    final activeProfile = ref.watch(activeEquipmentProfileProvider);
    if (activeProfile == null) {
      return const SizedBox.shrink();
    }

    final profileId = activeProfile.id.toString();
    final focusService = ref.watch(focusModelServiceProvider);
    final profileData = focusService.getProfileData(profileId);
    final focuserState = ref.watch(focuserStateProvider);
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final tempCompEnabled = settings?.tempCompensation ?? false;

    final model = profileData?.temperatureModel;
    final dataPoints = profileData?.dataPoints ?? [];

    // Get per-filter data points
    final filterNames = _getFilterNames(dataPoints);

    // Filter data points by selected filter (null means all)
    final displayPoints = _selectedFilter == null
        ? dataPoints
        : dataPoints.where((p) => p.filterName == _selectedFilter).toList();

    return NightshadeCard(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with expand/collapse
            _buildHeader(colors, isMobile, tempCompEnabled, model, dataPoints),
            if (_isExpanded) ...[
              SizedBox(height: isMobile ? 12 : 16),
              // Model status summary
              _buildModelStatus(colors, model, dataPoints.length),
              const SizedBox(height: 12),
              // Filter chips for per-filter selection
              if (filterNames.length > 1)
                _buildFilterChips(colors, filterNames),
              if (filterNames.length > 1) const SizedBox(height: 12),
              // Scatter plot
              _buildScatterPlot(colors, displayPoints, model, isMobile),
              const SizedBox(height: 12),
              // Current prediction readout
              _buildPredictionReadout(
                  colors, focuserState, profileId, focusService),
              const SizedBox(height: 12),
              // Actions row
              _buildActionsRow(colors, profileId, focusService, dataPoints),
            ],
          ],
        ),
      ),
    );
  }

  /// Collects unique filter names from data points.
  List<String> _getFilterNames(List<FocusHistoryPoint> points) {
    final names = <String>{};
    for (final p in points) {
      if (p.filterName != null) {
        names.add(p.filterName!);
      }
    }
    final sorted = names.toList()..sort();
    return sorted;
  }

  Widget _buildHeader(
    NightshadeColors colors,
    bool isMobile,
    bool tempCompEnabled,
    FocusModel? model,
    List<FocusHistoryPoint> dataPoints,
  ) {
    return InkWell(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          Icon(
            _isExpanded
                ? LucideIcons.chevronDown
                : LucideIcons.chevronRight,
            size: 16,
            color: colors.textMuted,
          ),
          const SizedBox(width: 8),
          Text(
            'Temperature Compensation',
            style: TextStyle(
              fontSize: isMobile ? 13 : 14,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          // Status badge
          _TempCompBadge(
            isEnabled: tempCompEnabled,
            model: model,
            pointCount: dataPoints.length,
          ),
          const Spacer(),
          // Compact info when collapsed
          if (!_isExpanded && model != null)
            Text(
              '${model.slope.toStringAsFixed(1)} steps/°C  R²=${model.rSquared.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModelStatus(
    NightshadeColors colors,
    FocusModel? model,
    int totalPoints,
  ) {
    if (model == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.info, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                totalPoints == 0
                    ? 'No focus data collected yet. Run autofocus at different temperatures to build a model.'
                    : 'Collecting data ($totalPoints point${totalPoints == 1 ? '' : 's'}). Need at least 3 temperature buckets for a model.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        // Slope
        _ModelStat(
          label: 'Slope',
          value: '${model.slope.toStringAsFixed(1)} steps/°C',
          colors: colors,
        ),
        const SizedBox(width: 16),
        // Intercept
        _ModelStat(
          label: 'Intercept',
          value: '${model.intercept.toStringAsFixed(0)} steps',
          colors: colors,
        ),
        const SizedBox(width: 16),
        // R²
        _ModelStat(
          label: 'R²',
          value: model.rSquared.toStringAsFixed(3),
          colors: colors,
          valueColor: _rSquaredColor(model.rSquared, colors),
        ),
        const SizedBox(width: 16),
        // Data points
        _ModelStat(
          label: 'Points',
          value: '${model.dataPointCount}',
          colors: colors,
        ),
        const Spacer(),
        // Quality badge
        _QualityBadge(model: model, colors: colors),
      ],
    );
  }

  Color _rSquaredColor(double rSquared, NightshadeColors colors) {
    if (rSquared >= 0.9) return colors.success;
    if (rSquared >= 0.7) return colors.warning;
    return colors.error;
  }

  Widget _buildFilterChips(NightshadeColors colors, List<String> filterNames) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            isSelected: _selectedFilter == null,
            onTap: () => setState(() => _selectedFilter = null),
            colors: colors,
          ),
          const SizedBox(width: 6),
          ...filterNames.map((name) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _FilterChip(
                  label: name,
                  isSelected: _selectedFilter == name,
                  onTap: () => setState(() => _selectedFilter = name),
                  colors: colors,
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildScatterPlot(
    NightshadeColors colors,
    List<FocusHistoryPoint> points,
    FocusModel? model,
    bool isMobile,
  ) {
    return Container(
      height: isMobile ? 160 : 200,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: points.isEmpty
          ? Center(
              child: Text(
                'No data points to display',
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: CustomPaint(
                painter: _TemperatureFocusPlotPainter(
                  points: points,
                  model: model,
                  accentColor: colors.accent,
                  gridColor: colors.border,
                  textColor: colors.textMuted,
                  lineColor: colors.primary,
                  pointColor: colors.accent,
                  warningColor: colors.warning,
                ),
                size: Size.infinite,
              ),
            ),
    );
  }

  Widget _buildPredictionReadout(
    NightshadeColors colors,
    FocuserState focuserState,
    String profileId,
    FocusModelService focusService,
  ) {
    final currentTemp = focuserState.temperature;
    if (currentTemp == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.thermometer, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              'No temperature reading available from focuser',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    final prediction = focusService.predictFocusPosition(
      profileId: profileId,
      currentTemperature: currentTemp,
    );

    if (prediction == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.thermometer, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              'Current: ${currentTemp.toStringAsFixed(1)}°C',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(width: 12),
            Text(
              'Model not yet reliable enough for predictions',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.thermometer, size: 16, color: colors.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Temperature',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
              ),
              Text(
                '${currentTemp.toStringAsFixed(1)}°C',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Icon(LucideIcons.arrowRight, size: 14, color: colors.textMuted),
          const SizedBox(width: 24),
          Icon(LucideIcons.focus, size: 16, color: colors.primary),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Predicted Focus',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
              ),
              Text(
                '${prediction.position}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _confidenceColor(prediction.confidence, colors)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              prediction.confidenceDescription,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _confidenceColor(prediction.confidence, colors),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _confidenceColor(double confidence, NightshadeColors colors) {
    if (confidence >= 0.9) return colors.success;
    if (confidence >= 0.7) return colors.warning;
    return colors.error;
  }

  Widget _buildActionsRow(
    NightshadeColors colors,
    String profileId,
    FocusModelService focusService,
    List<FocusHistoryPoint> dataPoints,
  ) {
    return Row(
      children: [
        NightshadeButton(
          label: 'Clear Model',
          icon: LucideIcons.trash2,
          size: ButtonSize.small,
          variant: ButtonVariant.outline,
          onPressed: dataPoints.isEmpty
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: colors.surface,
                      title: Text(
                        'Clear Focus Model?',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                      content: Text(
                        'This will delete all ${dataPoints.length} collected focus data points '
                        'and the temperature compensation model for this profile. '
                        'This cannot be undone.',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                      actions: [
                        NightshadeButton(
                          label: 'Cancel',
                          variant: ButtonVariant.ghost,
                          size: ButtonSize.small,
                          onPressed: () => Navigator.of(ctx).pop(false),
                        ),
                        NightshadeButton(
                          label: 'Clear',
                          variant: ButtonVariant.destructive,
                          size: ButtonSize.small,
                          onPressed: () => Navigator.of(ctx).pop(true),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await focusService.clearProfileData(profileId);
                    if (mounted) {
                      setState(() {});
                      context
                          .showSuccessSnackBar('Focus model data cleared.');
                    }
                  }
                },
        ),
        const Spacer(),
        if (dataPoints.isNotEmpty)
          Text(
            'Last updated: ${_formatLastUpdated(dataPoints.last.timestamp)}',
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
      ],
    );
  }

  String _formatLastUpdated(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Small status badge shown in the header row.
class _TempCompBadge extends StatelessWidget {
  final bool isEnabled;
  final FocusModel? model;
  final int pointCount;

  const _TempCompBadge({
    required this.isEnabled,
    required this.model,
    required this.pointCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    String label;
    Color badgeColor;

    if (!isEnabled) {
      label = 'Disabled';
      badgeColor = colors.textMuted;
    } else if (model == null) {
      label = pointCount == 0 ? 'No Data' : 'Building...';
      badgeColor = colors.warning;
    } else if (model!.isReliable) {
      label = 'Active';
      badgeColor = colors.success;
    } else {
      label = 'Low Confidence';
      badgeColor = colors.warning;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: badgeColor,
        ),
      ),
    );
  }
}

/// Displays a single model statistic (label + value).
class _ModelStat extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? valueColor;

  const _ModelStat({
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: colors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: valueColor ?? colors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// R² quality badge: green for good, yellow for fair, red for poor.
class _QualityBadge extends StatelessWidget {
  final FocusModel model;
  final NightshadeColors colors;

  const _QualityBadge({required this.model, required this.colors});

  @override
  Widget build(BuildContext context) {
    String label;
    Color badgeColor;

    if (model.rSquared >= 0.9) {
      label = 'Excellent';
      badgeColor = colors.success;
    } else if (model.rSquared >= 0.7) {
      label = 'Good';
      badgeColor = colors.success;
    } else if (model.rSquared >= 0.5) {
      label = 'Fair';
      badgeColor = colors.warning;
    } else {
      label = 'Poor';
      badgeColor = colors.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: badgeColor,
        ),
      ),
    );
  }
}

/// Filter chip for selecting which filter's data to display.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.1)
              : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isSelected ? colors.primary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// CustomPainter that draws a temperature vs focus position scatter plot
/// with a regression line overlay.
class _TemperatureFocusPlotPainter extends CustomPainter {
  final List<FocusHistoryPoint> points;
  final FocusModel? model;
  final Color accentColor;
  final Color gridColor;
  final Color textColor;
  final Color lineColor;
  final Color pointColor;
  final Color warningColor;

  _TemperatureFocusPlotPainter({
    required this.points,
    required this.model,
    required this.accentColor,
    required this.gridColor,
    required this.textColor,
    required this.lineColor,
    required this.pointColor,
    required this.warningColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const leftPadding = 55.0;
    const rightPadding = 16.0;
    const topPadding = 12.0;
    const bottomPadding = 28.0;

    final plotRect = Rect.fromLTRB(
      leftPadding,
      topPadding,
      size.width - rightPadding,
      size.height - bottomPadding,
    );

    if (plotRect.width <= 0 || plotRect.height <= 0) return;

    // Calculate data bounds
    double minTemp = points.first.temperatureCelsius;
    double maxTemp = points.first.temperatureCelsius;
    double minPos = points.first.focusPosition.toDouble();
    double maxPos = points.first.focusPosition.toDouble();

    for (final p in points) {
      if (p.temperatureCelsius < minTemp) minTemp = p.temperatureCelsius;
      if (p.temperatureCelsius > maxTemp) maxTemp = p.temperatureCelsius;
      if (p.focusPosition < minPos) minPos = p.focusPosition.toDouble();
      if (p.focusPosition > maxPos) maxPos = p.focusPosition.toDouble();
    }

    // Add padding to data range
    final tempRange = (maxTemp - minTemp).abs();
    final posRange = (maxPos - minPos).abs();
    final tempPad = tempRange < 1 ? 2.0 : tempRange * 0.1;
    final posPad = posRange < 10 ? 100.0 : posRange * 0.1;

    minTemp -= tempPad;
    maxTemp += tempPad;
    minPos -= posPad;
    maxPos += posPad;

    // Mapping functions
    double mapX(double temp) {
      return plotRect.left +
          (temp - minTemp) / (maxTemp - minTemp) * plotRect.width;
    }

    double mapY(double pos) {
      return plotRect.bottom -
          (pos - minPos) / (maxPos - minPos) * plotRect.height;
    }

    // Draw grid
    _drawGrid(canvas, plotRect, minTemp, maxTemp, minPos, maxPos, mapX, mapY);

    // Draw regression line
    if (model != null) {
      _drawRegressionLine(
          canvas, plotRect, model!, minTemp, maxTemp, mapX, mapY);
    }

    // Draw data points
    final pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;
    final pointStrokePaint = Paint()
      ..color = pointColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final p in points) {
      final x = mapX(p.temperatureCelsius);
      final y = mapY(p.focusPosition.toDouble());
      if (plotRect.contains(Offset(x, y))) {
        canvas.drawCircle(Offset(x, y), 3.5, pointPaint);
        canvas.drawCircle(Offset(x, y), 3.5, pointStrokePaint);
      }
    }

    // Draw axis labels
    _drawAxisLabels(canvas, plotRect, minTemp, maxTemp, minPos, maxPos);
  }

  void _drawGrid(
    Canvas canvas,
    Rect plotRect,
    double minTemp,
    double maxTemp,
    double minPos,
    double maxPos,
    double Function(double) mapX,
    double Function(double) mapY,
  ) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    // Horizontal grid lines (focus position)
    final posStep = _niceStep(maxPos - minPos, 5);
    final posStart = (minPos / posStep).ceil() * posStep;
    for (double pos = posStart; pos <= maxPos; pos += posStep) {
      final y = mapY(pos);
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        gridPaint,
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: pos.toInt().toString(),
          style: TextStyle(fontSize: 9, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(plotRect.left - tp.width - 4, y - tp.height / 2),
      );
    }

    // Vertical grid lines (temperature)
    final tempStep = _niceStep(maxTemp - minTemp, 5);
    final tempStart = (minTemp / tempStep).ceil() * tempStep;
    for (double temp = tempStart; temp <= maxTemp; temp += tempStep) {
      final x = mapX(temp);
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        gridPaint,
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: '${temp.toStringAsFixed(0)}°',
          style: TextStyle(fontSize: 9, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, plotRect.bottom + 4),
      );
    }

    // Border
    final borderPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.drawRect(plotRect, borderPaint);
  }

  void _drawRegressionLine(
    Canvas canvas,
    Rect plotRect,
    FocusModel model,
    double minTemp,
    double maxTemp,
    double Function(double) mapX,
    double Function(double) mapY,
  ) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Calculate line endpoints from model
    final y1 = model.intercept + model.slope * minTemp;
    final y2 = model.intercept + model.slope * maxTemp;

    final x1 = mapX(minTemp);
    final x2 = mapX(maxTemp);
    final py1 = mapY(y1);
    final py2 = mapY(y2);

    // Clip to plot area
    canvas.save();
    canvas.clipRect(plotRect);
    canvas.drawLine(Offset(x1, py1), Offset(x2, py2), linePaint);
    canvas.restore();

    // Draw dashed confidence band (approximate using R²)
    if (model.rSquared < 1.0) {
      final bandPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;

      // Band width proportional to uncertainty
      final uncertainty = (1.0 - model.rSquared) * 200;
      final path = Path()
        ..moveTo(x1, mapY(y1 - uncertainty))
        ..lineTo(x2, mapY(y2 - uncertainty))
        ..lineTo(x2, mapY(y2 + uncertainty))
        ..lineTo(x1, mapY(y1 + uncertainty))
        ..close();

      canvas.save();
      canvas.clipRect(plotRect);
      canvas.drawPath(path, bandPaint);
      canvas.restore();
    }
  }

  void _drawAxisLabels(
    Canvas canvas,
    Rect plotRect,
    double minTemp,
    double maxTemp,
    double minPos,
    double maxPos,
  ) {
    // X-axis label
    final xLabel = TextPainter(
      text: TextSpan(
        text: 'Temperature (°C)',
        style: TextStyle(fontSize: 9, color: textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    xLabel.paint(
      canvas,
      Offset(
        plotRect.left + (plotRect.width - xLabel.width) / 2,
        plotRect.bottom + 16,
      ),
    );

    // Y-axis label (rotated)
    canvas.save();
    canvas.translate(8, plotRect.top + plotRect.height / 2);
    canvas.rotate(-math.pi / 2);
    final yLabel = TextPainter(
      text: TextSpan(
        text: 'Focus Position',
        style: TextStyle(fontSize: 9, color: textColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    yLabel.paint(canvas, Offset(-yLabel.width / 2, 0));
    canvas.restore();
  }

  /// Choose a "nice" step size for grid lines.
  double _niceStep(double range, int targetLines) {
    if (range <= 0) return 1;
    final rough = range / targetLines;
    final mag = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final normalized = rough / mag;

    double nice;
    if (normalized <= 1.5) {
      nice = 1;
    } else if (normalized <= 3.5) {
      nice = 2;
    } else if (normalized <= 7.5) {
      nice = 5;
    } else {
      nice = 10;
    }
    return nice * mag;
  }

  @override
  bool shouldRepaint(covariant _TemperatureFocusPlotPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.model != model;
  }
}
