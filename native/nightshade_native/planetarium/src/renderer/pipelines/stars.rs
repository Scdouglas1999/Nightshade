//! Instanced star quads (design §5.2).
//!
//! PSF screen size and tone mapping match the v1 Dart planetarium
//! (`SkyRenderer._magnitudeToRadius` / `_magnitudeToBrightness`).

use std::sync::Arc;

use bytemuck::{Pod, Zeroable};
use glam::{Mat4, Quat, Vec3};

use crate::renderer::Scene;
use crate::scene::dev_catalog::{DevStar, DEV_STARS};
use crate::types::{SkyProjection, ViewPose};

/// Per-star GPU instance (matches WGSL instance layout).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Pod, Zeroable)]
pub struct StarInstance {
    /// Unit vector in ICRS (J2000).
    pub icrs_dir: [f32; 3],
    /// Apparent V magnitude.
    pub mag: f32,
    /// B−V color index; use `f32::NAN` when unknown.
    pub bv: f32,
    /// Bit flags (variable, double, …).
    pub flags: u32,
}

/// Unit quad corners (two triangles) expanded per instance in the vertex shader.
#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
struct QuadVertex {
    corner: [f32; 2],
}

const QUAD_VERTICES: &[QuadVertex] = &[
    QuadVertex { corner: [-1.0, -1.0] },
    QuadVertex { corner: [1.0, -1.0] },
    QuadVertex { corner: [-1.0, 1.0] },
    QuadVertex { corner: [1.0, -1.0] },
    QuadVertex { corner: [1.0, 1.0] },
    QuadVertex { corner: [-1.0, 1.0] },
];

#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
struct StarUniforms {
    icrs_to_view: [[f32; 4]; 4],
    proj_scale: [f32; 2],
    mag_limit: f32,
    psf_scale: f32,
    twinkle_seed: f32,
    viewport_pixels: [f32; 2],
}

/// Reference FOV in degrees for zoom scaling (v1 `viewState.fieldOfView` baseline).
const REFERENCE_FOV_DEG: f32 = 90.0;

/// Golden-image render size for the three-star regression.
pub const THREE_STARS_SIZE: u32 = 256;

/// Zoom factor applied to tiered PSF base radius from field of view (v1).
#[must_use]
pub fn psf_zoom_factor_from_fov_rad(fov_rad: f32) -> f32 {
    let fov_deg = fov_rad.to_degrees().max(0.1);
    (REFERENCE_FOV_DEG / fov_deg).clamp(0.8, 2.0)
}

/// Tiered PSF base radius in pixels before zoom clamp (v1 `_magnitudeToRadius` base term).
#[must_use]
pub fn psf_base_radius_px(magnitude: f32) -> f32 {
    if magnitude < 0.0 {
        6.0 + (0.0 - magnitude) * 2.5
    } else if magnitude < 2.0 {
        3.0 + (2.0 - magnitude) * 1.5
    } else if magnitude < 4.0 {
        1.5 + (4.0 - magnitude) * 0.75
    } else {
        (6.5 - magnitude).max(0.5) * 0.3
    }
}

/// Screen PSF radius in pixels (base × zoom, clamped like v1).
#[must_use]
pub fn psf_radius_px(magnitude: f32, fov_rad: f32) -> f32 {
    let zoom = psf_zoom_factor_from_fov_rad(fov_rad);
    (psf_base_radius_px(magnitude) * zoom).clamp(0.5, 25.0)
}

/// Brightness tone from apparent magnitude (v1 `_magnitudeToBrightness`).
#[must_use]
pub fn magnitude_to_tone(magnitude: f32) -> f32 {
    ((7.0 - magnitude) / 6.0).clamp(0.3, 1.0)
}

/// B−V indices for the three-star golden (HYG / standard photometry).
const BV_POLARIS: f32 = 0.636;
const BV_VEGA: f32 = 0.0;
const BV_SIRIUS: f32 = 0.0;

/// wgpu pipeline for instanced star sprites.
pub struct StarsPipeline {
    pipeline: wgpu::RenderPipeline,
    quad_vbuf: wgpu::Buffer,
    uniform_buf: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    queue: Arc<wgpu::Queue>,
    format: wgpu::TextureFormat,
}

