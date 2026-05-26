//! GPU precomputation of Bruneton 2020 atmospheric LUTs (Algorithm 4.1).

use std::sync::Arc;

use wgpu::util::DeviceExt;

use super::constants::{
    DEFAULT_SCATTERING_ORDERS, IRRADIANCE_TEXTURE_HEIGHT, IRRADIANCE_TEXTURE_WIDTH,
    SCATTERING_TEXTURE_DEPTH, SCATTERING_TEXTURE_HEIGHT, SCATTERING_TEXTURE_WIDTH,
    TRANSMITTANCE_TEXTURE_HEIGHT, TRANSMITTANCE_TEXTURE_WIDTH,
};
use super::luts::{
    create_texture_2d, create_texture_3d, lut_format, split_combined_scattering,
    transmittance_format, view_2d, view_3d, BrunetonLuts, BrunetonPrecomputeError,
};
use super::params::{luminance_from_radiance_identity, PrecomputeConfig};

const QUAD_VERTICES: [f32; 8] = [-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0];

/// Precompute all Bruneton LUTs on `device`/`queue` (typically &lt;2 s on desktop GPUs).
pub fn precompute_bruneton_luts(
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
) -> Result<BrunetonLuts, BrunetonPrecomputeError> {
    precompute_bruneton_luts_with_config(device, queue, &PrecomputeConfig::earth_demo())
}

