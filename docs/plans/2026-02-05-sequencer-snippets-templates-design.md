# Sequencer Snippets & Templates Enhancement Design

## Overview

Expand the built-in snippets from 5 to 19 and templates from 5 to 15, covering all major imaging workflows with tiered complexity for beginners through advanced users.

**Goals:**
- Help beginners get started quickly with "just works" templates
- Speed up advanced users with sophisticated adaptive workflows
- Support deep sky broadband, narrowband, planetary, solar, and lunar imaging

---

## Files to Modify

| File | Purpose |
|------|---------|
| `packages/nightshade_core/lib/src/models/sequence/template_snippet.dart` | Add new snippets to `BuiltInSnippets.all` |
| `packages/nightshade_app/lib/screens/sequencer/tabs/templates_tab.dart` | Add new templates to `_builtInTemplates` |

---

## Snippets (19 Total)

### Autofocus Category (4)

| ID | Name | Description | Node Structure |
|----|------|-------------|----------------|
| `builtin-autofocus-routine` | Autofocus Routine | (existing) Basic vCurve autofocus | `Autofocus(vCurve, step=100, stepsOut=7, exposure=3s)` |
| `builtin-hfr-triggered-af` | HFR-Triggered AF | Re-focus when stars bloat | `Conditional(hfrBelow=3.0) → Autofocus` |
| `builtin-temp-drift-af` | Temperature-Drift AF | Re-focus on temperature change | `Conditional(tempChange>2°C) → Autofocus` |
| `builtin-per-filter-af` | Per-Filter AF Offsets | Autofocus on L, apply offsets | `InstructionSet(AF on L, R-offset, G-offset, B-offset)` |

### Dithering Category (4)

| ID | Name | Description | Node Structure |
|----|------|-------------|----------------|
| `builtin-dither-after-each` | Dither After Each | (existing) Standard dither | `Dither(5px, settle=30s, threshold=1.5px)` |
| `builtin-aggressive-dither` | Aggressive Dither | Large dither for walking noise | `Dither(10px, settle=45s, threshold=1.0px)` |
| `builtin-gentle-dither` | Gentle Dither | Small dither for fast settle | `Dither(3px, settle=20s, threshold=2.0px)` |
| `builtin-dither-every-n` | Dither Every N | Dither after every 3 exposures | `Loop(count=3) → Exposure + Dither` |

### Filter Sequence Category (7)

| ID | Name | Description | Node Structure |
|----|------|-------------|----------------|
| `builtin-lrgb-filter-cycle` | LRGB Filter Cycle | (modified) Classic broadband | `Loop(whileDark) → L:120s, R:120s, G:120s, B:120s` |
| `builtin-ha-oiii-bicolor` | Ha-OIII Bicolor | Two-filter narrowband | `Loop(whileDark) → Ha:180s, OIII:180s` |
| `builtin-sho-hubble` | SHO Hubble Palette | Full narrowband | `Loop(whileDark) → SII:180s, Ha:180s, OIII:180s` |
| `builtin-lrgb-ha-enhanced` | LRGB + Ha Enhanced | Broadband with Ha accent | `Loop(whileDark) → L:120s, R:120s, G:120s, B:120s, Ha:180s` |
| `builtin-osc-no-filter` | OSC No Filter | One-shot color cameras | `Loop(whileDark) → Exposure:120s` |
| `builtin-dual-narrowband` | Dual Narrowband | Ha + OIII rotation | `Loop(whileDark) → Ha:180s, OIII:180s` |
| `builtin-rgb-only` | RGB Only | No luminance channel | `Loop(whileDark) → R:120s, G:120s, B:120s` |

### Safety/Calibration Category (4)

| ID | Name | Description | Node Structure |
|----|------|-------------|----------------|
| `builtin-safety-check` | Safety Check | (existing) Weather + guiding | `Conditional(weatherSafe) → Conditional(guidingRms<2.0)` |
| `builtin-meridian-flip-handler` | Meridian Flip Handler | (existing) Full flip sequence | `StopGuiding → MeridianFlip → Center → StartGuiding` |
| `builtin-weather-pause` | Weather Pause | Pause & retry on bad weather | `Conditional(!weatherSafe) → Park → Wait(5min) → Loop` |
| `builtin-guiding-recovery` | Guiding Recovery | Auto-restart guiding | `Recovery(retries=3) → StopGuiding → StartGuiding → Dither` |
| `builtin-hfr-degradation` | HFR Degradation Check | Re-focus when stars bloat | `Conditional(hfrBelow=4.0) → Continue ELSE Autofocus` |
| `builtin-altitude-guard` | Altitude Guard | Stop below altitude | `Conditional(altitudeAbove=30°) → Continue ELSE Skip` |
| `builtin-periodic-plate-solve` | Periodic Plate Solve | Re-center every 10 frames | `Loop(count=10) → Exposure THEN CenterTarget` |
| `builtin-pre-session-warmup` | Pre-Session Warmup | Standard startup | `Unpark → CoolCamera → StartGuiding → Autofocus` |

