# Mobile UI Scaling Fixes Plan

## Overview

The app has excellent responsive infrastructure (`Responsive` utilities, breakpoints, `ResponsiveCardGrid`) but many screens don't use it. Screens that work (Equipment, Framing, Analytics, Flat Wizard) use `Wrap`, `Expanded`, and flexible layouts. Screens that break (Dashboard, Imaging, Guiding, Planetarium, Sequencer, Settings) use hardcoded widths and inflexible `Row` layouts.

## Breakpoints (from NightshadeTokens)

- **Mobile**: 0-480px (phones)
- **Tablet**: 480-768px (tablets, small laptops)
- **Desktop**: 768-1024px (laptops)
- **Large Desktop**: 1024-1440px (monitors)
- **Ultra-wide**: 1440px+ (ultrawide monitors)

## Core Patterns to Apply

### 1. Use `Responsive.isMobile()` for layout switching
```dart
Responsive.isMobile(context)
    ? _buildMobileLayout()
    : _buildDesktopLayout()
```

### 2. Replace fixed widths with `Responsive.value()`
```dart
// Before
SizedBox(width: 320)

// After
SizedBox(width: Responsive.value(context, mobile: double.infinity, tablet: 280, desktop: 320))
```

### 3. Use `Wrap` instead of `Row` for reflowing content
```dart
// Before
Row(children: [Card1(), Card2(), Card3()])

// After
Wrap(spacing: 16, runSpacing: 16, children: [Card1(), Card2(), Card3()])
```

### 4. Make panels collapsible or scrollable on mobile
```dart
// Mobile: Stack panels vertically with SingleChildScrollView
// Desktop: Side-by-side panels
```

### 5. Use `LayoutBuilder` for fine-grained control
```dart
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < 600) {
      return _MobileLayout();
    }
    return _DesktopLayout();
  },
)
```

---

## Screen-by-Screen Fixes

### 1. Dashboard Screen ⚠️ HIGH PRIORITY
**File**: `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart`

**Issues**:
- Complex grid layout with hardcoded card sizes
- Session progress cards don't scale
- Weather widget fixed width
- Status cards use Row without wrapping

**Fixes**:
- Use `ResponsiveCardGrid` for device status cards
- Make session cards full-width on mobile (stack vertically)
- Weather widget: full-width on mobile, fixed on desktop
- Status row: `Wrap` instead of `Row`
- Quick actions: horizontal scroll on mobile, grid on desktop

**Mobile Layout** (single column, scrollable):
```
[Weather Widget - full width]
[Session Card - full width]
[Device Status Cards - stacked]
[Quick Actions - horizontal scroll]
```

**Desktop Layout** (current multi-column)

---

### 2. Imaging Screen ⚠️ HIGH PRIORITY
**File**: `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart`

**Issues**:
- Capture settings panel: `SizedBox(width: 320)` hardcoded
- Tab content doesn't adapt
- Image viewer + sidebar layout breaks

**Fixes**:
- Mobile: Full-width tabs, settings in bottom sheet or collapsible drawer
- Replace `SizedBox(width: 320)` with responsive width
- Use `LayoutBuilder` to switch between mobile/desktop layouts

**Mobile Layout**:
```
[Image Viewer - full screen]
[Tab Bar at bottom]
[Settings accessible via floating button/drawer]
```

**Desktop Layout** (current side-by-side)

---

### 3. Guiding Screen ⚠️ CRITICAL
**File**: `packages/nightshade_app/lib/screens/guiding/guiding_screen.dart`

**Issues**:
- `SizedBox(width: 280)` left panel - HARDCODED
- `SizedBox(width: 300)` right panel - HARDCODED
- Total minimum: 580px+ (impossible on phones!)

**Fixes**:
- Mobile: Stack panels vertically with tabs or accordion
- Use `Responsive.isMobile()` to switch layouts
- Remove hardcoded widths entirely

