import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show Phd2State;
import 'package:nightshade_app/widgets/phd2_connection_dialog.dart';
import 'package:nightshade_app/widgets/phd2/guide_controls_panel.dart';
import 'package:nightshade_app/widgets/phd2/guide_target_display.dart';
import 'package:nightshade_app/utils/phd2_helper.dart';
import 'package:nightshade_app/utils/confirm_dialog.dart';
import '../../widgets/tutorial_keys/guiding_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';

part 'guiding_screen_parts/state_fields.dart';
part 'guiding_screen_parts/desktop_sections.dart';
part 'guiding_screen_parts/mobile_sections.dart';
part 'guiding_screen_parts/actions.dart';

/// Why Pause is unavailable under Nightshade's own guider.
///
/// Pause is a PHD2 command. Under the built-in guider the button was simply
/// inert: nothing changed on screen, in the status bar, or in the log, so the
/// operator could not tell whether corrections had been suspended.
const String kBuiltinGuiderNoPauseReason =
    'Pause is a PHD2 feature. The built-in guider has no pause — '
    'use Stop to suspend guiding.';

/// Full PHD2 guiding interface screen
///
/// Provides comprehensive guiding control including:
/// - Star image view with crosshairs
/// - Target display (error history visualization)
/// - Advanced guiding graph with configurable scales
/// - PHD2 Brain settings panel
/// - Calibration controls
/// - Full guiding controls
class GuidingScreen extends ConsumerStatefulWidget {
  const GuidingScreen({super.key});

  @override
  ConsumerState<GuidingScreen> createState() => _GuidingScreenState();
}

class _GuidingScreenState extends ConsumerState<GuidingScreen>
    with
        SingleTickerProviderStateMixin,
        _GuidingStateFields,
        _GuidingActions,
        _GuidingDesktopSections,
        _GuidingMobileSections {
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final isConnected = ref.watch(phd2ConnectedProvider);
    final phd2State = ref.watch(phd2StateProvider);
    final guideStats = ref.watch(guideStatsProvider);

    ref.watch(phd2ControllerProvider);

    // Seed the settle/dither controls from the canonical persisted settings the
    // first time they are available. Watching the provider means a fresh screen
    // (post-reconstruction) re-hydrates from the persisted values.
    final settingsAsync = ref.watch(appSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    if (settings != null) {
      _hydrateGuidingSettings(settings);
    }

    return ContextualTourPrompt(
      screenId: 'guiding',
      tourCategory: TutorialCategory.guidingTour,
      title: 'Guiding Tour',
      description: 'Learn how to set up and monitor autoguiding.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: Scaffold(
        // Connection/settings inputs live in modal dialogs that handle their
        // own IME insets. Resizing the complex guiding dashboard behind the
        // modal can make its fixed status chrome overflow in short landscape
        // viewports even though the user cannot interact with it.
        resizeToAvoidBottomInset: false,
        backgroundColor: colors.background,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // Status bar - adapts for phone
              _buildStatusBar(colors, isConnected, phd2State, guideStats),
              if (settingsAsync.hasError)
                _GuidingSettingsAuthorityBanner(
                  error: settingsAsync.error!,
                  onRetry: () => ref.invalidate(appSettingsProvider),
                )
              else if (settingsAsync.isLoading)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: colors.primary,
                  backgroundColor: colors.border,
                ),
              // Main content. A phone is a phone in either orientation — a
              // large phone held in landscape is ~932 px wide yet must NOT get
              // the desktop split (its narrow side panels overflow). Branch on
              // the shortest side so portrait AND landscape phones both take
              // the reflowed mobile layout; genuine tablets/desktops keep the
              // split, which scales fractionally.
              Expanded(
                child: _isPhoneViewport(context)
                    ? _buildMobileLayout(
                        colors, isConnected, phd2State, guideStats)
                    : _buildDesktopLayout(
                        colors, isConnected, phd2State, guideStats),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidingSettingsAuthorityBanner extends StatelessWidget {
  const _GuidingSettingsAuthorityBanner({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colors.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(LucideIcons.alertTriangle, size: 15, color: colors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Guiding defaults unavailable: $error. '
              'Settle and dither edits are disabled.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
