//! Wire-contract pin for the Dart-produced `SequenceDefinition` document.
//!
//! `sequencerLoadJson` (bridge `api_sequencer_load_json`) is a plain
//! `serde_json::from_str::<SequenceDefinition>`: whatever the Dart side emits
//! must satisfy this crate's serde schema exactly. Live-rig finding L8 showed
//! the Dart headless test fixture had drifted — it omitted `priority`,
//! `count` and `binning` and spelled `duration_secs` as `duration`, so every
//! "wire validation" test exercised a document the executor would reject
//! outright.
//!
//! The canonical document below is the same tree the Dart fixture emits
//! (`apps/desktop/test/headless_api/sequencer_wire_validation_test.dart`
//! `wireSequence`), which in turn mirrors the real producer
//! (`SequenceSerializer._nodeToConfig`). Keep all three in sync when the wire
//! schema changes: a new non-`#[serde(default)]` field on a config struct used
//! here must be added to this document AND to the Dart fixture, or the
//! contract is only half pinned.

use nightshade_sequencer::{Binning, NodeType, SequenceDefinition};

/// The canonical minimal sequence: one Loop wrapping one TargetHeader wrapping
/// one TakeExposure — the shape `POST /api/sequencer/load` receives from a
/// remote client building a simple capture run.
fn canonical_wire_document() -> serde_json::Value {
    serde_json::json!({
        "id": "seq-1",
        "name": "Remote run",
        "description": "",
        "root_node_id": "root",
        "metadata": {},
        "nodes": [
            {
                "id": "root",
                "name": "Sequence",
                "node_type": {
                    "type": "Loop",
                    "iterations": 1,
                    "condition": "Count",
                    "condition_value": 1,
                },
                "enabled": true,
                "children": ["target"],
            },
            {
                "id": "target",
                "name": "M31",
                "node_type": {
                    "type": "TargetHeader",
                    "target_name": "M31",
                    "ra_hours": 0.712,
                    "dec_degrees": 41.27,
                    "rotation": null,
                    "min_altitude": null,
                    "max_altitude": null,
                    "priority": 0,
                    "start_after": null,
                    "end_before": null,
                    "mosaic_panel": null,
                    "brightness_tier_hint": null,
                    "start_when": null,
                    "end_when": null,
                    "trigger_poll_interval_secs": 30,
                    "integration_budget": null,
                },
                "enabled": true,
                "children": ["expose"],
            },
            {
                "id": "expose",
                "name": "Take Exposure",
                "node_type": {
                    "type": "TakeExposure",
                    "duration_secs": 60.0,
                    "count": 1,
                    "frame_type": "Light",
                    "filter": null,
                    "filter_index": null,
                    "gain": null,
                    "offset": null,
                    "binning": "One",
                    "dither_every": null,
                    "dither_pixels": 5.0,
                    "dither_settle_pixels": 1.5,
                    "dither_settle_time": 10.0,
                    "dither_settle_timeout": 60.0,
                    "dither_ra_only": false,
                    "save_to": null,
                    "triggers": [],
                    "adaptive_exposure": null,
                },
                "enabled": true,
                "children": [],
            },
        ],
    })
}

#[test]
fn the_dart_fixture_document_deserializes() {
    let definition: SequenceDefinition = serde_json::from_value(canonical_wire_document())
        .expect("the canonical Dart wire document must deserialize");

    assert_eq!(definition.id, "seq-1");
    assert_eq!(definition.nodes.len(), 3);

    let NodeType::TargetHeader(target) = &definition.nodes[1].node_type else {
        panic!("node[1] must be a TargetHeader");
    };
    assert_eq!(target.target_name, "M31");
    assert_eq!(target.priority, 0);

    // The L8 traps specifically: `duration_secs` (not `duration`), `count`,
    // and `binning` as the bare externally-tagged string (not an {x,y} map).
    let NodeType::TakeExposure(exposure) = &definition.nodes[2].node_type else {
        panic!("node[2] must be a TakeExposure");
    };
    assert_eq!(exposure.duration_secs, 60.0);
    assert_eq!(exposure.count, 1);
    assert_eq!(exposure.binning, Binning::One);
    assert_eq!(exposure.frame_type, "Light");
}
