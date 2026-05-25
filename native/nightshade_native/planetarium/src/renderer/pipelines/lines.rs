//! Line overlays: equatorial / alt-az / galactic grids, ecliptic, constellation stick figures.
//!
//! Vertex layout matches `shaders/lines.wgsl`: ICRS unit direction, packed RGBA, style id,
//! and per-segment `along` for fragment dashing.

use std::sync::Arc;

use bytemuck::{Pod, Zeroable};
use glam::{Mat4, Quat, Vec3};

use crate::astrometry::precession::mean_obliquity_from_julian_centuries_tt;
use crate::astrometry::vsop87::ecliptic_to_equatorial_rad;
use crate::catalog::constellation_lines::{
    icrs_dir_from_j2000, CONSTELLATIONS, LINE_VERTEX_COUNT,
};
use crate::renderer::Scene;
use crate::types::{SkyProjection, ViewPose};

/// std140 uniform block for [`LineUniforms`].
const LINE_UNIFORM_SIZE: u64 = 80;

/// Constellation stick figures (v1 `constellationLineColor` 0x40FFFFFF).
pub const COLOR_CONSTELLATION: u32 = pack_rgba(255, 255, 255, 0x40);

/// Equatorial grid (`gridColor` 0x33FFFFFF).
pub const COLOR_GRID: u32 = pack_rgba(255, 255, 255, 0x33);

/// Alt-az grid (same hue, lower alpha; dashed in shader).
pub const COLOR_ALT_AZ_GRID: u32 = pack_rgba(255, 255, 255, 0x4D);

/// Ecliptic (`eclipticColor` 0x40FFEB3B).
pub const COLOR_ECLIPTIC: u32 = pack_rgba(255, 235, 59, 0x40);

/// Galactic equator (`galacticPlaneColor` 0x4000BCD4).
pub const COLOR_GALACTIC: u32 = pack_rgba(0, 188, 212, 0x40);

/// Solid grid lines.
pub const STYLE_GRID_SOLID: u32 = 1;
/// Dashed grid (alt-az).
pub const STYLE_GRID_DASHED: u32 = 2;
/// Ecliptic great circle.
pub const STYLE_ECLIPTIC: u32 = 3;
/// Galactic equator.
pub const STYLE_GALACTIC: u32 = 4;

/// One GPU vertex for the line list.
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Pod, Zeroable)]
pub struct LineVertex {
    /// Unit vector in ICRS (J2000).
    pub icrs_dir: [f32; 3],
    /// Packed RGBA (`pack_rgba`).
    pub color: u32,
    /// Style id for dash / tone (`STYLE_*` constants; 0 = constellation).
    pub style_id: u32,
    /// Param along segment in \[0, 1\] for fragment dashing.
    pub along: f32,
}

/// WGSL `LineUniforms` (std140).
#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
struct LineUniforms {
    icrs_to_view: [[f32; 4]; 4],
    proj_scale: [f32; 2],
    viewport_pixels: [f32; 2],
}

/// wgpu pipeline for `LineList` overlays.
pub struct LinesPipeline {
    pipeline: wgpu::RenderPipeline,
    constellation_vbuf: wgpu::Buffer,
    constellation_vertex_count: u32,
    dynamic_vbuf: wgpu::Buffer,
    dynamic_vertex_count: u32,
    uniform_buf: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    format: wgpu::TextureFormat,
}

