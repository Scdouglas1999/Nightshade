# Equipment Screen & Profiles Redesign - Implementation Plan

## Overview

This plan implements a comprehensive overhaul of the equipment screen and profile management system. The redesign addresses:

1. **Profile management friction** - Too many steps, poor visibility, clunky editing
2. **Device naming issues** - Raw driver IDs instead of friendly names
3. **Layout problems** - Awkward card spacing, truncated text, visual polish
4. **Poor integration** - Profile info siloed, not visible on other screens

## Critical Implementation Rules

**ALL SUB-AGENTS MUST FOLLOW THESE RULES:**

1. **NO STUBS OR PLACEHOLDERS** - Every function, method, callback, and handler must be fully implemented. Do not write `// TODO`, `throw UnimplementedError()`, empty function bodies, or placeholder comments. If you cannot complete something, stop and report why.

2. **NO SIMPLIFIED IMPLEMENTATIONS** - Do not take shortcuts "to save time." Implement the full specification as described. If a card needs 6 telemetry fields, implement all 6. If a dialog needs 5 sections, implement all 5.

3. **COMPLETE UI EXPOSURE** - Every new model field, provider, or service method must be connected to the UI. Trace the path: Database → Model → Provider → Widget. If you add a field that isn't displayed anywhere, you have failed.

4. **VERIFY INTEGRATION** - After implementing, verify that:
   - New providers are actually watched by widgets
   - New model fields are actually displayed
   - New buttons/actions actually trigger handlers
   - New dialogs are actually accessible from the UI

5. **ERROR HANDLING** - All async operations must have proper error handling with user-visible feedback. No silent failures.

---

## File Reference

| Purpose | Path |
|---------|------|
| Database schema | `packages/nightshade_core/lib/src/database/tables/equipment_profiles.drift` |
| Database class | `packages/nightshade_core/lib/src/database/database.dart` |
| Profile DAO | `packages/nightshade_core/lib/src/database/daos/equipment_profiles_dao.dart` |
| Profile model | `packages/nightshade_core/lib/src/models/equipment_profile_model.dart` |
| DB Profile model | `packages/nightshade_core/lib/src/database/database.dart` (generated) |
| Profiles provider | `packages/nightshade_core/lib/src/providers/profiles_provider.dart` |
| Equipment provider | `packages/nightshade_core/lib/src/providers/equipment_provider.dart` |
| Equipment screen | `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` |
| Quick connect bar | `packages/nightshade_app/lib/screens/equipment/widgets/quick_connect_bar.dart` |
| Connection status | `packages/nightshade_app/lib/screens/equipment/widgets/connection_status_zone.dart` |
| Profile chip | `packages/nightshade_app/lib/screens/equipment/widgets/profile_chip.dart` |
| Connections tab | `packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart` |
| Settings tab | `packages/nightshade_app/lib/screens/equipment/tabs/settings_tab.dart` |
| App shell | `packages/nightshade_app/lib/widgets/app_shell.dart` |
| Framing screen | `packages/nightshade_app/lib/screens/framing/framing_screen.dart` |

---

## Phase 1: Database & Model Layer (2 agents in parallel)

### Agent 1-1: Database Schema Migration

**Scope:** Add new columns to equipment_profiles table and create migration.

**Files to modify:**
- `packages/nightshade_core/lib/src/database/tables/equipment_profiles.drift`
- `packages/nightshade_core/lib/src/database/database.dart`

**Schema changes - ADD these columns to equipment_profiles:**

```
camera_name         TEXT     -- User-friendly camera name (auto or custom)
mount_name          TEXT     -- User-friendly mount name
focuser_name        TEXT     -- User-friendly focuser name
filter_wheel_name   TEXT     -- User-friendly filter wheel name
guider_name         TEXT     -- User-friendly guider name
rotator_name        TEXT     -- User-friendly rotator name
telescope_name      TEXT     -- OTA description (e.g., "Esprit 100ED")
telescope_focal_length REAL  -- Telescope focal length (separate from profile focal_length)
telescope_aperture  REAL     -- Telescope aperture (separate from profile aperture)
profile_icon        TEXT     -- Icon identifier (emoji or icon name)
profile_color       INTEGER  -- Accent color as ARGB int
sort_order          INTEGER DEFAULT 0  -- For manual profile ordering
is_default          INTEGER DEFAULT 0  -- Boolean: auto-connect on startup
```

**Migration (schema version 5 → 6):**
- Write migration in `database.dart` that adds all columns with ALTER TABLE
- Ensure migration handles existing data gracefully (all new columns nullable or have defaults)
- Update `schemaVersion` to 6

