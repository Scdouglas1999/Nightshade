//! Instanced DSO sprites from OpenNGC mmap catalog (design §5.4).
//!
//! Procedural ellipse / halo shapes with a `type_id` switch in WGSL, matching v1
//! `SkyRenderer` surface-brightness opacity and display-size heuristics.

use std::sync::Arc;

use bytemuck::{Pod, Zeroable};
use glam::{Mat4, Quat, Vec3};

use crate::astrometry::frames::radec_from_icrs_dir;
use crate::catalog::{DsoRecord, ParsedDsoCatalog, DSO_FLAG_HAS_MAG};
use crate::renderer::Scene;
use crate::scene::build::BuildSceneInputs;
use crate::scene::projection::project_icrs;
use crate::types::{SkyProjection, ViewPose};

/// std140 uniform block for [`DsoUniforms`].
const DSO_UNIFORM_SIZE: u64 = 96;

/// v1 low / medium / high `maxDsosToRender` caps.
const MAX_DSOS_LOW: usize = 500;
const MAX_DSOS_MEDIUM: usize = 2000;
const MAX_DSOS_HIGH: usize = 4000;

/// Per-DSO GPU instance (matches WGSL instance layout and design `DsoInstance`).
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Pod, Zeroable)]
pub struct DsoInstance {
    /// Unit vector in ICRS (J2000).
    pub icrs_dir: [f32; 3],
    /// Major and minor axis size in arcminutes.
    pub size_arcmin: [f32; 2],
    /// Position angle in degrees (`NaN` when unknown).
    pub pa_deg: f32,
    /// Apparent magnitude for culling and size boost.
    pub surface_mag: f32,
    /// Renderer type id ([`crate::catalog::dso_type`]).
    pub type_id: u32,
    /// [`DSO_FLAG_HAS_MAG`] and related catalog flags.
    pub flags: u32,
}

/// Unit quad corners (two triangles) expanded per instance in the vertex shader.
#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
struct QuadVertex {
    corner: [f32; 2],
}

const QUAD_VERTICES: &[QuadVertex] = &[
    QuadVertex {
        corner: [-1.0, -1.0],
    },
    QuadVertex {
        corner: [1.0, -1.0],
    },
    QuadVertex {
        corner: [-1.0, 1.0],
    },
    QuadVertex {
        corner: [1.0, -1.0],
    },
    QuadVertex { corner: [1.0, 1.0] },
    QuadVertex {
        corner: [-1.0, 1.0],
    },
];

/// WGSL `DsoUniforms` (std140).
#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
struct DsoUniforms {
    icrs_to_view: [[f32; 4]; 4],
    proj_scale: [f32; 2],
    mag_limit: f32,
    pixels_per_deg: f32,
    viewport_pixels: [f32; 2],
    _pad: [f32; 2],
}

/// Build a GPU instance from an on-disk [`DsoRecord`].
#[must_use]
pub fn dso_instance_from_record(record: &DsoRecord) -> DsoInstance {
    DsoInstance {
        icrs_dir: record.icrs_dir,
        size_arcmin: record.size_arcmin,
        pa_deg: record.pa_deg,
        surface_mag: record.surface_mag,
        type_id: record.type_id,
        flags: record.flags,
    }
}

/// Surface brightness: `mag + 2.5 * log10(area_arcsec²)` (v1 `_surfaceBrightness`).
#[must_use]
pub fn dso_surface_brightness(major_arcmin: f32, minor_arcmin: f32, magnitude: f32) -> Option<f32> {
    if !magnitude.is_finite() || major_arcmin <= 0.0 {
        return None;
    }
    let minor = if minor_arcmin > 0.0 {
        minor_arcmin
    } else {
        major_arcmin
    };
    let area_arcmin2 = std::f32::consts::PI * (major_arcmin * 0.5) * (minor * 0.5);
    let area_arcsec2 = area_arcmin2 * 3600.0;
    if area_arcsec2 <= 0.0 {
        return None;
    }
    Some(magnitude + 2.5 * area_arcsec2.log10())
}

/// Map surface brightness to an opacity multiplier (v1 `_surfaceBrightnessOpacity`).
#[must_use]
pub fn dso_surface_brightness_opacity(sb: Option<f32>) -> f32 {
    let Some(sb) = sb else {
        return 0.7;
    };
    if sb <= 22.0 {
        1.0
    } else if sb >= 26.5 {
        0.15
    } else {
        1.0 - (sb - 22.0) / (26.5 - 22.0) * 0.85
    }
}

/// Screen diameter in pixels before clamp (v1 DSO size + magnitude bonus).
#[must_use]
pub fn dso_display_diameter_px(major_arcmin: f32, magnitude: f32, pixels_per_deg: f32) -> f32 {
    let major = if major_arcmin > 0.0 {
        major_arcmin
    } else {
        5.0
    };
    let dso_px = (major / 60.0) * pixels_per_deg;
    let mag = if magnitude.is_finite() {
        magnitude
    } else {
        14.0
    };
    let mag_bonus = ((14.0 - mag) / 14.0 * 14.0).clamp(0.0, 14.0);
    dso_px.clamp(6.0 + mag_bonus, 40.0)
}

