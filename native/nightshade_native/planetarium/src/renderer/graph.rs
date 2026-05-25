//! Frame graph: ordered render passes per design §5.1.
//!
//! Passes 1–9 are no-ops until their pipelines land in later tasks; pass 0 clears to black.

use super::Scene;
use crate::renderer::FRAME_CLEAR;

/// Ordered render passes (design doc §5.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum RenderPassId {
    /// Clear color attachment to pure black.
    Clear = 0,
    /// Bruneton atmosphere + sun disc.
    Atmosphere = 1,
    /// Precomputed Milky Way intensity map.
    MilkyWay = 2,
    /// Instanced star sprites.
    Stars = 3,
    /// DSO sprites.
    Dsos = 4,
    /// Grids, constellation lines, boundaries.
    Lines = 5,
    /// Sun, Moon, planets, minor bodies.
    Bodies = 6,
    /// SGP4 satellite sprites.
    Satellites = 7,
    /// Selection pulse ring.
    SelectionFx = 8,
    /// Horizon silhouette + light-pollution dome.
    Horizon = 9,
}

impl RenderPassId {
    /// All passes in frame order.
    pub const ORDER: [Self; 10] = [
        Self::Clear,
        Self::Atmosphere,
        Self::MilkyWay,
        Self::Stars,
        Self::Dsos,
        Self::Lines,
        Self::Bodies,
        Self::Satellites,
        Self::SelectionFx,
        Self::Horizon,
    ];
}

/// Frame graph executor — runs every pass slot in order.
pub struct FrameGraph;

impl FrameGraph {
    /// Run the full pass graph into `target_view`.
    ///
    /// Empty scene: only the clear pass writes pixels; later passes load and draw nothing,
    /// leaving pure black.
    pub fn render(
        encoder: &mut wgpu::CommandEncoder,
        target_view: &wgpu::TextureView,
        _scene: &Scene,
    ) {
        for (index, pass_id) in RenderPassId::ORDER.iter().enumerate() {
            Self::run_pass(encoder, target_view, *pass_id, index == 0);
        }
    }

    fn run_pass(
        encoder: &mut wgpu::CommandEncoder,
        target_view: &wgpu::TextureView,
        pass_id: RenderPassId,
        is_first: bool,
    ) {
        let label = format!("planetarium.pass.{pass_id:?}");
        let load = if is_first {
            wgpu::LoadOp::Clear(FRAME_CLEAR)
        } else {
            wgpu::LoadOp::Load
        };

        let pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some(&label),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: target_view,
                resolve_target: None,
                ops: wgpu::Operations {
                    load,
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
        });
        // Pipeline draw calls for `pass_id` are added in Tasks 48–62.
        drop(pass);
    }
}
