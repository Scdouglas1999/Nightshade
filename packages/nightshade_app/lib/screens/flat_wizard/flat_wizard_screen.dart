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
          // Screen header
          _buildHeader(colors, state),

          // Tab bar
          _buildTabBar(colors),

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

  Widget _buildHeader(NightshadeColors colors, FlatWizardState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(LucideIcons.sun, color: colors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Flat Frame Wizard',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Capture calibration frames with optimal exposure',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (state.isCapturing)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusXl),
                border:
                    Border.all(color: colors.success.withValues(alpha: 0.3)),
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
                    style: TextStyle(
                      color: colors.success,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar(NightshadeColors colors) {
    return Container(
      color: colors.surface,
      child: TabBar(
        key: FlatWizardTutorialKeys.tabs,
        controller: _tabController,
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.primary,
        indicatorWeight: 2,
        tabs: const [
          Tab(text: 'Quick Capture'),
          Tab(text: 'Multi-Filter Batch'),
          Tab(text: 'Sky Flats'),
        ],
      ),
    );
  }
}
