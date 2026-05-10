import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Set true while a sequence is running on iOS so the UI displays the
/// "honest banner" advisory (audit §3.2). Mobile code drives this; desktop
/// builds never flip it.
final iosBackgroundBannerProvider = StateProvider<bool>((_) => false);

/// Persistent advisory shown across all screens while a sequence runs on
/// iOS. iOS suspends the app within minutes of backgrounding and we don't
/// declare `UIBackgroundModes`, so monitoring stops if the user switches
/// apps. Surfacing this is the v2.5.0 "honest path" before W2 ships a real
/// background-task implementation.
class IosBackgroundBanner extends ConsumerWidget {
  const IosBackgroundBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(iosBackgroundBannerProvider);
    if (!visible) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.extension<NightshadeColors>();
    final warningColor = colors?.warning ?? Colors.amber.shade700;
    final onWarning = colors?.background ?? Colors.black;

    return SafeArea(
      bottom: false,
      child: Material(
        color: warningColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: onWarning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'iOS may pause monitoring while this app is in the '
                  'background. Keep the app foreground or rely on push '
                  'notifications from the desktop.',
                  style: TextStyle(
                    color: onWarning,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
