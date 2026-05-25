//! Delay instruction node.

use crate::instructions::execute_delay;
use crate::node::context::ExecutionContext;
use crate::node::progress::{ProgressDetail, ProgressUpdate};
use crate::node::registry::InstructionNode;
use crate::{NodeStatus, NodeType};
use async_trait::async_trait;

pub struct DelayInstruction;

#[async_trait]
impl InstructionNode for DelayInstruction {
    fn type_name(&self) -> &'static str {
        "Delay"
    }

    async fn execute(
        &self,
        node_id: &str,
        node_type: &NodeType,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        let NodeType::Delay(config) = node_type else {
            tracing::error!("DelayInstruction received non-Delay variant");
            return NodeStatus::Failure;
        };

        let ctx = context.to_instruction_context().await;
        let progress_cb = context.progress_callback.as_ref();
        let total_secs = config.seconds;

        let progress_fn = |progress: f64, _detail: String| {
            if let Some(cb) = progress_cb {
                // Delay reports progress as a fraction of total elapsed; we
                // turn that into structured `remaining_secs` without parsing.
                let remaining = (total_secs * (1.0 - progress / 100.0)).max(0.0);
                cb(ProgressUpdate::instruction_progress(
                    node_id.to_string(),
                    "Delay",
                    progress,
                    ProgressDetail::Wait {
                        remaining_secs: remaining,
                    },
                ));
            }
        };

        execute_delay(config, &ctx, Some(&progress_fn))
            .await
            .log_and_get_status_with_context("Delay", &ctx)
    }
}
