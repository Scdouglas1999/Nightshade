# UI Screens & Widgets Audit

## Executive Summary

The Nightshade UI layer is **mature and well-built**. 14 screens are routed via GoRouter with consistent page transitions. All screens use Riverpod for state management, the NightshadeUI design system for theming, and most implement responsive desktop/mobile layouts. There are no TODO comments, no placeholder stubs, and no empty catch blocks in the UI layer. The code demonstrates production-level quality with thorough error handling, loading states, and mounted checks.

**Key strengths:** Consistent design system usage, responsive layouts at multiple breakpoints, comprehensive tutorial/onboarding system, customizable dashboard, well-structured widget decomposition.

**Key concerns:** Massive file sizes (dashboard: 5,751 lines, imaging: 7,079 lines), duplicated `_formatDeviceId`/`_capitalizeVendor` code across 8 files, polar alignment screen has no mobile responsiveness, one async callback missing `mounted` check, bottom navigation UX on mobile is suboptimal.

---

## Routing

**File:** `packages/nightshade_app/lib/router/app_router.dart`
**Rating:** Complete & Solid

- GoRouter with 13 routes all under a single `ShellRoute` wrapping `AppShell`
- Custom slide/fade transitions via `CustomTransitionPage`
- Initial location: `/dashboard`
- Settings uses `scaleFadeTransition` (distinct from other screens)
- Missing: No nested routes (e.g., settings sub-pages), no route guards, no deep linking parameters. These are acceptable for a desktop-first app.
- The Suggestions screen is **NOT in the router** as a standalone route - it is embedded as a tab inside the Framing screen. The `SuggestionsScreen` class exists but is only shown within `FramingScreen`. This is fine from a UX standpoint.

---

## App Shell

**Files:** `screens/shell/app_shell.dart`, `app_shell_desktop.dart`, `app_shell_stub.dart`
**Rating:** Complete & Solid

- Proper conditional import for `window_manager` (desktop vs stub for mobile/web)
- Window close confirmation dialog when capture is in progress
- Catalog setup check on first launch
- `DisconnectedBackend` detection with red banner
- Weather alert banner integration
- Mobile sequence overlay on sequencer screen
- Autofocus progress overlay
- Toast notification overlay
- Tutorial overlay wrapping
- Welcome flow for first-time users
- Side navigation (desktop) / bottom navigation (mobile) based on `LayoutBuilder` breakpoint

### Sub-widgets

| Widget | File | Rating | Notes |
|--------|------|--------|-------|
| SideNavigation | `side_navigation.dart` | Complete & Solid | 10 nav items with icons, descriptions, tooltips when collapsed, tutorial key support |
| StatusBar | `status_bar.dart` | Complete & Solid | Clock, device status indicators, operation status. Duplicates `_formatDeviceId` logic |
| TitleBar | `title_bar.dart` | Complete & Solid | Conditional import pattern (desktop/stub), app icon, version display |
| NightshadeBottomNavigation | `nightshade_bottom_navigation.dart` | Functional but Needs Polish | Uses horizontal `ListView` for 10 items - scrollable but not discoverable. Should use 4-5 primary tabs + "More" pattern |

**Bug (minor):** `_getCurrentIndex` in `app_shell.dart:154-177` switch statement doesn't map `/settings`, `/polar-alignment`, or `/transients` to nav indices. They fall through to default `0` (dashboard), meaning the nav highlight is wrong when visiting those screens.

---

## Screen-by-Screen Assessment

### 1. Dashboard
**File:** `screens/dashboard/dashboard_screen.dart` (5,751 lines) + `dashboard_widgets.dart` (part file)
**Rating:** Complete & Solid

- Zone-based customizable layout (primary, secondary, tertiary zones)
- Three responsive breakpoints: full (>1024px), stacked (768-1024), compact (<768)
- Edit mode for widget management (drag-reorder, resize, enable/disable, zone assignment)
- Widget picker dialog for adding/removing dashboard cards
- Command bar with session status, clock, edit controls
- Dashboard widgets include: live preview, capture settings, sequence status, guiding, equipment status, mount control, focus, weather, tonight's objects, alerts, quick actions, quick stats
- Proper loading/error states for layout provider
- Animation controllers properly disposed

**Issue:** File is massive at 5,751 lines. The `part 'dashboard_widgets.dart'` pattern is used but the combined file likely exceeds 10K lines. Should be split into separate widget files.

**Issue:** Duplicates `_formatDeviceId` and `_capitalizeVendor` helper functions (also found in 7 other files). Should be extracted to a shared utility.

### 2. Equipment
**File:** `screens/equipment/equipment_screen.dart` (1,013 lines)
**Rating:** Complete & Solid

