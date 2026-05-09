//! Vendor Quirks Database
//!
//! This module provides a centralized database of known device and vendor quirks,
//! along with workarounds that should be applied automatically.
//!
//! ## Overview
//!
//! Many astronomy devices have known bugs or require workarounds due to:
//! - SDK bugs that report incorrect values
//! - Firmware issues that require specific timing
//! - Hardware variations that need special handling
//! - Discovery race conditions that can cause crashes
//!
//! Rather than scattering workarounds throughout the codebase, this module
//! provides a centralized registry that can be queried before/after operations.
//!
//! ## Usage
//!
//! ```rust,ignore
//! use nightshade_native::quirks::{get_quirks_for_device, Quirk};
//!
//! let quirks = get_quirks_for_device("native:zwo:ASI294MC");
//! for quirk in &quirks {
//!     match quirk {
//!         Quirk::Temperature(TemperatureQuirk::ScaleFactor(factor)) => {
//!             // Apply temperature scaling
//!             raw_temp = raw_temp / factor;
//!         }
//!         _ => {}
//!     }
//! }
//! ```

mod database;
mod types;

pub use database::*;
pub use types::*;

use crate::NativeVendor;
use std::collections::HashMap;
use std::sync::{Arc, RwLock};

/// Global quirk registry with runtime overrides
static QUIRK_REGISTRY: std::sync::OnceLock<Arc<RwLock<QuirkRegistry>>> = std::sync::OnceLock::new();

/// Initialize or get the global quirk registry
fn get_registry() -> &'static Arc<RwLock<QuirkRegistry>> {
    QUIRK_REGISTRY.get_or_init(|| Arc::new(RwLock::new(QuirkRegistry::new())))
}

/// Registry that combines built-in quirks with runtime overrides
pub struct QuirkRegistry {
    /// Runtime overrides that take precedence over built-in quirks
    overrides: HashMap<String, Vec<Quirk>>,
    /// Devices for which quirks should be disabled (for testing)
    disabled_devices: std::collections::HashSet<String>,
}

impl QuirkRegistry {
    fn new() -> Self {
        Self {
            overrides: HashMap::new(),
            disabled_devices: std::collections::HashSet::new(),
        }
    }
}

/// Get all quirks that apply to a specific device.
///
/// This function checks:
/// 1. Runtime overrides (highest priority)
/// 2. Device-specific quirks (by full device ID)
/// 3. Model-specific quirks (by model name pattern)
/// 4. Vendor-wide quirks (by vendor)
///
/// # Arguments
/// * `device_id` - The device identifier (e.g., "native:zwo:ASI294MC Pro")
///
/// # Returns
/// A vector of quirks that should be applied to this device
pub fn get_quirks_for_device(device_id: &str) -> Vec<Quirk> {
    let registry = get_registry().read().unwrap_or_else(|e| e.into_inner());

    // Check if quirks are disabled for this device
    if registry.disabled_devices.contains(device_id) {
        tracing::debug!("Quirks disabled for device: {}", device_id);
        return Vec::new();
    }

    // Check for runtime overrides first
    if let Some(overrides) = registry.overrides.get(device_id) {
        tracing::debug!(
            "Using {} runtime override quirks for device: {}",
            overrides.len(),
            device_id
        );
        return overrides.clone();
    }

    drop(registry); // Release the lock before calling the database

    // Get quirks from the built-in database
    database::get_device_quirks(device_id)
}

/// Get all quirks that apply to a vendor.
///
/// These are vendor-wide quirks that apply to all devices from that vendor.
///
/// # Arguments
/// * `vendor` - The vendor enum
///
/// # Returns
/// A vector of quirks that should be applied to all devices from this vendor
pub fn get_quirks_for_vendor(vendor: &NativeVendor) -> Vec<Quirk> {
    database::get_vendor_quirks(vendor)
}

