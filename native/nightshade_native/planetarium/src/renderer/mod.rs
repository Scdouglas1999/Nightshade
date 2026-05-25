//! wgpu renderer entry point and per-frame scene state.
//!
//! [`Renderer`] owns the render target and drives [`graph::FrameGraph`] each frame.

mod graph;
mod pipelines;

use std::sync::Arc;

pub use graph::{FrameGraph, RenderPassId};
pub use pipelines::stars::{
    magnitude_to_tone, psf_radius_px, psf_zoom_factor_from_fov_rad, render_scene_rgba,
    render_three_stars_rgba, star_altitude_rad, three_star_instances, three_stars_scene,
    three_stars_twinkle_scene, three_stars_view_pose, twinkle_altitude_gate,
    twinkle_brightness_delta, twinkle_enabled, StarInstance, StarsPipeline, THREE_STARS_SIZE,
};

use crate::types::{AstroTime, Observer, RenderConfig, ViewPose};

/// Clear color for pass 0 (design §5.1 — black sky before atmosphere overwrites).
pub const FRAME_CLEAR: wgpu::Color = wgpu::Color {
    r: 0.0,
    g: 0.0,
    b: 0.0,
    a: 1.0,
};

/// Render-thread scene inputs consumed by the frame graph.
#[derive(Debug, Clone, PartialEq)]
pub struct Scene {
    /// Where the camera looks on the celestial sphere.
    pub view_pose: ViewPose,
    /// Layer visibility and quality knobs.
    pub config: RenderConfig,
    /// GPU star instances for the current frame (may be empty).
    pub stars: Vec<StarInstance>,
    /// Observer for horizontal altitude (twinkle / extinction).
    pub observer: Observer,
    /// Epoch for the frame chain.
    pub astro_time: AstroTime,
    /// Twinkle animation phase in radians (`AnimationState::twinkle_phase`).
    pub twinkle_phase: f32,
}

impl Default for Scene {
    fn default() -> Self {
        Self {
            view_pose: ViewPose::default(),
            config: RenderConfig::default(),
            stars: Vec::new(),
            observer: Observer::default(),
            astro_time: AstroTime::from_jd_utc(crate::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC),
            twinkle_phase: 0.0,
        }
    }
}

/// GPU renderer: device-owned target texture and frame graph execution.
pub struct Renderer {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    target: wgpu::Texture,
    target_view: wgpu::TextureView,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
    stars: StarsPipeline,
    star_instance_buf: wgpu::Buffer,
    star_instance_count: u32,
}

impl Renderer {
    /// Build renderer state for an offscreen or surface-backed target.
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        format: wgpu::TextureFormat,
        width: u32,
        height: u32,
    ) -> Self {
        let target = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("planetarium.renderer.target"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let target_view = target.create_view(&wgpu::TextureViewDescriptor::default());

        let stars = StarsPipeline::new(device.clone(), queue.clone(), format);
        let star_instance_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("planetarium.stars.instances"),
            size: 4,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        Self {
            device,
            queue,
            target,
            target_view,
            width,
            height,
            format,
            stars,
            star_instance_buf,
            star_instance_count: 0,
        }
    }

    /// Target width in pixels.
    pub fn width(&self) -> u32 {
        self.width
    }

    /// Target height in pixels.
    pub fn height(&self) -> u32 {
        self.height
    }

    /// Color attachment format.
    pub fn format(&self) -> wgpu::TextureFormat {
        self.format
    }

    /// Shared wgpu device.
    pub fn device(&self) -> &Arc<wgpu::Device> {
        &self.device
    }

    /// Shared wgpu queue.
    pub fn queue(&self) -> &Arc<wgpu::Queue> {
        &self.queue
    }

    /// Run the frame graph for `scene` into the internal render target.
    pub fn render(&mut self, scene: &Scene) {
        self.upload_star_instances(scene);

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("planetarium.renderer.encoder"),
        });
        FrameGraph::render(
            &mut encoder,
            &self.target_view,
            scene,
            &self.stars,
            &self.star_instance_buf,
            self.star_instance_count,
            self.width,
            self.height,
        );
        self.queue.submit(std::iter::once(encoder.finish()));
        self.device.poll(wgpu::Maintain::Wait);
    }

    fn upload_star_instances(&mut self, scene: &Scene) {
        let count = scene.stars.len();
        if count == 0 {
            self.star_instance_count = 0;
            return;
        }
        let byte_len = (count * std::mem::size_of::<StarInstance>()) as u64;
        if self.star_instance_buf.size() < byte_len {
            self.star_instance_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("planetarium.stars.instances"),
                size: byte_len,
                usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
        }
        self.queue
            .write_buffer(&self.star_instance_buf, 0, bytemuck::cast_slice(&scene.stars));
        self.star_instance_count = count as u32;
    }

    /// Read back RGBA8 pixels from the internal target (`width * height * 4` bytes).
    pub fn readback_rgba(&self) -> Vec<u8> {
        readback_rgba(
            &self.device,
            &self.queue,
            &self.target,
            self.width,
            self.height,
        )
    }
}

/// Copy a render-target texture to tightly packed RGBA8 bytes.
pub fn readback_rgba(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    target: &wgpu::Texture,
    width: u32,
    height: u32,
) -> Vec<u8> {
    let bytes_per_pixel = 4u32;
    let unpadded_bpr = width * bytes_per_pixel;
    let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
    let padded_bpr = unpadded_bpr.div_ceil(align) * align;
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("planetarium.readback"),
        size: (padded_bpr * height) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("planetarium.readback.encoder"),
    });
    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture: target,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: &readback,
            layout: wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(padded_bpr),
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

    let (tx, rx) = std::sync::mpsc::channel();
    readback.slice(..).map_async(wgpu::MapMode::Read, move |r| {
        tx.send(r).expect("readback channel closed");
    });
    device.poll(wgpu::Maintain::Wait);
    rx.recv().expect("readback recv").expect("readback map failed");

    let data = readback.slice(..).get_mapped_range();
    let mut out = Vec::with_capacity((unpadded_bpr * height) as usize);
    for row in 0..height {
        let start = (row * padded_bpr) as usize;
        out.extend_from_slice(&data[start..start + unpadded_bpr as usize]);
    }
    drop(data);
    readback.unmap();
    out
}

/// Render an empty [`Scene`] to a headless target and return RGBA8 pixels.
pub fn render_empty_scene_rgba(width: u32, height: u32) -> Vec<u8> {
    pollster::block_on(async {
        let (device, queue) = offscreen_device().await;
        let mut renderer = Renderer::new(
            device,
            queue,
            wgpu::TextureFormat::Rgba8UnormSrgb,
            width,
            height,
        );
        renderer.render(&Scene::default());
        renderer.readback_rgba()
    })
}

/// Headless offscreen wgpu device for tests (Vulkan/DX12/Metal via default instance).
pub async fn offscreen_device() -> (Arc<wgpu::Device>, Arc<wgpu::Queue>) {
    let instance = wgpu::Instance::default();
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        })
        .await
        .expect("no GPU adapter available — wgpu cannot proceed");

    let (device, queue) = adapter
        .request_device(&wgpu::DeviceDescriptor::default(), None)
        .await
        .expect("device request failed");

    (Arc::new(device), Arc::new(queue))
}
