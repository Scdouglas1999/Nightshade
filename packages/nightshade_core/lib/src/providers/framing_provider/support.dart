part of '../framing_provider.dart';

// =============================================================================
// COMPUTED FOV PROVIDER
// =============================================================================

/// Equipment status for framing
enum EquipmentStatus {
  /// No equipment profile configured
  noProfile,

  /// Profile exists but no focal length configured
  noFocalLength,

  /// Profile exists but camera sensor specs not configured
  noCameraSpecs,

  /// Equipment is properly configured
  ready,
}

/// Result of checking equipment for framing
class FramingEquipmentResult {
  final EquipmentStatus status;
  final FramingEquipment? equipment;
  final String? profileName;
  final String? message;

  const FramingEquipmentResult({
    required this.status,
    this.equipment,
    this.profileName,
    this.message,
  });

  bool get isReady => status == EquipmentStatus.ready && equipment != null;
}

/// Provides calculated FOV from current equipment profile or custom settings
final framingFOVProvider = FutureProvider<FramingEquipmentResult>((ref) async {
  final framingState = ref.watch(framingProvider);

  // If using custom equipment, return it directly
  if (framingState.useCustomEquipment && framingState.customEquipment != null) {
    return FramingEquipmentResult(
      status: EquipmentStatus.ready,
      equipment: framingState.customEquipment,
      profileName: 'Custom Equipment',
    );
  }

  // Get from active profile (host-authoritative when paired).
  final profile = ref.watch(activeEquipmentProfileProvider);

  // Check if profile exists
  if (profile == null) {
    return const FramingEquipmentResult(
      status: EquipmentStatus.noProfile,
      message:
          'No equipment profile selected. Create and activate a profile in Settings → Equipment to enable framing.',
    );
  }

  // Check if focal length is configured
  if (profile.focalLength <= 0) {
    return FramingEquipmentResult(
      status: EquipmentStatus.noFocalLength,
      profileName: profile.name,
      message:
          'Optical specs not configured. Set the focal length in your equipment profile "${profile.name}" to enable FOV preview.',
    );
  }

  // Profile has basic optical data - we can calculate FOV
  // Check camera state early so we can use the friendly device name.
  //
  // Narrowed to the two fields this provider actually reads. Watching the whole
  // snapshot re-ran the async `getCameraStatus` round-trip below on every
  // telemetry tick — sensor temperature, cooler power, exposure progress — so
  // the Framing sidebar's equipment card spent most of its life mid-reload
  // (measured at eight of ten samples over 30 s) for data that only changes
  // when the camera connects, disconnects or is renamed.
  final (cameraConnectionState, cameraDeviceName) = ref.watch(
    cameraStateProvider.select(
      (state) => (state.connectionState, state.deviceName),
    ),
  );

  // Use friendly name from profile first, then connected camera's device name,
  // then fall back to device ID extraction
  final cameraName =
      profile.cameraName ??
      (cameraConnectionState == DeviceConnectionState.connected &&
              cameraDeviceName != null
          ? cameraDeviceName
          : (profile.cameraId != null
                ? _extractDeviceName(profile.cameraId!)
                : 'Unknown Camera'));

  final telescopeName = profile.telescopeName ?? profile.name;

  // Require real camera sensor specs; do not approximate with guessed defaults.
  double? sensorWidthMm;
  double? sensorHeightMm;
  double? pixelSizeMicrons;
  int? pixelsX;
  int? pixelsY;
  String? cameraMessage;
  final settingsDao = ref.watch(settingsDaoProvider);
  if (profile.cameraId != null &&
      cameraConnectionState == DeviceConnectionState.connected) {
    try {
      // Query camera status via backend (works with both local and remote)
      final backend = ref.watch(backendProvider);
      final status = await backend.getCameraStatus(profile.cameraId!);

      // Use actual sensor dimensions from connected camera
      // Now returns typed CameraStatus from all backends
      if (status.sensorWidth > 0 && status.sensorHeight > 0) {
        pixelsX = status.sensorWidth;
        pixelsY = status.sensorHeight;
        pixelSizeMicrons = status.pixelSizeX;

        // Calculate sensor physical size from pixel count and pixel size
        sensorWidthMm = (pixelsX * pixelSizeMicrons) / 1000;
        sensorHeightMm = (pixelsY * status.pixelSizeY) / 1000;

        cameraMessage = null; // No message needed - using real data

        // Write-through: sensor size does not change, so having read it once
        // from the live camera the app never needs the rig powered up again to
        // frame a target. Failing to record it is not a reason to withhold the
        // FOV we just computed, and its error must not be reported as "could
        // not query camera specs" — hence its own catch rather than the
        // enclosing one.
        try {
          await settingsDao.rememberSensorSpec(
            profile.cameraId!,
            RememberedSensorSpec(
              sensorWidth: status.sensorWidth,
              sensorHeight: status.sensorHeight,
              pixelSizeX: status.pixelSizeX,
              pixelSizeY: status.pixelSizeY,
              recordedAt: DateTime.now(),
            ),
          );
        } catch (error, stack) {
          developer.log(
            'Could not remember sensor geometry for ${profile.cameraId}.',
            name: 'Framing',
            level: 900,
            error: error,
            stackTrace: stack,
          );
        }
      } else {
        cameraMessage =
            'Camera is connected but did not report valid sensor dimensions.';
      }
    } catch (e) {
      cameraMessage = 'Could not query camera specs: $e';
    }
  } else if (profile.cameraId == null) {
    cameraMessage =
        'Camera is not configured for this profile. Configure and connect a camera to enable FOV.';
  } else {
    cameraMessage = 'Camera is not connected. Connect it to compute FOV.';
  }

  // Fall back to what this camera reported the last time it WAS connected.
  // Framing and mosaic planning happen indoors, ahead of the session, with the
  // rig unplugged; gating them on a live device made both unusable exactly
  // when they are wanted. The values are the camera's own, not an assumption,
  // and the message below says where they came from.
  if (pixelsX == null && profile.cameraId != null) {
    RememberedSensorSpec? remembered;
    try {
      remembered = await settingsDao.getRememberedSensorSpec(profile.cameraId!);
    } catch (error, stack) {
      developer.log(
        'Could not read remembered sensor geometry for ${profile.cameraId}.',
        name: 'Framing',
        level: 900,
        error: error,
        stackTrace: stack,
      );
    }
    if (remembered != null) {
      pixelsX = remembered.sensorWidth;
      pixelsY = remembered.sensorHeight;
      pixelSizeMicrons = remembered.pixelSizeX;
      sensorWidthMm = (pixelsX * remembered.pixelSizeX) / 1000;
      sensorHeightMm = (pixelsY * remembered.pixelSizeY) / 1000;
      cameraMessage =
          'Sensor size remembered from the last time this camera was '
          'connected. Connect it to confirm.';
    }
  }

  if (sensorWidthMm == null ||
      sensorHeightMm == null ||
      pixelSizeMicrons == null ||
      pixelsX == null ||
      pixelsY == null) {
    return FramingEquipmentResult(
      status: EquipmentStatus.noCameraSpecs,
      profileName: profile.name,
      message:
          cameraMessage ??
          'Camera sensor dimensions are unavailable. Connect camera hardware to compute FOV.',
    );
  }

  return FramingEquipmentResult(
    status: EquipmentStatus.ready,
    profileName: profile.name,
    equipment: FramingEquipment(
      cameraName: cameraName,
      sensorWidthMm: sensorWidthMm,
      sensorHeightMm: sensorHeightMm,
      pixelSizeMicrons: pixelSizeMicrons,
      pixelsX: pixelsX,
      pixelsY: pixelsY,
      telescopeName: telescopeName,
      focalLengthMm: profile.focalLength,
      apertureMm: profile.aperture > 0
          ? profile.aperture
          : profile.focalLength / 8,
    ),
    message: cameraMessage,
  );
});

