# Release Tightening Pass — 2026-08-11

## CLOSEOUT (DRAFT — takes effect when Wave G verifies the F-fix batch)

Campaign ledger, 2026-08-11 → 2026-08-14, all on `audit/end-to-end-campaign`:
- **Wave A** map (16 mappers) → adjudicated work orders per subsystem.
- **Wave B** adversarial GUI (8 clusters driving the real bundle) → 181 findings.
- **Fix waves**: C1 (15 batches), B-fix (80 findings incl. 2 P0 + 18 P1), C2 (~100 call
  sites consolidated, parity-pinned), stage-2 (17), C3 (118 files split), D-fix (61+3),
  E-fix (55), F-fix (32) — every wave sealed by the full gate set before commit.
- **Verification**: Waves D, E, F (live re-drives + refuters) + G (closing spot-check).
  Between them: 160 fixes verified live, 16 plausible-but-wrong fix claims refuted before
  they could ship as phantom fixes, and the two-implementations trap caught four times.
- **Signature catches**: autopilot silently killing manual runs (and later: never
  re-dispatching after its own run failed); the meridian flip's solve exposure stomping an
  in-flight light frame; the stacked-preview linear stretch rendering every sky black;
  pairing stores surviving reinstalls; the frame-count provider overwritten 43µs after
  every completed burst; operator stops pushed as critical failures.
- **Remaining, by design**: the owner-decision lists (Wave A's + the four Wave F product
  calls), the parked platform item (title-bar AT-SPI export needs GTK embedder work), the
  Windows-only file, and the documented P3/P4 residue in the wave verdict JSONs.
