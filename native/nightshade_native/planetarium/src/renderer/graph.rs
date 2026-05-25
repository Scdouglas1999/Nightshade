//! Frame graph: ordered render passes per design §5.1.
//!
//! Pass 0 clears to black; pass 2 draws the Milky Way intensity map; pass 3 draws stars.

use super::Scene;
use crate::renderer::pipelines::dsos::DsosPipeline;
use crate::renderer::pipelines::lines::LinesPipeline;
use crate::renderer::pipelines::milky_way::MilkyWayPipeline;
use crate::renderer::pipelines::stars::StarsPipeline;
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
    #[allow(clippy::too_many_arguments)]
    pub fn render(
        encoder: &mut wgpu::CommandEncoder,
        target_view: &wgpu::TextureView,
        scene: &Scene,
        milky_way: &MilkyWayPipeline,
        stars: &StarsPipeline,
        star_instance_buf: &wgpu::Buffer,
        star_instance_count: u32,
        dsos: &DsosPipeline,
        dso_instance_buf: &wgpu::Buffer,
        dso_instance_count: u32,
        lines: &mut LinesPipeline,
        width: u32,
        height: u32,
    ) {
        for (index, pass_id) in RenderPassId::ORDER.iter().enumerate() {
            Self::run_pass(
                encoder,
                target_view,
                scene,
                milky_way,
                stars,
                star_instance_buf,
                star_instance_count,
                dsos,
                dso_instance_buf,
                dso_instance_count,
                lines,
                width,
                height,
                *pass_id,
                index == 0,
            );
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn run_pass(
        encoder: &mut wgpu::CommandEncoder,
        target_view: &wgpu::TextureView,
        scene: &Scene,
        milky_way: &MilkyWayPipeline,
        stars: &StarsPipeline,
        star_instance_buf: &wgpu::Buffer,
        star_instance_count: u32,
        dsos: &DsosPipeline,
        dso_instance_buf: &wgpu::Buffer,
        dso_instance_count: u32,
        lines: &mut LinesPipeline,
        width: u32,
        height: u32,
        pass_id: RenderPassId,
        is_first: bool,
    ) {
        let label = format!("planetarium.pass.{pass_id:?}");
        let load = if is_first {
            wgpu::LoadOp::Clear(FRAME_CLEAR)
        } else {
            wgpu::LoadOp::Load
        };

        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
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

        if pass_id == RenderPassId::MilkyWay {
            milky_way.draw(&mut pass, scene, width, height);
        }

        if pass_id == RenderPassId::Stars {
            stars.draw_with_viewport(
                &mut pass,
                scene,
                star_instance_buf,
                star_instance_count,
                width,
                height,
            );
        }

        if pass_id == RenderPassId::Dsos {
            dsos.draw_with_viewport(
                &mut pass,
                scene,
                dso_instance_buf,
                dso_instance_count,
                width,
                height,
            );
        }

        if pass_id == RenderPassId::Lines {
            lines.prepare_and_draw(&mut pass, scene, width, height);
        }

        drop(pass);
    }
}
