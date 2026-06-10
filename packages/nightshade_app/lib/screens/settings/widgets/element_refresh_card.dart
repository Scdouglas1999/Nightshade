import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../utils/snackbar_helper.dart';

/// Settings card for **live MPC orbital-element refresh** — fetching fresh
/// minor-planet (MPCORB) and comet (CometEls) elements on a schedule.
///
/// Refreshed bodies feed the planetarium's minor-planet overlay and the
/// omnibox search. Offline-safe: a failed refresh keeps the cached set and the
/// "last updated" line reflects the cache age.
class ElementRefreshCard extends ConsumerWidget {
  const ElementRefreshCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.nightshadeColors;
    final status = ref.watch(elementRefreshControllerProvider);
    final controller = ref.read(elementRefreshControllerProvider.notifier);
    final configAsync = ref.watch(elementRefreshConfigProvider);
    final config = configAsync.valueOrNull ?? const ElementRefreshConfig();
    final service = ref.read(elementRefreshServiceProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(
          color: status.hasData
              ? colors.success.withValues(alpha: 0.3)
              : colors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(NightshadeIcons.refresh, color: colors.primary, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Minor Planets & Comets (MPC)',
                  style: NightshadeTypography.h4
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Downloads fresh asteroid (MPCORB) and comet (CometEls) elements '
            'from the Minor Planet Center. New bodies appear in the planetarium '
            'overlay and search. Satellite TLEs (CelesTrak) refresh on their '
            'own 24-hour cache when the satellite layer is on.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize13,
            ),
          ),
          const SizedBox(height: 16),
          // Last-updated indicator.
          Row(
            children: [
              Icon(
                status.hasData
                    ? NightshadeIcons.success
                    : NightshadeIcons.circle,
                size: 14,
                color: status.hasData ? colors.success : colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status.lastUpdated != null
                      ? 'Last updated ${_fmt(status.lastUpdated!)} • '
                          '${status.asteroidCount} asteroids, '
                          '${status.cometCount} comets'
                      : 'Using bundled elements — never refreshed',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: NightshadeTypography.fontSize12,
                  ),
                ),
              ),
            ],
          ),
          if (status.error != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last refresh failed: ${status.error}',
              style: TextStyle(
                color: colors.error,
                fontSize: NightshadeTypography.fontSize11,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Schedule selector.
          Row(
            children: [
              Text(
                'Auto-refresh:',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: NightshadeTypography.fontSize13,
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<ElementRefreshSchedule>(
                value: config.schedule,
                dropdownColor: colors.surface,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: NightshadeTypography.fontSize13,
                ),
                items: ElementRefreshSchedule.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.displayName),
                        ))
                    .toList(),
                onChanged: status.isRefreshing
                    ? null
                    : (s) async {
                        if (s == null) return;
                        await service.saveConfig(config.copyWith(schedule: s));
                        ref.read(elementRefreshReloadProvider.notifier).state++;
                      },
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: NightshadeButton(
              label: status.isRefreshing ? 'Refreshing…' : 'Refresh Now',
              icon: NightshadeIcons.download,
              variant: ButtonVariant.primary,
              onPressed: status.isRefreshing
                  ? null
                  : () async {
                      await controller.refresh();
                      if (context.mounted &&
                          ref.read(elementRefreshControllerProvider).error ==
                              null) {
                        context.showSuccessSnackBar('Elements refreshed');
                      }
                    },
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