impl StarsPipeline {
    /// Build the star render pipeline for `target_format`.
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
    ) -> Self {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("stars.shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("../../../shaders/stars.wgsl").into()),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("stars.bind_group_layout"),
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });

        let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("stars.pipeline_layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("stars.pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "vs_main",
                compilation_options: Default::default(),
                buffers: &[
                    wgpu::VertexBufferLayout {
                        array_stride: std::mem::size_of::<QuadVertex>() as u64,
                        step_mode: wgpu::VertexStepMode::Vertex,
                        attributes: &wgpu::vertex_attr_array![0 => Float32x2],
                    },
                    wgpu::VertexBufferLayout {
                        array_stride: std::mem::size_of::<StarInstance>() as u64,
                        step_mode: wgpu::VertexStepMode::Instance,
                        attributes: &wgpu::vertex_attr_array![
                            1 => Float32x3,
                            2 => Float32,
                            3 => Float32,
                            4 => Uint32,
                        ],
                    },
                ],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "fs_main",
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    blend: Some(wgpu::BlendState {
                        color: wgpu::BlendComponent {
                            src_factor: wgpu::BlendFactor::One,
                            dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha,
                            operation: wgpu::BlendOperation::Add,
                        },
                        alpha: wgpu::BlendComponent {
                            src_factor: wgpu::BlendFactor::One,
                            dst_factor: wgpu::BlendFactor::OneMinusSrcAlpha,
                            operation: wgpu::BlendOperation::Add,
                        },
                    }),
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

        let quad_vbuf = create_buffer_init(&device, &queue, "stars.quad_vbuf", QUAD_VERTICES);

        let uniform_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("stars.uniform"),
            size: 96,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("stars.bind_group"),
            layout: &bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform_buf.as_entire_binding(),
            }],
        });

        Self {
            pipeline,
            quad_vbuf,
            uniform_buf,
            bind_group,
            queue,
            format: target_format,
        }
    }

    /// Draw instanced stars into an active render pass.
    pub fn draw_with_viewport<'a>(
        &'a self,
        pass: &mut wgpu::RenderPass<'a>,
        scene: &Scene,
        instance_buf: &'a wgpu::Buffer,
        instance_count: u32,
        width: u32,
        height: u32,
    ) {
        if instance_count == 0 || !scene.config.show_stars {
            return;
        }

        let uniforms =
            build_uniforms_for_viewport(&scene.view_pose, width, height, scene.config.magnitude_limit);
        self.queue
            .write_buffer(&self.uniform_buf, 0, &uniforms_padded_bytes(&uniforms));

        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &self.bind_group, &[]);
        pass.set_vertex_buffer(0, self.quad_vbuf.slice(..));
        pass.set_vertex_buffer(1, instance_buf.slice(..));
        pass.draw(0..QUAD_VERTICES.len() as u32, 0..instance_count);
    }

    /// Target format this pipeline was created for.
    pub fn format(&self) -> wgpu::TextureFormat {
        self.format
    }
}

/// Build a [`StarInstance`] from a dev-catalog row.
#[must_use]
pub fn star_instance_from_dev(star: &DevStar, bv: f32) -> StarInstance {
    let dir = icrs_dir_f32(star.ra_rad, star.dec_rad);
    StarInstance {
        icrs_dir: dir,
        mag: star.mag,
        bv,
        flags: 0,
    }
}

/// Instances for Polaris, Vega, and Sirius (golden regression).
///
/// Catalog magnitudes and B−V are real; directions are small offsets around the
/// golden boresight so all three fit in a 30° field (they span >100° on the real sky).
#[must_use]
pub fn three_star_instances() -> [StarInstance; 3] {
    let pose = three_stars_view_pose();
    let vega = &DEV_STARS[1];
    let polaris = &DEV_STARS[0];
    let sirius = &DEV_STARS[2];
    [
        star_instance_at_offset(vega, &pose, 0.0, 0.0, BV_VEGA),
        star_instance_at_offset(polaris, &pose, -4.0, 3.5, BV_POLARIS),
        star_instance_at_offset(sirius, &pose, 5.5, -2.5, BV_SIRIUS),
    ]
}

/// View pose for the three-star golden: 30° FOV, stereographic.
#[must_use]
pub fn three_stars_view_pose() -> ViewPose {
    ViewPose {
        ra_rad: 1.15,
        dec_rad: 0.42,
        fov_rad: 30.0_f32.to_radians(),
        roll_rad: 0.0,
        projection: SkyProjection::Stereographic,
    }
}

/// Build a star instance at a small angular offset (degrees) from `pose` boresight.
#[must_use]
pub fn star_instance_at_offset(
    star: &DevStar,
    pose: &ViewPose,
    delta_ra_deg: f64,
    delta_dec_deg: f64,
    bv: f32,
) -> StarInstance {
    let (ra, dec) = offset_radec_deg(pose.ra_rad, pose.dec_rad, delta_ra_deg, delta_dec_deg);
    StarInstance {
        icrs_dir: icrs_dir_f32(ra, dec),
        mag: star.mag,
        bv,
        flags: 0,
    }
}

