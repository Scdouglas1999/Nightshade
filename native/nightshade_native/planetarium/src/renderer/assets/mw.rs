//! Load the bundled Milky Way intensity map into a `wgpu` texture.

use std::path::Path;
use std::sync::Arc;

use thiserror::Error;
use wgpu::util::DeviceExt;

use crate::catalog::{
    default_mw_asset_path, load_milky_way_map, parse_milky_way_map, MilkyWayError, MilkyWayMap,
    MILKY_WAY_FORMAT_R8,
};

/// Errors while loading or uploading the MW GPU texture.
#[derive(Debug, Error)]
pub enum MwTextureError {
    /// Catalog parse or file I/O failed.
    #[error(transparent)]
    Map(#[from] MilkyWayError),
    /// wgpu rejected the upload or texture creation.
    #[error("wgpu Milky Way texture: {0}")]
    Gpu(String),
}

/// GPU texture + view for the MW equirectangular intensity map (pass 2).
pub struct MilkyWayTexture {
    texture: wgpu::Texture,
    view: wgpu::TextureView,
    width: u32,
    height: u32,
}

impl MilkyWayTexture {
    /// Underlying `wgpu` texture.
    #[must_use]
    pub fn texture(&self) -> &wgpu::Texture {
        &self.texture
    }

    /// Shader bind view.
    #[must_use]
    pub fn view(&self) -> &wgpu::TextureView {
        &self.view
    }

    /// Raster width in pixels.
    #[must_use]
    pub fn width(&self) -> u32 {
        self.width
    }

    /// Raster height in pixels.
    #[must_use]
    pub fn height(&self) -> u32 {
        self.height
    }
}

/// Read `path` and upload the MW intensity map to the GPU.
pub fn load_mw_texture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    path: impl AsRef<Path>,
) -> Result<MilkyWayTexture, MwTextureError> {
    let map = load_milky_way_map(path)?;
    load_mw_texture_from_map(device, queue, &map)
}

/// Load from the default desktop bundle path under `repo_root`.
pub fn load_bundled_mw_texture(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    repo_root: impl AsRef<Path>,
) -> Result<MilkyWayTexture, MwTextureError> {
    load_mw_texture(device, queue, default_mw_asset_path(repo_root))
}

/// Upload a parsed [`MilkyWayMap`] as an `R8Unorm` texture.
pub fn load_mw_texture_from_map(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    map: &MilkyWayMap,
) -> Result<MilkyWayTexture, MwTextureError> {
    if map.header.format != MILKY_WAY_FORMAT_R8 {
        return Err(MwTextureError::Map(MilkyWayError::UnsupportedHeader {
            detail: format!("format {}", map.header.format),
        }));
    }
    let width = map.header.width;
    let height = map.header.height;
    let expected = (width as usize) * (height as usize);
    if map.pixels.len() != expected {
        return Err(MwTextureError::Map(MilkyWayError::SizeMismatch {
            expected: expected + crate::catalog::MILKY_WAY_HEADER_LEN,
            actual: map.pixels.len() + crate::catalog::MILKY_WAY_HEADER_LEN,
        }));
    }

    let texture = device.create_texture_with_data(
        queue,
        &wgpu::TextureDescriptor {
            label: Some("planetarium.mw.intensity"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::R8Unorm,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        },
        wgpu::util::TextureDataOrder::LayerMajor,
        &map.pixels,
    );

    let view = texture.create_view(&wgpu::TextureViewDescriptor {
        label: Some("planetarium.mw.intensity.view"),
        format: Some(wgpu::TextureFormat::R8Unorm),
        dimension: Some(wgpu::TextureViewDimension::D2),
        aspect: wgpu::TextureAspect::All,
        base_mip_level: 0,
        mip_level_count: None,
        base_array_layer: 0,
        array_layer_count: None,
    });

    Ok(MilkyWayTexture {
        texture,
        view,
        width,
        height,
    })
}

/// Convenience for tests: build in memory, upload without touching disk.
pub fn upload_procedural_mw_texture(
    device: &Arc<wgpu::Device>,
    queue: &Arc<wgpu::Queue>,
) -> Result<MilkyWayTexture, MwTextureError> {
    let map = crate::catalog::build_milky_way_map();
    load_mw_texture_from_map(device, queue, &map)
}

/// Parse raw bytes and upload (used when the asset is embedded or read from Flutter assets).
pub fn load_mw_texture_from_bytes(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    bytes: &[u8],
) -> Result<MilkyWayTexture, MwTextureError> {
    let map = parse_milky_way_map(bytes)?;
    load_mw_texture_from_map(device, queue, &map)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::{
        build_milky_way_map, encode_milky_way_map, GALACTIC_CENTER_DEC_DEG, GALACTIC_CENTER_RA_DEG,
        MILKY_WAY_FILE_LEN, MILKY_WAY_HEIGHT, MILKY_WAY_WIDTH,
    };
    use crate::renderer::offscreen_device;

    #[test]
    fn upload_procedural_map_matches_dimensions() {
        let (device, queue) = pollster::block_on(offscreen_device());
        let tex = upload_procedural_mw_texture(&device, &queue).expect("upload MW");
        assert_eq!(tex.width(), MILKY_WAY_WIDTH);
        assert_eq!(tex.height(), MILKY_WAY_HEIGHT);
    }

    #[test]
    fn roundtrip_bytes_upload() {
        let map = build_milky_way_map();
        let bytes = encode_milky_way_map(&map);
        assert_eq!(bytes.len(), MILKY_WAY_FILE_LEN);

        let (device, queue) = pollster::block_on(offscreen_device());
        let tex = load_mw_texture_from_bytes(&device, &queue, &bytes).expect("upload from bytes");
        assert_eq!(tex.width(), MILKY_WAY_WIDTH);
    }

    #[test]
    fn galactic_center_pixel_is_bright() {
        let map = build_milky_way_map();
        let intensity =
            map.intensity_at_equatorial_deg(GALACTIC_CENTER_RA_DEG, GALACTIC_CENTER_DEC_DEG);
        assert!(
            intensity > 0.5,
            "galactic center intensity {intensity} should be bright"
        );
    }
}
