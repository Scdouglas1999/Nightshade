#!/usr/bin/env python3
"""Tab through the live app, toggle every switch, and check it survives a restart.

WHY THIS EXISTS
---------------
"Audit every setting" is the part of a sweep that agents and humans both quietly
skip, because there are 664 setting rows and clicking each one is tedious. So the
settings that get exercised are the interesting-sounding ones, and a switch that
silently fails to persist -- or that throws when toggled -- ships.

This does it mechanically instead, and without needing pixel coordinates:
keyboard focus traversal visits every focusable control in order, the
accessibility tree reports which control is focused and whether it is on or off,
and Space toggles it. Then the app is restarted and every switch is read back.

Three distinct defects fall out of this that nothing else catches:
  * a switch that does not change state when activated (dead control)
  * a switch that changes in the UI but reverts after a restart (not persisted)
  * a switch that throws, hangs, or takes the app down when toggled

USAGE
  sweep_switches.py --profile settings-sweep [--max-tabs 400] [--no-restart]

Run it against a profile that is already past onboarding; it does not navigate,
it sweeps whatever screen the app is currently showing. Point it at Settings
sections one at a time for the fullest coverage.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drive_linux as d  # noqa: E402


def _focused(profile: str):
    """(role, name, is_on) for the control that currently has keyboard focus."""
    app = d._atspi_root(profile)
    if app is None:
        return None
    for _, role, name, node in d._walk(app):
        try:
            raw = {s.value_nick for s in node.get_state_set().get_states()}
        except Exception:
            continue
        if "focused" not in raw:
            continue
        on = "checked" in raw if "checkable" in raw else None
        return (role, " ".join(dict.fromkeys(name.split())), on, raw)
    return None


def _tab(profile: str, shift: bool = False) -> None:
    subprocess.run(
        ["xdotool", "key", "--clearmodifiers", "shift+Tab" if shift else "Tab"],
        env=d._env(profile), check=True,
    )
    time.sleep(0.35)


def _activate(profile: str) -> None:
    subprocess.run(
        ["xdotool", "key", "--clearmodifiers", "space"],
        env=d._env(profile), check=True,
    )
    time.sleep(0.6)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--profile", default="switch-sweep")
    ap.add_argument("--max-tabs", type=int, default=400)
    ap.add_argument("--no-restart", action="store_true")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    if d._running(d._paths(args.profile)["app_pid"]) is None:
        print(f"error: no app running for profile {args.profile}; start it first",
              file=sys.stderr)
        return 1

    seen: list[dict] = []
    fingerprints: set[tuple] = set()

    for i in range(args.max_tabs):
        _tab(args.profile)
        cur = _focused(args.profile)
        if cur is None:
            continue
        role, name, on, _raw = cur
        fp = (role, name)
        # Focus traversal wraps. Stopping on the first repeat would cut the sweep
        # short whenever two controls share a label, so require the whole cycle
        # to have gone quiet instead.
        if fp in fingerprints:
            if len(seen) and i > len(fingerprints) * 2:
                break
            continue
        fingerprints.add(fp)

        entry = {"role": role, "name": name, "before": on}
        if on is not None:
            _activate(args.profile)
            after = _focused(args.profile)
            entry["after"] = after[2] if after else None
            entry["toggled"] = entry["after"] is not None and entry["after"] != on
            if not entry["toggled"]:
                entry["defect"] = "activating the switch did not change its state"
        seen.append(entry)

    switches = [e for e in seen if e.get("before") is not None]
    dead = [e for e in switches if not e.get("toggled")]
    print(f"focusable visited: {len(seen)}  switches: {len(switches)}  "
          f"dead: {len(dead)}")

    if not args.no_restart and switches:
        expected = {e["name"]: e.get("after") for e in switches if e.get("toggled")}
        d.cmd_stop(argparse.Namespace(profile=args.profile))
        time.sleep(2)
        rc = d.cmd_start(argparse.Namespace(
            profile=args.profile, fresh=False, timeout=120,
            allow_shared_display=True))
        if rc != 0:
            print("error: app did not come back up after the toggles -- that is "
                  "itself a finding (a setting written during the sweep may be "
                  "unloadable)", file=sys.stderr)
            return 2
        time.sleep(5)
        app = d._atspi_root(args.profile)
        actual = {}
        if app:
            for _, _role, name, node in d._walk(app):
                try:
                    raw = {s.value_nick for s in node.get_state_set().get_states()}
                except Exception:
                    continue
                if "checkable" in raw:
                    actual[" ".join(dict.fromkeys(name.split()))] = "checked" in raw
        lost = {k: v for k, v in expected.items()
                if k in actual and actual[k] != v}
        for k, v in lost.items():
            print(f"NOT PERSISTED: {k!r} set to {v}, reads {actual[k]} after restart")
        print(f"persistence: {len(expected) - len(lost)}/{len(expected)} held")

    for e in dead:
        print(f"DEAD SWITCH: {e['name']!r} ({e['role']})")

    if args.out:
        Path(args.out).write_text(json.dumps(seen, indent=1))
        print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
