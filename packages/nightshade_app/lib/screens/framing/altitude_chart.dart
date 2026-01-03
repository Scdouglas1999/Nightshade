
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Altitude chart widget showing target visibility over time
class AltitudeChart extends ConsumerStatefulWidget {
  final double raHours;
  final double decDegrees;
  final String? targetName;

  const AltitudeChart({
    super.key,
    required this.raHours,
    required this.decDegrees,
    this.targetName,
  });

  @override
  ConsumerState<AltitudeChart> createState() => _AltitudeChartState();
}

class _AltitudeChartState extends ConsumerState<AltitudeChart> {
  List<FlSpot> _altitudeData = [];
  List<FlSpot> _airmassData = [];
  TwilightTimes? _twilight;
  ObjectVisibility? _visibility;
  DateTime _startTime = DateTime.now();
  DateTime _endTime = DateTime.now();
  double _currentAltitude = 0;
  double _currentAirmass = 0;
  bool _showAirmass = false;

  @override
  void initState() {
    super.initState();
    _calculateData();
  }

  @override
  void didUpdateWidget(AltitudeChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raHours != widget.raHours ||
        oldWidget.decDegrees != widget.decDegrees) {
      _calculateData();
    }
  }

  void _calculateData() {
    final settingsAsync = ref.read(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    if (settings == null) return;

    final lat = settings.latitude;
    final lon = settings.longitude;

    if (lat == 0.0 && lon == 0.0) {
      setState(() {
        _altitudeData = [];
        _airmassData = [];
      });
      return;
    }

    final now = DateTime.now();
    final raDeg = widget.raHours * 15.0;
    final decDeg = widget.decDegrees;

    // Calculate for 12 hours centered around now (6 hours back, 6 hours forward)
    // Or from sunset to sunrise if available
    _twilight = AstronomyCalculations.calculateTwilightTimes(
      date: now,
      latitudeDeg: lat,
      longitudeDeg: lon,
    );

    // Determine time range - prefer sunset to sunrise, fallback to 12 hours
    if (_twilight?.sunset != null && _twilight?.sunrise != null) {
      _startTime = _twilight!.sunset!.subtract(const Duration(hours: 1));
      _endTime = _twilight!.sunrise!.add(const Duration(hours: 1));
    } else {
      _startTime = now.subtract(const Duration(hours: 2));
      _endTime = now.add(const Duration(hours: 10));
    }

    // Calculate visibility info
    _visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: raDeg,
      decDeg: decDeg,
      date: now,
      latitudeDeg: lat,
      longitudeDeg: lon,
      minAltitude: 0,
    );

    // Calculate altitude at 10-minute intervals
    final altitudePoints = <FlSpot>[];
    final airmassPoints = <FlSpot>[];
    var time = _startTime;
    const interval = Duration(minutes: 10);

    while (time.isBefore(_endTime) || time.isAtSameMomentAs(_endTime)) {
      final x = time.difference(_startTime).inMinutes.toDouble();
      final (alt, _) = AstronomyCalculations.objectAltAz(
        raDeg: raDeg,
        decDeg: decDeg,
        dt: time,
        latitudeDeg: lat,
        longitudeDeg: lon,
      );

      altitudePoints.add(FlSpot(x, alt.clamp(-10, 90)));

      // Calculate airmass (only meaningful above horizon)
      if (alt > 0) {
        final airmass = AstronomyCalculations.airmass(alt);
        airmassPoints.add(FlSpot(x, airmass.clamp(1, 5)));
      }

      time = time.add(interval);
    }

    // Calculate current altitude
    final (currentAlt, _) = AstronomyCalculations.objectAltAz(
      raDeg: raDeg,
      decDeg: decDeg,
      dt: now,
      latitudeDeg: lat,
      longitudeDeg: lon,
    );
    _currentAltitude = currentAlt;
    _currentAirmass = currentAlt > 0 ? AstronomyCalculations.airmass(currentAlt) : 0;

    setState(() {
      _altitudeData = altitudePoints;
      _airmassData = airmassPoints;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with toggle
        Row(
          children: [
            Icon(LucideIcons.trendingUp, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(
              'Altitude',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const Spacer(),
            // Airmass toggle
            GestureDetector(
              onTap: () => setState(() => _showAirmass = !_showAirmass),
              child: Row(
                children: [
                  Icon(
                    _showAirmass ? LucideIcons.checkSquare : LucideIcons.square,
                    size: 12,
                    color: colors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Airmass',
                    style: TextStyle(fontSize: 10, color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Current values
        _buildCurrentValues(colors),
        const SizedBox(height: 8),

        // Chart
        if (_altitudeData.isEmpty)
          _buildNoLocationWarning(colors)
        else
          _buildChart(colors),

        const SizedBox(height: 8),

        // Rise/Transit/Set times
        if (_visibility != null) _buildVisibilityInfo(colors),
      ],
    );
  }

  Widget _buildCurrentValues(NightshadeColors colors) {
    return Row(
      children: [
        _buildValueChip(
          colors,
          'Alt',
          '${_currentAltitude.toStringAsFixed(1)}°',
          _currentAltitude > 30
              ? colors.success
              : _currentAltitude > 0
                  ? colors.warning
                  : colors.error,
        ),
        const SizedBox(width: 8),
        if (_currentAltitude > 0)
          _buildValueChip(
            colors,
            'Airmass',
            _currentAirmass.toStringAsFixed(2),
            _currentAirmass < 1.5
                ? colors.success
                : _currentAirmass < 2.0
                    ? colors.warning
                    : colors.error,
          ),
      ],
    );
  }

  Widget _buildValueChip(
      NightshadeColors colors, String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoLocationWarning(NightshadeColors colors) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mapPin, size: 24, color: colors.textMuted),
            const SizedBox(height: 8),
            Text(
              'Set location in Settings',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(NightshadeColors colors) {
    final now = DateTime.now();
    final nowX = now.difference(_startTime).inMinutes.toDouble();
    final totalMinutes = _endTime.difference(_startTime).inMinutes.toDouble();

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: totalMinutes,
          minY: _showAirmass ? 1 : -10,
          maxY: _showAirmass ? 5 : 90,
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: _showAirmass ? 1 : 30,
            verticalInterval: 60, // Every hour
            getDrawingHorizontalLine: (value) {
              // Highlight 30° line for altitude
              if (!_showAirmass && value == 30) {
                return FlLine(
                  color: colors.warning.withOpacity(0.5),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                );
              }
              return FlLine(
                color: colors.border.withOpacity(0.3),
                strokeWidth: 0.5,
              );
            },
            getDrawingVerticalLine: (value) {
              return FlLine(
                color: colors.border.withOpacity(0.3),
                strokeWidth: 0.5,
              );
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _showAirmass ? 1 : 30,
                getTitlesWidget: (value, meta) {
                  if (_showAirmass) {
                    if (value == 1 || value == 2 || value == 3 || value == 4) {
                      return Text(
                        value.toInt().toString(),
                        style: TextStyle(fontSize: 9, color: colors.textMuted),
                      );
                    }
                  } else {
                    if (value == 0 || value == 30 || value == 60 || value == 90) {
                      return Text(
                        '${value.toInt()}°',
                        style: TextStyle(fontSize: 9, color: colors.textMuted),
                      );
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: 120, // Every 2 hours
                getTitlesWidget: (value, meta) {
                  final time = _startTime.add(Duration(minutes: value.toInt()));
                  return Text(
                    DateFormat('HH:mm').format(time),
                    style: TextStyle(fontSize: 9, color: colors.textMuted),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: colors.border.withOpacity(0.5)),
          ),
          lineBarsData: [
            // Altitude curve
            if (!_showAirmass)
              LineChartBarData(
                spots: _altitudeData,
                isCurved: true,
                curveSmoothness: 0.2,
                color: colors.primary,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.primary.withOpacity(0.3),
                      colors.primary.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            // Airmass curve
            if (_showAirmass && _airmassData.isNotEmpty)
              LineChartBarData(
                spots: _airmassData,
                isCurved: true,
                curveSmoothness: 0.2,
                color: colors.warning,
                barWidth: 2,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
              ),
          ],
          extraLinesData: ExtraLinesData(
            verticalLines: [
              // Current time indicator
              VerticalLine(
                x: nowX.clamp(0, totalMinutes),
                color: colors.error,
                strokeWidth: 1,
                dashArray: [4, 2],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  style: TextStyle(fontSize: 8, color: colors.error),
                  labelResolver: (_) => 'Now',
                ),
              ),
              // Twilight markers
              if (_twilight?.astronomicalDusk != null)
                _twilightLine(
                  _twilight!.astronomicalDusk!,
                  colors.textMuted.withOpacity(0.5),
                  totalMinutes,
                ),
              if (_twilight?.astronomicalDawn != null)
                _twilightLine(
                  _twilight!.astronomicalDawn!,
                  colors.textMuted.withOpacity(0.5),
                  totalMinutes,
                ),
            ],
            horizontalLines: [
              // Horizon line
              if (!_showAirmass)
                HorizontalLine(
                  y: 0,
                  color: colors.error.withOpacity(0.5),
                  strokeWidth: 1,
                ),
              // Good altitude threshold (30°)
              if (!_showAirmass)
                HorizontalLine(
                  y: 30,
                  color: colors.warning.withOpacity(0.5),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
            ],
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => colors.surface,
              tooltipBorder: BorderSide(color: colors.border),
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final time =
                      _startTime.add(Duration(minutes: spot.x.toInt()));
                  final timeStr = DateFormat('HH:mm').format(time);
                  if (_showAirmass) {
                    return LineTooltipItem(
                      '$timeStr\nAirmass: ${spot.y.toStringAsFixed(2)}',
                      TextStyle(fontSize: 10, color: colors.textPrimary),
                    );
                  }
                  return LineTooltipItem(
                    '$timeStr\nAlt: ${spot.y.toStringAsFixed(1)}°',
                    TextStyle(fontSize: 10, color: colors.textPrimary),
                  );
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  VerticalLine _twilightLine(DateTime time, Color color, double maxX) {
    final x = time.difference(_startTime).inMinutes.toDouble();
    return VerticalLine(
      x: x.clamp(0, maxX),
      color: color,
      strokeWidth: 1,
      dashArray: [2, 4],
    );
  }

  Widget _buildVisibilityInfo(NightshadeColors colors) {
    final timeFormat = DateFormat('HH:mm');
    final items = <Widget>[];

    if (_visibility!.riseTime != null) {
      items.add(_buildTimeChip(
        colors,
        'Rise',
        timeFormat.format(_visibility!.riseTime!),
        LucideIcons.sunrise,
      ));
    }

    if (_visibility!.transitTime != null) {
      items.add(_buildTimeChip(
        colors,
        'Transit',
        timeFormat.format(_visibility!.transitTime!),
        LucideIcons.arrowUp,
      ));
    }

    if (_visibility!.setTime != null) {
      items.add(_buildTimeChip(
        colors,
        'Set',
        timeFormat.format(_visibility!.setTime!),
        LucideIcons.sunset,
      ));
    }

    if (_visibility!.transitAltitude != null) {
      items.add(_buildTimeChip(
        colors,
        'Max Alt',
        '${_visibility!.transitAltitude!.toStringAsFixed(1)}°',
        LucideIcons.chevronUp,
      ));
    }

    if (items.isEmpty) {
      // Check if circumpolar or never rises
      if (_visibility!.transitAltitude != null &&
          _visibility!.transitAltitude! > 0) {
        return Text(
          'Circumpolar - always visible',
          style: TextStyle(fontSize: 10, color: colors.success),
        );
      } else {
        return Text(
          'Never rises at this location',
          style: TextStyle(fontSize: 10, color: colors.error),
        );
      }
    }

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: items,
    );
  }

  Widget _buildTimeChip(
      NightshadeColors colors, String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: colors.textMuted),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 9, color: colors.textMuted),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
