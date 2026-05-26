//! Milky Way pass 2 — full-screen equirectangular intensity sampling (design §8.2).

use std::sync::Arc;

use bytemuck::{Pod, Zeroable};
use glam::{Mat4, Quat, Vec3};

use crate::catalog::{GALACTIC_CENTER_DEC_DEG, GALACTIC_CENTER_RA_DEG};
use crate::renderer::assets::upload_procedural_mw_texture;
use crate::renderer::Scene;
use crate::types::{RenderConfig, SkyProjection, ViewPose};

/// std140 uniform block for [`MwUniforms`].
///
/// Layout (WGSL std140, every column-major mat4x4 + vec2 keeps natural 8-byte alignment):
///   - `view_to_icrs`   mat4x4 → 64 bytes, offset  0
///   - `proj_scale`     vec2   →  8 bytes, offset 64
///   - `viewport_px`    vec2   →  8 bytes, offset 72  (placed adjacent so no inner pad)
///   - `sky_brightness` f32    →  4 bytes, offset 80
///   - `lp_factor`      f32    →  4 bytes, offset 84
///   - `mw_enabled`     f32    →  4 bytes, offset 88
///   - `_pad`           f32    →  4 bytes, offset 92  (rounds struct to 96, multiple of 16)
///
/// Total = 96 bytes. Field order MUST match `shaders/milky_way.wgsl::MwUniforms` exactly;
/// re-ordering vec2 to sit after a stray f32 introduces silent 4-byte misalignment.
const MW_UNIFORM_SIZE: u64 = 96;

/// Golden-image render size (galactic-center boresight).
pub const MW_GOLDEN_SIZE: u32 = 256;

/// WGSL `MwUniforms` (std140). Field order MUST match `shaders/milky_way.wgsl`.
#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
struct MwUniforms {
    view_to_icrs: [[f32; 4]; 4],
    proj_scale: [f32; 2],
    viewport_pixels: [f32; 2],
    sky_brightness: f32,
    lp_factor: f32,
    mw_enabled: f32,
    _pad: f32,
}

/// wgpu pipeline for the MW intensity pass.
pub struct MilkyWayPipeline {
    pipeline: wgpu::RenderPipeline,
    uniform_buf: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    queue: Arc<wgpu::Queue>,
    format: wgpu::TextureFormat,
}

impl MilkyWayPipeline {
    /// Build the MW pass and upload the procedural intensity map.
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
    ) -> Self {
        let mw = upload_procedural_mw_texture(&device, &queue)
            .expect("procedural MW texture upload must succeed");

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("milky_way.shader"),
            source: wgpu::ShaderSource::Wgsl(
                include_str!("../../../shaders/milky_way.wgsl").into(),
            ),
        });

        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("milky_way.sampler"),
            address_mode_u: wgpu::AddressMode::Repeat,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("milky_way.bind_group_layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                        view_dimension: wgpu::TextureViewDimension::D2,
                        multisampled: false,
                    },
                    count: None,
                },
            ],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("milky_way.pipeline_layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("milky_way.pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "vs_main",
                compilation_options: Default::default(),
                buffers: &[],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "fs_main",
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    // Fragment outputs premultiplied alpha (`rgb * alpha`, `alpha`), so the
                    // blend factors are (1, 1-srcA). `ALPHA_BLENDING` is for straight alpha
                    // and would double-multiply RGB by source alpha.
                    blend: Some(wgpu::BlendState::PREMULTIPLIED_ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                ..Default::default()
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });

        let uniform_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("milky_way.uniform"),
            size: MW_UNIFORM_SIZE,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("milky_way.bind_group"),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: uniform_buf.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(mw.view()),
                },
            ],
        });

        Self {
            pipeline,
            uniform_buf,
            bind_group,
            queue,
            format: target_format,
        }
    }

    /// Draw the MW layer into an active render pass (pass 2).
    pub fn draw<'a>(
        &'a self,
        pass: &mut wgpu::RenderPass<'a>,
        scene: &Scene,
        width: u32,
        height: u32,
    ) {
        if !scene.config.show_milky_way {
            return;
        }

        let uniforms = build_uniforms(scene, width, height);
        self.queue
            .write_buffer(&self.uniform_buf, 0, bytemuck::bytes_of(&uniforms));

        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &self.bind_group, &[]);
        pass.draw(0..3, 0..1);
    }

    /// Target format this pipeline was created for.
    pub fn format(&self) -> wgpu::TextureFormat {
        self.format
    }
}

/// View pose for golden image: boresight on the galactic center, 90° FOV.
#[must_use]
pub fn mw_galactic_center_view_pose() -> ViewPose {
    ViewPose {
        ra_rad: GALACTIC_CENTER_RA_DEG.to_radians(),
        dec_rad: GALACTIC_CENTER_DEC_DEG.to_radians(),
        fov_rad: 90.0_f32.to_radians(),
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    }
}

/// Scene for MW golden / smoke: only the galactic band visible on black.
#[must_use]
pub fn mw_galactic_center_scene() -> Scene {
    Scene {
        view_pose: mw_galactic_center_view_pose(),
        config: RenderConfig {
            show_stars: false,
            show_constellations: false,
            show_ecliptic: false,
            show_milky_way: true,
            show_horizon: false,
            show_atmosphere: false,
            show_dsos: false,
            show_solar_system: false,
            bortle_class: 0,
            twinkle: false,
            ..RenderConfig::default()
        },
        stars: Vec::new(),
        ..Scene::default()
    }
}

/// Render the MW golden frame to RGBA8 bytes.
pub fn render_mw_golden_rgba() -> Vec<u8> {
    pollster::block_on(async {
        let (device, queue) = crate::renderer::offscreen_device().await;
        let format = wgpu::TextureFormat::Rgba8UnormSrgb;
        let mut renderer =
            crate::renderer::Renderer::new(device, queue, format, MW_GOLDEN_SIZE, MW_GOLDEN_SIZE);
        renderer.render(&mw_galactic_center_scene());
        renderer.readback_rgba()
    })
}

