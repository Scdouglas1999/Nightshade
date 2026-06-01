import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show Phd2State;
import 'package:nightshade_app/widgets/phd2_connection_dialog.dart';
import 'package:nightshade_app/utils/phd2_helper.dart';
import '../../widgets/tutorial_keys/guiding_keys.dart';
import '../../widgets/contextual_tour_prompt.dart';

part 'guiding_screen_parts/state_fields.dart';
part 'guiding_screen_parts/desktop_sections.dart';
part 'guiding_screen_parts/mobile_sections.dart';

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

    // Initialize controller
    ref.watch(phd2ControllerProvider);

    return ContextualTourPrompt(
      screenId: 'guiding',
      tourCategory: TutorialCategory.guidingTour,
      title: 'Guiding Tour',
      description: 'Learn how to set up and monitor autoguiding.',
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: Scaffold(
        backgroundColor: colors.background,
        body: Column(
          children: [
            // Status bar - adapts for mobile
            _buildStatusBar(colors, isConnected, phd2State, guideStats),
            // Main content - responsive layout
            Expanded(
              child: Responsive.isMobile(context)
                  ? _buildMobileLayout(
                      colors, isConnected, phd2State, guideStats)
                  : _buildDesktopLayout(
                      colors, isConnected, phd2State, guideStats),
            ),
          ],
        ),
      ),
    );
  }
}
