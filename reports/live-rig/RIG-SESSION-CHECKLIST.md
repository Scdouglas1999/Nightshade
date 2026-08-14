# Live-rig session checklist — post-campaign validation (drafted 2026-08-14)

One document for the next owner-present session on sean-laptop (192.168.1.47, SSH
`nslaptop`, headless on :8080). Deploy per the rig-deploy recipe first: the owner's
install is a DIFFERENT tree; use Stop-ScheduledTask (never Stop-Process); grep a
campaign string in app.so as the freshness signal ('Stopped by autopilot' is a good
marker — it exists only in post-K builds).

## A. The stop pipeline on real hardware (the campaign's core claim)

1. **One press = one row.** Start a short run on the real rig, press Stop once →
   RECENT EVENTS shows exactly ONE "Sequence stopped — Stopped by request" row, no
   error toast, no Decision-logged row. (L7's cry-wolf was "Stop reports failure after
   successfully stopping" — verify the polarity stays fixed under real device timing,
   where the safing teardown takes real seconds.)
2. **The teardown gap.** Real park/dome close makes the api `Stopped` trail the press
   far longer than the sim's — confirm the feed still shows one row (run identity on
   the wire is what makes this work; the sim could not exercise real latency).
3. **Autopilot attribution.** Let the autopilot dispatch, then stop from the scheduler
   side (or wait for a re-plan) → the row must read "Stopped by autopilot", and with
   the new pause behavior the autopilot must NOT re-dispatch after YOUR stop — the
   "Autopilot paused — resume?" affordance appears instead.
4. **Safety abort stays neutral + pushes.** Trip a safety condition (weather sim input
   or dome) → the stop row is cause-neutral, and the phone receives an INFO push with
   the real cause. Your own press must NOT push.
5. **Stop of a paused run / mash test.** Pause → Stop; and (via the headless API, since
   the GUI single-fires) two rapid stops → one row per real invocation.

## B. Device identity (open L-items)

6. **L2 — camera model names**: every connected device should now show its real model,
   not the generic driver name ("EAF Focuser" → the actual model string).
7. **L4/L10 — phantom devices**: the fix is deployed but was never hardware-validated.
   Confirm the phantom CAA rotator no longer reports connected, and that a real move
   command is never silently swallowed.
8. **L5 — triple mount**: the same mount must appear once; verify the two ghost
   entries are gone and the one entry connects.
9. **L36 — ProgID vs model**: ASCOM devices should report their model; if this is
   still ProgID-only it stays open (task #35).

## C. New behaviors this campaign added (never seen hardware)

10. **Meridian flip camera claim** (the sim cannot fire a flip — the gate keys on real
    mount HA): run through a flip; the solve exposure must WAIT for the in-flight
    light frame, and the retry-ladder ETA must be sane.
11. **Failed interval autofocus continues**: force an AF failure (defocus heavily or
    cap the star count) mid-sequence → the run continues on the restored pre-AF
    position, one decision row, one INFO push, no re-fire storm.
12. **Unpark gating**: start an autopilot plan with the mount already unparked → no
    spurious unpark command reaches the mount (check the driver log).
13. **Mosaic panel resume** (owner accepted on-rig risk): start a mosaic, kill the
    app mid-panel, relaunch → the wizard resumes from the checkpoint with panel state
    intact.
14. **FITS stacked master**: run live stacking, save the master → a valid FITS with
    synthesized EXPTIME (total integration) and DATE-OBS (first frame), opens in a
    FITS viewer alongside the per-frame files.

## D. Session hygiene

15. Watch the first 30 minutes of an unattended run for the frame-registration seam
    (the 2026-08-09 headless start-path bug: 30 FITS on disk / 8 registered — fixed,
    never re-verified on the rig).
16. At session end: pull the app log; zero EXCEPTION/overflow lines is the bar the
    sim sessions now meet.

Everything here maps back to: reports/release-pass/RELEASE-PASS-2026-08-11.md
(CLOSEOUT + owner decisions), reports/live-rig/FINDINGS-2026-08-09.md (L-items), and
tasks #32/#34/#35.