**Verification:**
- Run `melos run generate` to regenerate drift code
- Verify generated `EquipmentProfile` class has all new fields
- Verify migration compiles without errors

---

### Agent 1-2: Model & Provider Updates

**Depends on:** Agent 1-1 (schema must be generated first)

**Scope:** Update Dart models and create new providers for optical config and filters.

**Files to modify:**
- `packages/nightshade_core/lib/src/models/equipment_profile_model.dart`
- `packages/nightshade_core/lib/src/providers/profiles_provider.dart`
- `packages/nightshade_core/lib/src/providers/equipment_provider.dart`

**EquipmentProfileModel updates:**

Add fields matching new schema:
```dart
final String? cameraName;
final String? mountName;
final String? focuserName;
final String? filterWheelName;
final String? guiderName;
final String? rotatorName;
final String? telescopeName;
final double? telescopeFocalLength;
final double? telescopeAperture;
final String? profileIcon;
final int? profileColor;
final int sortOrder;
final bool isDefault;
```

Add computed properties:
```dart
/// Returns telescope name + camera name as subtitle, or fallback
String get subtitle {
  if (telescopeName != null && cameraName != null) {
    return '$telescopeName + $cameraName';
  }
  if (cameraName != null) return cameraName!;
  if (mountName != null) return mountName!;
  return '$deviceCount devices';
}

/// Count of assigned devices
int get deviceCount {
  int count = 0;
  if (cameraId != null) count++;
  if (mountId != null) count++;
  if (focuserId != null) count++;
  if (filterWheelId != null) count++;
  if (guiderId != null) count++;
  if (rotatorId != null) count++;
  return count;
}
```

**New providers in profiles_provider.dart:**

```dart
/// Computed optical configuration for the active profile
final opticalConfigProvider = Provider<OpticalConfig?>((ref) {
  final profile = ref.watch(activeProfileProvider).valueOrNull;
  if (profile == null) return null;

  final cameraState = ref.watch(cameraStateProvider);

  return OpticalConfig(
    telescopeName: profile.telescopeName,
    focalLength: profile.telescopeFocalLength ?? profile.focalLength,
    aperture: profile.telescopeAperture ?? profile.aperture,
    focalRatio: _computeFocalRatio(profile),
    cameraName: profile.cameraName ?? cameraState.deviceName,
    sensorWidth: cameraState.sensorWidth,
    sensorHeight: cameraState.sensorHeight,
    pixelSize: cameraState.pixelSize,
  );
});

/// Filter list from active profile for dropdowns
final profileFiltersProvider = Provider<List<String>>((ref) {
  final profile = ref.watch(activeProfileProvider).valueOrNull;
  if (profile == null) return [];

  final filterNames = profile.filterNames;
  if (filterNames == null || filterNames.isEmpty) return [];

  // Parse JSON array
  try {
    final List<dynamic> parsed = jsonDecode(filterNames);
    return parsed.cast<String>();
  } catch (_) {
    return [];
  }
});

/// Profiles sorted by sort_order for display
final sortedProfilesProvider = Provider<List<EquipmentProfile>>((ref) {
  final profiles = ref.watch(allProfilesProvider).valueOrNull ?? [];
  return [...profiles]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
});
```

**Create OpticalConfig model:**

```dart
@freezed
class OpticalConfig with _$OpticalConfig {
  const factory OpticalConfig({
    String? telescopeName,
    double? focalLength,
    double? aperture,
    double? focalRatio,
    String? cameraName,
    int? sensorWidth,
    int? sensorHeight,
    double? pixelSize,
  }) = _OpticalConfig;

  const OpticalConfig._();

  /// Field of view in degrees (width, height)
  (double, double)? get fieldOfView {
    if (focalLength == null || sensorWidth == null || sensorHeight == null || pixelSize == null) {
      return null;
    }
    final widthMm = sensorWidth! * pixelSize! / 1000;
    final heightMm = sensorHeight! * pixelSize! / 1000;
    final fovWidth = 2 * atan(widthMm / (2 * focalLength!)) * 180 / pi;
    final fovHeight = 2 * atan(heightMm / (2 * focalLength!)) * 180 / pi;
    return (fovWidth, fovHeight);
  }

  /// Image scale in arcsec/pixel
  double? get imageScale {
    if (focalLength == null || pixelSize == null) return null;
    return 206.265 * pixelSize! / focalLength!;
  }

  /// Formatted FOV string
  String? get fovString {
    final fov = fieldOfView;
    if (fov == null) return null;
    return '${fov.$1.toStringAsFixed(2)}° × ${fov.$2.toStringAsFixed(2)}°';
  }

  /// Formatted scale string
  String? get scaleString {
    final scale = imageScale;
    if (scale == null) return null;
    return '${scale.toStringAsFixed(2)}"/px';
  }
}
```

