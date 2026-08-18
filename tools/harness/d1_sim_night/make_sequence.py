#!/usr/bin/env python3
"""Builds the D1 sim-night sequence envelope: {"json": "<stringified SequenceDefinition>"}.

Wire shape per sequence_serializer.dart:301-329 and sequencer/src/lib.rs
(SequenceDefinition:146, NodeDefinition:174, NodeType tag="type":191,
TargetHeaderConfig:1220, LoopConfig:1692, FilterConfig:2279). Optional keys
with serde(default) are omitted; required ones are stated.
"""
import json, sys, time, math

FILTERS = ["L", "R", "G", "B"]

def site(unix=None):
    """The harness observing site: lat 40N, longitude chosen so it is 01:00
    LOCAL SOLAR TIME at the site right now.

    A fixed longitude put the site wherever the wall clock happened to be: a
    Phase D wave running at ~04:00 UTC landed 40N/105W inside the
    DawnApproaching trigger's lead window, and the trigger — behaving
    correctly for that site — parked a run the harness then failed as its
    own. Solar 01:00 keeps every run mid-night at its site whatever hour the
    harness fires, with the whole night ahead of it before any dawn logic
    can arm."""
    unix = time.time() if unix is None else unix
    utc_hours = (unix / 3600.0) % 24.0
    lon = (1.0 - utc_hours) * 15.0
    lon = ((lon + 180.0) % 360.0) - 180.0
    return 40.0, round(lon, 4)

SITE_LAT, SITE_LON = site()

# The shell legs POST the observer location before they build the sequence;
# printing the pair here keeps them and the sequence on ONE site.
if len(sys.argv) > 1 and sys.argv[1] == "--print-site":
    print(f"{SITE_LAT} {SITE_LON}")
    sys.exit(0)

def lst_hours(unix, lon_deg):
    jd = unix / 86400.0 + 2440587.5
    d = jd - 2451545.0
    gmst = (18.697374558 + 24.06570982441908 * d) % 24.0
    return (gmst + lon_deg / 15.0) % 24.0

# High-and-east target: 1.5h east of the meridian at dec=latitude — altitude
# ~75 degrees (clears any altitude gate) while transit stays 1.5h away, so
# the meridian-flip window can never fire during a short harness night.
# (RA == LST put the target AT transit: every run rolled dice with the flip
# window, and a fired flip pauses on the unsolvable simulator field.)
ZENITH_RA = round((lst_hours(time.time(), SITE_LON) + 1.5) % 24.0, 4)
ZENITH_DEC = SITE_LAT

def exposure(fid, filt, idx):
    return {
        "id": fid,
        "name": f"Exposure {filt}",
        "node_type": {
            "type": "TakeExposure",
            "duration_secs": 2.0,
            "count": 3,
            "frame_type": "Light",
            "filter": filt,
            "filter_index": idx,
            "gain": 100,
            "offset": 10,
            "binning": "One",
        },
        "enabled": True,
        "children": [],
    }

def change_filter(fid, filt, idx):
    return {
        "id": fid,
        "name": f"Filter {filt}",
        "node_type": {"type": "ChangeFilter", "filter_name": filt, "filter_index": idx},
        "enabled": True,
        "children": [],
    }

nodes = []
target_children = []
for i, f in enumerate(FILTERS):
    cf, ex = f"cf_{f.lower()}", f"exp_{f.lower()}"
    nodes.append(change_filter(cf, f, i))
    nodes.append(exposure(ex, f, i))
    target_children += [cf, ex]

nodes.insert(0, {
    "id": "target_1",
    "name": "D1 Simulated Field",
    "node_type": {
        "type": "TargetHeader",
        "target_name": "D1 Simulated Field",
        "ra_hours": ZENITH_RA,
        "dec_degrees": ZENITH_DEC,
        "rotation": None,
        "priority": 0,
    },
    "enabled": True,
    "children": target_children,
})
nodes.insert(0, {
    "id": "root",
    "name": "Night root",
    "node_type": {"type": "Loop", "iterations": 1, "condition": "Count", "condition_value": None},
    "enabled": True,
    "children": ["target_1"],
})

definition = {
    "id": "d1-sim-night",
    "name": "D1 sim night",
    "description": "Phase D leg-1 harness sequence",
    "root_node_id": "root",
    "nodes": nodes,
    "metadata": {},
}

envelope = {"json": json.dumps(definition)}
with open(sys.argv[1], "w") as fh:
    json.dump(envelope, fh)
print(f"wrote {sys.argv[1]}: {len(nodes)} nodes, {sum(1 for n in nodes if n['node_type']['type']=='TakeExposure')*3} frames")