- On-sky validation on the live rig remains owed, as always, and is the natural next
  campaign (tasks #32/#34).

### Simulator-fidelity gap exposed by Wave G (blocks the flip live-oracle)

The simulator cannot be made to produce a meridian flip: the flip gate keys on the MOUNT's
reported hour angle, and the sim mount's HA never crosses in a way the trigger accepts —
four configured attempts (tracking the target 19-24 min past the meridian,
enable_meridian_flip=true, minutes_past=5.0) captured 8/8 frames with zero flips and
"Meridian flips 0" in the report. The new honest pre-frame warning ("the flip trigger
cannot fire") is itself a win, but the camera-claim mechanism and the retry-ladder ETA fix
can only be truly exercised on a rig (or after the sim mount models pier side + HA
progression). Belongs on the simulator-fidelity backlog next to the July items.

### What remains is user-gated (recorded 2026-08-14, mid-final-gate)

Everything still open outside the G-check pipeline needs the owner:
1. **Live-rig session** (deploy to sean-laptop per the rig-deploy recipe, owner present):
   validates the stop-pipeline family on hardware (L7 note in the live-rig findings), L2
   camera model names, L4 phantom-device fix, L5 triple mount, L36/ProgID — none of these
   can or should be driven unattended against the owner's physical equipment.
2. **The four Wave F product calls** + Wave A owner-decision list + sequenceStopped push
   copy + IMG-9 loop-count label + queue-membership semantics.
3. **Windows build verification** (ascom_wrapper/camera.rs split skipped; goldens are
   Windows-baselined) — needs the Windows host.

Ground-truth document for the release-level quality campaign. All findings land here
(or in files linked from here) before any fix wave launches. Nothing is fixed from memory.

## Mandate (owner, 2026-08-11)

Go from "works pretty well, solidly built" to commercial grade:

- No excessively long files; efficiently written code; clever simplification WITHOUT behavior change.
- No duplicate functionality living in different files.
- Optimize app performance, reliability, rendering.
- Full adversarial review of the UI by agents actually driving the app (not code-reading).
- Fable orchestrates and adjudicates; Opus 5 subagents implement.

## Standing rules in force

- UI/behavior bugs are reproduced in the running app before being fixed (no fixes from code-reads).
- Refactors are behavior-preserving; the full gate set is the proof:
  `melos run test`, full `cargo test`, analyzer_rollup, placeholder_audit, behavioral_audit,
  `dart format` + `cargo fmt`.
- No Claude commit trailers.
- Generated files (`*.g.dart`, `*.freezed.dart`, `frb_generated.*`) are exempt from length limits.
- Waves repeat until a wave finds nothing new.
- Never `git stash` while concurrent agents hold worktrees.

## Baseline (commit b07d91c9d, tree clean)

- Branch: `audit/end-to-end-campaign`. All five gates verified green at this commit
  (cargo: 2185 passed / 0 failed; melos: every package SUCCESS).
- Dart (packages/ + apps/, non-generated): ~563k + 472k + 108k lines total across the three roots.
- **112 non-generated, non-test Dart lib files exceed 1,000 lines.**
- **55 non-generated Rust files exceed 1,500 lines.** Giants:
  `sequencer/src/instructions.rs` 11,732; `sequencer/src/executor/mod.rs` 11,172;
  `bridge/src/api/imaging.rs` 7,406; `sequencer/src/triggers.rs` 4,519.
- Largest hand-written Dart: `headless_api/handlers/sequencer_handlers.dart` 2,309;
  `providers/sequence/sequence_executor.dart` 2,288; `session_review_controller.dart` 1,940.
- Release bundle rebuilt 2026-08-11 (fresh flutter build + fresh .so) for the GUI wave.

## Wave plan

- **Wave A — Map** (14 read-only Opus mappers, one per subsystem + one cross-cutting
  duplication hunter). Output: `reports/release-pass/map/*.md` + structured summaries.
  Targets: oversized files with split plans, duplicated functionality, dead code,
  perf risks, reliability risks.
- **Wave B — Adversarial GUI review**: agents drive the freshly built release bundle through
  `tools/ui_audit/drive_linux.py` (Xvfb, softpipe). A11y-tree first, screenshots budgeted.
  Findings written to `reports/release-pass/gui/` as found.
- **Adjudication** (Fable, main loop): merge A+B into a single prioritized work-list in this
  document. Expected FP rate on map findings ~15–40% based on prior campaigns.
- **Wave C — Implement**: Opus batches on worktree isolation, grouped so no two batches touch
  the same files. Targeted tests per batch; full gates at wave end.
- **Wave D — Adversarial verify**: independent agents try to refute each fix batch
  (prior campaigns: ~1/3 of batches incomplete on first pass). Then loop to the next map wave
  until dry.

## Wave A findings (adjudicated)

16/16 mappers returned (3.65M tokens, 0 errors). Detailed work orders live in
`reports/release-pass/map/<subsystem>.md`; the structured summaries are in the workflow
result. Adjudication deltas — everything not listed here is approved as mapped:

1. **Sequencing**: dedup + bug fixes + dead code FIRST (Wave C1); ALL file splits deferred
   to Wave C3 so diffs stay reviewable. Cross-package consolidations (astronomy/sidereal ×14,
   coordinate formatters ×39, `_formatDuration` ×30, device-registry collapse, PHD2 registry
   split, WCS conformance fixture) are Wave C2 — they cross batch boundaries.
2. **save_fits precedence** (rust-bridge): settled deliberately — FrameContext wins when
   `Some`, ImageData fills `None` only. That is the documented rationale in the (dead)
   sequencer_ops.rs and keeps the header consistent with the captured_images row. The live
   unified path must be fixed to this BEFORE the ~6,500-line dead-stack delete, with the 9
   pointing tests re-pointed at `UnifiedDeviceOps::save_fits`.
3. **Headless endpoint catalog** (apps-shells): REJECTED the mapper's proposal to derive
   `availableHeadlessEndpoints()` from the route table and retire the contract audit. That
   double-entry bookkeeping caught a real missing-route bug on 2026-08-10. Derivation is
   allowed only if an independently-committed snapshot check survives.
4. **AdaptivePanelLayout 768-vs-1024**: resolved as doc-matches-code (768 stays), pinned by
   test. No layout behavior change in a release pass.
5. **Behavior-adjacent items are bug fixes, not refactors** — failing test first, or the
   finding is recorded as a false positive and left alone (standing no-fixes-from-code-reads
   rule). Applies to: frames-rejected always 0, recordDither never wired, fabricated preview
   metadata, flat-wizard mid-run settings drift, calibration match/listMasters disagreement,
   HYG silent empty sky, Phd2 split-frame drops, inverted phd2AutoSelectStar guard, RA-unit
   double-division (imaging_records_repository.dart:967), CoordinateFormat seconds carry,
   Dart .wcs 80-char parsing, Debug-stringified FITS headers, runtime-config commands never
   wired (update_location et al.), meridian-flip outcome emission, dawn solar divergence,
   trigger-monitor hang watchdog, sweepCache never scheduled (doc claims it is).
6. **rust-imaging**: deleting the #[cfg(test)]-only internal solver + wgpu/pollster also
   removes yesterday's G20 escape hatch (FORCE_CPU env + GPU timeout latch) — superseded by
   the deletion, remove them with it.

### Owner decisions (NOT executed by agents — need product calls)

- Dart fallback device stack (phd2_client/alpaca_client/ascom_client + retry/circuit_breaker,
  2,656 lines): bridge_stub.dart states fail-closed policy the code contradicts. Delete or document?
- Six unimplemented `Native*` traits + six unpopulatable bridge registries (a whole
  unreachable device backend).
- `NIGHTSHADE_COMPANION_UI` mobile dashboard: 4,845 unreachable lines nothing enables.
- Mosaic panel resume: production uses `NullCheckpointSink`; docs/tests claim
  `SessionWizardCheckpointSink` is production. Is panel resume supposed to be real in 6.x?
- Seven production-unreachable public methods in device services + the unused sequential
  profile-connect path (profile_connections.dart:11-106).

## Run state (for recovery after restarts)

The CLI process has exited twice mid-wave (not OOM — 25 GB free, no kernel OOM records; both
workflows + MCP died simultaneously each time). Progress is durable on disk: partial edits stay
on the tree, impl logs in reports/release-pass/impl/, GUI reports in reports/release-pass/gui/.
- Wave A: COMPLETE (16/16, adjudicated below).
- Wave B: 6/8 clusters cached in run wf_688773ab-3be; resume with that runId + unchanged script
  `workflows/scripts/release-gui-adversarial-wf_688773ab-3be.js`.
  2026-08-12: cache-resume relaunched (4th generation) after the session itself was lost.
  2026-08-13 08:5x: gen5 cache-resume (same runId). ROOT CAUSE of every prior death is now
  established: background workflows run inside the CLI process, and each generation died the
  moment the CLI exited (user /exit or terminal close), 5 minutes after relaunch on gen4.
  The terminal must stay open until the waves report complete. The session transcript is
  107 MB, which is why the resumed UI shows no chat history — the work state is all on disk
  and does not depend on it.
  2026-08-13 ~08:45: gen5 died the same way (user /exit at 08:25, 13 min after relaunch).
  gen6 cache-resumed (same runId wf_688773ab-3be). Before relaunch, 5 orphaned Xvfb displays
  (:84–:88) and 5 orphaned release-bundle app instances from the killed generations were
  still running and were killed by PID — a resumed Wave B collides with them (bound displays,
  stale single-instance locks), so check for strays on every future restart.
- Wave C1: no agent has completed a full batch yet (killed three times: gen1 wf_44399a15-b00,
  gen2, gen3 wf_b2a283e0-9ac died ~1 min in when the CLI exited a third time on 2026-08-11
  ~16:28), but the tree holds most of the edits (~174 files) and the charter is resume-aware.
  Script: `workflows/scripts/release-tightening-c1-wf_44399a15-b00.js` (resume-context charter;
  agents now pinned to Opus effort=high per owner). 2026-08-12: gen4 running as wf_bb7e6a03-1fb.
  2026-08-13 08:5x: gen5 relaunched as a resume of wf_bb7e6a03-1fb (gen4 journal had zero
  completed batches, so this is effectively a fresh start of the same charter; the tree still
  holds the ~174 files of accumulated batch edits).
  2026-08-13 ~08:45: gen6 relaunched the same way (resume of wf_bb7e6a03-1fb) after gen5 was
  killed by /exit 13 minutes in.
- Baseline for all diffs: commit b07d91c9d. Agents are forbidden to run git write commands;
  Fable commits per batch scope after gates.

## Wave C plan

- **C1 (now)**: 15 implementation batches (Opus), one per subsystem, shared tree with
  strict file-ownership; bug fixes (failing-test-first), dead-code deletion (fresh
  zero-caller proof), in-subsystem dedup. No splits. No git from agents — Fable commits
  per batch scope after gates.
- **C2**: cross-package consolidations (list in delta 1) after C1 lands + gates.
- **C3**: the mechanical file splits, last.
- Then Wave B GUI fixes, Wave D adversarial verify, loop until dry.

## Wave B findings (adjudicated 2026-08-13)

8/8 clusters returned (1.27M tokens): **181 findings — 2 P0, 18 P1, 61 P2, 88 P3, 12 P4.**
The cluster reports in `reports/release-pass/gui/` ARE the work orders; this section carries
only selection, re-scopes, and cross-cutting rollups. Every finding was reproduced live
against the release bundle with evidence paths, so the no-fixes-from-code-reads rule is
satisfied at source — but note the binary mix: Dart side is the 2026-08-11 09:55 `libapp.so`,
Rust side is a bridge `.so` the agents rebuilt today from the tree (which carries partial C1
edits). Re-verify each finding against current HEAD via the failing-test-first rule as usual.

### P0 (both deterministic, reproduced twice)

- **SEQ-12** — armed Unattended Autopilot silently kills any manually started sequence at its
  next 60 s tick and records it as "paused-stopped" (two trials + two matching controls).
- **SKY-2** — Your Sky "Create region" locks the whole app behind a modal that never lifts
  (the write commits; only the dialog completion path is broken). Force-quit is the only exit.

### Adjudication deltas (everything else approved as filed)

1. **SCI-39** (Null Island daylight gate) is the root fix for the whole L53/Null-Island class:
   absent location must be UNKNOWN, not (0,0). The gate refuses-with-the-real-reason (or the
   run proceeds with a warning), and pre-flight must say it. Fix the gate once, not the message.
2. **IMG-4 / IMG-14**: the Imaging snapshot and TPPA paths still launch `astap_cli` with no
   position/scale hints despite e87984e88 — a second solver call site exists (the
   two-implementations trap). The fix is pointing the GUI path at the hinted path, not new code.
3. **SET-17 re-scoped**: `pairing.db` lives outside the data dir (`~/Documents/Nightshade`,
   `~/.local/share/...`), so wiped/scratch profiles inherit the machine's real pairings. Fix =
   store location under the configured data dir + a revocation story on reinstall. Same class
   as COL2-6 (catalogs outside the data dir; "Delete Catalogs" is cross-profile destructive).
4. **EQP-23 re-scoped**: the GL frame-timeout may be softpipe-environmental; the confirmed
   defect is that a fatal render error exits the process silently — no shutdown record, no
   device safing. Fix the death path, not the timeout.
5. **SEQ-8** (today's runs grouped under yesterday) is probably deliberate noon-rollover
   observing-night grouping; fix = label the group as an observing night. FP if disclosed already.
6. **IMG-12** (Polar Alignment Stop ignored) is either a regression of the 2026-07-13 polar
   hardening ("stop actually terminates") or a second stop path (screen vs standalone slice).
   Failing test against the screen's stop wiring first; check both implementations.
7. **SCI-40**: the dark-library matcher must key on the actual sensor temperature when the
   camera has no cooler, not the profile's cooling set-point.

### Cross-cutting classes (fix at the shared component; one work item each)

- **A11Y-STATE** — controls report `[DISABLED]` while live, expose no checked state, or are
  absent from the tree entirely (the whole title bar and nav rail, EQP-5/CON-61). Present in
  all 8 clusters: IMG-6/22, SEQ-10, EQP-4/5, SET-6/18/19, SKY-17, SCI-36, COL2-9/12/14/18,
  CON-47. This is a `nightshade_ui`/Semantics defect family, not per-screen work. Absorbs
  the open accessibility-remainders task.
- **CRY-WOLF** — the app states something untrue: IMG-4/7/8/18, EQP-1/2, SEQ-14/18/19,
  SET-5/9, SCI-38/41, COL2-11. Fixed per item; the class tag exists for Wave D to verify none
  merely relocated the false claim.
- **SILENT-NOOP** — enabled-looking controls that do nothing: SKY-4, COL2-3/16, SET-2,
  SEQ-11, CON-49, CON-61 (person icon). Standard: disable + reason, or act + acknowledge.
- **STOP-ACK** — stop/pause with no acknowledgement: IMG-10/12/21, SKY-1, SEQ-28.
- **STATE-VOCAB** — raw internals user-facing: "paused-stopped" (SEQ-6/CON-51), device ids
  (EQP-11, status bar), Dart class names (SEQ-1), ISO-microsecond timestamps (SEQ-22),
  "No tick scheduled" (CON-54). One presentation-mapping layer.
- **UNITS/LABELS** — one number, two labels: IMG-5/11, SCI-37/47, SKY-3, SEQ-23.
- **CON-44** — the in-flow tour nudge shortens every screen ~16% on first run and explains
  wave-1's CON-34 class; a single-widget float fix, first in the consistency batch.

### Sequencing decision (supersedes "C2, C3, then Wave B fixes")

The **Wave B-fix batch (all P0/P1 + the P2s sharing their repro paths) runs immediately after
C1 lands and gates — BEFORE C2/C3.** C2/C3 are behavior-preserving mechanics; shipping
defects outrank tidiness. Wave D then adversarially verifies C1 + B-fix together. Rationale:
the two wave-2 GUI passes re-tested their wave-1 findings against the same binary and found
essentially nothing fixed — the finding/fixing balance has tipped.

### Harness debts to clear before the Wave D re-drive

- `drive_linux.py`: a leading `--profile` is silently clobbered by the subparser default
  (5 of 8 agents lost time to it) — make it an error or honor it.
- No wheel-scroll command; it blocked real coverage (Guiding dither/settle, EQP device
  cards). `xdotool click 5` works — wrap it as a `wheel` command.
- The GUI bundle and cargo-rebuild waves share `build/.../bundle`: C1's rebuild removed
  `libnightshade_bridge.so` mid-drive and killed every agent's boot until they restored it.
  Rebuild + freshness-check the bundle before Wave D, and never run a GUI wave concurrent
  with a rebuild wave against one bundle.

### Not re-verified this wave (treat as still open)

Hub-connected Collaborative Sky surfaces (wave-1 COL-1/2/4/5/7/8), the Milky Way layer render
(prior SKY-4), all of consistency wave 1 (CON-1…43 — no commit references a CON id), the
`/mosaic/:id` screen (unreachable behind COL2-16), and populated Stack Result / Session
Review of a successful run (blocked by SCI-39 in that profile).

## Wave C1 outcome (2026-08-13)

Gen6 completed: **15/15 batches, 0 agent errors** (3.4M tokens). Two false positives caught by
the agents' own re-proof (WeatherSafetyNotifier.evaluateNow has a live headless-route caller;
the "disagreeing" supernova icons alias to one glyph). One item correctly refused as not
behavior-preserving (the 11-notifier connect/retry mixin hoist — 3 of 11 genuinely diverge;
recorded, not landed). Deferred by charter: file splits (→C3), catalog-pipeline unification
(→C2), the EXPTIME/GAIN carry-over loop at bridge/src/api/imaging.rs:4811 (root helpers landed,
call site owed), the Arc<[u8]> INDI BLOB share (cross-scope signature change).

Gate status: analyzer_rollup 0/0, placeholder_audit no new high-risk, behavioral_audit pass,
cargo fmt + dart format clean (12 agent test files formatted), **full cargo workspace green
(23 suites)** after fixing one PRE-EXISTING race: the device_id cache tests share the
process-global DEVICE_ID_CACHE and are now serialized with a test mutex (device_id.rs, file
otherwise untouched since baseline). One Linux-regenerated golden
(docs/design/goldens/surface-run-session-progress.png) was reverted per the standing rule.
Full `melos run test` in flight.

Harness debts CLEARED (tools/ui_audit/drive_linux.py): leading `--profile` no longer clobbered
(SUPPRESS on the shared parent + post-parse default; probe-verified all four argument
arrangements) and a `wheel x y notches` command added (single xdotool invocation, verified).

## Wave B-fix stage 1 (launched 2026-08-13 ~11:15)

Running as **wf_97c730bb-5f5** — 8 feature-scoped Opus batches (sequencing-autopilot,
imaging-guiding-polar, onboarding-settings, equipment-shell-chrome, sky-planetarium,
science-analytics, collab-mosaic-catalogs, a11y-design-system) covering both P0s, all 18
P1s, shared-path P2s, and the component-level A11Y-STATE class. Failing-test-first; no GUI
harness / no bundle rebuilds by agents (live verification belongs to Wave D). Script (for
cache-resume after a restart): `reports/release-pass/scripts/release-bfix-stage1.js`,
resumeFromRunId wf_97c730bb-5f5. Impl logs land in reports/release-pass/impl/bfix-*.md.

C1 was committed 2026-08-13 in 15 scoped commits (3e1be6cdc..7aadcacce) after the full gate
set went green. Two extra fixes rode along: the calibrate-save numeric-header carry-over
(C1's own blocked handoff, RED-proved test) and the mobile_e2e hang root cause — **btrfs
EIO-corrupted ~/.pub-cache/pdf-3.12.0** (removed + re-fetched; a system btrfs scrub is
owed, other files may be corrupt).

## Wave B-fix stage 1 outcome (2026-08-13)

8/8 batches, **80 findings fixed** (both P0s, the P1 set, shared-path P2s, the A11Y-STATE
component family in nightshade_ui), 10 false positives (mostly "already fixed at HEAD — the
audited 2026-08-11 binary predates the fix", each pinned with a regression test), 20 blocked.
Impl logs: reports/release-pass/impl/bfix-*.md.

Key harness discovery (fixed in drive_linux.py the same day): the tree dump printed
[DISABLED] only for focusable/selectable/checkable nodes, and Flutter drops `focusable` from
disabled buttons — so a correctly disabled control could NEVER show [DISABLED], and several
"announced disabled while working" findings were dump artifacts. Interactivity is now decided
by role. Wave D must re-drive the a11y findings against the fixed dump.

### Closer fixes after the wave (Fable, gate triage)

The wave left 5 test casualties in nightshade_app; all closed:
1. general_language_scope_test — updated for the a11y Semantics wrapper on dropdown items.
2. scheduler_tab_content_test + scheduler_screen_test — updated for the intended SEQ-17
   "Target queue"→"Scheduler queue" rename.
3. REAL regression: the queue header's new "Last evaluation" timestamp overflowed its Row
   by 8.5px at narrow widths — fixed in queue_table.dart (Flexible + ellipsis).
4. REAL regression: the new unknown-panel-size banner rendered ABOVE the mosaic resume
   banner, pushing the resume affordance below the fold of the fixed-height dialog —
   banner order swapped (resume outranks the warning). Also repaired the test file's
   FlutterError.onError filter, which called presentError instead of delegating to the
   original handler and turned the real failure into an opaque binding assertion.

### Stage-2 sweep list (cross-scope blocked items, root causes already located)

- IMG-14 solver-hints half: extract unified_device_ops::plate_solve's hint-gathering into a
  shared helper used by polar_alignment's write_temp_fits_for_solve and the annotate path.
- SCI-27 (linear min/max stretch → black stacked preview) + SCI-28 (Stop destroys the stack,
  nothing on disk) + SCI-47 (units) — all in screens/imaging/stacking_panel.dart + live_stacking_service.
- SCI-42 (duplicate warning in report), SCI-46 diagnostics half (dropdown offers only
  imaging_sessions), SCI-43 sequencer copy instances, SCI-48 (ASTAP .ini debris — solve from
  a scratch copy; native platesolve.rs).
- SCI-36 remainder: bare InkWells at mosaic_projects_list_screen.dart:161 +
  diagnostics_screen "Learn more"; the 29 raw DropdownButton call sites (recipe in the
  a11y impl log).
- SKY-8 (tooltip anchor maths + retirement in nightshade_ui tooltip), SKY-9 (profile-sourced
  sensor dimensions for Framing), EQP-23 (last-gasp shutdown record + safing at the desktop
  entry point), CON-61b (Settings section param ignored when already open), SET-17 revoke-all
  UI (needs a PairingNotifier method + confirm flow).
- IMG-9 Frame Count label during looping = product decision (guide corrections vs loop frames).
- Concurrent-edit test casualties to re-check at gate time: general_language_scope_test
  (dropdown item now wrapped in Semantics), tutorial_tour_navigation ×2 +
  tutorial_overlay_persistence.

## Work-list

Order of execution from here:

1. ~~C1~~ DONE — committed 3e1be6cdc..7aadcacce, full gates green.
2. ~~Wave B-fix stage 1~~ DONE — committed e1f10a24b..b17655239 (8 batch commits + closer
   fixes + harness + docs), gates green (melos: every package SUCCESS except the five
   nightshade_app casualties, all five closed and re-proven; final clean nightshade_app run
   recorded in the session log).
3. **C2** cross-package consolidations — COMPLETE (wf_99035b9c-9c5, 6/6 topics, ~3.6h).
   ~100 call sites consolidated onto canonical implementations with exact-== parity tests
   (24k-point sweeps per formatter site; deliberate non-merges recorded with measured proof,
   e.g. two JD algorithms shown non-bit-identical over 50k instants). Impl logs:
   reports/release-pass/impl/c2-*.md. Notable outputs feeding later waves:
   - **JD+0.5 suspect**: planetarium coordinate_system.dart:_julianDate returns JD + half a
     day (~12 sidereal hours of LST error in toHorizontal, 4 live callers in sky_view.dart);
     its own test asserts the wrong value. Render path demonstrably correct (GUI-wave
     astrometry spot-checks passed), so this is a dormant secondary path — Wave D must
     reproduce in the running app before anyone fixes it.
   - **PHD2 cry-wolf**: AppState.devices vs DeviceManager.devices split means the
     connected-devices API cannot see a connected PHD2 guider — a real bug fix, now in the
     stage-2 sweep (failing-test-first).
   - **Rotation-sign divergence** between Dart/Rust WCS parsers needs a real ASTAP .wcs from
     the rig — Wave D / live-rig item.
   C2 committed 2026-08-13 (6 topic commits + hub format + docs, through 32ac81d33) after a
   FULLY CLEAN melos run (every package SUCCESS) + cargo workspace green.
   **Stage-2 sweep RUNNING as wf_b30baa13-b93** (launched ~17:35; script:
   reports/release-pass/scripts/release-stage2-sweep.js, 7 parallel batches incl.
   phd2-crywolf; resume with script + runId after any restart). Then **C3** file splits.
3b. **Stage-2 sweep** — COMPLETE + COMMITTED through 45bc9d5e4 (wf_b30baa13-b93, 7/7
   batches, 17 fixed, 0 FPs). Gate triage: placeholder audit caught 2 new silent-fallback
   unwraps in the debris sweep (one could delete a pre-existing sidecar — sweep now skips
   without a snapshot); one interface break in an out-of-scope fake stubbed. Final:
   nightshade_core 5,795 green, cargo workspace green, all quick gates green.
   **C3 splits RUNNING as wf_c7ff2598-1bf** (script:
   reports/release-pass/scripts/release-c3-splits.js, 10 batches, re-measure before split).
   NOTE for Wave D: some test rewrites assets/screenshots/desktop-dashboard.png and
   docs/design/goldens/surface-run-session-progress.png on every suite run — find the
   writer; tests must not mutate repo assets (reverted twice today). Notables: SCI-27 root cause was a linear min/max stretch (preview now
   routes through the shared Rust STF — Wave D must eyeball the live preview since no Dart
   test loads the native lib); SCI-28 Stop now offers Save-master-first; PHD2 cry-wolf fixed
   both ways (registry + disconnect route); EQP-23 last-gasp shutdown record + safing hook
   added at the desktop entry point; dropdown remainder solved with AccessibleDropdown
   wrappers, not 42 hand edits. Impl logs: reports/release-pass/impl/s2-*.md.
   NEW leftovers for the next wave: (a) Dart PlateSolveService._solveWithAstap is a THIRD
   unhinted solver call site (plate_solve_service.dart:398-442) — the two-implementations
   trap again; (b) SCI-43 pre-flight copy string at preflight_rules.dart:246 (suggested text
   recorded); (c) phd2 generic-connect route defect (untestable without PHD2 installed —
   Wave D live item). OWNER decisions flagged by agents: stacked master saves as PNG, not
   FITS (the FITS writer demands EXPTIME/DATE-OBS the live stacker lacks) — accept or extend
   the writer.

3c. **C3 splits** — COMPLETE + COMMITTED through 00ce2bf02 (wf_c7ff2598-1bf, 10/10
   batches, **118 files split**, 51 correctly skipped as already under threshold). Gates
   ALL GREEN (cargo 23 suites; melos all-SUCCESS after fixing one pre-existing
   minute-boundary race in location_settings_truth_test; nightshade_app record run 3,301); placeholder baseline
   regenerated for the moved paths (net improvement 211→184 markers). The three
   cross-batch breaks agents reported mid-wave all self-repaired before the wave returned.
   Design-decision residue (NOT mechanical, parked for the owner/Wave D):
   - executor start() is one 5,271-line function; decomposing it needs the map's Step-0
     handle-bundle refactor (RunCore/RunSignals/...) — a design change.
   - api/imaging.rs 12-file split requires FRB regeneration (agent PROVED the map's
     "glob re-export preserves paths" claim false) — needs a codegen-owning task that runs
     scripts/dev.sh codegen and absorbs the Dart import moves.
   - ascom_wrapper/camera.rs is #[cfg(windows)] — unverifiable on this host, left intact.
   - DefaultScienceBackend / FlatWizardService / ConstellationService residuals are public
     API that extensions cannot carry — real decomposition or accept the size.

4. **Wave D — RUNNING as wf_8f351778-efa** (launched 2026-08-13 ~18:35 against the fresh
   18:31 bundle; script: reports/release-pass/scripts/release-waveD-verify.js; resume with
   script + runId after any restart; cluster reports land in
   reports/release-pass/gui/waveD-*.md). Adversarial verify over C1 + B-fix + C2 + stage-2 (re-drive the GUI clusters
   against a fresh bundle + the fixed a11y dump; verify no fix merely relocated its defect;
   reproduce the JD+0.5 planetarium suspect and the phd2 generic-connect route live; eyeball
   the stacked preview); loop map→fix→verify until a wave is dry.
## Wave F verdict (2026-08-14 early) — CONVERGED TO THE TAIL; adjudicated

47 verified, 13 refute-claims held; **7 still-broken (all with closer recipes), 25 new
(2 P2, rest P3/P4), 5 refuted.** Full verdict: reports/release-pass/waveF-result.json.
Convergence: D 37+48 → E 29+29 → F 7+25 with severity collapsing to polish.

TERMINATION JUDGMENT (recorded): strict "zero new findings" is unreachable — adversarial
sweeps of a 700k-line app will always find P4s. The doctrine's spirit is served when a
wave returns nothing significant. F-fix therefore takes: the 7 recipe'd still-brokens, the
2 P2s (WF-STOP-N1 first-frame-at-5s exposure bug; WF-STOP-N4 stalled-flip false Running),
the tractable P3 tail, and the refutation follow-ups. A focused G spot-check verifies ONLY
those items. The remaining P3/P4 residue and the policy questions below then constitute
the documented handoff, and the campaign closes.

PRODUCT CALLS surfaced by F (owner decides):
- WF-N3: an operator Stop of an autopilot-dispatched run is silently re-dispatched ~44s
  later. Probably should pause the autopilot with a visible "autopilot paused — resume?"
  affordance; policy is the owner's.
- WF-N2 + WD-SEQ-N5: "Remove from scheduler"/"Clear all" delete goals but goal-less
  targets stay eligible (free-form imaging contract). Needs the queue-membership decision.
- Unconditional UnparkNode in every autopilot plan (refuted as blunt): fine for most rigs,
  wrong for rigs where unpark is consequential; consider gating on parked state.
- sequenceStopped push copy (parked earlier, still open).

## ~~Wave F dryness check — RUNNING as wf_20c973c5-59e~~ (completed, verdict above)

Launched 2026-08-13 ~23:58 against the fresh 23:56 bundle (E-fix code). Script:
reports/release-pass/scripts/release-waveF-dryness.js. E-fix committed through 4723ca202
(55 fixes; the cleanest gate of the campaign — melos all-SUCCESS first try, cargo 23,
quick gates first-pass). Known-open handoffs Wave F confirms without relitigating: the
disconnect-toast device id (WD-EQ-2a, fix written+reverted mid-wave, shape in the
equipment-chrome-3 impl log), ALL-CAPS NOW/TONIGHT (CON-56, two literals at
time_control_panel.dart:396/:432), NEW-C2/C3 out-of-scope halves, CON-62 row-title case
(needs settings_search_index regen), and the PARKED product call: what a sequenceStopped
push should say (currently deleted rather than de-escalated — also silences dome-shutter
and dawn ParkAndAbort stop notifications). A rogue mid-wave git stash was reconciled by
content (one stranded file restored: the tooltip lifecycle test); see the
stash-reconciliation memory.

## Wave E verdict (2026-08-13 night) — NOT DRY; adjudicated

47 verified fixed, 18 refute-claims held; 29 still-broken, 29 new (1 P1, 4 P2), 6 refuted.
Full verdict: reports/release-pass/waveE-result.json; narratives in
reports/release-pass/gui/waveE-*.md. Convergence is real (D: 37+48 → E: 29+29) but the
recurring residue was mostly items D-fix declared out-of-scope — E-fix charters them
explicitly so the dryness metric stops re-counting them.

Adjudication:
- NEW P1 WE-SEQ-N1: after its own dispatched run FAILS, the autopilot never dispatches
  again — one failed run ends the unattended night. With WE-SEQ-N5 (generated plans have
  no Unpark step, so every post-safing dispatch fails instantly) these two compound into
  the worst unattended outcome. E-fix batch 1.
- Two-implementations strikes to close for good: IMG-14 (the -fov work sits in Dart's
  PlateSolveService which production does NOT run; the native path never receives
  hint_scale though the polar wizard computes and logs it), WD-SEQ-N4 (chip's own
  _statusLabel at target_score_row.dart:175 overrides the fixed engine reason), WD-SEQ-N1
  (Session Report fixed; the toast/banner pipeline is a different producer still saying
  "Sequence failed"/"Critical"), WD-EQ-2 (friendlyNameFromDeviceId has no arm for
  native:builtin_guider/sim_* ids), IMG-9 (claimed auto-select logging is not observable —
  find the impl that runs).
- CON-61 (title bar + nav rail absent from AT-SPI) — PARKED as a platform item: the
  in-widget semantics are compiled in with zero runtime effect; export requires GTK
  accessibility-bridge work at the embedder layer, out of Flutter-widget reach. Recorded
  with the probe evidence; stops counting toward dryness.
- CON-53's "fix" replaced one false claim with another (WE-EQ-N1: a "Target Queue tab"
  that no longer exists) — the relocated-defect shape; recorded and re-chartered.
- 6 refuted D-fix claims (incl. SEQ-12 "closed at both seams" — a run the autopilot does
  not own is never end...; SEQ-13's re-point path; the sequenceStopped stale-state
  collateral) — details in the JSON for the E-fix agents.

## ~~Wave E dryness check — RUNNING as wf_ea671eb0-a4b~~ (completed, verdict above)

Launched 2026-08-13 ~20:35 against the fresh 20:33 bundle (D-fix code). Script:
reports/release-pass/scripts/release-waveE-dryness.js; resume with script + runId. D-fix
was committed through baddf35fd (61 fixes + 3 Fable closers), all gates green. If Wave E
returns nothing new, the campaign is DRY; otherwise its harvest feeds one more focused
batch and the loop continues.

## Wave D verdict (2026-08-13 evening) — adjudicated

11/11 agents against the fresh 18:31 bundle. **66 verified fixed, 28 refute-claims held;
37 still-broken, 48 new findings (1 P1, ~10 P2), 5 claims REFUTED.** Full machine-readable
verdict: `reports/release-pass/waveD-result.json`; cluster reports:
`reports/release-pass/gui/waveD-*.md`.

Adjudication:
- The 17 consistency CON-45..63 "still broken" items were NEVER in a fix wave's scope
  (only CON-44/60/61 were chartered) — they are correctly-unfixed backlog, not regressions.
  Assigned to D-fix where mechanical; the copy-register items (CON-57) stay owner-decision.
- REFUTED (top priority, the flagship P0): both halves of SEQ-12's ownership fix — a race
  at the tick boundary (dispatch vs no-eligible tick) and `currentTargetId != null` is not
  a sound "this run is mine" test (stale after operator Stop / failure). Proof test saved at
  scratchpad seq12_race_test.dart — D-fix must adopt + harden it in-repo.
- REFUTED: C1 frame-verdict fix reaches counters but NOT the integration total beside them;
  phd2AutoSelectStar refusal RELOCATED not removed; SCI-48 debris sparing uses string-prefix
  not base-name matching (M31.fits spares M31_dark.ini class errors).
- Claimed-fixed-but-still-broken to re-open: IMG-10 (pause: tooltip added, click still a
  no-op — make it disabled-with-reason for the builtin guider), IMG-16 (bullseye now WORSE:
  post-run says "No measurement yet" beside a 3.2" result), SEQ-13 (target RA/Dec snapshot
  still stale in the engine; site changes ARE live), SEQ-18 (0/N after success), SEQ-19
  (contradiction moved: "R 180s" two rows above "No Filter"), SEQ-20 (elapsed still whole-
  minute), SCI-43 preflight string (preflight_rules.dart:246 — was recorded blocked, never
  landed), CON-61 (title bar STILL absent from the AT-SPI tree — the B-fix claim is wrong at
  the tree level), SET-2/12/18 residuals, SKY-4/10/16, COL2-3/13 (B-fix called these
  already-fixed-at-HEAD; Wave D disagrees — re-examine with the live evidence).
- IMG-4 unchanged (green "Found 0 objects" on a failed solve) and IMG-14's field-scale hint
  is still missing (-fov never passed; position hint landed).
- New P1: ND-1 live-stacking frame counters freeze at 1 while 68 frames stack; Stop dialog
  then under-reports. New P2s: ND-2/3/4, WD-SEQ-N1/N2, WD-EQ-1 (heartbeats STILL 20676d for
  5 of 6 types — the EQP-1 fix missed the non-camera path), WD-N1/N4, WD-SCI-N1, WD-COL-N1.
- Harness traps recorded by WD-EQ-8 (AT-SPI tree lag) — fold into the harness notes.

5. Owner-decision items from Wave A remain parked in their section above; IMG-9 (loop
   frame-count label) joined them from B-fix, CON-57 copy-register from Wave D.

## Fix log

_Pending._