**Verification:**
- Run `melos run generate` for freezed
- Verify OpticalConfig computes FOV correctly
- Verify providers compile and return expected types
- Write a simple test that creates an OpticalConfig and checks fieldOfView calculation

---

## Phase 2: Profile Sidebar & Device Cards (3 agents in parallel)

### Agent 2-1: Profile Sidebar Component

**Scope:** Create new profile sidebar widget replacing the horizontal quick connect bar.

**Files to create:**
- `packages/nightshade_app/lib/screens/equipment/widgets/profile_sidebar.dart`

**Files to modify:**
- `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` (integrate sidebar)

**ProfileSidebar widget requirements:**

1. **Layout:** Fixed 240px width, full height of equipment screen
2. **Header:** "PROFILES" title with [+] button to create new profile

3. **Profile cards** showing:
   - Default star indicator (★) if `isDefault == true`
   - Profile icon (emoji from `profileIcon` field, default 🔭)
   - Profile name (bold, primary text color)
   - Subtitle (from `profile.subtitle` computed property)
   - Device dots: one dot per assigned device type, colored by connection state
   - Connection count: "3/5" format

4. **Device dot order:** Camera → Mount → Focuser → Filter Wheel → Guider → Rotator

5. **Dot colors:**
   - Connected: `colors.success` (solid)
   - Connecting: `colors.warning` (pulsing animation)
   - Error: `colors.error` (solid)
   - Disconnected: `colors.textMuted` (hollow/outline)
   - Not in profile: no dot rendered

6. **Selected state:** Accent border using `profile.profileColor` or `colors.primary`

7. **Interactions:**
   - Single tap: Select profile (update `selectedEquipmentProfileIdProvider`)
   - Double tap: Select + trigger Connect All
   - Right-click / long-press: Show context menu
   - Drag: Reorder profiles (update `sortOrder` in database)

8. **Context menu items:**
   - "Set as Default" (toggle `isDefault`)
   - "Edit Profile" (open profile editor dialog)
   - "Duplicate" (create copy with " Copy" suffix)
   - "Delete" (confirmation dialog first)

9. **Footer actions** (below profile list):
   - [Connect All] button - primary variant, shown when selected profile has disconnected devices
   - [Disconnect All] button - ghost variant, shown when devices are connected
   - [Edit Profile] button - ghost variant, always shown

10. **Empty state:** When no profiles exist, show:
    - 🔭 icon
    - "No profiles yet"
    - "Create a profile to save your equipment configuration"
    - [Create First Profile] button

**Integration with equipment_screen.dart:**
- Replace the `QuickConnectBar` widget with `ProfileSidebar`
- Change layout from Column to Row with sidebar on left
- Sidebar takes fixed 240px, dashboard takes remaining space

**Verification:**
- Profile sidebar renders all profiles from `sortedProfilesProvider`
- Clicking a profile updates selection
- Double-clicking triggers connection
- Context menu actions work (delete shows confirmation, duplicate creates copy)
- Drag reorder persists to database
- Empty state shows when no profiles

---

### Agent 2-2: Device Card Redesign

**Scope:** Create new device card widget with proper visual hierarchy and quick actions.

**Files to create:**
- `packages/nightshade_app/lib/screens/equipment/widgets/device_card.dart`

**Files to modify:**
- `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` (replace `_ConnectedDeviceCard`)

**DeviceCard widget requirements:**

1. **Layout:** Responsive width (min 280px, flex-grow), consistent padding (20px)

2. **Header row:**
   - Device type icon in colored container (40x40, rounded)
   - Device type label (small, muted: "CAMERA")
   - Device name (bold, primary: "ZWO ASI294MC Pro")
   - Connection badge (right-aligned): "● Connected" / "◐ Connecting" / "✕ Error" / "○ Disconnected"

3. **Primary metrics row:** Large text with small label below
   - Display 3 key metrics per device type (see table below)
   - Metrics should be evenly spaced in a Row

4. **Quick actions row:**
   - Device-specific action buttons (see table below)
   - Settings gear icon button (opens device settings dialog)
   - Disconnect/Connect button

5. **Expanded state** (toggle on card tap):
   - Additional telemetry in a subtle background container
   - "Edit Name" button to customize device friendly name

