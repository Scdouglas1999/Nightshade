# Units still unreached after the closeout wave

## `screen:sequencer/broadcast_panel.dart`

Has no call site in the shipping app - only its own declaration and one widget test instantiate BroadcastPanel, so there is no route to it from the running binary. Recorded as a finding rather than a coverage gap.

Evidence: grep -rn BroadcastPanel packages apps --include=*.dart returns exactly 3 lines: the class declaration, its const constructor, and broadcast_panel_test.dart:30.

## `screen:sequencer/forensics_panel.dart`

Needs at least one REJECTED frame; none can exist on this profile because frame grading is off. The replay decision payload states 'grading_active: false', the Session Report and Session Summary both report 'Frames rejected 0', and _ForensicsPanelBody renders nothing when the record list is empty. Reaching it needs a run with grading enabled AND frames bad enough to fail it (sim_faults or a deliberately defocused frame).

Evidence: Replay Debug > 'Sequence started' payload: {"grading_active": false, "phase": "started", ...}; Session Summary 'Rejected 0 / Accepted 12'.

## `screen:sequencer/session_report_forensics_section.dart`

Same gate: ForensicsRunSection returns SizedBox.shrink() when forensicsRecordsForRunProvider is empty, and no frame was rejected in any of the three runs (grading off).

Evidence: Full Session Report for run #2 captured end to end: Wall clock/Frames tiles, Mount-operations, Guiding, Targets, Errors, Diagnostics ('Cooler Out of Setpoint Band' only), Journal, Notes. No forensics block; Frames rejected 0.

## `screen:sequencer/frame_detail_dialog.dart`

run_dashboard/frame_detail_dialog.dart is opened from the forensics rows (session_report_forensics_section imports it for exactly that), so it is blocked behind the same missing rejections. The strip's own inspect dialog that I did open is a different class (_FullFrameDialog in exposure_node_thumbnail_strip.dart), as is the live-frame tile's _FrameInspectDialog.

Evidence: grep shows session_report_forensics_section.dart imports run_dashboard/frame_detail_dialog.dart; with zero forensics records no row exists to click.

## `screen:sequencer/session_handoff_dialog.dart`

Its only call site is preflight_validation_dialog.dart:280, guarded by `if (carry.isNotEmpty)`. sessionCarryOverProvider only yields entries when the sequence's target NAME matches a row in the target LIBRARY (session_handoff_service.dart:262 does a byCatalog/byName lookup and `continue`s when null). The runs used an ad-hoc 'New Target' typed into the node, which is never written to the target library, so carry-over was empty.

Evidence: Start pressed a fourth time after three recorded runs on 'New Target'; Pre-Flight showed the changed-sequence card and Start Anyway, and no SessionHandoffDialog appeared in the screenshot or the a11y dump.

## `screen:sequencer/meridian_flip_progress_dialog.dart`

Requires the executor to actually PERFORM a flip. Run #2 sat for minutes with the target 8.93h past the meridian and the exposure gate explicitly waiting on a flip, and no flip ever fired; the simulated mount reports no pier side, so the MinutesPastMeridian trigger never acts. Recorded separately as the P1 hang finding.

Evidence: app.log 21:24:12.219964Z 'Waiting for the meridian flip before the next 5s exposure: the flip fires in ~0s (hour angle +8.93h ...)' with no flip in the following 4 minutes; Session Report tile 'Meridian flips 0'.

## `screen:sequencer/recovery_insights.dart`

It is a part of session_report_dialog and renders only when the run recorded recovery events. All three runs completed, failed or were stopped without the executor entering recovery, so the Session Report - read end to end twice - contained no recovery block.

Evidence: Full Session Report for run #2 captured in two overlapping screenshots: Wall clock/Frames tiles, Mount-operations, Guiding, Targets, Errors, Diagnostics, Journal, Notes, with no recovery section between any of them.

## `screen:sequencer/missing_specs_dialog.dart`

SmartNightMissingSpecsDialog is shown from smart_night_dialog.dart:720, inside the plan-build step that runs AFTER the wizard's Equipment step. The wizard could not be advanced past Equipment on this profile (see the Smart Night 'Next' finding), so the plan build never ran and _shouldPromptForCameraSpecs was never evaluated. Reaching it needs a profile with an ASSIGNED camera whose specs are incomplete.

