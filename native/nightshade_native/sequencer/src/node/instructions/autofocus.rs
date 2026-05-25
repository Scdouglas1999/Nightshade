//! Autofocus instruction node.

use crate::instructions::execute_autofocus;
use crate::node::context::ExecutionContext;
use crate::node::progress::{ProgressDetail, ProgressUpdate};
use crate::node::registry::InstructionNode;
use crate::{NodeStatus, NodeType};
use async_trait::async_trait;

pub struct AutofocusInstruction;

#[async_trait]
impl InstructionNode for AutofocusInstruction {
    fn type_name(&self) -> &'static str {
        "Autofocus"
    }

    async fn execute(
        &self,
        node_id: &str,
        node_type: &NodeType,
        context: &mut ExecutionContext,
    ) -> NodeStatus {
        let NodeType::Autofocus(config) = node_type else {
            tracing::error!("AutofocusInstruction received non-Autofocus variant");
            return NodeStatus::Failure;
        };

        let ctx = context.to_instruction_context().await;
        let progress_cb = context.progress_callback.as_ref();
        let steps_out = config.steps_out;
        let total_steps = steps_out.saturating_mul(2).saturating_add(1);

        let progress_fn = |progress: f64, detail_str: String| {
            if let Some(cb) = progress_cb {
                let (step, hfr) = parse_autofocus_detail(&detail_str);
                let detail = if step.is_some() || hfr.is_some() {
                    ProgressDetail::Autofocus {
                        step: step.unwrap_or(0),
                        total_steps,
                        current_hfr: hfr,
                    }
                } else {
                    ProgressDetail::Generic(detail_str)
                };
                cb(ProgressUpdate::instruction_progress(
                    node_id.to_string(),
                    "Autofocus",
                    progress,
                    detail,
                ));
            }
        };

        let result = execute_autofocus(config, &ctx, Some(&progress_fn)).await;

        if result.status == NodeStatus::Success {
            if let Some(trigger_state_lock) = &context.trigger_state {
                let mut trigger_state = trigger_state_lock.write().await;
                if let Some(best_hfr) = result.hfr_values.first() {
                    trigger_state.update_hfr(*best_hfr);
                    trigger_state.reset_baseline_hfr();
                    tracing::debug!("Reset HFR baseline to {:.2} after autofocus", best_hfr);
                }
                trigger_state.mark_autofocus_performed();
                tracing::debug!(
                    "Marked autofocus performed at exposure {}",
                    trigger_state.completed_exposures
                );
            }
        }

        result.log_and_get_status_with_context("Autofocus", &ctx)
    }
}

/// Parse "step N" and "hfr X.Y" style fragments from the autofocus
/// instruction's free-form detail string.
fn parse_autofocus_detail(s: &str) -> (Option<u32>, Option<f64>) {
    let lower = s.to_lowercase();
    let step = lower.find("step ").and_then(|idx| {
        let rest = &s[idx + "step ".len()..];
        rest.split(|c: char| !c.is_ascii_digit())
            .next()
            .and_then(|t| t.parse::<u32>().ok())
    });
    let hfr = lower.find("hfr").and_then(|idx| {
        let rest = &s[idx + "hfr".len()..];
        let mut start = None;
        for (i, c) in rest.char_indices() {
            if c.is_ascii_digit() || c == '.' || c == '-' {
                start = Some(i);
                break;
            }
        }
        let start = start?;
        let tail = &rest[start..];
        let mut end = tail.len();
        for (i, c) in tail.char_indices() {
            if !(c.is_ascii_digit() || c == '.' || c == '-') {
                end = i;
                break;
            }
        }
        tail[..end].parse::<f64>().ok()
    });
    (step, hfr)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_step_and_hfr() {
        let (s, h) = parse_autofocus_detail("step 3 of 13 HFR 2.45");
        assert_eq!(s, Some(3));
        assert_eq!(h, Some(2.45));
    }

    #[test]
    fn handles_missing_fields() {
        let (s, h) = parse_autofocus_detail("Moving focuser");
        assert!(s.is_none());
        assert!(h.is_none());
    }
}
