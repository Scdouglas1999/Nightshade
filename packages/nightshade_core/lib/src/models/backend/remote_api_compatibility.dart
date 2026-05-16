/// Compatibility policy for Nightshade remote/headless API clients.
class RemoteApiCompatibility {
  static const apiVersionHeader = 'x-nightshade-api-version';
  // 2.4.0 is the floor for the hardened remote API. Earlier 2.x builds did
  // not expose the auth, pairing, and version-negotiation contracts required
  // by current desktop, mobile, and WebRTC clients.
  static const minimumSupportedVersion = SemanticVersion(2, 4, 0);
  static const serverApiVersion = SemanticVersion(2, 5, 0);
  static const clientApiVersion = serverApiVersion;

  const RemoteApiCompatibility._();

  static RemoteApiCompatibilityResult check(String? serverVersion) {
    final parsed = SemanticVersion.tryParse(serverVersion);
    if (parsed == null) {
      return RemoteApiCompatibilityResult.incompatible(
        code: 'server_version_unknown',
        message:
            'The Nightshade server did not report a valid API version. Update the server before connecting.',
        serverVersion: serverVersion,
      );
    }

    if (parsed < minimumSupportedVersion) {
      return RemoteApiCompatibilityResult.incompatible(
        code: 'server_too_old',
        message:
            'This Nightshade server is too old for this client. Server: ${parsed.format()}, required: ${minimumSupportedVersion.format()} or newer.',
        serverVersion: parsed.format(),
      );
    }

    if (parsed.major > clientApiVersion.major) {
      return RemoteApiCompatibilityResult.incompatible(
        code: 'server_too_new',
        message:
            'This Nightshade server is newer than this client supports. Server: ${parsed.format()}, client API: ${clientApiVersion.format()}. Update this client before connecting.',
        serverVersion: parsed.format(),
      );
    }

    return RemoteApiCompatibilityResult.compatible(
      serverVersion: parsed.format(),
    );
  }

  static RemoteApiCompatibilityResult checkClient(String? clientVersion) {
    final parsed = SemanticVersion.tryParse(clientVersion);
    if (parsed == null) {
      return RemoteApiCompatibilityResult.incompatible(
        code: 'client_version_unknown',
        message:
            'The Nightshade client did not send a valid API version. Update the client before connecting.',
        serverVersion: serverApiVersion.format(),
        clientVersion: clientVersion,
      );
    }

    if (parsed < minimumSupportedVersion) {
      return RemoteApiCompatibilityResult.incompatible(
        code: 'client_too_old',
        message:
            'This Nightshade client is too old for this server. Client: ${parsed.format()}, required: ${minimumSupportedVersion.format()} or newer.',
        serverVersion: serverApiVersion.format(),
        clientVersion: parsed.format(),
      );
    }

    if (parsed.major > serverApiVersion.major) {
      return RemoteApiCompatibilityResult.incompatible(
        code: 'server_too_old',
        message:
            'This Nightshade server is too old for this client. Server API: ${serverApiVersion.format()}, client API: ${parsed.format()}. Update the server before connecting.',
        serverVersion: serverApiVersion.format(),
        clientVersion: parsed.format(),
      );
    }

    return RemoteApiCompatibilityResult.compatible(
      serverVersion: serverApiVersion.format(),
      clientVersion: parsed.format(),
    );
  }
}

class RemoteApiCompatibilityResult {
  final bool isCompatible;
  final String code;
  final String message;
  final String? serverVersion;
  final String? clientVersion;

  const RemoteApiCompatibilityResult._({
    required this.isCompatible,
    required this.code,
    required this.message,
    required this.serverVersion,
    required this.clientVersion,
  });

  factory RemoteApiCompatibilityResult.compatible({
    required String serverVersion,
    String? clientVersion,
  }) {
    return RemoteApiCompatibilityResult._(
      isCompatible: true,
      code: 'compatible',
      message: 'Compatible with Nightshade server $serverVersion.',
      serverVersion: serverVersion,
      clientVersion: clientVersion,
    );
  }

  factory RemoteApiCompatibilityResult.incompatible({
    required String code,
    required String message,
    required String? serverVersion,
    String? clientVersion,
  }) {
    return RemoteApiCompatibilityResult._(
      isCompatible: false,
      code: code,
      message: message,
      serverVersion: serverVersion,
      clientVersion: clientVersion,
    );
  }
}

class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;

  const SemanticVersion(this.major, this.minor, this.patch);

  static SemanticVersion? tryParse(String? value) {
    if (value == null) return null;
    final match =
        RegExp(r'^v?(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(value.trim());
    if (match == null) return null;

    return SemanticVersion(
      int.parse(match.group(1)!),
      int.tryParse(match.group(2) ?? '') ?? 0,
      int.tryParse(match.group(3) ?? '') ?? 0,
    );
  }

  String format() => '$major.$minor.$patch';

  @override
  int compareTo(SemanticVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) return majorCompare;
    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) return minorCompare;
    return patch.compareTo(other.patch);
  }

  bool operator <(SemanticVersion other) => compareTo(other) < 0;
  bool operator >(SemanticVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) {
    return other is SemanticVersion &&
        major == other.major &&
        minor == other.minor &&
        patch == other.patch;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);
}