/// Set runtime quirk overrides for a device.
///
/// This allows testing different quirk configurations without code changes.
/// Overrides take precedence over built-in quirks.
///
/// # Arguments
/// * `device_id` - The device identifier
/// * `quirks` - The quirks to apply (replaces any existing overrides)
pub fn set_quirk_overrides(device_id: &str, quirks: Vec<Quirk>) {
    let mut registry = get_registry().write().unwrap_or_else(|e| e.into_inner());
    tracing::info!(
        "Setting {} quirk overrides for device: {}",
        quirks.len(),
        device_id
    );
    registry.overrides.insert(device_id.to_string(), quirks);
}

/// Clear runtime quirk overrides for a device.
///
/// After clearing, the device will use the built-in quirks again.
pub fn clear_quirk_overrides(device_id: &str) {
    let mut registry = get_registry().write().unwrap_or_else(|e| e.into_inner());
    tracing::info!("Clearing quirk overrides for device: {}", device_id);
    registry.overrides.remove(device_id);
}

/// Disable all quirks for a device.
///
/// This is useful for testing to ensure quirks are actually being applied.
pub fn disable_quirks_for_device(device_id: &str) {
    let mut registry = get_registry().write().unwrap_or_else(|e| e.into_inner());
    tracing::info!("Disabling all quirks for device: {}", device_id);
    registry.disabled_devices.insert(device_id.to_string());
}

/// Re-enable quirks for a device after they were disabled.
pub fn enable_quirks_for_device(device_id: &str) {
    let mut registry = get_registry().write().unwrap_or_else(|e| e.into_inner());
    tracing::info!("Re-enabling quirks for device: {}", device_id);
    registry.disabled_devices.remove(device_id);
}

/// Apply temperature quirks to a raw temperature reading.
///
/// This is a convenience function that applies all relevant temperature quirks.
///
/// # Arguments
/// * `device_id` - The device identifier
/// * `raw_temp` - The raw temperature value from the SDK
///
/// # Returns
/// The corrected temperature value
pub fn apply_temperature_quirks(device_id: &str, raw_temp: f64) -> f64 {
    let quirks = get_quirks_for_device(device_id);
    let mut temp = raw_temp;

    for quirk in quirks {
        if let Quirk::Temperature(temp_quirk) = quirk {
            match temp_quirk {
                TemperatureQuirk::ScaleFactor(factor) => {
                    let old_temp = temp;
                    temp /= factor;
                    tracing::trace!(
                        "Applied temperature scale factor {} to {}: {} -> {}",
                        factor,
                        device_id,
                        old_temp,
                        temp
                    );
                }
                TemperatureQuirk::Offset(offset) => {
                    let old_temp = temp;
                    temp += offset;
                    tracing::trace!(
                        "Applied temperature offset {} to {}: {} -> {}",
                        offset,
                        device_id,
                        old_temp,
                        temp
                    );
                }
                TemperatureQuirk::Inverted => {
                    let old_temp = temp;
                    temp = -temp;
                    tracing::trace!(
                        "Applied temperature inversion to {}: {} -> {}",
                        device_id,
                        old_temp,
                        temp
                    );
                }
                TemperatureQuirk::SkipFirstRead => {
                    // This quirk is handled at the caller level
                    tracing::trace!(
                        "Temperature SkipFirstRead quirk noted for {} (handled by caller)",
                        device_id
                    );
                }
                TemperatureQuirk::RequiresDelayMs(delay_ms) => {
                    // This quirk is handled at the caller level
                    tracing::trace!(
                        "Temperature requires {}ms delay for {} (handled by caller)",
                        delay_ms,
                        device_id
                    );
                }
            }
        }
    }

    temp
}

/// Check if a device has a specific timing quirk.
///
/// # Arguments
/// * `device_id` - The device identifier
/// * `operation` - The operation to check for timing requirements
///
/// # Returns
/// Optional delay in milliseconds that should be applied after the operation
pub fn get_timing_delay(device_id: &str, operation: &str) -> Option<u64> {
    let quirks = get_quirks_for_device(device_id);

    for quirk in quirks {
        if let Quirk::Timing(timing_quirk) = quirk {
            match &timing_quirk {
                TimingQuirk::DelayAfterOperation {
                    operation_name,
                    delay_ms,
                } => {
                    if operation_name == operation {
                        return Some(*delay_ms);
                    }
                }
                TimingQuirk::DelayAfterConnect(delay_ms) if operation == "connect" => {
                    return Some(*delay_ms);
                }
                TimingQuirk::DelayAfterDisconnect(delay_ms) if operation == "disconnect" => {
                    return Some(*delay_ms);
                }
                TimingQuirk::DelayBetweenCommands(delay_ms) if operation == "command" => {
                    return Some(*delay_ms);
                }
                _ => {}
            }
        }
    }

    None
}

