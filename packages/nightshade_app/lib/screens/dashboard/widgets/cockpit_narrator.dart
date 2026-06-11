import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/narrator/narrator_feed.dart';

/// Cockpit "Night Narrator" tile — the dashboard surface for the Narrator's
/// session-long feed of plain-language insight cards ("the story of your
/// night").
///
/// Self-chromed like the other cockpit panels: it wraps itself in a
/// [NightshadeCard] with a `sparkles` header so the dashboard tile frame draws
/// no resting border. The feed is sessionful while a run is active (keyed off
/// [sessionStateProvider]'s `dbSessionId`) and falls back to the sessionless
/// recent feed when idle, so the tile always has something honest to show.
///
/// Caps at ~8 events with internal scrolling via [NarratorFeed.compact].
class CockpitNarrator extends ConsumerWidget {
  const CockpitNarrator({super.key});

  /// Cap height so the tile stays compact on the dense dashboard; the feed
  /// scrolls internally past this.
  static const double _maxFeedHeight = 320;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final dbSessionId = ref.watch(
      sessionStateProvider.select((s) => s.dbSessionId),
    );

    // Sessionful while a run is active; sessionless recent feed when idle.
    final AsyncValue<List<NarratorEvent>> feed = dbSessionId != null
        ? ref.watch(narratorFeedProvider(dbSessionId))
        : ref.watch(recentNarratorFeedProvider);

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'NIGHT NARRATOR',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
              const Spacer(),
              feed.maybeWhen(
                data: (events) => events.isEmpty
                    ? const SizedBox.shrink()
                    : Text(
                        '${events.length}',
                        style: NightshadeTypography.withTabular(
                          NightshadeTypography.labelStrongSm.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxFeedHeight),
            child: feed.when(
              data: (events) => NarratorFeed.compact(events: events),
              loading: () => const NarratorFeed.compact(
                events: <NarratorEvent>[],
              ),
              error: (_, __) => _ErrorRow(colors: colors),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim error row — keeps the tile honest if the feed stream faults rather
/// than vanishing or throwing.
class _ErrorRow extends StatelessWidget {
  final NightshadeColors colors;

  const _ErrorRow({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(LucideIcons.alertTriangle, size: 15, color: colors.textMuted),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: Text(
            "The Narrator's feed is unavailable right now.",
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12_5,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
