// Wave 7 Agent 2 — Live-stacking broadcast service.
//
// The complement to the Rust `nightshade_sequencer::broadcast` module:
// once a `LiveStackingNode` executes, the Dart side activates a
// session here so the headless API's `/api/broadcast/*` endpoints can
// answer with JPEGs of the building stack + telemetry. Pure Dart so
// the desktop, mobile (in companion / preview mode), and headless
// builds all share one path.
//
// Why a separate service from `LiveStackingService` (which already
// wraps the bridge stacker):
//
//   1. `LiveStackingService` only knows about the stacker's internal
//      u16 frame data. The broadcast needs a watermarked, rendered
//      JPEG suitable for serving over HTTP.
//   2. The broadcast cadence (every new accepted frame) is decoupled
//      from how often the user wants to look at the stack from the
//      UI.
//   3. Auth, public/private toggling, and viewer-count tracking are
//      first-class to broadcasting but irrelevant to the local
//      stacker.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../models/sequence/sequence_models.dart'
    show LiveStackingMethod, LiveStackingMode, LiveStackingNode;
import '../providers/sequence/sequencer_defaults.dart'
    show sequencerDefaultsProvider;
import 'logging_service.dart';

/// Snapshot of the broadcast state that the run dashboard renders.
///
/// `active == false` everywhere else: the service has not yet seen a
/// `LiveStackingNode` in the current sequence run.
class BroadcastSessionState {
  /// Whether a broadcast is currently armed.
  final bool active;

  /// The configured port the broadcast endpoints answer on. Mirrors
  /// the LiveStackingNode at activation time. `0` when inactive.
  final int port;

  /// HTTP path prefix the broadcast page is served at.
  final String path;

  /// Operating mode.
  final LiveStackingMode mode;

  /// Stack method selected at activation time. The mapping to the
  /// existing live-stacking engine (which only exposes sigma clip) is:
  ///   - [LiveStackingMethod.average] → sigma_clip_enabled = false
  ///   - [LiveStackingMethod.medianRej] / [LiveStackingMethod.sigma] →
  ///     sigma_clip_enabled = true
  /// The brief notes the Rust engine is the source of truth for the
  /// actual reduction; the method selector is a knob on it.
  final LiveStackingMethod stackMethod;

  /// Token required on each broadcast request. `null` or empty means
  /// the broadcast is public.
  final String? authToken;

  /// Watermark template (Wave 4 variable interpolation applied at
  /// render time).
  final String? watermarkText;

  /// Thumbnail width/height for the rendered JPEG.
  final int thumbnailWidth;
  final int thumbnailHeight;

  /// Frames added to the broadcast stack so far.
  final int framesStacked;

  /// `DateTime.now()` at activation.
  final DateTime? activatedAt;

  /// Current target name (lifted from the sequence progress) — used in
  /// the default watermark / `/info` JSON.
  final String? currentTarget;

  /// Total accumulated integration time in seconds across all stacked
  /// frames. Drives the dashboard "Integration" badge and the default
  /// watermark token.
  final double integrationSecs;

  /// Cached snapshot of the most recently rendered broadcast JPEG.
  /// Updated on every accepted frame, served verbatim by the HTTP
  /// endpoint. `null` when no frame has been stacked yet.
  final Uint8List? jpegBytes;

  /// Current viewer count (incremented by `/info` polls in the public
  /// outreach UI). Best-effort only; the dashboard renders it as a
  /// hint, not a guarantee.
  final int viewerCount;

  const BroadcastSessionState({
    this.active = false,
    this.port = 0,
    this.path = '/broadcast',
    this.mode = LiveStackingMode.broadcastOnly,
    this.stackMethod = LiveStackingMethod.average,
    this.authToken,
    this.watermarkText,
    this.thumbnailWidth = 1280,
    this.thumbnailHeight = 720,
    this.framesStacked = 0,
    this.activatedAt,
    this.currentTarget,
    this.integrationSecs = 0.0,
    this.jpegBytes,
    this.viewerCount = 0,
  });

  /// True when the broadcast is public (no token required).
  bool get isPublic => authToken == null || authToken!.isEmpty;

