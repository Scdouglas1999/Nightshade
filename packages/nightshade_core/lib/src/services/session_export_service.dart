import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../database/daos/sessions_dao.dart';
import '../database/daos/images_dao.dart';
import '../database/database.dart';

/// Service for exporting session data to various formats
class SessionExportService {
  final SessionsDao _sessionsDao;
  final ImagesDao _imagesDao;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final DateTime Function() _now;

  /// [nowProvider] supplies the timestamp stamped onto export filenames and
  /// inside diagnostic dumps. Defaults to [DateTime.now] for backwards
  /// compatibility; the desktop wiring overrides it with the user's
  /// chosen [Clock] so exports labelled in the operator's timezone match
  /// the rest of the session records (audit-handoff §2.1 WIRE-UP #9).
  SessionExportService({
    required SessionsDao sessionsDao,
    required ImagesDao imagesDao,
    Future<Directory> Function()? documentsDirectoryProvider,
    DateTime Function()? nowProvider,
  })  : _sessionsDao = sessionsDao,
        _imagesDao = imagesDao,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
        _now = nowProvider ?? DateTime.now;

  /// Export session images to CSV format
  ///
  /// Exports filename, exposure time, filter, HFR, FWHM, stars detected,
  /// temperature, and timestamp for each image in the session.
  ///
  /// Returns the path to the saved CSV file.
  Future<String> exportToCsv(int sessionId) async {
    final session = await _sessionsDao.getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }

    final images = await _imagesDao.getImagesForSession(sessionId);

    // CSV header
    final List<List<dynamic>> rows = [
      [
        'Filename',
        'Exposure Time (s)',
        'Filter',
        'HFR (px)',
        'FWHM (px)',
        'Stars Detected',
        'Sensor Temp (C)',
        'Timestamp',
        'Frame Type',
        'Gain',
        'Offset',
        'Binning',
        'Guiding RMS Total',
        'Accepted',
      ]
    ];

    // Add image data rows
    for (final image in images) {
      // Calculate FWHM from HFR (FWHM ≈ HFR * 2.35 for Gaussian profiles)
      final fwhm = image.hfr != null ? image.hfr! * 2.35 : null;

      rows.add([
        image.fileName,
        image.exposureDuration,
        image.filter ?? '',
        image.hfr?.toStringAsFixed(2) ?? '',
        fwhm?.toStringAsFixed(2) ?? '',
        image.starCount ?? '',
        image.sensorTemp?.toStringAsFixed(1) ?? '',
        image.capturedAt.toIso8601String(),
        image.frameType,
        image.gain ?? '',
        image.offset ?? '',
        '${image.binX}x${image.binY}',
        image.guidingRmsTotal?.toStringAsFixed(2) ?? '',
        image.isAccepted ? 'Yes' : 'No',
      ]);
    }

    // Convert to CSV
    final csv = const ListToCsvConverter().convert(rows);

    // Save to file
    final directory = await _getExportDirectory();
    final sessionName = session.name ?? 'session_$sessionId';
    final timestamp =
        _now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final fileName = '${sessionName}_$timestamp.csv';
    final filePath = path.join(directory.path, fileName);

    final file = File(filePath);
    await file.writeAsString(csv);

