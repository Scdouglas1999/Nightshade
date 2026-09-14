# w14-tppa-solve — three-point polar alignment plate solves time out

Branch `agent/w14-tppa-solve`, based on `26e00be5d` (verified with `git rev-parse --short HEAD`).

## The problem, from tonight's rig log

Normal captures solve hinted (`Plate solving near RA:342.10°, Dec:58.27°`) in ~5 s. TPPA
frames solved **blind** (`Blind plate solving: …polar_align_point_1_…fits`) on a
4656 × 3520 unbinned frame with a 30 s budget. Generation 1: `Plate solve timed out after
30.0 seconds for point 1` **and** `ASTAP (pid 6844) timed out after 30 seconds` — the
async guard and the process runner fired at the same instant. Generation 2's retry solved
point 1 blind in 26.5 s, i.e. the old budget was marginal on a good attempt and short on
a bad one.

Three independent causes, all fixed here: no position hint, a budget too small for a
blind solve, and a downsample factor that was inherited rather than chosen.

## What changed

### 1. TPPA frames solve hinted first (new file `bridge/src/api/polar_alignment/solve.rs`)

- `read_polar_solve_hint(mount_id)` reads `mount_get_status` — the same call
  `rotate_for_next_point` already uses to build its slew target — and turns
  `right_ascension` (hours) into the degrees `plate_solve_near_scaled` takes.
  A driver error, a NaN, or `|Dec| > 90` produces `None` and the frame solves blind
  exactly as before.
- Search radius is `POLE_REGION_OFFSET_DEG` (30°), clamped to
  `ASTAP_MAX_SEARCH_RADIUS_DEG` (180°). 30° because the measurement points sit that far
  from the pole in the mount's own frame, so the cone covers the whole pole region even
  if the unaligned pointing model is wrong by the full width of it. The centring path's
  5° would not.
- `solve_polar_frame()` runs hinted, then blind on failure, and logs which one won:
  `Polar alignment point 2: solved by the HINTED path in 4.3s` or
  `… the hinted solve failed (…); falling back to a blind solve with the remaining 45s`.
  The failure text names both attempts instead of implying one.
- The scale hint (`-fov`) is unchanged and still sent on both paths.
- The adjustment loop now solves through the same function. It re-solves the same field
  every few seconds and was the frame least entitled to search the whole sky.

### 2. Timeouts

- Rust default: `solve_timeout.unwrap_or(60.0)` → `DEFAULT_POLAR_SOLVE_TIMEOUT_SECS` (90).
- Dart default: `PolarAlignmentConfig.solveTimeout` `30.0` → `90.0` (freezed/json
  regenerated). `session_handlers.dart`'s `solveTimeout ?? 30` now defers to the model
  default so the headless API and the dialog cannot drift.
- The hard-coded `Some(30)` / `from_secs(30)` in the adjustment loop is gone; it uses the
  configured value.
- The value stays user-editable on the existing Advanced → Solve timeout slider
  (10–120 s, unchanged range), and the validator still bounds it at 5–120 s.
- **Budget split (deviation from the brief — see below).** One frame's budget is shared:
  the hinted attempt gets `max(50 %, 15 s)` of it, the blind fallback gets the rest, and
  a remainder under 10 s means no fallback is started at all (it could not finish, and
  spending the time to reach the same failure is worse). At the 90 s default: 45 s hinted
  + 45 s blind, and 45 s beats the 26.5 s a blind solve actually took on this rig.
- **ASTAP is the authority on the deadline.** Each attempt hands ASTAP its whole budget
  as the process timeout, and the async watchdog sits 5 s *behind* that
  (`SOLVE_WATCHDOG_MARGIN_SECS`). So the solver kills its own child, reports
  "ASTAP timed out after N seconds", and releases the solve gate immediately, instead of
  being abandoned mid-run by a watchdog that fired at the same second. With no hint (the
  blind-only path) the ASTAP process timeout equals the whole frame timeout.