/// Pixels per degree for the current viewport and FOV (stereographic tangent plane).
#[must_use]
pub fn pixels_per_degree(width: u32, height: u32, fov_rad: f32) -> f32 {
    let min_px = width.min(height) as f32;
    let half_fov = fov_rad.max(0.001) * 0.5;
    let edge_r = 2.0 * (half_fov * 0.5).tan();
    if edge_r <= f32::EPSILON {
        return min_px;
    }
    min_px / edge_r.to_degrees()
}

/// Max DSO draw count for a render-quality tier.
#[must_use]
pub fn max_dsos_for_quality(quality: u32) -> usize {
    match quality {
        0 => MAX_DSOS_LOW,
        1 => MAX_DSOS_MEDIUM,
        _ => MAX_DSOS_HIGH,
    }
}

/// Collect visible DSO instances from a parsed OpenNGC catalog.
#[must_use]
pub fn collect_dso_instances(
    catalog: &ParsedDsoCatalog<'_>,
    inputs: BuildSceneInputs,
) -> Vec<DsoInstance> {
    if !inputs.render_config.show_dsos {
        return Vec::new();
    }
    collect_dso_instances_from_records(catalog.records, inputs)
}

/// Collect visible DSO instances from a record slice (tests / partial catalogs).
#[must_use]
pub fn collect_dso_instances_from_records(
    records: &[DsoRecord],
    inputs: BuildSceneInputs,
) -> Vec<DsoInstance> {
    if !inputs.render_config.show_dsos {
        return Vec::new();
    }

    let mag_limit = inputs.render_config.magnitude_limit;
    let max_count = max_dsos_for_quality(inputs.render_config.quality);
    let mut out = Vec::with_capacity(max_count.min(records.len()));

    for record in records {
        if out.len() >= max_count {
            break;
        }
        let mag = effective_dso_magnitude(record);
        if mag > mag_limit {
            continue;
        }
        let (ra_rad, dec_rad) = radec_from_icrs_dir(record.icrs_dir);
        if project_icrs(ra_rad, dec_rad, inputs.view_pose).is_none() {
            continue;
        }
        out.push(dso_instance_from_record(record));
    }

    out
}

fn effective_dso_magnitude(record: &DsoRecord) -> f32 {
    if (record.flags & DSO_FLAG_HAS_MAG) != 0 && record.surface_mag.is_finite() {
        record.surface_mag
    } else {
        99.0
    }
}

/// wgpu pipeline for instanced DSO sprites.
pub struct DsosPipeline {
    pipeline: wgpu::RenderPipeline,
    quad_vbuf: wgpu::Buffer,
    uniform_buf: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    queue: Arc<wgpu::Queue>,
    format: wgpu::TextureFormat,
}

