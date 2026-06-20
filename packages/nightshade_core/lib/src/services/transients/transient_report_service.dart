import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../database/database.dart' show TransientDetectionRow;

/// Which discovery network a [TransientReportService] report targets. Each has a
/// distinct, real submission format.
enum TransientReportFormat {
  /// AAVSO Extended File Format (variable-star / brightening photometry).
  aavso,

  /// Minor Planet Center 80-column optical astrometry (moving objects).
  mpc,

  /// IAU Transient Name Server bulk JSON-ish TSV report (new transients).
  tns,
}

/// Generates properly-formatted discovery reports for a confirmed transient
/// detection, ready to submit to AAVSO, the MPC, or the TNS.
///
/// These are the *real* file formats, not placeholder text:
///   * AAVSO Extended File Format (`# TYPE=EXTENDED` header + comma-separated
///     observation rows) — https://www.aavso.org/aavso-extended-file-format
///   * MPC 80-column optical astrometry — exactly 80 columns per line,
///     https://www.minorplanetcenter.net/iau/info/OpticalObs.html
///   * TNS AT-report TSV — the column set the TNS bulk-report endpoint accepts,
///     https://www.wis-tns.org/
///
/// A report is generated for *one confirmed candidate* (a [TransientDetectionRow]
/// the user has reviewed). The observer's identity (AAVSO observer code, MPC
/// observatory code) is supplied by the caller from science settings; the
/// service validates them and refuses to emit a malformed report.
class TransientReportService {
  /// Build an AAVSO Extended File Format report for [detection].
  ///
  /// AAVSO photometry needs a magnitude, so a detection whose [deltaMag] is null
  /// (a brand-new source with no template flux to difference against) cannot be
  /// reported here — the caller routes those to [generateTnsReport] instead.
  ///
  /// [observerCode] is the observer's AAVSO initials (e.g. `ABC`); [chartId] is
  /// the comparison-chart id if one was used, else `na`.
  String generateAavsoReport({
    required TransientDetectionRow detection,
    required String observerCode,
    String? starName,
    String chartId = 'na',
  }) {
    if (observerCode.trim().isEmpty) {
      throw ArgumentError('AAVSO observer code is required');
    }
    final delta = detection.deltaMag;
    if (delta == null || !delta.isFinite) {
      throw ArgumentError(
        'AAVSO photometry needs a magnitude change; this detection has none '
        '(it is a new source — use the TNS report instead)',
      );
    }

    final jd = _toJulianDate(detection.detectedAt);
    // The Extended File Format magnitude column is the reported magnitude. We do
    // not have an absolute mag here, so report the differential change relative
    // to the template (NAME carries the position so the row is unambiguous).
    final name = starName?.trim().isNotEmpty == true
        ? starName!.trim()
        : detection.catalogMatch ?? _positionName(detection);
    final mag = delta.abs().toStringAsFixed(3);
    final uncertainty = _magUncertainty(detection.snr).toStringAsFixed(3);

    final buffer = StringBuffer()
      ..writeln('#TYPE=EXTENDED')
      ..writeln('#OBSCODE=$observerCode')
      ..writeln('#SOFTWARE=Nightshade First Light')
      ..writeln('#DELIM=,')
      ..writeln('#DATE=JD')
      ..writeln('#OBSTYPE=CCD')
      // NAME,DATE,MAGNITUDE,MAGERR,FILT,TRANS,MTYPE,CNAME,CMAG,KNAME,KMAG,
      // AMASS,GROUP,CHART,NOTES
      ..writeln(
        '$name,'
        '${jd.toStringAsFixed(5)},'
        '$mag,'
        '$uncertainty,'
        'CV,' // clear filter, V-zeropoint
        'NO,' // transformed? no
        'DIF,' // differential magnitude type
        'na,na,na,na,na,na,' // comp/check star + airmass + group: unavailable
        '$chartId,'
        'Nightshade difference-image detection vs deep atlas template; '
        'SNR ${detection.snr.toStringAsFixed(1)}',
      );
    return buffer.toString();
  }

