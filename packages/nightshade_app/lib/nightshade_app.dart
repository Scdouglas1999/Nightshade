/// Nightshade App - Unified application package
library nightshade_app;

// Main App Widget
export 'app.dart';

// Router
export 'router/app_router.dart';
export 'router/page_transitions.dart';

// Screens
export 'screens/analytics/analytics_screen.dart';
export 'screens/dashboard/dashboard_screen.dart';
export 'screens/equipment/equipment_screen.dart';
export 'screens/framing/framing_screen.dart';
export 'screens/imaging/imaging_screen.dart';
export 'screens/planetarium/planetarium_screen.dart';
export 'screens/sequencer/sequencer_screen.dart';
export 'screens/settings/settings_screen.dart';
export 'screens/settings/catalog_settings_screen.dart';
export 'screens/settings/equipment_profiles_screen.dart';
export 'screens/shell/app_shell.dart';

// Widgets
export 'widgets/adaptive_shell.dart';
export 'widgets/animated_tab_bar_view.dart';
export 'widgets/animated_tab_indicator.dart';
export 'widgets/catalog_setup_dialog.dart';
export 'widgets/staggered_animation.dart';
export 'widgets/annotation_painter.dart';
export 'widgets/object_info_panel.dart';
export 'widgets/sequence_progress_card.dart';
export 'widgets/sequence_controls.dart';
export 'widgets/mobile_sequence_overlay.dart';
export 'widgets/session_recovery_checker.dart';
export 'widgets/session_recovery_dialog.dart';
export 'widgets/auto_discovery_launcher.dart';
export 'widgets/tutorial_overlay.dart';
export 'widgets/welcome_flow.dart';
export 'widgets/tour_selection_sheet.dart';
export 'widgets/contextual_tour_prompt.dart';
export 'widgets/connection_stale_banner.dart';
export 'widgets/equipment_status_indicator.dart';
export 'widgets/ios_background_banner.dart';

// Sequencer Wizards (Priority 2)
export 'screens/sequencer/widgets/mosaic_wizard_dialog.dart';
export 'screens/sequencer/widgets/flat_wizard_dialog.dart';
export 'screens/sequencer/widgets/trigger_configuration_dialog.dart';

// Sequencer Visual Enhancements (Priority 3)
export 'screens/sequencer/widgets/sequence_enhancements.dart';

// Services
export 'services/location_sync_service.dart';
