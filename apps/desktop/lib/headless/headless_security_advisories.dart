/// Operator-facing security advisories derived from the resolved bind / auth /
/// TLS configuration.
///
/// Returned as plain strings so both the startup stdout banner and the
/// structured log can surface them. The list is empty when the configuration is
/// safe: either the server is loopback-only, or its LAN exposure is both
/// authenticated and TLS-encrypted. The intent is that a headless operator who
/// opens the server to the LAN cannot miss the two real footguns — no
/// authentication, and credentials in cleartext — even though both are
/// reachable configurations on purpose.
List<String> headlessSecurityAdvisories({
  required bool bindLocalOnly,
  required bool hasAuth,
  required bool tlsEnabled,
}) {
  // Loopback-only deployments are not reachable from the network, so none of
  // the LAN-exposure advisories apply.
  if (bindLocalOnly) return const [];

  final advisories = <String>[];

  if (!hasAuth) {
    advisories.add(
      'UNAUTHENTICATED LAN CONTROL: anyone on this network can control your '
      'equipment with no token. Use --require-auth or --auth-token unless this '
      'is an isolated, fully-trusted network.',
    );
  }

  if (!tlsEnabled) {
    advisories.add(
      'TLS IS OFF: the bearer token and pairing codes travel UNENCRYPTED over '
      'the LAN and can be captured by anyone on the same network segment. Pass '
      '--tls to encrypt (a self-signed certificate is auto-provisioned).',
    );
  }

  return advisories;
}
