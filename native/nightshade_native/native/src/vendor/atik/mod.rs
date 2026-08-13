//! Atik Camera SDK Bindings
//!
//! Native driver for Atik cameras using their official Artemis SDK.
//! Supports Atik Horizon, ACIS, APX, and older series cameras.

use crate::camera::{
    BayerPattern, CameraCapabilities, CameraState, CameraStatus, ExposureParams, ImageData,
    ImageMetadata, ReadoutMode, SensorInfo, SubFrame, VendorFeatures,
};
use crate::sync::atik_mutex;
use crate::traits::{NativeCamera, NativeDevice, NativeError, NativeFilterWheel};
use crate::NativeVendor;
use async_trait::async_trait;
use std::collections::HashMap;
use std::ffi::{c_char, c_float, c_int, c_void, CStr};
use std::sync::{Mutex, OnceLock};

mod camera;
mod camera_ops;
mod discovery;
mod ffi;
mod filter_wheel;
mod sdk;

pub use camera::*;
pub use discovery::*;
use ffi::*;
pub use filter_wheel::*;
use sdk::*;

#[cfg(test)]
mod sdk_loader_tests {
    use super::*;

    #[test]
    fn efw_entry_points_stay_optional() {
        // Every Atik SDK build older than the EFW API exports none of these.
        // Promoting one to the required table would make such a build fail to
        // load entirely, so no Atik camera would be visible either.
        let required = AtikSdk::required_symbol_names();
        assert!(
            !required.iter().any(|name| name.starts_with("efw_")),
            "an EFW entry point became mandatory: {:?}",
            required
        );
        assert!(!required.contains(&"refresh_devices_count"));
        assert!(required.contains(&"device_count"));
        assert_eq!(required.len(), 28);
    }
}
