//! Notification instruction node.
//!
//! the title and message both flow through the variable
//! interpolation engine before being shown to the user, so templates like
//! `"${target.name} done. ${frame.total} frames captured."` render against
//! the live sequence context.

use crate::expressions::{interpolate, EvaluationFrame};
use crate::instructions::execute_notification;
use crate::node::context::ExecutionContext;
use crate::node::registry::InstructionNode;
use crate::{NodeStatus, NodeType, NotificationConfig};
use async_trait::async_trait;

pub struct NotificationInstruction;

#[async_trait]
impl InstructionNode for NotificationInstruction {
    fn type_name(&self) -> &'static str {
        "Notification"
    }

    async fn execute(
        &self,
        node_id: &str,
        node_type: &NodeType,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        let NodeType::Notification(config) = node_type else {
            tracing::error!("NotificationInstruction received non-Notification variant");
            return NodeStatus::Failure;
        };

        // Notifications fire OUTSIDE an exposure burst, so frame fields are
        // None in the EvaluationFrame. A user template that references
        // `${frame}` from a notification will surface as Unresolvable — the
        // intended behaviour, since the alert wouldn't have a meaningful
        // frame number to substitute.
        let frame = EvaluationFrame::empty();

        let title = match interpolate(&config.title, context, &frame) {
            Ok(s) => s,
            Err(e) => {
                tracing::error!(
                    "Notification title `{}` failed interpolation: {e}",
                    config.title
                );
                return NodeStatus::Failure;
            }
        };
        let message = match interpolate(&config.message, context, &frame) {
            Ok(s) => s,
            Err(e) => {
                tracing::error!(
                    "Notification message `{}` failed interpolation: {e}",
                    config.message
                );
                return NodeStatus::Failure;
            }
        };
        let interpolated = NotificationConfig {
            title,
            message,
            level: config.level,
            // preserve the user's per-node
            // transport override through interpolation so the bridge event
            // carries it for the Dart NotificationRouter to consume.
            explicit_transports: config.explicit_transports.clone(),
        };

        let ctx = context.to_instruction_context(node_id).await;
        execute_notification(&interpolated, &ctx)
            .await
            .log_and_get_status_with_context("Notification", &ctx)
    }
}