---

## Templates (15 Total)

### Tier 1: Beginner (Static, Simple)

#### First Light
Absolute beginner, single target, fixed count.

```
TargetHeader
└── InstructionSet
    ├── CoolCamera (temp: -10°C)
    ├── Slew (to target)
    ├── Loop (count: 20)
    │   └── TakeExposure (30s, no filter)
    ├── WarmCamera
    └── Park
```

#### One-Shot Color (OSC)
Color cameras with no filter wheel.

```
TargetHeader
└── InstructionSet
    ├── CoolCamera (temp: -10°C)
    ├── Slew (to target)
    ├── CenterTarget (plate solve)
    ├── Autofocus (vCurve)
    ├── StartGuiding
    ├── Loop (whileDark)
    │   ├── TakeExposure (120s)
    │   └── Dither (5px)
    ├── StopGuiding
    ├── WarmCamera
    └── Park
```

#### Quick Test
Equipment verification, short run.

```
TargetHeader
└── InstructionSet
    ├── CoolCamera (temp: -10°C)
    ├── Autofocus (vCurve)
    ├── Loop (count: 3)
    │   └── TakeExposure (5s)
    └── WarmCamera
```

#### Planetary Capture
High frame rate lucky imaging.

```
TargetHeader
└── InstructionSet
    ├── Slew (to target)
    ├── CenterTarget (plate solve)
    ├── Loop (count: 10)
    │   └── TakeExposure (30s, video mode, high gain)
    └── Park
```

### Tier 2: Intermediate (Condition-aware)

#### LRGB Standard
Classic broadband with meridian flip handler, periodic AF, dithering.

```
TargetHeader
└── InstructionSet
    ├── CoolCamera (temp: -10°C)
    ├── Slew (to target)
    ├── CenterTarget (plate solve)
    ├── Autofocus (vCurve)
    ├── StartGuiding
    ├── Loop (whileDark)
    │   ├── Conditional (meridianFlipNeeded)
    │   │   └── InstructionSet [Meridian Flip Handler]
    │   │       ├── StopGuiding
    │   │       ├── MeridianFlip (5min past, autoCenter)
    │   │       ├── CenterTarget
    │   │       ├── StartGuiding
    │   │       └── Autofocus
    │   ├── Loop (count: 3)
    │   │   ├── FilterChange (L) → TakeExposure (120s)
    │   │   ├── FilterChange (R) → TakeExposure (120s)
    │   │   ├── FilterChange (G) → TakeExposure (120s)
    │   │   └── FilterChange (B) → TakeExposure (120s)
    │   ├── Dither (5px)
    │   └── Conditional (every 30 min)
    │       └── Autofocus
    ├── StopGuiding
    ├── WarmCamera
    └── Park
```

#### Ha-OIII Bicolor
Two-filter narrowband with guiding stability check.

```
TargetHeader
└── InstructionSet
    ├── CoolCamera (temp: -10°C)
    ├── Slew (to target)
    ├── CenterTarget (plate solve)
    ├── Autofocus (vCurve)
    ├── StartGuiding
    ├── Conditional (guidingRmsBelow: 2.0)
    │   └── WaitTime (30s)
    ├── Loop (whileDark)
    │   ├── FilterChange (Ha) → TakeExposure (180s)
    │   ├── Dither (5px)
    │   ├── FilterChange (OIII) → TakeExposure (180s)
    │   ├── Dither (5px)
    │   └── Conditional (every 45 min)
    │       └── Autofocus
    ├── StopGuiding
    ├── WarmCamera
    └── Park
```

#### SHO Hubble Palette
Full narrowband with weather safety wrapper.

```
TargetHeader
└── Conditional (weatherSafe)
    └── InstructionSet
        ├── CoolCamera (temp: -10°C)
        ├── Slew (to target)
        ├── CenterTarget (plate solve)
        ├── Autofocus (vCurve)
        ├── StartGuiding
        ├── Loop (whileDark)
        │   ├── FilterChange (SII) → TakeExposure (180s) → Dither
        │   ├── FilterChange (Ha) → TakeExposure (180s) → Dither
        │   ├── FilterChange (OIII) → TakeExposure (180s) → Dither
        │   └── Conditional (every 45 min)
        │       └── Autofocus
        ├── StopGuiding
        ├── WarmCamera
        └── Park
```

