//! What Nightshade is allowed to write when it commands an ASCOM cooler.
//!
//! Not gated behind `cfg(windows)`: this is pure policy over two booleans and
//! an `Option`, so it stays testable on the Linux workstation where the COM
//! plumbing cannot even compile. The Windows STA worker
//! (`bridge/src/ascom_wrapper/camera.rs`) is the only production caller.
//!
//! # Why this exists
//!
//! ICameraV3 splits cooling into two properties: `CoolerOn` (a bool) and
//! `SetCCDTemperature` (the setpoint, optional — a driver may reject it and
//! advertises that through `CanSetCCDTemperature`). Nightshade used to write
//! both on every cooler command, with a fabricated -10 C substituted whenever
//! the caller named no setpoint.
//!
//! On the reference rig (2026-08-09) that combination bricked end-of-night
//! warm-up. `POST /api/camera/cooling {"enabled":false}` carries no setpoint,
//! so the -10 was invented, and on a ZWO ASI178MM — `CanSetCCDTemperature =
//! False` — the `SetCCDTemperature` write threw:
//!
//! ```text
//! Failed to set ASCOM camera ascom:ASCOM.ASICamera2.Camera cooler
//! (enabled=false, target=-10C): SDK error: Failed to set cooler:
//! Failed to set property SetCCDTemperature...
//! ```
//!
//! Because the setpoint was written *before* `CoolerOn`, the throw meant
//! `CoolerOn = false` was never attempted: the cooler could not be switched
//! off at all. Two rules fall out, and this module is where they live:
//!
//! 1. **Off needs no setpoint.** Turning a TEC off is a `CoolerOn = false`
//!    write and nothing else.
//! 2. **Never write a property the driver says it does not have.** A camera
//!    reporting `CanSetCCDTemperature = False` must not be sent one.

/// Decide the setpoint (if any) to write to `SetCCDTemperature` before
/// toggling `CoolerOn`.
///
/// * `enabled` — the cooler state being commanded.
/// * `requested` — the setpoint the caller asked for, or `None` when the
///   caller named none. `None` is never turned into a number here; the
///   driver keeps whatever setpoint it already holds.
/// * `can_set_ccd_temperature` — the driver's own `CanSetCCDTemperature`
///   answer, or `None` when that probe itself failed. A failed probe is
///   treated as "do not write": a capability read that errors is not
///   evidence the property exists, and the alternative (write anyway) is the
///   exact call that took the cooler-off path down.
///
/// Returns `Some(setpoint)` only when writing `SetCCDTemperature` is both
/// wanted and permitted.
pub fn setpoint_to_write(
    enabled: bool,
    requested: Option<f64>,
    can_set_ccd_temperature: Option<bool>,
) -> Option<f64> {
    if !enabled {
        return None;
    }
    let target = requested?;
    match can_set_ccd_temperature {
        Some(true) => Some(target),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::setpoint_to_write;

    /// The live defect: a cooler-OFF command carries no setpoint, and the
    /// layer above used to substitute -10 C. Nothing may be written.
    #[test]
    fn disabling_never_writes_a_setpoint() {
        assert_eq!(setpoint_to_write(false, None, Some(true)), None);
        // Even when a caller does name one, switching off does not need it —
        // and on the rig this write is what threw.
        assert_eq!(setpoint_to_write(false, Some(-10.0), Some(true)), None);
        assert_eq!(setpoint_to_write(false, Some(-10.0), Some(false)), None);
        assert_eq!(setpoint_to_write(false, Some(-10.0), None), None);
    }

    /// A camera that answers `CanSetCCDTemperature = False` (the ASI178MM on
    /// the reference rig) must never be sent the property.
    #[test]
    fn a_camera_without_set_temperature_is_never_written_to() {
        assert_eq!(setpoint_to_write(true, Some(-10.0), Some(false)), None);
    }

    /// A capability probe that itself errored is not evidence the property
    /// exists; writing anyway is what broke the rig.
    #[test]
    fn an_unreadable_capability_is_treated_as_unsupported() {
        assert_eq!(setpoint_to_write(true, Some(-10.0), None), None);
    }

    /// No setpoint named while enabling: keep the driver's own setpoint
    /// rather than inventing one.
    #[test]
    fn enabling_without_a_named_setpoint_writes_nothing() {
        assert_eq!(setpoint_to_write(true, None, Some(true)), None);
    }

    /// The one case that does write: enabling, with a setpoint, on a camera
    /// that accepts one.
    #[test]
    fn enabling_with_a_setpoint_on_a_capable_camera_writes_it() {
        assert_eq!(
            setpoint_to_write(true, Some(-15.0), Some(true)),
            Some(-15.0)
        );
    }
}