  /// Build an MPC 80-column optical astrometry line for [detection].
  ///
  /// [observatoryCode] is the 3-character MPC code; [provisionalDesignation] is
  /// the temporary id (auto-assigned `NSxxxx` when null). One detection = one
  /// observation line; multi-night linking is the caller's job (group by id).
  String generateMpcReport({
    required TransientDetectionRow detection,
    required String observatoryCode,
    String? provisionalDesignation,
  }) {
    if (observatoryCode.length != 3) {
      throw ArgumentError(
        'MPC observatory code must be exactly 3 characters, '
        'got "$observatoryCode"',
      );
    }
    final desig =
        (provisionalDesignation ??
                'NS${detection.id.toString().padLeft(4, '0')}')
            .padRight(7)
            .substring(0, 7);

    // Columns 1-5 blank (unnumbered); 6-12 designation; 13 discovery flag;
    // 14 note1 (C = CCD); 15 note2; 16-32 date; 33-44 RA; 45-56 Dec;
    // 57-65 blank; 66-70 mag; 71 band; 72-77 blank; 78-80 obs code.
    const numField = '     ';
    const discoveryFlag = ' ';
    const note1 = 'C';
    const note2 = ' ';
    final dateField = _formatMpcDate(detection.detectedAt);
    final raField = _formatMpcRa(detection.raDeg);
    final decField = _formatMpcDec(detection.decDeg);
    const blank9 = '         ';

    // Difference-imaging gives a magnitude *change*, not an absolute mag; MPC
    // accepts astrometry-only lines, so leave the magnitude blank.
    const magField = '     ';
    const band = ' ';
    const blank6 = '      ';
    final obsCode = observatoryCode.padRight(3).substring(0, 3);

    final line =
        '$numField$desig$discoveryFlag$note1$note2'
        '$dateField$raField$decField$blank9$magField$band$blank6$obsCode';
    if (line.length != 80) {
      throw StateError('MPC line length ${line.length}, expected 80: "$line"');
    }
    return '$line\n';
  }

  /// Build a TNS AT-report row (tab-separated) for [detection].
  ///
  /// The TNS bulk AT-report accepts a header line of column names followed by a
  /// data row. [reporterName] / [reporterGroup] identify the submitter.
  String generateTnsReport({
    required TransientDetectionRow detection,
    required String reporterName,
    String reporterGroup = 'Nightshade',
  }) {
    if (reporterName.trim().isEmpty) {
      throw ArgumentError('TNS reporter name is required');
    }
    final obsDate = detection.detectedAt.toUtc().toIso8601String();
    final ra = _decimalDegToSexagesimalRa(detection.raDeg);
    final dec = _decimalDegToSexagesimalDec(detection.decDeg);
    final flux = detection.deltaMag;
    final discMag = (flux != null && flux.isFinite)
        ? flux.abs().toStringAsFixed(2)
        : '';
    final remarks =
        'Nightshade difference-image detection vs deep personal-atlas template; '
        'kind=${detection.kind}; SNR=${detection.snr.toStringAsFixed(1)}; '
        'eccentricity=${detection.eccentricity.toStringAsFixed(2)}';

    final header = <String>[
      'ra',
      'dec',
      'reporting_group',
      'discovery_datetime',
      'at_type',
      'discovery_mag',
      'filter',
      'reporter',
      'remarks',
    ].join('\t');
    final row = <String>[
      ra,
      dec,
      reporterGroup,
      obsDate,
      _tnsAtType(detection),
      discMag,
      'Clear',
      reporterName.trim(),
      remarks,
    ].join('\t');
    return '$header\n$row\n';
  }