/// Precompute with explicit atmosphere configuration.
pub fn precompute_bruneton_luts_with_config(
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    config: &PrecomputeConfig,
) -> Result<BrunetonLuts, BrunetonPrecomputeError> {
    let format = lut_format(config.half_precision);
    let transmittance_format = transmittance_format();

    let transmittance = create_texture_2d(
        &device,
        "planetarium.bruneton.transmittance",
        TRANSMITTANCE_TEXTURE_WIDTH,
        TRANSMITTANCE_TEXTURE_HEIGHT,
        transmittance_format,
    );
    let combined_scattering = create_texture_3d(
        &device,
        "planetarium.bruneton.combined_scattering",
        SCATTERING_TEXTURE_WIDTH,
        SCATTERING_TEXTURE_HEIGHT,
        SCATTERING_TEXTURE_DEPTH,
        format,
    );
    let irradiance = create_texture_2d(
        &device,
        "planetarium.bruneton.irradiance",
        IRRADIANCE_TEXTURE_WIDTH,
        IRRADIANCE_TEXTURE_HEIGHT,
        format,
    );

    let delta_irradiance = create_texture_2d(
        &device,
        "planetarium.bruneton.delta_irradiance",
        IRRADIANCE_TEXTURE_WIDTH,
        IRRADIANCE_TEXTURE_HEIGHT,
        format,
    );
    let delta_rayleigh = create_texture_3d(
        &device,
        "planetarium.bruneton.delta_rayleigh",
        SCATTERING_TEXTURE_WIDTH,
        SCATTERING_TEXTURE_HEIGHT,
        SCATTERING_TEXTURE_DEPTH,
        format,
    );
    let delta_mie = create_texture_3d(
        &device,
        "planetarium.bruneton.delta_mie",
        SCATTERING_TEXTURE_WIDTH,
        SCATTERING_TEXTURE_HEIGHT,
        SCATTERING_TEXTURE_DEPTH,
        format,
    );
    let delta_scattering_density = create_texture_3d(
        &device,
        "planetarium.bruneton.delta_scattering_density",
        SCATTERING_TEXTURE_WIDTH,
        SCATTERING_TEXTURE_HEIGHT,
        SCATTERING_TEXTURE_DEPTH,
        format,
    );

    let ctx = PrecomputeContext::new(device.clone(), queue.clone(), format)?;
    let lfr = luminance_from_radiance_identity();

    // Transmittance
    ctx.draw_2d(
        &transmittance,
        &[],
        &ctx.transmittance_pipeline,
        &ctx.transmittance_bgl,
        &luminance_from_radiance_identity(),
        TRANSMITTANCE_TEXTURE_WIDTH,
        TRANSMITTANCE_TEXTURE_HEIGHT,
        0,
        0,
    )?;

    // Direct irradiance → delta_irradiance; irradiance cleared
    ctx.draw_2d_multi(
        &[&delta_irradiance, &irradiance],
        &[Some(&transmittance)],
        &ctx.direct_irradiance_pipeline,
        &ctx.direct_irradiance_bgl,
        IRRADIANCE_TEXTURE_WIDTH,
        IRRADIANCE_TEXTURE_HEIGHT,
        0,
        0,
        false,
    )?;

    // Single scattering → combined_scattering (combined textures: 3 MRTs)
    for layer in 0..SCATTERING_TEXTURE_DEPTH {
        ctx.draw_3d_layer(
            &[&delta_rayleigh, &delta_mie, &combined_scattering],
            &[Some(&transmittance)],
            &ctx.single_scattering_pipeline,
            &ctx.single_scattering_bgl,
            &lfr,
            layer,
            false,
        )?;
    }

    for order in 2..=DEFAULT_SCATTERING_ORDERS {
        for layer in 0..SCATTERING_TEXTURE_DEPTH {
            ctx.draw_3d_layer_with_order(
                &[&delta_scattering_density],
                &[
                    Some(&transmittance),
                    Some(&delta_rayleigh),
                    Some(&delta_mie),
                    Some(&delta_rayleigh),
                    Some(&delta_irradiance),
                ],
                &ctx.scattering_density_pipeline,
                &ctx.scattering_density_bgl,
                layer,
                order as i32,
            )?;
        }

        ctx.draw_2d_multi(
            &[&delta_irradiance, &irradiance],
            &[
                Some(&delta_rayleigh),
                Some(&delta_mie),
                Some(&delta_rayleigh),
            ],
            &ctx.indirect_irradiance_pipeline,
            &ctx.indirect_irradiance_bgl,
            IRRADIANCE_TEXTURE_WIDTH,
            IRRADIANCE_TEXTURE_HEIGHT,
            order as i32,
            0,
            true,
        )?;

        for layer in 0..SCATTERING_TEXTURE_DEPTH {
            ctx.draw_3d_layer_multi(
                &[&delta_rayleigh, &combined_scattering],
                &[Some(&transmittance), Some(&delta_scattering_density)],
                &ctx.multiple_scattering_pipeline,
                &ctx.multiple_scattering_bgl,
                &lfr,
                layer,
                true,
            )?;
        }
    }

    let (single_scattering, multiple_scattering) =
        split_combined_scattering(&device, &queue, &combined_scattering, format)?;

    Ok(BrunetonLuts {
        transmittance_view: view_2d(&transmittance),
        transmittance,
        single_scattering_view: view_3d(&single_scattering),
        single_scattering,
        multiple_scattering_view: view_3d(&multiple_scattering),
        multiple_scattering,
        irradiance_view: view_2d(&irradiance),
        irradiance,
        combined_scattering_view: view_3d(&combined_scattering),
        combined_scattering,
    })
}

struct PrecomputeContext {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    quad: wgpu::Buffer,
    uniform_buf: wgpu::Buffer,
    transmittance_pipeline: wgpu::RenderPipeline,
    transmittance_bgl: wgpu::BindGroupLayout,
    direct_irradiance_pipeline: wgpu::RenderPipeline,
    direct_irradiance_bgl: wgpu::BindGroupLayout,
    single_scattering_pipeline: wgpu::RenderPipeline,
    single_scattering_bgl: wgpu::BindGroupLayout,
    scattering_density_pipeline: wgpu::RenderPipeline,
    scattering_density_bgl: wgpu::BindGroupLayout,
    indirect_irradiance_pipeline: wgpu::RenderPipeline,
    indirect_irradiance_bgl: wgpu::BindGroupLayout,
    multiple_scattering_pipeline: wgpu::RenderPipeline,
    multiple_scattering_bgl: wgpu::BindGroupLayout,
    scattering_format: wgpu::TextureFormat,
}