/// Extract a human-readable device name from a raw device identifier.
///
/// Handles several formats:
/// - ASCOM IDs: "ASCOM.Simulator.Camera" -> "Camera"
/// - Native IDs: "zwo:native:0" -> "ZWO #0"
/// - Plain names are returned as-is.
String _extractDeviceName(String deviceId) {
  // ASCOM IDs are typically like "ASCOM.Simulator.Camera" or just a name
  if (deviceId.contains('.')) {
    final parts = deviceId.split('.');
    return parts.length > 1 ? parts.last : deviceId;
  }
  // Native driver IDs use colon separator: "vendor:driver:index"
  if (deviceId.contains(':')) {
    final parts = deviceId.split(':');
    if (parts.length >= 3) {
      final vendor = parts[0].toUpperCase();
      final index = parts[2];
      return '$vendor #$index';
    }
    // Fallback for 2-part colon IDs
    return parts[0].toUpperCase();
  }
  return deviceId;
}

// =============================================================================
// SIMBAD NAME RESOLVER
// =============================================================================

/// Resolved object from SIMBAD
class SimbadResult {
  final String mainId;
  final double raHours;
  final double decDegrees;
  final String objectType;
  final double? magnitude;
  final List<String> aliases;

  const SimbadResult({
    required this.mainId,
    required this.raHours,
    required this.decDegrees,
    required this.objectType,
    this.magnitude,
    this.aliases = const [],
  });
}