#### LRGB + Ha Enhanced
Broadband with hydrogen-alpha accent layer.

```
TargetHeader
└── InstructionSet
    ├── CoolCamera (temp: -10°C)
    ├── Slew (to target)
    ├── CenterTarget (plate solve)
    ├── Autofocus (vCurve)
    ├── StartGuiding
    ├── Loop (whileDark)
    │   ├── FilterChange (L) → TakeExposure (120s)
    │   ├── FilterChange (R) → TakeExposure (120s)
    │   ├── FilterChange (G) → TakeExposure (120s)
    │   ├── FilterChange (B) → TakeExposure (120s)
    │   ├── FilterChange (Ha) → TakeExposure (180s)
    │   ├── Dither (5px)
    │   └── Conditional (every 30 min)
    │       └── Autofocus
    ├── StopGuiding
    ├── WarmCamera
    └── Park
```

#### Multi-Target Night
Multiple targets with altitude-based switching.

```
Sequence
├── TargetHeader [Target 1]
│   └── InstructionSet
│       ├── CoolCamera
│       ├── Slew → CenterTarget → Autofocus → StartGuiding
│       ├── Loop (untilAltitude: 30°)
│       │   ├── LRGB cycle (120s each)
│       │   └── Dither
│       └── StopGuiding
│
├── TargetHeader [Target 2]
│   └── InstructionSet
│       ├── Slew → CenterTarget → Autofocus → StartGuiding
│       ├── Loop (untilAltitude: 30°)
│       │   ├── LRGB cycle
│       │   └── Dither
│       └── StopGuiding
│
└── InstructionSet [Shutdown]
    ├── WarmCamera
    └── Park
```

### Tier 3: Advanced (Fully Adaptive)

#### Unattended All-Night
Dusk-to-dawn automation with weather pause, HFR recovery, meridian flip.

```
TargetHeader
└── InstructionSet
    ├── CoolCamera (temp: -10°C)
    ├── Slew (to target)
    ├── CenterTarget (plate solve)
    ├── Autofocus (vCurve)
    ├── StartGuiding
    ├── Loop (whileDark)
    │   ├── Conditional (NOT weatherSafe)
    │   │   └── InstructionSet [Weather Pause]
    │   │       ├── StopGuiding
    │   │       ├── Park
    │   │       ├── WaitTime (5min)
    │   │       └── Loop (until weatherSafe)
    │   │           └── WaitTime (5min)
    │   │       ├── Unpark
    │   │       ├── Slew → CenterTarget
    │   │       ├── StartGuiding
    │   │       └── Autofocus
    │   ├── Conditional (meridianFlipNeeded)
    │   │   └── [Meridian Flip Handler]
    │   ├── Conditional (hfrAbove: 4.0)
    │   │   └── Autofocus
    │   ├── Recovery (retries: 3, onFailure: Autofocus)
    │   │   └── InstructionSet
    │   │       ├── LRGB cycle (120s each)
    │   │       └── Dither
    │   └── Conditional (every 30 min)
    │       └── Autofocus
    ├── StopGuiding
    ├── WarmCamera
    └── Park
```

#### Mosaic Multi-Panel
Large field mosaic with per-panel centering and adaptive AF.

```
Sequence
├── InstructionSet [Setup]
│   ├── CoolCamera
│   └── Autofocus
│
├── Loop (for each panel)
│   └── TargetHeader [Panel N]
│       └── InstructionSet
│           ├── Slew (to panel center)
│           ├── CenterTarget (plate solve, tolerance: 5 arcsec)
│           ├── StartGuiding
│           ├── Loop (count: 10)
│           │   ├── LRGB cycle (120s each)
│           │   └── Dither
│           ├── StopGuiding
│           └── Conditional (every 2 panels)
│               └── Autofocus
│
└── InstructionSet [Shutdown]
    ├── WarmCamera
    └── Park
```

#### Comet/Asteroid Tracking
Moving target with periodic re-centering, short exposures.