impl PrecomputeContext {
    fn new(
        device: Arc<wgpu::Device>,
        queue: Arc<wgpu::Queue>,
        scattering_format: wgpu::TextureFormat,
    ) -> Result<Self, BrunetonPrecomputeError> {
        let quad = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("planetarium.bruneton.quad"),
            contents: bytemuck::cast_slice(&QUAD_VERTICES),
            usage: wgpu::BufferUsages::VERTEX,
        });
        let uniform_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("planetarium.bruneton.uniforms"),
            size: 256,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let vertex = load_spirv(&device, "bruneton_precompute_vertex.spv");
        let transmittance_shader = load_spirv(&device, "bruneton_precompute_transmittance.spv");
        let direct_shader = load_spirv(&device, "bruneton_precompute_direct_irradiance.spv");
        let single_shader = load_spirv(&device, "bruneton_precompute_single_scattering.spv");
        let density_shader = load_spirv(&device, "bruneton_precompute_scattering_density.spv");
        let indirect_shader = load_spirv(&device, "bruneton_precompute_indirect_irradiance.spv");
        let multi_shader = load_spirv(&device, "bruneton_precompute_multiple_scattering.spv");

        let scatter_fmt = lut_format(true);
        let (transmittance_pipeline, transmittance_bgl) = pipeline_2d(
            &device,
            &vertex,
            &transmittance_shader,
            1,
            transmittance_format(),
            &[],
        )?;
        let (direct_irradiance_pipeline, direct_irradiance_bgl) = pipeline_2d(
            &device,
            &vertex,
            &direct_shader,
            2,
            scatter_fmt,
            &[tex2d(1)],
        )?;
        let (single_scattering_pipeline, single_scattering_bgl) = pipeline_3d(
            &device,
            &vertex,
            &single_shader,
            3,
            scatter_fmt,
            &[tex2d(1)],
        )?;
        let (scattering_density_pipeline, scattering_density_bgl) = pipeline_3d(
            &device,
            &vertex,
            &density_shader,
            1,
            scatter_fmt,
            &[tex2d(1), tex3d(2), tex3d(3), tex3d(4), tex2d(5)],
        )?;
        let (indirect_irradiance_pipeline, indirect_irradiance_bgl) = pipeline_2d(
            &device,
            &vertex,
            &indirect_shader,
            2,
            scatter_fmt,
            &[tex3d(1), tex3d(2), tex3d(3)],
        )?;
        let (multiple_scattering_pipeline, multiple_scattering_bgl) = pipeline_3d(
            &device,
            &vertex,
            &multi_shader,
            2,
            scatter_fmt,
            &[tex2d(1), tex3d(2)],
        )?;

        Ok(Self {
            device,
            queue,
            quad,
            uniform_buf,
            transmittance_pipeline,
            transmittance_bgl,
            direct_irradiance_pipeline,
            direct_irradiance_bgl,
            single_scattering_pipeline,
            single_scattering_bgl,
            scattering_density_pipeline,
            scattering_density_bgl,
            indirect_irradiance_pipeline,
            indirect_irradiance_bgl,
            multiple_scattering_pipeline,
            multiple_scattering_bgl,
            scattering_format,
        })
    }

    fn write_uniforms(&self, lfr: &[[f32; 3]; 3], layer: i32, order: i32) {
        let mut bytes = [0u8; 256];
        for row in 0..3 {
            for col in 0..3 {
                let v = lfr[row][col];
                bytes[row * 16 + col * 4..row * 16 + col * 4 + 4].copy_from_slice(&v.to_le_bytes());
            }
        }
        bytes[48..52].copy_from_slice(&layer.to_le_bytes());
        bytes[52..56].copy_from_slice(&order.to_le_bytes());
        self.queue.write_buffer(&self.uniform_buf, 0, &bytes);
    }

    fn draw_2d(
        &self,
        target: &wgpu::Texture,
        textures: &[Option<&wgpu::Texture>],
        pipeline: &wgpu::RenderPipeline,
        bgl: &wgpu::BindGroupLayout,
        lfr: &[[f32; 3]; 3],
        width: u32,
        height: u32,
        layer: i32,
        order: i32,
    ) -> Result<(), BrunetonPrecomputeError> {
        self.write_uniforms(lfr, layer, order);
        let view = view_2d(target);
        let bind_group = self.make_bind_group(bgl, textures)?;
        self.render_pass(&[&view], pipeline, &bind_group, width, height, false)
    }

    fn draw_2d_multi(
        &self,
        targets: &[&wgpu::Texture],
        textures: &[Option<&wgpu::Texture>],
        pipeline: &wgpu::RenderPipeline,
        bgl: &wgpu::BindGroupLayout,
        width: u32,
        height: u32,
        layer: i32,
        order: i32,
        blend: bool,
    ) -> Result<(), BrunetonPrecomputeError> {
        self.write_uniforms(&luminance_from_radiance_identity(), layer, order);
        let views: Vec<_> = targets.iter().map(|t| view_2d(t)).collect();
        let view_refs: Vec<_> = views.iter().collect();
        let bind_group = self.make_bind_group(bgl, textures)?;
        self.render_pass(&view_refs, pipeline, &bind_group, width, height, blend)
    }

    fn draw_3d_layer(
        &self,
        targets: &[&wgpu::Texture],
        textures: &[Option<&wgpu::Texture>],
        pipeline: &wgpu::RenderPipeline,
        bgl: &wgpu::BindGroupLayout,
        lfr: &[[f32; 3]; 3],
        layer: u32,
        blend: bool,
    ) -> Result<(), BrunetonPrecomputeError> {
        self.write_uniforms(lfr, layer as i32, 0);
        let bind_group = self.make_bind_group(bgl, textures)?;
        self.render_3d_layer_to_scratch(targets, pipeline, &bind_group, layer, blend)
    }

    fn draw_3d_layer_with_order(
        &self,
        targets: &[&wgpu::Texture],
        textures: &[Option<&wgpu::Texture>],
        pipeline: &wgpu::RenderPipeline,
        bgl: &wgpu::BindGroupLayout,
        layer: u32,
        order: i32,
    ) -> Result<(), BrunetonPrecomputeError> {
        self.write_uniforms(&luminance_from_radiance_identity(), layer as i32, order);
        let bind_group = self.make_bind_group(bgl, textures)?;
        self.render_3d_layer_to_scratch(targets, pipeline, &bind_group, layer, false)
    }

    fn draw_3d_layer_multi(
        &self,
        targets: &[&wgpu::Texture],
        textures: &[Option<&wgpu::Texture>],
        pipeline: &wgpu::RenderPipeline,
        bgl: &wgpu::BindGroupLayout,
        lfr: &[[f32; 3]; 3],
        layer: u32,
        blend: bool,
    ) -> Result<(), BrunetonPrecomputeError> {
        self.draw_3d_layer(targets, textures, pipeline, bgl, lfr, layer, blend)
    }

    fn make_bind_group(
        &self,
        layout: &wgpu::BindGroupLayout,
        textures: &[Option<&wgpu::Texture>],
    ) -> Result<wgpu::BindGroup, BrunetonPrecomputeError> {
        let mut entries = vec![wgpu::BindGroupEntry {
            binding: 0,
            resource: self.uniform_buf.as_entire_binding(),
        }];
        let mut tex_views = Vec::new();
        for tex in textures.iter().flatten() {
            tex_views.push(view_for_sample(tex));
        }
        for (i, view) in tex_views.iter().enumerate() {
            entries.push(wgpu::BindGroupEntry {
                binding: (i + 1) as u32,
                resource: wgpu::BindingResource::TextureView(view),
            });
        }
        Ok(self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("planetarium.bruneton.precompute.bind_group"),
            layout,
            entries: &entries,
        }))
    }

    fn render_pass(
        &self,
        color_views: &[&wgpu::TextureView],
        pipeline: &wgpu::RenderPipeline,
        bind_group: &wgpu::BindGroup,
        width: u32,
        height: u32,
        blend: bool,
    ) -> Result<(), BrunetonPrecomputeError> {
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("planetarium.bruneton.precompute.encoder"),
            });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("planetarium.bruneton.precompute.pass"),
                color_attachments: &color_views
                    .iter()
                    .map(|view| {
                        Some(wgpu::RenderPassColorAttachment {
                            view,
                            resolve_target: None,
                            ops: wgpu::Operations {
                                load: if blend {
                                    wgpu::LoadOp::Load
                                } else {
                                    wgpu::LoadOp::Clear(wgpu::Color::BLACK)
                                },
                                store: wgpu::StoreOp::Store,
                            },
                        })
                    })
                    .collect::<Vec<_>>(),
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            pass.set_vertex_buffer(0, self.quad.slice(..));
            pass.set_viewport(0.0, 0.0, width as f32, height as f32, 0.0, 1.0);
            pass.draw(0..4, 0..1);
        }
        self.queue.submit(std::iter::once(encoder.finish()));
        self.device.poll(wgpu::Maintain::Wait);
        Ok(())
    }

    fn render_3d_layer_to_scratch(
        &self,
        targets: &[&wgpu::Texture],
        pipeline: &wgpu::RenderPipeline,
        bind_group: &wgpu::BindGroup,
        layer: u32,
        blend: bool,
    ) -> Result<(), BrunetonPrecomputeError> {
        let scratch: Vec<_> = targets
            .iter()
            .enumerate()
            .map(|(i, _)| {
                let label = format!("planetarium.bruneton.layer_scratch.{i}");
                create_texture_2d(
                    &self.device,
                    &label,
                    SCATTERING_TEXTURE_WIDTH,
                    SCATTERING_TEXTURE_HEIGHT,
                    self.scattering_format,
                )
            })
            .collect();
        let views: Vec<_> = scratch.iter().map(view_2d).collect();
        let view_refs: Vec<_> = views.iter().collect();

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("planetarium.bruneton.precompute.3d_layer.encoder"),
            });
        if blend {
            for (target, scratch) in targets.iter().zip(scratch.iter()) {
                encoder.copy_texture_to_texture(
                    wgpu::ImageCopyTexture {
                        texture: target,
                        mip_level: 0,
                        origin: wgpu::Origin3d {
                            x: 0,
                            y: 0,
                            z: layer,
                        },
                        aspect: wgpu::TextureAspect::All,
                    },
                    wgpu::ImageCopyTexture {
                        texture: scratch,
                        mip_level: 0,
                        origin: wgpu::Origin3d::ZERO,
                        aspect: wgpu::TextureAspect::All,
                    },
                    wgpu::Extent3d {
                        width: SCATTERING_TEXTURE_WIDTH,
                        height: SCATTERING_TEXTURE_HEIGHT,
                        depth_or_array_layers: 1,
                    },
                );
            }
        }
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("planetarium.bruneton.precompute.3d_layer.pass"),
                color_attachments: &view_refs
                    .iter()
                    .map(|view| {
                        Some(wgpu::RenderPassColorAttachment {
                            view,
                            resolve_target: None,
                            ops: wgpu::Operations {
                                load: if blend {
                                    wgpu::LoadOp::Load
                                } else {
                                    wgpu::LoadOp::Clear(wgpu::Color::BLACK)
                                },
                                store: wgpu::StoreOp::Store,
                            },
                        })
                    })
                    .collect::<Vec<_>>(),
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(pipeline);
            pass.set_bind_group(0, bind_group, &[]);
            pass.set_vertex_buffer(0, self.quad.slice(..));
            pass.set_viewport(
                0.0,
                0.0,
                SCATTERING_TEXTURE_WIDTH as f32,
                SCATTERING_TEXTURE_HEIGHT as f32,
                0.0,
                1.0,
            );
            pass.draw(0..4, 0..1);
        }
        for (scratch, target) in scratch.iter().zip(targets.iter()) {
            encoder.copy_texture_to_texture(
                wgpu::ImageCopyTexture {
                    texture: scratch,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::ImageCopyTexture {
                    texture: target,
                    mip_level: 0,
                    origin: wgpu::Origin3d {
                        x: 0,
                        y: 0,
                        z: layer,
                    },
                    aspect: wgpu::TextureAspect::All,
                },
                wgpu::Extent3d {
                    width: SCATTERING_TEXTURE_WIDTH,
                    height: SCATTERING_TEXTURE_HEIGHT,
                    depth_or_array_layers: 1,
                },
            );
        }
        self.queue.submit(std::iter::once(encoder.finish()));
        self.device.poll(wgpu::Maintain::Wait);
        Ok(())
    }
}

