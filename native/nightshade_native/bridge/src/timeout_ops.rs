//! Operation Timeout Utilities
//!
//! This module provides utilities for adding timeouts to device operations.
//! All device operations that communicate with hardware should be wrapped
//! with appropriate timeouts to prevent indefinite blocking.
//!
//! # Timeout Guidelines
//!
//! | Operation Type | Default Timeout | Notes |
//! |----------------|-----------------|-------|
//! | Connection | 30s | Initial device connection |
//! | Property Read | 5s | Getting device state |
//! | Property Write | 10s | Setting device parameters |
//! | Short Slew | 60s | Small mount movements |
//! | Long Slew | 300s | GoTo operations |
//! | Exposure Start | 10s | Begin exposure command |
//! | Exposure Wait | exposure_time + 60s | Wait for image |
//! | Image Download | 30s | Transfer image data |
//! | Focuser Move | 120s | Focuser position change |
//! | Filter Wheel | 60s | Filter wheel rotation |
//!
//! # Example
//!
//! ```rust
//! use nightshade_bridge::timeout_ops::*;
//!
//! async fn slew_mount(mount_id: &str, ra: f64, dec: f64) -> Result<(), NightshadeError> {
//!     with_timeout(
//!         mount_slew_internal(mount_id, ra, dec),
//!         Timeouts::long_slew(),
//!         mount_id,
//!         "slew_to_coordinates"
//!     ).await
//! }
//! ```

use crate::error::NightshadeError;
use std::future::Future;
use std::time::Duration;
use tokio::time::timeout;

// =========================================================================
// Standard Timeouts
// =========================================================================

/// Standard timeout values for different operation types
pub struct Timeouts;

impl Timeouts {
    /// Timeout for establishing a connection
    pub const fn connection() -> Duration {
        Duration::from_secs(30)
    }

    /// Timeout for reading device properties
    pub const fn property_read() -> Duration {
        Duration::from_secs(5)
    }

    /// Timeout for writing device properties
    pub const fn property_write() -> Duration {
        Duration::from_secs(10)
    }

    /// Timeout for short mount movements (small adjustments, pulse guide)
    pub const fn short_slew() -> Duration {
        Duration::from_secs(60)
    }

    /// Timeout for long mount movements (GoTo)
    pub const fn long_slew() -> Duration {
        Duration::from_secs(300)
    }

    /// Timeout for parking/unparking
    pub const fn park() -> Duration {
        Duration::from_secs(180)
    }

    /// Timeout for finding home
    pub const fn find_home() -> Duration {
        Duration::from_secs(300)
    }

    /// Timeout for starting an exposure
    pub const fn exposure_start() -> Duration {
        Duration::from_secs(10)
    }

    /// Calculate timeout for waiting for an exposure to complete
    pub fn exposure_wait(exposure_secs: f64) -> Duration {
        // Add 60s buffer for download and processing
        Duration::from_secs_f64(exposure_secs + 60.0)
    }

    /// Timeout for downloading image data
    pub const fn image_download() -> Duration {
        Duration::from_secs(30)
    }

    /// Timeout for large image downloads (high resolution cameras)
    pub const fn image_download_large() -> Duration {
        Duration::from_secs(120)
    }

    /// Timeout for focuser movements
    pub const fn focuser_move() -> Duration {
        Duration::from_secs(120)
    }

    /// Timeout for filter wheel rotation
    pub const fn filter_wheel() -> Duration {
        Duration::from_secs(60)
    }

    /// Timeout for rotator movements
    pub const fn rotator_move() -> Duration {
        Duration::from_secs(60)
    }

    /// Timeout for dome operations
    pub const fn dome() -> Duration {
        Duration::from_secs(300)
    }

    /// Timeout for dome shutter operations
    pub const fn dome_shutter() -> Duration {
        Duration::from_secs(120)
    }

    /// Timeout for cover calibrator operations
    pub const fn cover_calibrator() -> Duration {
        Duration::from_secs(30)
    }

    /// Timeout for heartbeat/ping operations
    pub const fn heartbeat() -> Duration {
        Duration::from_secs(5)
    }

    /// Timeout for device discovery
    pub const fn discovery() -> Duration {
        Duration::from_secs(10)
    }
}

// =========================================================================
// Timeout Wrapper Functions
// =========================================================================

/// Execute a future with a timeout, converting to NightshadeError on timeout
///
/// # Arguments
/// * `future` - The async operation to execute
/// * `timeout_duration` - Maximum time to wait
/// * `device_id` - Device ID for error context
/// * `operation` - Operation name for error context
///
/// # Returns
/// * `Ok(T)` - Operation completed within timeout
/// * `Err(NightshadeError::DeviceTimeout)` - Operation timed out
pub async fn with_timeout<T, F>(
    future: F,
    timeout_duration: Duration,
    device_id: &str,
    operation: &str,
) -> Result<T, NightshadeError>
where
    F: Future<Output = Result<T, NightshadeError>>,
{
    match timeout(timeout_duration, future).await {
        Ok(result) => result,
        Err(_elapsed) => Err(NightshadeError::DeviceTimeout {
            device_id: device_id.to_string(),
            operation: operation.to_string(),
            timeout_secs: timeout_duration.as_secs_f64(),
        }),
    }
}