```
TargetHeader
└── InstructionSet
    ├── CoolCamera (temp: -10°C)
    ├── Slew (to target)
    ├── CenterTarget (plate solve)
    ├── StartGuiding (comet tracking mode)
    ├── Loop (whileDark)
    │   ├── Loop (count: 10)
    │   │   └── TakeExposure (60s)  [No dither for tracking]
    │   ├── CenterTarget (re-acquire)
    │   └── Conditional (every 30 min)
    │       └── Autofocus
    ├── StopGuiding
    ├── WarmCamera
    └── Park
```

#### Solar Ha
Daytime solar imaging with temperature monitoring and frequent AF.

```
TargetHeader
└── InstructionSet
    ├── FilterChange (Ha solar filter)
    ├── Loop (count: 100)
    │   ├── TakeExposure (0.01s, high gain)
    │   ├── Conditional (every 10 exposures)
    │   │   └── Autofocus
    │   └── Conditional (tempChange > 1°C)
    │       └── Autofocus
    └── Notification ("Solar session complete")
```

#### Lunar Surface
High-resolution moon mosaic with lucky imaging bursts.

```
Sequence
├── Loop (for each panel)
│   └── TargetHeader [Panel N]
│       └── InstructionSet
│           ├── Slew (to panel center)
│           ├── CenterTarget
│           ├── Loop (count: 5)
│           │   └── TakeExposure (0.05s, video burst, 1000 frames)
│           └── Conditional (every 3 panels)
│               └── Autofocus
│
└── Notification ("Lunar mosaic complete")
```

#### Remote Observatory
Full remote operation with comprehensive safety monitors.

```
TargetHeader
└── Parallel
    ├── InstructionSet [Main Imaging Loop]
    │   ├── OpenDome
    │   ├── CoolCamera (temp: -10°C)
    │   ├── Unpark
    │   ├── Slew → CenterTarget → Autofocus → StartGuiding
    │   ├── Loop (whileDark)
    │   │   ├── LRGB cycle with dither
    │   │   └── Conditional (every 30 min)
    │   │       └── Autofocus
    │   ├── StopGuiding
    │   ├── Park
    │   ├── WarmCamera
    │   └── CloseDome
    │
    └── InstructionSet [Safety Monitor - runs parallel]
        └── Loop (forever)
            ├── Conditional (NOT weatherSafe OR NOT safetyMonitorSafe)
            │   └── InstructionSet [Emergency Shutdown]
            │       ├── StopGuiding
            │       ├── Park
            │       ├── CloseDome
            │       └── Notification ("Emergency park - unsafe conditions")
            └── WaitTime (60s)
```

---

## Implementation Notes

### Snippet Implementation Pattern

Add to `BuiltInSnippets` class in `template_snippet.dart`:

```dart
static final hfrTriggeredAf = TemplateSnippet(
  id: 'builtin-hfr-triggered-af',
  name: 'HFR-Triggered AF',
  description: 'Re-focus automatically when star HFR exceeds threshold',
  category: SnippetCategory.autofocus,
  iconName: 'focus',
  isBuiltIn: true,
  createdAt: DateTime(2026, 2, 5),
  nodeData: [
    {
      'nodeType': 'conditional',
      'name': 'HFR Check',
      'conditionType': 'hfrBelow',
      'hfrThreshold': 3.0,
      'children': [
        {
          'nodeType': 'autofocus',
          'name': 'Autofocus',
          'method': 'vCurve',
          'stepSize': 100,
          'stepsOut': 7,
          'exposureDuration': 3.0,
        }
      ],
    }
  ],
);
```

### Template Implementation Pattern

Add to `_builtInTemplates` in `templates_tab.dart` following existing pattern:

```dart
Sequence(
  id: 0,
  name: 'First Light',
  description: 'Simple sequence for absolute beginners',
  isTemplate: true,
  createdAt: DateTime(2026, 2, 5),
  rootNodeId: 'target-1',
  nodes: {
    'target-1': TargetHeaderNode(...),
    'set-1': InstructionSetNode(...),
    // ... all nodes
  },
)
```

### Default Values Reference

| Parameter | Value |
|-----------|-------|
| LRGB exposure | 120s |
| Narrowband exposure | 180s |
| Dither pixels | 5px |
| Dither settle | 30s |
| Guiding RMS threshold | 2.0 arcsec |
| HFR threshold | 3.0-4.0 |
| Camera temp | -10°C |
| Min altitude | 30° |
| AF interval | 30-45 min |

---

## Verification

After implementation:

1. Run `melos run analyze` - no errors
2. Run `melos run test` - all tests pass
3. Manual verification:
   - All 19 snippets appear in snippet palette
   - All 15 templates appear in templates tab
   - Snippets insert correctly into sequences
   - Templates load and execute properly
