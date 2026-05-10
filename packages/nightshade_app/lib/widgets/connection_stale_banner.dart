import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Set true when the WebSocket connection to a remote backend has been
/// down briefly but is still within the reconnect grace window (audit
/// §3.6). The mobile app drives this; desktop/headless do not flip it.
final connectionStaleProvider = StateProvider<bool>((_) => false);

/// Inline banner shown across all screens while the mobile app is mid-
/// reconnect. Replaces the old "session torn down after 3 polls" UX.
class ConnectionStaleBanner extends ConsumerWidget {
  const ConnectionStaleBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stale = ref.watch(connectionStaleProvider);
    if (!stale) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>();
    final bg = colors?.warning ?? Colors.amber.shade700;
    final fg = colors?.background ?? Colors.black;

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
          ],
        ),
      ),
    );
  }
}