fn pipeline_2d(
    device: &wgpu::Device,
    vertex: &wgpu::ShaderModule,
    fragment: &wgpu::ShaderModule,
    color_count: usize,
    color_format: wgpu::TextureFormat,
    extra: &[wgpu::BindGroupLayoutEntry],
) -> Result<(wgpu::RenderPipeline, wgpu::BindGroupLayout), BrunetonPrecomputeError> {
    let mut entries = vec![ubo()];
    entries.extend_from_slice(extra);
    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("planetarium.bruneton.bgl"),
        entries: &entries,
    });
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("planetarium.bruneton.pipeline"),
        layout: Some(
            &device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: None,
                bind_group_layouts: &[&bgl],
                push_constant_ranges: &[],
            }),
        ),
        vertex: wgpu::VertexState {
            module: vertex,
            entry_point: "main",
            buffers: &[wgpu::VertexBufferLayout {
                array_stride: 8,
                step_mode: wgpu::VertexStepMode::Vertex,
                attributes: &[wgpu::VertexAttribute {
                    format: wgpu::VertexFormat::Float32x2,
                    offset: 0,
                    shader_location: 0,
                }],
            }],
            compilation_options: Default::default(),
        },
        fragment: Some(wgpu::FragmentState {
            module: fragment,
            entry_point: "main",
            targets: &vec![
                Some(wgpu::ColorTargetState {
                    format: color_format,
                    blend: blend_state_for_format(color_format),
                    write_mask: wgpu::ColorWrites::ALL,
                });
                color_count
            ],
            compilation_options: Default::default(),
        }),
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview: None,
        cache: None,
    });
    Ok((pipeline, bgl))
}

