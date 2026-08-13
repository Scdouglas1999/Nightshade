# GUI release pass — Sequencing cluster

Cluster: Sequencer (builder + run dashboard), Scheduler, Planner, Tonight.
Driver: `tools/ui_audit/drive_linux.py`, profile `gui-sequencing`, display `:82`, fresh scratch profile.
Build: release desktop bundle, softpipe. Devices: built-in Simulated Camera / Mount / Focuser / Filter Wheel connected via Equipment → Discovery.

> Harness note: `--profile` must be passed **after** the subcommand (`start --profile X`);
> the subparser default (`main`) silently overrides a leading `--profile`.

---

## Findings

### SEQ-1 — P2 — Properties panel titles every node with its internal Dart class name ("TargetHeader", "TakeExposure")

**Screen:** Sequencer → Builder → Properties (right panel)
**Repro:**
1. Sequencer → Builder. Click `+` on the **Target** palette card to add a target node.
2. Look at the Properties panel header.

**Expected:** the header names the node the way the rest of the UI does — "New Target" / "Target".
**Actual:** the header reads **`TargetHeader`** with the subtitle `TARGET`. Select the exposure node
instead and the header reads **`TakeExposure`** / `INSTRUCTION`, while the canvas chip and the
Name field both say "Take Exposures".

`TargetHeader` is a widget class name, not a product noun; `TakeExposure` is the internal instruction
id. Both are raw code identifiers rendered in the primary heading slot of a paid product's main
authoring surface. It is also inconsistent with the node's own Name field two rows below it.

Evidence: `reports/release-pass/gui/shots/seq-07-props-region.png`, `seq-08-exposure-props.png`.

### SEQ-2 — P2 — Target node has two "name" fields; editing the top one changes nothing on screen but forks the node's identity in the event stream

**Screen:** Sequencer → Builder → Properties, target node selected
**Repro:**
1. Add a Target node, select it.
2. Properties shows **`Name`** (value "Target") near the top and, under "Target Settings",
   **`Target Name`** (value "New Target").
3. Click the top `Name` field, Ctrl+A, type `ZZTOP`, press Tab.
4. Look at the canvas node title, the sequence tree, and the `Target Name` field.

**Expected:** one name per node; editing it renames the target everywhere.
**Actual:** nothing visible changes. The canvas node still reads "New Target", `Target Name` still reads
"New Target", and no surface in the app — canvas, sequence tree, run header, Session Report, History —
ever shows "ZZTOP". Editing the *second* field (`Target Name`) renames the canvas node immediately, so
that is the real one.

The top `Name` field is not inert, though — it is the **execution node name**, and it is only observable in the
log, where the two names now disagree for the same node:

```
INFO Child 0: 'ZZTOP' (id=8ed41382-…)
INFO [PROGRESS_CB] Emitting NodeStarted: id=8ed41382-…, name=ZZTOP
INFO Starting target: M42-TEST (RA: 5.5885h, Dec: -5.3900°)
…
INFO Child 'ZZTOP' completed with status: Cancelled
```

So the first editable control on the panel is labelled with the most generic word possible, has no visible
effect, and quietly forks the node's identity between the UI ("M42-TEST") and the execution/progress event
stream ("ZZTOP"). Either label the two fields distinctly or drop one.

Evidence: `reports/release-pass/gui/shots/seq-07-props-region.png` (Name = ZZTOP while Target Name = New Target).


### SEQ-3 — P1 — Pre-Flight says "Ready with Warnings" for a sequence the engine refuses outright; run dies in <1s with 0 frames

**Screen:** Sequencer → Builder → Start → Pre-Flight Validation
**Setup:** observing site set to a **daytime** longitude (Settings → Location: lat 40, lon −105, machine clock 10:09 local / 14:10 UTC), one Target + one Take Exposures (LIGHT, 4 × 3 s), capture folder configured.
**Repro:**
1. Sequencer → Builder → **Start**.
2. Pre-Flight reports **"Ready with Warnings — 2 warning(s) found"**, and the Simulation card says
   *"Sequence is expected to start at 10:09, before the dark window starts at 23:44."* — a **warning**.
   The **Start Anyway** button is enabled and green.