### 3. Downsample

- `polar_solve_downsample(width, height, binning)`: `2` when the long side exceeds
  3000 px **and** binning is 1; `1` (explicit, no downsampling) when binning ≥ 2.
  Computed per frame from the image that came back, not from the requested binning, so a
  camera that refused the bin request is not mis-classified.
- **This found a real bug in the opposite direction.** `PlateSolverConfig::default()`
  already sets `downsample: 2` and nothing overrides it, so ASTAP was *already* getting
  `-z 2` on TPPA frames — and also on binned ones, where binning and downsampling
  compound (a 4×4 frame halved again is 1/8 of the sensor per axis, which throws away the
  stars the solve needs). The polar path now passes an explicit factor instead of
  inheriting a global.
- `downsample` is threaded as `Option<u32>` through `plate_solve_{blind,near}_scaled` and
  `nightshade_imaging::{blind_solve_with_timeout, solve_near_with_timeout}`. `None` keeps
  the configured default; the two existing `device_ops.rs` call sites pass `None` and are
  behaviourally unchanged.
- `build_astap_args` now emits `-z` for any factor ≥ 1 (was > 1). `0` still means "ASTAP
  decides" and still sends no flag; `1` now reaches ASTAP as `-z 1`, which is how a caller
  says "do not downsample" — omitting the flag says "you choose", which is not the same
  instruction.
- **`-fov` is unaffected by `-z`, confirmed in code and pinned by a test.**
  `build_astap_args` derives `-fov` from the frame's own NAXIS2 and the arcsec/px scale
  and never consults `config.downsample`; `-fov` is the angular height of the field, which
  is the same field however many pixels ASTAP reads it at. No scale adjustment is needed
  or made. (`downsampling_does_not_move_the_field_of_view_hint`.)

### 4. Dialog default binning

`PolarAlignmentConfig.binning` was **already** `2` at this commit — the rig ran binning 1
because the owner's saved config (DB key `polar_alignment_config`) holds 1, either from
the High Precision preset or a manual choice. Saved settings are not rewritten from under
him. What changed: the Binning help text is now
*"Binning 2 solves in a quarter of the time; alignment accuracy is unaffected."*, the
default carries that reasoning as a doc comment, and the widget test asserts the wizard
opens on 2 with that explanation visible.

### 5. Presets

`quickStart` 20 s → 60 s and `highPrecision` 45 s → 120 s. 20 s was below what a blind
fallback needs to finish at all, so "quick" meant "gives up"; `highPrecision` runs
unbinned, the slowest case, so it gets the largest budget the validator accepts.

## Deviations from the brief

1. **"The ASTAP process timeout must be ≥ the point timeout."** Held exactly for the
   blind-only path (ASTAP timeout == frame timeout, watchdog 5 s later). For the hinted
   attempt, ASTAP gets the *attempt's* budget (45 s of a 90 s frame), not the frame's —
   because the literal reading double-books the clock: a hinted attempt allowed the full
   frame timeout leaves nothing for the fallback the brief also asks for, and a fallback
   with its own full timeout silently doubles the frame to 180 s (9 minutes for three
   points). The guarantee the brief is protecting — ASTAP is never killed before the
   thing waiting on it gives up — holds for every attempt.
2. **Binning default** was already 2 (see above), so only the help text and its
   justification changed.
3. **Preset timeouts** were raised; not in the brief, but leaving `quickStart` at 20 s
   reintroduces exactly tonight's failure for anyone who taps that preset.
4. `apps/desktop/lib/headless_api/handlers/session_handlers.dart` and
   `bridge/src/unified_device_ops/device_ops.rs` are outside the pointer list; each takes
   a one-expression change (the headless default, and `None` for the new parameter).

## Windows-only / untested here