- Profile sidebar (collapsible, resizable, animated)
- Device dashboard with connection status for all 6 device types
- First-time onboarding flow (welcome message, setup steps, auto-discovery)
- Profile CRUD operations (create, edit, duplicate, delete, reorder, set default)
- Connect All / Disconnect All with individual device error tracking
- Empty states for: no profile selected, no devices assigned, no devices connected
- Proper `mounted` checks on all async operations
- Equipment settings dialog

**Sub-widgets:**
- `ProfileSidebar` - profile list with context menu actions
- `ConnectedDeviceCard` - device-specific status cards
- `DiscoveryPanel` - auto-discovery for ASCOM/INDI/Alpaca/native devices
- `ProfileEditorDialog` - full profile editor with device selection
- `ProfileWizardDialog` - guided setup wizard
- `IndiServerDialog` - INDI server connection config
- `BackendSelectorChips` - ASCOM/INDI/Alpaca/Native toggle

### 3. Imaging
**File:** `screens/imaging/imaging_screen.dart` (7,079 lines)
**Rating:** Complete & Solid (with one bug)

- Live preview with zoom/pan, crosshair, grid, star overlay
- Capture controls: snapshot, loop capture, abort
- Panel selection persisted via provider
- Annotation overlay with catalog integration
- Science HUD overlay
- Stretch controls for image visualization
- Desktop layout: preview + side panels (Camera, Capture, Focus, Mount, Guiding tabs)
- Mobile layout: tabs at bottom with compact preview
- Annotation catalog banner with setup prompt

**Bug:** `imaging_screen.dart:168` - `onError` callback in `startLoopCapture` uses `context.showErrorSnackBar('Capture error: $error')` without a `mounted` check. This callback is invoked asynchronously and could fire after the widget is disposed.

**Sub-tabs:**
- `CameraTab` - cooling, sensor info, debayering, gain/offset presets, download settings
- `CaptureTab` - exposure settings, histogram, ROI selection
- `FocusTab` - focuser position, autofocus with V-curve visualization
- `MountTab` - mount position, tracking, park/unpark
- `GuidingTab` - compact guiding status within imaging screen

### 4. Guiding
**File:** `screens/guiding/guiding_screen.dart` (1,296 lines)
**Rating:** Complete & Solid

- Full PHD2 guiding interface
- Desktop layout: star view, target display, guide graph, controls, brain settings
- Mobile layout: guide graph at top + 3 tabbed sections (Star View, Controls, Settings)
- Responsive tab bar handling (scrollable on very narrow screens, icon-only on tiny)
- PHD2 connection status bar
- Guide graph with configurable time/Y scales
- Star image view with crosshairs and star selection
- Target display (error history visualization)
- Brain settings panel (toggle show/hide)
- Proper dispose of TabController

### 5. Sequencer
**File:** `screens/sequencer/sequencer_screen.dart` (1,471 lines)
**Rating:** Complete & Solid

- Three tabs: Builder, Targets, Templates
- Keyboard shortcuts: Ctrl+Z undo, Ctrl+Y redo, Delete remove, Ctrl+D duplicate, Alt+1/2/3 tab switch, Ctrl+T toggle snippet palette
- Auto-creates default sequence if none exists
- Progress bar visible during execution
- Running indicator in tab bar
- Mobile playback bar
- Proper sync between tab controller and provider

**Sub-widgets (extensive):**
- `SequenceTree` - drag-and-drop node tree
- `NodePalette` - instruction/trigger/logic node catalog (drag source)
- `SnippetPalette` - user-saved node snippets
- `NodePropertiesPanel` - context-sensitive property editor for all node types
- `SequenceToolbar` - run/pause/stop/validate controls
- `SequenceProgressBar` - execution progress
- `SequenceTimeline` - visual timeline
- `TargetHeaderCard` - target info display
- `PreflightValidationDialog` - pre-run checks
- `MountUnparkDialog` - unpark confirmation
- `MosaicWizardDialog` - mosaic panel setup
- `FlatWizardDialog` - flat frame integration
- `MeridianFlipProgressDialog` - flip monitoring
- `TriggerConfigurationDialog` - trigger setup
- `MobilePlaybackBar` - compact mobile controls
- `SequenceEnhancements` - enhancement overlays

### 6. Planetarium
**File:** `screens/planetarium/planetarium_screen.dart` (5,824 lines)
**Rating:** Complete & Solid

