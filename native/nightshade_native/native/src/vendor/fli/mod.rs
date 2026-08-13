//! Finger Lakes Instrumentation (FLI) SDK Bindings
//!
//! Native driver for FLI cameras, focusers, and filter wheels using libfli.
//! This is an open-source library with cross-platform support.

use crate::camera::{
    CameraCapabilities, CameraState, CameraStatus, ExposureParams, ImageData, ImageMetadata,
    ReadoutMode, SensorInfo, SubFrame, VendorFeatures,
};
use crate::sync::fli_mutex;
use crate::traits::{NativeCamera, NativeDevice, NativeError, NativeFilterWheel, NativeFocuser};
use crate::NativeVendor;
use async_trait::async_trait;
use std::ffi::{c_char, c_double, c_long, CStr, CString};

mod camera;
mod camera_ops;
mod discovery;
mod ffi;
mod filter_wheel;
mod focuser;
mod sdk;

pub use camera::*;
pub use discovery::*;
use ffi::*;
pub use filter_wheel::*;
pub use focuser::*;
use sdk::*;

#[cfg(test)]
mod camera_tests {
    use super::*;

    #[tokio::test]
    async fn fli_gain_and_offset_writes_report_not_supported() {
        let mut camera = FliCamera::new("test".to_string());

        assert!(matches!(
            camera.set_gain(10).await,
            Err(NativeError::NotSupported)
        ));
        assert!(matches!(
            camera.set_offset(20).await,
            Err(NativeError::NotSupported)
        ));
    }
}