impl LinesPipeline {
    /// Build the line pipeline and upload static constellation geometry.
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
    ) -> Self {
        let constellation_verts = build_constellation_line_vertices();
        debug_assert_eq!(constellation_verts.len(), LINE_VERTEX_COUNT);
        let constellation_vertex_count = constellation_verts.len() as u32;

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("lines.shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("../../../shaders/lines.wgsl").into()),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("lines.bind_group_layout"),
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
            label: Some("lines.pipeline_layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("lines.pipeline"),
            layout: Some(&pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: "vs_main",
                compilation_options: Default::default(),
                buffers: &[wgpu::VertexBufferLayout {
                    array_stride: std::mem::size_of::<LineVertex>() as u64,
                    step_mode: wgpu::VertexStepMode::Vertex,
                    attributes: &wgpu::vertex_attr_array![
                        0 => Float32x3,
                        1 => Uint32,
                        2 => Uint32,
                        3 => Float32,
                    ],
                }],
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: "fs_main",
                compilation_options: Default::default(),
                targets: &[Some(wgpu::ColorTargetState {
                    format: target_format,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::LineList,
                ..Default::default()
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        });

        let constellation_vbuf =
            create_buffer_init(&device, &queue, "lines.constellation_vbuf", &constellation_verts);

        let dynamic_vbuf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("lines.dynamic_vbuf"),
            size: 4,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let uniform_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("lines.uniform"),
            size: LINE_UNIFORM_SIZE,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("lines.bind_group"),
            layout: &bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform_buf.as_entire_binding(),
            }],
        });

        Self {
            pipeline,
            constellation_vbuf,
            constellation_vertex_count,
            dynamic_vbuf,
            dynamic_vertex_count: 0,
            uniform_buf,
            bind_group,
            device,
            queue,
            format: target_format,
        }
    }

    /// Rebuild grid / ecliptic / galactic vertices from `scene` and draw all enabled layers.
    pub fn prepare_and_draw<'a>(
        &'a mut self,
        pass: &mut wgpu::RenderPass<'a>,
        scene: &Scene,
        width: u32,
        height: u32,
    ) {
        let dynamic = build_overlay_line_vertices(scene);
        self.upload_dynamic(&dynamic);
        if !any_lines_visible(scene) {
            return;
        }

        let uniforms = build_uniforms(&scene.view_pose, width, height);
        self.queue
            .write_buffer(&self.uniform_buf, 0, bytemuck::bytes_of(&uniforms));

        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, &self.bind_group, &[]);

        if scene.config.show_constellations && self.constellation_vertex_count > 0 {
            pass.set_vertex_buffer(0, self.constellation_vbuf.slice(..));
            pass.draw(0..self.constellation_vertex_count, 0..1);
        }

        if self.dynamic_vertex_count > 0 {
            pass.set_vertex_buffer(0, self.dynamic_vbuf.slice(..));
            pass.draw(0..self.dynamic_vertex_count, 0..1);
        }
    }

    /// Static constellation stick-figure vertex count (2 per catalog segment).
    #[must_use]
    pub fn constellation_vertex_count(&self) -> u32 {
        self.constellation_vertex_count
    }

    /// Target format this pipeline was created for.
    pub fn format(&self) -> wgpu::TextureFormat {
        self.format
    }

    fn upload_dynamic(&mut self, vertices: &[LineVertex]) {
        let count = vertices.len();
        if count == 0 {
            self.dynamic_vertex_count = 0;
            return;
        }
        let byte_len = (count * std::mem::size_of::<LineVertex>()) as u64;
        if self.dynamic_vbuf.size() < byte_len {
            self.dynamic_vbuf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("lines.dynamic_vbuf"),
                size: byte_len,
                usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
        }
        self.queue
            .write_buffer(&self.dynamic_vbuf, 0, bytemuck::cast_slice(vertices));
        self.dynamic_vertex_count = count as u32;
    }
}

/// Pack 8-bit RGBA into a `LineVertex::color` word (little-endian R in LSB).
#[must_use]
pub const fn pack_rgba(r: u8, g: u8, b: u8, a: u8) -> u32 {
    (a as u32) << 24 | (b as u32) << 16 | (g as u32) << 8 | r as u32
}

/// Build GPU vertices for all constellation segments (count = [`LINE_VERTEX_COUNT`]).
#[must_use]
pub fn build_constellation_line_vertices() -> Vec<LineVertex> {
    let mut out = Vec::with_capacity(LINE_VERTEX_COUNT);
    for constellation in CONSTELLATIONS {
        for segment in constellation.segments {
            let start = icrs_dir_from_j2000(segment.start_ra_hours, segment.start_dec_deg);
            let end = icrs_dir_from_j2000(segment.end_ra_hours, segment.end_dec_deg);
            push_segment(
                &mut out,
                start,
                end,
                COLOR_CONSTELLATION,
                0,
            );
        }
    }
    out
}

/// Vertex count for constellation stick figures only.
#[must_use]
pub fn constellation_line_vertex_count() -> usize {
    build_constellation_line_vertices().len()
}

/// Whether any overlay line layer is enabled for `scene`.
#[must_use]
pub fn any_lines_visible(scene: &Scene) -> bool {
    let c = &scene.config;
    c.show_constellations
        || c.show_equatorial_grid
        || c.show_alt_az_grid
        || c.show_galactic_grid
        || c.show_ecliptic
}

/// Build dynamic grid / ecliptic / galactic vertices for the current frame.
#[must_use]
pub fn build_overlay_line_vertices(scene: &Scene) -> Vec<LineVertex> {
    let mut out = Vec::new();
    let cfg = &scene.config;
    let pose = &scene.view_pose;
    let fov_deg = pose.fov_rad.to_degrees();

    if cfg.show_equatorial_grid {
        append_equatorial_grid(&mut out, fov_deg);
    }
    if cfg.show_alt_az_grid {
        append_alt_az_grid(&mut out, scene);
    }
    if cfg.show_ecliptic {
        append_ecliptic(&mut out, scene.astro_time.julian_centuries_tt());
    }
    if cfg.show_galactic_grid {
        append_galactic_equator(&mut out);
    }
    out
}

