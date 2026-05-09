/// Format a device ID into a user-friendly display name.
///
/// Handles the following formats:
/// - Native: `native:vendor:index` or `native:vendor_type:index`
/// - ASCOM: `ascom:ASCOM.Vendor.Type` or `ASCOM.Vendor.Type`
/// - Alpaca: `alpaca:host:port:device_number`
/// - PHD2 identifiers
/// - INDI: `indi:host:port:device_name`
String formatDeviceId(String id) {
  final lowerId = id.toLowerCase();

  // Handle native device IDs: native:vendor:index or native:vendor_type:index
  if (lowerId.startsWith('native:')) {
    final parts = id.substring(7).split(':');
    if (parts.isNotEmpty) {
      final devicePart = parts[0];
      final index = parts.length > 1 ? int.tryParse(parts[1]) : null;

      // Handle vendor_type format (e.g., zwo_eaf)
      if (devicePart.contains('_')) {
        final subParts = devicePart.split('_');
        final vendor = capitalizeVendor(subParts[0]);
        final type = subParts.sublist(1).map((s) => s.toUpperCase()).join(' ');
        return '$vendor $type';
      }

      // Simple vendor format
      final vendor = capitalizeVendor(devicePart);
      if (index != null) {
        return '$vendor #${index + 1}';
      }
      return vendor;
    }
  }

  // Handle ASCOM device IDs: ascom:ASCOM.Vendor.Type or ASCOM.Vendor.Type
  if (lowerId.startsWith('ascom:') || lowerId.startsWith('ascom.')) {
    final ascomId = lowerId.startsWith('ascom:') ? id.substring(6) : id;
    final parts = ascomId.split('.');
    if (parts.length >= 2) {
      final vendorPart = parts.length > 1 ? parts[1] : parts[0];
      return formatAscomVendor(vendorPart);
    }
  }

  // Handle Alpaca device IDs
  if (lowerId.startsWith('alpaca:')) {
    final alpacaPart = id.substring(7);
    return 'Alpaca: $alpacaPart';
  }

  // Handle PHD2
  if (lowerId.contains('phd2') || lowerId.contains('phd 2')) {
    return 'PHD2';
  }

  // Fallback: try to clean up the ID
  return cleanupDeviceId(id);
}

/// Capitalize a vendor name using known vendor mappings.
///
/// Maps lowercase vendor identifiers to their proper display names,
/// e.g. `zwo` -> `ZWO`, `skywatcher` -> `Sky-Watcher`.
String capitalizeVendor(String vendor) {
  const knownVendors = {
    'zwo': 'ZWO',
    'asi': 'ZWO ASI',
    'qhy': 'QHY',
    'playerone': 'PlayerOne',
    'svbony': 'SVBony',
    'atik': 'Atik',
    'fli': 'FLI',
    'moravian': 'Moravian',
    'touptek': 'Touptek',
    'pegasus': 'Pegasus',
    'pegasusastro': 'Pegasus Astro',
    'ioptron': 'iOptron',
    'skywatcher': 'Sky-Watcher',
    'celestron': 'Celestron',
    'meade': 'Meade',
    'losmandy': 'Losmandy',
    'moonlite': 'MoonLite',
    'optec': 'Optec',
    'lacerta': 'Lacerta',
    'esatto': 'Esatto',
    'primaluce': 'PrimaLuce',
  };

  final lower = vendor.toLowerCase();
  if (knownVendors.containsKey(lower)) {
    return knownVendors[lower]!;
  }

  // Default: capitalize first letter
  if (vendor.isEmpty) return vendor;
  return vendor[0].toUpperCase() + vendor.substring(1);
}

/// Format an ASCOM vendor string by adding spaces before capital letters
/// and numbers (e.g. `FocuserPro` -> `Focuser Pro`).
String formatAscomVendor(String vendor) {
  final spaced = vendor.replaceAllMapped(
    RegExp(r'([a-z])([A-Z0-9])'),
    (m) => '${m.group(1)} ${m.group(2)}',
  );
  return spaced;
}

/// Clean up an unrecognized device ID for display.
///
/// Strips common prefixes, replaces separators with spaces,
/// removes trailing index numbers, and capitalizes words.
String cleanupDeviceId(String id) {
  // Remove common prefixes
  var cleaned = id;
  for (final prefix in ['native:', 'ascom:', 'alpaca:', 'ASCOM.']) {
    if (cleaned.toLowerCase().startsWith(prefix.toLowerCase())) {
      cleaned = cleaned.substring(prefix.length);
    }
  }

  // Replace underscores and dots with spaces
  cleaned = cleaned.replaceAll('_', ' ').replaceAll('.', ' ');

  // Remove trailing numbers that look like indices
  cleaned = cleaned.replaceAll(RegExp(r'\s*:\s*\d+$'), '');

  // Capitalize words
  if (cleaned.isNotEmpty) {
    cleaned = cleaned.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  return cleaned.isEmpty ? id : cleaned;
}