/// Resolves object names via SIMBAD API
class SimbadResolver {
  static const _baseUrl = 'https://simbad.cds.unistra.fr/simbad/sim-id';

  /// Resolve an object name to coordinates
  static Future<SimbadResult?> resolve(String name) async {
    try {
      final url =
          '$_baseUrl?Ident=${Uri.encodeComponent(name)}'
          '&output.format=votable'
          '&output.params=main_id,ra,dec,otype,flux(V)';

      final client = http.Client();
      try {
        final response = await client.get(Uri.parse(url));

        if (response.statusCode != 200) return null;

        // Parse the simple VOTable response
        final body = response.body;

        // Extract RA and Dec from response
        final raMatch = RegExp(r'<TD>(\d+\.\d+)</TD>').firstMatch(body);
        final decMatch = RegExp(
          r'<TD>([+-]?\d+\.\d+)</TD>',
          caseSensitive: false,
        ).firstMatch(body);

        if (raMatch == null || decMatch == null) {
          // Try TAP query instead
          return await _resolveTAP(name);
        }

        final raDeg = double.parse(raMatch.group(1)!);
        final decDeg = double.parse(decMatch.group(1)!);

        return SimbadResult(
          mainId: name,
          raHours: raDeg / 15,
          decDegrees: decDeg,
          objectType: 'Unknown',
        );
      } finally {
        client.close();
      }
    } catch (error, stack) {
      developer.log(
        'SIMBAD primary resolver failed for "$name"; trying TAP fallback.',
        name: 'Framing',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
      return _resolveTAP(name);
    }
  }

  /// Alternative TAP query resolution
  /// Builds the ADQL body for the TAP fallback resolve. Exposed for tests so
  /// the exact-match/LIKE interpolation stays verified.
  static String buildTapQuery(String name) {
    return '''
        SELECT TOP 1 main_id, ra, dec, otype_txt, flux
        FROM basic JOIN flux ON oid = oidref
        WHERE main_id = '${name.toUpperCase()}'
        OR main_id LIKE '%${name.toUpperCase()}%'
      ''';
  }

  static Future<SimbadResult?> _resolveTAP(String name) async {
    try {
      final query = buildTapQuery(name);

      final url =
          'https://simbad.cds.unistra.fr/simbad/sim-tap/sync'
          '?request=doQuery'
          '&lang=adql'
          '&format=json'
          '&query=${Uri.encodeComponent(query)}';

      final client = http.Client();
      try {
        final response = await client.get(Uri.parse(url));

        if (response.statusCode != 200) return null;

        final json = jsonDecode(response.body);
        final data = json['data'] as List?;

        if (data == null || data.isEmpty) return null;

        final row = data[0] as List;

        return SimbadResult(
          mainId: row[0] as String,
          raHours: (row[1] as num).toDouble() / 15,
          decDegrees: (row[2] as num).toDouble(),
          objectType: row[3] as String? ?? 'Unknown',
          magnitude: row.length > 4 ? (row[4] as num?)?.toDouble() : null,
        );
      } finally {
        client.close();
      }
    } catch (error, stack) {
      developer.log(
        'SIMBAD TAP resolver failed for "$name".',
        name: 'Framing',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Search for objects matching a query
  static Future<List<SimbadResult>> search(String query) async {
    if (query.isEmpty || query.length < 2) return [];

    try {
      final tapQuery =
          '''
        SELECT TOP 20 main_id, ra, dec, otype_txt
        FROM basic
        WHERE main_id LIKE '${query.toUpperCase()}%'
        OR main_id LIKE '%${query.toUpperCase()}%'
        ORDER BY CASE WHEN main_id = '${query.toUpperCase()}' THEN 0 ELSE 1 END, main_id
      ''';

      final url =
          'https://simbad.cds.unistra.fr/simbad/sim-tap/sync'
          '?request=doQuery'
          '&lang=adql'
          '&format=json'
          '&query=${Uri.encodeComponent(tapQuery)}';

      final client = http.Client();
      try {
        final response = await client.get(Uri.parse(url));

        if (response.statusCode != 200) return [];

        final json = jsonDecode(response.body);
        final data = json['data'] as List?;

        if (data == null) return [];

        return data.map((row) {
          final r = row as List;
          return SimbadResult(
            mainId: r[0] as String,
            raHours: (r[1] as num).toDouble() / 15,
            decDegrees: (r[2] as num).toDouble(),
            objectType: r[3] as String? ?? 'Unknown',
          );
        }).toList();
      } finally {
        client.close();
      }
    } catch (error, stack) {
      developer.log(
        'SIMBAD search failed for "$query".',
        name: 'Framing',
        level: 1000,
        error: error,
        stackTrace: stack,
      );
      return [];
    }
  }
}

// =============================================================================
// TARGET SEARCH PROVIDER — REMOVED 2026-05-16 (audit §2.5).
//
// The duplicate `TargetSearchState` / `TargetSearchNotifier` / `targetSearchProvider`
// previously lived here. The screen-local autoDispose version at
// `packages/nightshade_app/lib/screens/framing/framing_search_provider.dart`
// is the canonical implementation. Every importer of `nightshade_core` had to
// `hide TargetSearchState, targetSearchProvider` to avoid the symbol collision;
// removing the duplicate eliminates that workaround.
// =============================================================================

// =============================================================================
// COORDINATE CONVERSION UTILITIES
// =============================================================================

class CoordinateUtils {
  /// Parse RA from string (supports HH:MM:SS, HHhMMmSSs, decimal hours/degrees)
  static double? parseRA(String input) => CoordinateParser.parseRa(input);

  /// Parse Dec from string (supports ±DD:MM:SS, ±DD°MM'SS", decimal)
  static double? parseDec(String input) => CoordinateParser.parseDec(input);

  /// Format RA (decimal hours) as `HHh MMm SS.Ss`.
  static String formatRA(double raHours) => CoordinateFormat.ra(raHours);

  /// Format Dec as `±DD° MM' SS.S"`
  static String formatDec(double decDegrees) =>
      CoordinateFormat.dec(decDegrees);
}
