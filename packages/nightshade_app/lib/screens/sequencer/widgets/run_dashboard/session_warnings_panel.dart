import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Compact "Session warnings" sub-panel that surfaces non-fatal warnings
/// accumulated by the live sequence run.
///
/// Reads `liveSequenceStatsProvider.warningMessages` — the same list that
/// the post-session report renders. Hidden entirely when there are no
/// warnings so an idle dashboard stays clean.
///
/// Behavior:
///   * Header shows the count and an expand chevron.
///   * Tapping the header expands the panel inline; tapping again
///     collapses it.
///   * Each warning gets its own row with a yellow chevron icon and the
///     full message text (multi-line, no truncation — the user must be
///     able to read every word).
class RunDashboardSessionWarningsPanel extends ConsumerStatefulWidget {
  const RunDashboardSessionWarningsPanel({super.key});

  @override
  ConsumerState<RunDashboardSessionWarningsPanel> createState() =>
      _RunDashboardSessionWarningsPanelState();
}

class _RunDashboardSessionWarningsPanelState
    extends ConsumerState<RunDashboardSessionWarningsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final stats = ref.watch(liveSequenceStatsProvider);
    final warnings = stats?.warningMessages ?? const <String>[];
    if (warnings.isEmpty) return const SizedBox.shrink();

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 14, color: colors.warning),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Expanded(
                    child: Text(
                      'SESSION WARNINGS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.warning.withValues(alpha: 0.15),
                      borderRadius:
                          BorderRadius.circular(NightshadeTokens.radiusXs),
                    ),
                    child: Text(
                      '${warnings.length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.warning,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Icon(
                    _expanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 14,
                    color: colors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            for (var i = 0; i < warnings.length; i++) ...[
              _WarningRow(colors: colors, message: warnings[i]),
              if (i < warnings.length - 1)
                Divider(
                  height: NightshadeTokens.spaceSm * 2,
                  color: colors.border,
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  final NightshadeColors colors;
  final String message;

  const _WarningRow({required this.colors, required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child:
              Icon(LucideIcons.chevronRight, size: 13, color: colors.warning),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