Evidence: Smart Night stepper stayed on '2. Equipment' through four Next clicks while showing 'Camera <no camera>', 'OTA <no telescope> (0mm @ f/0.0)', 'Mount <no mount>'.

## `settings:backup (S3 push)`

No S3-compatible endpoint is available in this sandbox — no minio, no moto, no boto3 — and I did not install packages onto the user's system. Unlike WebDAV, a hand-rolled S3 stub that accepts anything would not exercise the part that can actually be wrong (SigV4 signing), so it would be a green light with no evidence behind it. The WebDAV half of the same SyncTarget code path was exercised end to end instead.



## `screen:constellation/shared_target_detail_screen.dart`

Both call sites (constellation_screen.dart:312 and :673) push the screen with a SharedTarget obtained from a Constellation hub. There is no hub server in this tree — packages/ holds app, bridge, core, planetarium, plugins, remote_protocol, ui, updater and no nightshade_hub — and the paired appliance is a rig, not a hub. Faking one the way I faked WebDAV was rejected on cost: constellation_client.dart is 1145 lines implementing the whole §5 hub contract, not a single endpoint.



## `mobile:first_run_setup_screen.dart`

I got the mobile app paired to the appliance (second Android emulator on port 5556 so the sibling agent's emulator-5554 was untouched; pairing code COSMOS-QUASAR-5851 accepted with admin scope) and confirmed the screen still cannot appear. FirstRunSetupScreen's only mount point is mobile_dashboard_screen.dart:96, and MobileDashboardScreen's only instantiation is main.dart:509 inside `if (useCompanionUi)`; useCompanionUi = isPhone && isCompanionUiEnabled, and isCompanionUiEnabled is a --dart-define defaulting to false plus a Platform.environment lookup an Android app cannot satisfy. The paired phone rendered the shared NightshadeApp shell and its 13-step 'Set up your rig' wizard instead. Recorded as a finding.



## `mobile:checkpoint_resume_dialog.dart`

Pairing was not the blocker and is now closed; host state is. With the phone paired, GET /api/sequencer/checkpoint/has on the appliance returns {"hasCheckpoint":false} and /info returns {"info":null}, so _checkForCheckpoint's `if (info == null || !info.canResume) return;` fires. It cannot be seeded from outside a run: POST /api/sequencer/checkpoint/save answers {"error":"internal_error","message":"No sequence loaded"}, and the on-disk artefact is a serialised SessionCheckpoint carrying a whole SequenceDefinition (sequencer/src/checkpoint.rs:234, CHECKPOINT_VERSION 3). This unit belongs with the runtime-run cluster.



## `mobile:session_replay_screen.dart`

Same dependency, different artefact. SessionReplayScreen is pushed only from session_picker_screen.dart:244 with a runId, and the paired appliance has never executed a sequence: its dashboard reads 'No runs yet — your first night will appear here' and /api/status reports sequencer state 'idle'. A completed run on the host is what is missing, not a paired client.



## `widget:connection_stale_banner.dart`

Not reachable on the desktop remote client, which is what this cluster provides. connectionStaleProvider is a StateProvider whose only writers anywhere in the tree are apps/mobile/lib/main_parts/mobile_connection_state.dart:151/258/282/292/346; the shared shell mounts the banner (app_shell.dart:840) but nothing on the desktop side ever flips the flag. Verified live rather than by reading: I SIGSTOPped the appliance for two minutes with the client on the dashboard and no banner appeared at any point — the chip stayed green 'LAN 192.168.1.20 2 ms' for ~90 s and then went red 'Offline 192.168.1.20'. Reaching it needs the MOBILE app inside its reconnect grace window; my emulator app was paired but I did not hold it in that window.



## `screen:sequencer/narrow_layout.dart`

Provably unreachable in the shipping build, demonstrated live rather than argued from source. _NarrowDesktopLayout is chosen only when the builder's availableWidth < 396 (48 rail + 300 centre + 48 rail), but its parent already returns the phone builder whenever min(width,height) < 600 — which every sub-396 width satisfies. Driven at 420x900 and again at 380x900: both rendered the phone builder (SequenceToolbar + MobilePlaybackBar + 'Tap + to add instructions' + add FAB), never the 48px icon rail. It is dead code, not a coverage gap.

Evidence: scratchpad/shots/seq-380.png plus the a11y tree at 380x900 showing the playback bar and 'Tap + to add instructions' with no rail

## `screen:imaging/centering_dialog.dart`

Still blocked on plate solving — the plan's 'now unblocked by S9' is stale. sim_sky.rs has landed and IS in the shipped bridge (bundle .so and target/release .so share an md5, built after the source), and its own ignored test solves a downloaded simulator frame to 0.5". But it does not engage in the running app: with sim camera + sim mount connected, the solver preference loaded at startup as astap='.../nightshade-audit/astap/bin/astap_cli' catalog='.../astap/bin' (full D05), and the mount unparked and slewed to RA 05h30m/Dec +22 (the slew was accepted, which also proves the sim mount reads connected), the app's own solve logged 'Running ASTAP: ... -d .../astap/bin -wcs' then 'ASTAP exited with non-zero status 1'. Independent hinted solves at 0.582 deg (400 mm) and 0.2327 deg (1000 mm default) plus a 180-degree blind solve all returned 'No solution found', two consecutive frames at a fixed pointing share ZERO of their 40 brightest median-filtered sources, and no 'sim sky: indexed N area files' line is ever logged. Without a WCS none of Slew & Center / dashboard quick actions / planetarium can produce the dialog.



## `widget:details_panel.dart`

Same root cause. details_panel is `part of` catalog_overlay_widget, which live_preview_area only builds once the preview holds a plate-solved frame with a WCS. No simulated frame can be solved in the shipped app (see centering_dialog), so the overlay never mounts. The recorded reason on file is still accurate; only its 'plate solving is now solved in principle' caveat is not.



## `widget:details_panel.dart`

Still blocked on plate solving, but for a NEW reason, not the recorded one. S9's sky renderer is wired only into device_manager/ops/camera.rs:1217; the Imaging screen's capture runs through api/imaging.rs, whose simulator branch calls its own generate_simulated_image() (imaging.rs:1304-1344, rand::thread_rng star field). The log never prints sim_sky's 'sim sky: indexed' line, the frame is visibly a uniform random blob field, and no solve is possible, so CatalogOverlayWidget never receives a catalogWcs and CatalogOverlayDetailsPanel (catalog_overlay_widget.dart:319) cannot mount. It becomes reachable the moment api/imaging.rs's simulator branch renders through synthesize_sim_frame + sim_sky_view like the device-manager path already does.

Evidence: Live release build with the whole chain stood up: ASTAP 2026.07.16 + D05 detected by the app ('ASTAP detected /home/scdouglas/.local/share/nightshade-audit/astap/bin/astap'), platesolver.json catalog_path pointed at the D05 directory, Simulated Camera + Simulated Mount connected, optical train 1000mm f/5.0 (app-computed 0.78"/px, the exact configuration the S9 probe solved sub-pixel at). Snapshot produced /tmp/nightshade_captures/capture_1786311827034.fits (FOCALLEN=1000, RA=0, DEC=0) and the app auto-solved it: ASTAP reported '49 stars, 173 quads selected in the image' then '30d,30d,No solution found!  :('. With that frame loaded, Overlays > Catalog overlay produced 'Catalog overlay unavailable / Solve this frame to project catalog objects.'

## `settings:captured-images (populated state)`

Re-verified live, and the brief's hypothesis ('needs frames on disk') is wrong: with a local desktop backend the page renders only its subtitle 'Browse frames captured on the connected appliance' and the note 'Connect to a remote appliance to browse its captured frames.' -- no grid, no thumbnails, regardless of the capture folder contents. The populated state needs a paired NetworkBackend appliance that already holds captured frames, i.e. the remote-appliance cluster's pairing recipe plus the runtime-run cluster's completed run. I had neither and did not fake it.


