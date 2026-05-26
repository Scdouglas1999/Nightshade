//! GPU textures produced by Bruneton LUT precomputation.

use std::sync::Arc;

use thiserror::Error;
use wgpu::TextureFormat;

use super::constants::{
    IRRADIANCE_TEXTURE_HEIGHT, IRRADIANCE_TEXTURE_WIDTH, SCATTERING_TEXTURE_DEPTH,
    SCATTERING_TEXTURE_HEIGHT, SCATTERING_TEXTURE_WIDTH, TRANSMITTANCE_TEXTURE_HEIGHT,
    TRANSMITTANCE_TEXTURE_WIDTH,
};

/// Precompute failure (shader, device, or IO).
#[derive(Debug, Error)]
pub enum BrunetonPrecomputeError {
    /// wgpu rejected a resource or pass.
    #[error("wgpu Bruneton precompute: {0}")]
    Gpu(String),
}

/// Four Bruneton lookup textures for the atmosphere pass (design §5.3 / §8.1).
pub struct BrunetonLuts {
    /// 2D transmittance (256×64, RGBA16F).
    pub transmittance: wgpu::Texture,
    pub transmittance_view: wgpu::TextureView,
    /// 3D single scattering: Rayleigh RGB + single Mie in alpha (combined packing).
    pub single_scattering: wgpu::Texture,
    pub single_scattering_view: wgpu::TextureView,
    /// 3D multiple scattering (RGB).
    pub multiple_scattering: wgpu::Texture,
    pub multiple_scattering_view: wgpu::TextureView,
    /// 2D ground-sky irradiance (64×16, RGBA16F).
    pub irradiance: wgpu::Texture,
    pub irradiance_view: wgpu::TextureView,
    /// Internal combined scattering texture (kept for Task 53 atmosphere shader).
    pub(crate) combined_scattering: wgpu::Texture,
    pub(crate) combined_scattering_view: wgpu::TextureView,
}

impl BrunetonLuts {
    /// Bind group layout entries for atmosphere sampling (Task 53).
    #[must_use]
    pub fn bind_group_layout_entries() -> [wgpu::BindGroupLayoutEntry; 4] {
        [
            wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Texture {
                    sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    view_dimension: wgpu::TextureViewDimension::D2,
                    multisampled: false,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 1,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Texture {
                    sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    view_dimension: wgpu::TextureViewDimension::D3,
                    multisampled: false,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 2,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Texture {
                    sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    view_dimension: wgpu::TextureViewDimension::D3,
                    multisampled: false,
                },
                count: None,
            },
            wgpu::BindGroupLayoutEntry {
                binding: 3,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Texture {
                    sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    view_dimension: wgpu::TextureViewDimension::D2,
                    multisampled: false,
                },
                count: None,
            },
        ]
    }
}

pub(crate) fn transmittance_format() -> TextureFormat {
    TextureFormat::Rgba32Float
}

pub(crate) fn lut_format(half_precision: bool) -> TextureFormat {
    if half_precision {
        TextureFormat::Rgba16Float
    } else {
        TextureFormat::Rgba32Float
    }
}

pub(crate) fn create_texture_2d(
    device: &wgpu::Device,
    label: &str,
    width: u32,
    height: u32,
    format: TextureFormat,
) -> wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label: Some(label),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT
            | wgpu::TextureUsages::TEXTURE_BINDING
            | wgpu::TextureUsages::COPY_SRC
            | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    })
}

pub(crate) fn create_texture_3d(
    device: &wgpu::Device,
    label: &str,
    width: u32,
    height: u32,
    depth: u32,
    format: TextureFormat,
) -> wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label: Some(label),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: depth,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D3,
        format,
        usage: wgpu::TextureUsages::TEXTURE_BINDING
            | wgpu::TextureUsages::COPY_SRC
            | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    })
}

pub(crate) fn view_2d(texture: &wgpu::Texture) -> wgpu::TextureView {
    texture.create_view(&wgpu::TextureViewDescriptor::default())
}

pub(crate) fn view_3d(texture: &wgpu::Texture) -> wgpu::TextureView {
    texture.create_view(&wgpu::TextureViewDescriptor {
        dimension: Some(wgpu::TextureViewDimension::D3),
        ..Default::default()
    })
}

/// Read back a 2D RGBA32F texture (`width * height * 4` floats, tightly packed).
pub fn readback_texture_2d_rgba_f32(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
) -> Result<Vec<f32>, BrunetonPrecomputeError> {
    let bytes_per_pixel = 16u32;
    let row_bytes = width * bytes_per_pixel;
    let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
    let padded_row = row_bytes.div_ceil(align) * align;
    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("planetarium.bruneton.2d.readback"),
        size: (padded_row * height) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("planetarium.bruneton.2d.readback.encoder"),
    });
    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: &buffer,
            layout: wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(padded_row),
                rows_per_image: Some(height),
            },
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );
    queue.submit(std::iter::once(encoder.finish()));
    let slice = buffer.slice(..);
    let (tx, rx) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |r| {
        tx.send(r).expect("channel");
    });
    device.poll(wgpu::Maintain::Wait);
    rx.recv()
        .expect("recv")
        .map_err(|e| BrunetonPrecomputeError::Gpu(e.to_string()))?;
    let data = slice.get_mapped_range();
    let mut out = Vec::with_capacity((row_bytes * height / 4) as usize);
    for row in 0..height {
        let start = (row * padded_row) as usize;
        out.extend_from_slice(bytemuck::cast_slice(
            &data[start..start + row_bytes as usize],
        ));
    }
    drop(data);
    buffer.unmap();
    Ok(out)
}