    return filePath;
  }

  /// Export session data to JSON format
  ///
  /// Exports full session metadata including all images and equipment profiles.
  /// Returns the path to the saved JSON file.
  Future<String> exportToJson(int sessionId) async {
    final session = await _sessionsDao.getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }

    final images = await _imagesDao.getImagesForSession(sessionId);

    // Build JSON structure
    final data = {
      'session': {
        'id': session.id,
        'name': session.name,
        'startTime': session.startTime.toIso8601String(),
        'endTime': session.endTime?.toIso8601String(),
        'status': session.status,
        'profileId': session.profileId,
        'targetId': session.targetId,
        'statistics': {
          'totalExposures': session.totalExposures,
          'successfulExposures': session.successfulExposures,
          'failedExposures': session.failedExposures,
          'totalIntegrationSecs': session.totalIntegrationSecs,
          'totalIntegrationHours': session.totalIntegrationSecs / 3600.0,
          'avgHfr': session.avgHfr,
          'avgGuidingRms': session.avgGuidingRms,
          'autofocusCount': session.autofocusCount,
        },
        'conditions': {
          'avgTemperature': session.avgTemperature,
          'avgHumidity': session.avgHumidity,
          'avgSeeing': session.avgSeeing,
        },
        'notes': session.notes,
      },
      'images': images.map((image) {
        return {
          'id': image.id,
          'fileName': image.fileName,
          'filePath': image.filePath,
          'fileFormat': image.fileFormat,
          'fileSize': image.fileSize,
          'frameType': image.frameType,
          'capturedAt': image.capturedAt.toIso8601String(),
          'exposure': {
            'duration': image.exposureDuration,
            'gain': image.gain,
            'offset': image.offset,
            'binX': image.binX,
            'binY': image.binY,
            'filter': image.filter,
          },
          'camera': {
            'sensorTemp': image.sensorTemp,
            'coolerPower': image.coolerPower,
          },
          'quality': {
            'hfr': image.hfr,
            'fwhm': image.hfr != null ? image.hfr! * 2.35 : null,
            'starCount': image.starCount,
            'background': image.background,
            'noise': image.noise,
          },
          'guiding': {
            'rmsRa': image.guidingRmsRa,
            'rmsDec': image.guidingRmsDec,
            'rmsTotal': image.guidingRmsTotal,
          },
          'mount': {
            'ra': image.mountRa,
            'dec': image.mountDec,
            'altitude': image.mountAltitude,
            'azimuth': image.mountAzimuth,
            'pierSide': image.pierSide,
          },
          'focuser': {
            'position': image.focuserPosition,
            'temp': image.focuserTemp,
          },
          'plateSolve': image.isPlateSolved
              ? {
                  'ra': image.solvedRa,
                  'dec': image.solvedDec,
                  'rotation': image.solvedRotation,
                  'pixelScale': image.solvedPixelScale,
                }
              : null,
          'isAccepted': image.isAccepted,
          'rejectionReason': image.rejectionReason,
        };
      }).toList(),
      'exportedAt': _now().toIso8601String(),
      'exportVersion': '1.0',
    };

    // Convert to JSON
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    // Save to file
    final directory = await _getExportDirectory();
    final sessionName = session.name ?? 'session_$sessionId';
    final timestamp =
        _now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final fileName = '${sessionName}_$timestamp.json';
    final filePath = path.join(directory.path, fileName);

    final file = File(filePath);
    await file.writeAsString(jsonString);

    return filePath;
  }

  /// Get or create the export directory
  Future<Directory> _getExportDirectory() async {
    final docsDir = await _documentsDirectoryProvider();
    final exportDir =
        Directory(path.join(docsDir.path, 'Nightshade', 'exports'));

    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    return exportDir;
  }

  /// Export session summary (lightweight text format)
  ///
  /// Returns a formatted string summary of the session.
  Future<String> exportSummary(int sessionId) async {
    final session = await _sessionsDao.getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }

    final images = await _imagesDao.getImagesForSession(sessionId);
    final acceptedImages = images.where((img) => img.isAccepted).toList();

    final buffer = StringBuffer();
    buffer.writeln('=' * 60);
    buffer.writeln('Nightshade Imaging Session Summary');
    buffer.writeln('=' * 60);
    buffer.writeln();
    buffer.writeln('Session: ${session.name ?? "Unnamed Session"}');
    buffer.writeln('Started: ${session.startTime}');
    buffer.writeln('Ended: ${session.endTime ?? "In Progress"}');
    buffer.writeln('Status: ${session.status}');
    buffer.writeln();
    buffer.writeln('-' * 60);
    buffer.writeln('Statistics');
    buffer.writeln('-' * 60);
    buffer.writeln('Total Exposures: ${session.totalExposures}');
    buffer.writeln('Successful: ${session.successfulExposures}');
    buffer.writeln('Failed: ${session.failedExposures}');
    final totalExposures = session.totalExposures;
    final successRate = totalExposures > 0
        ? (session.successfulExposures / totalExposures * 100)
        : 0.0;
    buffer.writeln('Success Rate: ${successRate.toStringAsFixed(1)}%');
    buffer.writeln(
        'Total Integration: ${(session.totalIntegrationSecs / 3600).toStringAsFixed(2)} hours');

    if (session.avgHfr != null) {
      buffer.writeln('Average HFR: ${session.avgHfr!.toStringAsFixed(2)} px');
    }

    if (session.avgGuidingRms != null) {
      buffer.writeln(
          'Average Guiding RMS: ${session.avgGuidingRms!.toStringAsFixed(2)} "');
    }

    buffer.writeln('Autofocus Runs: ${session.autofocusCount}');
    buffer.writeln();

    if (session.avgTemperature != null ||
        session.avgHumidity != null ||
        session.avgSeeing != null) {
      buffer.writeln('-' * 60);
      buffer.writeln('Conditions');
      buffer.writeln('-' * 60);

      if (session.avgTemperature != null) {
        buffer.writeln(
            'Avg Temperature: ${session.avgTemperature!.toStringAsFixed(1)} °C');
      }

      if (session.avgHumidity != null) {
        buffer.writeln(
            'Avg Humidity: ${session.avgHumidity!.toStringAsFixed(1)} %');
      }

      if (session.avgSeeing != null) {
        buffer
            .writeln('Avg Seeing: ${session.avgSeeing!.toStringAsFixed(1)} "');
      }

      buffer.writeln();
    }

    buffer.writeln('-' * 60);
    buffer.writeln('Images Breakdown');
    buffer.writeln('-' * 60);
    buffer.writeln('Total Images: ${images.length}');
    buffer.writeln('Accepted: ${acceptedImages.length}');
    buffer.writeln('Rejected: ${images.length - acceptedImages.length}');
    buffer.writeln();

    // Group by filter
    final filterGroups = <String, List<CapturedImage>>{};
    for (final image in acceptedImages) {
      final filter = image.filter ?? 'No Filter';
      filterGroups.putIfAbsent(filter, () => []).add(image);
    }

    if (filterGroups.isNotEmpty) {
      buffer.writeln('By Filter:');
      for (final entry in filterGroups.entries) {
        final totalExp = entry.value
            .fold<double>(0, (sum, img) => sum + img.exposureDuration);
        buffer.writeln(
            '  ${entry.key}: ${entry.value.length} images, ${(totalExp / 60).toStringAsFixed(1)} min');
      }
      buffer.writeln();
    }

    if (session.notes != null && session.notes!.isNotEmpty) {
      buffer.writeln('-' * 60);
      buffer.writeln('Notes');
      buffer.writeln('-' * 60);
      buffer.writeln(session.notes);
      buffer.writeln();
    }

    buffer.writeln('=' * 60);
    buffer.writeln('Exported: ${_now()}');
    buffer.writeln('=' * 60);

    return buffer.toString();
  }

  /// Export a styled HTML session report.
  Future<String> exportToHtml(int sessionId) async {
    final session = await _sessionsDao.getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session not found: $sessionId');
    }

    final images = await _imagesDao.getImagesForSession(sessionId);
    final acceptedImages = images.where((image) => image.isAccepted).toList();
    final totalIntegrationHours = session.totalIntegrationSecs / 3600.0;
    final successRate = session.totalExposures > 0
        ? (session.successfulExposures / session.totalExposures) * 100.0
        : 0.0;

    final filterGroups = <String, List<CapturedImage>>{};
    for (final image in acceptedImages) {
      final filter = image.filter ?? 'No Filter';
      filterGroups.putIfAbsent(filter, () => <CapturedImage>[]).add(image);
    }

    final filterRows = filterGroups.entries.map((entry) {
      final totalExp = entry.value.fold<double>(
        0.0,
        (sum, img) => sum + img.exposureDuration,
      );
      return '''
        <tr>
          <td>${entry.key}</td>
          <td>${entry.value.length}</td>
          <td>${(totalExp / 60).toStringAsFixed(1)} min</td>
        </tr>
      ''';
    }).join();

    final imageRows = acceptedImages.take(20).map((image) {
      return '''
        <tr>
          <td>${image.fileName}</td>
          <td>${image.frameType}</td>
          <td>${image.filter ?? '-'}</td>
          <td>${image.exposureDuration.toStringAsFixed(1)} s</td>
          <td>${image.hfr?.toStringAsFixed(2) ?? '-'}</td>
          <td>${image.guidingRmsTotal?.toStringAsFixed(2) ?? '-'}</td>
        </tr>
      ''';
    }).join();

    final html = '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Nightshade Session Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 32px; color: #1f2937; background: #f6f7fb; }
    .hero { background: linear-gradient(135deg, #0f172a, #1d4ed8); color: white; padding: 28px; border-radius: 18px; }
    .grid { display: grid; grid-template-columns: repeat(4, minmax(120px, 1fr)); gap: 12px; margin: 20px 0; }
    .card { background: white; border-radius: 14px; padding: 16px; box-shadow: 0 10px 30px rgba(15, 23, 42, 0.08); }
    h1, h2 { margin: 0 0 12px; }
    h2 { margin-top: 24px; }
    table { width: 100%; border-collapse: collapse; background: white; border-radius: 14px; overflow: hidden; box-shadow: 0 10px 30px rgba(15, 23, 42, 0.08); }
    th, td { text-align: left; padding: 12px 14px; border-bottom: 1px solid #e5e7eb; }
    th { background: #e0e7ff; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; }
    .muted { color: #6b7280; }
    .notes { white-space: pre-wrap; }
  </style>
</head>
<body>
  <section class="hero">
    <h1>${session.name ?? "Unnamed Session"}</h1>
    <div>Started ${session.startTime.toLocal()}</div>
    <div>Ended ${session.endTime?.toLocal() ?? "In progress"} · Status ${session.status}</div>
  </section>

  <section class="grid">
    <div class="card"><div class="muted">Integration</div><strong>${totalIntegrationHours.toStringAsFixed(2)} h</strong></div>
    <div class="card"><div class="muted">Exposures</div><strong>${session.successfulExposures}/${session.totalExposures}</strong></div>
    <div class="card"><div class="muted">Success Rate</div><strong>${successRate.toStringAsFixed(1)}%</strong></div>
    <div class="card"><div class="muted">Autofocus Runs</div><strong>${session.autofocusCount}</strong></div>
  </section>

  <h2>Session Summary</h2>
  <div class="grid">
    <div class="card"><div class="muted">Average HFR</div><strong>${session.avgHfr?.toStringAsFixed(2) ?? "-"}</strong></div>
    <div class="card"><div class="muted">Guiding RMS</div><strong>${session.avgGuidingRms?.toStringAsFixed(2) ?? "-"}</strong></div>
    <div class="card"><div class="muted">Humidity</div><strong>${session.avgHumidity?.toStringAsFixed(1) ?? "-"}%</strong></div>
    <div class="card"><div class="muted">Temperature</div><strong>${session.avgTemperature?.toStringAsFixed(1) ?? "-"} C</strong></div>
  </div>

  <h2>Accepted Frames by Filter</h2>
  <table>
    <thead>
      <tr><th>Filter</th><th>Frames</th><th>Integration</th></tr>
    </thead>
    <tbody>
      ${filterRows.isEmpty ? '<tr><td colspan="3">No accepted frames recorded.</td></tr>' : filterRows}
    </tbody>
  </table>

  <h2>Accepted Frame Sample</h2>
  <table>
    <thead>
      <tr><th>Filename</th><th>Type</th><th>Filter</th><th>Exposure</th><th>HFR</th><th>Guiding RMS</th></tr>
    </thead>
    <tbody>
      ${imageRows.isEmpty ? '<tr><td colspan="6">No accepted frames recorded.</td></tr>' : imageRows}
    </tbody>
  </table>

  ${session.notes != null && session.notes!.isNotEmpty ? '<h2>Notes</h2><div class="card notes">${session.notes}</div>' : ''}
</body>
</html>
''';

    final directory = await _getExportDirectory();
    final sessionName = session.name ?? 'session_$sessionId';
    final timestamp =
        _now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final fileName = '${sessionName}_$timestamp.html';
    final filePath = path.join(directory.path, fileName);
    final file = File(filePath);
    await file.writeAsString(html);
    return filePath;
  }
}
