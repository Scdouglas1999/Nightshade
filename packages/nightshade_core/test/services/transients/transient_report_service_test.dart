import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

TransientDetectionRow _detection({
  int id = 1,
  double raDeg = 187.7059,
  double decDeg = 12.3911,
  double? deltaMag,
  double snr = 18.0,
  String kind = 'newSource',
  String? catalogMatch,
  bool reviewed = true,
  bool dismissed = false,
}) {
  return TransientDetectionRow(
    id: id,
    tileId: 42,
    detectedAt: DateTime.utc(2026, 6, 20, 6, 30, 0),
    raDeg: raDeg,
    decDeg: decDeg,
    residualFlux: 5000.0,
    deltaMag: deltaMag,
    snr: snr,
    fwhm: 2.1,
    eccentricity: 0.1,
    positionAngleDeg: 0.0,
    kind: kind,
    catalogMatch: catalogMatch,
    confidence: 0.8,
    reviewed: reviewed,
    dismissed: dismissed,
  );
}

void main() {
  final service = TransientReportService();

  group('MPC report', () {
    test('produces an exact 80-column line', () {
      final report = service.generateMpcReport(
        detection: _detection(kind: 'movingStreak'),
        observatoryCode: 'G40',
      );
      final line = report.trimRight();
      expect(line.length, 80);
      // Observatory code lands in cols 78-80.
      expect(line.substring(77, 80), 'G40');
      // CCD note in column 14 (index 13).
      expect(line[13], 'C');
    });

    test('rejects a non-3-char observatory code', () {
      expect(
        () => service.generateMpcReport(
          detection: _detection(),
          observatoryCode: 'XX',
        ),
        throwsArgumentError,
      );
    });
  });

  group('AAVSO report', () {
    test('has the Extended File Format header + an observation row', () {
      final report = service.generateAavsoReport(
        detection: _detection(deltaMag: -0.7, catalogMatch: 'V0123 Cyg'),
        observerCode: 'ABC',
      );
      expect(report, contains('#TYPE=EXTENDED'));
      expect(report, contains('#OBSCODE=ABC'));
      expect(report, contains('#DELIM=,'));
      expect(report, contains('V0123 Cyg'));
    });

    test('refuses a detection with no magnitude change', () {
      expect(
        () => service.generateAavsoReport(
          detection: _detection(deltaMag: null),
          observerCode: 'ABC',
        ),
        throwsArgumentError,
      );
    });

    test('requires an observer code', () {
      expect(
        () => service.generateAavsoReport(
          detection: _detection(deltaMag: -0.7),
          observerCode: '   ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('TNS report', () {
    test('has a header + tab-separated data row', () {
      final report = service.generateTnsReport(
        detection: _detection(),
        reporterName: 'S. Douglas',
      );
      final lines = report.trim().split('\n');
      expect(lines, hasLength(2));
      final header = lines[0].split('\t');
      final row = lines[1].split('\t');
      expect(header.length, row.length);
      expect(header, contains('ra'));
      expect(header, contains('discovery_datetime'));
      // A new unnamed source reports as a PSN AT type.
      expect(row, contains('PSN'));
    });

    test('requires a reporter name', () {
      expect(
        () => service.generateTnsReport(
          detection: _detection(),
          reporterName: '',
        ),
        throwsArgumentError,
      );
    });
  });

  group('alert mapper', () {
    test('maps an unnamed new source to a supernova-class new alert', () {
      final alert = transientAlertFromDetection(_detection(reviewed: false));
      expect(alert.id, 'firstlight:1');
      expect(alert.type, TransientType.supernova);
      expect(alert.state, TransientAlertState.newAlert);
      expect(alert.source, TransientSource.manual);
    });

    test('maps a moving streak to an asteroid alert', () {
      final alert = transientAlertFromDetection(
        _detection(kind: 'movingStreak'),
      );
      expect(alert.type, TransientType.asteroid);
    });

    test('maps a named brightening to a variable-star alert', () {
      final alert = transientAlertFromDetection(
        _detection(
          kind: 'pointBrightening',
          deltaMag: -0.8,
          catalogMatch: 'V0123 Cyg',
        ),
      );
      expect(alert.type, TransientType.variableStar);
      expect(alert.name, 'V0123 Cyg');
      expect(alert.magnitude, closeTo(0.8, 1e-9));
    });

    test('a dismissed detection maps to a dismissed alert', () {
      final alert = transientAlertFromDetection(_detection(dismissed: true));
      expect(alert.state, TransientAlertState.dismissed);
    });
  });
}
