# UI Visual Polish Design: "Quiet Confidence"

**Date:** 2026-01-07
**Status:** Approved
**Goal:** Elevate Nightshade's UI from functional to premium through strategic use of animations, shadows, and refined interactions while maintaining professional aesthetic.

---

## Design Philosophy

### Core Principle: Calm Base, Vibrant Signals

The majority of the UI stays in a subdued dark palette to prevent fatigue during long imaging sessions. Vibrancy is reserved for elements that demand attention, creating a clear visual hierarchy.

**What earns vibrancy:**
- Primary actions and CTAs
- Active status indicators
- Data visualization
- State changes that need acknowledgment

**What stays calm:**
- Surface backgrounds
- Text content areas
- Unfocused form inputs
- Secondary/tertiary actions

### Aesthetic Guidelines

- **Gradients are monochromatic or near-monochromatic** - Depth without circus (indigo-600 to indigo-500, not rainbow)
- **Glows are soft and functional** - 2-4px glow that says "this is active," not neon signs
- **Color saturation stays controlled** - Existing palette works harder through contrast and placement
- **Animation implies quality, not fun** - Smooth 200-300ms eases that feel precise, not bouncy
- **Status colors are the only "loud" elements** - And only when demanding attention

The goal is a professional studio feel, not a gaming lounge. Everything considered and purposeful.

---

## Section 1: Animation System Overhaul

### New Animation Tokens

Add to `NightshadeTokens`:

```dart
// Refined curves for different purposes
static const curveSnappy = Curves.easeOutCubic;      // Responsive UI feedback
static const curvePrecise = Curves.easeInOutCubic;   // State transitions
static const curveSettle = Curves.easeOutBack;       // Slight overshoot for toggles/switches

// Refined durations
static const durationMicro = Duration(milliseconds: 100);    // Hover color changes
static const durationFast = Duration(milliseconds: 150);     // Button presses
static const durationNormal = Duration(milliseconds: 200);   // Card hovers, toggles
static const durationSmooth = Duration(milliseconds: 300);   // Page transitions
static const durationCinematic = Duration(milliseconds: 400); // Modal appearances
```

### Micro-interactions

**Buttons:**
- Scale to 0.98 on press (durationFast, curveSnappy)
- Color transition on hover (durationMicro)
- Release returns to 1.0 with curveSettle

**Cards:**
- Hover: translateY(-2px) + shadow increase (durationNormal, curveSnappy)
- Transition shadow and transform together

**Toggles/Switches:**
- Use curveSettle for satisfying snap with slight overshoot
- Never use linear curves

**Icon Buttons:**
- Soft scale pulse on hover (1.0 → 1.05 → 1.0, durationNormal)

### Page Transitions

- Keep current slide-fade foundation
- Add staggered children: content fades in 50ms after container
- Sidebar navigation highlight slides smoothly to new position (not instant swap)

### Loading States

- Replace static spinners with pulsing opacity or skeleton shimmer
- Use ShimmerLoading component consistently across all screens
- Progress bars use smooth interpolation, never jump values

### Status Change Animations

- Device connect/disconnect: status pill does subtle pulse-glow
- Sequence state changes: icon rotation + color animates together
- Success states: brief glow pulse, then settles to steady

---

## Section 2: Shadows & Depth System

### Elevation Hierarchy

| Level | Usage | Visual Treatment |
|-------|-------|------------------|
| 0 (inset) | Input fields, wells, inactive areas | Subtle inner shadow |
| 1 (base) | Cards, panels, sidebar | Barely lifted, separation from background |
| 2 (raised) | Hovered cards, dropdowns, active panels | Noticeable lift |
| 3 (floating) | Modals, dialogs, tooltips | Prominent shadow + blur |

### Dark-Theme Shadow Recipes

