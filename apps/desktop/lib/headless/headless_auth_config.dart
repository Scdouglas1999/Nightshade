import 'dart:io';

import '../headless_api/auth_policy.dart';
import '../headless_api/handlers/pairing_handlers.dart' show PairingMode;
import 'headless_env.dart';

/// Resolved server configuration derived from CLI arguments and environment
/// variables. Immutable snapshot passed into the service bootstrap so the
/// startup path reads a single coherent set of values.
class HeadlessAuthConfig {
  final String? token;
  final bool requireAuth;
  final bool bindLocalOnly;
  final int port;
  final Map<String, HeadlessTokenScope> scopedTokens;
  final List<String> corsAllowedOrigins;
  final bool pairingPrintCodes;
  final PairingMode pairingMode;
  final bool tlsEnabled;
  final String? tlsCertPath;
  final String? tlsKeyPath;

  HeadlessAuthConfig({
    this.token,
    this.requireAuth = false,
    this.bindLocalOnly = true,
    this.port = 8080,
    this.scopedTokens = const {},
    this.corsAllowedOrigins = const [],
    this.pairingPrintCodes = false,
    this.pairingMode = PairingMode.lanOpen,
    this.tlsEnabled = false,
    this.tlsCertPath,
    this.tlsKeyPath,
  });
}

/// Parse the headless server configuration from CLI [args] and environment
/// variables. Environment is read first (the systemd/docker idiom) and CLI
/// flags override or extend it. See `main_headless.dart`'s doc comment for the
/// full flag/variable reference.
HeadlessAuthConfig parseHeadlessAuthConfig(List<String> args) {
  String? token;
  var requireAuth = false;
  var allowUnauthenticatedLan = envFlag(
    'NIGHTSHADE_ALLOW_UNAUTHENTICATED_LAN',
  );
  var port = 8080;
  final scopedTokens = <String, HeadlessTokenScope>{};
  final corsAllowedOrigins = <String>[];
  var pairingPrintCodes = envFlag('NIGHTSHADE_PAIRING_PRINT_CODES');
  // Default to one-tap LAN pairing; operators can tighten to code-required.
  final pairingMode = PairingMode.fromWire(
    Platform.environment['NIGHTSHADE_PAIRING_MODE'],
  );
  var tlsEnabled = envFlag('NIGHTSHADE_TLS');
  String? tlsCertPath = trimToNull(
    Platform.environment['NIGHTSHADE_TLS_CERT'],
  );
  String? tlsKeyPath = trimToNull(Platform.environment['NIGHTSHADE_TLS_KEY']);

  token = Platform.environment['NIGHTSHADE_AUTH_TOKEN'];
  _addScopedTokenFromEnv(
    scopedTokens,
    'NIGHTSHADE_VIEW_TOKEN',
    HeadlessTokenScope.view,
  );
  _addScopedTokenFromEnv(
    scopedTokens,
    'NIGHTSHADE_CONTROL_TOKEN',
    HeadlessTokenScope.control,
  );
  if (Platform.environment['NIGHTSHADE_PORT'] != null) {
    port = int.tryParse(Platform.environment['NIGHTSHADE_PORT']!) ?? 8080;
  }

  // Why env-first: NIGHTSHADE_CORS_ORIGINS is the systemd/docker idiom; CLI
  // overrides allow operators to extend the list at launch time.
  final envCors = Platform.environment['NIGHTSHADE_CORS_ORIGINS'];
  if (envCors != null && envCors.trim().isNotEmpty) {
    for (final raw in envCors.split(',')) {
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        corsAllowedOrigins.add(trimmed);
      }
    }
  }

  for (final arg in args) {
    if (arg.startsWith('--auth-token=')) {
      token = arg.substring('--auth-token='.length);
    } else if (arg == '--require-auth') {
      requireAuth = true;
    } else if (arg == '--allow-unauthenticated-lan') {
      allowUnauthenticatedLan = true;
    } else if (arg.startsWith('--view-token=')) {
      _addScopedToken(
        scopedTokens,
        arg.substring('--view-token='.length),
        HeadlessTokenScope.view,
      );
    } else if (arg.startsWith('--control-token=')) {
      _addScopedToken(
        scopedTokens,
        arg.substring('--control-token='.length),
        HeadlessTokenScope.control,
      );
    } else if (arg.startsWith('--port=')) {
      port = int.tryParse(arg.substring('--port='.length)) ?? port;
    } else if (arg.startsWith('--cors-origin=')) {
      final value = arg.substring('--cors-origin='.length).trim();
      if (value.isNotEmpty) {
        corsAllowedOrigins.add(value);
      }
    } else if (arg == '--pairing-print-codes') {
      pairingPrintCodes = true;
    } else if (arg == '--tls') {
      tlsEnabled = true;
    } else if (arg.startsWith('--tls-cert=')) {
      tlsCertPath = trimToNull(arg.substring('--tls-cert='.length));
    } else if (arg.startsWith('--tls-key=')) {
      tlsKeyPath = trimToNull(arg.substring('--tls-key='.length));
    }
  }

  if (token != null && token.trim().isEmpty) {
    token = null;
  }

  // Explicit cert/key paths imply TLS even without --tls; otherwise the
  // operator's paths would be silently ignored. Same rule for the env-var
  // equivalents — passing NIGHTSHADE_TLS_CERT must enable TLS.
  if (tlsCertPath != null || tlsKeyPath != null) {
    tlsEnabled = true;
  }

  final hasAuthentication =
      token != null || requireAuth || scopedTokens.isNotEmpty;
  return HeadlessAuthConfig(
    token: token,
    requireAuth: requireAuth,
    bindLocalOnly: !hasAuthentication && !allowUnauthenticatedLan,
    port: port,
    scopedTokens: Map.unmodifiable(scopedTokens),
    corsAllowedOrigins: List.unmodifiable(corsAllowedOrigins),
    pairingPrintCodes: pairingPrintCodes,
    pairingMode: pairingMode,
    tlsEnabled: tlsEnabled,
    tlsCertPath: tlsCertPath,
    tlsKeyPath: tlsKeyPath,
  );
}

void _addScopedTokenFromEnv(
  Map<String, HeadlessTokenScope> scopedTokens,
  String envName,
  HeadlessTokenScope scope,
) {
  _addScopedToken(scopedTokens, Platform.environment[envName], scope);
}

void _addScopedToken(
  Map<String, HeadlessTokenScope> scopedTokens,
  String? token,
  HeadlessTokenScope scope,
) {
  final normalizedToken = token?.trim();
  if (normalizedToken == null || normalizedToken.isEmpty) {
    return;
  }
  scopedTokens[normalizedToken] = scope;
}
