import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../database/daos/images_dao.dart';
import '../../database/daos/science_dao.dart';
import '../../database/daos/settings_dao.dart';
import '../../database/database.dart';

/// Generates AAVSO Extended Format (Version 1.11) text files from photometry
/// measurements stored in the Nightshade database.
///
/// Reference: https://www.aavso.org/aavso-extended-file-format
///
/// The Extended Format consists of a header block followed by data lines.
/// Each data line represents one photometric measurement of a variable star.
class AavsoExportService {
  final ScienceDao _scienceDao;
  final SettingsDao _settingsDao;
  final ImagesDao _imagesDao;
  final Future<Directory> Function() _documentsDirectoryProvider;

  AavsoExportService({
    required ScienceDao scienceDao,
    required SettingsDao settingsDao,
    required ImagesDao imagesDao,
    Future<Directory> Function()? documentsDirectoryProvider,
  })  : _scienceDao = scienceDao,
        _settingsDao = settingsDao,
        _imagesDao = imagesDao,
        _documentsDirectoryProvider =
            documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  /// Export photometry data for a session to AAVSO Extended Format.
  ///
  /// [sessionId] — the imaging session containing photometry measurements.
  /// [targetStarName] — the AAVSO star designation (e.g., "SS CYG").
  /// [filterBand] — the photometric filter band (e.g., "V", "B", "R", "I",
  ///   "CV", "CR", "TG"). If null, defaults to "CV" (clear with V zeropoint).
  /// [chartId] — optional AAVSO chart ID used for comparison stars.
  ///
  /// Returns the path to the saved file.
  ///
  /// Throws if no photometry data is found or if the observer code is not set.
  Future<String> exportSession({
    required int sessionId,
    required String targetStarName,
    String? filterBand,
    String? chartId,
  }) async {
    final observerCode =
        await _settingsDao.getSetting('science.aavso.observer_code');
    if (observerCode == null || observerCode.trim().isEmpty) {
      throw const AavsoExportError(
        'AAVSO observer code is not set. '
        'Please set your observer code in Settings > Science before exporting.',
      );
    }
    if (observerCode.trim().length > 5) {
      throw AavsoExportError(
        'AAVSO observer code "${observerCode.trim()}" exceeds 5 characters. '
        'Please correct it in Settings > Science.',
      );
    }

    final measurements = await _scienceDao.getPhotometryForSession(sessionId);
    if (measurements.isEmpty) {
      throw AavsoExportError(
        'No photometry measurements found for session $sessionId.',
      );
    }

    final calibrations = await _scienceDao.getCalibrationsForSession(sessionId);

    // Build a lookup from capturedImageId -> calibration for zero-point access
    final calibrationByImage = <int, FramePhotometricCalibrationRow>{};
    for (final cal in calibrations) {
      if (cal.capturedImageId != null && cal.isCalibrated) {
        calibrationByImage[cal.capturedImageId!] = cal;
      }
    }

    // Partition measurements by role
    final targetMeasurements = <PhotometryMeasurementRow>[];
    final compStars = <String, PhotometryMeasurementRow>{};
    final checkStars = <String, PhotometryMeasurementRow>{};

    for (final m in measurements) {
      switch (m.role) {
        case 'target':
          targetMeasurements.add(m);
          break;
        case 'comparison':
          compStars.putIfAbsent(m.objectId, () => m);
          break;
        case 'check':
          checkStars.putIfAbsent(m.objectId, () => m);
          break;
      }
    }

    if (targetMeasurements.isEmpty) {
      throw AavsoExportError(
        'No target star measurements found in session $sessionId. '
        'Ensure a target star is designated in the photometry setup.',
      );
    }

    final effectiveFilter = filterBand ?? 'CV';

    // Determine comparison/check star labels from the first occurrence
    final compLabel = compStars.isNotEmpty ? compStars.keys.first : 'na';
    final checkLabel = checkStars.isNotEmpty ? checkStars.keys.first : 'na';

    final buffer = StringBuffer();

    // === Header ===
    buffer.writeln('#TYPE=Extended');
    buffer.writeln('#OBSCODE=$observerCode');
    buffer.writeln('#SOFTWARE=Nightshade 2.5.0');
    buffer.writeln('#DELIM=,');
    buffer.writeln('#DATE=JD');
    buffer.writeln('#OBSTYPE=CCD');

    // === Data lines ===
    // Extended format columns:
    // NAME,DATE,MAG,MERR,FILT,TRANS,MTYPE,CNAME,CMAG,KNAME,KMAG,AMASS,GROUP,CHART,NOTES
    for (final m in targetMeasurements) {
      final jd = _dateTimeToJd(m.timestamp);

      // Magnitude: use differential magnitude if available, otherwise skip
      if (m.differentialMagnitude == null) {
        continue;
      }
      final mag = m.differentialMagnitude!.toStringAsFixed(4);

      // Magnitude error from uncertainty field
      final merr = m.uncertainty != null && m.uncertainty! > 0
          ? m.uncertainty!.toStringAsFixed(4)
          : 'na';

      // Transformation status: NO = untransformed (we report raw differential)
      const trans = 'NO';

      // Measurement type: STD = standardized, DIFF = differential
      // Our photometry is differential by default
      const mtype = 'DIFF';

      // Comparison star magnitude — try to find a comp measurement for the
      // same capturedImageId to get a frame-matched comp mag.
      String cmag = 'na';
      if (compStars.isNotEmpty) {
        final compForFrame = measurements
            .where((row) =>
                row.role == 'comparison' &&
                row.capturedImageId == m.capturedImageId)
            .toList();
        if (compForFrame.isNotEmpty && compForFrame.first.differentialMagnitude != null) {
          cmag = compForFrame.first.differentialMagnitude!.toStringAsFixed(4);
        }
      }

      // Check star magnitude — same logic
      String kmag = 'na';
      if (checkStars.isNotEmpty) {
        final checkForFrame = measurements
            .where((row) =>
                row.role == 'check' &&
                row.capturedImageId == m.capturedImageId)
            .toList();
        if (checkForFrame.isNotEmpty && checkForFrame.first.differentialMagnitude != null) {
          kmag = checkForFrame.first.differentialMagnitude!.toStringAsFixed(4);
        }
      }

      // Airmass — compute from the captured image's mount altitude using
      // the Pickering (2002) formula for better accuracy near the horizon:
      //   airmass = 1 / sin(alt + 244.0/(165.0 + 47.0*alt^1.1))
      // Falls back to 'na' if no altitude is available.
      String amass = 'na';
      if (m.capturedImageId != null) {
        final capturedImage =
            await _imagesDao.getImageById(m.capturedImageId!);
        if (capturedImage != null &&
            capturedImage.mountAltitude != null &&
            capturedImage.mountAltitude! > 0) {
          final altDeg = capturedImage.mountAltitude!;
          final altRad = altDeg * math.pi / 180.0;
          // Pickering (2002) refraction-corrected airmass formula
          final correctionDeg =
              244.0 / (165.0 + 47.0 * math.pow(altDeg, 1.1));
          final effectiveAltRad = altRad + correctionDeg * math.pi / 180.0;
          final sinAlt = math.sin(effectiveAltRad);
          if (sinAlt > 0) {
            final airmass = (1.0 / sinAlt).clamp(1.0, 40.0);
            amass = airmass.toStringAsFixed(3);
          }
        }
      }

      // Group: all measurements from the same frame get the same group number.
      // Use the capturedImageId as the group identifier.
      final group = m.capturedImageId?.toString() ?? 'na';

      // Chart reference
      final chartRef = chartId ?? 'na';

      // Notes: include SNR if available
      final notes = m.snr != null ? 'SNR=${m.snr!.toStringAsFixed(1)}' : 'na';

      buffer.writeln(
        '${_sanitize(targetStarName)},'
        '${jd.toStringAsFixed(5)},'
        '$mag,'
        '$merr,'
        '$effectiveFilter,'
        '$trans,'
        '$mtype,'
        '${_sanitize(compLabel)},'
        '$cmag,'
        '${_sanitize(checkLabel)},'
        '$kmag,'
        '$amass,'
        '$group,'
        '$chartRef,'
        '$notes',
      );
    }

    final content = buffer.toString();

    // Validate we produced at least one data line (header is 6 lines)
    final lineCount = content.split('\n').where((l) => l.trim().isNotEmpty).length;
    if (lineCount <= 6) {
      throw const AavsoExportError(
        'No exportable measurements found. All target measurements lack '
        'differential magnitude values.',
      );
    }

    // Write to file
    final directory = await _getExportDirectory();
    final sanitizedName =
        targetStarName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final fileName = 'AAVSO_${sanitizedName}_$timestamp.txt';
    final filePath = path.join(directory.path, fileName);

    final file = File(filePath);
    await file.writeAsString(content);

    return filePath;
  }

