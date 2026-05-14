// CQ-W3-API-RS: split from monolithic api.rs (audit-rust §9 / audit-arch §1.2)
#![allow(unused_imports)]
// Shared imports inherited from the monolithic api.rs (audit-rust §9).
use crate::adaptive_polling::{AdaptivePoller, PollerPreset};
use crate::device::*;
use crate::devices::DeviceManager;
use crate::error::*;
use crate::event::*;
use crate::filter_matching::find_filter_match;
use crate::state::*;
use crate::storage::{AppSettings, ObserverLocation};
use crate::unified_device_ops::create_unified_device_ops;
use nightshade_imaging::{
    calculate_airmass, validate_fits_header, validate_image, write_fits, BayerPattern,
    DebayerAlgorithm, FitsHeader, ImageData,
};
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;
use tokio::sync::RwLock;
// Sibling-module items via the parent's pub use re-exports.
use super::*;

// =============================================================================
// Session Management
// =============================================================================

/// Get current session state
pub async fn api_get_session_state() -> SessionState {
    get_state().get_session().await
}

/// Start a new imaging session
pub async fn api_start_session(
    target_name: Option<String>,
    ra: Option<f64>,
    dec: Option<f64>,
) -> Result<(), NightshadeError> {
    get_state().start_session(target_name, ra, dec).await;
    tracing::info!("Session started");
    Ok(())
}

/// End the current session
pub async fn api_end_session() -> Result<(), NightshadeError> {
    get_state().end_session().await;
    tracing::info!("Session ended");
    Ok(())
}