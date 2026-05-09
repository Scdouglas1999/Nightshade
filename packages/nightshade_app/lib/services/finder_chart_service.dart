import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Configuration for finder chart rendering
class FinderChartConfig {
  /// Whether to use inverted colors (white background, black stars) for printing
  final bool printMode;

  /// Resolution of the rendered sky chart in pixels (width = height)
  final int chartResolution;

  /// Optional object name to display in the header
  final String? objectName;

  /// Optional object type description
  final String? objectType;

  /// Optional object magnitude
  final double? objectMagnitude;

  /// Optional object size string (e.g., "10' x 6'")
  final String? objectSize;

  /// Whether to include an object details page
  final bool includeDetailsPage;

  const FinderChartConfig({
    this.printMode = false,
    this.chartResolution = 2048,
    this.objectName,
    this.objectType,
    this.objectMagnitude,
    this.objectSize,
    this.includeDetailsPage = false,
  });
}

/// Service for generating PDF finder charts from the planetarium sky view.
///
/// Renders the current sky view to a high-resolution bitmap using the existing
/// SkyCanvasPainter, then embeds it in a PDF document with header/footer metadata.
class FinderChartService {
  FinderChartService._();

  /// Generate a PDF finder chart and save it to [outputPath].
  ///
  /// Uses the current sky view state, render config, and catalog data to produce
  /// a high-resolution chart. Throws on any rendering or I/O failure.
  static Future<void> generateChart({
    required String outputPath,
    required SkyViewState viewState,
    required SkyRenderConfig renderConfig,
    required List<Star> stars,
    required List<DeepSkyObject> dsos,
    required List<ConstellationData> constellations,
    required DateTime observationTime,
    required double latitude,
    required double longitude,
    required FinderChartConfig chartConfig,
    CelestialCoordinate? selectedObject,
    (double, double)? sunPosition,
    (double, double, double)? moonPosition,
    List<PlanetData> planets = const [],
    List<MilkyWayPoint>? milkyWayPoints,
  }) async {
    // Render the sky chart to a bitmap image
    final chartImage = await _renderSkyChart(
      viewState: viewState,
      renderConfig: renderConfig,
      stars: stars,
      dsos: dsos,
      constellations: constellations,
      observationTime: observationTime,
      latitude: latitude,
      longitude: longitude,
      chartConfig: chartConfig,
      selectedObject: selectedObject,
      sunPosition: sunPosition,
      moonPosition: moonPosition,
      planets: planets,
      milkyWayPoints: milkyWayPoints,
    );

    // Build the PDF document
    final pdf = _buildPdf(
      chartImage: chartImage,
      viewState: viewState,
      observationTime: observationTime,
      latitude: latitude,
      longitude: longitude,
      chartConfig: chartConfig,
    );

    // Write to file
    final file = File(outputPath);
    await file.writeAsBytes(await pdf.save());
  }

  /// Render the sky to a PNG byte buffer using SkyCanvasPainter.
  static Future<Uint8List> _renderSkyChart({
    required SkyViewState viewState,
    required SkyRenderConfig renderConfig,
    required List<Star> stars,
    required List<DeepSkyObject> dsos,
    required List<ConstellationData> constellations,
    required DateTime observationTime,
    required double latitude,
    required double longitude,
    required FinderChartConfig chartConfig,
    CelestialCoordinate? selectedObject,
    (double, double)? sunPosition,
    (double, double, double)? moonPosition,
    List<PlanetData> planets = const [],
    List<MilkyWayPoint>? milkyWayPoints,
  }) async {
    final resolution = chartConfig.chartResolution.toDouble();
    final size = Size(resolution, resolution);

    // Build a render config appropriate for the chart mode
    final chartRenderConfig = chartConfig.printMode
        ? _buildPrintModeConfig(renderConfig)
        : renderConfig;

    // Use a PictureRecorder to capture the SkyCanvasPainter output
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);