/// Sky brightness factor for MW fade (0 = night, 1 = full daylight).
///
/// **Atmosphere is not yet wired** (Task 51-53, Bruneton precompute). Until that lands
/// this returns 0.0 in both branches — see [`crate::renderer::bruneton`] when it is
/// gated behind the `bruneton-precompute` feature. Once the atmosphere pass exists,
/// it must publish the per-frame sky luminance and this function should consume it
/// instead of always returning 0.
#[must_use]
pub fn mw_sky_brightness_factor(_config: &RenderConfig) -> f32 {
    // No silent fallback: the value is intentionally the night value. The branch on
    // `show_atmosphere` was removed because both arms returned the same value, which
    // hid a stub — explicit constant is honest until Bruneton lands.
    0.0
}

/// Light-pollution wash multiplier from Bortle class (0 = no LP dome).
#[must_use]
pub fn mw_lp_factor(bortle_class: u32) -> f32 {
    if bortle_class == 0 {
        return 1.0;
    }
    let b = (bortle_class.min(9) as f32) / 9.0;
    (1.0 - b * 0.65).clamp(0.2, 1.0)
}

/// Count pixels with MW glow (non-black RGB; readback uses opaque black alpha).
#[must_use]
pub fn count_mw_visible_pixels(rgba: &[u8], luma_threshold: u8) -> usize {
    rgba.chunks_exact(4)
        .filter(|p| {
            let luma = (u16::from(p[0]) + u16::from(p[1]) + u16::from(p[2])) / 3;
            luma > u16::from(luma_threshold)
        })
        .count()
}

fn build_uniforms(scene: &Scene, width: u32, height: u32) -> MwUniforms {
    let pose = &scene.view_pose;
    let view_to_icrs = icrs_to_view_matrix(pose).inverse();
    MwUniforms {
        view_to_icrs: view_to_icrs.to_cols_array_2d(),
        proj_scale: stereographic_proj_scale(pose),
        viewport_pixels: [width as f32, height as f32],
        sky_brightness: mw_sky_brightness_factor(&scene.config),
        lp_factor: mw_lp_factor(scene.config.bortle_class),
        mw_enabled: if scene.config.show_milky_way {
            1.0
        } else {
            0.0
        },
        _pad: 0.0,
    }
}

fn icrs_to_view_matrix(pose: &ViewPose) -> Mat4 {
    let center = icrs_dir_vec3(pose.ra_rad, pose.dec_rad);
    let from = center.normalize_or_zero();
    let align = if from.length_squared() > f32::EPSILON {
        Mat4::from_quat(Quat::from_rotation_arc(from, Vec3::Z))
    } else {
        Mat4::IDENTITY
    };
    let roll = Mat4::from_rotation_z(-pose.roll_rad);
    roll * align
}

fn stereographic_proj_scale(pose: &ViewPose) -> [f32; 2] {
    let half_fov = pose.fov_rad * 0.5;
    let edge_r = match pose.projection {
        SkyProjection::Stereographic => 2.0 * (half_fov * 0.5).tan(),
        SkyProjection::Orthographic => half_fov.sin(),
        SkyProjection::AzimuthalEquidistant => half_fov,
    };
    let scale = if edge_r > f32::EPSILON {
        1.0 / edge_r
    } else {
        1.0
    };
    [2.0 * scale, 2.0 * scale]
}

fn icrs_dir_vec3(ra_rad: f64, dec_rad: f64) -> Vec3 {
    let (sin_dec, cos_dec) = dec_rad.sin_cos();
    let (sin_ra, cos_ra) = ra_rad.sin_cos();
    Vec3::new(
        (cos_dec * cos_ra) as f32,
        (cos_dec * sin_ra) as f32,
        sin_dec as f32,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mw_uniforms_struct_matches_wgsl_std140_size() {
        assert_eq!(std::mem::size_of::<MwUniforms>() as u64, MW_UNIFORM_SIZE);
    }

    #[test]
    fn galactic_center_scene_enables_mw_only() {
        let scene = mw_galactic_center_scene();
        assert!(scene.config.show_milky_way);
        assert!(!scene.config.show_stars);
        assert!(scene.stars.is_empty());
    }

    #[test]
    fn lp_factor_no_bortle_is_full_strength() {
        assert!((mw_lp_factor(0) - 1.0).abs() < f32::EPSILON);
        assert!(mw_lp_factor(9) < mw_lp_factor(1));
    }

    #[test]
    fn mw_golden_frame_has_visible_band_pixels() {
        let rgba = render_mw_golden_rgba();
        assert_eq!(rgba.len(), (MW_GOLDEN_SIZE * MW_GOLDEN_SIZE * 4) as usize);
        let visible = count_mw_visible_pixels(&rgba, 8);
        assert!(
            visible > 500,
            "expected MW band pixels, got {visible} above alpha threshold"
        );
    }

    #[test]
    fn mw_disabled_scene_is_black() {
        let mut scene = mw_galactic_center_scene();
        scene.config.show_milky_way = false;
        let rgba = pollster::block_on(async {
            let (device, queue) = crate::renderer::offscreen_device().await;
            let mut renderer = crate::renderer::Renderer::new(
                device,
                queue,
                wgpu::TextureFormat::Rgba8UnormSrgb,
                MW_GOLDEN_SIZE,
                MW_GOLDEN_SIZE,
            );
            renderer.render(&scene);
            renderer.readback_rgba()
        });
        assert_eq!(count_mw_visible_pixels(&rgba, 4), 0);
    }
}
