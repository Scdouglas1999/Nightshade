//! Offscreen smoke renderer used by Phase 1 spike tests.
//!
//! Renders a single-color triangle into a 512x512 RGBA texture and returns
//! the raw pixels. Verifies that wgpu device creation, pipeline compilation,
//! render pass, and buffer readback work in our environment before we plug
//! into Flutter's texture API.

use bytemuck::{Pod, Zeroable};

/// Pixel size of the offscreen target.
pub const SPIKE_SIZE: u32 = 512;

/// Render a single triangle to RGBA8 pixels. Returns `SPIKE_SIZE * SPIKE_SIZE * 4` bytes.
pub fn render_triangle() -> Vec<u8> {
    pollster::block_on(render_triangle_async())
}

#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable)]
struct Vertex {
    pos: [f32; 2],
    color: [f32; 3],
}

const VERTICES: &[Vertex] = &[
    Vertex { pos: [ 0.0,  0.7], color: [1.0, 0.0, 0.0] },
    Vertex { pos: [-0.7, -0.7], color: [0.0, 1.0, 0.0] },
    Vertex { pos: [ 0.7, -0.7], color: [0.0, 0.0, 1.0] },
];

async fn render_triangle_async() -> Vec<u8> {
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

    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("spike.shader"),
        source: wgpu::ShaderSource::Wgsl(include_str!("../shaders/spike.wgsl").into()),
    });

    let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("spike.pipeline_layout"),
        bind_group_layouts: &[],
        push_constant_ranges: &[],
    });

    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("spike.pipeline"),
        layout: Some(&pipeline_layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: "vs_main",
            compilation_options: Default::default(),
            buffers: &[wgpu::VertexBufferLayout {
                array_stride: std::mem::size_of::<Vertex>() as u64,
                step_mode: wgpu::VertexStepMode::Vertex,
                attributes: &wgpu::vertex_attr_array![0 => Float32x2, 1 => Float32x3],
            }],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: "fs_main",
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState {
                format: wgpu::TextureFormat::Rgba8UnormSrgb,
                blend: Some(wgpu::BlendState::REPLACE),
                write_mask: wgpu::ColorWrites::ALL,
            })],
        }),
        primitive: wgpu::PrimitiveState::default(),
        depth_stencil: None,
        multisample: wgpu::MultisampleState::default(),
        multiview: None,
        cache: None,
    });

    let vbuf = device.create_buffer_init_via_queue(&queue, "spike.vbuf", VERTICES);

    let target = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("spike.target"),
        size: wgpu::Extent3d { width: SPIKE_SIZE, height: SPIKE_SIZE, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8UnormSrgb,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let target_view = target.create_view(&wgpu::TextureViewDescriptor::default());

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("spike.encoder"),
    });
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("spike.pass"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &target_view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color { r: 0.02, g: 0.02, b: 0.06, a: 1.0 }),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });
        pass.set_pipeline(&pipeline);
        pass.set_vertex_buffer(0, vbuf.slice(..));
        pass.draw(0..VERTICES.len() as u32, 0..1);
    }

    let bytes_per_pixel = 4u32;
    let unpadded_bpr = SPIKE_SIZE * bytes_per_pixel;
    let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;
    let padded_bpr = unpadded_bpr.div_ceil(align) * align;
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("spike.readback"),
        size: (padded_bpr * SPIKE_SIZE) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    encoder.copy_texture_to_buffer(
        wgpu::ImageCopyTexture {
            texture: &target,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::ImageCopyBuffer {
            buffer: &readback,
            layout: wgpu::ImageDataLayout {
                offset: 0,
                bytes_per_row: Some(padded_bpr),
                rows_per_image: Some(SPIKE_SIZE),
            },
        },
        wgpu::Extent3d { width: SPIKE_SIZE, height: SPIKE_SIZE, depth_or_array_layers: 1 },
    );

    queue.submit(std::iter::once(encoder.finish()));

    let (tx, rx) = std::sync::mpsc::channel();
    readback.slice(..).map_async(wgpu::MapMode::Read, move |r| {
        tx.send(r).expect("readback channel closed");
    });
    device.poll(wgpu::Maintain::Wait);
    rx.recv().expect("readback recv").expect("readback map failed");

    let data = readback.slice(..).get_mapped_range();
    let mut out = Vec::with_capacity((unpadded_bpr * SPIKE_SIZE) as usize);
    for row in 0..SPIKE_SIZE {
        let start = (row * padded_bpr) as usize;
        out.extend_from_slice(&data[start..start + unpadded_bpr as usize]);
    }
    drop(data);
    readback.unmap();
    out
}

/// Tiny `DeviceExt` shim so the test code reads cleanly.
trait DeviceExt {
    fn create_buffer_init_via_queue<T: bytemuck::Pod>(
        &self,
        queue: &wgpu::Queue,
        label: &str,
        data: &[T],
    ) -> wgpu::Buffer;
}
impl DeviceExt for wgpu::Device {
    fn create_buffer_init_via_queue<T: bytemuck::Pod>(
        &self,
        queue: &wgpu::Queue,
        label: &str,
        data: &[T],
    ) -> wgpu::Buffer {
        let buf = self.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: (data.len() * std::mem::size_of::<T>()) as u64,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        queue.write_buffer(&buf, 0, bytemuck::cast_slice(data));
        buf
    }
}