3. Click **Start Anyway**.

**Expected:** either pre-flight blocks this the same way it blocks a missing capture folder (that one *is* a hard
error), or the executor waits for the dark window.
**Actual:** the run starts and fails **in the same millisecond** with zero frames:

```
14:10:46.803 INFO  Starting sequence execution
14:10:46.803 WARN  Daylight gate: refusing light-frame exposure — Sun altitude 22.1° is above the maximum -12.0°…
14:10:46.803 ERROR Exposure failed: Daylight gate: …
14:10:46.803 INFO  Child 'Take Exposures' completed with status: Failure
```

Pre-flight already computed the dark window (23:44) and the start time (10:09); it has everything it needs to
know the run cannot capture a single light frame. Presenting that as a yellow warning next to a green
"Start Anyway" is the exact failure pre-flight exists to prevent. Evidence:
`reports/release-pass/gui/shots/seq-13-preflight-ok.png`, `seq-14-postrun.png`.

### SEQ-4 — P2 — Post-run "How did this run go?" prompt covers the Session Report it is stacked on

**Screen:** Sequencer, immediately after any run ends
**Repro:** finish or fail any run. Two modals appear at once: the **Session Report** dialog and, centred on top
of it, the **"How did this run go?"** note nudge.
**Expected:** the journal nudge appears after the report is dismissed, or as a non-blocking element inside it.
**Actual:** the nudge sits over the middle of the report, hiding the Mount/operations, Guiding and Targets
sections; you must dismiss the nudge to read the report you were just shown. It also fires after a run that
captured **zero** frames and failed in under a second ("A quick note now is worth a long memory later").
Evidence: `reports/release-pass/gui/shots/seq-14-postrun.png`.

### SEQ-5 — P2 — Run-quality warnings that cost data are log-only: nothing reaches the UI, the Session Report or the alert centre

**Screen:** Sequencer run dashboard / Session Report / notification centre
**Repro:**
1. Connect Simulated Camera + Mount (no guider). Build Target + Take Exposures (LIGHT, 4 × 15 s) and run to
   completion at night.
2. During the run the engine logs two warnings:
   - `WARN Dither requested after frame 3/4 but no guider is configured — skipping dithers for the rest of this burst. Frames will be UNDITHERED (walking noise)…`
   - `WARN Not holding the next 15s exposure for a meridian flip: the target is +0.07h past the meridian but the mount reports hour angle -2.51h … check that the mount is tracking the target.`
3. Open the Session Report, then the bell → notification centre.