fn push_segment(
    out: &mut Vec<LineVertex>,
    start: [f32; 3],
    end: [f32; 3],
    color: u32,
    style_id: u32,
) {
    out.push(LineVertex {
        icrs_dir: start,
        color,
        style_id,
        along: 0.0,
    });
    out.push(LineVertex {
        icrs_dir: end,
        color,
        style_id,
        along: 1.0,
    });
}

fn append_equatorial_grid(out: &mut Vec<LineVertex>, fov_deg: f32) {
    let (ra_spacing_h, dec_spacing_deg, dec_step_deg) = equatorial_grid_spacing(fov_deg);

    for ra_h in frange(0.0, 24.0, ra_spacing_h) {
        append_polyline(
            out,
            (-90.0..=90.0).step_by_float(dec_step_deg),
            |dec| icrs_dir_from_equatorial(ra_h, dec),
            COLOR_GRID,
            STYLE_GRID_SOLID,
        );
    }

    let ra_step_h = if fov_deg > 30.0 { 0.5 } else { 0.25 };
    for dec in frange(-90.0 + dec_spacing_deg, 90.0, dec_spacing_deg) {
        append_polyline(
            out,
            (0.0..=24.0).step_by_float(ra_step_h),
            |ra_h| icrs_dir_from_equatorial(ra_h, dec),
            COLOR_GRID,
            STYLE_GRID_SOLID,
        );
    }
}

fn equatorial_grid_spacing(fov_deg: f32) -> (f32, f32, f32) {
    if fov_deg > 60.0 {
        (2.0, 30.0, 5.0)
    } else if fov_deg > 30.0 {
        (1.0, 15.0, 3.0)
    } else if fov_deg > 10.0 {
        (0.5, 10.0, 2.0)
    } else {
        (0.25, 5.0, 1.0)
    }
}

fn append_alt_az_grid(out: &mut Vec<LineVertex>, scene: &Scene) {
    let lst_hours = scene.astro_time.lmst(scene.observer.longitude_rad) * 12.0 / std::f64::consts::PI;
    let lat_deg = scene.observer.latitude_rad.to_degrees();

    for alt in [0_i32, 30, 60, 90] {
        append_polyline(
            out,
            (0.0..=360.0).step_by_float(5.0),
            |az| {
                let (ra_deg, dec_deg) = horizontal_to_equatorial_deg(
                    f64::from(alt),
                    f64::from(az),
                    lat_deg,
                    lst_hours,
                );
                icrs_dir_from_equatorial((ra_deg / 15.0) as f32, dec_deg as f32)
            },
            COLOR_ALT_AZ_GRID,
            STYLE_GRID_DASHED,
        );
    }
}

fn append_ecliptic(out: &mut Vec<LineVertex>, julian_centuries_tt: f64) {
    let obliquity_rad = mean_obliquity_from_julian_centuries_tt(julian_centuries_tt);
    append_polyline(
        out,
        (0.0..=360.0).step_by_float(2.0),
        |lon| {
            let (ra_rad, dec_rad) = ecliptic_to_equatorial_rad(
                f64::from(lon).to_radians(),
                0.0,
                obliquity_rad,
            );
            icrs_dir_from_radec_rad(ra_rad, dec_rad)
        },
        COLOR_ECLIPTIC,
        STYLE_ECLIPTIC,
    );
}

fn append_galactic_equator(out: &mut Vec<LineVertex>) {
    append_polyline(
        out,
        (0.0..=360.0).step_by_float(2.0),
        |lon| {
            let (ra_deg, dec_deg) = galactic_to_equatorial_deg(lon, 0.0);
            icrs_dir_from_equatorial(ra_deg / 15.0, dec_deg)
        },
        COLOR_GALACTIC,
        STYLE_GALACTIC,
    );
}

fn append_polyline<F>(out: &mut Vec<LineVertex>, steps: StepF32, mut sample: F, color: u32, style: u32)
where
    F: FnMut(f32) -> [f32; 3],
{
    let mut prev: Option<[f32; 3]> = None;
    for t in steps {
        let dir = sample(t);
        if let Some(p) = prev {
            push_segment(out, p, dir, color, style);
        }
        prev = Some(dir);
    }
}

fn icrs_dir_from_equatorial(ra_hours: f32, dec_deg: f32) -> [f32; 3] {
    icrs_dir_from_j2000(ra_hours, dec_deg)
}

