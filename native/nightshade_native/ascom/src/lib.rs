//! ASCOM COM Interface (Windows Only)
//!
//! Provides real access to ASCOM devices via COM on Windows.
//! This module enables Nightshade to connect to actual astronomical
//! equipment through the ASCOM standard.

#[cfg(windows)]
mod windows_impl;

/// ASCOM device information discovered from Windows Registry
#[derive(Debug, Clone)]
pub struct AscomDevice {
    /// The COM ProgID used to instantiate the driver
    pub prog_id: String,
    /// Human-readable name
    pub name: String,
    /// Description from ASCOM profile
    pub description: String,
}

/// ASCOM device types as defined by ASCOM standard
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AscomDeviceType {
    Camera,
    Telescope,
    Focuser,
    FilterWheel,
    Rotator,
    Dome,
    SafetyMonitor,
    ObservingConditions,
    Switch,
    CoverCalibrator,
}

impl AscomDeviceType {
    /// Get the registry key name for this device type
    pub fn registry_name(&self) -> &'static str {
        match self {
            AscomDeviceType::Camera => "Camera",
            AscomDeviceType::Telescope => "Telescope",
            AscomDeviceType::Focuser => "Focuser",
            AscomDeviceType::FilterWheel => "FilterWheel",
            AscomDeviceType::Rotator => "Rotator",
            AscomDeviceType::Dome => "Dome",
            AscomDeviceType::SafetyMonitor => "SafetyMonitor",
            AscomDeviceType::ObservingConditions => "ObservingConditions",
            AscomDeviceType::Switch => "Switch",
            AscomDeviceType::CoverCalibrator => "CoverCalibrator",
        }
    }
}

/// Discover ASCOM devices of a specific type
/// Returns a list of available drivers registered in the Windows Registry
#[cfg(windows)]
pub fn discover_devices(device_type: AscomDeviceType) -> Vec<AscomDevice> {
    windows_impl::discover_devices(device_type.registry_name())
}

/// Discover ASCOM devices (non-Windows stub)
#[cfg(not(windows))]
pub fn discover_devices(_device_type: AscomDeviceType) -> Vec<AscomDevice> {
    Vec::new()
}

/// Check if ASCOM is available on this platform
pub fn is_available() -> bool {
    cfg!(windows)
}

// Re-export Windows-specific types when on Windows
#[cfg(windows)]
pub use windows_impl::{
    get_timeout_config,
    // COM initialization
    init_com,
    // Device discovery
    probe_device_name,
    set_timeout_config,
    uninit_com,
    // Device types
    AscomCamera,
    AscomCleanupGuard,
    AscomCoverCalibrator,
    // Device connection wrapper
    AscomDeviceConnection,
    AscomDisconnectable,
    AscomDome,
    // Error types
    AscomError,
    AscomFilterWheel,
    AscomFocuser,
    AscomMount,
    AscomObservingConditions,
    // RAII guards for resource cleanup
    AscomOperationGuard,
    AscomResult,
    AscomRotator,
    AscomSafetyMonitor,
    AscomSwitch,
    CameraExposureSettings,
    CameraFullStatus,
    CameraSensorConfig,
    // Batch status types - Camera
    CameraThermalStatus,
    // Health monitoring
    ConnectionHealth,
    // Batch status types - Cover Calibrator
    CoverCalibratorFullStatus,
    // Batch status types - Dome
    DomeFullStatus,
    // Batch status types - Filter Wheel
    FilterWheelFullStatus,
    // Batch status types - Focuser
    FocuserCapabilities,
    FocuserFullStatus,
    HealthMonitor,
    MountCapabilities,
    MountFullStatus,
    MountGuideRates,
    MountMotionStatus,
    // Batch status types - Mount
    MountPositionStatus,
    ObservingConditionsFullStatus,
    // Batch status types - Rotator
    RotatorFullStatus,
    // Batch status types - Safety Monitor
    SafetyMonitorFullStatus,
    SkyStatus,
    // Batch status types - Switch
    SwitchFullStatus,
    // Configuration types
    TimeoutConfig,
    // Batch status types - Observing Conditions
    WeatherStatus,
    WindStatus,
};