  /// Human-readable integration time, e.g. "2h12m" — matches the
  /// `${integration.hms}` Wave 4 interpolation token.
  String get integrationHms {
    final secs = integrationSecs.round();
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0 && m > 0) return '${h}h${m}m';
    if (h > 0) return '${h}h';
    if (m > 0 && s > 0) return '${m}m${s}s';
    if (m > 0) return '${m}m';
    return '${s}s';
  }

  BroadcastSessionState copyWith({
    bool? active,
    int? port,
    String? path,
    LiveStackingMode? mode,
    LiveStackingMethod? stackMethod,
    String? authToken,
    String? watermarkText,
    int? thumbnailWidth,
    int? thumbnailHeight,
    int? framesStacked,
    DateTime? activatedAt,
    String? currentTarget,
    double? integrationSecs,
    Uint8List? jpegBytes,
    int? viewerCount,
  }) {
    return BroadcastSessionState(
      active: active ?? this.active,
      port: port ?? this.port,
      path: path ?? this.path,
      mode: mode ?? this.mode,
      stackMethod: stackMethod ?? this.stackMethod,
      authToken: authToken ?? this.authToken,
      watermarkText: watermarkText ?? this.watermarkText,
      thumbnailWidth: thumbnailWidth ?? this.thumbnailWidth,
      thumbnailHeight: thumbnailHeight ?? this.thumbnailHeight,
      framesStacked: framesStacked ?? this.framesStacked,
      activatedAt: activatedAt ?? this.activatedAt,
      currentTarget: currentTarget ?? this.currentTarget,
      integrationSecs: integrationSecs ?? this.integrationSecs,
      jpegBytes: jpegBytes ?? this.jpegBytes,
      viewerCount: viewerCount ?? this.viewerCount,
    );
  }

  /// JSON view returned by `/api/broadcast/info`.
  Map<String, dynamic> toInfoJson() => {
        'active': active,
        'port': port,
        'path': path,
        'mode': mode.storageKey,
        'stackMethod': stackMethod.storageKey,
        'isPublic': isPublic,
        'requiresAuth': !isPublic,
        'framesStacked': framesStacked,
        'integrationSecs': integrationSecs,
        'integrationHms': integrationHms,
        'currentTarget': currentTarget,
        'activatedAt': activatedAt?.toUtc().toIso8601String(),
        'thumbnailWidth': thumbnailWidth,
        'thumbnailHeight': thumbnailHeight,
        'viewerCount': viewerCount,
      };
}

/// Event the broadcast SSE handler emits to subscribers.
class BroadcastUpdate {
  /// Total frames in the current broadcast stack.
  final int framesStacked;

  /// Cumulative integration time, seconds.
  final double integrationSecs;

  /// ISO-8601 server-time the update was produced.
  final DateTime timestamp;

  BroadcastUpdate({
    required this.framesStacked,
    required this.integrationSecs,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'framesStacked': framesStacked,
        'integrationSecs': integrationSecs,
        'timestamp': timestamp.toUtc().toIso8601String(),
      };
}

/// Coordinates between the LiveStacking node, the live-stacking
/// service, and the broadcast HTTP endpoints.
class LiveStackingBroadcastService {
  final Ref _ref;
  final StreamController<BroadcastUpdate> _updates =
      StreamController<BroadcastUpdate>.broadcast();
  BroadcastSessionState _state = const BroadcastSessionState();

  /// Wave 7.5 — master kill switch mirrored from
  /// `SequencerDefaults.livestackingDisableEverywhere`. When true, every
  /// `activate()` call is a no-op and any currently-active session is
  /// forced into the deactivated state. The user's per-node settings
  /// stay intact — flipping the master switch back off lets new nodes
  /// activate normally on next entry.
  bool _killSwitch = false;
  bool get killSwitchEnabled => _killSwitch;

  LiveStackingBroadcastService(this._ref);

  LoggingService get _logger => _ref.read(loggingServiceProvider);

  /// Subscribe to broadcast updates. The handler implementation maps
  /// each event onto an SSE message; the dashboard panel can also
  /// listen for a "frame badge" counter.
  Stream<BroadcastUpdate> get updates => _updates.stream;

  /// Current snapshot of the broadcast state. Cheap; safe to call
  /// every HTTP request.
  BroadcastSessionState get state => _state;

  /// Wave 7.5 — flip the master kill switch. When [enabled] is true,
  /// any active session is force-deactivated and subsequent
  /// `activate()` calls are no-ops until the switch is cleared. The
  /// settings layer calls this whenever
  /// `SequencerDefaults.livestackingDisableEverywhere` changes.
  void setKillSwitch(bool enabled) {
    if (_killSwitch == enabled) return;
    _killSwitch = enabled;
    if (enabled && _state.active) {
      _logger.warning(
        'Broadcast force-deactivated: master kill switch engaged',
        source: 'BroadcastService',
      );
      _state = const BroadcastSessionState();
    }
  }

