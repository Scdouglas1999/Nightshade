// Run this from the planetarium package directory:
// cd packages/nightshade_planetarium
// dart run example/m31_test.dart

import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// Test script to verify M31 coordinates
/// 
/// Expected M31 coordinates:
/// RA: 00h 42m 44s = 0.7122 hours = 10.683 degrees
/// Dec: +41° 16' 9" = +41.269 degrees
void main() async {
  print('Testing M31 coordinates...\n');
  
  // Load DSOs from OpenNGC
  final catalog = OpenNgcDsoCatalog(magnitudeLimit: 20.0);
  final dsos = await catalog.loadObjects();
  
  // Find M31
  final m31 = dsos.where((d) => d.catalogIds.contains('M31') || d.name == 'M31').firstOrNull;
  
  if (m31 == null) {
    print('ERROR: M31 not found in catalog!');
    return;
  }
  
  print('M31 found!');
  print('Name: ${m31.name}');
  print('ID: ${m31.id}');
  print('Catalog IDs: ${m31.catalogIds}');
  print('');
  
  print('=== Stored Coordinates ===');
  print('coordinates.ra: ${m31.coordinates.ra}');
  print('coordinates.dec: ${m31.coordinates.dec}');
  print('');
  
  print('=== Interpreted as Hours (what code assumes) ===');
  print('RA Hours: ${m31.coordinates.ra}');
  print('RA Degrees (raHours * 15): ${m31.coordinates.ra * 15}');
  print('Dec Degrees: ${m31.coordinates.dec}');
  print('');
  
  print('=== Expected Actual Values ===');
  print('RA Hours: 0.7122');
  print('RA Degrees: 10.683');
  print('Dec Degrees: +41.269');
  print('');
  
  print('=== Analysis ===');
  final expectedRaDegrees = 10.683;
  final expectedRaHours = 0.7122;
  final expectedDec = 41.269;
  
  if ((m31.coordinates.dec - expectedDec).abs() < 0.1) {
    print('✓ Dec looks correct (${m31.coordinates.dec} ≈ $expectedDec)');
  } else {
    print('✗ Dec is wrong!');
  }
  
  if ((m31.coordinates.ra - expectedRaDegrees).abs() < 0.1) {
    print('✓ RA is stored in DEGREES (${m31.coordinates.ra} ≈ $expectedRaDegrees)');
    print('  This means coordinates.ra is in DEGREES, not hours!');
    print('');
    print('BUG CONFIRMED:');
    print('  - OpenNGC parser stores RA in DEGREES');
    print('  - Code assumes RA is in HOURS');
    print('  - When converting to degrees, it multiplies by 15 again');
    print('  - For M31: 10.683° * 15 = 160.245° (WRONG!)');
    print('  - Should be: 10.683° (CORRECT)');
  } else if ((m31.coordinates.ra - expectedRaHours).abs() < 0.01) {
    print('RA is stored in hours (${m31.coordinates.ra} ≈ $expectedRaHours)');
    print('No bug detected - RA units are correct');
  } else {
    print('✗ RA value doesn\'t match expected hours or degrees!');
    print('  Expected hours: $expectedRaHours');
    print('  Expected degrees: $expectedRaDegrees');
    print('  Actual: ${m31.coordinates.ra}');
  }
}

