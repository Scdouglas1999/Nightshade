//! RuntimeNode — the live behaviour-tree node built from a NodeDefinition.
//!
//! The top-level execute() dispatch is intentionally small: container/logic
//! variants are routed to `node::logic::*` (which need `&mut self.children`
//! access) and every other variant goes through the `InstructionRegistry`
//! trait dispatch.

use crate::expressions::{interpolate, EvaluationFrame};
use crate::node::context::ExecutionContext;
use crate::node::logic;
use crate::node::progress::ProgressUpdate;
use crate::node::registry::registry;
use crate::{NodeDefinition, NodeId, NodeStatus, NodeType};
use async_trait::async_trait;

/// Wave 4 — render a node's display name through the interpolation engine.
///
/// Display strings are non-load-bearing: when interpolation fails we log
/// at debug! (a user-visible label that won't render is annoying but not
/// dangerous) and return the raw template. Errors that are load-bearing
/// (script arguments, save paths, notification text) use a fail-closed
/// path elsewhere — this helper exists specifically for the cosmetic
/// label channel.
fn render_node_display_name(raw: &str, context: &ExecutionContext) -> String {
    // Fast path: no `${` anywhere → skip the parser entirely.
    if !raw.contains("${") {
        return raw.to_string();
    }
    let frame = EvaluationFrame::empty();
    match interpolate(raw, context, &frame) {
        Ok(rendered) => rendered,
        Err(e) => {
            tracing::debug!("Node display name `{raw}` interpolation failed (non-fatal): {e}");
            raw.to_string()
        }
    }
}

/// Base trait for all behaviour-tree nodes.
#[async_trait]
pub trait Node: Send + Sync {
    fn id(&self) -> &NodeId;
    fn name(&self) -> &str;
    fn node_type(&self) -> &NodeType;
    fn is_enabled(&self) -> bool;
    async fn execute(&mut self, context: &mut ExecutionContext) -> NodeStatus;
    fn reset(&mut self);
    async fn abort(&mut self);
    fn children(&self) -> &[Box<dyn Node>];
    fn children_mut(&mut self) -> &mut Vec<Box<dyn Node>>;
    fn mark_completed(&mut self, node_id: &NodeId);
    /// Trust-patch §7: does this subtree contain `node_id`?
    fn contains_node(&self, node_id: &NodeId) -> bool {
        if self.id() == node_id {
            return true;
        }
        for child in self.children() {
            if child.contains_node(node_id) {
                return true;
            }
        }
        false
    }
}

/// A runtime node instance built from a NodeDefinition.
pub struct RuntimeNode {
    pub definition: NodeDefinition,
    pub children: Vec<Box<dyn Node>>,
    pub status: NodeStatus,
    pub current_iteration: u32,
}

impl RuntimeNode {
    pub fn from_definition(def: NodeDefinition) -> Self {
        Self {
            definition: def,
            children: Vec::new(),
            status: NodeStatus::Pending,
            current_iteration: 0,
        }
    }

    pub fn add_child(&mut self, child: Box<dyn Node>) {
        self.children.push(child);
    }
}

#[async_trait]
impl Node for RuntimeNode {
    fn id(&self) -> &NodeId {
        &self.definition.id
    }

    fn name(&self) -> &str {
        &self.definition.name
    }

    fn node_type(&self) -> &NodeType {
        &self.definition.node_type
    }

    fn is_enabled(&self) -> bool {
        self.definition.enabled
    }

    async fn execute(&mut self, context: &mut ExecutionContext) -> NodeStatus {
        if !self.definition.enabled {
            self.status = NodeStatus::Skipped;
            return NodeStatus::Skipped;
        }

        self.status = NodeStatus::Running;
        // Wave 4 — render the node display name through the interpolation
        // engine so user-authored templates like
        // "Image ${target.name} with ${filter}" become live labels in the
        // Run Dashboard. Resolution failure is non-fatal here (a display
        // string is not load-bearing); we log and fall back to the raw
        // template so the operator still sees something.
        let display_name = render_node_display_name(self.name(), context);
        context.send_progress(ProgressUpdate::lifecycle(
            self.id().clone(),
            NodeStatus::Running,
            format!("Executing: {}", display_name),
        ));

        // Cloning is cheap on serde-derived configs; this avoids a mutable
        // borrow of self.definition while we also need &mut self for the
        // container variants.
        let node_type = self.definition.node_type.clone();
        let node_id = self.definition.id.clone();

        let result = match &node_type {
            // Container / logic variants. They take `&mut self` so they can
            // walk self.children; the trait-registry dispatch does NOT cover
            // them.
            NodeType::TargetHeader(config) | NodeType::TargetGroup(config) => {
                logic::target_header::execute_target_header(self, config.clone(), context).await
            }
            NodeType::Loop(config) => {
                logic::loop_node::execute_loop(self, config.clone(), context).await
            }
            NodeType::Parallel(config) => {
                logic::parallel::execute_parallel(self, config.clone(), context).await
            }
            NodeType::Conditional(config) => {
                logic::conditional::execute_conditional(self, config.clone(), context).await
            }
            NodeType::Recovery(config) => {
                logic::recovery::execute_recovery(self, config.clone(), context).await
            }
            // Wave 3 Agent 1: TargetScheduler — dynamic target picker. Container
            // variant: needs &mut self to walk + reset children, so it lives
            // here alongside the other logic nodes rather than in the
            // instruction registry.
            NodeType::TargetScheduler(config) => {
                logic::target_scheduler::execute_target_scheduler(self, config.clone(), context)
                    .await
            }
            // All other variants — instruction nodes — go through the registry.
            other => match registry().build(other) {
                Some(instruction) => instruction.execute(&node_id, &node_type, context).await,
                None => {
                    tracing::error!(
                        "No instruction registered for variant {:?}; sequence cannot proceed",
                        other
                    );
                    NodeStatus::Failure
                }
            },
        };

        self.status = result;
        // Re-render in case interpolation values changed between Running
        // and Completed events (e.g. a target swap between events).
        let display_name = render_node_display_name(self.name(), context);
        context.send_progress(ProgressUpdate::lifecycle(
            self.id().clone(),
            result,
            format!("Completed: {}", display_name),
        ));

        result
    }

    fn reset(&mut self) {
        self.status = NodeStatus::Pending;
        self.current_iteration = 0;
        for child in &mut self.children {
            child.reset();
        }
    }

    async fn abort(&mut self) {
        self.status = NodeStatus::Cancelled;
        for child in &mut self.children {
            child.abort().await;
        }
    }

    fn children(&self) -> &[Box<dyn Node>] {
        &self.children
    }

    fn children_mut(&mut self) -> &mut Vec<Box<dyn Node>> {
        &mut self.children
    }

    fn mark_completed(&mut self, node_id: &NodeId) {
        if self.id() == node_id {
            self.status = NodeStatus::Success;
        } else {
            for child in &mut self.children {
                child.mark_completed(node_id);
            }
        }
    }
}