fn icrs_dir_from_radec_rad(ra_rad: f64, dec_rad: f64) -> [f32; 3] {
    let (sin_dec, cos_dec) = dec_rad.sin_cos();
    let (sin_ra, cos_ra) = ra_rad.sin_cos();
    [
        (cos_dec * cos_ra) as f32,
        (cos_dec * sin_ra) as f32,
        sin_dec as f32,
    ]
}

/// Horizontal (alt°, az°) → equatorial (RA°, Dec°); matches v1 `horizontalToEquatorial`.
fn horizontal_to_equatorial_deg(
    alt_deg: f64,
    az_deg: f64,
    latitude_deg: f64,
    lst_hours: f64,
) -> (f64, f64) {
    let alt = alt_deg.to_radians();
    let az = az_deg.to_radians();
    let lat = latitude_deg.to_radians();

    let sin_dec = alt.sin() * lat.sin() + alt.cos() * lat.cos() * az.cos();
    let dec = sin_dec.clamp(-1.0, 1.0).asin();

    let y = -az.sin() * alt.cos();
    let x = alt.sin() * lat.cos() - alt.cos() * lat.sin() * az.cos();
    let ha = y.atan2(x);

    let mut ra = lst_hours * 15.0 - ha.to_degrees();
    ra = ra.rem_euclid(360.0);
    (ra, dec.to_degrees())
}

/// Galactic (l°, b°) → equatorial (RA°, Dec°); IAU 1958 constants from v1.
fn galactic_to_equatorial_deg(lon_deg: f32, lat_deg: f32) -> (f32, f32) {
    const ALPHA_GP: f32 = 192.85948;
    const DELTA_GP: f32 = 27.12825;
    const L_OMEGA: f32 = 32.93192;

    let l = lon_deg.to_radians();
    let b = lat_deg.to_radians();
    let d_gp = DELTA_GP.to_radians();
    let l_o = L_OMEGA.to_radians();

    let sin_dec = b.sin() * d_gp.sin() + b.cos() * d_gp.cos() * (l - l_o).sin();
    let dec = sin_dec.clamp(-1.0, 1.0).asin();

    let y = b.cos() * (l - l_o).cos();
    let x = b.sin() * d_gp.cos() - b.cos() * d_gp.sin() * (l - l_o).sin();
    let mut ra = x.atan2(y).to_degrees() + ALPHA_GP;
    ra = ra.rem_euclid(360.0);
    (ra, dec.to_degrees())
}

fn build_uniforms(pose: &ViewPose, width: u32, height: u32) -> LineUniforms {
    LineUniforms {
        icrs_to_view: icrs_to_view_matrix(pose).to_cols_array_2d(),
        proj_scale: stereographic_proj_scale(pose),
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

struct StepF32 {
    start: f32,
    end: f32,
    step: f32,
}

impl Iterator for StepF32 {
    type Item = f32;

    fn next(&mut self) -> Option<Self::Item> {
        if self.start > self.end + f32::EPSILON {
            return None;
        }
        let v = self.start;
        self.start += self.step;
        Some(v)
    }
}

trait FloatRange {
    fn step_by_float(self, step: f32) -> StepF32;
}

impl FloatRange for std::ops::RangeInclusive<f32> {
    fn step_by_float(self, step: f32) -> StepF32 {
        StepF32 {
            start: *self.start(),
            end: *self.end(),
            step,
        }
    }
}

fn frange(start: f32, end: f32, step: f32) -> StepF32 {
    StepF32 { start, end, step }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::constellation_lines::LINE_VERTEX_COUNT;

    #[test]
    fn constellation_line_vertex_count_matches_catalog() {
        assert_eq!(constellation_line_vertex_count(), LINE_VERTEX_COUNT);
        assert_eq!(build_constellation_line_vertices().len(), 728);
    }

    #[test]
    fn line_uniforms_struct_matches_wgsl_std140_size() {
        assert_eq!(
            std::mem::size_of::<LineUniforms>() as u64,
            LINE_UNIFORM_SIZE
        );
    }

    #[test]
    fn pack_rgba_matches_v1_constellation_color() {
        assert_eq!(COLOR_CONSTELLATION, 0x40FFFFFF);
        assert_eq!(COLOR_ECLIPTIC, 0x40FFEB3B);
    }

    #[test]
    fn galactic_pole_ra_dec_matches_v1_constants() {
        let (ra, dec) = galactic_to_equatorial_deg(0.0, 90.0);
        assert!((ra - 192.85948).abs() < 0.02);
        assert!((dec - 27.12825).abs() < 0.02);
    }
}