  /// Convert a DateTime to Julian Date.
  ///
  /// Uses the standard algorithm for the proleptic Gregorian calendar.
  /// Accurate for dates after March 1, 4801 BCE.
  static double _dateTimeToJd(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.year;
    final m = utc.month;
    final d = utc.day;
    final h = utc.hour;
    final min = utc.minute;
    final s = utc.second;
    final ms = utc.millisecond;

    // Julian Day Number (integer part) using the standard formula
    final a = (14 - m) ~/ 12;
    final adjustedY = y + 4800 - a;
    final adjustedM = m + 12 * a - 3;

    final jdn = d +
        (153 * adjustedM + 2) ~/ 5 +
        365 * adjustedY +
        adjustedY ~/ 4 -
        adjustedY ~/ 100 +
        adjustedY ~/ 400 -
        32045;

    // Fractional day
    final dayFraction =
        (h - 12) / 24.0 + min / 1440.0 + s / 86400.0 + ms / 86400000.0;

    return jdn.toDouble() + dayFraction;
  }

  /// Sanitize a string for use in AAVSO CSV fields.
  /// Removes commas and trims whitespace.
  static String _sanitize(String value) {
    return value.replaceAll(',', ' ').trim();
  }

  Future<Directory> _getExportDirectory() async {
    final docs = await _documentsDirectoryProvider();
    final exportDir = Directory(path.join(docs.path, 'Nightshade', 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }
}

/// Error thrown when AAVSO export fails due to missing data or configuration.
class AavsoExportError implements Exception {
  final String message;
  const AavsoExportError(this.message);

  @override
  String toString() => 'AavsoExportError: $message';
}
