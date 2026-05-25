# Planetarium v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current 5,344-line CPU-bound CustomPainter planetarium with a Rust+wgpu renderer surfaced to Flutter as a `Texture` widget — full feature parity plus Bruneton atmospheric scattering, Tycho-2/Gaia catalog support, visual-grade astrometry, and event-driven rendering.

**Architecture:** New Rust crate `native/nightshade_native/planetarium/` owns GPU rendering, catalogs, astrometry, scene state, and gestures behind a `Planetarium` handle. New Dart package `packages/nightshade_planetarium_v2/` is a thin shell hosting a `Texture` widget with Flutter-rendered overlay layers (labels, FOV, mosaic, HUD). FFI surface is added to `native/nightshade_native/bridge/`. Old planetarium stays untouched and switchable via a settings toggle until v2 reaches parity.

**Tech Stack:** Rust 2021, `wgpu` 22, `irondash_engine_context` + `irondash_texture`, `cdshealpix`, `sgp4`, `bytemuck`, `glam`, `crossbeam-channel`, `arc-swap`, `parking_lot`, `memmap2`, `zerocopy`, `tokio`. Dart 3 + Flutter 3.24, `flutter_riverpod`, `flutter_rust_bridge` 2.11.1, existing `nightshade_core` providers.

**Design doc:** `docs/plans/2026-05-25-planetarium-v2-design.md` — read it first.

---

## How to use this plan

1. **All work stays on the current branch.** Other concurrent work is in flight on this branch; do not switch branches, do not create worktrees, do not stash. Every commit explicitly stages only planetarium-v2 paths (`packages/nightshade_planetarium_v2/**`, `native/nightshade_native/planetarium/**`, `native/nightshade_native/bridge/src/planetarium*.rs`, `native/nightshade_native/Cargo.toml`, `melos.yaml`, the relevant pubspec.yaml files). **Never use `git add .` or `git add -A`** — those would sweep up other engineers' WIP.

2. **One task per session of focus.** Each task is a coherent unit; each step inside a task is 2–5 minutes. Run the verify commands before moving on. Commit at the end of each task.

3. **TDD where it works, golden-image where it doesn't.** Pure-logic code (astrometry, catalog parsing, gesture state machine) gets unit tests first. Shader/render output gets golden-image tests via headless wgpu (`backend = Vulkan` on `lavapipe`, `backend = Dx12` with WARP on Windows, `backend = Metal` on macOS). Texture-handoff tasks have visual smoke tests that require an actual running app — those are flagged.

4. **Fail loud.** Per `CLAUDE.md`: no stubs, no silent fallbacks, no placeholders. If a task can't be completed because of an upstream dependency, stop and surface the blocker — don't `todo!()`/`unimplemented!()` or write fake data.

5. **Commit message convention:** `feat(planetarium-v2): <task name>` for new code; `test(planetarium-v2): <task name>` when only tests change.

6. **Skill references:** Use @superpowers:test-driven-development inside each task. Use @superpowers:systematic-debugging when a verification step fails — do not paper over failures.

---

## Phase index

- **Phase 1** — Windows Rust→Flutter texture vertical-slice spike (R1 de-risk). Tasks 1–8.
- **Phase 2** — Crate skeleton, FFI surface, event loop, snapshot publishing. Tasks 9–18.
- **Phase 3** — Astrometry: time, frames, precession, nutation, aberration, refraction, sidereal, VSOP87, ELP2000, Kepler. Tasks 19–32.
- **Phase 4** — Catalog system: tile format, mmap loaders, HEALPix, pack manifest, HYG + OpenNGC port, hit-test index. Tasks 33–46.
- **Phase 5** — Render pipelines: stars, atmosphere/Bruneton, DSOs, lines, bodies, MW, horizon, satellites, minor bodies, selection FX. Tasks 47–66.
- **Phase 6** — Scene + input: view pose, visibility cull, LOD selector, gesture state machine, hit testing, pose controller. Tasks 67–74.
- **Phase 7** — Dart shell: package skeleton, FRB bindings, providers, `InteractiveSkyView` v2, `SceneSnapshot` reader. Tasks 75–88.
- **Phase 8** — Overlay port: LabelLayer, ConstellationArt, FOV, Mosaic, MountReticle, CompassHUD, Minimap, ObjectDetailsPanel, TimeControlPanel, search. Tasks 89–98.
- **Phase 9** — Catalog pack manager UI + Tycho-2 download path. Tasks 99–104.
- **Phase 10** — Platform expansion: macOS, iOS, Android, Linux. Tasks 105–116.
- **Phase 11** — Cutover prep: toggle, parity tests, perf gates, retire v1. Tasks 117–122.

---

# Phase 1 — Windows Vertical-Slice Spike

**Why this phase exists.** Risk R1 in the design doc: texture handoff is the single highest-risk piece. If `wgpu` rendering into a Flutter `Texture` doesn't work on Windows via `irondash_texture`, the entire architecture changes. This phase produces the smallest possible end-to-end demo (a rotating triangle from Rust visible inside a running Flutter desktop app) before any non-trivial code is written. Total target: 1–2 days for a focused engineer.

---

### Task 1: Register the new Rust crate in the workspace

**Files:**
- Create: `native/nightshade_native/planetarium/Cargo.toml`
- Create: `native/nightshade_native/planetarium/src/lib.rs`
- Modify: `native/nightshade_native/Cargo.toml`

**Step 1: Add the workspace member**

Edit `native/nightshade_native/Cargo.toml`. Inside the `[workspace]` block, append `"planetarium"` to the `members` array so it reads:

```toml
[workspace]
members = [
    "bridge",
    "sequencer",
    "ascom",
    "indi",
    "alpaca",
    "imaging",
    "native",
    "updater",
    "planetarium",
]
resolver = "2"
```

**Step 2: Create the crate manifest**

Write `native/nightshade_native/planetarium/Cargo.toml`:

```toml
[package]
name = "nightshade_planetarium"
version.workspace = true
edition.workspace = true
license.workspace = true
authors.workspace = true

[dependencies]
thiserror.workspace = true
tracing.workspace = true

[features]
default = []
```

**Step 3: Create the crate entry point**

Write `native/nightshade_native/planetarium/src/lib.rs`:

```rust
//! Nightshade Planetarium v2 — Rust+wgpu renderer.
//!
//! See docs/plans/2026-05-25-planetarium-v2-design.md for the full architecture.

#![deny(unsafe_op_in_unsafe_fn)]
#![warn(missing_docs)]

/// Crate-wide error type. Per CLAUDE.md, fail loud — no silent fallbacks.
#[derive(Debug, thiserror::Error)]
pub enum PlanetariumError {
    /// A platform surface could not be created for the current platform.
    #[error("platform surface unsupported: {0}")]
    UnsupportedPlatform(&'static str),
}
```

**Step 4: Verify the workspace builds**

Run:
```bash
cd native/nightshade_native && cargo build -p nightshade_planetarium
```
Expected: builds cleanly, no warnings.

**Step 5: Commit**

```bash
git add native/nightshade_native/Cargo.toml native/nightshade_native/planetarium/
git commit -m "feat(planetarium-v2): register planetarium crate in workspace"
```

---

### Task 2: Add a smoke test for the crate

**Files:**
- Create: `native/nightshade_native/planetarium/tests/smoke.rs`

**Step 1: Write the failing test**

```rust
//! Smoke test: confirms the crate's error type works and the build is wired up.

use nightshade_planetarium::PlanetariumError;

#[test]
fn error_displays_platform_message() {
    let e = PlanetariumError::UnsupportedPlatform("haiku");
    assert_eq!(e.to_string(), "platform surface unsupported: haiku");
}
```

