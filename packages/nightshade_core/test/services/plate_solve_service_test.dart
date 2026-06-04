import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// These tests pin the unit contract for every local-fallback solve parser:
/// `PlateSolveResult.ra` is in DEGREES, matching the dominant FFI/network
/// host path (Rust `PlateSolveResult.ra` reads FITS `CRVAL1` verbatim — see
/// `native/.../bridge/src/api/plate_solve.rs`). The previous parsers divided
/// CRVAL1 by 15 and returned hours, a latent 15x inconsistency that fed the
/// wrong-unit RA into the centering pipeline (which assumes degrees).
void main() {
  late ProviderContainer container;
  late PlateSolveService service;

  setUp(() {
    container = ProviderContainer();
    service = container.read(plateSolveServiceProvider);
  });

  tearDown(() {
    container.dispose();
  });

  group('RA unit contract — all parsers return degrees', () {
    test('_parseWcsFile returns RA in degrees (CRVAL1 verbatim)', () async {
      // CRVAL1 = 187.7 deg (≈ 12.513h). If the parser still divided by 15 we
      // would see ~12.513 here instead of 187.7.
      const crval1Deg = 187.7;
      const crval2Deg = 12.39;
      final tmp = await Directory.systemTemp.createTemp('ns_wcs_test');
      addTearDown(() => tmp.delete(recursive: true));
      final wcs = File('${tmp.path}/frame.wcs');
      await wcs.writeAsString(
        'CRVAL1  =       $crval1Deg / RA of reference point\n'
        'CRVAL2  =        $crval2Deg / Dec of reference point\n'
        'CDELT1  =   -0.000416667 / deg/pixel\n'
        'CDELT2  =    0.000416667 / deg/pixel\n'
        'CROTA2  =           1.25 / rotation\n',
      );

      final result = await service.parseWcsFileForTest(wcs.path);

      expect(result.success, isTrue);
      expect(result.ra, closeTo(crval1Deg, 1e-9),
          reason: 'RA must be in degrees, not hours (187.7 not 12.513)');
      expect(result.dec, closeTo(crval2Deg, 1e-9));
      // CDELT1 (deg/px) -> arcsec/px
      expect(result.pixelScale, closeTo(0.000416667 * 3600, 1e-6));
      expect(result.rotation, closeTo(1.25, 1e-9));
    });

    test('_parseAstrometryOutput returns RA in degrees', () {
      const raDeg = 187.7;
      const decDeg = 12.39;
      const output = 'Field center: (RA,Dec) = ($raDeg, $decDeg) deg.\n'
          'RA,Dec = ($raDeg,$decDeg), pixel scale 1.23 arcsec/pix.\n';

      final result = service.parseAstrometryOutputForTest(output);

      expect(result.success, isTrue);
      expect(result.ra, closeTo(raDeg, 1e-9),
          reason: 'RA must be in degrees, not hours');
      expect(result.dec, closeTo(decDeg, 1e-9));
    });

    test('_parsePlateSolve2Output returns RA in degrees', () async {
      const raDeg = 187.7;
      const decDeg = 12.39;
      final tmp = await Directory.systemTemp.createTemp('ns_apm_test');
      addTearDown(() => tmp.delete(recursive: true));
      final apm = File('${tmp.path}/frame.fit.apm');
      await apm.writeAsString('$raDeg,$decDeg,1\n');

      final result = await service.parsePlateSolve2OutputForTest(apm.path);

      expect(result.success, isTrue);
      expect(result.ra, closeTo(raDeg, 1e-9),
          reason: 'RA must be in degrees, not hours');
      expect(result.dec, closeTo(decDeg, 1e-9));
    });
  });

  group('parser failure paths fail closed (no silent success)', () {
    test('_parseWcsFile fails loud when CRVAL keywords are absent', () async {
      final tmp = await Directory.systemTemp.createTemp('ns_wcs_bad');
      addTearDown(() => tmp.delete(recursive: true));
      final wcs = File('${tmp.path}/frame.wcs');
      await wcs.writeAsString('COMMENT no coordinates here\n');

      final result = await service.parseWcsFileForTest(wcs.path);

      expect(result.success, isFalse);
      expect(result.ra, 0);
      expect(result.error, isNotNull);
    });

    test('_parseAstrometryOutput fails loud on unparseable output', () {
      final result =
          service.parseAstrometryOutputForTest('no solution in this text');

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });

    test('_parsePlateSolve2Output fails loud on non-numeric coordinates', () async {
      final tmp = await Directory.systemTemp.createTemp('ns_apm_bad');
      addTearDown(() => tmp.delete(recursive: true));
      final apm = File('${tmp.path}/frame.fit.apm');
      await apm.writeAsString('notanumber,alsobad\n');

      final result = await service.parsePlateSolve2OutputForTest(apm.path);

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });
  });
}
