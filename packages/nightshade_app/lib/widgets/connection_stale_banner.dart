import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Set true when the WebSocket connection to a remote backend has been
/// down briefly but is still within the reconnect grace window (audit
/// §3.6). The mobile app drives this; desktop/headless do not flip it.
final connectionStaleProvider = StateProvider<bool>((_) => false);

/// Inline banner shown across all screens while the mobile app is mid-
/// reconnect. Replaces the old "session torn down after 3 polls" UX.
///
/// During the 30-second grace window the operator now also gets a
/// "Retry" button so they can force an immediate reconnect attempt
/// instead of waiting for the exponential-backoff timer to fire
/// The button is a no-op when the current
/// backend is not a [NetworkBackend] (e.g. host-side desktop).
class ConnectionStaleBanner extends ConsumerStatefulWidget {
  const ConnectionStaleBanner({super.key});

  @override
  ConsumerState<ConnectionStaleBanner> createState() =>
      _ConnectionStaleBannerState();
}

class _ConnectionStaleBannerState extends ConsumerState<ConnectionStaleBanner> {
  bool _retrying = false;

  Future<void> _handleRetry() async {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) {
      // No remote session to reconnect — the banner shouldn't normally
      // show in that case, but if it does we just no-op rather than
      // throw, because spinning forever would be worse UX.
      return;
    }
    setState(() => _retrying = true);
    try {
      await backend.reconnectNow();
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stale = ref.watch(connectionStaleProvider);
    if (!stale) return const SizedBox.shrink();

    final colors = NightshadeColors.of(context);
    final bg = colors.warning;
    final fg = colors.background;

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(fg),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Reconnecting to server… session controls may be stale.',
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _retrying ? null : _handleRetry,
              child: Text(
                _retrying ? 'Retrying…' : 'Retry',
                style: TextStyle(
                  color: _retrying ? fg.withValues(alpha: 0.5) : fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
