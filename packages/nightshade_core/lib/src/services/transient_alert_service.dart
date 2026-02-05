import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../models/alerts/transient_alert.dart';
import 'logging_service.dart';

/// Service for fetching astronomical transient alerts from external APIs.
///
/// Transient alerts notify astronomers of time-critical events like novae,
/// supernovae, and other variable star outbursts that require prompt observation.
///
/// Supported sources:
/// - AAVSO (American Association of Variable Star Observers)
/// - TNS (Transient Name Server) - requires API key, uses sample data
///
/// Usage:
/// ```dart
/// final service = TransientAlertService(httpClient: http.Client(), logger: loggingService);
/// final alerts = await service.getAllAlerts(settings);
/// ```
class TransientAlertService {
  /// HTTP client for making API requests.
  final http.Client _httpClient;

  /// Logging service for error and debug logging.
  final LoggingService _logger;

  /// Cached alerts from the last fetch.
  List<TransientAlert>? _cachedAlerts;

  /// Expiration time of the current cache.
  DateTime? _cacheExpiry;

  /// Cache time-to-live duration (15 minutes).
  static const Duration _cacheTtl = Duration(minutes: 15);

  /// AAVSO API endpoint for variable star data.
  static const String _aavsoApiUrl =
      'https://www.aavso.org/vsx/index.php?view=api.list&format=json&maxrec=50';

  /// Creates a new transient alert service instance.
  ///
  /// Parameters:
  /// - [httpClient]: HTTP client for API requests
  /// - [logger]: Logging service for error reporting
  TransientAlertService({
    required http.Client httpClient,
    required LoggingService logger,
  })  : _httpClient = httpClient,
        _logger = logger;

  /// Whether the cache is still valid and has not expired.
  bool get isCacheValid {
    if (_cachedAlerts == null || _cacheExpiry == null) {
      return false;
    }
    return DateTime.now().isBefore(_cacheExpiry!);
  }

  /// Clears the cached alerts, forcing a fresh fetch on next request.
  void clearCache() {
    _cachedAlerts = null;
    _cacheExpiry = null;
    _logger.debug('Transient alert cache cleared', source: 'TransientAlertService');
  }

