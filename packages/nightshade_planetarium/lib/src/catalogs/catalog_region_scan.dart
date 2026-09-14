/// Region-scoped streaming scans for the large galaxy catalogs.
///
/// GLADE+ carries ~22 million rows and HyperLEDA ~3 million. Answering a
/// half-degree annotation query by loading either of them into memory first
/// froze the app: `File.readAsLines()` materialises every row as a Dart
/// `String` in one list, and the parse loop that follows is synchronous, so
/// once it starts no other microtask on that isolate ever runs again. On the
/// rig that presented as a total UI freeze with a multi-gigabyte working set
/// and a pinned core, with no log output, because the isolate never got back
/// to the code that logs.
///
/// These scans stream the file instead and keep only the rows inside the
/// requested cone, so peak memory is proportional to the answer rather than to
/// the catalog, and they run in a background isolate so the UI isolate is never
/// the one parsing.
library;

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

/// Cone-and-magnitude test for one streaming catalog scan.
///
/// Holds only primitives so it can be sent to a background isolate.
class CatalogRegionFilter {
  /// Cone centre right ascension, degrees.
  final double ra;

  /// Cone centre declination, degrees.
  final double dec;

  /// Cone radius, degrees.
  final double radiusDegrees;

  /// Reject objects fainter than this magnitude. Objects with no magnitude are
  /// treated as magnitude 99 (the convention the catalog loaders already use),
  /// so they are rejected whenever a cutoff is given.
  final double? maxMagnitude;

  /// Backstop against an unbounded answer. A scan that reaches this many
  /// matches stops reading and says so; it exists so a caller that asks for an
  /// absurd radius degrades into a truncated answer instead of an OOM.
  final int maxResults;

  const CatalogRegionFilter({
    required this.ra,
    required this.dec,
    required this.radiusDegrees,
    this.maxMagnitude,
    this.maxResults = defaultMaxResults,
  });

  /// Generous relative to any real field of view (a half-degree cone of GLADE+
  /// holds a few thousand rows at most), so it never truncates a legitimate
  /// annotation query — it only bounds a pathological one.
  static const int defaultMaxResults = 50000;

  /// Squared angular distance in degrees, small-angle approximation with the
  /// RA axis compressed by cos(dec) — the same identity the catalog loaders
  /// used when they filtered an in-memory spatial index.
  double _distanceSquared(double objRa, double objDec) {
    final dRa = _wrappedRaDelta(objRa) * math.cos(dec * math.pi / 180);
    final dDec = objDec - dec;
    return dRa * dRa + dDec * dDec;
  }

  /// RA difference taking the 0h/24h seam into account, so a cone straddling
  /// RA 0 does not silently lose half its objects.
  double _wrappedRaDelta(double objRa) {
    var delta = (objRa - ra) % 360.0;
    if (delta > 180.0) {
      delta -= 360.0;
    } else if (delta < -180.0) {
      delta += 360.0;
    }
    return delta;
  }

  /// Whether this object belongs in the answer.
  bool accepts({
    required double objRa,
    required double objDec,
    required double? magnitude,
  }) {
    if (maxMagnitude != null && (magnitude ?? 99) > maxMagnitude!) {
      return false;
    }
    return _distanceSquared(objRa, objDec) <= radiusDegrees * radiusDegrees;
  }

  /// Distance ordering key, nearest the cone centre first.
  double sortKey(double objRa, double objDec) =>
      _distanceSquared(objRa, objDec);
}

/// Outcome of one streaming scan: the rows that matched, plus what the scan had
/// to skip or cut short. The counts are reported rather than logged per row —
/// logging per malformed line across millions of rows is its own stall.
class CatalogRegionScan<T> {
  final List<T> objects;
  final int malformedRows;
  final bool truncated;

  const CatalogRegionScan({
    required this.objects,
    required this.malformedRows,
    required this.truncated,
  });
}

/// Stream `filePath` and keep only the rows `filter` accepts.
///
/// `parse` turns one CSV line into an object or throws; `positionOf` and
/// `magnitudeOf` read back the fields the filter needs. The first line is
/// treated as a header and skipped, matching the catalog files on disk.
///
/// Intended to be called inside `Isolate.run`, which is why it takes plain
/// functions rather than an object with state.
Future<CatalogRegionScan<T>> scanCatalogRegion<T>({
  required String filePath,
  required CatalogRegionFilter filter,
  required T Function(String line) parse,
  required ({double ra, double dec}) Function(T object) positionOf,
  required double? Function(T object) magnitudeOf,
  required String catalogName,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    throw FileSystemException('$catalogName catalog not found', filePath);
  }

  final matches = <T>[];
  var malformedRows = 0;
  var truncated = false;
  var lineNumber = 0;

  final lines = file
      .openRead()
      .transform(utf8.decoder)
      .transform(const LineSplitter());

  await for (final line in lines) {
    lineNumber++;
    if (lineNumber == 1 || line.isEmpty) {
      continue;
    }

    final T object;
    try {
      object = parse(line);
    } catch (_) {
      malformedRows++;
      continue;
    }

    final position = positionOf(object);
    if (!filter.accepts(
      objRa: position.ra,
      objDec: position.dec,
      magnitude: magnitudeOf(object),
    )) {
      continue;
    }

    matches.add(object);
    if (matches.length >= filter.maxResults) {
      truncated = true;
      break;
    }
  }

  matches.sort((a, b) {
    final pa = positionOf(a);
    final pb = positionOf(b);
    return filter
        .sortKey(pa.ra, pa.dec)
        .compareTo(filter.sortKey(pb.ra, pb.dec));
  });

  if (malformedRows > 0) {
    developer.log(
      '$catalogName region scan skipped $malformedRows malformed rows',
      name: 'CatalogRegionScan',
      level: 500,
    );
  }
  if (truncated) {
    developer.log(
      '$catalogName region scan stopped at ${filter.maxResults} matches for a '
      '${filter.radiusDegrees}deg cone; the answer is truncated',
      name: 'CatalogRegionScan',
      level: 900,
    );
  }

  return CatalogRegionScan<T>(
    objects: matches,
    malformedRows: malformedRows,
    truncated: truncated,
  );
}