  /// Write [content] to the exports directory under [fileName] and return the
  /// absolute path.
  Future<String> writeReport({
    required String content,
    required String fileName,
  }) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(
      path.join(docsDir.path, 'Nightshade', 'exports'),
    );
    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }
    final filePath = path.join(exportDir.path, fileName);
    await File(filePath).writeAsString(content);
    return filePath;
  }

  // ── format helpers ─────────────────────────────────────────────────────────

  /// TNS AT (astronomical transient) subtype code. A new point source is `PSN`
  /// (possible SN-like), a moving streak is not a TNS target (kept generic).
  String _tnsAtType(TransientDetectionRow detection) {
    return detection.catalogMatch == null ? 'PSN' : 'Other';
  }

  /// Rough magnitude uncertainty from SNR: σ_mag ≈ 1.0857 / SNR.
  double _magUncertainty(double snr) {
    if (snr <= 0) return 9.999;
    return (1.0857 / snr).clamp(0.001, 9.999).toDouble();
  }

  String _positionName(TransientDetectionRow d) =>
      'NS J${_decimalDegToSexagesimalRa(d.raDeg).replaceAll(':', '')}'
      '${_decimalDegToSexagesimalDec(d.decDeg).replaceAll(':', '')}';

  /// Convert a UTC [DateTime] to Julian Date.
  double _toJulianDate(DateTime dt) {
    final utc = dt.toUtc();
    final y = utc.month <= 2 ? utc.year - 1 : utc.year;
    final m = utc.month <= 2 ? utc.month + 12 : utc.month;
    final a = (y / 100).floor();
    final b = 2 - a + (a / 4).floor();
    final dayFraction =
        utc.hour / 24.0 +
        utc.minute / 1440.0 +
        utc.second / 86400.0 +
        utc.millisecond / 86400000.0;
    final jd =
        (365.25 * (y + 4716)).floor() +
        (30.6001 * (m + 1)).floor() +
        utc.day +
        dayFraction +
        b -
        1524.5;
    return jd;
  }

  String _decimalDegToSexagesimalRa(double raDeg) {
    var ra = raDeg % 360.0;
    if (ra < 0) ra += 360.0;
    final hours = ra / 15.0;
    final h = hours.floor();
    final mFull = (hours - h) * 60.0;
    final m = mFull.floor();
    final s = (mFull - m) * 60.0;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toStringAsFixed(2).padLeft(5, '0')}';
  }

  String _decimalDegToSexagesimalDec(double decDeg) {
    final sign = decDeg < 0 ? '-' : '+';
    final abs = decDeg.abs();
    final d = abs.floor();
    final mFull = (abs - d) * 60.0;
    final m = mFull.floor();
    final s = (mFull - m) * 60.0;
    return '$sign${d.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toStringAsFixed(1).padLeft(4, '0')}';
  }

  String _formatMpcDate(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final fractionalDay =
        utc.hour / 24.0 +
        utc.minute / 1440.0 +
        utc.second / 86400.0 +
        utc.millisecond / 86400000.0;
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final dayWithFraction = utc.day + fractionalDay;
    final dayStr = dayWithFraction.toStringAsFixed(5).padLeft(8, '0');
    return '$year $month ${dayStr.padRight(9)}';
  }

  String _formatMpcRa(double raDegrees) {
    var ra = raDegrees % 360.0;
    if (ra < 0) ra += 360.0;
    final totalHours = ra / 15.0;
    final hours = totalHours.floor();
    final remainderMinutes = (totalHours - hours) * 60.0;
    final minutes = remainderMinutes.floor();
    final seconds = (remainderMinutes - minutes) * 60.0;
    final clamped = seconds >= 59.995 ? 59.99 : seconds;
    final secStr = clamped.toStringAsFixed(2).padLeft(5, '0').padRight(6);
    return '${hours.toString().padLeft(2, '0')} '
        '${minutes.toString().padLeft(2, '0')} '
        '$secStr';
  }

  String _formatMpcDec(double decDegrees) {
    final sign = decDegrees < 0 ? '-' : '+';
    final absDec = decDegrees.abs();
    final degrees = absDec.floor();
    final remainderMinutes = (absDec - degrees) * 60.0;
    final minutes = remainderMinutes.floor();
    final seconds = (remainderMinutes - minutes) * 60.0;
    final clamped = seconds >= 59.95 ? 59.9 : seconds;
    final secStr = clamped.toStringAsFixed(1).padLeft(4, '0').padRight(5);
    return '$sign${degrees.toString().padLeft(2, '0')} '
        '${minutes.toString().padLeft(2, '0')} '
        '$secStr';
  }
}
