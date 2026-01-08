# Flat Wizard Redesign

**Date:** 2026-01-07
**Status:** Approved

## Overview

Complete redesign of the Flat Wizard feature to achieve feature parity with NINA's flat wizard while providing superior real-time feedback and a more intuitive user experience.

## Problems with Current Implementation

1. No image preview during flat captures
2. No persistent image view across sub-tabs
3. Poor ADU-based exposure algorithm (bouncing, overshooting)
4. Lack of configurable settings per filter
5. No progress feedback or live updates
6. No learned exposure history

## Layout & Structure

### Split View Design

```
+---------------------------------------------------------------------+
|  [Quick Capture]  [Multi-Filter Batch]  [Sky Flats]    <- Sub-tabs  |
+----------------------------+----------------------------------------+
|                            |                                        |
|   CONTROLS PANEL           |   PREVIEW PANEL                        |
|   (~40% width, scrollable) |   (~60% width)                         |
|                            |                                        |
|   - Mode-specific          |   +--------------------------------+   |
|     settings               |   |                                |   |
|                            |   |     Live Image Preview         |   |
|   - Filter selection       |   |     (auto-stretch, optional    |   |
|     & per-filter config    |   |      histogram overlay)        |   |
|                            |   |                                |   |
|   - Global settings        |   +--------------------------------+   |
|                            |                                        |
|   - Action buttons         |   Stats Bar:                           |
|     (Start/Stop/Test)      |   Filter | Exposure | ADU | Progress   |
|                            |                                        |
|                            |   Live Countdown: 1.7s remaining...    |
|                            |                                        |
|                            |   +--------------------------------+   |
|                            |   |  Toggleable Visualizations     |   |
|                            |   |  (collapsible section)         |   |
|                            |   +--------------------------------+   |
|                            |                                        |
+----------------------------+----------------------------------------+
```

**Key points:**
- Sub-tabs switch controls panel content; preview panel stays constant
- Preview panel shows same image view regardless of which sub-tab is active

## Controls Panel (Per Sub-Tab)

### Quick Capture Tab

- Filter selector dropdown
- Histogram target slider (0-100%, default 50%)
- Tolerance slider (+/-1-25%, default 10%)
- Exposure limits (min/max inputs)
- Frame count input
- [Test Exposure] [Auto-Tune] [Start Capture] buttons

### Multi-Filter Batch Tab

- **Filter checklist** with toggles (from connected wheel)
- [Import from Session] button - pre-selects filters used tonight
- [Load Preset] / [Save Preset] for filter sets
- **Global defaults section:**
  - Histogram target, tolerance, frame count
- **Per-filter overrides** (expandable per filter):
  - Override checkbox -> reveals target, tolerance, exposure limits, frame count
- **Filter order:** Drag-to-reorder or [Auto-Order] button
- [Start Batch] [Stop] buttons

### Sky Flats Tab

Everything from Multi-Filter Batch, plus:

- **Twilight mode:** Dawn / Dusk toggle
- **Sky brightness indicator:** Current ADU/s reading
- **Twilight timing:** Shows optimal window (e.g., "Best window: 17 min from now")
- **Auto-order toggle:** "Order filters for twilight"
  - Dusk (darkening): Most restrictive first (Ha, SII, OIII, Red) -> Luminance last
  - Dawn (brightening): Luminance first -> narrowband last
- **History suggestion:** "Based on last 5 sessions, suggest starting at X sec for L filter" (dismissible)

## Preview Panel & Visualizations

### Preview Panel (Always Visible)

```
+------------------------------------------------------+
|  +------------------------------------------------+  |
|  |                                                |  |
|  |           LIVE IMAGE PREVIEW                   |  |
|  |        (auto-stretch for visibility)           |  |
|  |                                                |  |
|  |   +------------------+  <- Optional histogram  |  |
|  |   |                  |     overlay (toggle)    |  |
|  |   +------------------+                         |  |
|  +------------------------------------------------+  |
|                                                      |
|  +- Stats Bar --------------------------------------+|
|  | Filter: L  |  Exposure: 2.34s  |  ADU: 32,450   ||
|  | Frame: 3/30  |  ########..  52%  |  OK On Target ||
|  +--------------------------------------------------+|
|                                                      |
|  CAPTURING: 1.7s remaining...  [progress bar]        |
|                                                      |
+------------------------------------------------------+
```

### Stats Bar Shows

- Current filter name
- Exposure time used
- Measured ADU (and as % of histogram)
- Frame progress (X of Y)
- Status indicator (On Target, Adjusting, Out of Range)

### Live Countdown

During active exposure, shows seconds remaining with animated progress bar.

### Toggleable Visualizations (Collapsible)

| Visualization | What it shows |
|---------------|---------------|
| ADU Convergence | Line graph of ADU readings per test frame, target band highlighted |
| Exposure History | Bar chart of exposure values tried during tuning |
| Sky Brightness | Real-time ADU/s trend showing twilight curve (Sky Flats only) |
| Filter Progress Cards | Card per filter: status, exposure found, frames done/total |

Each visualization has an eye icon toggle to show/hide.

## Exposure Algorithm

### Flat Panel Mode (Stable Light Source)

```
1. Check history database for this filter + similar conditions
   -> If found: Start at historical exposure (+/-10%)
   -> If not: Start at geometric mean of min/max limits

2. Binary search with damping:
   - Take test frame, measure median ADU from central 50% of image
   - If within tolerance: Done, use this exposure
   - If too low: increase exposure (cap jump at 2x)
   - If too high: decrease exposure (cap reduction at 0.5x)
   - Max 5 iterations, then accept best result

3. Save successful exposure to history database
```