  /// Fetches variable star alerts from AAVSO.
  ///
  /// Queries the AAVSO VSX (Variable Star Index) API for recent alerts.
  /// Maps AAVSO variable types to [TransientType] enum values.
  ///
  /// Returns an empty list on failure (graceful degradation).
  Future<List<TransientAlert>> fetchAavsoAlerts() async {
    _logger.debug('Fetching AAVSO alerts from: $_aavsoApiUrl',
        source: 'TransientAlertService');

    try {
      final response = await _httpClient
          .get(Uri.parse(_aavsoApiUrl))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        _logger.error(
            'AAVSO API returned status ${response.statusCode}: ${response.reasonPhrase}',
            source: 'TransientAlertService');
        return [];
      }

      // Parse JSON response
      final dynamic data;
      try {
        data = json.decode(response.body);
      } catch (e) {
        _logger.error('Failed to parse AAVSO API response: $e',
            source: 'TransientAlertService');
        return [];
      }

      // AAVSO VSX returns an object with 'VSXObjects' containing the list
      final List<dynamic>? vsxObjects;
      if (data is Map<String, dynamic>) {
        vsxObjects = data['VSXObjects'] as List<dynamic>?;
      } else {
        _logger.error(
            'Unexpected AAVSO API response format: expected Map, got ${data.runtimeType}',
            source: 'TransientAlertService');
        return [];
      }

      if (vsxObjects == null || vsxObjects.isEmpty) {
        _logger.warning('AAVSO API returned no variable star objects',
            source: 'TransientAlertService');
        return [];
      }

      final alerts = <TransientAlert>[];
      final now = DateTime.now();

      for (final obj in vsxObjects) {
        if (obj is! Map<String, dynamic>) continue;

        try {
          final alert = _parseAavsoObject(obj, now);
          if (alert != null) {
            alerts.add(alert);
          }
        } catch (e) {
          _logger.warning('Failed to parse AAVSO object: $e',
              source: 'TransientAlertService');
          // Continue processing other objects
        }
      }

      _logger.info('Fetched ${alerts.length} alerts from AAVSO',
          source: 'TransientAlertService');
      return alerts;
    } on http.ClientException catch (e) {
      _logger.error('Network error fetching AAVSO alerts: $e',
          source: 'TransientAlertService');
      return [];
    } catch (e) {
      _logger.error('Unexpected error fetching AAVSO alerts: $e',
          source: 'TransientAlertService');
      return [];
    }
  }

  /// Parses a single AAVSO VSX object into a TransientAlert.
  ///
  /// Returns null if the object cannot be parsed.
  TransientAlert? _parseAavsoObject(Map<String, dynamic> obj, DateTime now) {
    // Extract name - required field
    final name = obj['Name'] as String?;
    if (name == null || name.isEmpty) {
      return null;
    }

    // Extract coordinates - required fields
    final raStr = obj['RA2000'] as String?;
    final decStr = obj['Declination2000'] as String?;
    if (raStr == null || decStr == null) {
      return null;
    }

    // Parse RA from hours:minutes:seconds format (e.g., "18:23:54.67")
    final raHours = _parseRaString(raStr);
    if (raHours == null) {
      return null;
    }

    // Parse Dec from degrees:arcmin:arcsec format (e.g., "+23:45:12.3")
    final decDegrees = _parseDecString(decStr);
    if (decDegrees == null) {
      return null;
    }

    // Extract variable type and map to TransientType
    final varType = obj['Type'] as String?;
    final transientType = _mapAavsoTypeToTransientType(varType);

    // Extract magnitude if available
    final maxMagStr = obj['MaxMag'] as String?;
    final minMagStr = obj['MinMag'] as String?;
    final magnitude = maxMagStr != null ? double.tryParse(maxMagStr) : null;
    final peakMagnitude = minMagStr != null ? double.tryParse(minMagStr) : null;

    // Generate unique ID from AAVSO OID or name
    final oid = obj['OID'] as String?;
    final id = 'aavso_${oid ?? name.replaceAll(' ', '_').toLowerCase()}';

    // Extract constellation for classification
    final constellation = obj['Constellation'] as String?;

    // Calculate priority based on type and magnitude
    final priority = _calculatePriority(transientType, magnitude);

    return TransientAlert(
      id: id,
      name: name,
      type: transientType,
      raHours: raHours,
      decDegrees: decDegrees,
      magnitude: magnitude,
      peakMagnitude: peakMagnitude,
      discoveryTime: now, // AAVSO doesn't provide discovery time in list API
      lastUpdated: now,
      source: TransientSource.aavso,
      sourceUrl: 'https://www.aavso.org/vsx/index.php?view=detail.top&oid=$oid',
      priority: priority,
      classification: constellation != null ? 'Constellation: $constellation' : null,
    );
  }

  /// Parses RA string in HMS format (e.g., "18:23:54.67") to hours.
  double? _parseRaString(String raStr) {
    try {
      final parts = raStr.split(':');
      if (parts.length < 2) {
        // Try parsing as decimal hours
        return double.tryParse(raStr);
      }

      final hours = double.parse(parts[0]);
      final minutes = double.parse(parts[1]);
      final seconds = parts.length > 2 ? double.parse(parts[2]) : 0.0;

      return hours + minutes / 60.0 + seconds / 3600.0;
    } catch (e) {
      return null;
    }
  }

  /// Parses Dec string in DMS format (e.g., "+23:45:12.3") to degrees.
  double? _parseDecString(String decStr) {
    try {
      // Handle sign
      final isNegative = decStr.startsWith('-');
      var cleanStr = decStr.replaceFirst('+', '').replaceFirst('-', '');

      final parts = cleanStr.split(':');
      if (parts.length < 2) {
        // Try parsing as decimal degrees
        final value = double.tryParse(decStr);
        return value;
      }

      final degrees = double.parse(parts[0]).abs();
      final arcminutes = double.parse(parts[1]);
      final arcseconds = parts.length > 2 ? double.parse(parts[2]) : 0.0;

      var result = degrees + arcminutes / 60.0 + arcseconds / 3600.0;
      return isNegative ? -result : result;
    } catch (e) {
      return null;
    }
  }

  /// Maps AAVSO variable type codes to TransientType enum.
  ///
  /// AAVSO type codes: https://www.aavso.org/vsx/help/VariableStarTypeDesignations.html
  TransientType _mapAavsoTypeToTransientType(String? varType) {
    if (varType == null) {
      return TransientType.other;
    }

    final type = varType.toUpperCase();

    // Nova types
    if (type.contains('N') && !type.contains('SN')) {
      if (type == 'N' || type == 'NA' || type == 'NB' || type == 'NC' || type == 'NR') {
        return TransientType.nova;
      }
    }

    // Supernova
    if (type.contains('SN')) {
      return TransientType.supernova;
    }

    // Cataclysmic variables (dwarf novae, AM CVn, etc.)
    if (type.contains('UG') ||
        type.contains('AM') ||
        type.contains('CV') ||
        type.contains('DQ') ||
        type.contains('UGSS') ||
        type.contains('UGSU') ||
        type.contains('UGZ') ||
        type.contains('UGWZ')) {
      return TransientType.cataclysmic;
    }

    // Variable stars (Mira, Cepheids, RR Lyrae, etc.)
    if (type.contains('M') ||
        type.contains('SR') ||
        type.contains('CEP') ||
        type.contains('RR') ||
        type.contains('DCEP') ||
        type.contains('RRAB') ||
        type.contains('RRC')) {
      return TransientType.variableStar;
    }

    // Eruptive/irregular variables are often interesting
    if (type.contains('UV') ||
        type.contains('IN') ||
        type.contains('BE') ||
        type.contains('GCAS')) {
      return TransientType.variableStar;
    }

    return TransientType.other;
  }

  /// Calculates alert priority (1-10, 1=highest) based on type and magnitude.
  int _calculatePriority(TransientType type, double? magnitude) {
    int basePriority;

    // Type-based priority
    switch (type) {
      case TransientType.supernova:
        basePriority = 1;
      case TransientType.gammaRayBurst:
        basePriority = 2;
      case TransientType.nova:
        basePriority = 3;
      case TransientType.cataclysmic:
        basePriority = 4;
      case TransientType.comet:
        basePriority = 5;
      case TransientType.asteroid:
        basePriority = 6;
      case TransientType.variableStar:
        basePriority = 7;
      case TransientType.other:
        basePriority = 8;
    }

    // Adjust for brightness (brighter objects are higher priority)
    if (magnitude != null) {
      if (magnitude < 8.0) {
        basePriority = (basePriority - 2).clamp(1, 10);
      } else if (magnitude < 12.0) {
        basePriority = (basePriority - 1).clamp(1, 10);
      } else if (magnitude > 16.0) {
        basePriority = (basePriority + 1).clamp(1, 10);
      }
    }

    return basePriority;
  }

  /// Fetches recent transient alerts from TNS (Transient Name Server).
  ///
  /// TNS requires an API key for access. If no API key is configured,
  /// this method returns an empty list and logs a warning.
  ///
  /// To obtain an API key:
  /// 1. Create an account at https://www.wis-tns.org/
  /// 2. Request API access in your account settings
  /// 3. Configure the key in Nightshade settings
  ///
  /// See: https://www.wis-tns.org/content/tns-api-overview
  Future<List<TransientAlert>> fetchTnsAlerts({String? apiKey}) async {
    // TNS requires an API key - return empty list if not configured
    if (apiKey == null || apiKey.isEmpty) {
      _logger.warning(
        'TNS API key not configured - TNS alerts disabled. '
        'Obtain an API key at https://www.wis-tns.org/',
        source: 'TransientAlertService',
      );
      return [];
    }

    _logger.debug('Fetching transients from TNS', source: 'TransientAlertService');

    try {
      // TNS API requires specific headers and parameters
      final response = await _httpClient.post(
        Uri.parse('https://www.wis-tns.org/api/get/search'),
        headers: {
          'User-Agent': 'Nightshade Astrophotography Suite',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'api_key': apiKey,
          'format': 'json',
          // Get recent objects from the last 30 days
          'date_start': _formatTnsDate(DateTime.now().subtract(const Duration(days: 30))),
          'date_end': _formatTnsDate(DateTime.now()),
          // Only get confirmed supernovae and novae
          'objtype': '1,2,3,4,5', // SN Ia, SN II, SN Ibc, CV, Nova
          'num_page': '50',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseTnsResponse(data);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _logger.error(
          'TNS API authentication failed - check your API key',
          source: 'TransientAlertService',
        );
        return [];
      } else {
        _logger.error(
          'TNS API error: ${response.statusCode} - ${response.reasonPhrase}',
          source: 'TransientAlertService',
        );
        return [];
      }
    } catch (e) {
      _logger.error('Failed to fetch TNS alerts: $e', source: 'TransientAlertService');
      return [];
    }
  }

  /// Formats a DateTime for TNS API date parameters (YYYY-MM-DD).
  String _formatTnsDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Parses the TNS API response into TransientAlert objects.
  List<TransientAlert> _parseTnsResponse(dynamic data) {
    final alerts = <TransientAlert>[];

    try {
      // TNS response format: { "id_count": N, "objids": [...], "data": { objid: {...}, ... } }
      if (data is! Map<String, dynamic>) return alerts;

      final objects = data['data'] as Map<String, dynamic>? ?? {};

      for (final entry in objects.entries) {
        try {
          final obj = entry.value as Map<String, dynamic>;

          // Parse coordinates
          final raStr = obj['ra'] as String? ?? '';
          final decStr = obj['dec'] as String? ?? '';
          final raHours = _parseRaString(raStr);
          final decDegrees = _parseDecString(decStr);

          if (raHours == null || decDegrees == null) continue;

          // Parse magnitude
          final magStr = obj['discovermag'] as String? ?? '';
          final magnitude = double.tryParse(magStr);

          // Determine type based on classification
          final classification = obj['type'] as String? ?? '';
          final type = _classifyTnsObject(classification);

          // Parse discovery time
          final discDateStr = obj['discoverydate'] as String? ?? '';
          final discoveryTime = DateTime.tryParse(discDateStr) ?? DateTime.now();

          alerts.add(TransientAlert(
            id: 'tns_${entry.key}',
            name: obj['name'] as String? ?? 'Unknown',
            type: type,
            raHours: raHours,
            decDegrees: decDegrees,
            magnitude: magnitude,
            peakMagnitude: magnitude,
            discoveryTime: discoveryTime,
            lastUpdated: DateTime.now(),
            source: TransientSource.tns,
            sourceUrl: 'https://www.wis-tns.org/object/${obj['name'] ?? entry.key}',
            priority: _calculatePriority(type, magnitude),
            classification: classification,
          ));
        } catch (e) {
          _logger.debug('Failed to parse TNS object ${entry.key}: $e',
              source: 'TransientAlertService');
        }
      }
    } catch (e) {
      _logger.error('Failed to parse TNS response: $e', source: 'TransientAlertService');
    }

    return alerts;
  }

  /// Classifies a TNS object type string to our TransientType enum.
  TransientType _classifyTnsObject(String classification) {
    final lower = classification.toLowerCase();
    if (lower.contains('sn ia') || lower.contains('type ia')) {
      return TransientType.supernova;
    }
    if (lower.contains('sn ii') || lower.contains('sn ib') || lower.contains('sn ic')) {
      return TransientType.supernova;
    }
    if (lower.contains('nova')) {
      return TransientType.nova;
    }
    if (lower.contains('cv') || lower.contains('cataclysmic')) {
      return TransientType.cataclysmic;
    }
    if (lower.contains('grb') || lower.contains('gamma')) {
      return TransientType.gammaRayBurst;
    }
    return TransientType.other;
  }

  /// Fetches all alerts from enabled sources and filters by settings.
  ///
  /// Implements caching to avoid excessive API calls. Cache TTL is 15 minutes.
  ///
  /// Parameters:
  /// - [settings]: Alert settings controlling which sources and types to include
  ///
  /// Returns a filtered, deduplicated, and sorted list of alerts.
  Future<List<TransientAlert>> getAllAlerts(TransientAlertSettings settings) async {
    // Check cache first
    if (isCacheValid && _cachedAlerts != null) {
      _logger.debug('Returning cached alerts (${_cachedAlerts!.length} total)',
          source: 'TransientAlertService');
      return _filterAlerts(_cachedAlerts!, settings);
    }

    _logger.debug('Fetching alerts from enabled sources',
        source: 'TransientAlertService');

    // Fetch from enabled sources in parallel
    final futures = <Future<List<TransientAlert>>>[];

    if (settings.enabledSources.contains(TransientSource.aavso)) {
      futures.add(fetchAavsoAlerts());
    }

    // TNS requires an API key - only fetch if configured
    if (settings.enabledSources.contains(TransientSource.tns)) {
      if (settings.tnsApiKey != null && settings.tnsApiKey!.isNotEmpty) {
        futures.add(fetchTnsAlerts(apiKey: settings.tnsApiKey));
      } else {
        _logger.info(
          'TNS source enabled but no API key configured - skipping TNS',
          source: 'TransientAlertService',
        );
      }
    }

    // Wait for all fetches to complete
    final results = await Future.wait(futures);

    // Combine all alerts
    final allAlerts = <TransientAlert>[];
    for (final alerts in results) {
      allAlerts.addAll(alerts);
    }

    // Deduplicate by name (case-insensitive)
    final seen = <String>{};
    final deduplicatedAlerts = <TransientAlert>[];
    for (final alert in allAlerts) {
      final key = alert.name.toLowerCase().trim();
      if (!seen.contains(key)) {
        seen.add(key);
        deduplicatedAlerts.add(alert);
      }
    }

    // Update cache
    _cachedAlerts = deduplicatedAlerts;
    _cacheExpiry = DateTime.now().add(_cacheTtl);

    _logger.info(
        'Fetched ${deduplicatedAlerts.length} unique alerts, cache updated',
        source: 'TransientAlertService');

    return _filterAlerts(deduplicatedAlerts, settings);
  }

  /// Filters alerts based on user settings.
  List<TransientAlert> _filterAlerts(
      List<TransientAlert> alerts, TransientAlertSettings settings) {
    var filtered = alerts.where((alert) {
      // Filter by type
      if (!settings.typesToMonitor.contains(alert.type)) {
        return false;
      }

      // Filter by magnitude threshold (only if magnitude is known)
      if (alert.magnitude != null && alert.magnitude! > settings.magnitudeThreshold) {
        return false;
      }

      // Filter by source
      if (!settings.enabledSources.contains(alert.source)) {
        return false;
      }

      return true;
    }).toList();

    // Sort by priority (ascending, 1=highest) then by discovery time (newest first)
    filtered.sort((a, b) {
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return b.discoveryTime.compareTo(a.discoveryTime);
    });

    return filtered;
  }

  /// Determines if an alert should trigger a notification.
  ///
  /// Returns true if the alert matches the notification criteria:
  /// - Alert type is being monitored
  /// - Magnitude is below the notification threshold (brighter)
  /// - If autoQueueBright is enabled, checks if brighter than autoQueueMagnitude
  ///
  /// Parameters:
  /// - [alert]: The alert to check
  /// - [settings]: Current alert settings
  bool shouldNotify(TransientAlert alert, TransientAlertSettings settings) {
    // Must be a monitored type
    if (!settings.typesToMonitor.contains(alert.type)) {
      return false;
    }

    // Must be from an enabled source
    if (!settings.enabledSources.contains(alert.source)) {
      return false;
    }

    // Check magnitude threshold (if magnitude is known)
    if (alert.magnitude != null) {
      // Alert must be brighter than (less than) the threshold
      if (alert.magnitude! > settings.magnitudeThreshold) {
        return false;
      }
    }

    // Check auto-queue criteria for bright transients
    if (settings.autoQueueBright) {
      if (alert.magnitude != null && alert.magnitude! <= settings.autoQueueMagnitude) {
        // This is a bright transient that should be auto-queued
        return true;
      }
    }

    // Notify for any alert that passes magnitude and type filters
    return settings.notifyOnNew;
  }

  /// Closes the HTTP client and releases resources.
  void dispose() {
    _httpClient.close();
    _logger.debug('TransientAlertService disposed', source: 'TransientAlertService');
  }
}

/// Provider for the transient alert service.
final transientAlertServiceProvider = Provider<TransientAlertService>((ref) {
  final logger = ref.watch(loggingServiceProvider);
  final service = TransientAlertService(
    httpClient: http.Client(),
    logger: logger,
  );

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});