/// Execute a future with a timeout, mapping string errors to NightshadeError
///
/// This variant is useful for operations that return `Result<T, String>`
pub async fn with_timeout_str<T, F>(
    future: F,
    timeout_duration: Duration,
    device_id: &str,
    operation: &str,
) -> Result<T, NightshadeError>
where
    F: Future<Output = Result<T, String>>,
{
    match timeout(timeout_duration, future).await {
        Ok(result) => result.map_err(|e| NightshadeError::OperationFailed(e)),
        Err(_elapsed) => Err(NightshadeError::DeviceTimeout {
            device_id: device_id.to_string(),
            operation: operation.to_string(),
            timeout_secs: timeout_duration.as_secs_f64(),
        }),
    }
}

/// Execute a future with a timeout, with a custom timeout error message
pub async fn with_timeout_custom<T, F, E>(
    future: F,
    timeout_duration: Duration,
    timeout_error: E,
) -> Result<T, NightshadeError>
where
    F: Future<Output = Result<T, NightshadeError>>,
    E: FnOnce() -> NightshadeError,
{
    match timeout(timeout_duration, future).await {
        Ok(result) => result,
        Err(_elapsed) => Err(timeout_error()),
    }
}

// =========================================================================
// Specialized Timeout Operations
// =========================================================================

/// Mount slew with appropriate timeout based on estimated slew distance
pub async fn mount_slew_with_timeout<F>(
    future: F,
    mount_id: &str,
    ra: f64,
    dec: f64,
    current_ra: Option<f64>,
    current_dec: Option<f64>,
) -> Result<(), NightshadeError>
where
    F: Future<Output = Result<(), NightshadeError>>,
{
    // Estimate slew time based on distance (if current position known)
    let timeout_duration = if let (Some(cur_ra), Some(cur_dec)) = (current_ra, current_dec) {
        let ra_diff = (ra - cur_ra).abs();
        let dec_diff = (dec - cur_dec).abs();
        let max_diff = ra_diff.max(dec_diff);

        // Rough estimate: 15 degrees per minute typical slew speed
        // Plus 30s buffer
        let estimated_secs = (max_diff / 0.25) + 30.0;
        Duration::from_secs_f64(estimated_secs.max(60.0).min(600.0))
    } else {
        Timeouts::long_slew()
    };

    with_timeout(future, timeout_duration, mount_id, "slew_to_coordinates").await
}

/// Camera exposure with timeout based on exposure duration
pub async fn exposure_with_timeout<T, F>(
    future: F,
    camera_id: &str,
    exposure_secs: f64,
) -> Result<T, NightshadeError>
where
    F: Future<Output = Result<T, NightshadeError>>,
{
    let timeout_duration = Timeouts::exposure_wait(exposure_secs);
    with_timeout(future, timeout_duration, camera_id, "exposure").await
}

/// Focuser move with timeout based on step distance
pub async fn focuser_move_with_timeout<F>(
    future: F,
    focuser_id: &str,
    target_position: i32,
    current_position: Option<i32>,
    max_position: i32,
) -> Result<(), NightshadeError>
where
    F: Future<Output = Result<(), NightshadeError>>,
{
    // Estimate move time based on distance
    let timeout_duration = if let Some(current) = current_position {
        let distance = (target_position - current).abs();
        let full_travel_time = 120.0; // 120s for full travel
                                      // Why (audit-rust §1.4): i32 → f64 widening, exact. The resulting
                                      // timeout is clamped to [30, 180] seconds via min/max below, so
                                      // any precision artifact is invisible.
        let estimated_secs =
            (f64::from(distance) / f64::from(max_position)) * full_travel_time + 10.0;
        Duration::from_secs_f64(estimated_secs.max(30.0).min(180.0))
    } else {
        Timeouts::focuser_move()
    };

    with_timeout(future, timeout_duration, focuser_id, "move").await
}

// =========================================================================
// Retry with Timeout
// =========================================================================

/// Configuration for retry operations
#[derive(Debug, Clone)]
pub struct RetryConfig {
    /// Maximum number of attempts (including first attempt)
    pub max_attempts: u32,
    /// Initial delay between retries
    pub initial_delay: Duration,
    /// Maximum delay between retries
    pub max_delay: Duration,
    /// Backoff multiplier
    pub backoff_multiplier: f64,
    /// Timeout per attempt
    pub timeout_per_attempt: Duration,
}

impl Default for RetryConfig {
    fn default() -> Self {
        Self {
            max_attempts: 3,
            initial_delay: Duration::from_secs(1),
            max_delay: Duration::from_secs(30),
            backoff_multiplier: 2.0,
            timeout_per_attempt: Duration::from_secs(10),
        }
    }
}