### Sky Flats Mode (Changing Brightness)

```
1. Rate measurement phase:
   - Take 2 quick test frames at fixed exposure (1s apart)
   - Calculate sky brightness change rate (ADU/s/s)
   - Determine if brightening (dawn) or darkening (dusk)

2. Predictive exposure calculation:
   - Start from historical exposure if available
   - Adjust for current sky brightness vs historical
   - Factor in rate of change: predict ADU at capture midpoint

3. Adaptive capture:
   - Take test frame with predicted exposure
   - If within tolerance: Capture frames for this filter
   - If not: Single adjustment using rate-aware calculation
   - Max 3 iterations per filter (speed is critical)

4. Between filters:
   - Re-measure sky brightness rate (conditions change)
   - Adjust predictions for next filter accordingly

5. Save successful exposures + sky conditions to history
```

### Key Algorithm Improvements

- Rate tracking for sky flats (not just current ADU)
- Capped adjustment jumps (prevents wild overshooting)
- Fewer iterations with smarter starting points
- History-informed starting exposures

## Save Path & Data Persistence

### Save Path Requirement

Modal shown when user clicks Start without a save path set:

```
+-------------------------------------------------------------+
|  ! Save Location Required                                   |
|                                                             |
|  Choose where to save your flat frames before starting.     |
|                                                             |
|  +-------------------------------------------------------+  |
|  | C:\Astrophotography\Flats\2024-01-07               [] |  |
|  +-------------------------------------------------------+  |
|                                                             |
|  [x] Create date subfolder automatically                    |
|  [x] Create filter subfolders (L/, R/, G/, B/, etc.)        |
|                                                             |
|  [Browse...]                           [Cancel]  [Continue] |
+-------------------------------------------------------------+
```

- Path persists in app settings (survives restart)
- Optional auto-subfolders by date and/or filter name
- Save path also shown in controls panel with edit button

### History Database

Stored in app database, tracks per session:

- Filter name
- Equipment profile (camera + filter wheel combo)
- Achieved exposure time
- Target histogram % and actual ADU
- Panel brightness (if flat panel)
- Sky conditions (if sky flats): twilight phase, ADU/s rate
- Timestamp

When starting new session, query last 5-10 matching sessions (same equipment profile + filter) to suggest starting exposure.

## Error Handling & Edge Cases

### Exposure Limit Warnings

| Condition | User Feedback |
|-----------|---------------|
| Hit max exposure, still under target | "Max exposure reached (30s) but only at 42% histogram. Consider brighter light source or waiting for darker sky." |
| Hit min exposure, still over target | "Min exposure reached (0.001s) but at 78% histogram. Consider dimmer panel or waiting for brighter sky." |
| ADU wildly inconsistent between frames | "Unstable readings detected. Check for clouds or light leaks." |
| Sky changing too fast | "Sky brightness changing rapidly. Captured what we could - review frames for quality." |

### Recovery Behavior

- If tuning fails for one filter: Log warning, move to next filter, continue batch
- Don't fail entire batch for one problematic filter
- At end, show summary: "Completed 4/5 filters. Ha failed (max exposure reached)."

### Sky Flats Specific

- If optimal window passes: Show warning banner but **continue capturing** (user decides when to stop)
- If clouds detected (high ADU variance): Alert user but continue
- Show countdown to optimal window if started too early

**Critical principle:** Software informs, user decides. Never auto-stop a sequence except for hardware failures.

### Connection Issues

- Camera disconnect mid-capture: Pause, attempt reconnect, resume or abort gracefully
- Filter wheel stuck: Alert user, offer to skip filter or retry

### Cancellation

- User can cancel anytime
- Partial results are kept (frames already captured are saved)
- "Cancelled. Saved 12 L flats, 8 R flats before stopping."

## Settings Summary

### Global Settings (Defaults)

- Histogram target: 50% (0-100%)
- Tolerance: +/-10% (1-25%)
- Exposure min: 0.001s
- Exposure max: 30s
- Frame count: 30

### Per-Filter Overrides

Each filter can optionally override:

- Histogram target %
- Tolerance %
- Exposure min/max limits
- Frame count
- Enabled/disabled toggle

### User-Friendly Abstractions

- Histogram % instead of raw ADU values (50% = ~32,768 ADU for 16-bit)
- Smart defaults with override capability
- Learned suggestions from history (not requirements)

## Implementation Notes

### Files to Modify

- `packages/nightshade_app/lib/screens/flat_wizard/flat_wizard_screen.dart` - Complete rewrite
- `packages/nightshade_core/lib/src/services/flat_wizard_service.dart` - Algorithm improvements
- `packages/nightshade_core/lib/src/database/` - Add flat history table
- `native/nightshade_native/sequencer/src/flat_wizard.rs` - Rate tracking algorithm

### New Components Needed

- `FlatWizardPreviewPanel` - Persistent image preview with stats
- `FilterChecklistWidget` - Filter selection with per-filter config
- `ExposureConvergenceGraph` - ADU convergence visualization
- `SkyBrightnessGraph` - Twilight curve visualization
- `FilterProgressCard` - Per-filter status card
- `SavePathDialog` - Save location picker modal

### Database Schema Addition

```sql
CREATE TABLE flat_history (
  id INTEGER PRIMARY KEY,
  equipment_profile_id INTEGER,
  filter_name TEXT,
  exposure_time REAL,
  histogram_target REAL,
  actual_adu INTEGER,
  panel_brightness INTEGER,
  sky_adu_rate REAL,
  twilight_phase TEXT,
  timestamp INTEGER,
  FOREIGN KEY (equipment_profile_id) REFERENCES equipment_profiles(id)
);
```
