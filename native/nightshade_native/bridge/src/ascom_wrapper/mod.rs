//! ASCOM STA-thread wrappers grouped by device class.
//!
//! Each submodule wraps one ICamera/IMount/etc. interface with the
//! single-threaded apartment marshalling required for Win32 COM. See
//! the per-file module-level docs for the as-cast / unwrap_or policy
//! that applies to that interface.

pub mod camera;
pub mod covercalibrator;
pub mod dome;
pub mod filterwheel;
pub mod focuser;
pub mod mount;
pub mod rotator;
pub mod safetymonitor;
pub mod switch;
pub mod weather;
