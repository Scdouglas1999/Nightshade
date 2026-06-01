//! Structured error type for the internal device-dispatch + device-manager
//! ops layer.
//!
//! # Why this exists
//!
//! The FFI boundary (`crate::api::*`) is properly typed: every public function
//! returns `Result<_, NightshadeError>`. But the *internal* device plumbing in
//! `crate::dispatch::*` and `crate::device_manager::ops::*` historically leaned
//! on `Result<_, String>`. A bare `String` flattens the structured context that
//! callers need for programmatic recovery — *which* device failed, *what
//! category* of failure it was (not-connected vs. invalid-parameter vs.
//! timeout vs. unsupported), and whether retrying could plausibly help.
//!
//! `DeviceOpError` restores that structure *behind* the FFI edge. It is mapped
//! to `NightshadeError` at the `api/` layer via `From<DeviceOpError>`, so the
//! FFI surface and the messages Dart sees are **unchanged** — this is a
//! behavior-preserving refactor. The win is purely internal: the dispatch and
//! ops layers now classify their failures instead of stringly-typing them.
//!
//! # Behavior preservation
//!
//! Today the `api/` layer wraps every ops error as
//! `NightshadeError::OperationFailed(string)`. To preserve that exactly:
//!
//! * Every `DeviceOpError` variant's `Display` reproduces the *exact* string
//!   the corresponding `format!`/`.to_string()` produced before this refactor.
//! * `From<DeviceOpError> for NightshadeError` maps to
//!   `NightshadeError::OperationFailed(self.to_string())` — byte-for-byte the
//!   same `NightshadeError` value the api layer used to construct.
//!
//! Both directions of `String` conversion are provided so that sub-helpers
//! which still return `Result<_, String>` (the Alpaca trait methods, the
//! `sim_gate` connection gates, INDI client errors) keep flowing through `?`
//! unchanged: `From<String>` lands in [`DeviceOpError::Message`], and
//! `From<DeviceOpError> for String` lets any remaining `String`-typed caller
//! compile.

use crate::error::NightshadeError;
use thiserror::Error;

/// Structured failure for an internal device operation (dispatch + ops layer).
///
/// Each variant carries enough context to classify the failure programmatically
/// without re-parsing a message string:
/// * the device id, where one is in scope;
/// * an optional underlying source message / vendor code;
/// * a category that [`DeviceOpError::is_retryable`] keys off.
///
/// `Display` is contractually identical to the legacy `format!` strings so the
/// message that reaches Dart (via `NightshadeError::OperationFailed`) does not
/// change.
#[derive(Error, Debug, Clone)]
pub enum DeviceOpError {
    /// The device id was not present in the manager's device map.
    ///
    /// Legacy string: `"Device not found: {id}"`.
    #[error("Device not found: {0}")]
    DeviceNotFound(String),

    /// A driver-specific handle for the device was not connected. `detail` is
    /// the exact legacy phrasing (it varies per driver, e.g.
    /// `"ASCOM mount not connected"`, `"Alpaca mount {id} not connected"`,
    /// `"INDI client not connected for {key}"`), so `Display` just renders it.
    #[error("{detail}")]
    NotConnected {
        /// Device id when known (the simulator/driver-bare messages omit it).
        device_id: Option<String>,
        /// The exact not-connected message for this driver arm.
        detail: String,
    },

    /// A device id failed to parse / was malformed for its driver.
    ///
    /// Legacy strings: `"Invalid INDI device ID format: {id}"`,
    /// `"Invalid INDI device ID"`, `"Invalid port number"`, etc. — preserved
    /// verbatim in `detail`.
    #[error("{detail}")]
    InvalidDeviceId { detail: String },

    /// A caller-supplied parameter was invalid or out of range.
    ///
    /// Legacy strings: `"Invalid direction: {dir}"`,
    /// `"Switch index {i} out of range ..."`, etc.
    #[error("{detail}")]
    InvalidParameter { detail: String },

    /// The operation is not supported by this device / driver.
    ///
    /// Legacy strings: `"Alt/Az slew is not supported for native serial mounts"`,
    /// `"Find home is not supported for native serial mounts"`, the simulator
    /// "devices are disabled" message, etc.
    #[error("{detail}")]
    Unsupported { detail: String },

