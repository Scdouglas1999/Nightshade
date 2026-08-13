# Release Tightening Pass — 2026-08-11

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
   Next: **stage-2 sweep** (script: reports/release-pass/scripts/release-stage2-sweep.js,
   7 batches incl. phd2-crywolf), then **C3** file splits.
4. **Wave D** adversarial verify over C1 + B-fix (re-drive the GUI clusters against a fresh
   bundle + the fixed a11y dump; verify no fix merely relocated its defect); loop
   map→fix→verify until a wave is dry.
5. Owner-decision items from Wave A remain parked in their section above; IMG-9 (loop
   frame-count label) joined them from B-fix.

## Fix log

_Pending._
