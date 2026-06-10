import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../../widgets/help/field_help_copy.dart';
import 'settings_widgets.dart';

/// Shared "Solve parameters" editor — timeout, search radius, and blind-solve.
///
/// Single source of truth for these three runtime knobs so the in-shell
/// Settings → Plate Solving section and the dedicated `/settings/plate-solving`
/// screen never diverge. All three persist through [AppSettingsNotifier]
/// (`plate_solve_timeout` / `plate_solve_search_radius` / `blind_solve`); the
/// desktop solve path honours them via `PlateSolveService.solveWithFallback`
/// and the headless handlers read them directly.
class PlateSolveParametersSection extends ConsumerStatefulWidget {
  const PlateSolveParametersSection({super.key});

  @override
  ConsumerState<PlateSolveParametersSection> createState() =>
      _PlateSolveParametersSectionState();
}

class _PlateSolveParametersSectionState
    extends ConsumerState<PlateSolveParametersSection> {
  final _timeoutController = TextEditingController();
  final _radiusController = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _timeoutController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _initControllers(AppSettingsState settings) {
    if (!_initialized) {
      _timeoutController.text = settings.plateSolveTimeout.toString();
      _radiusController.text =
          settings.plateSolveSearchRadius.toStringAsFixed(1);
      _initialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(appSettingsProvider);

    return settingsAsync.when(
      loading: () => const SettingsSection(
        title: 'Solve Parameters',
        children: [
          SettingRow(
            icon: LucideIcons.loader,
            title: 'Loading…',
            subtitle: 'Reading saved solve parameters',
            trailing: SizedBox.shrink(),
            isLast: true,
          ),
        ],
      ),
      error: (error, _) => SettingsSection(
        title: 'Solve Parameters',
        children: [
          SettingRow(
            icon: LucideIcons.alertCircle,
            title: 'Failed to load solve parameters',
            subtitle: '$error',
            trailing: const SizedBox.shrink(),
            isLast: true,
          ),
        ],
      ),
      data: (settings) {
        _initControllers(settings);
        return SettingsSection(
          title: 'Solve Parameters',
          children: [
            SettingRow(
              icon: LucideIcons.timer,
              title: 'Timeout',
              subtitle: 'Maximum time to attempt a solve before giving up',
              trailing: SettingsNumberInput(
                controller: _timeoutController,
                suffix: 'sec',
                min: 10,
                max: 300,
                decimals: 0,
                onChanged: (value) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setPlateSolveTimeout(value.toInt());
                },
              ),
            ),
            SettingRow(
              icon: LucideIcons.search,
              title: 'Search radius',
              helpId: FieldHelpId.plateSolverSearchRadius,
              subtitle: 'How far around the expected position to search',
              trailing: SettingsNumberInput(
                controller: _radiusController,
                suffix: '°',
                min: 1,
                max: 180,
                decimals: 1,
                onChanged: (value) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setPlateSolveSearchRadius(value);
                },
              ),
            ),
            SettingRow(
              icon: LucideIcons.compass,
              title: 'Blind solve',
              subtitle: 'Solve with no position hint (slower, but works when '
                  'the mount position is unknown)',
              trailing: SettingsSwitch(
                value: settings.blindSolve,
                onChanged: (value) {
                  ref.read(appSettingsProvider.notifier).setBlindSolve(value);
                },
              ),
              isLast: true,
            ),
          ],
        );
      },
    );
  }
}