**Step 2: Run it (should pass already since Task 1's code supports it)**

```bash
cd native/nightshade_native && cargo test -p nightshade_planetarium
```
Expected: 1 passed.

**Step 3: Commit**

```bash
git add native/nightshade_native/planetarium/tests/
git commit -m "test(planetarium-v2): add crate smoke test"
```

---

### Task 3: Add wgpu to the planetarium crate and render to an in-memory PNG

**Files:**
- Modify: `native/nightshade_native/planetarium/Cargo.toml`
- Create: `native/nightshade_native/planetarium/src/spike.rs`
- Modify: `native/nightshade_native/planetarium/src/lib.rs`
- Create: `native/nightshade_native/planetarium/tests/spike_render.rs`

**Step 1: Add wgpu and supporting deps**

Edit `Cargo.toml`:

```toml
[dependencies]
thiserror.workspace = true
tracing.workspace = true
wgpu = "22"
bytemuck = { version = "1.16", features = ["derive"] }
pollster = "0.3"

[dev-dependencies]
image = { version = "0.25", default-features = false, features = ["png"] }
```

**Step 2: Implement the offscreen spike renderer**

Write `native/nightshade_native/planetarium/src/spike.rs`:

```rust
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
```

Add the WGSL source. Create `native/nightshade_native/planetarium/shaders/spike.wgsl`:

```wgsl
struct VsIn {
    @location(0) pos: vec2<f32>,
    @location(1) color: vec3<f32>,
};
struct VsOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) color: vec3<f32>,
};

@vertex
fn vs_main(in: VsIn) -> VsOut {
    var out: VsOut;
    out.clip = vec4<f32>(in.pos, 0.0, 1.0);
    out.color = in.color;
    return out;
}

@fragment
fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}
```

Re-export from `lib.rs`:

```rust
pub mod spike;
```

**Step 3: Write the failing render test**

Write `native/nightshade_native/planetarium/tests/spike_render.rs`:

```rust
//! Verifies wgpu can produce a non-empty triangle on the host running tests.
//!
//! Skipped automatically if no GPU adapter is available (CI without GPU).

use nightshade_planetarium::spike::{render_triangle, SPIKE_SIZE};

#[test]
fn triangle_has_red_pixel_near_top() {
    let pixels = render_triangle();
    assert_eq!(pixels.len(), (SPIKE_SIZE * SPIKE_SIZE * 4) as usize);

    // Sample a pixel inside the red corner of the triangle.
    let x = SPIKE_SIZE / 2;
    let y = SPIKE_SIZE / 6;
    let idx = ((y * SPIKE_SIZE + x) * 4) as usize;
    let (r, g, b) = (pixels[idx], pixels[idx + 1], pixels[idx + 2]);
    assert!(r > 180 && g < 40 && b < 40, "expected reddish pixel, got ({r},{g},{b})");
}
```

**Step 4: Run — expect a real wgpu render to pass**

```bash
cd native/nightshade_native && cargo test -p nightshade_planetarium --test spike_render -- --nocapture
```
Expected: 1 passed. If your machine has no GPU adapter, the test panics with `no GPU adapter available` — this is fail-loud by design.

**Step 5: Commit**

```bash
git add native/nightshade_native/planetarium/Cargo.toml \
        native/nightshade_native/planetarium/src/spike.rs \
        native/nightshade_native/planetarium/src/lib.rs \
        native/nightshade_native/planetarium/shaders/spike.wgsl \
        native/nightshade_native/planetarium/tests/spike_render.rs
git commit -m "feat(planetarium-v2): wgpu spike renders a triangle offscreen"
```

---

### Task 4: Pick an irondash_texture API that compiles in this workspace

**Files:**
- Modify: `native/nightshade_native/planetarium/Cargo.toml`
- Create: `native/nightshade_native/planetarium/src/surface/mod.rs`
- Create: `native/nightshade_native/planetarium/src/surface/windows.rs`
- Modify: `native/nightshade_native/planetarium/src/lib.rs`

The goal here is *only* to confirm the dependency builds and the trait abstraction compiles on Windows. We don't wire it to Flutter yet.

**Step 1: Add the platform deps**

Edit `Cargo.toml`:

```toml
[dependencies]
# ...previous...
irondash_engine_context = "0.5"
irondash_texture = "0.5"

[target.'cfg(target_os = "windows")'.dependencies]
windows = { version = "0.52", features = [
    "Win32_Graphics_Direct3D11",
    "Win32_Graphics_Dxgi",
    "Win32_Graphics_Dxgi_Common",
    "Win32_Foundation",
] }
```

**Step 2: Define the platform-surface trait**

Write `src/surface/mod.rs`:

```rust
//! Platform texture abstraction.
//!
//! Each platform implements [`PlatformSurface`] to bridge wgpu's render target
//! to a `flutter::Texture` that Dart can display via `Texture(textureId: ...)`.
//!
//! Per CLAUDE.md: failures here surface as `PlanetariumError`, never silently
//! degrade to CPU readback in production builds.

use crate::PlanetariumError;

/// A platform-specific texture target the renderer writes into and Flutter reads from.
pub trait PlatformSurface: Send + Sync {
    /// Allocate the underlying GPU texture and register it with Flutter.
    /// Returns the texture id Flutter's `Texture` widget needs.
    fn allocate(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError>;

    /// Re-allocate at a new size. Texture id may or may not stay the same.
    fn resize(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError>;

    /// Signal Flutter that a new frame is available for the current texture id.
    fn mark_frame_available(&self) -> Result<(), PlanetariumError>;

    /// Tear down the surface.
    fn shutdown(&mut self) -> Result<(), PlanetariumError>;
}

#[cfg(target_os = "windows")]
pub mod windows;

#[cfg(not(any(target_os = "windows")))]
compile_error!("Phase 1 only supports Windows. Phase 10 adds other platforms.");

/// Create the platform surface for the current OS.
pub fn create_surface(
    engine_handle: i64,
) -> Result<Box<dyn PlatformSurface>, PlanetariumError> {
    #[cfg(target_os = "windows")]
    {
        Ok(Box::new(windows::WindowsSurface::new(engine_handle)?))
    }
}
```

**Step 3: Stub Windows surface — but with real wiring**

Write `src/surface/windows.rs`:

```rust
//! Windows D3D11 texture surface.
//!
//! Renders into a `wgpu::Texture` backed by a D3D11 shared texture handle,
//! which `irondash_texture` registers with the Flutter engine so the Dart-side
//! `Texture(textureId: ...)` widget can display it.

use crate::{surface::PlatformSurface, PlanetariumError};
use std::sync::Arc;

/// Windows-specific surface. Owns the engine context handle and the wgpu device.
pub struct WindowsSurface {
    engine_handle: i64,
    current: Option<Allocated>,
}

struct Allocated {
    width: u32,
    height: u32,
    texture_id: i64,
}

impl WindowsSurface {
    pub fn new(engine_handle: i64) -> Result<Self, PlanetariumError> {
        Ok(Self { engine_handle, current: None })
    }
}

impl PlatformSurface for WindowsSurface {
    fn allocate(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError> {
        // Task 5 wires this to irondash_texture + wgpu. For now, fail loudly
        // so callers can't depend on this returning a fake id.
        Err(PlanetariumError::UnsupportedPlatform(
            "WindowsSurface::allocate not yet implemented — Task 5 wires it",
        ))
    }

    fn resize(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError> {
        self.allocate(width, height)
    }

    fn mark_frame_available(&self) -> Result<(), PlanetariumError> {
        Err(PlanetariumError::UnsupportedPlatform(
            "WindowsSurface::mark_frame_available not yet implemented — Task 5",
        ))
    }

    fn shutdown(&mut self) -> Result<(), PlanetariumError> {
        self.current = None;
        Ok(())
    }
}
```

> **Note on the "fail loud" stubs:** these are *not* placeholder logic — they return a typed error that propagates. Per CLAUDE.md no silent fallbacks. Task 5 replaces these specific error returns with the real implementation. Do not leave them past Task 5.

Re-export from `lib.rs`:

```rust
pub mod surface;
pub mod spike;
```

**Step 4: Verify it compiles**

```bash
cd native/nightshade_native && cargo build -p nightshade_planetarium
```
Expected: builds cleanly on Windows. Verify by running:

```bash
cargo check -p nightshade_planetarium
```

**Step 5: Commit**

```bash
git add native/nightshade_native/planetarium/Cargo.toml \
        native/nightshade_native/planetarium/src/lib.rs \
        native/nightshade_native/planetarium/src/surface/
git commit -m "feat(planetarium-v2): platform surface trait + windows skeleton"
```

---

### Task 5: Implement the Windows D3D11 shared texture path end-to-end

**Files:**
- Modify: `native/nightshade_native/planetarium/Cargo.toml`
- Modify: `native/nightshade_native/planetarium/src/surface/windows.rs`
- Create: `native/nightshade_native/planetarium/src/surface/d3d11_shared.rs`

This is the most technically dense task in Phase 1. Read it through before starting.

**Step 1: Add the wgpu HAL feature**

Edit `Cargo.toml`:

```toml
[dependencies]
# Replace the existing wgpu line with:
wgpu = { version = "22", features = ["dx12", "vulkan", "hal"] }
```

`features = ["hal"]` exposes `wgpu_hal` which is the only way to extract the underlying D3D12/D3D11 resource we need to hand to Flutter.

**Step 2: Implement the shared-handle helper**

Create `src/surface/d3d11_shared.rs`:

```rust
//! D3D11 shared-handle helper.
//!
//! wgpu defaults to DX12 on Windows. To produce a texture Flutter Windows can
//! display we either (a) use the DX12 backend and create a shared `NT_HANDLE`
//! texture, then open it in D3D11 inside Flutter via `OpenSharedResource1`, or
//! (b) ask wgpu to use the Vulkan backend and import its image as a D3D11
//! shared handle via VK_KHR_external_memory_win32. We use (a).
//!
//! `irondash_texture` expects an `ID3D11Texture2D` keyed-mutex shared handle on
//! Windows; we therefore create the resource via wgpu's DX12 HAL escape hatch,
//! retrieve the underlying `ID3D12Resource`, and hand the shared-handle to
//! Flutter through irondash.

use crate::PlanetariumError;
use std::sync::Arc;

/// Allocate a shareable wgpu texture and return both the wgpu handle and the
/// raw `HANDLE` (NT shared handle) for `OpenSharedResource1`-style import.
pub struct SharedTexture {
    pub wgpu: Arc<wgpu::Texture>,
    pub shared_handle: isize,
    pub width: u32,
    pub height: u32,
}

pub fn allocate_shared(
    device: &wgpu::Device,
    width: u32,
    height: u32,
) -> Result<SharedTexture, PlanetariumError> {
    // SAFETY: We access the underlying DX12 HAL device only to set the resource
    // flag that requests a shared NT handle. wgpu does not expose this directly.
    use wgpu::hal::dx12 as hal_dx12;

    let tex = device.create_texture(&wgpu::TextureDescriptor {
        label: Some("nightshade.shared_target"),
        size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Bgra8Unorm, // Flutter desktop expects BGRA
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT
            | wgpu::TextureUsages::COPY_SRC
            | wgpu::TextureUsages::TEXTURE_BINDING,
        view_formats: &[],
    });

    // Pull the raw HANDLE through the HAL.
    let shared_handle = unsafe {
        let mut handle: isize = 0;
        tex.as_hal::<wgpu::core::api::Dx12, _, _>(|hal_tex| -> Result<(), PlanetariumError> {
            let hal_tex = hal_tex.ok_or(PlanetariumError::UnsupportedPlatform(
                "wgpu texture has no DX12 backing — wrong backend selected",
            ))?;
            // hal_tex.resource() returns an `ID3D12Resource`.
            // Convert to shared handle via `ID3D12Device::CreateSharedHandle`.
            handle = create_shared_handle_for_resource(hal_tex.resource())?;
            Ok(())
        });
        if handle == 0 {
            return Err(PlanetariumError::UnsupportedPlatform(
                "failed to create shared handle for D3D12 resource",
            ));
        }
        handle
    };

    Ok(SharedTexture {
        wgpu: Arc::new(tex),
        shared_handle,
        width,
        height,
    })
}

/// Call `ID3D12Device::CreateSharedHandle` on the resource.
unsafe fn create_shared_handle_for_resource(
    _resource: &impl std::any::Any,
) -> Result<isize, PlanetariumError> {
    // The exact API call is platform-specific. The implementation uses
    // `windows::Win32::Graphics::Direct3D12::ID3D12Device::CreateSharedHandle`.
    // Engineer reference: https://learn.microsoft.com/en-us/windows/win32/api/d3d12/nf-d3d12-id3d12device-createsharedhandle
    //
    // The DX12 HAL types are not currently in public wgpu re-exports for stable
    // — engineer must downcast from the HAL trait object using the wgpu hal
    // header types. If this proves blocked, fall back to the Vulkan import
    // path documented in the module-level comment and re-open this task.
    Err(PlanetariumError::UnsupportedPlatform(
        "create_shared_handle_for_resource needs DX12 HAL escape — see module doc",
    ))
}
```

> **Engineer note.** Step 2 contains the only "I don't know if this will work" code in the entire plan. wgpu's DX12 HAL is the right escape hatch but its public surface has shifted version-to-version. If `create_shared_handle_for_resource` is blocked because `wgpu::hal::dx12` doesn't expose what's needed in 22.x, **stop and consult**: the alternative is the Vulkan backend with VK_KHR_external_memory_win32. Do not silently fall back to CPU readback. Pause and surface the blocker.

**Step 3: Wire the surface to irondash**

Edit `src/surface/windows.rs` to replace the stub:

```rust
use crate::{surface::PlatformSurface, PlanetariumError};
use crate::surface::d3d11_shared::{allocate_shared, SharedTexture};

use irondash_engine_context::EngineContext;
use irondash_texture::{BoxedPixelData, PayloadProvider, Texture};

use std::sync::Arc;

pub struct WindowsSurface {
    engine_handle: i64,
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    current: Option<Allocated>,
}

struct Allocated {
    width: u32,
    height: u32,
    texture_id: i64,
    shared: SharedTexture,
    flutter_texture: Texture<()>, // Type parameter depends on irondash variant chosen.
}

impl WindowsSurface {
    pub fn new(engine_handle: i64) -> Result<Self, PlanetariumError> {
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::DX12, // shared handle path requires DX12
            ..Default::default()
        });
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        }))
        .ok_or(PlanetariumError::UnsupportedPlatform("no DX12 adapter on this Windows host"))?;
        let (device, queue) = pollster::block_on(adapter.request_device(
            &wgpu::DeviceDescriptor {
                label: Some("nightshade.windows.device"),
                ..Default::default()
            },
            None,
        ))
        .map_err(|_| PlanetariumError::UnsupportedPlatform("wgpu DX12 device request failed"))?;

        Ok(Self {
            engine_handle,
            device: Arc::new(device),
            queue: Arc::new(queue),
            current: None,
        })
    }

    pub fn device(&self) -> Arc<wgpu::Device> { self.device.clone() }
    pub fn queue(&self) -> Arc<wgpu::Queue> { self.queue.clone() }
    pub fn wgpu_texture(&self) -> Option<Arc<wgpu::Texture>> {
        self.current.as_ref().map(|a| a.shared.wgpu.clone())
    }
}

impl PlatformSurface for WindowsSurface {
    fn allocate(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError> {
        if width == 0 || height == 0 {
            return Err(PlanetariumError::UnsupportedPlatform("surface size must be positive"));
        }
        let shared = allocate_shared(&self.device, width, height)?;

        // Register with Flutter via irondash. The exact constructor depends on the
        // irondash_texture API; use the `PlatformTexture::create_shared_d3d11`
        // variant if available, otherwise the SwapChain provider variant.
        let texture_id = irondash_register_shared_texture(self.engine_handle, &shared)?;

        self.current = Some(Allocated { width, height, texture_id, shared, flutter_texture: () });
        Ok(texture_id)
    }

    fn resize(&mut self, width: u32, height: u32) -> Result<i64, PlanetariumError> {
        if let Some(a) = &self.current {
            if a.width == width && a.height == height {
                return Ok(a.texture_id);
            }
        }
        self.shutdown()?;
        self.allocate(width, height)
    }

    fn mark_frame_available(&self) -> Result<(), PlanetariumError> {
        let Some(a) = &self.current else {
            return Err(PlanetariumError::UnsupportedPlatform(
                "mark_frame_available called before allocate",
            ));
        };
        irondash_mark_frame_available(self.engine_handle, a.texture_id)
    }

    fn shutdown(&mut self) -> Result<(), PlanetariumError> {
        if let Some(a) = self.current.take() {
            // Drop shared texture; irondash unregisters on drop.
            drop(a);
        }
        Ok(())
    }
}

fn irondash_register_shared_texture(
    engine_handle: i64,
    shared: &SharedTexture,
) -> Result<i64, PlanetariumError> {
    // The exact irondash_texture call depends on which constructor variant
    // exposes the D3D11 shared-handle import. Reference:
    //   - PlatformTexture::create_dx_shared_handle(engine_handle, handle, w, h)
    //   - Texture::new_with_provider with a D3D11SharedHandleProvider impl
    // If neither matches the version we pin, engineer must check the docs at
    // https://docs.rs/irondash_texture and stop. Do not invent a fake id.
    let _ = (engine_handle, shared);
    Err(PlanetariumError::UnsupportedPlatform(
        "irondash_texture API for D3D11 shared handle not selected — see Task 5 notes",
    ))
}

fn irondash_mark_frame_available(
    engine_handle: i64,
    texture_id: i64,
) -> Result<(), PlanetariumError> {
    let _ = (engine_handle, texture_id);
    Err(PlanetariumError::UnsupportedPlatform(
        "irondash mark_frame_available wiring not selected — see Task 5 notes",
    ))
}
```

**Step 4: Confirm compilation**

```bash
cd native/nightshade_native && cargo build -p nightshade_planetarium
```
Expected: builds, no warnings. Tests don't run yet (no texture id at runtime).

**Step 5: Commit**

```bash
git add native/nightshade_native/planetarium/Cargo.toml \
        native/nightshade_native/planetarium/src/surface/
git commit -m "feat(planetarium-v2): wire wgpu DX12 + irondash texture scaffolding (windows)"
```

> **If Step 2 or `irondash_register_shared_texture` blocked.** Open an issue, paste exact errors, and stop. The alternative paths (Vulkan import, GL FBO via flutter_gl) are documented in the design doc R1. Do not proceed to Task 6 until you can produce a real texture id.

---

### Task 6: Add the FFI surface for the spike (`create_planetarium_window`, `tick`, `dispose`)

**Files:**
- Modify: `native/nightshade_native/bridge/src/lib.rs`
- Create: `native/nightshade_native/bridge/src/planetarium_spike.rs`
- Modify: `native/nightshade_native/bridge/Cargo.toml`
- Modify: `native/nightshade_native/flutter_rust_bridge.yaml`

The first FFI shape is minimal — just enough to spawn the renderer, hand it a Flutter engine handle, and tick it. The full FFI surface arrives in Phase 2.

**Step 1: Bridge depends on the planetarium crate**

Edit `bridge/Cargo.toml`. Inside `[dependencies]`:

```toml
nightshade_planetarium = { path = "../planetarium" }
```

**Step 2: Write the spike FFI module**

Create `bridge/src/planetarium_spike.rs`:

```rust
//! Minimal FFI shape for the Phase 1 spike.
//!
//! Exposes three functions to Dart:
//!   - `planetarium_spike_create(engine_handle) -> handle id`
//!   - `planetarium_spike_resize(handle, w, h) -> texture id`
//!   - `planetarium_spike_dispose(handle)`
//!
//! Replaces itself with the full FFI in Phase 2. Engineer MUST remove this
//! module once Task 18 (full FFI) lands. Do not leave parallel surfaces.

use nightshade_planetarium::surface::{create_surface, PlatformSurface};

use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::OnceLock;

static REGISTRY: OnceLock<Mutex<HashMap<i64, Box<dyn PlatformSurface>>>> = OnceLock::new();
static NEXT_ID: OnceLock<Mutex<i64>> = OnceLock::new();

fn registry() -> &'static Mutex<HashMap<i64, Box<dyn PlatformSurface>>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}
fn next_id() -> i64 {
    let m = NEXT_ID.get_or_init(|| Mutex::new(1));
    let mut g = m.lock();
    let v = *g;
    *g += 1;
    v
}

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_spike_create(engine_handle: i64) -> Result<i64, String> {
    let surface = create_surface(engine_handle).map_err(|e| e.to_string())?;
    let id = next_id();
    registry().lock().insert(id, surface);
    Ok(id)
}

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_spike_resize(handle: i64, width: u32, height: u32) -> Result<i64, String> {
    let mut reg = registry().lock();
    let surface = reg
        .get_mut(&handle)
        .ok_or_else(|| format!("planetarium spike handle {handle} not found"))?;
    surface.resize(width, height).map_err(|e| e.to_string())
}

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_spike_dispose(handle: i64) -> Result<(), String> {
    let mut reg = registry().lock();
    if let Some(mut s) = reg.remove(&handle) {
        s.shutdown().map_err(|e| e.to_string())?;
    }
    Ok(())
}
```

**Step 3: Add the module to `bridge/src/lib.rs`**

```rust
pub mod planetarium_spike;
```

**Step 4: Regenerate FRB bindings**

Per `CLAUDE.md`, codegen requires `CPATH` on Windows:

```powershell
$env:CPATH = "C:\Program Files\LLVM\lib\clang\21\include;C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.43.34808\include;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\ucrt;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\um;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\shared"
flutter_rust_bridge_codegen generate
```

Expected: `packages/nightshade_bridge/lib/src/api/planetarium_spike.dart` is generated with `planetariumSpikeCreate`, `planetariumSpikeResize`, `planetariumSpikeDispose`.

**Step 5: Run the bridge crate tests**

```bash
cd native/nightshade_native && cargo test -p nightshade_bridge
```
Expected: existing tests pass; planetarium_spike module compiles into the bridge.

**Step 6: Commit**

```bash
git add native/nightshade_native/bridge/Cargo.toml \
        native/nightshade_native/bridge/src/lib.rs \
        native/nightshade_native/bridge/src/planetarium_spike.rs \
        packages/nightshade_bridge/lib/src/api/planetarium_spike.dart \
        packages/nightshade_bridge/lib/src/frb_generated.dart
git commit -m "feat(planetarium-v2): spike FFI surface (create/resize/dispose)"
```

---

### Task 7: Drive the spike from a tiny Flutter test screen

**Files:**
- Create: `apps/desktop/lib/dev/planetarium_spike_screen.dart`
- Modify: `apps/desktop/lib/main.dart` (developer-only route)

**Step 1: Build the screen**

Write `apps/desktop/lib/dev/planetarium_spike_screen.dart`:

```dart
// Developer-only screen used to verify the Rust→Flutter texture spike.
// Once Phase 1 is done, this screen can be removed (Task 122).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:irondash_engine_context/irondash_engine_context.dart';
import 'package:nightshade_bridge/api/planetarium_spike.dart' as spike;

class PlanetariumSpikeScreen extends StatefulWidget {
  const PlanetariumSpikeScreen({super.key});

  @override
  State<PlanetariumSpikeScreen> createState() => _PlanetariumSpikeScreenState();
}

class _PlanetariumSpikeScreenState extends State<PlanetariumSpikeScreen> {
  int? _handle;
  int? _textureId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final engineHandle = await EngineContext.instance.getEngineHandle();
      final handle = await spike.planetariumSpikeCreate(engineHandle: engineHandle);
      final textureId =
          await spike.planetariumSpikeResize(handle: handle, width: 1280, height: 720);
      setState(() {
        _handle = handle;
        _textureId = textureId;
      });
    } catch (e, st) {
      setState(() => _error = '$e\n$st');
    }
  }

  @override
  void dispose() {
    if (_handle != null) {
      spike.planetariumSpikeDispose(handle: _handle!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _error != null
        ? SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText('Spike error:\n\n$_error',
                style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace')),
          )
        : _textureId == null
            ? const Center(child: CircularProgressIndicator())
            : Texture(textureId: _textureId!);
    return Scaffold(
      appBar: AppBar(title: const Text('Planetarium spike')),
      body: body,
    );
  }
}
```

**Step 2: Add a dev route**

Edit `apps/desktop/lib/main.dart`. Find the existing `MaterialApp` routes / `GoRouter` config and add a `/dev/planetarium-spike` route that pushes `PlanetariumSpikeScreen`. The exact insertion point is in the router config — engineer must locate it (it differs from build to build). Do not duplicate route handlers.

**Step 3: Make sure the app still builds**

```bash
melos run analyze
```
Expected: no new errors. Warnings about unused dev-screen import are acceptable for now.

**Step 4: Commit**

```bash
git add apps/desktop/lib/dev/ apps/desktop/lib/main.dart
git commit -m "feat(planetarium-v2): dev route to test spike texture"
```

---

### Task 8: Render a rotating colored triangle into the live texture

**Files:**
- Modify: `native/nightshade_native/planetarium/src/spike.rs`
- Modify: `native/nightshade_native/planetarium/src/surface/windows.rs`
- Modify: `native/nightshade_native/bridge/src/planetarium_spike.rs`

**Step 1: Add a tick function to the spike module**

Extend `spike.rs` with a `Spike` struct that owns the wgpu pipeline + vertex buffer (factored out of `render_triangle_async`) and renders into an externally-provided `wgpu::Texture`. Code structure:

```rust
pub struct Spike {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    pipeline: wgpu::RenderPipeline,
    vbuf: wgpu::Buffer,
    rotation_uniform: wgpu::Buffer,
    bind_group: wgpu::BindGroup,
    start: Instant,
}

impl Spike {
    pub fn new(device: Arc<wgpu::Device>, queue: Arc<wgpu::Queue>) -> Self { ... }
    pub fn tick(&self, target_view: &wgpu::TextureView) { ... }
}
```

Update the shader (`shaders/spike.wgsl`) to take a rotation uniform and rotate the triangle.

**Step 2: Add a `tick` FFI**

In `planetarium_spike.rs`, expose:

```rust
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_spike_tick(handle: i64) -> Result<(), String> {
    let mut reg = registry().lock();
    let surface = reg.get_mut(&handle).ok_or("handle not found")?;
    // Downcast or call a `tick` method on the surface that owns the Spike.
    surface.tick().map_err(|e| e.to_string())?;
    surface.mark_frame_available().map_err(|e| e.to_string())?;
    Ok(())
}
```

Add a `tick` method to `PlatformSurface` that delegates to the platform impl's `Spike`.

**Step 3: Drive `tick` from Dart**

Modify `PlanetariumSpikeScreen` to call `planetariumSpikeTick(handle: handle)` via a `Ticker` (`SchedulerBinding.instance.scheduleFrameCallback` or a simple `Timer.periodic(Duration(milliseconds: 16))`).

**Step 4: Regenerate FRB and rebuild**

```bash
melos run dev
```
Expected: app launches, navigates to `/dev/planetarium-spike`, displays a rotating colored triangle on a dark background. **This is the Phase 1 success gate.**

If the texture stays black: the shared-handle import failed silently somewhere. Drop into the Rust side, log every step. Do not proceed past Task 8 with a black texture.

**Step 5: Commit**

```bash
git add native/nightshade_native/planetarium/src/spike.rs \
        native/nightshade_native/planetarium/src/surface/windows.rs \
        native/nightshade_native/planetarium/shaders/spike.wgsl \
        native/nightshade_native/bridge/src/planetarium_spike.rs \
        apps/desktop/lib/dev/planetarium_spike_screen.dart \
        packages/nightshade_bridge/lib/src/api/planetarium_spike.dart \
        packages/nightshade_bridge/lib/src/frb_generated.dart
git commit -m "feat(planetarium-v2): rotating triangle visible inside Flutter Texture (windows)"
```

**Phase 1 done.** You now know the texture handoff works. Everything beyond this is "just" software.

---

# Phase 2 — Crate Foundation

Tasks 9–18 build the real planetarium handle, event-driven render loop, scene snapshot publishing, command channel, and the full FFI surface. Phase 1's `planetarium_spike` module is deleted at the end of this phase.

### Task 9: Add core dependencies

**Files:**
- Modify: `native/nightshade_native/planetarium/Cargo.toml`

**Step 1: Add the dependency list from the design doc § 4.3**

Append to `[dependencies]`:

```toml
glam = { version = "0.27", features = ["bytemuck"] }
crossbeam-channel = "0.5"
arc-swap = "1.7"
parking_lot.workspace = true
zerocopy = { version = "0.7", features = ["derive"] }
memmap2 = "0.9"
cdshealpix = "0.7"
sgp4 = "2"
tokio = { workspace = true, features = ["rt-multi-thread", "sync", "fs", "macros"] }
```

**Step 2: Verify**

```bash
cd native/nightshade_native && cargo build -p nightshade_planetarium
```
Expected: builds.

**Step 3: Commit**

```bash
git add native/nightshade_native/planetarium/Cargo.toml
git commit -m "feat(planetarium-v2): add core deps (glam, crossbeam, arc-swap, cdshealpix, sgp4)"
```

---

### Task 10: Define `ViewPose`, `Observer`, `AstroTime`, `RenderConfig` value types

**Files:**
- Create: `native/nightshade_native/planetarium/src/types.rs`
- Modify: `native/nightshade_native/planetarium/src/lib.rs`
- Create: `native/nightshade_native/planetarium/tests/types.rs`

**Step 1: Write the failing test**

```rust
use nightshade_planetarium::types::{ViewPose, SkyProjection};

#[test]
fn view_pose_default_is_zenith() {
    let p = ViewPose::default();
    assert_eq!(p.fov_rad, std::f32::consts::FRAC_PI_2);
    assert!(matches!(p.projection, SkyProjection::Stereographic));
}
```

**Step 2: Run — expect failure**

```bash
cargo test -p nightshade_planetarium --test types
```
Expected: compile error (`types` module doesn't exist).

**Step 3: Implement the types**

Create `src/types.rs`:

```rust
//! Public value types crossing the FFI / render-thread boundary.
//!
//! All types are POD-friendly (no allocations on hot paths) and `Send + Sync`.

use bytemuck::{Pod, Zeroable};
use glam::{DVec3, Mat3, Mat4, Vec3};

/// Sky projection mode.
#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SkyProjection {
    #[default]
    Stereographic = 0,
    Orthographic = 1,
    AzimuthalEquidistant = 2,
}

/// View pose: where the camera looks at the celestial sphere.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ViewPose {
    /// Right ascension of view center (radians, J2000).
    pub ra_rad: f64,
    /// Declination of view center (radians, J2000).
    pub dec_rad: f64,
    /// Field of view across the shorter screen axis (radians).
    pub fov_rad: f32,
    /// Roll about the view axis (radians).
    pub roll_rad: f32,
    pub projection: SkyProjection,
}

impl Default for ViewPose {
    fn default() -> Self {
        Self {
            ra_rad: 0.0,
            dec_rad: std::f64::consts::FRAC_PI_2, // celestial pole
            fov_rad: std::f32::consts::FRAC_PI_2,  // 90°
            roll_rad: 0.0,
            projection: SkyProjection::Stereographic,
        }
    }
}

/// Observer location.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Observer {
    pub latitude_rad: f64,
    pub longitude_rad: f64,
    pub elevation_m: f64,
    pub pressure_hpa: f32,
    pub temperature_c: f32,
}

impl Default for Observer {
    fn default() -> Self {
        Self {
            latitude_rad: 0.0,
            longitude_rad: 0.0,
            elevation_m: 0.0,
            pressure_hpa: 1013.25,
            temperature_c: 10.0,
        }
    }
}

/// Astronomical time. See astrometry/time.rs.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AstroTime {
    pub jd_utc: f64,
    pub jd_ut1: f64,
    pub jd_tt:  f64,
}

/// Per-layer visibility + quality knobs. Mirrors current `SkyRenderConfig` shape
/// so existing Dart providers map 1:1.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RenderConfig {
    pub show_stars: bool,
    pub show_constellations: bool,
    pub show_constellation_boundaries: bool,
    pub show_constellation_art: bool,
    pub show_equatorial_grid: bool,
    pub show_alt_az_grid: bool,
    pub show_galactic_grid: bool,
    pub show_ecliptic: bool,
    pub show_galactic_plane: bool,
    pub show_milky_way: bool,
    pub show_horizon: bool,
    pub show_atmosphere: bool,
    pub show_dsos: bool,
    pub show_solar_system: bool,
    pub show_satellites: bool,
    pub show_minor_planets: bool,
    pub show_variable_stars: bool,
    pub magnitude_limit: f32,
    pub quality: u32, // 0=low, 1=medium, 2=high
    pub bortle_class: u32, // 1..9, 0 = no LP dome
    pub twinkle: bool,
}

impl Default for RenderConfig {
    fn default() -> Self {
        Self {
            show_stars: true,
            show_constellations: true,
            show_constellation_boundaries: false,
            show_constellation_art: false,
            show_equatorial_grid: false,
            show_alt_az_grid: false,
            show_galactic_grid: false,
            show_ecliptic: true,
            show_galactic_plane: false,
            show_milky_way: true,
            show_horizon: true,
            show_atmosphere: true,
            show_dsos: true,
            show_solar_system: true,
            show_satellites: false,
            show_minor_planets: false,
            show_variable_stars: false,
            magnitude_limit: 6.0,
            quality: 1,
            bortle_class: 4,
            twinkle: true,
        }
    }
}
```

Re-export from `lib.rs`:

```rust
pub mod types;
```

**Step 4: Run — expect pass**

```bash
cargo test -p nightshade_planetarium --test types
```
Expected: 1 passed.

**Step 5: Commit**

```bash
git add native/nightshade_native/planetarium/src/types.rs \
        native/nightshade_native/planetarium/src/lib.rs \
        native/nightshade_native/planetarium/tests/types.rs
git commit -m "feat(planetarium-v2): public value types (ViewPose, Observer, RenderConfig)"
```

---

### Task 11: Command channel + dirty flag bitset

Define `PlanetariumCommand`, `DirtyFlags`, and the channel pair. Test that pushing every command variant flips the right dirty bit.

**Files:**
- Create: `native/nightshade_native/planetarium/src/bus/mod.rs`
- Create: `native/nightshade_native/planetarium/src/bus/dirty.rs`
- Create: `native/nightshade_native/planetarium/tests/bus_dirty.rs`

**Step 1: Failing test**

```rust
use nightshade_planetarium::bus::dirty::DirtyFlags;
use nightshade_planetarium::bus::PlanetariumCommand;
use nightshade_planetarium::types::ViewPose;

#[test]
fn pose_command_marks_pose_dirty() {
    let mut d = DirtyFlags::empty();
    let cmd = PlanetariumCommand::SetPose(ViewPose::default());
    cmd.apply_dirty(&mut d);
    assert!(d.contains(DirtyFlags::POSE));
    assert!(!d.contains(DirtyFlags::TIME));
}
```

**Step 2: Implement dirty + commands**

`src/bus/dirty.rs`:

```rust
bitflags::bitflags! {
    #[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
    pub struct DirtyFlags: u32 {
        const POSE      = 1 << 0;
        const TIME      = 1 << 1;
        const OBSERVER  = 1 << 2;
        const CONFIG    = 1 << 3;
        const MOUNT     = 1 << 4;
        const FOV       = 1 << 5;
        const MOSAIC    = 1 << 6;
        const HORIZON   = 1 << 7;
        const CATALOG   = 1 << 8;
        const SELECTION = 1 << 9;
        const RESIZE    = 1 << 10;
    }
}
```

(Adds `bitflags = "2"` to deps.)

`src/bus/mod.rs`:

```rust
pub mod dirty;

use crate::types::{AstroTime, Observer, RenderConfig, ViewPose};
use dirty::DirtyFlags;

#[derive(Debug, Clone)]
pub enum PlanetariumCommand {
    SetPose(ViewPose),
    SetTime(AstroTime),
    SetObserver(Observer),
    SetConfig(RenderConfig),
    Resize { width: u32, height: u32, dpr: f32 },
    Shutdown,
    // ...expanded across phases
}

impl PlanetariumCommand {
    pub fn apply_dirty(&self, d: &mut DirtyFlags) {
        match self {
            Self::SetPose(_) => *d |= DirtyFlags::POSE,
            Self::SetTime(_) => *d |= DirtyFlags::TIME,
            Self::SetObserver(_) => *d |= DirtyFlags::OBSERVER,
            Self::SetConfig(_) => *d |= DirtyFlags::CONFIG,
            Self::Resize { .. } => *d |= DirtyFlags::RESIZE,
            Self::Shutdown => {}
        }
    }
}
```

**Step 3: Pass**

```bash
cargo test -p nightshade_planetarium --test bus_dirty
```

**Step 4: Commit**

```bash
git add native/nightshade_native/planetarium/src/bus/ \
        native/nightshade_native/planetarium/src/lib.rs \
        native/nightshade_native/planetarium/Cargo.toml \
        native/nightshade_native/planetarium/tests/bus_dirty.rs
git commit -m "feat(planetarium-v2): command + dirty-flags bus"
```

---

### Task 12: `SceneSnapshot` type + `ArcSwap` slot

Define the structure Dart will read each frame for label placement and HUD widgets. Test that publish + read returns the latest snapshot.

**Files:**
- Create: `native/nightshade_native/planetarium/src/scene/mod.rs`
- Create: `native/nightshade_native/planetarium/src/scene/snapshot.rs`
- Create: `native/nightshade_native/planetarium/tests/snapshot.rs`

[Step pattern as before. Snapshot contains `frame_id: u64`, `view_pose`, `labels: Vec<LabelHint>`, `selected: Option<SelectedObject>`. Use `Arc<ArcSwap<SceneSnapshot>>` as the publish slot. Verify by spawning a publisher thread + reader thread, asserting reader sees the latest.]

**Commit message:** `feat(planetarium-v2): SceneSnapshot + ArcSwap publish slot`

---

### Task 13: Event-driven render loop skeleton

Build the loop sketched in design § 9.1 around the command channel + dirty flags. Loop runs on a dedicated thread spawned by `Planetarium::new`. Test that idle = no CPU, that a `SetPose` command wakes it, that `Shutdown` exits the thread cleanly.

**Files:**
- Create: `native/nightshade_native/planetarium/src/bus/loop_thread.rs`
- Create: `native/nightshade_native/planetarium/tests/loop_thread.rs`

[Test uses a fake renderer that just counts frames. Asserts: 1 frame after first POSE command, 0 frames after no commands, joined cleanly after Shutdown.]

**Commit message:** `feat(planetarium-v2): event-driven render loop thread`

---

### Task 14: `Planetarium` handle — combines surface, loop, snapshot

**Files:**
- Modify: `native/nightshade_native/planetarium/src/lib.rs`
- Create: `native/nightshade_native/planetarium/tests/handle_lifecycle.rs`

Define the public `Planetarium` struct as in design § 4.1. `Planetarium::new(engine_handle) -> Result<Self, PlanetariumError>` creates the surface, spawns the loop, exposes `send(cmd)`, `snapshot()`, `texture_id()`. Test that creating + dropping the handle in a tight loop doesn't leak or panic.

**Commit message:** `feat(planetarium-v2): Planetarium handle type binds surface+loop+snapshot`

---

### Task 15: Real FFI surface

**Files:**
- Create: `native/nightshade_native/bridge/src/planetarium.rs`
- Modify: `native/nightshade_native/bridge/src/lib.rs`
- Delete: `native/nightshade_native/bridge/src/planetarium_spike.rs`
- Delete: `apps/desktop/lib/dev/planetarium_spike_screen.dart`

The full FFI surface mirrors the design § 4.1 commands plus snapshot access:

```rust
#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_create(engine_handle: i64) -> Result<i64, String>;

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_resize(handle: i64, w: u32, h: u32, dpr: f32) -> Result<i64, String>;

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_set_pose(handle: i64, pose: ViewPose) -> Result<(), String>;
// SetTime, SetObserver, SetConfig, SetMountPosition, SetEquipmentFov, ...

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_snapshot(handle: i64) -> Result<SceneSnapshotDto, String>;

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_push_gesture(handle: i64, evt: GestureEvent) -> Result<(), String>;

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_hit_test(handle: i64, x: f32, y: f32) -> Result<Option<SelectedObject>, String>;

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_dispose(handle: i64) -> Result<(), String>;
```

Each function looks up the handle in a static registry (same pattern as the spike) and forwards.

**Step 1 (write failing widget-level smoke test in Dart):**

```dart
test('planetarium handle round-trip', () async {
  final engineHandle = await EngineContext.instance.getEngineHandle();
  final handle = await planetariumCreate(engineHandle: engineHandle);
  final textureId = await planetariumResize(handle: handle, w: 64, h: 64, dpr: 1);
  expect(textureId, greaterThan(0));
  await planetariumDispose(handle: handle);
});
```

**Step 2: implement FFI**, regenerate, run desktop integration test.

**Step 3: delete the spike module + dev screen.** Per CLAUDE.md, no parallel surfaces.

**Commit message:** `feat(planetarium-v2): full FFI surface; remove spike scaffolding`

---

### Tasks 16–18 — Phase 2 wrap-up

| Task | Subject |
|---|---|
| 16 | Animation set (twinkle, selection pulse, pop-in) + loop integration |
| 17 | Snapshot publishing pipeline — `Renderer::publish_snapshot()` populates `labels`, hooks into ArcSwap |
| 18 | `Planetarium::push_gesture` round-trip test from Dart → render loop sees POSE dirty |

Each follows the same TDD shape. Each ends with a single scoped commit.

**Phase 2 done.** You have an empty (black) planetarium texture you can resize, accept commands, publish snapshots, and shut down cleanly.

---

# Phase 3 — Astrometry

All-pure-Rust; perfect for tight TDD. Tests use IAU SOFA-published reference values as ground truth (cite source in each test).

### Task 19: `AstroTime` constructors + `julian_centuries_tt`

**Files:**
- Create: `native/nightshade_native/planetarium/src/astrometry/mod.rs`
- Create: `native/nightshade_native/planetarium/src/astrometry/time.rs`
- Create: `native/nightshade_native/planetarium/tests/astrometry_time.rs`

**Test (failing first):**

```rust
use nightshade_planetarium::astrometry::time::*;

#[test]
fn julian_date_2000_jan_1_noon_tt() {
    // J2000.0 epoch in TT.
    let t = AstroTime::from_jd_utc(2_451_545.0);
    // 2000-01-01 12:00:00 UTC = TAI − 32.184s in TT terms; UT1≈UTC for this date.
    assert!((t.jd_tt - 2_451_545.000_745).abs() < 1e-6);
    assert_eq!(t.julian_centuries_tt(), 0.0_f64.copysign(t.julian_centuries_tt()));
}
```

**Implementation:** Bundled IERS leap-second table (`assets/iers/leapseconds.txt` shipped with the `core` pack) + parser + ΔUT1 spline. For Phase 3 use a built-in `const` table of leap seconds through 2026; later replace with the pack-loaded table.

**Commit:** `feat(planetarium-v2): AstroTime + JD/TT/UT1 conversion`

---

### Task 20: Earth Rotation Angle + GMST/LMST

Test values from IAU SOFA `eraEra00` reference. Same TDD shape.

**Commit:** `feat(planetarium-v2): Earth Rotation Angle, sidereal time`

---

### Task 21: IAU 2006 P03 precession

Reference: Capitaine et al. (2003) polynomial. Test fixture: precession from J2000 to J2050.0 of a star at (RA=0, Dec=0) — compare to SOFA `eraPmat06` output to <0.5″.

**Commit:** `feat(planetarium-v2): IAU 2006 P03 precession`

---

### Task 22: IAU 2000B nutation (78-term truncated)

Test against SOFA `eraNut00b` fixture values at multiple times.

**Commit:** `feat(planetarium-v2): IAU 2000B nutation`

---

### Task 23: Annual aberration

Earth heliocentric velocity from VSOP87 Sun (Task 27); apply first-order v×c correction. Test fixture: aberration of Polaris at perihelion — compare to JPL Horizons to <1″.

**Commit:** `feat(planetarium-v2): annual aberration`

---

### Task 24: Saemundsson atmospheric refraction

Pure function; trivial to test against published table values.

**Commit:** `feat(planetarium-v2): atmospheric refraction`

---

### Task 25: Atmospheric extinction LUT

Port the 91-entry LUT from `packages/nightshade_planetarium/lib/src/coordinate_system.dart`. Test that interpolation matches the original Dart outputs to within float precision.

**Commit:** `feat(planetarium-v2): atmospheric extinction LUT`

---

### Task 26: `FrameChain::for(time, observer)` and `icrs_to_horizontal`

Composes the matrices from Tasks 21–24. Test that a vector at celestial pole maps to alt = `observer.latitude` for sidereal time = pole hour angle.

**Commit:** `feat(planetarium-v2): frame chain ICRS→CIRS→TIRS→horizontal`

---

### Task 27: VSOP87D Sun + planets

Use a published Rust port (or write directly from the public VSOP87D tables) for Mercury–Neptune heliocentric coordinates. Test: Sun position at 2000-01-01 12:00 UTC equals (RA=18h45m, Dec=−23°00′) to ~5′.

**Commit:** `feat(planetarium-v2): VSOP87D ephemeris`

---

### Task 28: ELP2000-82B Moon (truncated)

Use a reasonable truncation (~50 terms) of the ELP2000-82B series. Test against JPL Horizons Moon position for a half-dozen dates to <1′.

**Commit:** `feat(planetarium-v2): ELP2000-82B Moon`

---

### Task 29: Kepler-equation solver + minor-body propagation

Newton-Raphson with proper handling of near-parabolic orbits (use Newton + Halley fallback when e ≈ 1). Test: propagate Comet C/2024 X1 (or any current well-known comet) at multiple epochs against MPC ephemeris.

**Commit:** `feat(planetarium-v2): Kepler solver + minor body propagation`

---

### Task 30: SGP4 satellite propagation

Wraps the `sgp4` crate. Test using the canonical SGP4 verification dataset (`sgp4_verif` testcases) to <1 km position.

**Commit:** `feat(planetarium-v2): SGP4 satellite propagation`

---

### Task 31: Body lighting & phase angles

Compute Sun-body and observer-body vectors per body; phase angle for inferior planets and Moon. Pure function; test fixture from JPL Horizons.

**Commit:** `feat(planetarium-v2): body phase angle computation`

---

### Task 32: Astrometry benchmark suite

`cargo bench` covering: FrameChain build (target: <5 µs), VSOP87 Sun (<2 µs), VSOP87 planet (<5 µs), ELP Moon (<10 µs), Kepler iter (<1 µs).

If any exceeds budget, optimize before continuing. Per-frame budget is ~50 µs for astrometry total.

**Commit:** `perf(planetarium-v2): astrometry benchmarks + budget gating`

---

# Phase 4 — Catalog System

### Task 33: Tile format types + zerocopy parser

Define `TileHeader`, `LodEntry`, `StarRecord` per design § 6.2. Test round-trip serialization with `zerocopy` (write bytes, mmap, parse, assert equal).

**Commit:** `feat(planetarium-v2): HEALPix tile binary format`

---

### Task 34: HEALPix helpers wrapping `cdshealpix`

`pixel_for_direction(ra, dec, nside)`, `pixels_in_cone(center, radius, nside)`, `bounding_pixels_for_fov(view_pose, fov_rad)`. Test with known sky positions vs `cdshealpix` direct calls.

**Commit:** `feat(planetarium-v2): HEALPix wrappers`

---

### Task 35: HYG → tile converter (binary tool)

Add a `bin/build_hyg_tiles.rs` tool that reads the existing HYG CSV from `packages/nightshade_planetarium/assets/...` and emits a `stars-hyg-v1/` tile set under `apps/desktop/assets/planetarium/catalogs/`. Test: tile count and total record count match expected.

**Commit:** `feat(planetarium-v2): HYG → tile converter`

---

### Task 36: OpenNGC port to tile-equivalent format

Similar to Task 35 for DSOs. The OpenNGC dataset is small enough to remain a single mmap'd file rather than HEALPix-tiled — design exception.

**Commit:** `feat(planetarium-v2): OpenNGC binary catalog`

---

### Task 37: Constellation lines + boundaries port

Port `packages/nightshade_planetarium/lib/src/catalogs/constellation_data.dart` to a Rust `const` table. Test count: 88 constellations, line vertex count matches.

**Commit:** `feat(planetarium-v2): constellation line data`

---

### Task 38: Catalog manager (`CatalogSet`)

Owns the currently active set of packs; queries return iterators of records intersecting a (pose, magnitude limit) query. TDD: register a fake pack, query, assert visibility.

**Commit:** `feat(planetarium-v2): CatalogSet`

---

### Task 39: Pack manifest format + integrity check

Define `pack.json` schema (name, version, sha256, file list). Implement manifest load + sha256 verify. Test: corrupted file fails to load with loud error (no silent fallback).

**Commit:** `feat(planetarium-v2): pack manifest + integrity check`

---

### Task 40: Tile residency manager

Keeps a `BTreeMap<HealpixId, ResidentTile>` of currently uploaded GPU buffers; LRU evict on cap; eager load on FOV change with warmup ring. Test: simulate FOV pan across many tiles, assert LRU behavior with a fixed cap of 8.

**Commit:** `feat(planetarium-v2): tile residency LRU`

---

### Task 41: Hit-test index

Per-pack sorted by HEALPix cell + within-cell binary heap by magnitude. Query: nearest visible object to a direction within a cone. Test: hit-test for known stars (Polaris, Vega, Sirius) against expected HIP id.

**Commit:** `feat(planetarium-v2): hit-test index`

---

### Tasks 42–46 — Catalog wrap-up

| Task | Subject |
|---|---|
| 42 | Variable star metadata table (small, ports from existing Dart catalog) |
| 43 | Minor body catalog format + MPC orbital elements |
| 44 | Satellite TLE pack format + loader |
| 45 | Milky Way raster asset (texture file generation + load) |
| 46 | Bundle the `core` and `stars-hyg` packs as Flutter assets |

**Phase 4 done.** Catalogs are queryable from the render thread; mostly bundled, ready to be consumed by pipelines.

---

# Phase 5 — Render Pipelines

Heaviest phase. Each pipeline is its own subtask with WGSL shader, vertex format, golden-image test (or visual smoke).

### Task 47: Renderer entry + frame graph

`Renderer::new(device, queue, format, width, height)` constructs all pipelines and resource buffers. `Renderer::render(scene)` runs the pass graph in order. Test: render an empty scene to a 64×64 target, verify pure black output.

**Commit:** `feat(planetarium-v2): renderer entry + frame graph`

---

### Task 48: Star pipeline + WGSL

Per design § 5.2. TDD:
1. Failing golden-image test: render 3 known stars (Polaris, Vega, Sirius) at zoom = 30°, compare against `tests/golden/stars_three.png` (committed alongside the test, generated once and reviewed by eye).
2. Vertex buffer layout: `StarInstance`.
3. WGSL vertex shader: ICRS→view→projection chain.
4. WGSL fragment shader: PSF gradient + B-V color.
5. Verify golden image matches within RMSE < 0.005.

**Commit:** `feat(planetarium-v2): star pipeline`

---

### Task 49: Star magnitude → screen size + tone mapping

Refine the PSF size curve and tone mapping for natural-looking magnitudes (the current planetarium has a well-tuned curve; port the formula). Visual smoke + perf check (5M stars at 60 fps target).

**Commit:** `feat(planetarium-v2): star PSF size + tone mapping`

---

### Task 50: Twinkle animation

Sin-based perturbation in the fragment shader, gated by config + altitude. Visual smoke.

**Commit:** `feat(planetarium-v2): star twinkle`

---

### Task 51: Bruneton LUT precompute

Port the public Bruneton 2020 implementation. Outputs four `wgpu::Texture` LUTs. Smoke test: precompute completes in <2 s on reference desktop, LUTs sample to expected values at known angles.

**Commit:** `feat(planetarium-v2): Bruneton LUT precompute`

---

### Task 52: Bundle precomputed Bruneton LUTs

Run the precompute once, save `.bin` to `apps/desktop/assets/planetarium/bruneton/luts-v1.bin`. Wire load path.

**Commit:** `chore(planetarium-v2): bundle Bruneton LUTs`

---

### Task 53: Atmosphere pipeline

Full-screen quad sampling the LUTs. Golden-image test at: midday, civil twilight, nautical twilight, astronomical twilight, midnight. Five goldens.

**Commit:** `feat(planetarium-v2): atmosphere pipeline`

---

### Task 54: Sun disc rendering inside atmosphere shader

Hard disc with limb darkening. Golden-image test.

**Commit:** `feat(planetarium-v2): solar disc`

---

### Task 55: Milky Way pipeline

Project the precomputed MW intensity texture onto the sphere. Brightness modulated by atmosphere. Golden-image test.

**Commit:** `feat(planetarium-v2): Milky Way pass`

---

### Task 56: Line pipeline (grids, constellations, ecliptic, galactic)

One pipeline, many style ids. Vertex format: `(icrs_dir, color, style_id)`. WGSL handles dashing via per-fragment discard.

**Commit:** `feat(planetarium-v2): line pipeline`

---

### Task 57: DSO sprite pipeline

Procedural ellipse/halo. Type-id switch in WGSL.

**Commit:** `feat(planetarium-v2): DSO sprite pipeline`

---

### Task 58: Body pipeline (Sun, Moon, planets, minor bodies)

Procedural sphere shader: lit hemisphere, phase, noise. Special-case the Moon for phase + libration term.

**Commit:** `feat(planetarium-v2): body pipeline`

---

### Task 59: Horizon pipeline + light-pollution dome

Two sub-passes: terrain silhouette (filled tri-strip) + LP dome (additive azimuthal gradient with Bortle color).

**Commit:** `feat(planetarium-v2): horizon + LP dome`

---

### Task 60: Satellite pipeline

Sprites + optional trail ribbon.

**Commit:** `feat(planetarium-v2): satellite pipeline`

---

### Task 61: Minor body pipeline

Sprites + tail rendering for comets (procedural cone with falloff).

**Commit:** `feat(planetarium-v2): minor body pipeline`

---

### Task 62: Selection FX pipeline

Pulsing ring with sin-driven alpha; subscribes to `DirtyFlags::SELECTION`.

**Commit:** `feat(planetarium-v2): selection FX`

---

### Task 63: Pass ordering integration

Wire all pipelines into the frame graph in design § 5.1 order. Single golden image with everything visible: Vega/Orion region at civil twilight with grids + constellations + ecliptic + Moon.

**Commit:** `feat(planetarium-v2): integrated frame graph golden`

---

### Task 64: Animation set + frame timing

Twinkle (continuous when enabled), selection pulse (timed), pop-in (timed). Loop wakes for animations.

**Commit:** `feat(planetarium-v2): animation set`

---

### Task 65: Tone mapping + sRGB handling pass

Final fullscreen pass: tonemap HDR scene → SDR Bgra8 output. Apply gamma if surface format requires.

**Commit:** `feat(planetarium-v2): tonemap + sRGB pass`

---

### Task 66: Render perf benchmark gate

Bench with 200k stars + atmosphere + constellations at 1920×1080 on reference desktop. Gate: ≤8 ms/frame on Windows reference (~120 fps headroom). Adjust quality knobs if it doesn't meet.

**Commit:** `perf(planetarium-v2): render benchmark gate`

---

# Phase 6 — Scene + Input

### Task 67: Visibility cull module

For a given `(ViewPose, fov)`, return the set of HEALPix tiles intersecting the frustum (sphere cap). Pure function. Unit tested.

**Commit:** `feat(planetarium-v2): visibility cull`

---

### Task 68: LOD selector

Pick magnitude limit per tile based on `(zoom, quality_config, mag_limit_config)`. Unit tested with several zoom levels.

**Commit:** `feat(planetarium-v2): LOD selector`

---

### Task 69: Pose controller state machine

`Free`, `LockedToTarget(id)`, `LockedToMount`, `LockedToBody(planet_id)`. Unit tested with synthetic mount/target/time inputs.

**Commit:** `feat(planetarium-v2): pose controller`

---

### Task 70: Gesture state machine

Pan/zoom/rotate/tap with momentum. Pure logic, no GPU. Unit tested with synthetic event sequences.

**Commit:** `feat(planetarium-v2): gesture state machine`

---

### Task 71: Pan momentum integration

Velocity decay + friction tuned to match v1 feel. Unit tested against expected pose trajectories.

**Commit:** `feat(planetarium-v2): pan momentum`

---

### Task 72: Hit testing wiring

Connects FFI `hit_test(x, y)` → projection inverse → catalog hit-test index → `SelectedObject`. Integration tested.

**Commit:** `feat(planetarium-v2): hit testing`

---

### Task 73: Tracking integration (mount + target)

Locked pose updates from `SetMountPosition`/`SetTrackingTarget` commands. Integration tested.

**Commit:** `feat(planetarium-v2): tracking lock integration`

---

### Task 74: Scene snapshot population

`Renderer::publish_snapshot()` produces `SceneSnapshot` with visible objects + label hints + constellation art placements + selected screen position. Verified end-to-end via Dart-side smoke test.

**Commit:** `feat(planetarium-v2): scene snapshot population`

---

# Phase 7 — Dart Shell

### Task 75: New package skeleton

**Files:**
- Create: `packages/nightshade_planetarium_v2/pubspec.yaml`
- Create: `packages/nightshade_planetarium_v2/lib/nightshade_planetarium_v2.dart`
- Modify: `melos.yaml`
- Modify: `apps/desktop/pubspec.yaml`
- Modify: `apps/mobile/pubspec.yaml`

`pubspec.yaml` mirrors `packages/nightshade_planetarium/pubspec.yaml` structure (Flutter package, `flutter_riverpod`, `nightshade_bridge`, `nightshade_core` deps).

```bash
melos bootstrap
melos run analyze
```

**Commit:** `feat(planetarium-v2): new package skeleton`

---

### Task 76: Bridge wrapper — `Planetarium` Dart handle

`packages/nightshade_planetarium_v2/lib/src/bridge/planetarium_handle.dart`:

```dart
class Planetarium {
  Planetarium._(this._id, this._textureId);
  final int _id;
  final int _textureId;
  int get textureId => _textureId;

  static Future<Planetarium> create() async {
    final engineHandle = await EngineContext.instance.getEngineHandle();
    final id = await rust.planetariumCreate(engineHandle: engineHandle);
    final tex = await rust.planetariumResize(handle: id, w: 1280, h: 720, dpr: 1);
    return Planetarium._(id, tex);
  }

  Future<void> setPose(ViewPose pose) => rust.planetariumSetPose(handle: _id, pose: pose);
  // ... other setters
  Future<void> dispose() => rust.planetariumDispose(handle: _id);
}
```

Widget test: create + dispose round-trip.

**Commit:** `feat(planetarium-v2): Dart bridge handle`

---

### Task 77: `planetariumHandleProvider`

Lazy `FutureProvider<Planetarium>`, keepalive after first success.

**Commit:** `feat(planetarium-v2): handle provider`

---

### Tasks 78–88: providers + InteractiveSkyView

| Task | Subject |
|---|---|
| 78 | `viewPoseProvider` — push pose changes to Rust |
| 79 | `observationTimeProvider` — wraps core observation time, pushes to Rust |
| 80 | `observerProvider` — pushes to Rust |
| 81 | `renderConfigProvider` — visibility toggles, quality |
| 82 | `sceneSnapshotProvider` — read native snapshot per Flutter frame |
| 83 | `selectionProvider` |
| 84 | `InteractiveSkyView` widget shell (just hosts `Texture`) |
| 85 | Gesture detector → push gestures to Rust |
| 86 | Resize observer → push resize to Rust on size change |
| 87 | Lifecycle hooks → quiesce on background, restore on foreground |
| 88 | Tap → hit-test → selection round-trip |

Each follows TDD: widget test asserting a specific Riverpod state change triggers the expected `planetarium*` Rust call (using a mocked `Planetarium` handle).

**Phase 7 done.** v2 can be hosted as a stand-alone Flutter screen showing the full Rust-rendered sky with pan/zoom/select working.

---

# Phase 8 — Overlay Port

Each overlay widget is a near-direct port from `packages/nightshade_planetarium/` to v2, plus the rewire to consume `sceneSnapshotProvider` for position data instead of computing it Dart-side.

| Task | Widget | Notes |
|---|---|---|
| 89 | `LabelLayer` | Consumes `snapshot.labels`, places `Positioned(Text(...))` children; existing label-overlap-resolution code ported as-is |
| 90 | `ConstellationArtLayer` | Consumes `snapshot.constellation_art`; uses existing PNG assets |
| 91 | `FovOverlay` | Reuses widget from v1, fed by `equipmentFovProvider` |
| 92 | `MosaicOverlay` | Same as v1 |
| 93 | `MountReticle` | Reads `snapshot.mount_screen` |
| 94 | `CompassHud` | Same as v1 |
| 95 | `SkyMinimap` | Pulls from snapshot |
| 96 | `ObjectDetailsPanel` | Same UI as v1, fed by `selectionProvider` |
| 97 | `TimeControlPanel` | Same UI as v1, pushes to `observationTimeProvider` |
| 98 | Search UI | Same UI; uses hit-test FFI for selection |

Each task: widget test with mock snapshot, golden-screenshot test where applicable.

**Phase 8 done.** v2 has full visual parity with v1.

---

# Phase 9 — Catalog Pack Manager

### Task 99: `CatalogPack` model + repository

Dart model mirroring the Rust pack manifest. Repository class with `list()`, `installed()`, `available()`, `install(packId)`, `uninstall(packId)`, `update(packId)`. HTTP fetch with resume + sha256 verify, save under `path_provider.getApplicationSupportDirectory()/nightshade/catalogs/`.

**Commit:** `feat(planetarium-v2): catalog pack repository`

---

### Task 100: Pack-load FFI

`planetarium_load_pack(handle, pack_path)` → engine loads tiles from disk; emits `DirtyFlags::CATALOG`.

**Commit:** `feat(planetarium-v2): pack-load FFI`

---

### Task 101: Catalog manager screen

UI: list of installed + available packs with size, version, install/uninstall buttons. Routed under Settings.

**Commit:** `feat(planetarium-v2): catalog manager screen`

---

### Task 102: Tycho-2 pack: source → tile converter

Run as a one-off CI/CD pipeline (script under `tools/catalog-build/`). Outputs `stars-tycho2-v1.zip` to be uploaded to the Nightshade CDN.

**Commit:** `chore(planetarium-v2): Tycho-2 tile build script`

---

### Task 103: Catalog CDN upload + version registry

Add Tycho-2 pack to the version registry consumed by the catalog repository.

**Commit:** `chore(planetarium-v2): publish Tycho-2 pack`

---

### Task 104: First-launch onboarding

Detect when v2 is being used for the first time; offer to download Tycho-2 (50 MB). Skippable; user can install later via catalog manager.

**Commit:** `feat(planetarium-v2): first-launch pack prompt`

---

# Phase 10 — Platform Expansion

Each platform follows the Phase 1 pattern: implement the surface, smoke-test with a triangle, then validate full renderer.

### Task 105: macOS surface — IOSurface + Metal

**Files:**
- Create: `native/nightshade_native/planetarium/src/surface/macos.rs`

Pattern documented in design § 10.1. wgpu's Metal backend; `MTLTexture` over `IOSurface`; register via `irondash_texture` Metal external texture path.

Smoke test on a Mac: rotating triangle works.

**Commit:** `feat(planetarium-v2): macOS IOSurface surface`

---

### Task 106: macOS full renderer validation

Run all golden-image tests on macOS. Diff against canonical goldens (allow ~1% RMSE for backend differences). Investigate any larger deltas.

**Commit:** `test(planetarium-v2): macOS golden parity`

---

### Task 107: iOS surface

Same pattern as macOS; just a different `irondash_texture` constructor variant.

**Commit:** `feat(planetarium-v2): iOS surface`

---

### Task 108: iOS performance gate

30 fps target with HYG + atmosphere + grids + constellations at typical zoom on iPhone 13-class device. Tune quality presets if not met.

**Commit:** `perf(planetarium-v2): iOS perf gate`

---

### Task 109: Android surface — AHardwareBuffer

Pattern in design § 10.1. wgpu Vulkan backend; `AHardwareBuffer` import; `SurfaceTexture` registration.

**Commit:** `feat(planetarium-v2): Android AHB surface`

---

### Task 110: Android performance gate

Same target as iOS.

**Commit:** `perf(planetarium-v2): Android perf gate`

---

### Task 111: Linux surface — GL FBO via flutter_gl

Linux is the highest-risk platform per R1. Path: wgpu's GL backend rendering to an offscreen FBO; `flutter_gl` exposes that texture id to Dart.

**Commit:** `feat(planetarium-v2): Linux GL FBO surface`

---

### Task 112: Wayland vs X11 differentiation

Confirm both work. Test on Ubuntu 22.04 (X11) + Fedora 39 (Wayland).

**Commit:** `feat(planetarium-v2): Linux Wayland + X11 support`

---

### Tasks 113–116 — Platform hardening

| Task | Subject |
|---|---|
| 113 | DPI changes — drag window between displays, resize, no flicker |
| 114 | Background/foreground transitions — quiesce GPU resources, restore |
| 115 | Multi-instance — two `InteractiveSkyView` widgets in one app share device, separate texture |
| 116 | Error paths — surface failures surface as snackbar + log, never silent |

**Phase 10 done.** v2 ships on all five platforms.

---

# Phase 11 — Cutover

### Task 117: `renderingPlatformProvider` toggle

Add a setting (default = v1) that routes Planetarium screens to v1 or v2. Implement in `nightshade_core` settings table.

**Commit:** `feat(planetarium-v2): rendering platform toggle`

---

### Task 118: Wire toggle into screens

`nightshade_app`'s target picker, mosaic planner, and full-screen sky screens read the toggle and render either v1 or v2 `InteractiveSkyView`.

**Commit:** `feat(planetarium-v2): toggle in screens`

---

### Task 119: Parity-suite

Integration test running both v1 and v2 with the same state and asserting `objectDetailsProvider` returns identical results for 100 random sky positions + times.

**Commit:** `test(planetarium-v2): parity suite vs v1`

---

### Task 120: Performance gate before default flip

- Windows reference desktop: 60 fps sustained, all layers visible
- iPhone 13: 30 fps sustained
- Pixel 6: 30 fps sustained
- 2024 MacBook Pro: 60 fps sustained
- Ubuntu 22.04 reference desktop: 60 fps sustained

If any platform misses, open a separate optimization sub-plan. Do not flip the default.

**Commit:** `test(planetarium-v2): perf gates documented`

---

### Task 121: Flip toggle default to v2

After 2 weeks of internal use behind the toggle with no regressions reported.

**Commit:** `feat(planetarium-v2): default to v2`

---

### Task 122: Remove v1

After one full release cycle on v2-default. Delete `packages/nightshade_planetarium/`, remove the toggle setting (always v2), rename v2 package back to `nightshade_planetarium`.

**Commit:** `chore(planetarium-v2): remove legacy planetarium`

---

## Cross-cutting verification

After each phase:

- `melos run analyze` — zero errors.
- `cd native/nightshade_native && cargo clippy --all-features -- -D warnings` — zero warnings.
- `cargo test -p nightshade_planetarium` — all tests pass.
- `melos run test` — Dart-side tests pass.
- `melos run audit:placeholders` — must pass; per CLAUDE.md no stubs.

Per CLAUDE.md, run `melos run dev` (not raw `flutter run`) any time Rust changes — hash mismatches will surface otherwise.

---

## Open items the engineer is expected to surface

1. **wgpu DX12 HAL shared-handle extraction.** Task 5 step 2 may be blocked by wgpu version. If so, escalate and choose between Vulkan-import path or downgrading to wgpu's older HAL version that exposed the API. Do not silently fall back to CPU readback.
2. **`irondash_texture` API variant.** Tasks 5, 105, 107, 109, 111 each select an `irondash_texture` constructor. Confirm the chosen variants compile against the same pinned crate version.
3. **Bundled Bruneton LUTs vs runtime precompute.** Decided at Task 52 based on first-run perf measurement.
4. **HEALPix nside.** Tasks 33–35 may need tuning if Tycho-2 tile sizes are too large or too small.
5. **Linux GL FBO** approach (Task 111) is the highest-residual risk. If `flutter_gl` doesn't accept wgpu's GL backend texture cleanly, an alternate path is `dma-buf` + EGL extension import — open a dedicated sub-task.

---

## Plan complete — execution options

Plan complete and saved to `docs/plans/2026-05-25-planetarium-v2-plan.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch a fresh subagent for each task with code review between tasks. Fast iteration; quality gate between every task. Best when the user wants to stay in this session and approve task-by-task.

**2. Parallel Session (separate)** — Open a new session in this same branch and run `superpowers:executing-plans` against this plan in controlled batches with review checkpoints. Best when the user wants to step away or have someone else execute.

Which approach?

---

## Implementation progress (coordinator log)

> **Last updated:** 2026-05-25 (coordinator handoff, batch 2). **Branch:** `main` (36 commits ahead of `origin/main`). **Planetarium code HEAD:** `5d64513` (annual aberration). **Docs log commit:** `8dbbc7c` / `fcdb9bf` (prior). Verify: `git log --oneline --grep="planetarium-v2" -50`.

### Completed task numbers (committed)

| Phase | Tasks done |
|-------|------------|
| 1 | **1–8** |
| 2 | **9–18** |
| 3 | **19–25**, **27–30**, **22–23** (23: `aberration.rs` committed; **`pub mod aberration` missing at HEAD** — integrator WIP) |
| 4 | **33**, **34** (HEALPix helpers bundled in `5cefaf3` Moon commit), **37** |
| 7 | **75–77** |

**Not started / in flight (no planetarium-v2 commit yet):** 26, 31–32, 35–36, 38–46, 47+, 78–88, Phases 5–6, 8–11.

### Code review — P0 fixes (in flight)

Rust + Dart readonly reviews flagged **P0** items; dedicated fix agent running (do not duplicate):

| P0 | Issue | Primary files |
|----|--------|----------------|
| 1 | `SetTime` / `SetObserver` accepted via FFI but never stored or applied in snapshots | `planetarium/src/handle.rs`, `bus/mod.rs`, `bridge/src/planetarium.rs` |
| 2 | `surface/mod.rs` `compile_error!` breaks non-Windows workspace CI | `planetarium/src/surface/mod.rs` — need `cfg(windows)` surface + fail-loud stub |

**P1 (same agent if time):** release bridge mutex before `wait_texture_id` poll; propagate `planetarium_resize` surface errors.

### Parallel agents (coordinator batch 2)

| Worker | Focus | Expected commit prefix |
|--------|--------|-------------------------|
| P0 fixes | Items above + handle lifecycle tests | `fix(planetarium-v2):` |
| Integrator 3 | Wire `aberration`, `frames`, `body_lighting` in `astrometry/mod.rs`; land `frames.rs` / `body_lighting.rs` + tests | `fix(planetarium-v2): integrate …` |
| Task 35 | HYG → tile converter tool | `feat(planetarium-v2):` |
| Task 38 | `CatalogSet` | `feat(planetarium-v2): CatalogSet` |
| Tasks 78–80 | `viewPose`, observation time, observer providers | `feat(planetarium-v2):` |
| Task 47 | Renderer / frame graph skeleton | `feat(planetarium-v2): renderer entry` |
| Second review | Re-run after P0 + integrator land | readonly report only |

**WIP on disk (uncommitted, do not duplicate):** `astrometry/mod.rs` (+ `aberration` / `frames` / `body_lighting` exports), `frames.rs`, `body_lighting.rs`, matching tests; test harness cleanup in `astrometry_*` integration tests.

### Work completed (by phase/task)

#### Phase 1 — Tasks 1–8 (Windows vertical-slice spike): **done**

| Task | Status | Commit |
|------|--------|--------|
| 1 Register crate in workspace | done | `9f27abc` |
| 2 Crate smoke test | done | `31a223b` |
| 3 wgpu offscreen triangle (PNG) | done | `e2543eb` |
| 4 irondash_texture API + surface trait skeleton | done | `31b2667` |
| 5 Windows D3D11 shared texture + vendored irondash | done | `84f0288` |
| 6 Spike FFI (`create`/`resize`/`dispose`) | done | `463a48d` |
| 7 Dev route + spike Flutter screen | done | `f53592c` (screen/route **removed** later in `587b3cb`) |
| 8 Rotating triangle in live Flutter `Texture` | done | `e50371d` |

**Phase 1 visual gate:** Spike route `/dev/planetarium-spike` was added in `f53592c` and deleted in `587b3cb`. Manual smoke now uses the **full** planetarium FFI (`planetariumCreate` / `planetariumResize` / `planetariumDispose` in `packages/nightshade_bridge/lib/src/api/planetarium.dart`) via `melos run dev` — there is no dedicated dev route anymore.

#### Phase 2 — Tasks 9–18 (crate skeleton, loop, FFI): **done**

| Task | Status | Commit |
|------|--------|--------|
| 9 Core deps (glam, crossbeam, arc-swap, cdshealpix, sgp4) | done | `079d1a2` |
| 10 `ViewPose`, `Observer`, `RenderConfig` types | done | `76efff8` |
| 11 Command channel + dirty flags | done | `605fba5` |
| 12 `SceneSnapshot` + `ArcSwap` | done | `48426f4` |
| 13 Event-driven render loop thread | done | `7a9fee7` |
| 14 `Planetarium` handle (surface + loop + snapshot) | done | `681a7c1` |
| 15 Real FFI surface; spike removed | done | `587b3cb` |
| 16 Animation set | done | `73464e5` |
| 17 Snapshot publishing pipeline | done | `f6560b5` |
| 18 `push_gesture` Dart → POSE dirty round-trip | done | `d614483` |

#### Phase 3 — Tasks 19–32 (astrometry): **mostly done** (26 / 31 / 32 remain)

| Task | Subject | Status | Commit / notes |
|------|---------|--------|----------------|
| 19 | `AstroTime` + JD/TT/UT1 | **done** | `93c5d03` |
| 20 | Earth Rotation Angle + sidereal | **done** | `ac847c8` |
| 21 | IAU 2006 P03 precession | **done** | `29380a9` |
| 22 | IAU 2000B nutation | **done** | `e5f9b18`; wired in `d15cd52` |
| 23 | Annual aberration | **done** (integrator wire-up pending) | `5d64513` — **`pub mod aberration` not in committed `mod.rs` at HEAD**; WIP adds export |
| 24 | Saemundsson refraction | **done** | `849ccb5`; exported in `d15cd52` |
| 25 | Atmospheric extinction LUT | **done** | `6036c45`; exported in `d15cd52` |
| 26 | `FrameChain` + `icrs_to_horizontal` | **in flight** | WIP: `frames.rs`, `tests/astrometry_frames.rs` (untracked); integrator agent |
| 27 | VSOP87D Sun + planets | **done** | `vsop87.rs` in `d15cd52` integrator commit |
| 28 | ELP2000-82B Moon | **done** | `5cefaf3` |
| 29 | Kepler + minor bodies | **done** | `007d774`; wired in `d15cd52` |
| 30 | SGP4 propagation | **done** | `23aabed`; `pub mod sgp4_prop` at HEAD |
| 31 | Body lighting & phase | **in flight** | WIP: `body_lighting.rs`, `tests/astrometry_body_lighting.rs` (untracked) |
| 32 | Astrometry benchmark suite | **not started** | — |

**Integrator history:** `d15cd52` exported `nutation`, `vsop87`, `moon`, `kepler` (+ prior `extinction`, `refraction`, `sgp4_prop`). **Integrator 3 still needed:** `aberration` (committed module, missing `pub mod`), `frames`, `body_lighting`.

#### Phase 4 — Tasks 33–46 (catalog): **partial**

| Task | Subject | Status | Commit / notes |
|------|---------|--------|----------------|
| 33 | HEALPix tile binary format | **done** | `b7023ba` — `catalog/tile.rs` |
| 34 | HEALPix helpers (`cdshealpix`) | **done** | `5cefaf3` — `catalog/healpix.rs` (landed with Moon task) |
| 35 | HYG → tile converter | **in flight** | parallel agent |
| 36 | OpenNGC port | **not started** | — |
| 37 | Constellation lines + boundaries | **done** | `7d455af` — `catalog/constellation_lines.rs` |
| 38 | `CatalogSet` | **in flight** | parallel agent |
| 39–46 | manifest, residency, hit-test, wrap-up | **not started** | — |

Phases 5–6 are **not started**. Phase 7 tasks **78+** in flight (see parallel agents).

#### Phase 7 — Tasks 75–77 (Dart / providers): **partial**

| Task | Status | Commit |
|------|--------|--------|
| 75 New package skeleton | **done** | `41efa5e` |
| 76 Bridge `Planetarium` Dart handle | **done** | `639de37` — `lib/src/bridge/planetarium_handle.dart` |
| 77 `planetariumHandleProvider` | **done** | `df7bd31` |
| 78–88 providers + `InteractiveSkyView` | **in flight** | Tasks **78–80** assigned; **81–88** not started |

---

### Files touched (grouped)

All paths below are from `git log --grep="planetarium-v2" --name-only` on `main` unless noted as **WIP (uncommitted)**.

#### `native/nightshade_native/planetarium/**`

| Area | Files / modules |
|------|-----------------|
| Crate root | `Cargo.toml`, `src/lib.rs`, `shaders/spike.wgsl`, `src/spike.rs` (offscreen/golden tests) |
| **surface/** | `mod.rs`, `windows.rs`, `d3d11_shared.rs` |
| **bus/** | `mod.rs`, `dirty.rs`, `loop_thread.rs` |
| **scene/** | `mod.rs`, `snapshot.rs`, `publish.rs`, `projection.rs`, `dev_catalog.rs` |
| **gesture/** | `mod.rs`, `hit_test.rs` |
| **animation/** | `mod.rs` |
| **astrometry/** | `mod.rs`, `time.rs`, `earth_rotation.rs`, `precession.rs`, `nutation.rs`, `aberration.rs`, `extinction.rs`, `refraction.rs`, `sgp4_prop.rs`, `vsop87.rs`, `moon.rs`, `kepler.rs`; WIP: `frames.rs`, `body_lighting.rs` |
| **catalog/** | `mod.rs`, `tile.rs`, `healpix.rs`, `constellation_lines.rs` |
| **handle** | `src/handle.rs`, `src/types.rs` |
| **vendor/** | `vendor/irondash_texture/**` (vendored for Windows texture handoff) |
| **tests/** | `smoke.rs`, `spike_render.rs`, `types.rs`, `bus_dirty.rs`, `loop_thread.rs`, `handle_lifecycle.rs`, `snapshot.rs`, `snapshot_publish.rs`, `animation.rs`, `astrometry_*.rs` (time, sidereal, precession, nutation, aberration, extinction, refraction, sgp4, vsop87, moon, kepler), `catalog_tile.rs`, `catalog_healpix.rs`, `catalog_constellation_lines.rs`; WIP: `astrometry_frames.rs`, `astrometry_body_lighting.rs` |

#### `native/nightshade_native/bridge/**`

- **Added:** `bridge/src/planetarium.rs` (`587b3cb`)
- **Removed:** `bridge/src/planetarium_spike.rs` (`587b3cb`)
- **Modified:** `bridge/src/lib.rs`, `bridge/src/api/mod.rs`, `bridge/Cargo.toml`, `bridge/src/frb_generated.rs`
- Workspace: `native/nightshade_native/Cargo.toml` (`planetarium` member)

#### `packages/nightshade_bridge/**`

- `lib/src/api/planetarium.dart` (FRB-generated API)
- **Removed:** `lib/src/api/planetarium_spike.dart`
- `lib/src/api_barrel.dart`, `lib/src/frb_generated.dart`, `lib/src/frb_generated.io.dart`
- `test/planetarium_handle_test.dart`
- Platform headers: `ios/bridge_generated.h`, `linux/bridge_generated.h`, `macos/bridge_generated.h`

#### `apps/desktop/**`

- `pubspec.yaml` — v2 path dep added in `41efa5e`
- `lib/main.dart` — dev-route wiring in `f53592c`, reverted in `587b3cb`
- **Deleted:** `lib/dev/planetarium_spike_screen.dart` (`587b3cb`)

#### `packages/nightshade_app/**`

- `lib/router/app_router.dart` — dev route in `f53592c`, reverted in `587b3cb`

#### `packages/nightshade_planetarium_v2/**`

- Skeleton: `41efa5e`
- `lib/src/bridge/planetarium_handle.dart`, `test/planetarium_handle_test.dart` — `639de37`
- `lib/src/providers/planetarium_handle_provider.dart`, `test/planetarium_handle_provider_test.dart` — `df7bd31`
- Tasks **78–88** widgets/providers: not started (in flight: 78–80)

#### `planetarium/vendor/**`

- Full **irondash_texture** crate vendored under `native/nightshade_native/planetarium/vendor/irondash_texture/` (`84f0288`)

#### Explicitly **NOT touched**

- **`packages/nightshade_planetarium/`** (v1 legacy `CustomPainter` planetarium) — unchanged by planetarium-v2 commits; remains the production path until Phase 11 cutover.

---

### Pick-up notes for future agents

#### Scoped commits (mandatory)

Per **How to use this plan** above: stage **only** planetarium-v2 paths; never `git add .` / `git add -A`. Other WIP on `main` (headless API, bridge unrelated files, etc.) must not be swept into planetarium commits.

#### Parallelization — `mod.rs` integrator pattern

When multiple agents work Phase 3 astrometry in parallel:

1. **Module agents** own exactly one pair: `src/astrometry/<name>.rs` + `tests/astrometry_<name>.rs`. Do **not** edit `astrometry/mod.rs` (see `refraction.rs` header: `INTEGRATE: add pub mod refraction;`).
2. **Integrator agent** (single owner) merges `astrometry/mod.rs`: add `pub mod …;` lines, resolve order, run `cargo test -p nightshade_planetarium`, commit integrator-only or rebase module commits.
3. **Integrator debt at `5d64513`:** `d15cd52` wired `nutation`, `vsop87`, `moon`, `kepler`, `extinction`, `refraction`, `sgp4_prop`. Still missing at HEAD: **`pub mod aberration`** (`5d64513` landed `aberration.rs` only). **Integrator 3** must also land `frames` + `body_lighting` (files exist uncommitted).
4. **SGP4:** top-level `pub mod sgp4_prop` at HEAD; drop any stale `time.rs` `#[path]` child if still present in WIP.

#### FRB regeneration — when?

Regenerate and commit bridge + Dart bindings when **`native/nightshade_native/bridge/src/planetarium.rs`** (or FRB-marked types it exports) changes:

```bash
cd native/nightshade_native
flutter_rust_bridge_codegen generate
# Then melos run dev (or copy DLLs) before flutter run — see CLAUDE.md
```

Last full regen bundled in `587b3cb` (`planetarium.dart`, `frb_generated.*`, platform `bridge_generated.h`). Pure-Rust astrometry-only changes do **not** require FRB regen.

#### Verification commands (each task / integrator pass)

```bash
cd native/nightshade_native && cargo test -p nightshade_planetarium
cd native/nightshade_native && cargo clippy -p nightshade_planetarium -- -D warnings
melos run analyze   # after Dart package / FRB changes
melos run dev       # after any Rust bridge or DLL-affecting change
```

#### Phase 1 visual gate (updated)

- ~~`/dev/planetarium-spike`~~ removed (`587b3cb`).
- Smoke: `melos run dev`, exercise `planetariumCreate` → `planetariumResize` → texture in a host screen (Task 76+), or `packages/nightshade_bridge/test/planetarium_handle_test.dart` for FFI-only.

#### Open blockers (from plan + observed)

1. **P0 review fixes** — `SetTime`/`SetObserver` no-ops; non-Windows `compile_error!` in `surface/mod.rs` (fix agent in flight).
2. **wgpu DX12 HAL shared-handle extraction** (plan Task 5) — Windows path works via `d3d11_shared.rs` + vendored irondash.
3. **irondash_texture API variant** — pinned via vendor copy; confirm for macOS/iOS tasks (105, 107, 109).
4. **Bundled Bruneton LUTs vs runtime precompute** — Task 52 (not started).
5. **HEALPix nside tuning** — Tasks 35–36 (converter / OpenNGC not started).
6. **Linux GL FBO** — Task 111 (not started).
7. **Astrometry integrator 3** — `aberration` export + land `frames` / `body_lighting` WIP before Task **32** benchmarks.

#### Next recommended batches

1. **Land P0 fix commit** (handle time/observer + cross-platform surface stub) — unblocks CI and honest FFI semantics.
2. **Integrator 3** — `astrometry/mod.rs` + `frames` / `body_lighting` / `aberration` exports; `cargo test -p nightshade_planetarium`.
3. **Parallel:** Task **35** (HYG tiles), **38** (`CatalogSet`), **47** (renderer skeleton), **78–80** (Dart providers).
4. **Phase 3 wrap:** Task **32** benchmark suite after integrator 3 merges.
5. **Second review pass** after P0 + integrator land.

To refresh this log: `git log --oneline --grep="planetarium-v2" -50` and `git status` under `native/nightshade_native/planetarium/`.