**Mobile Layout**:
```
[Guide Graph - full width, shorter height]
[Tab Bar: Status | Settings | History]
[Tab Content - full width, scrollable]
```

**Desktop Layout** (current 3-column)

---

### 4. Planetarium Screen ⚠️ HIGH PRIORITY
**File**: `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart`

**Issues**:
- Filter sidebar: `SizedBox(width: 320)` hardcoded
- Object info panel fixed width
- Sky view + panels don't adapt

**Fixes**:
- Mobile: Sky view full screen, panels as bottom sheets
- Filter panel: Collapsible or in drawer
- Object info: Bottom sheet on mobile

**Mobile Layout**:
```
[Sky View - full screen]
[FAB for filters]
[Bottom sheet for object info when selected]
```

**Desktop Layout** (current side panels)

---

### 5. Sequencer Screen ⚠️ HIGH PRIORITY
**File**: `packages/nightshade_app/lib/screens/sequencer/sequencer_screen.dart`

**Issues**:
- Builder tab: `SizedBox(width: 320)` for node palette
- Sequence tree doesn't scale
- Properties panel fixed

**Fixes**:
- Mobile: Node palette as bottom sheet
- Tree view: Collapsible with larger touch targets
- Properties: Full-width modal on mobile

**Mobile Layout**:
```
[Sequence Tree - full width]
[FAB to add nodes -> opens bottom sheet]
[Properties panel as modal when node selected]
```

**Desktop Layout** (current 3-column)

---

### 6. Settings Screen ⚠️ MEDIUM PRIORITY
**File**: `packages/nightshade_app/lib/screens/settings/settings_screen.dart`

**Issues**:
- `ResizablePanel(initialWidth: 240, minWidth: 180, maxWidth: 400)` for nav
- Split layout doesn't work on phones

**Fixes**:
- Mobile: Navigation list, tap to navigate to settings page
- Replace split view with navigation-based approach on mobile

**Mobile Layout**:
```
[Settings Categories List - full width]
Tap -> Navigate to settings detail page
```

**Desktop Layout** (current split view)

---

### 7. Weather Screen ⚠️ LOW PRIORITY
**File**: `packages/nightshade_app/lib/screens/weather/weather_screen.dart`

**Issues**:
- Multiple panels with fixed widths
- Forecast cards don't wrap

**Fixes**:
- Stack panels vertically on mobile
- Forecast cards: horizontal scroll on mobile
- Radar view: full width on mobile

---

## Implementation Order

**Phase 1 - Critical (can't use at all on mobile)**:
1. Guiding Screen - hardcoded 580px minimum
2. Imaging Screen - main functionality broken
3. Dashboard Screen - home screen must work

**Phase 2 - High Priority (usable but bad)**:
4. Planetarium Screen - important feature
5. Sequencer Screen - important feature
6. Settings Screen - users need to configure

**Phase 3 - Polish**:
7. Weather Screen - less critical

---

## Files to Modify

| Screen | File Path | Priority |
|--------|-----------|----------|
| Dashboard | `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` | HIGH |
| Imaging | `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` | HIGH |
| Guiding | `packages/nightshade_app/lib/screens/guiding/guiding_screen.dart` | CRITICAL |
| Planetarium | `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` | HIGH |
| Sequencer | `packages/nightshade_app/lib/screens/sequencer/sequencer_screen.dart` | HIGH |
| Settings | `packages/nightshade_app/lib/screens/settings/settings_screen.dart` | MEDIUM |
| Weather | `packages/nightshade_app/lib/screens/weather/weather_screen.dart` | LOW |

---

## Verification

After fixes, test at these widths:
- 375px (iPhone SE)
- 414px (iPhone Plus/Max)
- 768px (iPad portrait)
- 1024px (iPad landscape)
- 1440px+ (desktop)

All screens should:
- ✅ No overflow errors
- ✅ All controls accessible
- ✅ Text readable (not wrapped weirdly)
- ✅ Touch targets large enough (48px minimum)
- ✅ Scrollable when content exceeds screen
