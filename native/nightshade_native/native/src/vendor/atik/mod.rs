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

#[cfg(test)]
mod colour_classification_tests {
    use super::*;

    /// ARTEMISCOLOURTYPE 0 is UNKNOWN — "either the device is not a camera or
    /// the colour cannot be determined" (AtikDefs.h:56) — and it is also the
    /// value `connect`'s out-parameter keeps when ArtemisColourProperties
    /// fails. It must never resolve to a sensor description: publishing mono
    /// for an undetermined sensor strips BAYERPAT from every frame of the
    /// session, so a one-shot-colour camera images all night undebayered.
    #[test]
    fn unknown_colour_type_is_not_a_sensor_description() {
        assert_eq!(atik_sensor_colour(ARTEMIS_COLOUR_UNKNOWN), None);
        // The seed the connect path initialises the out-parameter with is
        // exactly that value, so a swallowed SDK failure cannot masquerade as
        // an answer.
        assert_eq!(ARTEMIS_COLOUR_UNKNOWN, 0);
    }

    /// Monochrome is a value the SDK reports explicitly; only that value may
    /// publish a mono sensor.
    #[test]
    fn none_colour_type_is_mono_with_no_bayer_pattern() {
        let colour = atik_sensor_colour(ARTEMIS_COLOUR_NONE).expect("mono is determinate");
        assert_eq!(colour, AtikSensorColour::Mono);
        assert!(!colour.is_color());
        assert_eq!(colour.bayer_pattern(), None);
    }

    #[test]
    fn rggb_colour_type_publishes_the_rggb_bayer_pattern() {
        let colour = atik_sensor_colour(ARTEMIS_COLOUR_RGGB).expect("RGGB is determinate");
        assert_eq!(colour, AtikSensorColour::Rggb);
        assert!(colour.is_color());
        assert_eq!(colour.bayer_pattern(), Some(BayerPattern::Rggb));
    }

    /// A colour type a future SDK adds is as undetermined as UNKNOWN for this
    /// build: we know it is not the RGGB we can debayer, and we do not know it
    /// is mono either.
    #[test]
    fn unrecognised_colour_types_are_undetermined_not_mono() {
        for colour_type in [-1, 3, 4, 99] {
            assert_eq!(
                atik_sensor_colour(colour_type),
                None,
                "colour type {colour_type} was resolved to a sensor description"
            );
        }
    }
}
