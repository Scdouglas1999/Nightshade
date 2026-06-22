import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;

import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/flat_wizard_keys.dart';
import 'widgets/flat_wizard_split_view.dart';
import 'widgets/flat_preview_panel.dart';
import 'widgets/save_path_dialog.dart';

part 'flat_wizard_screen/capture_mode_controls.dart';
part 'flat_wizard_screen/filter_controls.dart';
part 'flat_wizard_screen/tuning_controls.dart';
part 'flat_wizard_screen/action_buttons.dart';

class FlatWizardScreen extends ConsumerStatefulWidget {
  const FlatWizardScreen({super.key});

  @override
  ConsumerState<FlatWizardScreen> createState() => _FlatWizardScreenState();
}

class _FlatWizardScreenState extends ConsumerState<FlatWizardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    // Load filters on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(flatWizardProvider.notifier).loadFiltersFromWheel();
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final mode = switch (_tabController.index) {
      0 => FlatWizardMode.quick,
      1 => FlatWizardMode.batch,
      2 => FlatWizardMode.skyFlats,
      _ => FlatWizardMode.quick,
    };
    ref.read(flatWizardProvider.notifier).setMode(mode);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final state = ref.watch(flatWizardProvider);

    return ContextualTourPrompt(
      screenId: 'flat_wizard',
      tourCategory: TutorialCategory.flatWizardTour,
      title: 'Flat Wizard Tour',
      description: 'Learn how to capture calibration frames for your images.',
      durationMinutes: 2,
      alignment: Alignment.bottomRight,
      child: Column(
        children: [
          // Title + mode tabs share ONE row (the screen title previously sat in
          // its own ~56px header above the tab bar). The title folds inline to
          // the left of the tab strip — icon-only on a phone — and the live
          // "Capturing" badge rides at the right end of the same row.
          _buildTabBar(colors, state),

          // Split view content
          Expanded(
            child: FlatWizardSplitView(
              controlsPanel: TabBarView(
                controller: _tabController,
                children: const [
                  _QuickCaptureControls(),
                  _BatchCaptureControls(),
                  _SkyFlatsControls(),
                ],
              ),
              previewPanel:
                  FlatPreviewPanel(key: FlatWizardTutorialKeys.preview),
            ),
          ),
        ],
      ),
    );
  }

  /// A compact "Capturing" status pill surfaced inline at the right end of the
  /// tab row while a flat-capture run is active.
  Widget _capturingBadge(NightshadeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(right: NightshadeTokens.spaceMd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
          border: Border.all(color: colors.success.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.success,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Capturing',
              style: NightshadeTypography.label.copyWith(color: colors.success),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar(NightshadeColors colors, FlatWizardState state) {
    // AdaptiveTabBar never overflows: the three mode labels scroll
    // horizontally on a narrow phone instead of throwing a RenderFlex.
    // It drives the existing TabController so the TabBarView stays in sync.
    // The screen title is folded inline to the left of the strip (icon-only on
    // a phone) and the live "Capturing" badge rides at the right end.
    final isPhone = Responsive.isPhone(context);
    return Container(
      key: FlatWizardTutorialKeys.tabs,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: NightshadeTokens.spaceLg,
              right:
                  isPhone ? NightshadeTokens.spaceSm : NightshadeTokens.spaceMd,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // On a phone the title folds to icon-only to keep the tab strip
                // from overflowing, so the visible label is dropped. The screen
                // identity still rides on the icon via a Semantics label so it
                // stays accessible (and assertable) without the wide text.
                Semantics(
                  label: 'Flat Frame Wizard',
                  child: Icon(LucideIcons.sun, size: 18, color: colors.primary),
                ),
                if (!isPhone) ...[
                  const SizedBox(width: NightshadeTokens.spaceSm),
                  Text(
                    'Flat Frame Wizard',
                    style: NightshadeTypography.h5.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) => AdaptiveTabBar(
                tabs: const [
                  AdaptiveTab(label: 'Quick Capture', icon: LucideIcons.zap),
                  AdaptiveTab(
                      label: 'Multi-Filter Batch', icon: LucideIcons.layers),
                  AdaptiveTab(label: 'Sky Flats', icon: LucideIcons.sunrise),
                ],
                selectedIndex: _tabController.index,
                onSelected: (i) => _tabController.animateTo(i),
              ),
            ),
          ),
          if (state.isCapturing) _capturingBadge(colors),
        ],
      ),
    );
  }
}
