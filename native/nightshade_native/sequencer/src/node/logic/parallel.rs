//! Parallel logic node.
//!
//! Replaces the pre-refactor 22-field manual ExecutionContext copy with a
//! single `ctx.clone()` call. The clone is cheap because every non-Copy
//! field is wrapped in `Arc` so the clone is a refcount bump.

use crate::node::context::ExecutionContext;
use crate::node::progress::ProgressUpdate;
use crate::node::runtime::RuntimeNode;
use crate::node::Node;
use crate::{NodeDefinition, NodeStatus, NodeType, ParallelConfig};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Arc;
use tokio::sync::Mutex as TokioMutex;

pub async fn execute_parallel(
    node: &mut RuntimeNode,
    config: ParallelConfig,
    context: &mut ExecutionContext,
) -> NodeStatus {
    let total_children = node.children.len();
    if total_children == 0 {
        return NodeStatus::Success;
    }

    // `required_successes: Option<u32>` — None means all children must succeed,
    // which matches the parallel-AND default.
    let required = config.required_successes.unwrap_or(total_children);
    let node_id = node.id().clone();

    let mut update = ProgressUpdate::lifecycle(
        node_id.clone(),
        NodeStatus::Running,
        format!("Running {} parallel branches", total_children),
    );
    update.current_child = Some(0);
    update.total_children = Some(total_children);
    context.send_progress(update);

    let success_count = Arc::new(AtomicUsize::new(0));
    let cancelled = Arc::new(AtomicBool::new(false));

    // Children are owned by &mut node but the spawned tasks need 'static
    // lifetimes; wrapping each in Arc<Mutex<_>> lets them survive join_all
    // without cloning the underlying Node. They are unwrapped back into
    // node.children below after every task completes.
    let children = std::mem::take(&mut node.children);
    let children: Vec<Arc<TokioMutex<Box<dyn Node>>>> = children
        .into_iter()
        .map(|c| Arc::new(TokioMutex::new(c)))
        .collect();

    let handles: Vec<_> = children
        .iter()
        .enumerate()
        .map(|(i, child)| {
            let child = child.clone();
            let success_count = success_count.clone();
            let cancelled = cancelled.clone();
            // The blocker for `#[derive(Clone)]` on ExecutionContext was the
            // `Box<dyn Fn>` callbacks. Now they are `Arc<dyn Fn>`, so the
            // entire context clones cheaply (every non-Copy field is Arc'd)
            // and the pre-refactor 22-field manual copy disappears.
            let mut branch_context = context.clone();
            branch_context.node_id = format!("{}_branch_{}", node_id, i);
            // Spawned branches do not report progress to the parent's
            // callback (matches pre-refactor behaviour). The other Arc'd
            // shared-state fields stay populated so the branch can still
            // cancel, update trigger state, etc.
            branch_context.progress_callback = None;
            branch_context.polar_align_image_callback = None;

            let is_cancelled = context.is_cancelled.clone();

            tokio::spawn(async move {
                if is_cancelled.load(Ordering::Relaxed) || cancelled.load(Ordering::Relaxed) {
                    return (i, NodeStatus::Cancelled);
                }

                let mut child_guard = child.lock().await;
                let result = child_guard.execute(&mut branch_context).await;

                match result {
                    NodeStatus::Success => {
                        success_count.fetch_add(1, Ordering::Relaxed);
                    }
                    NodeStatus::Cancelled => {
                        cancelled.store(true, Ordering::Relaxed);
                    }
                    _ => {}
                }

                (i, result)
            })
        })
        .collect();

    let _results: Vec<_> = futures::future::join_all(handles)
        .await
        .into_iter()
        .filter_map(|r| r.ok())
        .collect();

    // Restore children from mutex wrappers. Audit §1.12: try_unwrap failure
    // means another task somewhere is still holding a clone of the child Arc
    // — i.e. the parallel-execution invariant has been violated. Previously
    // we silently dropped the unrecovered child; now we surface the violation
    // by returning Failure. Unrecovered children are replaced with
    // placeholder Failed nodes so subsequent walks see a structurally valid
    // tree (length and order preserved).
    let mut restored_children = Vec::with_capacity(children.len());
    let mut unrecovered = 0usize;
    for child_mutex in children {
        match Arc::try_unwrap(child_mutex) {
            Ok(mutex) => {
                restored_children.push(mutex.into_inner());
            }
            Err(_arc) => {
                tracing::error!(
                    "[NODE_TREE] Failed to reclaim child from parallel execution; a spawned task is still holding the Arc. \
                     This is a logical-impossibility violation — returning Failure so the user is told."
                );
                unrecovered += 1;
                let placeholder_def = NodeDefinition {
                    id: format!("__unrecovered_child_{}", unrecovered),
                    name: "Unrecovered parallel child".to_string(),
                    // Park is a no-op for the walker; the surrounding
                    // NodeStatus::Failure return is the actual signal to the caller.
                    node_type: NodeType::Park,
                    enabled: false,
                    children: Vec::new(),
                };
                let placeholder = RuntimeNode::from_definition(placeholder_def);
                restored_children.push(Box::new(placeholder));
            }
        }
    }
    node.children = restored_children;
    if unrecovered > 0 {
        return NodeStatus::Failure;
    }

    if context.is_cancelled.load(Ordering::Relaxed) || cancelled.load(Ordering::Relaxed) {
        return NodeStatus::Cancelled;
    }

    let successes = success_count.load(Ordering::Relaxed);

    let final_status = if successes >= required {
        NodeStatus::Success
    } else {
        NodeStatus::Failure
    };
    let mut final_update = ProgressUpdate::lifecycle(
        node_id.clone(),
        final_status,
        format!("{}/{} branches succeeded", successes, total_children),
    );
    final_update.current_child = Some(total_children);
    final_update.total_children = Some(total_children);
    context.send_progress(final_update);

    if successes >= required {
        NodeStatus::Success
    } else {
        tracing::warn!(
            "Parallel node: only {}/{} branches succeeded, required {}",
            successes,
            total_children,
            required
        );
        NodeStatus::Failure
    }
}
