import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds runtime state for the embedded web server.
///
/// This is separate from persisted AppSettings because it tracks
/// transient runtime info like whether the server is actually running,
/// the actual port (which may differ if the configured port was busy),
/// the local network IP, and the collaboration viewer count.
class WebServerState {
  final bool isRunning;
  final int configuredPort;
  final int actualPort;
  final String localIp;
  final int activeViewers;
  final bool bindLocalOnly;
  final bool requiresAuthentication;
  final bool dashboardAvailable;
  final String lastError;

  const WebServerState({
    this.isRunning = false,
    this.configuredPort = 8080,
    this.actualPort = 8080,
    this.localIp = '',
    this.activeViewers = 0,
    this.bindLocalOnly = true,
    this.requiresAuthentication = false,
    this.dashboardAvailable = false,
    this.lastError = '',
  });

  /// The URL for accessing the web dashboard from the local machine.
  String get localUrl => 'http://localhost:$actualPort';

  /// The URL for accessing the web dashboard from other devices on the network.
  String get networkUrl =>
      !bindLocalOnly && localIp.isNotEmpty ? 'http://$localIp:$actualPort' : '';

  WebServerState copyWith({
    bool? isRunning,
    int? configuredPort,
    int? actualPort,
    String? localIp,
    int? activeViewers,
    bool? bindLocalOnly,
    bool? requiresAuthentication,
    bool? dashboardAvailable,
    String? lastError,
  }) {
    return WebServerState(
      isRunning: isRunning ?? this.isRunning,
      configuredPort: configuredPort ?? this.configuredPort,
      actualPort: actualPort ?? this.actualPort,
      localIp: localIp ?? this.localIp,
      activeViewers: activeViewers ?? this.activeViewers,
      bindLocalOnly: bindLocalOnly ?? this.bindLocalOnly,
      requiresAuthentication:
          requiresAuthentication ?? this.requiresAuthentication,
      dashboardAvailable: dashboardAvailable ?? this.dashboardAvailable,
      lastError: lastError ?? this.lastError,
    );
  }
}

/// Notifier for web server runtime state.
///
/// The desktop main.dart should call [setRunning] after starting the web server,
/// and update viewer counts from the collaboration session manager.
class WebServerStateNotifier extends StateNotifier<WebServerState> {
  WebServerStateNotifier() : super(const WebServerState()) {
    _resolveLocalIp();
  }

  void setRunning({
    required bool isRunning,
    required int actualPort,
    int? configuredPort,
    bool? bindLocalOnly,
    bool? requiresAuthentication,
    bool? dashboardAvailable,
    String? lastError,
  }) {
    state = state.copyWith(
      isRunning: isRunning,
      actualPort: actualPort,
      configuredPort: configuredPort ?? state.configuredPort,
      bindLocalOnly: bindLocalOnly ?? state.bindLocalOnly,
      requiresAuthentication:
          requiresAuthentication ?? state.requiresAuthentication,
      dashboardAvailable: dashboardAvailable ?? state.dashboardAvailable,
      lastError: lastError ?? '',
    );
  }

  void setStopped({
    int? configuredPort,
    int? actualPort,
    bool? bindLocalOnly,
    bool? requiresAuthentication,
    bool? dashboardAvailable,
    String? lastError,
  }) {
    state = state.copyWith(
      isRunning: false,
      actualPort: actualPort ?? state.actualPort,
      configuredPort: configuredPort ?? state.configuredPort,
      bindLocalOnly: bindLocalOnly ?? state.bindLocalOnly,
      requiresAuthentication:
          requiresAuthentication ?? state.requiresAuthentication,
      dashboardAvailable: dashboardAvailable ?? state.dashboardAvailable,
      activeViewers: 0,
      lastError: lastError ?? '',
    );
  }

  void setActiveViewers(int count) {
    state = state.copyWith(activeViewers: count);
  }

  void setConfiguredPort(int port) {
    state = state.copyWith(configuredPort: port);
  }

  Future<void> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            state = state.copyWith(localIp: addr.address);
            return;
          }
        }
      }
    } catch (_) {
      // Network interface enumeration is best-effort
    }
  }
}

final webServerStateProvider =
    StateNotifierProvider<WebServerStateNotifier, WebServerState>(
  (ref) => WebServerStateNotifier(),
);