impl RetryConfig {
    /// Quick retry config for fast operations
    pub fn quick() -> Self {
        Self {
            max_attempts: 3,
            initial_delay: Duration::from_millis(100),
            max_delay: Duration::from_secs(1),
            backoff_multiplier: 2.0,
            timeout_per_attempt: Duration::from_secs(5),
        }
    }

    /// Patient retry config for slow operations
    pub fn patient() -> Self {
        Self {
            max_attempts: 5,
            initial_delay: Duration::from_secs(2),
            max_delay: Duration::from_secs(60),
            backoff_multiplier: 1.5,
            timeout_per_attempt: Duration::from_secs(60),
        }
    }
}

/// Execute an operation with retry and per-attempt timeout
pub async fn with_retry<T, F, Fut>(
    operation: F,
    config: RetryConfig,
    device_id: &str,
    operation_name: &str,
) -> Result<T, NightshadeError>
where
    F: Fn() -> Fut,
    Fut: Future<Output = Result<T, NightshadeError>>,
{
    let mut attempt = 0;
    let mut delay = config.initial_delay;

    loop {
        attempt += 1;

        let result = timeout(config.timeout_per_attempt, operation()).await;

        match result {
            Ok(Ok(value)) => return Ok(value),
            Ok(Err(e)) => {
                // Check if error is retryable
                if !e.is_retryable() {
                    return Err(e);
                }

                if attempt >= config.max_attempts {
                    tracing::warn!(
                        "Operation {} on {} failed after {} attempts: {:?}",
                        operation_name,
                        device_id,
                        attempt,
                        e
                    );
                    return Err(e);
                }

                tracing::debug!(
                    "Attempt {} of {} for {} on {} failed: {:?}. Retrying in {:?}",
                    attempt,
                    config.max_attempts,
                    operation_name,
                    device_id,
                    e,
                    delay
                );
            }
            Err(_elapsed) => {
                if attempt >= config.max_attempts {
                    return Err(NightshadeError::DeviceTimeout {
                        device_id: device_id.to_string(),
                        operation: operation_name.to_string(),
                        timeout_secs: config.timeout_per_attempt.as_secs_f64(),
                    });
                }

                tracing::debug!(
                    "Attempt {} of {} for {} on {} timed out. Retrying in {:?}",
                    attempt,
                    config.max_attempts,
                    operation_name,
                    device_id,
                    delay
                );
            }
        }

        // Wait before retry
        tokio::time::sleep(delay).await;

        // Increase delay for next attempt (with backoff)
        delay = Duration::from_secs_f64(
            (delay.as_secs_f64() * config.backoff_multiplier).min(config.max_delay.as_secs_f64()),
        );
    }
}

// =========================================================================
// Deadline-based Operations
// =========================================================================

/// A deadline that can be shared across multiple operations
#[derive(Debug, Clone)]
pub struct Deadline {
    expires_at: std::time::Instant,
}

impl Deadline {
    /// Create a new deadline from a duration
    pub fn from_duration(duration: Duration) -> Self {
        Self {
            expires_at: std::time::Instant::now() + duration,
        }
    }

    /// Create a new deadline from an absolute time
    pub fn from_instant(instant: std::time::Instant) -> Self {
        Self {
            expires_at: instant,
        }
    }

    /// Check if the deadline has expired
    pub fn is_expired(&self) -> bool {
        std::time::Instant::now() >= self.expires_at
    }

    /// Get the remaining time until deadline
    pub fn remaining(&self) -> Duration {
        self.expires_at
            .saturating_duration_since(std::time::Instant::now())
    }

    /// Execute a future with this deadline
    pub async fn execute<T, F>(&self, future: F) -> Result<T, NightshadeError>
    where
        F: Future<Output = Result<T, NightshadeError>>,
    {
        let remaining = self.remaining();
        if remaining.is_zero() {
            return Err(NightshadeError::Timeout(
                "Deadline already expired".to_string(),
            ));
        }

        timeout(remaining, future)
            .await
            .map_err(|_| NightshadeError::Timeout("Deadline exceeded".to_string()))?
    }
}

// =========================================================================
// Tests
// =========================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_timeout_success() {
        let result: Result<i32, NightshadeError> = with_timeout(
            async { Ok(42) },
            Duration::from_secs(1),
            "test_device",
            "test_op",
        )
        .await;

        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 42);
    }

    #[tokio::test]
    async fn test_timeout_expiry() {
        let result: Result<i32, NightshadeError> = with_timeout(
            async {
                tokio::time::sleep(Duration::from_secs(2)).await;
                Ok(42)
            },
            Duration::from_millis(100),
            "test_device",
            "test_op",
        )
        .await;

        assert!(result.is_err());
        match result.unwrap_err() {
            NightshadeError::DeviceTimeout {
                device_id,
                operation,
                ..
            } => {
                assert_eq!(device_id, "test_device");
                assert_eq!(operation, "test_op");
            }
            _ => panic!("Expected DeviceTimeout error"),
        }
    }

    #[test]
    fn test_deadline() {
        let deadline = Deadline::from_duration(Duration::from_secs(10));
        assert!(!deadline.is_expired());
        assert!(deadline.remaining() > Duration::from_secs(9));
    }
}