6. **Border color by state:**
   - Connected: `colors.success`
   - Connecting: `colors.warning`
   - Error: `colors.error`
   - Disconnected: `colors.border`

**Primary metrics by device type:**

| Device | Metric 1 | Metric 2 | Metric 3 |
|--------|----------|----------|----------|
| Camera | Sensor Temp (°C) | Cooler Power (%) | Status (Idle/Exposing) |
| Mount | RA / Dec | Tracking (On/Off) | Status (Slewing/Parked/Ready) |
| Focuser | Position | Temperature (°C) | Status (Moving/Ready) |
| Filter Wheel | Current Filter | Position (#) | - |
| Guider | RMS Total (") | RA/Dec RMS | Status (Guiding/Idle) |
| Rotator | Angle (°) | - | Status (Moving/Ready) |

**Quick actions by device type:**

| Device | Action 1 | Action 2 |
|--------|----------|----------|
| Camera | "Cool to [target]" | "Warm Up" |
| Mount | "Park" / "Unpark" | "Tracking On/Off" |
| Focuser | "Move to..." (opens input) | - |
| Filter Wheel | Filter dropdown | - |
| Guider | "Start Guiding" / "Stop" | - |
| Rotator | "Rotate to..." (opens input) | - |

**Card factory pattern:**

```dart
class DeviceCard extends ConsumerWidget {
  final DeviceType type;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  // Factory constructor determines which variant to build
  factory DeviceCard.camera(...) => DeviceCard(type: DeviceType.camera, ...);
  factory DeviceCard.mount(...) => DeviceCard(type: DeviceType.mount, ...);
  // etc.
}
```

**Verification:**
- Each device type renders its specific metrics
- Quick action buttons trigger actual device commands (not empty callbacks!)
- Expanded state shows additional info
- Edit Name saves to profile's `*Name` field
- Settings button opens device settings (or shows "Not implemented" toast if no settings exist yet)
- Connection state changes border color

---

### Agent 2-3: Profile Editor Dialog

**Scope:** Create single-page profile editor replacing the multi-step wizard.

**Files to create:**
- `packages/nightshade_app/lib/screens/equipment/dialogs/profile_editor_dialog.dart`

**Files to modify:**
- `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` (wire up dialog)
- `packages/nightshade_app/lib/screens/equipment/widgets/profile_sidebar.dart` (wire up dialog)

**ProfileEditorDialog requirements:**

1. **Dialog size:** 600px wide, scrollable content, max 80% screen height

2. **Sections (all in single scrollable view):**

**Section 1: Profile Identity**
- Name text field (required, 1-100 chars)
- Icon picker: Row of emoji options (🔭 🌙 🪐 ⭐ 📷 🔴 🔵 🟢 🟡) + "More" option
- Color picker: Small color swatches for accent color
- "Default profile" checkbox with label "(auto-connect on startup)"

**Section 2: Optical Train**
- Telescope name text field
- Focal length number field (mm)
- Aperture number field (mm)
- Computed displays (read-only):
  - f/Ratio: "f/5.5 (calculated)" - auto-compute from focal/aperture
  - Scale: "1.26\"/px (at 3.76µm)" - needs pixel size from camera

**Section 3: Devices**
For each device type (Camera, Mount, Focuser, Filter Wheel, Guider, Rotator):
- Friendly name display (editable inline)
- Device ID dropdown showing:
  - Currently assigned device (if any)
  - All discovered devices of that type
  - "Scan for devices..." option
  - "Enter ID manually..." option
- Clear (✕) button to unassign
- Show raw device ID below name in muted text

- [+ Add from connected] button at bottom - populates empty slots from currently connected devices

**Section 4: Filters** (only if filter wheel assigned)
- Table with columns: #, Name, Focus Offset
- Editable text fields for each filter slot
- [+ Add Filter] button
- [Auto-detect from wheel] button - queries connected filter wheel

**Section 5: Camera Defaults**
- Gain number field
- Offset number field
- Binning dropdown (1x1, 2x2, 3x3, 4x4)
- Cooling target number field (°C)
- "Cool on connect" checkbox

3. **Section headers:** Collapsible with [−]/[+] toggle, show summary when collapsed

4. **Footer:** [Cancel] and [Save Changes] buttons (or [Create Profile] for new)

5. **Validation:**
   - Name required
   - Focal length required if aperture set (and vice versa)
   - Show inline validation errors

6. **New profile mode:**
   - Title: "New Profile"
   - Empty fields (or copy from source if duplicating)
   - Button: "Create Profile"

**Verification:**
- Dialog opens from sidebar context menu "Edit Profile"
- Dialog opens from sidebar [Edit Profile] button
- Dialog opens from [+] button in "New Profile" mode
- All fields save correctly to database
- Computed f/ratio updates as focal length/aperture change
- Device dropdowns show discovered devices
- "Add from connected" populates from actual connected devices
- Filters section only shows when filter wheel assigned
- Cancel discards changes, Save persists them

---

## Phase 3: Discovery Panel & Screen Integration (2 agents in parallel)

### Agent 3-1: Discovery Panel Refactor

**Scope:** Convert discovery from a tab to a collapsible panel at the bottom of the dashboard.

**Files to create:**
- `packages/nightshade_app/lib/screens/equipment/widgets/discovery_panel.dart`

**Files to modify:**
- `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` (remove tabs, add panel)

**Files to delete/deprecate:**
- `packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart` (functionality moves to panel)

**DiscoveryPanel widget requirements:**

1. **Collapsed state (default):**
   - Single row: "DISCOVERY" label, device count ("3 devices found"), last scan time, [Scan All] button, [▼ Expand] button
   - Subtle background to distinguish from device cards above

2. **Expanded state:**
   - Grouped by device type: CAMERAS, MOUNTS, FOCUSERS, FILTER WHEELS, GUIDERS, ROTATORS
   - Each group shows discovered devices of that type
   - Empty groups show "No {type} found" with [Scan] button

3. **Device row in discovery:**
   - Connection indicator (● connected, ○ available)
   - Device name (friendly, parsed from driver)
   - Driver type badge (native, ascom, alpaca, phd2, indi)
   - [Assign ▼] dropdown - assign to profile slot
   - [Connect] / [Disconnect] button

4. **Assign dropdown contents:**
   - Header: "Assign to {ProfileName} as:"
   - Options for each device slot: "Camera (empty)" or "Camera (has ASI294)"
   - Separator
   - Other profiles listed similarly
   - Selecting replaces existing assignment

5. **Auto-collapse behavior:**
   - Collapse after successful connection
   - Stay expanded if errors occur

6. **Scan functionality:**
   - [Scan All] triggers `unifiedDiscoveryProvider.notifier.discoverAll()`
   - Per-type [Scan] triggers discovery for just that type
   - Show loading indicator during scan
   - "Last scan: X min ago" updates in real-time

**Integration with equipment_screen.dart:**

Remove the tab bar and `IndexedStack`. New layout:

```dart
Row(
  children: [
    // Left: Profile sidebar (240px fixed)
    SizedBox(width: 240, child: ProfileSidebar(...)),

    // Right: Device dashboard (flexible)
    Expanded(
      child: Column(
        children: [
          // Device cards grid
          Expanded(child: DeviceDashboard(...)),

          // Discovery panel (collapsible)
          DiscoveryPanel(...),
        ],
      ),
    ),
  ],
)
```

**Verification:**
- Panel expands and collapses smoothly
- Scan button triggers discovery
- Discovered devices appear grouped by type
- Assign dropdown shows all profiles and slots
- Assigning updates profile in database
- Connect/Disconnect buttons work
- Last scan time updates

---

### Agent 3-2: Equipment Screen Layout Overhaul

**Scope:** Restructure equipment_screen.dart to use new two-panel layout.

**Files to modify:**
- `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart`

**Changes required:**

1. **Remove old components:**
   - Remove `QuickConnectBar` usage
   - Remove `ConnectionStatusZone` usage
   - Remove tab bar (`_SubTabBar`, `_SubTabData`)
   - Remove `IndexedStack` with tabs
   - Remove `_ConnectedDevicesTab` (replaced by DeviceDashboard)

2. **Add new layout structure:**

```dart
@override
Widget build(BuildContext context) {
  final colors = Theme.of(context).extension<NightshadeColors>()!;
  final profilesAsync = ref.watch(sortedProfilesProvider);
  final selectedProfileId = ref.watch(selectedEquipmentProfileIdProvider);

  // First-time onboarding check
  final showOnboarding = profilesAsync.maybeWhen(
    data: (profiles) => profiles.isEmpty,
    orElse: () => false,
  );

  if (showOnboarding) {
    return _FirstTimeOnboarding(...); // Keep existing
  }

  return Row(
    children: [
      // Profile Sidebar
      SizedBox(
        width: 240,
        child: ProfileSidebar(
          selectedProfileId: selectedProfileId,
          onProfileSelected: (id) => ref.read(selectedEquipmentProfileIdProvider.notifier).state = id,
          onCreateProfile: () => _showProfileEditor(context, null),
          onEditProfile: (profile) => _showProfileEditor(context, profile),
        ),
      ),

      // Divider
      VerticalDivider(width: 1, color: colors.border),

      // Device Dashboard + Discovery
      Expanded(
        child: Column(
          children: [
            // Header
            _DashboardHeader(
              profileName: selectedProfile?.name,
              onSettings: () => _showSettings(context),
            ),

            // Device cards
            Expanded(
              child: DeviceDashboard(
                profile: selectedProfile,
                onAssignDevice: (type, deviceId) => _assignDevice(type, deviceId),
              ),
            ),

            // Discovery panel
            DiscoveryPanel(
              onAssignDevice: (type, deviceId, profileId) => _assignDevice(type, deviceId, profileId),
            ),
          ],
        ),
      ),
    ],
  );
}
```

3. **Create DeviceDashboard widget:**
   - Responsive grid of DeviceCard widgets
   - Shows cards for all device types in profile (connected or not)
   - Empty slots show "Click to assign" placeholder
   - Uses `Wrap` with `spacing: 16, runSpacing: 16`

4. **Create _DashboardHeader widget:**
   - Shows profile name
   - Settings gear button (opens equipment settings)
   - Help button

5. **Move settings to dialog:**
   - `EquipmentSettingsTab` becomes `EquipmentSettingsDialog`
   - Triggered by gear button in header

**Verification:**
- Screen renders with sidebar on left, dashboard on right
- Selecting profile updates dashboard cards
- Device cards show correct connection state
- Discovery panel appears at bottom
- No visual regressions (spacing, colors, fonts)
- Settings accessible via gear button

---

## Phase 4: Context-Aware Integration (3 agents in parallel)

### Agent 4-1: Global Status Bar Integration

**Scope:** Add equipment status section to the app's global status bar.

**Files to modify:**
- `packages/nightshade_app/lib/widgets/app_shell.dart` (or wherever status bar lives)

**Files to create:**
- `packages/nightshade_app/lib/widgets/equipment_status_indicator.dart`

**EquipmentStatusIndicator requirements:**

1. **Compact display** (in status bar):
   - Profile icon + name
   - Connection badge: "● 5/5" (green) or "◐ 3/5" (yellow) or "✕ 0/5" (red)

2. **Click to expand** dropdown showing:
   - Profile name and full connection status
   - Divider
   - List of devices with: icon, name, status, key metric
   - Divider
   - [Disconnect All] and [Equipment] buttons

3. **Device rows in dropdown:**
```
📷 ASI294MC Pro     ● -10.2°C
🔭 EQ6-R Pro        ● Tracking
🎯 ZWO EAF          ● 12450
◐ ZWO EFW           ● Ha
⊕ PHD2              ● 0.42"
```

4. **Status bar section layout:**
```
🔭 Backyard Rig  ● 5/5  │  🌡 -10.2°C  │  📍 Tracking  │  ⏱ 21:34
    ▲                         ▲              ▲              ▲
    Profile status            Camera temp    Mount status   Session time
```

5. **Integration:** Add to status bar row in app_shell.dart

**Verification:**
- Status indicator appears in global status bar
- Shows correct profile name and connection count
- Click expands dropdown with device list
- Dropdown actions work (Disconnect All, navigate to Equipment)
- Updates in real-time as devices connect/disconnect

---

### Agent 4-2: Framing Screen Optical Config

**Scope:** Show optical configuration from active profile in the framing screen.

**Files to modify:**
- `packages/nightshade_app/lib/screens/framing/framing_screen.dart`

**Files to create:**
- `packages/nightshade_app/lib/screens/framing/widgets/optical_config_panel.dart`

**OpticalConfigPanel requirements:**

1. **When profile has optical config:**
```
┌─ OPTICAL CONFIG ─────────────────────┐
│  🔭 Esprit 100ED                     │
│  550mm f/5.5 @ 100mm                 │
│                                       │
│  📷 ASI294MC Pro                     │
│  4144 × 2822 px (3.76µm)             │
│                                       │
│  FOV: 1.72° × 1.17°                  │
│  Scale: 1.41"/px                     │
│                                       │
│  [Change Profile ▼]                  │
└───────────────────────────────────────┘
```

2. **When no profile or missing config:**
```
┌─ OPTICAL CONFIG ─────────────────────┐
│                                       │
│  ⚠ No optical configuration          │
│                                       │
│  Set up your telescope and camera    │
│  to see accurate field of view.      │
│                                       │
│  [Configure in Equipment]            │
│                                       │
└───────────────────────────────────────┘
```

3. **Data source:** Use `opticalConfigProvider`

4. **Change Profile dropdown:** Shows all profiles, selecting switches active profile

5. **Integration:** Add panel to framing screen layout (left side or top, depending on existing layout)

**Verification:**
- Panel shows optical config from active profile
- FOV and scale compute correctly
- Missing config shows warning state
- "Configure in Equipment" navigates to equipment screen
- Change Profile dropdown switches profile

---

### Agent 4-3: Sequencer Filter & Defaults Integration

**Scope:** Use profile filters and camera defaults in sequencer exposure editor.

**Files to modify:**
- `packages/nightshade_app/lib/screens/sequencer/` - find exposure/filter editing widgets

**Search for:** Filter dropdowns, exposure settings, gain/offset fields in sequencer

**Requirements:**

1. **Filter dropdowns** should:
   - Use `profileFiltersProvider` for options
   - Show filters from active profile
   - Include "Edit filters..." option that opens profile editor
   - Fall back to generic list if no profile

2. **Exposure editor** should:
   - Pre-populate Gain from `activeProfile.defaultGain`
   - Pre-populate Offset from `activeProfile.defaultOffset`
   - Pre-populate Binning from `activeProfile.defaultBinX/Y`
   - Show "(profile default)" hint text when using defaults
   - Allow override (user can change from default)

3. **Visual indicator** when using profile defaults vs custom value

**Verification:**
- Filter dropdown shows filters from active profile
- New exposure nodes get profile default values
- Changing defaults in profile editor reflects in sequencer
- "Edit filters" option opens profile editor dialog

---

## Phase 5: Verification Agents (4 agents in parallel)

**CRITICAL: These agents verify the implementation is complete. They must be ruthless in finding issues.**

### Agent 5-1: Database & Model Verification

**Scope:** Verify all schema changes are complete and models are correct.

**Tasks:**

1. **Check schema migration:**
   - Read `equipment_profiles.drift` - verify ALL 12 new columns exist
   - Read `database.dart` - verify migration from v5 to v6 is complete
   - Verify migration adds columns, doesn't drop data

2. **Check generated code:**
   - Run `melos run generate`
   - Verify `EquipmentProfile` class has all new fields
   - Verify no compilation errors

3. **Check model:**
   - Read `equipment_profile_model.dart`
   - Verify all new fields are in freezed model
   - Verify `subtitle` computed property works
   - Verify `deviceCount` computed property works

4. **Check providers:**
   - Read `profiles_provider.dart`
   - Verify `opticalConfigProvider` exists and computes correctly
   - Verify `profileFiltersProvider` exists and parses JSON
   - Verify `sortedProfilesProvider` exists and sorts

5. **Check OpticalConfig:**
   - Verify `fieldOfView` calculation is mathematically correct
   - Verify `imageScale` calculation uses correct formula (206.265 * pixelSize / focalLength)

**Report any:**
- Missing columns in schema
- Missing fields in models
- Incorrect calculations
- Unimplemented providers

---

### Agent 5-2: UI Component Verification

**Scope:** Verify all new UI components are complete with no stubs.

**Tasks:**

1. **ProfileSidebar verification:**
   - Read `profile_sidebar.dart`
   - Verify all 10 requirements from Agent 2-1 are implemented
   - Check: profile cards show all info (icon, name, subtitle, dots, count)
   - Check: selection works
   - Check: double-click connects
   - Check: context menu has all items AND they all work (not empty callbacks)
   - Check: drag reorder is implemented
   - Check: empty state exists

2. **DeviceCard verification:**
   - Read `device_card.dart`
   - Verify all device types have their specific metrics (check the table)
   - Verify all device types have their quick actions (check the table)
   - Check: quick action buttons call real device service methods (not `() {}`)
   - Check: settings button does something
   - Check: expanded state shows additional info
   - Check: edit name saves to database

3. **ProfileEditorDialog verification:**
   - Read `profile_editor_dialog.dart`
   - Verify all 5 sections exist
   - Check: Profile Identity section complete
   - Check: Optical Train section complete with computed f/ratio
   - Check: Devices section complete with dropdowns
   - Check: Filters section conditional on filter wheel
   - Check: Camera Defaults section complete
   - Check: Validation works
   - Check: Save actually saves to database

4. **DiscoveryPanel verification:**
   - Read `discovery_panel.dart`
   - Check: collapsed state shows summary
   - Check: expanded state shows grouped devices
   - Check: assign dropdown works
   - Check: connect/disconnect work
   - Check: scan triggers discovery

**Report any:**
- Empty callback bodies `() {}`
- TODO comments
- `throw UnimplementedError()`
- Missing sections or features
- Features that don't actually work

---

### Agent 5-3: Integration Verification

**Scope:** Verify all components are properly wired together.

**Tasks:**

1. **Equipment screen integration:**
   - Read `equipment_screen.dart`
   - Verify old components removed (QuickConnectBar, ConnectionStatusZone, tabs)
   - Verify new layout uses ProfileSidebar + DeviceDashboard + DiscoveryPanel
   - Verify profile editor dialog is accessible

2. **Global status bar integration:**
   - Read `app_shell.dart`
   - Verify `EquipmentStatusIndicator` is added to status bar
   - Verify it watches correct providers
   - Verify dropdown actions navigate correctly

3. **Framing screen integration:**
   - Read `framing_screen.dart`
   - Verify `OpticalConfigPanel` is present
   - Verify it uses `opticalConfigProvider`
   - Verify empty state navigates to equipment

4. **Sequencer integration:**
   - Find filter dropdown widgets
   - Verify they use `profileFiltersProvider`
   - Find exposure editor
   - Verify it reads profile defaults

5. **Provider connections:**
   - Trace: `activeProfileProvider` → used by OpticalConfigPanel
   - Trace: `opticalConfigProvider` → used by framing screen
   - Trace: `profileFiltersProvider` → used by sequencer
   - Trace: `sortedProfilesProvider` → used by ProfileSidebar

**Report any:**
- Components not wired up
- Providers defined but never watched
- Navigation that doesn't work
- Missing integrations

---

### Agent 5-4: Full Flow Testing

**Scope:** Manually trace complete user flows to verify end-to-end functionality.

**Tasks:**

1. **New user flow:**
   - App starts with no profiles → First-time onboarding shows
   - Click "Create First Profile" → Profile editor opens
   - Fill in name, telescope, devices → Save works
   - Profile appears in sidebar
   - Click profile → Device cards show
   - Click Connect All → Devices connect (or show error if no devices)

2. **Edit profile flow:**
   - Right-click profile → Context menu shows
   - Click "Edit Profile" → Editor dialog opens with existing data
   - Change name → Save → Name updates in sidebar
   - Add filter names → Save → Filters appear in sequencer

3. **Device connection flow:**
   - Expand discovery panel → Devices listed
   - Click Connect on device → Device connects
   - Device card updates to show Connected state
   - Status bar updates with connection count

4. **Optical config flow:**
   - Set telescope focal length and aperture in profile
   - Go to framing screen
   - OpticalConfigPanel shows computed FOV and scale
   - FOV matches manual calculation

5. **Profile switching flow:**
   - Create two profiles with different devices
   - Click profile 1 → Its devices show
   - Click profile 2 → Its devices show
   - Status bar updates to show correct profile

**Report any:**
- Flows that don't complete
- Data that doesn't persist
- UI that doesn't update
- Calculations that are wrong

---

## Execution Order

```
PHASE 1 (sequential - schema must exist before models):
  [1-1] Database Schema ────► [1-2] Models & Providers

PHASE 2 (parallel, after Phase 1):
  [2-1] Profile Sidebar
  [2-2] Device Cards
  [2-3] Profile Editor Dialog

PHASE 3 (parallel, after Phase 2):
  [3-1] Discovery Panel
  [3-2] Equipment Screen Layout

PHASE 4 (parallel, after Phase 3):
  [4-1] Global Status Bar
  [4-2] Framing Screen Integration
  [4-3] Sequencer Integration

PHASE 5 (parallel, after Phase 4):
  [5-1] Database/Model Verification
  [5-2] UI Component Verification
  [5-3] Integration Verification
  [5-4] Full Flow Testing
```

---

## Success Criteria

1. **All new schema fields** are in database and models
2. **Profile sidebar** replaces horizontal chip bar
3. **Device cards** show proper metrics and have working quick actions
4. **Profile editor** is single-page with all sections
5. **Discovery** is collapsible panel, not a tab
6. **Equipment status** visible in global status bar
7. **Optical config** shown on framing screen
8. **Profile filters** used in sequencer
9. **NO stubs, placeholders, or empty callbacks anywhere**
10. **All features accessible from UI**

---

## Verification Commands

After implementation, run:

```bash
# Generate code
melos run generate

# Analyze for errors
melos run analyze

# Run tests
melos run test

# Build to verify compilation
cd apps/desktop && flutter build windows --debug
```
