//! Bundled GPU assets (Bruneton LUTs, Milky Way intensity map, …).

pub mod mw;

pub use mw::{
    load_bundled_mw_texture, load_mw_texture, load_mw_texture_from_bytes,
    load_mw_texture_from_map, upload_procedural_mw_texture, MilkyWayTexture, MwTextureError,
};