    if (chartConfig.printMode) {
      // White background for print mode
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = const Color(0xFFFFFFFF),
      );
    }

    // Create the painter with high-quality config (no animations)
    final painter = SkyCanvasPainter(
      viewState: viewState,
      config: chartRenderConfig,
      qualityConfig: const RenderQualityConfig.quality(),
      stars: stars,
      dsos: dsos,
      constellations: constellations,
      observationTime: observationTime,
      latitude: latitude,
      longitude: longitude,
      selectedObject: selectedObject,
      sunPosition: sunPosition,
      moonPosition: moonPosition,
      planets: planets,
      milkyWayPoints: chartConfig.printMode ? null : milkyWayPoints,
      // No animations for static chart
      animationPhase: null,
      selectionAnimationPhase: null,
      popinAnimationPhase: null,
      dsoPopinAnimationPhase: null,
      parallaxPanDelta: null,
    );

    painter.paint(canvas, size);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      chartConfig.chartResolution,
      chartConfig.chartResolution,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();

    if (byteData == null) {
      throw StateError('Failed to encode sky chart image to PNG');
    }

    return byteData.buffer.asUint8List();
  }

  /// Build a SkyRenderConfig suitable for print mode (white bg, black stars).
  static SkyRenderConfig _buildPrintModeConfig(SkyRenderConfig base) {
    return base.copyWith(
      // Disable ground/horizon glow for clean print
      showGroundPlane: false,
      showMilkyWay: false,
      showMountPosition: false,
      // High-contrast colors for print
      gridColor: const Color(0x40000000),
      constellationLineColor: const Color(0x60444444),
      eclipticColor: const Color(0x40DAA520),
      galacticPlaneColor: const Color(0x40008B8B),
      horizonColor: const Color(0x60CC3300),
      mountPositionColor: const Color(0xFFCC0000),
    );
  }

  /// Build the PDF document with chart image, header, and footer.
  static pw.Document _buildPdf({
    required Uint8List chartImage,
    required SkyViewState viewState,
    required DateTime observationTime,
    required double latitude,
    required double longitude,
    required FinderChartConfig chartConfig,
  }) {
    final pdf = pw.Document(
      title: chartConfig.objectName != null
          ? 'Finder Chart - ${chartConfig.objectName}'
          : 'Finder Chart',
      author: 'Nightshade 2.0',
      creator: 'Nightshade Astrophotography Suite',
    );

    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    final dateStr = dateFormatter.format(observationTime);

    final latStr = _formatLatitude(latitude);
    final lonStr = _formatLongitude(longitude);

    final fovStr = _formatFOV(viewState.fieldOfView);
    final raStr = _formatRA(viewState.centerRA);
    final decStr = _formatDec(viewState.centerDec);
    final projectionStr = _projectionName(viewState.projection);

    final image = pw.MemoryImage(chartImage);

    // Chart page
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Header
              _buildHeader(
                chartConfig: chartConfig,
                dateStr: dateStr,
                latStr: latStr,
                lonStr: lonStr,
              ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 8),

              // Chart image - expand to fill available space
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),

              // Footer
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              _buildFooter(
                fovStr: fovStr,
                raStr: raStr,
                decStr: decStr,
                projectionStr: projectionStr,
                magLimit: viewState.fieldOfView < 10 ? 12.0 : 6.0,
                chartConfig: chartConfig,
              ),
            ],
          );
        },
      ),
    );

    // Optional details page
    if (chartConfig.includeDetailsPage && chartConfig.objectName != null) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          build: (context) {
            return _buildDetailsPage(
              chartConfig: chartConfig,
              dateStr: dateStr,
              latStr: latStr,
              lonStr: lonStr,
              raStr: raStr,
              decStr: decStr,
              fovStr: fovStr,
              latitude: latitude,
              longitude: longitude,
              observationTime: observationTime,
              viewState: viewState,
            );
          },
        ),
      );
    }

    return pdf;
  }

  static pw.Widget _buildHeader({
    required FinderChartConfig chartConfig,
    required String dateStr,
    required String latStr,
    required String lonStr,
  }) {
    final titleText = chartConfig.objectName != null
        ? 'Finder Chart: ${chartConfig.objectName}'
        : 'Finder Chart';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                titleText,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              if (chartConfig.objectType != null)
                pw.Text(
                  chartConfig.objectType!,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              dateStr,
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Text(
              '$latStr, $lonStr',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildFooter({
    required String fovStr,
    required String raStr,
    required String decStr,
    required String projectionStr,
    required double magLimit,
    required FinderChartConfig chartConfig,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            _footerItem('FOV', fovStr),
            pw.SizedBox(width: 16),
            _footerItem('Center', '$raStr  $decStr'),
          ],
        ),
        pw.Row(
          children: [
            _footerItem('Mag limit', magLimit.toStringAsFixed(1)),
            pw.SizedBox(width: 16),
            _footerItem('Projection', projectionStr),
            if (chartConfig.printMode) ...[
              pw.SizedBox(width: 16),
              pw.Text(
                'Print mode',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey500,
                ),
              ),
            ],
          ],
        ),
        pw.Text(
          'Generated by Nightshade 2.0',
          style: const pw.TextStyle(
            fontSize: 7,
            color: PdfColors.grey500,
          ),
        ),
      ],
    );
  }

  static pw.Widget _footerItem(String label, String value) {
    return pw.Row(
      children: [
        pw.Text(
          '$label: ',
          style: const pw.TextStyle(
            fontSize: 8,
            color: PdfColors.grey600,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 8,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildDetailsPage({
    required FinderChartConfig chartConfig,
    required String dateStr,
    required String latStr,
    required String lonStr,
    required String raStr,
    required String decStr,
    required String fovStr,
    required double latitude,
    required double longitude,
    required DateTime observationTime,
    required SkyViewState viewState,
  }) {
    // Compute altitude for the chart center at observation time
    final lst = AstronomyCalculations.localSiderealTime(
      observationTime,
      longitude,
    );
    final (alt, az) = AstronomyCalculations.equatorialToHorizontal(
      raDeg: viewState.centerRA * 15.0,
      decDeg: viewState.centerDec,
      latitudeDeg: latitude,
      lstHours: lst,
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Object Details: ${chartConfig.objectName ?? "Unknown"}',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 16),

        _detailRow('Object Name', chartConfig.objectName ?? 'N/A'),
        if (chartConfig.objectType != null)
          _detailRow('Type', chartConfig.objectType!),
        if (chartConfig.objectMagnitude != null)
          _detailRow(
            'Magnitude',
            chartConfig.objectMagnitude!.toStringAsFixed(1),
          ),
        if (chartConfig.objectSize != null)
          _detailRow('Size', chartConfig.objectSize!),

        pw.SizedBox(height: 16),
        pw.Divider(thickness: 0.5, color: PdfColors.grey300),
        pw.SizedBox(height: 16),

        pw.Text(
          'Observation Context',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),

        _detailRow('Date/Time', dateStr),
        _detailRow('Location', '$latStr, $lonStr'),
        _detailRow('Right Ascension', raStr),
        _detailRow('Declination', decStr),
        _detailRow('Altitude', '${alt.toStringAsFixed(1)}\u00b0'),
        _detailRow('Azimuth', '${az.toStringAsFixed(1)}\u00b0'),
        _detailRow('Field of View', fovStr),
        _detailRow(
          'Projection',
          _projectionName(viewState.projection),
        ),

        pw.SizedBox(height: 24),
        pw.Divider(thickness: 0.5, color: PdfColors.grey300),
        pw.SizedBox(height: 8),

        pw.Text(
          'Notes',
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        // Empty box for user notes
        pw.Container(
          height: 200,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
        ),

        pw.Spacer(),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated by Nightshade 2.0',
          style: const pw.TextStyle(
            fontSize: 7,
            color: PdfColors.grey500,
          ),
        ),
      ],
    );
  }

  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Formatting helpers

  static String _formatLatitude(double lat) {
    final sign = lat >= 0 ? 'N' : 'S';
    return '${lat.abs().toStringAsFixed(4)}\u00b0$sign';
  }

  static String _formatLongitude(double lon) {
    final sign = lon >= 0 ? 'E' : 'W';
    return '${lon.abs().toStringAsFixed(4)}\u00b0$sign';
  }

  static String _formatFOV(double fovDeg) {
    if (fovDeg >= 1) {
      return '${fovDeg.toStringAsFixed(1)}\u00b0';
    } else {
      return '${(fovDeg * 60).toStringAsFixed(1)}\'';
    }
  }

  static String _formatRA(double raHours) {
    final h = raHours.floor();
    final remainder = (raHours - h) * 60;
    final m = remainder.floor();
    final s = ((remainder - m) * 60);
    return '${h}h ${m}m ${s.toStringAsFixed(1)}s';
  }

  static String _formatDec(double decDeg) {
    final sign = decDeg >= 0 ? '+' : '-';
    final d = decDeg.abs().floor();
    final remainder = (decDeg.abs() - d) * 60;
    final m = remainder.floor();
    final s = ((remainder - m) * 60).floor();
    return "$sign$d\u00b0 $m' $s\"";
  }

  static String _projectionName(SkyProjection projection) {
    switch (projection) {
      case SkyProjection.stereographic:
        return 'Stereographic';
      case SkyProjection.orthographic:
        return 'Orthographic';
      case SkyProjection.azimuthalEquidistant:
        return 'Equidistant';
    }
  }

  /// Generate a suggested filename for the chart.
  static String suggestedFilename({String? objectName}) {
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    if (objectName != null) {
      final safeName = objectName.replaceAll(RegExp(r'[^\w\s-]'), '_').trim();
      return 'finder_chart_${safeName}_$date.pdf';
    }
    return 'finder_chart_$date.pdf';
  }
}