/// Split combined scattering into single + multiple 3D textures (design four-LUT API).
pub(crate) fn split_combined_scattering(
    device: &Arc<wgpu::Device>,
    queue: &Arc<wgpu::Queue>,
    combined: &wgpu::Texture,
    format: TextureFormat,
) -> Result<(wgpu::Texture, wgpu::Texture), BrunetonPrecomputeError> {
    let combined_data = readback_texture_3d_rgba_f32(
        device,
        queue,
        combined,
        SCATTERING_TEXTURE_WIDTH,
        SCATTERING_TEXTURE_HEIGHT,
        SCATTERING_TEXTURE_DEPTH,
    )?;

    let voxel_count =
        (SCATTERING_TEXTURE_WIDTH * SCATTERING_TEXTURE_HEIGHT * SCATTERING_TEXTURE_DEPTH) as usize;
    let mut single = vec![0f32; voxel_count * 4];
    let mut multi = vec![0f32; voxel_count * 4];

    for i in 0..voxel_count {
        let base = i * 4;
        let r = combined_data[base];
        let g = combined_data[base + 1];
        let b = combined_data[base + 2];
        let a = combined_data[base + 3];
        single[base] = r;
        single[base + 1] = r;
        single[base + 2] = r;
        single[base + 3] = a;
        multi[base] = g;
        multi[base + 1] = g;
        multi[base + 2] = b;
        multi[base + 3] = 1.0;
    }

    let single_tex = upload_texture_3d(
        device,
        queue,
        "planetarium.bruneton.single_scattering",
        format,
        &single,
    )?;
    let multi_tex = upload_texture_3d(
        device,
        queue,
        "planetarium.bruneton.multiple_scattering",
        format,
        &multi,
    )?;
    Ok((single_tex, multi_tex))
}

fn upload_texture_3d(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    format: TextureFormat,
    data: &[f32],
) -> Result<wgpu::Texture, BrunetonPrecomputeError> {
    let texture = create_texture_3d(
        device,
        label,
        SCATTERING_TEXTURE_WIDTH,
        SCATTERING_TEXTURE_HEIGHT,
        SCATTERING_TEXTURE_DEPTH,
        format,
    );
    let bytes: &[u8] = bytemuck::cast_slice(data);
    queue.write_texture(
        wgpu::ImageCopyTexture {
            texture: &texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        bytes,
        wgpu::ImageDataLayout {
            offset: 0,
            bytes_per_row: Some(SCATTERING_TEXTURE_WIDTH * 16),
            rows_per_image: Some(SCATTERING_TEXTURE_HEIGHT),
        },
        wgpu::Extent3d {
            width: SCATTERING_TEXTURE_WIDTH,
            height: SCATTERING_TEXTURE_HEIGHT,
            depth_or_array_layers: SCATTERING_TEXTURE_DEPTH,
        },
    );
    Ok(texture)
}

fn readback_texture_3d_rgba_f32(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
    depth: u32,
) -> Result<Vec<f32>, BrunetonPrecomputeError> {
    let bytes_per_pixel = 16u32;
    let row_bytes = width * bytes_per_pixel;
    let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
    let padded_row = row_bytes.div_ceil(align) * align;
    let layer_bytes = padded_row * height;
    let total_bytes = layer_bytes * depth;

    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("planetarium.bruneton.3d.readback"),
        size: total_bytes as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("planetarium.bruneton.3d.readback.encoder"),
    });
    for layer in 0..depth {
        encoder.copy_texture_to_buffer(
            wgpu::ImageCopyTexture {
                texture,
                mip_level: 0,
                origin: wgpu::Origin3d {
                    x: 0,
                    y: 0,
                    z: layer,
                },
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::ImageCopyBuffer {
                buffer: &buffer,
                layout: wgpu::ImageDataLayout {
                    offset: (layer * layer_bytes) as u64,
                    bytes_per_row: Some(padded_row),
                    rows_per_image: Some(height),
                },
            },
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
        );
    }
    queue.submit(std::iter::once(encoder.finish()));

    let slice = buffer.slice(..);
    let (tx, rx) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |r| {
        tx.send(r).expect("readback channel");
    });
    device.poll(wgpu::Maintain::Wait);
    rx.recv()
        .expect("recv")
        .map_err(|e| BrunetonPrecomputeError::Gpu(e.to_string()))?;

    let data = slice.get_mapped_range();
    let mut out = Vec::with_capacity((width * height * depth * 4) as usize);
    for layer in 0..depth {
        for row in 0..height {
            let start = (layer * layer_bytes + row * padded_row) as usize;
            out.extend_from_slice(bytemuck::cast_slice(
                &data[start..start + row_bytes as usize],
            ));
        }
    }
    drop(data);
    buffer.unmap();
    Ok(out)
}
