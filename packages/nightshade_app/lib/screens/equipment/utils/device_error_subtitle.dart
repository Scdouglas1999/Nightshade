// DEV-P3-4: shared widget that renders the subtitle line for a device
// card. When the device is in error state, it shows the pretty-printed
// raw driver message with a tooltip carrying the full text; otherwise
// it falls back to the descriptive subtitle the card normally shows.
//
// Split out into a public widget (rather than living inline in
// unified_base_device_card.dart, which is a `part of` partial) so the
// equipment widget tests can construct it directly.

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'driver_error_pretty.dart';

class DeviceErrorSubtitle extends StatelessWidget {
  /// The descriptive subtitle the card normally shows (device name,
  /// short purpose blurb, etc.). Rendered verbatim when the device is
  /// not in an error state.
  final String descriptiveSubtitle;

  /// Whether the owning device is currently in
  /// `DeviceConnectionState.error`.
  final bool isError;

  /// The raw driver error message — typically
  /// `state.lastError?.message`. When null/empty, the widget falls
  /// back to [descriptiveSubtitle] even if [isError] is true.
  final String? errorMessage;

  final NightshadeColors colors;

  const DeviceErrorSubtitle({
    super.key,
    required this.descriptiveSubtitle,
    required this.isError,
    required this.errorMessage,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final raw = errorMessage?.trim();
    if (isError && raw != null && raw.isNotEmpty) {
      final pretty = PrettyError.format(raw);
      return Tooltip(
        message: pretty.full,
        waitDuration: const Duration(milliseconds: 250),
        child: Row(
          children: [
            Icon(LucideIcons.alertCircle, size: 11, color: colors.error),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                pretty.short,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.error,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }
    return Text(
      descriptiveSubtitle,
      style: TextStyle(
        fontSize: 11,
        color: colors.textMuted,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
