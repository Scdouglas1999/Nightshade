//! Public API exposed to Dart via flutter_rust_bridge
//!
//! This module contains all the functions that can be called from Dart.
//! Each function is marked with the appropriate flutter_rust_bridge attributes.

use crate::device::*;
use crate::device_manager::DeviceManager;
use crate::error::*;
use crate::event::*;
use crate::state::*;
use std::sync::atomic::Ordering;
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

/// Global application state singleton
static APP_STATE: OnceLock<SharedAppState> = OnceLock::new();

/// Get or initialize the global application state
#[flutter_rust_bridge::frb(ignore)]
pub fn get_state() -> &'static SharedAppState {
    APP_STATE.get_or_init(AppState::new)
}

/// Global device manager singleton
static DEVICE_MANAGER: OnceLock<Arc<DeviceManager>> = OnceLock::new();

/// Get or initialize the global device manager
#[flutter_rust_bridge::frb(ignore)]
pub fn get_device_manager() -> &'static Arc<DeviceManager> {
    DEVICE_MANAGER.get_or_init(|| DeviceManager::new(get_state().clone()))
}

// =============================================================================
// Unified Discovery Cache (ASCOM + Alpaca + Native + INDI)
// =============================================================================

/// Unified cache for ALL discovered devices across every discovery source.
/// When `api_discover_devices()` is called for any device type, the first call
/// runs full discovery for all sources (ASCOM, Alpaca, Native, INDI) and caches
/// every result. Subsequent calls within the TTL just filter by device_type.
struct DiscoveryCache {
    /// All discovered devices from every source, unfiltered
    all_devices: Vec<DeviceInfo>,
    /// When the cache was last populated
    timestamp: Instant,
}

/// Global unified discovery cache
static DISCOVERY_CACHE: OnceLock<Mutex<Option<DiscoveryCache>>> = OnceLock::new();

// =============================================================================
// Event Stream Overflow Tracking
// =============================================================================

use std::sync::atomic::AtomicU64;

/// Global counter for total events dropped across all event streams.
/// This is incremented when a receiver falls behind and events are skipped.
static TOTAL_DROPPED_EVENTS: AtomicU64 = AtomicU64::new(0);
static TEMP_FITS_FILE_COUNTER: AtomicU64 = AtomicU64::new(0);

/// How long to cache unified discovery results (60 seconds)
const DISCOVERY_CACHE_TTL: Duration = Duration::from_secs(60);

/// Get or initialize the discovery cache
fn get_discovery_cache() -> &'static Mutex<Option<DiscoveryCache>> {
    DISCOVERY_CACHE.get_or_init(|| Mutex::new(None))
}

/// Discovery state to prevent concurrent discovery operations
static DISCOVERY_IN_PROGRESS: OnceLock<Mutex<bool>> = OnceLock::new();

fn get_discovery_lock() -> &'static Mutex<bool> {
    DISCOVERY_IN_PROGRESS.get_or_init(|| Mutex::new(false))
}

pub(crate) fn create_unique_temp_fits_path(prefix: &str) -> std::path::PathBuf {
    let counter = TEMP_FITS_FILE_COUNTER.fetch_add(1, Ordering::Relaxed);
    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "{}_{}_{}_{}.fits",
        prefix,
        std::process::id(),
        timestamp,
        counter
    ))
}

/// Invalidate the unified discovery cache, forcing fresh discovery on next call.
/// Also invalidates the native SDK discovery cache so vendor SDKs are re-queried.
/// Called when user explicitly requests a rescan.
pub async fn api_invalidate_discovery_cache() {
    // Invalidate the unified cache
    let mut cache = get_discovery_cache().lock().await;
    *cache = None;
    // Also invalidate the native vendor SDK cache so it re-queries all SDKs
    nightshade_native::invalidate_discovery_cache().await;
    tracing::info!("Discovery cache invalidated");
}

// =============================================================================
// Submodule declarations (CQ-W3-API-RS decomposition — audit-rust §9)
// =============================================================================

pub mod init;
pub mod event_stream;
pub mod discovery;
pub mod connection;
pub mod heartbeat;
pub mod api_version;
pub mod session;
pub mod storage;
pub mod diagnostics;
pub mod plate_solve;
pub mod phd2;
pub mod polar_alignment;
pub mod sequencer;
pub mod imaging;
pub mod devices;

pub use init::*;
pub use event_stream::*;
pub use discovery::*;
pub use connection::*;
pub use heartbeat::*;
pub use api_version::*;
pub use session::*;
pub use storage::*;
pub use diagnostics::*;
pub use plate_solve::*;
pub use phd2::*;
pub use polar_alignment::*;
pub use sequencer::*;
pub use imaging::*;
pub use devices::*;
