//! Mosaic instruction node.
//!
//! ## When this code runs
//!
//! This node executes only when a sequence contains a
//! [`NodeType::Mosaic`] variant. In the current architecture
//! Nightshade's Dart UI does NOT emit `Mosaic` nodes — the
//! `MosaicService.createMosaicSequence` path expands a mosaic into
//! N×M `TargetHeader` siblings instead, so the per-panel slew /
//! center / expose / dither work happens at the node tree level. See
//! [`crate::mosaic`] module docs for the full architectural
//! discussion.
//!
//! This node is the forward-looking entry point for when the
//! orchestration eventually moves into Rust (so the Dart side emits a
//! single mosaic node with `MosaicConfig` and the wizard owns
//! per-panel work). When that happens, the wizard's per-panel
//! checkpoint will provide step-level resume support automatically —
//! see the `resume_round_trips_through_session_sink_on_disk` test in
//! [`crate::mosaic`].
//!
//! ## Progress reporting
//!
//! Every progress update emitted by the wizard carries a structured
//! [`ProgressDetail::Mosaic`] payload (`panel_index`, `total_panels`).
//! The Dart Run Dashboard consumes the typed payload directly so it
//! can render "Panel 5/9" without parsing message strings.

use crate::instructions::execute_mosaic;
use crate::node::context::ExecutionContext;
use crate::node::progress::{ProgressDetail, ProgressUpdate};
use crate::node::registry::InstructionNode;
use crate::{NodeStatus, NodeType};
use async_trait::async_trait;

pub struct MosaicInstruction;

#[async_trait]
impl InstructionNode for MosaicInstruction {
    fn type_name(&self) -> &'static str {
        "Mosaic"
    }

    async fn execute(
        &self,
        node_id: &str,
        node_type: &NodeType,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        let NodeType::Mosaic(config) = node_type else {
            tracing::error!("MosaicInstruction received non-Mosaic variant");
            return NodeStatus::Failure;
        };

        let ctx = context.to_instruction_context().await;
        let progress_cb = context.progress_callback.as_ref();
        let total_panels = config
            .panels_horizontal
            .saturating_mul(config.panels_vertical);
        let panels_horizontal = config.panels_horizontal;

        let progress_fn = |progress: f64, detail: String| {
            if let Some(cb) = progress_cb {
                let panel_index = extract_panel_index(&detail).unwrap_or(0);
                // Wave 4.5 — derive panel_row / panel_col from the panel
                // index using the configured horizontal grid width.
                // The mosaic plan emits panels in row-major order
                // (`calculate_mosaic_panels` enforces this), so
                // `row = idx / cols`, `col = idx % cols`. `panel_index`
                // here is 1-based when extracted from the progress
                // string ("panel 5/9"); we convert to 0-based for the
                // row/col arithmetic, then keep `panel_index` as 1-based
                // in the payload (matches the existing wire shape).
                let (panel_row, panel_col) = if panels_horizontal > 0 && panel_index > 0 {
                    let zero_based = panel_index - 1;
                    (
                        Some(zero_based / panels_horizontal),
                        Some(zero_based % panels_horizontal),
                    )
                } else {
                    (None, None)
                };
                cb(ProgressUpdate::instruction_progress(
                    node_id.to_string(),
                    "Mosaic",
                    progress,
                    ProgressDetail::Mosaic {
                        panel_index,
                        total_panels,
                        panel_row,
                        panel_col,
                    },
                ));
            }
        };

        execute_mosaic(config, &ctx, Some(&progress_fn))
            .await
            .log_and_get_status_with_context("Mosaic", &ctx)
    }
}

fn extract_panel_index(detail: &str) -> Option<u32> {
    let lower = detail.to_lowercase();
    let idx = lower.find("panel ")?;
    let rest = &detail[idx + "panel ".len()..];
    let mut buf = String::new();
    for c in rest.chars() {
        if c.is_ascii_digit() {
            buf.push(c);
        } else {
            break;
        }
    }
    if buf.is_empty() {
        None
    } else {
        buf.parse::<u32>().ok()
    }
}