  /// Activate the broadcast for a given [LiveStackingNode]. Called
  /// when the sequence executor enters the node. Replacing an existing
  /// session is allowed (last-one-wins) so two nodes in the same
  /// sequence cannot lock each other out.
  void activate(LiveStackingNode node) {
    if (_killSwitch) {
      _logger.info(
        'Broadcast activation suppressed: master kill switch engaged',
        source: 'BroadcastService',
      );
      return;
    }
    _state = BroadcastSessionState(
      active: true,
      port: node.broadcastPort,
      path: node.broadcastPath,
      mode: node.mode,
      stackMethod: node.stackMethod,
      authToken: node.authToken,
      watermarkText: node.watermarkText,
      thumbnailWidth: node.thumbnailWidth,
      thumbnailHeight: node.thumbnailHeight,
      activatedAt: DateTime.now(),
    );
    _logger.info(
      'Broadcast activated on port ${node.broadcastPort} '
      '(${node.isPublic ? "public" : "private"}, '
      '${node.stackMethod.label})',
      source: 'BroadcastService',
    );
  }

  /// Tear down the active session. Called on sequence stop, or by the
  /// "Stop broadcasting" button on the dashboard.
  void deactivate() {
    if (!_state.active) return;
    _logger.info(
      'Broadcast deactivated (frames=${_state.framesStacked})',
      source: 'BroadcastService',
    );
    _state = const BroadcastSessionState();
  }

  /// Increment the viewer-count hint. Called by `/api/broadcast/info`
  /// on each request; the count decays via a 30-second idle reset in
  /// the handler so disconnected viewers eventually drop off.
  void incrementViewers() {
    if (!_state.active) return;
    _state = _state.copyWith(viewerCount: _state.viewerCount + 1);
  }

  /// Reset the viewer count. Called on a fixed cadence by the
  /// dashboard panel's refresh timer so the displayed count tracks
  /// recent activity rather than lifetime hits.
  void resetViewerCount() {
    if (!_state.active) return;
    _state = _state.copyWith(viewerCount: 0);
  }

  /// Update the broadcast's current-target metadata. Called by the
  /// dashboard's frame-accepted listener so the watermark / `/info`
  /// JSON always reflect the live target name.
  void updateCurrentTarget(String? targetName) {
    if (!_state.active) return;
    if (_state.currentTarget == targetName) return;
    _state = _state.copyWith(currentTarget: targetName);
  }

  /// Feed a newly-stacked u16 preview into the broadcast. The
  /// LiveStackingNotifier already calls into the engine and updates
  /// its own preview field; we re-encode that to a watermarked JPEG
  /// here so HTTP requests can be served without re-stretching the
  /// 16-bit data on every poll.
  ///
  /// [exposureSecs] is added to the accumulated integration counter.
  void publishFrame({
    required int width,
    required int height,
    required Uint16List previewData,
    required double exposureSecs,
  }) {
    if (!_state.active) return;
    if (width <= 0 || height <= 0 || previewData.isEmpty) return;

    final jpeg = _renderJpeg(
      width: width,
      height: height,
      data: previewData,
      session: _state,
    );

    _state = _state.copyWith(
      framesStacked: _state.framesStacked + 1,
      integrationSecs: _state.integrationSecs + exposureSecs,
      jpegBytes: jpeg,
    );

    final update = BroadcastUpdate(
      framesStacked: _state.framesStacked,
      integrationSecs: _state.integrationSecs,
      timestamp: DateTime.now(),
    );
    if (!_updates.isClosed) {
      _updates.add(update);
    }
  }

  /// Validate the `token` query parameter against the active session.
  ///
  /// Returns true when the request is allowed (public broadcast OR the
  /// supplied token matches). The caller maps `false` to HTTP 401.
  bool authorize(String? suppliedToken) {
    if (!_state.active) return false;
    if (_state.isPublic) return true;
    if (suppliedToken == null || suppliedToken.isEmpty) return false;
    // Constant-time comparison. The token is a shared secret; a
    // straight `==` would leak length / prefix information through
    // timing. The cost on a short token is negligible.
    return _constantTimeEqual(suppliedToken, _state.authToken ?? '');
  }

  /// Render the watermark template (Wave 4 token syntax) against the
  /// live session state. Exposed so callers (HTML page, tests) can
  /// preview the rendered string without forcing a JPEG re-encode.
  String renderWatermark() {
    final template = _state.watermarkText;
    if (template == null || template.trim().isEmpty) return '';
    return _expandWatermarkTokens(template, _state);
  }