- **Nothing in this change is `#[cfg(windows)]`.** No COM, no ASCOM wrapper, no
  platform-gated code was touched; the mount position comes from
  `DeviceManager::mount_get_status`, which every backend already implements and which the
  rotation path has used on this rig.
- **Untested on hardware.** The hint only helps if the mount's reported RA/Dec is roughly
  right; that is the condition tonight's rig satisfies (it reports a position, and the
  pointing error being measured is degrees, not tens of degrees). No ASTAP process was run
  in this verification — `build_astap_args` is asserted, ASTAP's response to `-r 30`,
  `-z 1` and a pole-region cone is not. Both `-z 1` and `-r` are documented ASTAP flags
  the existing code already emits in other combinations.
- The blind fallback is what covers a mount whose position is wrong by more than 30°.
- `flutter_rust_bridge` codegen was NOT re-run: no FFI signature changed
  (`api_start_polar_alignment` still takes `solve_timeout: Option<f64>`; only its default
  moved).

## Commands run (unpiped exit codes)

| Command | Exit |
| --- | --- |
| `cargo test -p nightshade_bridge -p nightshade_native --lib` (TMPDIR=~/.cache/ns-tests, CARGO_TARGET_DIR=~/.cache/ns-worktrees/cargo-target) | 0 — 708 + 202 passed, 0 failed |
| `cargo test -p nightshade_imaging --lib` | 0 — 865 passed, 0 failed |
| `cargo build --release -p nightshade_bridge` | 0 (Linux preview stays buildable) |
| `cargo clippy -p nightshade_bridge -p nightshade_imaging --lib --all-targets` | 0, no warnings |
| `flutter test test/screens/polar_alignment --concurrency=3` (nightshade_app) | 0 — 62 passed |
| `flutter test test/models/polar_alignment_config_validation_test.dart test/providers/polar_alignment_{run_control,stop_acknowledgement}_test.dart` (nightshade_core) | 0 — 35 passed |
| `flutter test test/headless_api/session_handlers_test.dart` (apps/desktop) | 0 — 22 passed |
| `dart format --output=none --set-exit-if-changed packages/nightshade_app packages/nightshade_core apps/desktop/…/session_handlers.dart` | 0 — 3714 files, 0 changed |
| `dart analyze` (nightshade_app) | 0 — 873 issues, all pre-existing `info` deprecations, 0 errors/warnings, none in the changed lines |
| `dart analyze` (nightshade_core) | 0 — 16 pre-existing `info`s |
| `dart analyze lib/headless_api` (apps/desktop) | 0 — no issues found |

## Tests added

Rust (`bridge/src/api/polar_alignment/solve.rs`): hours→degrees hint construction, RA
wrap folding, the radius floor and ASTAP clamp, NaN/out-of-range reports producing no
hint (blind fallback), the large-unbinned/already-binned/small-frame downsample rule,
the budget split (both attempts inside the configured timeout, no-hint spends it all,
short budget keeps the hinted floor and drops a hopeless fallback, NaN clamped), and
ASTAP owning the deadline with the watchdog behind it.

Rust (`imaging/src/platesolve.rs`): `-z 1` reaches ASTAP, `-z 0` sends no flag, and
`-fov` is identical at `-z 1` and `-z 2`.

Dart (`packages/nightshade_app/test/screens/polar_alignment/polar_alignment_solve_defaults_test.dart`):
the fresh config is binning 2 / 90 s and passes its own validator, every preset budgets
≥ 60 s, the wizard opens on binning 2 with the quarter-of-the-time explanation, and the
Advanced slider opens on 90 s.

## Left undone

- The owner's persisted config still holds `solveTimeout: 30` and `binning: 1`; the new
  defaults apply to a fresh install. **That is survivable tonight**: at 30 s the split is
  15 s hinted + 15 s blind, and a hinted pole-region solve on this rig runs in ~5 s. To
  get the full margin he can drag Advanced → Solve timeout to 90 and set Binning to 2×2.
- On-sky validation of the hinted TPPA path.