```dart
// Level 1 - Base elevation
static final elevationLevel1 = [
  BoxShadow(
    color: Colors.black.withOpacity(0.3),
    blurRadius: 8,
    offset: Offset(0, 2),
  ),
];

// Level 2 - Raised (hover states, dropdowns)
static final elevationLevel2 = [
  BoxShadow(
    color: Colors.black.withOpacity(0.4),
    blurRadius: 16,
    offset: Offset(0, 4),
  ),
  BoxShadow(
    color: Colors.black.withOpacity(0.2),
    blurRadius: 4,
    offset: Offset(0, 1),
  ),
];

// Level 3 - Floating (modals, dialogs)
static final elevationLevel3 = [
  BoxShadow(
    color: Colors.black.withOpacity(0.5),
    blurRadius: 32,
    offset: Offset(0, 8),
  ),
  BoxShadow(
    color: colors.primary.withOpacity(0.1),
    blurRadius: 24,
    spreadRadius: -4,
  ), // Subtle accent glow
];

// Inset shadow for recessed elements
static final elevationInset = [
  BoxShadow(
    color: Colors.black.withOpacity(0.4),
    blurRadius: 4,
    offset: Offset(0, 2),
    inset: true, // Note: Requires custom implementation in Flutter
  ),
];
```

### Surface Differentiation

Introduce clear surface hierarchy:
- `surface` - Base background
- `surfaceAlt` - Cards and panels sit here
- `surfaceElevated` - Raised interactive elements
- `surfaceOverlay` - Modals and floating elements

Each level slightly lighter than the previous, creating depth through color even without shadows.

### Highlight Edges

Elevated elements get subtle top highlight:
- 1px lighter border-top or gradient edge
- Makes elements "catch light" and feel physical

---

## Section 3: Interactive Element Refinements

### Button Hierarchy

**Primary Buttons:**
```dart
// Gradient fill (not flat)
gradient: LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [colors.primary.lighten(5), colors.primary],
)

// Hover: soft glow fades in
boxShadow: [
  BoxShadow(
    color: colors.primary.withOpacity(0.3),
    blurRadius: 12,
    spreadRadius: 0,
  ),
]

// Pressed: darken + remove shadow (physical press feel)
```

**Secondary/Outline Buttons:**
- Hover: fill fades in (0% → 8% opacity of accent)
- Border brightens on hover

**Ghost Buttons:**
- Nearly invisible until hovered
- Soft background appears on hover

**Destructive Buttons:**
- Reserve true saturated red only for these
- Makes them feel appropriately serious

### Input Fields