    /// A hardware / SDK / protocol call failed. `detail` carries the full
    /// legacy message (which frequently embeds the device id and the
    /// underlying driver error), so `Display` renders it verbatim.
    #[error("{detail}")]
    Hardware {
        /// Device id when the legacy message scoped the failure to one.
        device_id: Option<String>,
        /// Full legacy failure message (often `"Failed to … {id}: {source}"`).
        detail: String,
    },

    /// One-off message that does not fit a category. Used for sub-helper
    /// errors that arrive as a bare `String` (Alpaca trait results, INDI
    /// client errors, sim-gate gates) where re-classifying would risk
    /// changing the user-visible wording.
    #[error("{0}")]
    Message(String),
}

impl DeviceOpError {
    /// `"Device not found: {id}"` — the canonical lookup-miss error.
    pub(crate) fn device_not_found(device_id: impl Into<String>) -> Self {
        DeviceOpError::DeviceNotFound(device_id.into())
    }

    /// Driver handle absent. `detail` is the exact legacy phrasing for the arm.
    pub(crate) fn not_connected(
        device_id: Option<String>,
        detail: impl Into<String>,
    ) -> Self {
        DeviceOpError::NotConnected {
            device_id,
            detail: detail.into(),
        }
    }

    /// Malformed / unparseable device id.
    pub(crate) fn invalid_device_id(detail: impl Into<String>) -> Self {
        DeviceOpError::InvalidDeviceId {
            detail: detail.into(),
        }
    }

    /// Invalid caller parameter.
    pub(crate) fn invalid_parameter(detail: impl Into<String>) -> Self {
        DeviceOpError::InvalidParameter {
            detail: detail.into(),
        }
    }

    /// Operation unsupported on this device / driver.
    pub(crate) fn unsupported(detail: impl Into<String>) -> Self {
        DeviceOpError::Unsupported {
            detail: detail.into(),
        }
    }

    /// Hardware / SDK / protocol failure carrying the full legacy message.
    pub(crate) fn hardware(device_id: Option<String>, detail: impl Into<String>) -> Self {
        DeviceOpError::Hardware {
            device_id,
            detail: detail.into(),
        }
    }

    /// Classify a bare driver/SDK error string (the common
    /// `.map_err(|e| e.to_string())` site) as a [`DeviceOpError::Hardware`]
    /// without a device id. The id is frequently already embedded in the
    /// driver's own message, and these sites previously discarded it entirely
    /// (they produced a bare `String`), so attaching `None` preserves the
    /// exact wording while still marking the failure category as hardware
    /// (and therefore retryable) for programmatic recovery.
    pub(crate) fn driver(detail: impl std::fmt::Display) -> Self {
        DeviceOpError::Hardware {
            device_id: None,
            detail: detail.to_string(),
        }
    }

    /// The device id this failure is scoped to, when known. Lets callers do
    /// programmatic recovery (reconnect *this* device) without parsing strings.
    ///
    /// Part of the structured-recovery API this refactor exists to enable.
    /// Not yet consumed by a caller (the FFI edge currently maps straight to
    /// `NightshadeError::OperationFailed`), but kept as the typed accessor so
    /// follow-up retry/reconnect logic does not have to re-parse messages.
    #[allow(dead_code)]
    pub(crate) fn device_id(&self) -> Option<&str> {
        match self {
            DeviceOpError::DeviceNotFound(id) => Some(id),
            DeviceOpError::NotConnected { device_id, .. }
            | DeviceOpError::Hardware { device_id, .. } => device_id.as_deref(),
            DeviceOpError::InvalidDeviceId { .. }
            | DeviceOpError::InvalidParameter { .. }
            | DeviceOpError::Unsupported { .. }
            | DeviceOpError::Message(_) => None,
        }
    }

    /// Whether retrying the same operation could plausibly succeed.
    ///
    /// Mirrors `NightshadeError::is_recoverable`'s philosophy: not-connected
    /// and hardware/communication failures may be transient (the device can be
    /// reconnected or the SDK call re-issued), whereas invalid parameters,
    /// unsupported operations, and malformed ids will fail identically on
    /// retry. A device-not-found is treated as non-retryable (the caller must
    /// reconnect/rediscover, not blindly retry the op).
    ///
    /// Part of the structured-recovery API this refactor exists to enable; see
    /// [`DeviceOpError::device_id`] for why it is not yet wired to a caller.
    #[allow(dead_code)]
    pub(crate) fn is_retryable(&self) -> bool {
        matches!(
            self,
            DeviceOpError::NotConnected { .. } | DeviceOpError::Hardware { .. }
        )
    }
}