fn blend_state_for_format(format: wgpu::TextureFormat) -> Option<wgpu::BlendState> {
    if matches!(format, wgpu::TextureFormat::Rgba32Float) {
        return None;
    }
    Some(wgpu::BlendState {
        color: wgpu::BlendComponent {
            src_factor: wgpu::BlendFactor::One,
            dst_factor: wgpu::BlendFactor::One,
            operation: wgpu::BlendOperation::Add,
        },
        alpha: wgpu::BlendComponent {
            src_factor: wgpu::BlendFactor::One,
            dst_factor: wgpu::BlendFactor::One,
            operation: wgpu::BlendOperation::Add,
        },
    })
}

fn pipeline_3d(
    device: &wgpu::Device,
    vertex: &wgpu::ShaderModule,
    fragment: &wgpu::ShaderModule,
    color_count: usize,
    color_format: wgpu::TextureFormat,
    extra: &[wgpu::BindGroupLayoutEntry],
) -> Result<(wgpu::RenderPipeline, wgpu::BindGroupLayout), BrunetonPrecomputeError> {
    pipeline_2d(device, vertex, fragment, color_count, color_format, extra)
}

fn ubo() -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding: 0,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Uniform,
            has_dynamic_offset: false,
            min_binding_size: None,
        },
        count: None,
    }
}

