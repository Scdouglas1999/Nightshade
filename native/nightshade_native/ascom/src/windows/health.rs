//! Connection health monitoring for ASCOM devices.
//!
//! # `unwrap_or` policy (audit-rust §4.3)
//!
//! All `unwrap_or(0)` sites in this file follow a `SystemTime::now()
//! .duration_since(UNIX_EPOCH)` chain that only fails if the system clock
//! is set to before 1970-01-01 — a configuration we have classified as
//! "user has chosen to break Unix time, accept degraded health metrics".
//! Returning `0` produces a timestamp before the connection was opened,
//! which the `time_since_last_success()` `saturating_sub` already handles
//! by clamping to `0` (treated as "no successful op yet").
//! The same `0` fallback is used in `get_health()` — `now == 0` and
//! `last_success == 0` are handled by the `last_success == 0 → Unknown`
//! early return immediately after, so no degraded false-positive is
//! reported either.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

/// Health status of an ASCOM device connection
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionHealth {
    /// Device is healthy and responding
    Healthy,
    /// Device is not responding but may recover
    Degraded,
    /// Device connection has failed
    Failed,
    /// Device health is unknown (not yet checked)
    Unknown,
}

/// Tracks connection health for an ASCOM device
#[derive(Debug)]
pub struct HealthMonitor {
    /// Last successful communication timestamp (epoch ms)
    last_success: AtomicU64,
    /// Last failed communication timestamp (epoch ms)
    last_failure: AtomicU64,
    /// Consecutive failure count
    failure_count: std::sync::atomic::AtomicU32,
    /// Whether the connection is considered healthy
    is_healthy: AtomicBool,
    /// Maximum time between health checks before considering connection degraded (ms)
    health_check_interval_ms: u64,
    /// Number of consecutive failures before marking connection as failed
    max_failures: u32,
}

impl Default for HealthMonitor {
    fn default() -> Self {
        Self {
            last_success: AtomicU64::new(0),
            last_failure: AtomicU64::new(0),
            failure_count: std::sync::atomic::AtomicU32::new(0),
            is_healthy: AtomicBool::new(true),
            health_check_interval_ms: 30_000, // 30 seconds
            max_failures: 3,
        }
    }
}

impl HealthMonitor {
    /// Create a new health monitor with custom settings
    pub fn new(health_check_interval_ms: u64, max_failures: u32) -> Self {
        Self {
            health_check_interval_ms,
            max_failures,
            ..Default::default()
        }
    }

    /// Record a successful operation
    pub fn record_success(&self) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        self.last_success.store(now, Ordering::SeqCst);
        self.failure_count.store(0, Ordering::SeqCst);
        self.is_healthy.store(true, Ordering::SeqCst);
    }

    /// Record a failed operation
    pub fn record_failure(&self) {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        self.last_failure.store(now, Ordering::SeqCst);
        let failures = self.failure_count.fetch_add(1, Ordering::SeqCst) + 1;
        if failures >= self.max_failures {
            self.is_healthy.store(false, Ordering::SeqCst);
        }
    }

    /// Get the current health status
    pub fn get_health(&self) -> ConnectionHealth {
        if !self.is_healthy.load(Ordering::SeqCst) {
            return ConnectionHealth::Failed;
        }

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        let last_success = self.last_success.load(Ordering::SeqCst);

        if last_success == 0 {
            return ConnectionHealth::Unknown;
        }

        let elapsed = now.saturating_sub(last_success);
        if elapsed > self.health_check_interval_ms {
            ConnectionHealth::Degraded
        } else {
            ConnectionHealth::Healthy
        }
    }

    /// Reset the health monitor (e.g., on reconnection)
    pub fn reset(&self) {
        self.last_success.store(0, Ordering::SeqCst);
        self.last_failure.store(0, Ordering::SeqCst);
        self.failure_count.store(0, Ordering::SeqCst);
        self.is_healthy.store(true, Ordering::SeqCst);
    }

    /// Get time since last successful operation in milliseconds
    pub fn time_since_last_success(&self) -> Option<u64> {
        let last = self.last_success.load(Ordering::SeqCst);
        if last == 0 {
            return None;
        }
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        Some(now.saturating_sub(last))
    }
}
