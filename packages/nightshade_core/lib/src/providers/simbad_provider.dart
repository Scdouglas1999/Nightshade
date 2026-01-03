import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/annotation_data.dart';

class SimbadProvider {
  static const String _baseUrl = 'http://simbad.u-strasbg.fr/simbad/sim-tap/sync';

  Future<ObjectData?> queryByCoordinates(double ra, double dec, {double radiusArcmin = 1.0}) async {
    // ADQL Query
    final adql = '''
      SELECT TOP 1
      basic.main_id, basic.ra, basic.dec, basic.coo_err_maj, basic.coo_err_min, 
      basic.coo_err_angle, basic.otype, basic.sp_type,
      flux.V, flux.B, flux.R,
      dist.plx_value, dist.plx_err
      FROM basic
      LEFT JOIN flux ON basic.oid = flux.oidref
      LEFT JOIN dist ON basic.oid = dist.oidref
      WHERE 1=CONTAINS(POINT('ICRS', basic.ra, basic.dec), CIRCLE('ICRS', $ra, $dec, ${radiusArcmin / 60.0}))
    ''';

    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        body: {
          'request': 'doQuery',
          'lang': 'adql',
          'format': 'json',
          'query': adql,
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final data = json['data'];
        
        if (data != null && (data as List).isNotEmpty) {
          final row = data[0];
          // Parse row data (simplified mapping)
          // Note: SIMBAD JSON format is [[val1, val2, ...], ...]
          
          return ObjectData(
            description: 'Identified via SIMBAD',
            objectClass: row[6]?.toString(), // otype
            spectralType: _parseSpectralType(row[7]?.toString()),
            parallax: _parseDouble(row[11]),
            distance: _calculateDistance(_parseDouble(row[11])),
            simbadId: row[0]?.toString(),
            dataSource: 'SIMBAD',
            lastUpdated: DateTime.now(),
          );
        }
      }
    } catch (e) {
      debugPrint('[SIMBAD] Error: $e');
    }
    
    return null;
  }

  SpectralClass? _parseSpectralType(String? spType) {
    if (spType == null || spType.isEmpty) return null;
    final firstChar = spType[0].toUpperCase();
    switch (firstChar) {
      case 'O': return SpectralClass.o;
      case 'B': return SpectralClass.b;
      case 'A': return SpectralClass.a;
      case 'F': return SpectralClass.f;
      case 'G': return SpectralClass.g;
      case 'K': return SpectralClass.k;
      case 'M': return SpectralClass.m;
      default: return SpectralClass.unknown;
    }
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  double? _calculateDistance(double? parallax) {
    if (parallax == null || parallax <= 0) return null;
    return 1000.0 / parallax; // parsecs
  }
}