**States:**
- Unfocused: Subtle inner shadow, muted border
- Focused: Border transitions to accent, faint outer glow (2px blur), inner shadow lifts
- Filled: Slightly different background tint (scan what's completed)
- Error: Red border + subtle red glow

### Toggles and Switches

- Track: Subtle inner shadow (feels recessed)
- Thumb: Highlight edge on top (catches light)
- Animation: curveSettle for overshoot "settling" into position
- Active: Track fills with subtle gradient, not flat color

### Cards

**Hover state:**
- translateY(-2px)
- Shadow increases (level 1 → level 2)
- Border brightens slightly (opacity +0.1)

**Selected state:**
- Accent-colored left border (3px) appears
- Or accent top border for horizontal layouts

**Transitions:**
- All changes animate together (durationNormal, curveSnappy)

### Dropdowns and Menus

- Appear with scale (0.95 → 1.0) + fade (durationCinematic)
- Selected item: soft accent background
- Hover: immediate but gentle background change

---

## Section 4: Status Indicators & Data Visualization

### Status Indicator States

| State | Visual Treatment |
|-------|------------------|
| Idle/Inactive | Muted, no animation |
| Active/Running | Subtle pulsing glow (opacity 0.4→0.7→0.4, 2s loop) |
| Warning | Amber, slightly more saturated, slow pulse |
| Error/Critical | Sharper pulse (1s), higher contrast |
| Success | Brief flash-glow on transition, then steady |

### Connection Status

- Device cards: colored left border matching connection state
- Connecting: smooth indeterminate shimmer across card
- Connected: subtle green pulse once, then steady indicator

### Progress Bars

```dart
// Smooth value interpolation (never jumps)
AnimatedContainer with durationNormal

// Gradient fill
gradient: LinearGradient(
  colors: [colors.primary, colors.primary.lighten(10)],
)

// Track has inner shadow for depth
// Completion: glow pulse + color shift to success
```

### Guide Graphs and Histograms

**Line Graphs:**
- Gradient fill under line (fades to transparent)
- Subtle grid lines at low opacity
- Soft glow at data peaks/valleys

**Histograms:**
- Bar gradient (top lighter than bottom)
- Rounded tops (radiusSm)
- Subtle gaps between bars

### Real-Time Data

- Frequently updating values: brief highlight flash on change
- Monotonic values (temperature, counts): smooth interpolation, no jumps

---

## Section 5: Navigation & Layout Structure

### Sidebar

**Elevation:**
- Level 1 shadow on right edge
- Creates clear separation from content

**Active Nav Item:**
- Accent-colored left border (3px)
- Soft background highlight
- Not just icon color change

**Hover:**
- Background fades in smoothly (durationMicro)
- Icon scales subtly (1.05x)

**Collapse Transition:**
- Smooth width animation
- Labels fade in after container expands

### Screen Headers

- Subtle bottom border with gradient fade (accent → transparent)
- Creates clear visual separation from content
- Optional: 2-3% opacity accent gradient in background (barely visible warmth)

### Section Organization

- Section headers: subtle left accent bar (2px)
- Related controls grouped in well/container (inset shadow background)
- Consistent spacing rhythm using space tokens

### Content Area

- Increase padding slightly in main content area
- Consistent card margins - nothing cramped
- Major section breaks: 32-48px spacing

### Status Bar

- Level 1 elevation (subtle top shadow)
- Dividers between status items
- Active issues pulse gently, normal status steady

---

## Section 6: Polish Details

### Typography Refinements

- Increase weight contrast between headings and body
- Key values (temps, coords, exposure times): monospace with +0.5px letter-spacing
- Optional: 1px text-shadow on headings over dark backgrounds (very low opacity)

### Icon Treatments

- Hover: icons get accent color (not just opacity change)
- Status icons: filled style, not just strokes
- Key actions: subtle animation (gear rotates on hover, refresh spins on click)

### Border Refinements

- Featured elements (cards, dialogs): subtle gradient borders
- Hover: border opacity increases (0.1 → 0.2)
- Selected: accent-colored border replaces neutral

### Focus States (Accessibility)

- Custom focus ring using accent color glow
- Animates in (opacity 0 → 1, durationFast)
- Consistent across all interactive elements

### Loading and Empty States

- Empty states: subtle icon + helpful message
- Skeleton loaders match actual content layout
- Shimmer uses subtle accent tint

### Tooltips

- Appear with 300ms delay + fade-scale animation
- Dark background with accent-tinted shadow
- Precise arrow/pointer alignment

---

## Implementation Priority

### Phase 1: Foundation (High Impact, Low Risk)
1. Add new animation tokens and curves
2. Implement elevation shadow system
3. Update NightshadeButton with new states
4. Update NightshadeCard with hover animations

### Phase 2: Interactive Elements
1. Refine input field states
2. Update toggles and switches
3. Dropdown/menu animations
4. Focus state system

### Phase 3: Status & Data
1. Status indicator animations
2. Progress bar refinements
3. Guide graph/histogram styling
4. Real-time value animations

### Phase 4: Navigation & Layout
1. Sidebar elevation and transitions
2. Screen header styling
3. Section organization
4. Status bar refinements

### Phase 5: Polish
1. Typography refinements
2. Icon treatments
3. Border refinements
4. Empty/loading states
5. Tooltip refinements

---

## Files to Modify

**Design System (packages/nightshade_ui):**
- `lib/src/theme/nightshade_tokens.dart` - Add animation curves, elevation shadows
- `lib/src/theme/nightshade_colors.dart` - Add surface hierarchy colors
- `lib/src/components/nightshade_button.dart` - Gradient, glow, press states
- `lib/src/components/nightshade_card.dart` - Hover lift, shadow transitions
- `lib/src/components/nightshade_text_field.dart` - Focus glow, filled state
- `lib/src/components/nightshade_switch.dart` - Overshoot animation, gradient track
- `lib/src/components/status_pill.dart` - Pulse animations
- `lib/src/components/nightshade_progress_bar.dart` - Gradient fill, smooth interpolation

**App Shell (packages/nightshade_app):**
- `lib/screens/shell/side_navigation.dart` - Elevation, hover states, transitions
- `lib/screens/shell/status_bar.dart` - Elevation, dividers
- Various screen files for section headers and layout spacing

---

## Success Criteria

- [ ] All interactive elements have visible hover/focus/active states
- [ ] Animations feel smooth and intentional (no janky transitions)
- [ ] Clear elevation hierarchy visible across the app
- [ ] Status changes are noticeable without being distracting
- [ ] Professional aesthetic maintained - not playful or over-designed
- [ ] Consistent application across all 10 main screens
- [ ] Red Night theme still functions correctly with new styles
- [ ] No performance degradation from animations
