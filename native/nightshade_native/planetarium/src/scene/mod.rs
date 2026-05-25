//! Scene state and per-frame snapshots for Dart overlays.

pub mod build;
pub mod dev_catalog;
pub mod lod;
pub mod pose;
pub mod projection;
pub mod publish;
pub mod snapshot;
pub mod visibility;

pub use build::{build_render_scene, collect_star_instances, star_instance_from_record, BuildSceneInputs};
pub use lod::{
    fov_zoom_mag_boost, frame_star_mag_limit, select_lod, tile_star_mag_limit, LodSelection,
    MagLimitConfig, QualityConfig, FOV_MAG_BOOST_CAP, REF_FOV_DEG, STAR_MAG_CEILING, STAR_MAG_FLOOR,
};
pub use pose::{
    body_equatorial_rad, BodyId, MountPosition, PoseController, PoseError, PoseInputs, PoseLock,
    PoseOffset, TrackingTarget,
};
pub use projection::{project_icrs, unproject_icrs};
pub use visibility::{frustum_cap_radius_rad, visible_tiles, HealpixTileId};
pub use publish::{build_snapshot, publish_snapshot, SnapshotInputs};
pub use snapshot::{
    load, new_snapshot_slot, publish, ConstellationArtPlacement, LabelCategory, LabelHint,
    ObjectId, SceneSnapshot, SelectedObject, SmallString, SnapshotSlot,
};