- GPU-rendered sky visualization (via `nightshade_planetarium` package)
- Object tap handling with popup info cards
- Slew mode for direct mount control
- FOV overlay toggle
- Mount position sync (initial + live tracking)
- Rotator position sync
- Object search with catalog results
- Send to Framing / Add to Sequencer actions
- Slew, Slew+Center, Slew+Center+Rotate workflows
- Filter sidebar for catalog visibility
- DSO display info helper with Messier/NGC/IC prioritization
- Keyboard controls and mouse interactions

**Issue:** Large file at 5,824 lines. Could benefit from extracting popup/info card widgets.

### 7. Framing
**File:** `screens/framing/framing_screen.dart` (4,688 lines)
**Rating:** Complete & Solid

- Two tabs: Framing and Suggestions (integrated `SuggestionsTab`)
- Target search with catalog lookup
- RA/Dec manual entry with formatting
- Alt/Az live update (10-second timer, properly disposed)
- Persisted target loading from database
- Framing preview with FOV overlay
- Altitude chart
- Mosaic config panel
- Optical config panel
- Slew dropdown button integration
- Framing history persistence

### 8. Analytics
**File:** `screens/analytics/analytics_screen.dart` (1,028 lines)
**Rating:** Complete & Solid

- Four sub-tabs: Session, History, Equipment Stats, Science
- Session tab: summary bar (duration, exposures, integration, avg HFR), HFR/guiding charts
- History tab: session browser with export/share
- Equipment Stats tab: device usage statistics
- Science tab: full science analytics (KPI strip, surface explorer, timeline scrubber, insights)
- Tutorial key support for tabs
- Proper `.when()` handling for async data

**Sub-widgets:**
- `SessionChart` - HFR, guiding RMS, temperature, focuser position charts
- `ImageThumbnailStrip` - horizontal scrolling image browser
- `ScienceAnalyticsTab` - comprehensive science data visualization
- `ScienceKpiStrip`, `ScienceSurfaceExplorer`, `ScienceInsightsPanel`, `ScienceOverlayComposer`, `ScienceTimelineScrubber`

### 9. Flat Wizard
**File:** `screens/flat_wizard/flat_wizard_screen.dart` (1,137 lines)
**Rating:** Complete & Solid

- Three tabs: Quick Capture, Multi-Filter Batch, Sky Flats
- Split view layout (controls + preview)
- ADU target calculation
- Filter-aware capture
- Calibration history recording
- Progress tracking with error/warning messages
- Preview panel with live flat frame display

### 10. Weather
**File:** `screens/weather/weather_screen.dart` (723+ lines)
**Rating:** Complete & Solid

- Weather radar map with animated playback
- Cloud motion tracking with ETA predictions
- Alert status and notifications
- Timeline scrubber for radar frames
- Auto-refresh every 5 minutes (timer properly disposed)
- Location requirement check with setup prompt
- Three responsive layouts: wide, medium, stacked
- Weather status card (collapsible)
- Satellite legend
- Radar opacity and contrast controls
- Playback speed control

### 11. Settings
**File:** `screens/settings/settings_screen.dart` (6,364 lines)
**Rating:** Complete & Solid

- 18 setting categories in sidebar
- Desktop: resizable sidebar + content area
- Mobile: category list -> detail page with back button
- Categories: Connection, General, Appearance, Location, Equipment Profiles, Catalogs, Imaging, Autofocus, Science, Annotations, Sequencer, Plate Solving, PHD2 Guiding, Notifications, File Paths, Plugins, Help & Tutorials, About
- Each category is a fully implemented settings panel

**Sub-screens:**
- `CatalogSettingsScreen` - star/DSO catalog management
- `EquipmentProfilesScreen` - profile import/export
- `PluginsScreen` - plugin management
- `PairingScreen` - remote pairing setup
- `BackupScreen` - database backup/restore

### 12. Polar Alignment
**File:** `screens/polar_alignment/polar_alignment_screen.dart` (2,981 lines)
**Rating:** Functional but Needs Polish

- Three-point polar alignment method
- Equipment validation (camera + mount required)
- Left panel: equipment status & config
- Center panel: progress & instructions
- Right panel: error visualization
- Footer with action buttons
- Start/stop/complete/reset workflow
- History panel (collapsible)
- Advanced settings panel

**Issue:** **No mobile/responsive layout.** Uses fixed `SizedBox(width: 320)` and `SizedBox(width: 400)` for left/right panels. Will overflow on screens narrower than ~1000px. This is the only main screen without responsive handling.

**Issue:** Uses raw `ScaffoldMessenger.of(context).showSnackBar` instead of the `context.showErrorSnackBar` extension method used everywhere else (inconsistent).

### 13. Transients
**File:** `screens/transients/transients_screen.dart` (400+ lines)
**Rating:** Complete & Solid

