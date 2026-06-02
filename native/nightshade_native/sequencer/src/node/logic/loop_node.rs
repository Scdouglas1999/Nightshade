//! Loop logic node.

use crate::node::context::ExecutionContext;
use crate::node::logic::sequential::execute_children_sequential;
use crate::node::progress::ProgressUpdate;
use crate::node::runtime::RuntimeNode;
use crate::node::Node;
use crate::{LoopCondition, LoopConfig, NodeStatus};

pub async fn execute_loop(
    node: &mut RuntimeNode,
    config: LoopConfig,
    context: &mut ExecutionContext,
) -> NodeStatus {
    // P1-8: do NOT reset current_iteration here. A fresh run already has it at
    // 0 (from_definition / reset), and a nested re-run is preceded by the
    // parent's reset() — so the only time it's non-zero on entry is a RESUME,
    // where `resume_from_checkpoint` restored it via restore_loop_iterations.
    // Unconditionally zeroing it made a resumed Count loop restart at iteration
    // 1 and re-image every already-captured iteration.

    // Count-based loops have an explicit upper bound; condition-based loops
    // (UntilTime, AltitudeBelow, WhileDark, etc.) terminate via runtime
    // checks inside the loop body, so the bound stays effectively infinite.
    let max_iterations = match config.condition {
        // `iterations: Option<u32>` — semantically REQUIRED when condition
        // == Count, optional otherwise. UI builder enforces this; `unwrap_or(1)`
        // is a safety floor for a legacy/corrupt sequence file where Count
        // was selected without iterations. A single execution is the safest
        // interpretation of "Count with no count".
        LoopCondition::Count => config.iterations.unwrap_or(1),
        _ => u32::MAX,
    };

    loop {
        if context.is_cancelled().await {
            return NodeStatus::Cancelled;
        }
        if context.is_skip_to_next_target_requested() {
            return NodeStatus::Skipped;
        }

        let should_continue = match config.condition {
            LoopCondition::Count => node.current_iteration < max_iterations,
            LoopCondition::UntilTime => {
                if let Some(until) = config.condition_value {
                    // condition_value is f64 carrying a Unix timestamp; year
                    // 2038 is ~2.1e9 (< 2^31), still 1000x below f64 precision
                    // limit. f64 -> i64 saturates per Rust 1.45 spec.
                    chrono::Utc::now().timestamp() < (until as i64)
                } else {
                    false
                }
            }
            LoopCondition::AltitudeBelow => {
                if let Some(threshold) = config.condition_value {
                    let Some(current_alt) = context.calculate_altitude() else {
                        tracing::error!(
                            "Loop condition AltitudeBelow requires target coordinates and observer location"
                        );
                        return NodeStatus::Failure;
                    };
                    current_alt >= threshold
                } else {
                    false
                }
            }
            LoopCondition::AltitudeAbove => {
                if let Some(threshold) = config.condition_value {
                    let Some(current_alt) = context.calculate_altitude() else {
                        tracing::error!(
                            "Loop condition AltitudeAbove requires target coordinates and observer location"
                        );
                        return NodeStatus::Failure;
                    };
                    current_alt <= threshold
                } else {
                    false
                }
            }
            LoopCondition::IntegrationTime => {
                if let Some(target_secs) = config.condition_value {
                    let integrated_secs = context.get_completed_integration_secs().await;
                    integrated_secs < target_secs
                } else {
                    false
                }
            }
            LoopCondition::Forever => true,
            LoopCondition::WhileDark => {
                let Some(is_dark) = context.is_dark() else {
                    tracing::error!(
                        "Loop condition WhileDark requires observer latitude/longitude"
                    );
                    return NodeStatus::Failure;
                };
                is_dark
            }
        };

        if !should_continue {
            break;
        }

        node.current_iteration += 1;
        tracing::info!("=== LOOP ITERATION {} STARTING ===", node.current_iteration);
        tracing::info!("Loop has {} children", node.children.len());
        for (i, child) in node.children.iter().enumerate() {
            tracing::info!("  Child {}: '{}' (id={})", i, child.name(), child.id());
        }

        let total_children = match config.condition {
            // max_iterations is u32 -> usize widening (lossless on >=32-bit platforms).
            LoopCondition::Count => Some(max_iterations as usize),
            _ => None,
        };

        let mut update = ProgressUpdate::lifecycle(
            node.id().clone(),
            NodeStatus::Running,
            format!("Loop iteration {}", node.current_iteration),
        );
        // current_iteration is u32 -> usize widening (lossless).
        update.current_child = Some(node.current_iteration as usize);
        update.total_children = total_children;
        context.send_progress(update);

        // Children retain Success/Failure from the previous iteration and
        // would short-circuit on the next pass; resetting them per-iter is
        // what makes a Loop actually re-execute its body.
        tracing::info!(
            "Resetting {} children for iteration {}",
            node.children.len(),
            node.current_iteration
        );
        for child in &mut node.children {
            child.reset();
        }
        tracing::info!("Children reset complete");

        tracing::info!(
            "Starting execute_children_sequential for iteration {}",
            node.current_iteration
        );
        let result = execute_children_sequential(node, context).await;
        tracing::info!(
            "execute_children_sequential completed with result: {:?}",
            result
        );
        if result == NodeStatus::Skipped && context.is_skip_to_next_target_requested() {
            return NodeStatus::Skipped;
        }
        if result == NodeStatus::Failure || result == NodeStatus::Cancelled {
            return result;
        }
    }

    NodeStatus::Success
}