fn offset_radec_deg(
    ra0: f64,
    dec0: f64,
    delta_ra_deg: f64,
    delta_dec_deg: f64,
) -> (f64, f64) {
    let center = icrs_dir_vec3(ra0, dec0);
    let east = icrs_dir_vec3(ra0 + std::f64::consts::FRAC_PI_2, dec0);
    let east = (east - center * east.dot(center)).normalize();
    let north = center.cross(east).normalize();
    let d_ra = delta_ra_deg.to_radians();
    let d_dec = delta_dec_deg.to_radians();
    let dir = (center + east * d_ra as f32 + north * d_dec as f32).normalize();
    let dec = f64::from(dir.z.clamp(-1.0, 1.0).asin());
    let ra = f64::from(dir.y.atan2(dir.x).rem_euclid(std::f32::consts::TAU));
    (ra, dec)
}

/// Scene for the three-star golden image.
#[must_use]
pub fn three_stars_scene() -> Scene {
    Scene {
        view_pose: three_stars_view_pose(),
        config: crate::types::RenderConfig {
            show_stars: true,
            magnitude_limit: 10.0,
            twinkle: false,
            ..Default::default()
        },
        stars: three_star_instances().to_vec(),
    }
}

/// Render the three-star golden frame to RGBA8 bytes.
pub fn render_three_stars_rgba() -> Vec<u8> {
    pollster::block_on(async {
        let (device, queue) = crate::renderer::offscreen_device().await;
        let format = wgpu::TextureFormat::Rgba8UnormSrgb;
        let mut renderer = crate::renderer::Renderer::new(
            device,
            queue,
            format,
            THREE_STARS_SIZE,
            THREE_STARS_SIZE,
        );
        renderer.render(&three_stars_scene());
        renderer.readback_rgba()
    })
}

fn uniforms_padded_bytes(uniforms: &StarUniforms) -> [u8; 96] {
    let mut bytes = [0u8; 96];
    let raw = bytemuck::bytes_of(uniforms);
    bytes[..raw.len()].copy_from_slice(raw);
    bytes
}

fn build_uniforms_for_viewport(
    pose: &ViewPose,
    width: u32,
    height: u32,
    mag_limit: f32,
) -> StarUniforms {
    let icrs_to_view = icrs_to_view_matrix(pose);
    let proj_scale = stereographic_proj_scale(pose);
    StarUniforms {
        icrs_to_view: icrs_to_view.to_cols_array_2d(),
        proj_scale: [proj_scale[0], proj_scale[1]],
        mag_limit,
        psf_scale: psf_zoom_factor_from_fov_rad(pose.fov_rad),
        twinkle_seed: 0.0,
        viewport_pixels: [width as f32, height as f32],
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
    // NDC = 2 * tangent * scale (see scene/projection.rs).
    [2.0 * scale, 2.0 * scale]
}

fn icrs_dir_f32(ra_rad: f64, dec_rad: f64) -> [f32; 3] {
    let v = icrs_dir_vec3(ra_rad, dec_rad);
    [v.x, v.y, v.z]
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

fn create_buffer_init<T: Pod>(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    data: &[T],
) -> wgpu::Buffer {
    let buf = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (data.len() * std::mem::size_of::<T>()) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    queue.write_buffer(&buf, 0, bytemuck::cast_slice(data));
    buf
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn psf_zoom_factor_clamps_at_narrow_fov() {
        let fov_30 = 30.0_f32.to_radians();
        assert!((psf_zoom_factor_from_fov_rad(fov_30) - 2.0).abs() < 1e-5);
        let fov_90 = 90.0_f32.to_radians();
        assert!((psf_zoom_factor_from_fov_rad(fov_90) - 1.0).abs() < 1e-5);
    }

    #[test]
    fn psf_base_radius_tiered_matches_v1() {
        assert!((psf_base_radius_px(-1.46) - 9.65).abs() < 0.01);
        assert!((psf_base_radius_px(0.03) - 5.955).abs() < 0.01);
        assert!((psf_base_radius_px(1.98) - 3.03).abs() < 0.01);
        assert!((psf_base_radius_px(5.0) - 0.45).abs() < 0.01);
    }

    #[test]
    fn psf_radius_px_applies_zoom_and_clamp() {
        let fov_30 = 30.0_f32.to_radians();
        assert!((psf_radius_px(-1.46, fov_30) - 19.3).abs() < 0.05);
        assert!((psf_radius_px(0.03, fov_30) - 11.91).abs() < 0.05);
        assert!((psf_radius_px(1.98, fov_30) - 6.06).abs() < 0.05);
    }

    #[test]
    fn magnitude_to_tone_matches_v1() {
        assert!((magnitude_to_tone(-1.46) - 1.0).abs() < 1e-5);
        assert!((magnitude_to_tone(0.03) - 1.0).abs() < 1e-5);
        assert!((magnitude_to_tone(1.98) - 0.837).abs() < 0.01);
        assert!((magnitude_to_tone(7.0) - 0.3).abs() < 1e-5);
    }
}