**Expected:** at least the undithered-frames warning surfaces where a user will see it.
**Actual:** the run dashboard shows nothing; the Session Report's **Diagnostics** section lists only
*"Cooler Out of Setpoint Band"*; the notification popup says **"Transient Alerts — No active alerts"**. The two
warnings that actually describe degraded data ("frames will be UNDITHERED", "mount may not be tracking the
target") are visible only to someone reading the Rust log.

### SEQ-6 — P2 — A stopped-while-running sequence is reported as "paused-stopped"

**Screen:** Sequencer → Session Report / History
**Repro:**
1. Start a 4 × 15 s run. Click **Pause** (chip reads PAUSED). Click **Resume** — the header returns to
   "Sequence Running" and the log records `Resumed: continuing the instruction`.
2. While it is *running*, click **Stop** (the square button).

**Expected:** "stopped" / "cancelled".
**Actual:** the Session Report title is **"New Sequence - paused-stopped"**, and the History filter chips
expose the same string. The run was not paused when it was stopped — the log is unambiguous
(`14:21:51 Resumed` … `14:22:18 Stopping sequence execution` … `completed with status: Cancelled`).
`paused-stopped` is also a raw state-machine identifier, not product English.

### SEQ-7 — P3 — "Frames accepted 2/2" for a run that was stopped 2 frames into a 4-frame plan

**Screen:** Sequencer → Session Report
**Repro:** stop the 4 × 15 s run after 2 frames (see SEQ-6).
**Expected:** `2/4`, or an explicit "stopped early" qualifier.
**Actual:** **Frames accepted `2/2`**, and the target row reads **"2/2 frames | 30s"**. The denominator is
silently rebased from *planned* to *attempted*, so a run that delivered half its plan reads as 100 % complete.

### SEQ-8 — P2 — Execution History groups today's runs under yesterday's date

**Screen:** Sequencer → History
**Repro:** run any sequence today, open **History**.
**Expected:** the group header matches the runs beneath it (or is explicitly labelled as an observing night).
**Actual:** the header reads **"Monday, Aug 10, 2026 · 2 runs"** while both rows underneath are stamped
**"Aug 11, 2026 10:16"** and **"Aug 11, 2026 10:10"** — and the app's own Dashboard says today is
*Tue, Aug 11*. If this is deliberate noon-rollover "observing night" grouping it is undisclosed; as rendered the
header contradicts every row it contains. Evidence: `reports/release-pass/gui/shots/seq-21-history.png`.

### SEQ-9 — P3 — Notification badge in History rows is drawn on top of the neighbouring icons

**Screen:** Sequencer → History, run rows
**Repro:** open History with at least one run that has notes/decisions; look at the icon cluster left of the
status pill.
**Actual:** a blue circular "2" badge overlaps the icon to its left and clips the book icon to its right — the
badge is positioned over adjacent controls rather than on the corner of its own.
Evidence: `reports/release-pass/gui/shots/seq-22-history-badges.png` (340×120 crop at root +1560+430).

### SEQ-10 — P3 — History status filter chips expose no selected state to accessibility

**Screen:** Sequencer → History
**Repro:** `tree` the screen, click **Failed**, `tree` again.
**Actual:** before and after, every chip is reported identically as `button: Completed` / `button: Failed` / … with
no `[ON]`/checked state, even though the list is now filtered to 1 run. A screen-reader user cannot tell which
filter is active. (The filter itself works.)

### SEQ-11 — P2 — Toolbar "Slew to Target" and "Polar Alignment" stay unlocked during a run, and Slew silently does nothing

**Screen:** Sequencer → Builder toolbar, while a sequence is running
**Repro:**
1. Start a run. `tree` the toolbar: nine buttons are annotated *"(locked while sequence is running)"* —
   New Sequence, Quick-Start Wizard, Calibrate Flat Exposures, Plan Mosaic, Plan Tonight, Open Sequence,
   Import from NINA / SGP, Exposure Triggers, Undo, Redo.
2. **`Slew to Target`** and **`Polar Alignment`** carry no such annotation and no `[DISABLED]` state — they read
   as live, mount-commanding controls in the middle of an imaging run.
3. Click **Slew to Target** while running.

**Expected:** either locked like its neighbours, or it slews and says so.
**Actual:** nothing happens — no slew in the log (`grep -i slew` over the run window is empty), no dialog, no
toast, no state change. An enabled-looking mount command that silently no-ops is the worst of both readings:
it is a dead control, and its sibling **Polar Alignment** advertises the same availability during a run.

---

### SEQ-12 — **P0** — With Unattended Autopilot running, every manually started sequence is silently killed mid-exposure at the next 60-second tick

**Screens:** Plan Tonight → Schedule (Unattended Autopilot) + Sequencer → Builder
**Repro (reproduced twice, with a matching two-trial control):**
1. Settings → Location: lat **−35**, lon **148** (so the site is in darkness), capture folder set.
2. Sequencer → Builder: one Target (`Target Name` = M42-TEST, RA 21.42 h, Dec −35°) + one
   Take Exposures (LIGHT, 4 × 15 s ≈ 68 s).
3. Plan Tonight → **Schedule** → **Run unattended all night** → **Start anyway**. The panel now reads
   *Unattended Autopilot — Running — "No eligible target right now." — "next eval in NNs"*.
4. Go to Sequencer → Builder → **Start** → **Start Anyway**. Header reads **Sequence Running**.
5. Wait.

**Expected:** either the sequence runs (autopilot has no eligible target and is doing nothing), or the app
refuses to start / warns that autopilot owns the rig.
**Actual:** at the autopilot's next evaluation tick the run is **stopped mid-exposure** with no dialog, no
toast, no notification and no reason recorded anywhere a user can see. The log shows only the bare
API-stop line:

| run | started | died | autopilot |
|---|---|---|---|
| run 4 | 14:33:43 | `14:34:17.647 Stopping sequence execution` → `Cancelled` | Running |
| run 5 | 14:35:50 | `14:36:17.657 Stopping sequence execution` → `Cancelled` | Running |
| run 2 (control) | 14:16:32 | completed 4/4 | not started |
| run 6 (control) | 14:39:03 | `14:40:08 completed with status: Success`, 4/4 | **Stopped** |

The kill times are the autopilot's own tick boundary — the Schedule panel's Reasoning box reads
`No eligible candidates at 2026-08-11T14:37:17.512114Z (tick)`, i.e. ticks land on **:17.5** of every
minute, exactly when both runs died. The two control runs, taken with autopilot not running, each ran
straight through two tick boundaries and finished 4/4.

**Why P0:** this is the classic "left it running overnight" case. A user arms autopilot in the evening, then
decides to start a specific sequence by hand; the run is destroyed within 60 s, mid-frame, and every retry
is destroyed the same way, all night. The Session Report then blames the user — it labels the run
**"paused-stopped"** (SEQ-6), indistinguishable from pressing Stop. Nothing in the Sequencer indicates that
autopilot is armed, and nothing in the autopilot panel indicates it is stopping anything: it keeps saying
*"No eligible target right now."*

### SEQ-13 — **P1** — The scheduler evaluates targets at coordinates the user replaced ~25 minutes earlier

**Screens:** Sequencer → Builder (target properties) + Plan Tonight → Schedule (Target queue / Reasoning)
**Repro:**
1. Build a target, set RA **5.5885** h / Dec **−5.39**°, run it once (this is what registers it with the scheduler).
2. In the builder, change the same target's RA to **21.42** h and Dec to **−35**°. The builder immediately
   shows `RA 21h 25m 12s / Dec -35° 00' 00"`, `Alt: 87.9° / Airmass 1.00`, and the Dashboard target card
   agrees (`Altitude 86.5°`).
3. Plan Tonight → **Schedule**. Press **Re-evaluate** as many times as you like.

**Expected:** the queue evaluates the target where it is now — at the zenith, eligible.
**Actual:** the Target queue row reads **`M42-TEST — altitude -19.8° below site minimum 30.0° — Below horizon`**,
and Reasoning repeats it. Re-evaluate refreshes the timestamp and recomputes, but from the **old** RA/Dec:

| clock (UTC) | scheduler says | altitude of *old* coords (5.5885 h / −5.39°) | altitude of *current* coords |
|---|---|---|---|
| 14:28:03 | −19.8° | **−19.80°** | +87° |
| 14:37:17 | −18.0° | **−17.98°** | +87° |

(computed from the app's own LST readout, lat −35). The match is exact to 0.02°, so the scheduler is
demonstrably holding a stale snapshot of the target's coordinates. Combined with SEQ-12 this is what an
unattended night looks like: autopilot refuses a zenith target as "below horizon" all night, and kills any
run you start by hand.

### SEQ-14 — **P1** — Plan Tonight → Schedule reports "No astronomical darkness" for all 7 nights while the same app counts down "Dark 4h 56m left"

**Screen:** Plan Tonight → Schedule, "This Week — Best nights for your project targets"
**Repro:** Settings → Location lat −35 / lon 148, then Plan Tonight → Schedule.
**Expected:** a latitude-35 site in August has astronomical darkness every night, and the app's other
surfaces say so.
**Actual:** all seven cards (Tue 11 … Mon 17) read **"No astronomical darkness"** with a sun icon. At the same
moment:
- the Dashboard status strip reads **"Dark 4h 56m left"**;
- Plan Tonight → Recommendation rates IC1386 **"Peak in dark 76.0°"**, **"9.0h visible"**;
- the sequencer's own daylight gate *passed* and captured light frames (it only refuses above −12° sun).

So the one surface a user consults to pick a night says no night exists, and three other surfaces of the same
feature disagree. Evidence: `reports/release-pass/gui/shots/seq-28-schedule.png`,
`seq-30-dashboard-dark.png`.

Note for whoever fixes this: Plan Tonight → **Projects** is empty ("No projects yet"), and the strip is headed
*"best nights for your **project** targets"* — so this may be an empty-state path rendering as a false
astronomical claim rather than a twilight-maths bug. Either way "No astronomical darkness", seven times, with
a sun icon, is the wrong thing to say.

### SEQ-15 — **P1** — Sequencer toolbar "Slew to Target" fires a real, unconfirmed slew — during a run, and to targets below the horizon — with zero feedback

**Screen:** Sequencer → Builder toolbar (paper-plane icon, right of the bell)
**Repro A (below the horizon, idle):**
1. Select the target node; set RA **12.0** h, Dec −35° (Dashboard shows `Altitude -13.1°`).
2. Click **Slew to Target**.
3. Dashboard → Equipment → Mount now reads **RA 12h 00m 00s / Dec -35° 00' 00" / Alt −13.2°**.

**Repro B (during a run):**
1. Mount parked at RA 12 h; target at RA 21.42 h. Start the sequence; header reads *Sequence Running*.
2. Click **Slew to Target** while a 15 s exposure is in flight.
3. Dashboard → Equipment → Mount now reads **RA 21h 25m 12s / Alt 85.6°** — the mount moved mid-exposure.

**Expected:** a horizon-limit refusal or at least a confirmation for A; the control locked (like its nine toolbar
neighbours, which are all annotated *"locked while sequence is running"*) for B.
**Actual, in both cases:** no confirmation, no toast, no "Slewing…" state — the Mount chip stays **Idle**
throughout — and **not one line in the log** (`grep -ic slew` over the whole session log returns **0**). The only
way to discover the mount moved is to open a different screen and read the Equipment panel. The sequence
kept reporting normal progress across the slew and the frames captured either side were both counted as
accepted.

This also makes the control indistinguishable from a dead button in the moment, which is how it first read
during this audit.

### SEQ-16 — **P1** — A run whose mount is 13° below the horizon passes pre-flight and files its frames under the target's name

**Screen:** Sequencer → Builder → Start
**Repro:**
1. Target at RA 21.42 h / Dec −35° (zenith, `Alt 87.9°`). Slew the mount to RA 12 h (SEQ-15 Repro A), i.e.
   `Alt −13°`. The sequence contains **no** Slew-to-Target / Center instruction.
2. **Start** → pre-flight reports **"Ready with Warnings"** — nothing about the mount not being on target.
3. **Start Anyway**.

**Actual:** the run exposes and saves `M42-TEST_R_0001_002.fits` etc. The engine knows exactly what it is
doing — it logs
`WARN Omitting AIRMASS from FITS header: cannot compute for altitude -13.343…°: Altitude -13.3432° is below the horizon`
— yet nothing surfaces in the UI, the frames are named and tallied against **M42-TEST**, and the Session
Report credits the target with the integration. A user reviewing History sees N accepted frames of M42-TEST
that contain a patch of ground.

**Expected:** pre-flight should flag "target has coordinates but the sequence never slews/centres, and the
mount is currently 100° away", or the run should refuse to file frames under a target it is not pointing at.

### SEQ-17 — P2 — Two different things are called "Target Queue", and the Recommendation empty state asserts targets are queued when the one it links to is empty

**Screens:** Sequencer → Builder → **Queue** tab, and Plan Tonight → Recommendation / Schedule
**Repro:**
1. Sequencer → Builder → palette **Queue** tab: **"Target Queue — 0 — Your target queue is empty."**
2. Plan Tonight → Recommendation: *"AUTOPILOT STANDING BY / **Nothing eligible right now** / **Targets are
   queued**, but none pass the scheduler right now…"* with an **Open Target Queue** button.
3. Plan Tonight → Schedule: a *different* **"Target queue"** table containing **M42-TEST**.

**Actual:** the builder's Queue tab and the scheduler's Target queue are separate lists with the same name and
different contents, and the Recommendation copy states a premise ("Targets are queued") that is false for the
queue the reader is most likely looking at. The builder's Queue empty state also directs the user to
surfaces that do not exist under those names: *"Add targets from the planetarium or the **Tonight tab**"* —
there is no Tonight tab and no Planetarium entry in the nav (it is Plan Tonight → Planetarium).

### SEQ-18 — P2 — After a run that captured 4 of 4 frames, the exposure node reports "0 / 4 frames" above thumbnails of those 4 frames

**Screen:** Sequencer → Builder, immediately after a completed run
**Repro:** run a 4 × 15 s Take Exposures node to completion (Session Report: *Frames accepted 4/4*), close the
report, look at the exposure node on the canvas.
**Actual:** the node's progress card reads **"Exposure: No Filter — 0 / 4 frames"** with all four progress boxes
empty, directly above a strip of **four captured thumbnails** labelled `R`. After a run that was *stopped* at
2 frames the same card correctly reads "2 / 4 frames", so the reset is specific to the success path.
Evidence: `reports/release-pass/gui/shots/seq-23-canvas2.png` (0/4 + 4 thumbnails) vs
`seq-25-idle-after.png` (2/4 after a stop).

### SEQ-19 — P2 — The builder says "No Filter" / "No filters in profile" while every frame is captured, named and reported as filter "R"

**Screen:** Sequencer → Builder (exposure node + Properties) vs Session Report / capture folder
**Repro:** connect the Simulated Filter Wheel, add a Take Exposures node, run it.
**Actual:** Properties → **Filter** is empty with the hint **"No filters in profile"**; the canvas node header reads
**"Exposure: No Filter"**. But the run telemetry strip reads **"Filter: R"**, every file is written as
`M42-TEST_**R**_0001.fits`, the thumbnails are labelled `R`, and the Session Report's per-filter table has one
row: **R**. The authoring surface denies a filter the data-writing path uses for the file names and the
statistics.

### SEQ-20 — P3 — Durations under a minute render as "0m"

**Screens:** Sequencer → Builder (target card), run dashboard
**Repro:** set Take Exposures to 4 × 3 s.
**Actual:** the target card reads **"4 planned exposures • 0m"** while the sequence estimate right beside it
reads **"~20s"**. During a run the elapsed readout shows **"0m / 1m"** for the first minute. Sub-minute values
should render in seconds, as the estimate already does.

### SEQ-21 — P3 — "1 error(s)" / "2 warning(s)" pluralisation in Pre-Flight

**Screen:** Sequencer → Builder → Start → Pre-Flight Validation
**Actual:** the summary line reads **"Please fix 1 error(s) before starting"** and **"2 warning(s) found"`.
Evidence: `reports/release-pass/gui/shots/seq-09-preflight.png`, `seq-13-preflight-ok.png`.

### SEQ-22 — P3 — Raw UTC ISO-8601 timestamps with microseconds in the scheduler Reasoning box

**Screen:** Plan Tonight → Schedule → Reasoning
**Actual:** **"No eligible candidates at 2026-08-11T14:37:17.512114Z (tick)"** — a machine timestamp in UTC with
6 decimal places, and a bare state token `(tick)` / `(preview)` / `(engine start)`, on a screen where every other
time is rendered as local `10:37:17`.

### SEQ-23 — P3 — Two incompatible "Score" scales inside Plan Tonight

**Screen:** Plan Tonight → Recommendation vs → Schedule
**Actual:** Recommendation scores IC1386 **98**; the Schedule tab's Target queue column headed **SCORE** shows
**2.121** for M42-TEST. Neither is labelled with its range, and the same word means two different things one tab
apart.

### SEQ-24 — P3 — The "Unattended Autopilot" panel tells you to go to Plan Tonight; it is inside Plan Tonight

**Screen:** Plan Tonight → Schedule → Unattended Autopilot
**Actual:** *"Runs hands-off and re-picks the best target all night as the sky changes. For a plan you can see
and edit before it runs, **use Plan Tonight instead**."* — the panel is a tab of Plan Tonight.

### SEQ-25 — P3 — The unattended-start confirmation is an off-design alert with an unactionable reason

**Screen:** Plan Tonight → Schedule → Run unattended all night
**Actual:** a plain grey box with no icon, no severity colour and default-styled text buttons — visibly not the
app's dialog (compare Pre-Flight Validation two screens away, which has an icon, a coloured status header and
styled actions). Its first bullet is **"Assigned accessories: One or more configured accessories are
unavailable."** — it never says which, on a screen where the user is about to leave the rig alone all night.
Evidence: `reports/release-pass/gui/shots/seq-29-unattended-confirm.png`.

### SEQ-26 — P3 — Node count disagrees between the Sequence Library and the builder header

**Screen:** Sequencer → Sequences vs Sequencer → Builder
**Actual:** the Sequence Library card for the saved sequence reads **"3 nodes / 1 target / 1 capture step"**; the
builder header for the same sequence reads **"1 target · 2 nodes"**. One counts the implicit root, the other does
not, and neither says so.

### SEQ-27 — P3 — A node's last-run error persists on the card with no timestamp after the sequence and site have changed

**Screen:** Sequencer → Builder, target card
**Repro:** fail a run with the daylight gate, then change Settings → Location to a night-side site and retarget
the node.
**Actual:** the target card still shows **"Error: Exposure: Daylight gate: refusing light-frame exposure — Sun
altitude 22.1° is above the maximum -12.0°…"** while the same card's altitude chart has already recomputed for
the new site (Transit alt 90.0°) and the sun there is ~70° below the horizon. The banner carries no "from the
run at 10:10" qualifier, so it reads as the current state of the node.

### SEQ-28 — P4 — Stopping a running sequence takes one click with no confirmation

**Screen:** Sequencer run toolbar
**Actual:** the square Stop button immediately aborts the in-flight exposure and terminates the run — no
confirm, no undo — in an app that *does* confirm closing the window during capture (Settings → General →
"Confirm before closing").

---

## What worked well (so the fix pass does not break it)

- **Pre-flight hard errors are correct and well written.** "Image Output Path Not Configured — No capture folder
  is set, so frames would be captured and then discarded" blocks Start outright, with a link to the right
  Settings page. The Dark Library check names the exact missing combination
  (`gain=100, offset=50, temp=-10.0C, duration=3s, binning=1x1`) and offers "Capture missing darks".
- **Session Report arithmetic is honest.** Cross-checked against the files on disk and the plan: 4 frames × 15 s
  → `Integration 1m 0s`, `Wall clock 1m 5s`, `Effective imaging 92.3%`, four `M42-TEST_R_000n.fits` on disk.
  The stopped run reported 30 s for 2 frames. No frame-count inflation anywhere.
- **Pause genuinely pauses.** It lets the in-flight exposure finish, saves it, then holds
  (`Paused: holding before the next unit of work in this instruction`); 25 s of pause produced zero extra
  frames on disk. Resume continues the same instruction.
- **Runs are repeatable within one app launch** — six runs in one session, no terminal-state wedging.
- **The toolbar's "locked while sequence is running" annotations are exposed to accessibility**, which is how
  SEQ-11/SEQ-15 were found at all.
- **The "Mount is Parked" pre-start dialog** (countdown + "Unpark Now" / "Cancel Sequence") is a good pattern.
- **Templates** is a genuinely strong screen: five bundled starters with honest, specific descriptions and
  realistic time estimates, difficulty chips, and a "loading one replaces your current sequence" warning.

## Coverage

**Screens driven:**

| Screen | What was exercised |
|---|---|
| Sequencer → Builder | node palette (Target / Imaging / Science / Guiding / Mount groups), add via `+`, Target properties (name, RA/Dec, altitude chart, min/max altitude, start/end conditions, integration budget), Take Exposures properties (duration, count, frame type, filter, dither, adaptive exposure, timing), collapse/expand, sequence header badges, issues dialog, toolbar (13 buttons incl. Slew to Target, Polar Alignment, Undo/Redo lock states) |
| Sequencer → Builder → Pre-Flight Validation | error path (no capture folder), warning path (dark window, dark library, disk space), Re-check, Cancel, Start Anyway |
| Sequencer run dashboard | live progress (`n/4 done`, `%`, elapsed/total, ETA "done ~hh:mm:ss"), per-node frame strip, telemetry row (Cam / Focus / Filter / Mount), thumbnails, Pause, Resume, Stop, properties lock-out |
| Sequencer → Session Report | completed, failed, stopped variants; stats block, per-filter target table, Diagnostics, Errors, Journal/Notes, "How did this run go?" nudge |
| Sequencer → History | run list, date grouping, status filter chips, row badges |
| Sequencer → Templates | 5 starters, difficulty filters, Reusable Snippets banner, Save as Template / Quick-Start Wizard affordances |
| Sequencer → Sequences | Sequence Library card (node/target/step counts, run count, last run) |
| Sequencer → Queue tab | empty state |
| Plan Tonight → Recommendation | autopilot standing-by banner, filter chips, Night Outlook card (score, altitude chart, chips, Send to Framing / Open Planetarium), Transient Alerts |
| Plan Tonight → Schedule | This Week strip, Unattended Autopilot (Run unattended all night → confirm dialog → Running → Pause/Stop/Re-evaluate, tick cadence, Reasoning box), Target queue table, Clear all |
| Plan Tonight → Projects | empty state + New Project CTA |
| Plan Tonight → Framing | equipment-missing state, survey/grid/labels toggles, rotation slider, target search |
| Plan Tonight → Discover | Your Sky / Constellation / Collaborate tabs, Your Sky empty state |
| Dashboard (Tonight briefing) | run state card, target card (altitude / to-meridian / to-set), recent frames strip, Equipment panel (camera/mount/focuser/filter wheel), Safety panel, Recent Events, dark-time countdown, alert banner |
| Supporting (to reach the above) | onboarding skip, Equipment discovery + connect of 4 simulators, Settings → Location, Settings → Files & Storage, notification centre |

**Not reached / blocked:**

| Screen | Why |
|---|---|
| Plan Tonight → Planetarium | Deliberately left to the planetarium cluster; opening it from here was out of scope for the sequencing pass and it is a heavy render surface. |
| Sequencer → Quick-Start Wizard, Plan Mosaic, Calibrate Flat Exposures, Import from NINA/SGP, Export Sequence File, Polar Alignment (toolbar) | Each is a separate multi-step wizard; the context budget went to the run dashboard and scheduler instead. Their toolbar entry points were verified present and correctly lock/unlock (SEQ-11). |
| Sequencer → Builder → Snippets tab | Only the tab header was read (19 snippets advertised); the snippet list itself was not exercised. |
| Multi-target / multi-instruction sequences (Change Filter, Dither, Smart Exposure, Live Stacking, Science Photometry, Start/Stop Guiding, Center Target, Meridian Flip) | No guider is available in the simulator set, and each additional instruction type multiplies the run matrix. All were confirmed present and draggable in the palette but were not executed. |
| Guided run behaviour (dither, settle, RMS panels) | Simulated Guide Camera / PHD2 not connected — the Guiding sections of the run dashboard and Session Report only ever showed "No guide data recorded for this session." |
| Autofocus / meridian-flip triggers firing during a run | Would need a >25-frame run or a target at the meridian; not reached in the time available. |