impl DsosPipeline {
    /// Build the DSO render pipeline for `target_format`.
    pub fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        target_format: wgpu::TextureFormat,
    ) -> Self {
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("dsos.shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("../../../shaders/dsos.wgsl").into()),
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("dsos.bind_group_layout"),
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
            label: Some("dsos.pipeline_layout"),
            bind_group_layouts: &[&bind_group_layout],
            push_constant_ranges: &[],
        });

        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("dsos.pipeline"),
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
                        array_stride: std::mem::size_of::<DsoInstance>() as u64,
                        step_mode: wgpu::VertexStepMode::Instance,
                        attributes: &wgpu::vertex_attr_array![
                            1 => Float32x3,
                            2 => Float32x2,
                            3 => Float32,
                            4 => Float32,
                            5 => Uint32,
                            6 => Uint32,
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
                    // `dsos.wgsl` returns premultiplied alpha (`vec4(rgb * alpha, alpha)`),
                    // so blend factors must be (1, 1-srcA). `ALPHA_BLENDING` is straight-alpha
                    // and would multiply RGB by alpha a second time, fading sprites to black.
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

        let quad_vbuf = create_buffer_init(&device, &queue, "dsos.quad_vbuf", QUAD_VERTICES);

        let uniform_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("dsos.uniform"),
            size: DSO_UNIFORM_SIZE,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("dsos.bind_group"),
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

    /// Draw instanced DSO sprites into an active render pass.
    pub fn draw_with_viewport<'a>(
        &'a self,
        pass: &mut wgpu::RenderPass<'a>,
        scene: &Scene,
        instance_buf: &'a wgpu::Buffer,
        instance_count: u32,
        width: u32,
        height: u32,
    ) {
        if instance_count == 0 || !scene.config.show_dsos {
            return;
        }

        let uniforms = build_uniforms(scene, width, height);
        self.queue
            .write_buffer(&self.uniform_buf, 0, bytemuck::bytes_of(&uniforms));

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

fn build_uniforms(scene: &Scene, width: u32, height: u32) -> DsoUniforms {
    let pose = &scene.view_pose;
    DsoUniforms {
        icrs_to_view: icrs_to_view_matrix(pose).to_cols_array_2d(),
        proj_scale: stereographic_proj_scale(pose),
        mag_limit: scene.config.magnitude_limit,
        pixels_per_deg: pixels_per_degree(width, height, pose.fov_rad),
        viewport_pixels: [width as f32, height as f32],
        _pad: [0.0, 0.0],
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
        size: std::mem::size_of_val(data) as u64,
        usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    queue.write_buffer(&buf, 0, bytemuck::cast_slice(data));
    buf
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::dso_type;
    use crate::catalog::{encode_catalog, DsoCatalogHeader, DSO_FLAG_HAS_MAG, DSO_FLAG_MESSIER};
    use crate::catalog::{DsoRecord, OPENNGC_CATALOG_ID, OPENNGC_PACK_VERSION};
    use crate::types::{AstroTime, Observer, RenderConfig, ViewPose};

    #[test]
    fn dso_surface_brightness_m31_fixture() {
        // M31 from ngc_mini.csv: MajAx 189.1, MinAx 61.7, V 3.44
        let sb = dso_surface_brightness(189.1, 61.7, 3.44).expect("sb");
        // Large apparent size pushes SB well above 22 → reduced opacity (v1 curve).
        assert!(sb > 22.0, "sb={sb}");
        let opacity = dso_surface_brightness_opacity(Some(sb));
        assert!(opacity > 0.5 && opacity <= 1.0, "opacity={opacity}");
    }

    #[test]
    fn dso_display_diameter_clamps_faint_and_bright() {
        let ppd = 10.0;
        let bright = dso_display_diameter_px(189.1, 3.44, ppd);
        assert!(bright > 30.0 && bright <= 40.0, "bright={bright}");
        let faint = dso_display_diameter_px(1.0, 14.0, ppd);
        assert!(faint >= 6.0 && faint <= 20.0);
        let capped = dso_display_diameter_px(500.0, 1.0, 100.0);
        assert!((capped - 40.0).abs() < 0.01);
    }

    #[test]
    fn collect_respects_mag_limit_and_visibility() {
        let records = vec![DsoRecord::from_radec(
            0.1,
            0.2,
            10.0,
            5.0,
            35.0,
            3.4,
            dso_type::GALAXY,
            DSO_FLAG_HAS_MAG,
            224,
            0,
            31,
        )];
        let pose = ViewPose {
            ra_rad: 0.1,
            dec_rad: 0.2,
            fov_rad: 30.0_f32.to_radians(),
            ..ViewPose::default()
        };
        let base_inputs = BuildSceneInputs {
            view_pose: pose,
            render_config: RenderConfig {
                show_dsos: true,
                magnitude_limit: 10.0,
                ..RenderConfig::default()
            },
            observer: Observer::default(),
            astro_time: AstroTime::from_jd_utc(crate::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC),
        };
        let visible = collect_dso_instances_from_records(&records, base_inputs);
        assert_eq!(visible.len(), 1);

        let faint_limit = BuildSceneInputs {
            render_config: RenderConfig {
                magnitude_limit: 2.0,
                ..base_inputs.render_config
            },
            ..base_inputs
        };
        assert!(collect_dso_instances_from_records(&records, faint_limit).is_empty());
    }

    #[test]
    fn collect_from_parsed_catalog_round_trip() {
        let records = vec![DsoRecord::from_radec(
            0.1,
            0.2,
            10.0,
            5.0,
            35.0,
            3.4,
            dso_type::GALAXY,
            DSO_FLAG_HAS_MAG | DSO_FLAG_MESSIER,
            224,
            0,
            31,
        )];
        let header = DsoCatalogHeader::new(OPENNGC_CATALOG_ID, OPENNGC_PACK_VERSION, 1, 20.0);
        let bytes = encode_catalog(&header, &records);
        let parsed = crate::catalog::parse_catalog(&bytes).expect("parse");
        let pose = ViewPose {
            ra_rad: 0.1,
            dec_rad: 0.2,
            fov_rad: 45.0_f32.to_radians(),
            ..ViewPose::default()
        };
        let inputs = BuildSceneInputs {
            view_pose: pose,
            render_config: RenderConfig {
                show_dsos: true,
                magnitude_limit: 12.0,
                ..RenderConfig::default()
            },
            observer: Observer::default(),
            astro_time: AstroTime::from_jd_utc(crate::scene::snapshot::DEFAULT_ASTRO_TIME_JD_UTC),
        };
        let instances = collect_dso_instances(&parsed, inputs);
        assert_eq!(instances.len(), 1);
        assert_eq!(instances[0].type_id, dso_type::GALAXY);
    }
}