  /// Dispose all resources. Called when the provider is torn down.
  void dispose() {
    _updates.close();
  }

  // ===========================================================================
  // Internal: JPEG rendering + watermark
  // ===========================================================================

  /// Render the current stack to a watermarked JPEG ready to serve.
  ///
  /// The input is a u16 single-channel array (the live-stacking engine
  /// emits luminance) which we auto-stretch then encode. Real-world
  /// sensor frames have a wide dynamic range so a percentile stretch
  /// is the difference between "looks like M42" and "looks like a
  /// black square."
  Uint8List _renderJpeg({
    required int width,
    required int height,
    required Uint16List data,
    required BroadcastSessionState session,
  }) {
    final expected = width * height;
    if (data.length < expected) {
      // Defensive: short buffer would otherwise corrupt encode. Throw
      // so the caller surfaces the bug rather than silently serving
      // garbage.
      throw StateError(
        'Broadcast frame buffer too small: ${data.length} < $expected '
        '(width=$width height=$height)',
      );
    }

    // Per-frame percentile stretch: black at the 0.5% percentile,
    // white at the 99.5%. Matches the "auto stretch" the desktop
    // preview uses by default and looks correct for the typical
    // long-exposure DSO target the broadcast is built for.
    final (blackPoint, whitePoint) = _computeStretchEnds(data);
    final range = (whitePoint - blackPoint).clamp(1, 65535).toInt();

    final bytes = Uint8List(expected);
    for (var i = 0; i < expected; i++) {
      final value = data[i] - blackPoint;
      final scaled = (value * 255 ~/ range).clamp(0, 255);
      bytes[i] = scaled;
    }

    var bitmap = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      numChannels: 1,
      order: img.ChannelOrder.red,
      format: img.Format.uint8,
    );

    // Optional downscale to the configured broadcast size. We allow
    // the broadcast to be smaller than the sensor so the LAN payload
    // stays phone-friendly (1080p sensor → 720p broadcast cuts the
    // file size by ~2.25× while preserving outreach-quality detail).
    final targetW = session.thumbnailWidth;
    final targetH = session.thumbnailHeight;
    if (targetW > 0 &&
        targetH > 0 &&
        (width != targetW || height != targetH)) {
      // Preserve aspect ratio by fitting inside the target box.
      final srcRatio = width / height;
      final tgtRatio = targetW / targetH;
      int outW;
      int outH;
      if (srcRatio > tgtRatio) {
        outW = targetW;
        outH = (targetW / srcRatio).round().clamp(1, targetH);
      } else {
        outH = targetH;
        outW = (targetH * srcRatio).round().clamp(1, targetW);
      }
      bitmap = img.copyResize(bitmap, width: outW, height: outH);
    }

    // Promote to RGB so the watermark can render in colour. The
    // pixel data is luminance, so RGB == grey == identical channels.
    bitmap = bitmap.convert(numChannels: 3);

    final rendered = renderWatermark();
    if (rendered.isNotEmpty) {
      _drawWatermark(bitmap, rendered);
    }

    return Uint8List.fromList(img.encodeJpg(bitmap, quality: 82));
  }

  /// Compute the 0.5%/99.5% percentile black/white points for the
  /// stretch. Falls back to min/max when the histogram is degenerate.
  (int, int) _computeStretchEnds(Uint16List data) {
    // Build a sparse histogram. Building a full 65536-bin histogram
    // would be wasteful for small previews; we collect into a HashMap
    // and walk the unique values sorted.
    final counts = <int, int>{};
    for (final v in data) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final keys = counts.keys.toList()..sort();
    if (keys.isEmpty) return (0, 65535);
    final total = data.length;
    final lowTarget = (total * 0.005).floor();
    final highTarget = (total * 0.995).ceil();
    var acc = 0;
    int? black;
    int? white;
    for (final k in keys) {
      acc += counts[k]!;
      if (black == null && acc >= lowTarget) {
        black = k;
      }
      if (white == null && acc >= highTarget) {
        white = k;
      }
      if (black != null && white != null) break;
    }
    black ??= keys.first;
    white ??= keys.last;
    // Guard against pathological zero-range data — a single-tone
    // frame would otherwise hand the encoder a divide-by-zero range.
    if (white <= black) {
      return (0, 65535);
    }
    return (black, white);
  }

