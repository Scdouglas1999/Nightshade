//! Per-driver device dispatch modules.
//!
//! The `DeviceManager` defined in `crate::device_manager` keeps the public dispatcher
//! surface (top-level methods that match on `DriverType` and route per device
//! ID). Driver-specific helper methods that previously crowded `devices.rs`
//! live here, split across one module per driver, using Rust's split-impl-block
//! feature. The original monolithic `devices.rs` has been further decomposed
//! into the `crate::device_manager` module tree.
//!
//! Each module is `pub(crate)` and contributes additional methods to
//! `impl DeviceManager`. No new public surface is introduced — the goal is
//! purely to localize per-driver code paths so `devices.rs` can read as a
//! thin router.

pub(crate) mod error;
pub use error::DeviceOpError;

pub(crate) mod alpaca;
pub(crate) mod alpaca_device_common;
pub(crate) mod ascom;
// `ascom_device_common` only contains `DeviceCommonMetadata` trait impls for the
// typed ASCOM COM wrappers in `crate::ascom_wrapper`, which exist only on
// Windows. Gating the whole module keeps it off non-Windows targets where those
// wrapper types (and the underlying COM) don't exist.
#[cfg(windows)]
pub(crate) mod ascom_device_common;
pub(crate) mod device_common_metadata;
pub(crate) mod indi;
pub(crate) mod native;
