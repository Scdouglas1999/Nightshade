//! Timeout configuration for ASCOM operations.

/// Default timeout values for different operation types (in milliseconds)
#[derive(Debug, Clone, Copy)]
pub struct TimeoutConfig {
    /// Default timeout for property get operations
    pub property_get_ms: u64,
    /// Default timeout for property set operations
    pub property_set_ms: u64,
    /// Default timeout for method calls
    pub method_call_ms: u64,
    /// Timeout for long-running operations (slewing, exposures, etc.)
    pub long_operation_ms: u64,
    /// Timeout for connection operations
    pub connect_ms: u64,
}

impl Default for TimeoutConfig {
    fn default() -> Self {
        Self {
            property_get_ms: 5_000,     // 5 seconds
            property_set_ms: 10_000,    // 10 seconds
            method_call_ms: 30_000,     // 30 seconds
            long_operation_ms: 300_000, // 5 minutes
            connect_ms: 60_000,         // 1 minute
        }
    }
}

/// Global timeout configuration - can be modified at runtime
static TIMEOUT_CONFIG: std::sync::OnceLock<std::sync::RwLock<TimeoutConfig>> =
    std::sync::OnceLock::new();

/// Get the current timeout configuration
pub fn get_timeout_config() -> TimeoutConfig {
    TIMEOUT_CONFIG
        .get_or_init(|| std::sync::RwLock::new(TimeoutConfig::default()))
        .read()
        .map(|g| *g)
        .unwrap_or_else(|e| *e.into_inner())
}

/// Set the timeout configuration
pub fn set_timeout_config(config: TimeoutConfig) {
    if let Some(lock) = TIMEOUT_CONFIG.get() {
        match lock.write() {
            Ok(mut guard) => *guard = config,
            Err(e) => {
                *e.into_inner() = config;
            }
        }
    } else {
        let _ = TIMEOUT_CONFIG.set(std::sync::RwLock::new(config));
    }
}