- Filter tabs: All, New, Queued, Observed
- TransientCard with expand/collapse
- Queue, View in Framing, Dismiss actions
- Loading shimmer skeleton
- Empty state per filter type
- Error state with retry
- Responsive layout (mobile padding)
- Settings dialog for transient alert configuration

### 14. Suggestions
**File:** `screens/suggestions/suggestions_screen.dart` (400+ lines)
**Rating:** Complete & Solid

- Responsive grid layout (1 column mobile, 2 columns tablet/desktop)
- Dynamic card height based on available space
- Pull-to-refresh on mobile
- Filter sheet with active filter count badge
- Loading shimmer with matched sizing
- Empty state with helpful messaging
- View in Framing / Add to Sequence actions

---

## Shared Widgets Assessment

| Widget | File | Rating | Notes |
|--------|------|--------|-------|
| AdaptiveShell | `adaptive_shell.dart` | Complete & Solid | Platform-adaptive layout container |
| AnimatedTabBarView | `animated_tab_bar_view.dart` | Complete & Solid | Custom animated tab transitions |
| AnimatedTabIndicator | `animated_tab_indicator.dart` | Complete & Solid | Custom tab indicator animation |
| AnnotationOverlay | `annotation_overlay.dart` | Complete & Solid | Star/DSO annotation on images |
| AnnotationPainter | `annotation_painter.dart` | Complete & Solid | Custom painter for annotations |
| AnnotationCatalogDialog | `annotation_catalog_dialog.dart` | Complete & Solid | Annotation catalog management |
| AstroImageViewer | `astro_image_viewer.dart` | Complete & Solid | Full-featured image viewer with stretch |
| AutoDiscoveryLauncher | `auto_discovery_launcher.dart` | Complete & Solid | Equipment auto-discovery trigger |
| AutofocusProgressOverlay | `autofocus_progress_overlay.dart` | Complete & Solid | Global AF progress display |
| CaptureSettingsPanel | `capture_settings_panel.dart` | Complete & Solid | Reusable capture config panel |
| CatalogSetupDialog | `catalog_setup_dialog.dart` | Complete & Solid | First-run catalog setup |
| ContextualTourPrompt | `contextual_tour_prompt.dart` | Complete & Solid | Per-screen tutorial prompt |
| EquipmentStatusIndicator | `equipment_status_indicator.dart` | Complete & Solid | Device connection status dots |
| FilterWheelSelector | `filter_wheel_selector.dart` | Complete & Solid | Filter selection dropdown |
| FocuserControls | `focuser_controls.dart` | Complete & Solid | Reusable focuser movement + AF |
| MobileSequenceOverlay | `mobile_sequence_overlay.dart` | Complete & Solid | Mobile sequence status overlay |
| NotificationToastOverlay | `notification_toast_overlay.dart` | Complete & Solid | Global toast notification system |
| ObjectInfoPanel | `object_info_panel.dart` | Complete & Solid | Celestial object detail display |
| OperationStatusBar | `operation_status_bar.dart` | Complete & Solid | Current operation status display |
| Phd2ConnectionDialog | `phd2_connection_dialog.dart` | Complete & Solid | PHD2 connection setup |
| QuickStartChecker | `quick_start_checker.dart` | Complete & Solid | First-run equipment check |
| QuickStartDialog | `quick_start_dialog.dart` | Complete & Solid | Quick start wizard |
| SequenceControls | `sequence_controls.dart` | Complete & Solid | Sequence playback controls |
| SequenceProgressCard | `sequence_progress_card.dart` | Complete & Solid | Sequence progress display |
| SessionRecoveryChecker | `session_recovery_checker.dart` | Complete & Solid | Session crash recovery |
| SessionRecoveryDialog | `session_recovery_dialog.dart` | Complete & Solid | Recovery confirmation dialog |
| SlewDropdownButton | `slew_dropdown_button.dart` | Complete & Solid | Slew action menu (slew, center, rotate) |
| StaggeredAnimation | `staggered_animation.dart` | Complete & Solid | Sequential animation utility |
| TourSelectionSheet | `tour_selection_sheet.dart` | Complete & Solid | Tutorial tour picker |
| TransientAlertBadge | `transient_alert_badge.dart` | Complete & Solid | Badge for new transient alerts |
| TutorialOverlay | `tutorial_overlay.dart` | Complete & Solid | Full tutorial system with step-by-step guides |
| TutorialKeys | `tutorial_keys/` (13 files) | Complete & Solid | GlobalKey definitions for tutorial targeting per screen |
| Weather widgets | `weather/` (7 files) | Complete & Solid | Radar map, timeline scrubber, status card, alert banner, satellite legend, location marker, motion indicator, dashboard widget |
| WelcomeFlow | `welcome_flow.dart` | Complete & Solid | First-launch welcome with 3 options |