/// Check if discovery should skip certain operations for a vendor.
///
/// Some SDKs can crash during discovery if certain operations are performed.
///
/// # Arguments
/// * `vendor` - The vendor to check
///
/// # Returns
/// List of operations that should be skipped during discovery
pub fn get_discovery_skip_operations(vendor: &NativeVendor) -> Vec<String> {
    let quirks = get_quirks_for_vendor(vendor);
    let mut skip_ops = Vec::new();

    for quirk in quirks {
        if let Quirk::Discovery(discovery_quirk) = quirk {
            match discovery_quirk {
                DiscoveryQuirk::SkipOperation(op) => {
                    skip_ops.push(op);
                }
                DiscoveryQuirk::SkipOperations(ops) => {
                    skip_ops.extend(ops);
                }
                _ => {}
            }
        }
    }

    skip_ops
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_zwo_quirks() {
        let quirks = get_quirks_for_device("native:zwo:ASI294MC Pro");
        assert!(!quirks.is_empty(), "ZWO cameras should have quirks");

        // Check for temperature scale factor
        let has_temp_scale = quirks
            .iter()
            .any(|q| matches!(q, Quirk::Temperature(TemperatureQuirk::ScaleFactor(10.0))));
        assert!(has_temp_scale, "ZWO should have temperature scale factor");
    }

    #[test]
    fn test_get_qhy_quirks() {
        let quirks = get_quirks_for_vendor(&NativeVendor::Qhy);
        assert!(!quirks.is_empty(), "QHY should have vendor quirks");

        // Check for discovery protection
        let has_discovery_protection = quirks.iter().any(|q| matches!(q, Quirk::Discovery(_)));
        assert!(
            has_discovery_protection,
            "QHY should have discovery protection"
        );
    }

    #[test]
    fn test_apply_temperature_quirks() {
        // ZWO cameras report temperature * 10
        let raw_temp = 200.0; // Actually 20.0 degrees
        let corrected = apply_temperature_quirks("native:zwo:ASI294MC Pro", raw_temp);
        assert!(
            (corrected - 20.0).abs() < 0.01,
            "Temperature should be scaled: got {}",
            corrected
        );
    }

    #[test]
    fn test_quirk_overrides() {
        let device_id = "test:device:1";

        // Initially should have no quirks
        let quirks = get_quirks_for_device(device_id);
        assert!(quirks.is_empty());

        // Set override
        set_quirk_overrides(
            device_id,
            vec![Quirk::Temperature(TemperatureQuirk::ScaleFactor(5.0))],
        );

        let quirks = get_quirks_for_device(device_id);
        assert_eq!(quirks.len(), 1);

        // Clear override
        clear_quirk_overrides(device_id);
        let quirks = get_quirks_for_device(device_id);
        assert!(quirks.is_empty());
    }

    #[test]
    fn test_disable_quirks() {
        // Use a different device ID to avoid conflicts with parallel tests
        let device_id = "native:zwo:ASI6200MM";

        // Should have quirks by default (ZWO vendor-wide quirks)
        let quirks = get_quirks_for_device(device_id);
        assert!(!quirks.is_empty(), "ZWO device should have vendor quirks");

        // Disable quirks
        disable_quirks_for_device(device_id);
        let quirks = get_quirks_for_device(device_id);
        assert!(quirks.is_empty(), "Quirks should be disabled");

        // Re-enable
        enable_quirks_for_device(device_id);
        let quirks = get_quirks_for_device(device_id);
        assert!(!quirks.is_empty(), "Quirks should be re-enabled");
    }
}
