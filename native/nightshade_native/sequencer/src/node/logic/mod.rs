//! Container / logic node implementations.
//!
//! These nodes need `&mut self.children` (and, for Loop, `&mut self.current_iteration`)
//! access on `RuntimeNode`, which makes them awkward to push through a trait-object
//! dispatch. Each logic file exposes a free-standing `execute_*(node, config, context)`
//! function that takes a `&mut RuntimeNode` so the implementations can be split out
//! of the giant `node.rs` match without owning RuntimeNode's internals.

pub mod conditional;
pub mod loop_node;
pub mod parallel;
pub mod recovery;
pub mod sequential;
pub mod target_header;
// Wave 3 Agent 1: TargetScheduler — dynamic target picker.
pub mod target_scheduler;
