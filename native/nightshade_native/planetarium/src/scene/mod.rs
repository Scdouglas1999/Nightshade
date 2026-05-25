//! Scene state and per-frame snapshots for Dart overlays.

pub mod dev_catalog;
pub mod projection;
pub mod publish;
pub mod snapshot;
pub mod visibility;

pub use projection::{project_icrs, unproject_icrs};
pub use visibility::{frustum_cap_radius_rad, visible_tiles, HealpixTileId};
pub use publish::{build_snapshot, publish_snapshot, SnapshotInputs};
pub use snapshot::{
    load, new_snapshot_slot, publish, LabelCategory, LabelHint, ObjectId, SceneSnapshot,
    SelectedObject, SmallString, SnapshotSlot,
};
