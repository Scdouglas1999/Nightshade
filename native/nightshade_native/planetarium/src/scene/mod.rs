//! Scene state and per-frame snapshots for Dart overlays.

pub mod snapshot;

pub use snapshot::{
    load, new_snapshot_slot, publish, LabelCategory, LabelHint, ObjectId, SceneSnapshot,
    SelectedObject, SmallString, SnapshotSlot,
};