---

## Bugs Found

### B1: Missing `mounted` check in async callback (Medium)
**File:** `imaging_screen.dart:168`
```dart
onError: (error) {
    context.showErrorSnackBar('Capture error: $error');
}
```
The `onError` callback from `startLoopCapture` fires asynchronously but doesn't check `mounted` before using `context`. Could crash if the widget is disposed during loop capture.

### B2: Nav index not mapped for 3 routes (Low)
**File:** `app_shell.dart:154-177`
The `_getCurrentIndex` switch statement doesn't handle `/settings`, `/polar-alignment`, or `/transients` routes. They fall through to `default: return 0` (Dashboard), causing the side nav to incorrectly highlight Dashboard when the user is on Settings, Polar Alignment, or Transients screens.

### B3: Polar Alignment has no responsive layout (Medium)
**File:** `polar_alignment_screen.dart:118-141`
Uses fixed-width panels (`SizedBox(width: 320)` and `SizedBox(width: 400)`) with no mobile breakpoint check. Will overflow on screens narrower than ~1000px. This is the only main screen without responsive handling.

### B4: Inconsistent SnackBar usage in Polar Alignment (Low)
**File:** `polar_alignment_screen.dart:51, 63`
Uses raw `ScaffoldMessenger.of(context).showSnackBar(SnackBar(...))` instead of the `context.showErrorSnackBar()` extension used consistently everywhere else. Results in visually different error messages.

---

## Code Quality Issues

### CQ1: Duplicated `_formatDeviceId` / `_capitalizeVendor` code (High)
Found in **8 separate files**, each with a nearly identical copy of the device ID formatting logic:
- `dashboard_screen.dart`
- `status_bar.dart`
- `connections_tab.dart`
- `connected_device_card.dart`
- `equipment_status_widget.dart`
- `profiles_tab.dart`
- `connection_status_zone.dart`
- `equipment_profiles_screen.dart`

This should be extracted into a single shared utility class (e.g., `DeviceIdFormatter` in nightshade_core or nightshade_app/utils).

### CQ2: File size concerns (Medium)
Several files are excessively large:
- `imaging_screen.dart`: 7,079 lines
- `settings_screen.dart`: 6,364 lines
- `dashboard_screen.dart`: 5,751 lines (+ `dashboard_widgets.dart` part file)
- `planetarium_screen.dart`: 5,824 lines
- `framing_screen.dart`: 4,688 lines

These should be refactored into smaller widget files. The dashboard already uses the `part` directive but the others do not.

### CQ3: `ignore_for_file` suppressions (Low)
Found in 4 files:
- `analytics_screen.dart`: `unused_element_parameter`
- `capture_tab.dart`: `unused_local_variable`
- `flat_wizard_screen.dart`: `unused_element_parameter`
- `settings_screen.dart`: `unused_element_parameter`

These suggest dead code that should be cleaned up.

### CQ4: Bottom navigation UX (Low)
`NightshadeBottomNavigation` uses a horizontally scrollable `ListView` for 10 navigation items. Standard mobile UX patterns recommend 3-5 bottom nav items. A "More" menu or priority-based tab selection would be more discoverable.

---

## Missing UI (Expected but Not Found)

1. **No dedicated log viewer screen** - There is no screen to view application logs. Most astrophotography suites (NINA, SGPro) have a log panel. Nightshade has logging infrastructure but no UI to view it.

2. **No image gallery/browser** - The Analytics screen shows session images in a thumbnail strip but there's no dedicated full-screen image gallery for browsing captured images with metadata.

3. **No dark frame library screen** - The Flat Wizard handles flat frames, but there's no equivalent for managing a dark frame library.

4. **No scheduler screen** - The sequencer handles sequence execution, but there's no visual scheduler for planning multi-night observation campaigns (though the Suggestions tab partially fills this gap).

---

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total screens | 14 (+ embedded Suggestions) |
| Total screen files | 98 Dart files |
| Total shared widgets | 54+ Dart files |
| Screens rated Complete & Solid | 13 |
| Screens rated Functional but Needs Polish | 1 (Polar Alignment) |
| Screens rated Half-Baked | 0 |
| Screens rated Stubbed/Placeholder | 0 |
| Screens rated Missing | 0 |
| Screens rated Broken | 0 |
| Bugs found | 4 (0 critical, 2 medium, 2 low) |
| Code quality issues | 4 |
| TODO/FIXME comments | 0 |
| Empty catch blocks | 0 |