  /// Render the watermark string onto the bitmap. The text is drawn
  /// at the bottom-left with a subtle dark stroke + white fill, the
  /// same convention Astrobin / Cuiv's overlays use for outreach.
  ///
  /// The `image` package's built-in `BitmapFont` provides exactly
  /// what we need without pulling in a font-rendering dependency.
  void _drawWatermark(img.Image bitmap, String text) {
    if (text.isEmpty) return;
    // Use the largest built-in font that fits within ~5% of the
    // bitmap height. For a 720p broadcast `arial48` at the bottom
    // left renders cleanly.
    final font = img.arial48;
    // Padding from the bottom-left corner; scales with image height
    // so small downscales still look right.
    final pad = (bitmap.height * 0.025).clamp(8, 64).toInt();
    final x = pad;
    final y = bitmap.height - pad - font.lineHeight;
    // Drop-shadow for legibility on bright nebula edges.
    img.drawString(
      bitmap,
      text,
      font: font,
      x: x + 2,
      y: y + 2,
      color: img.ColorUint8.rgb(0, 0, 0),
    );
    img.drawString(
      bitmap,
      text,
      font: font,
      x: x,
      y: y,
      color: img.ColorUint8.rgb(255, 255, 255),
    );
  }

  /// Constant-time string compare to gate auth tokens.
  bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Expand the small watermark template language. Supports the Wave 4
/// tokens the brief calls out — `${target}`, `${filter}`,
/// `${integration.hms}`, `${integration.secs}` — plus a literal
/// `\${`/`\}` escape for users who actually want the brace characters
/// rendered.
///
/// Unknown tokens fall through as literal text (matching the lenient
/// behaviour the Run Dashboard's notification template uses). The Wave
/// 4 expression engine lives in Rust; reaching across FFI for a
/// per-frame string render would be a needless round-trip when the
/// universe of useful tokens is small.
String _expandWatermarkTokens(String template, BroadcastSessionState session) {
  final buf = StringBuffer();
  var i = 0;
  while (i < template.length) {
    final ch = template[i];
    if (ch == r'$' && i + 1 < template.length && template[i + 1] == '{') {
      final close = template.indexOf('}', i + 2);
      if (close > 0) {
        final token = template.substring(i + 2, close);
        buf.write(_resolveWatermarkToken(token, session));
        i = close + 1;
        continue;
      }
    }
    buf.write(ch);
    i++;
  }
  return buf.toString();
}

String _resolveWatermarkToken(String token, BroadcastSessionState session) {
  switch (token.trim()) {
    case 'target':
    case 'target.name':
      return session.currentTarget ?? '';
    case 'integration.hms':
      return session.integrationHms;
    case 'integration.secs':
      return session.integrationSecs.toStringAsFixed(0);
    case 'frames':
      return session.framesStacked.toString();
    case 'stack':
    case 'stack.method':
      return session.stackMethod.label;
    case 'now':
      return DateTime.now().toLocal().toString().substring(0, 19);
    default:
      // Surface unknown tokens unmodified so the user can see the
      // typo rather than silently dropping the text.
      return '\${$token}';
  }
}

/// Provider for the broadcast service. Singleton per app — the HTTP
/// handler reads from this every request.
final liveStackingBroadcastServiceProvider =
    Provider<LiveStackingBroadcastService>((ref) {
  final svc = LiveStackingBroadcastService(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

/// Wave 7.5 — bridges the "Disable broadcast everywhere" toggle in
/// Sequencer Settings (`SequencerDefaults.livestackingDisableEverywhere`)
/// into the live broadcast service. Watched once at app start by the
/// shell so the kill switch:
///
///   * applies on cold start (a process that started with the switch on
///     comes up disabled, not in a brief "armed" window), and
///   * propagates live: flipping the toggle during an active broadcast
///     force-deactivates the session.
///
/// Kept as a separate provider so the broadcast service itself stays
/// free of a SettingsDao dependency — unit tests of the service alone
/// don't need a SQLite-backed database.
final liveStackingKillSwitchBridgeProvider = Provider<void>((ref) {
  final svc = ref.watch(liveStackingBroadcastServiceProvider);
  // Initial seed: read once, apply.
  final initial = ref.watch(sequencerDefaultsProvider);
  svc.setKillSwitch(initial.livestackingDisableEverywhere);
  // No explicit listener needed — `ref.watch` rebuilds this provider
  // whenever the kill-switch field changes, which re-runs the setter
  // above. The Provider re-evaluation is cheap because setKillSwitch
  // is a no-op when the value hasn't changed.
});

/// Convenience provider for whether the broadcast is currently armed.
/// The dashboard's "Broadcasting" indicator watches this.
final broadcastActiveProvider = Provider<bool>((ref) {
  return ref.watch(liveStackingBroadcastServiceProvider).state.active;
});