fn tex2d(binding: u32) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Texture {
            sample_type: wgpu::TextureSampleType::Float { filterable: false },
            view_dimension: wgpu::TextureViewDimension::D2,
            multisampled: false,
        },
        count: None,
    }
}

fn tex3d(binding: u32) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Texture {
            sample_type: wgpu::TextureSampleType::Float { filterable: false },
            view_dimension: wgpu::TextureViewDimension::D3,
            multisampled: false,
        },
        count: None,
    }
}

fn load_spirv(device: &wgpu::Device, file: &str) -> wgpu::ShaderModule {
    let path = format!("{}/{}", env!("OUT_DIR"), file);
    let data = std::fs::read(&path).unwrap_or_else(|e| panic!("read SPIR-V {path}: {e}"));
    // SAFETY: these SPIR-V modules are generated by build.rs from checked-in
    // Bruneton GLSL using shaderc. Naga rejects some valid glslang output from
    // this shader family, so the native-only precompute path passes it directly
    // to the backend instead of reparsing it through Naga.
    unsafe {
        device.create_shader_module_spirv(&wgpu::ShaderModuleDescriptorSpirV {
            label: Some(file),
            source: wgpu::util::make_spirv_raw(&data),
        })
    }
}

fn view_for_sample(texture: &wgpu::Texture) -> wgpu::TextureView {
    if texture.depth_or_array_layers() > 1 {
        view_3d(texture)
    } else {
        view_2d(texture)
    }
}