/// Bare strings from sub-helpers (Alpaca trait methods, INDI client errors,
/// the `sim_gate` connection gates) land here so `?` keeps working without
/// reclassifying — and without changing their wording.
impl From<String> for DeviceOpError {
    fn from(s: String) -> Self {
        DeviceOpError::Message(s)
    }
}

impl From<&str> for DeviceOpError {
    fn from(s: &str) -> Self {
        DeviceOpError::Message(s.to_string())
    }
}

/// INDI protocol errors propagated via bare `?` from `IndiClient` calls.
///
/// The legacy code path returned `Result<_, String>` and relied on
/// `From<IndiError> for String` (the INDI crate's own conversion) when a
/// `?`-propagated `IndiError` crossed into a `String`-typed function. To keep
/// those `?` sites compiling — and the surfaced message byte-identical — we
/// reproduce that exact string (`e.to_string()`) but classify it as a
/// [`DeviceOpError::Hardware`] (INDI failures are protocol/comm failures, i.e.
/// retryable). The device id is not in scope at the trait-error boundary, so
/// it is left `None`; the INDI message already names the property that failed.
impl From<nightshade_indi::IndiError> for DeviceOpError {
    fn from(e: nightshade_indi::IndiError) -> Self {
        DeviceOpError::Hardware {
            device_id: None,
            detail: e.to_string(),
        }
    }
}

/// FFI edge mapping. The api layer historically wrapped every ops error as
/// `NightshadeError::OperationFailed(string)`; reproducing that exactly (via
/// `Display`) keeps the error that reaches Dart byte-for-byte identical.
impl From<DeviceOpError> for NightshadeError {
    fn from(e: DeviceOpError) -> Self {
        NightshadeError::OperationFailed(e.to_string())
    }
}

/// Keep any remaining `Result<_, String>` caller compiling while the migration
/// is partial: a `DeviceOpError` renders to the same string it always did.
impl From<DeviceOpError> for String {
    fn from(e: DeviceOpError) -> Self {
        e.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_matches_legacy_strings() {
        assert_eq!(
            DeviceOpError::device_not_found("ascom:Foo").to_string(),
            "Device not found: ascom:Foo"
        );
        assert_eq!(
            DeviceOpError::not_connected(None, "ASCOM mount not connected").to_string(),
            "ASCOM mount not connected"
        );
        assert_eq!(
            DeviceOpError::invalid_parameter("Invalid direction: up").to_string(),
            "Invalid direction: up"
        );
    }

    #[test]
    fn ffi_mapping_preserves_operation_failed_string() {
        let err = DeviceOpError::hardware(
            Some("alpaca:host:0:1".to_string()),
            "Failed to park Alpaca mount: boom",
        );
        let mapped: NightshadeError = err.into();
        match mapped {
            NightshadeError::OperationFailed(s) => {
                assert_eq!(s, "Failed to park Alpaca mount: boom");
            }
            other => panic!("expected OperationFailed, got {other:?}"),
        }
    }

    #[test]
    fn string_roundtrips_through_message_variant() {
        let from_helper: DeviceOpError = "boom from sub-helper".to_string().into();
        assert_eq!(from_helper.to_string(), "boom from sub-helper");
        let back: String = from_helper.into();
        assert_eq!(back, "boom from sub-helper");
    }

    #[test]
    fn retryable_classification() {
        assert!(DeviceOpError::not_connected(None, "x not connected").is_retryable());
        assert!(DeviceOpError::hardware(None, "sdk boom").is_retryable());
        assert!(!DeviceOpError::invalid_parameter("bad").is_retryable());
        assert!(!DeviceOpError::unsupported("nope").is_retryable());
        assert!(!DeviceOpError::device_not_found("x").is_retryable());
    }

    #[test]
    fn device_id_extraction() {
        assert_eq!(
            DeviceOpError::device_not_found("d1").device_id(),
            Some("d1")
        );
        assert_eq!(
            DeviceOpError::hardware(Some("d2".to_string()), "boom").device_id(),
            Some("d2")
        );
        assert_eq!(DeviceOpError::invalid_parameter("bad").device_id(), None);
    }
}
