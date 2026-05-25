// Minimal FFI shape for the Phase 1 spike.
//
// Exposes three functions to Dart:
//   - `planetarium_spike_create(engine_handle) -> handle id`
//   - `planetarium_spike_resize(handle, w, h) -> texture id`
//   - `planetarium_spike_tick(handle)`
//   - `planetarium_spike_dispose(handle)`
//
// Replaces itself with the full FFI in Phase 2. Engineer MUST remove this
// module once Task 18 (full FFI) lands. Do not leave parallel surfaces.

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
pub fn planetarium_spike_tick(handle: i64) -> Result<(), String> {
    let reg = registry().lock();
    let surface = reg
        .get(&handle)
        .ok_or_else(|| format!("planetarium spike handle {handle} not found"))?;
    surface.tick().map_err(|e| e.to_string())?;
    surface.mark_frame_available().map_err(|e| e.to_string())?;
    Ok(())
}

#[flutter_rust_bridge::frb(sync)]
pub fn planetarium_spike_dispose(handle: i64) -> Result<(), String> {
    let mut reg = registry().lock();
    if let Some(mut s) = reg.remove(&handle) {
        s.shutdown().map_err(|e| e.to_string())?;
    }
    Ok(())
}
