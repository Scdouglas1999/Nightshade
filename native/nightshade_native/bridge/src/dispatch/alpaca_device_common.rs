//! Shared "ASCOM-Common" metadata trait for typed Alpaca device wrappers.
//!
//! Every Alpaca device — irrespective of role (camera, mount, focuser, etc.) —
//! exposes the same four identification properties:
//!
//! | Method                 | Alpaca endpoint    | Returns               |
//! |------------------------|--------------------|-----------------------|
//! | `interface_version()`  | `interfaceversion` | `i32` (ASCOM Vn)      |
//! | `driver_version()`     | `driverversion`    | `String` (vendor str) |
//! | `driver_info()`        | `driverinfo`       | `String` (vendor str) |
//! | `supported_actions()`  | `supportedactions` | `Vec<String>`         |
//!
//! Each of the 10 typed Alpaca wrappers in `nightshade_alpaca` already
//! implements these four methods with identical signatures; this trait
//! formalizes the shared contract so a single generic helper can replace the
//! 10-arm `match DeviceType { ... }` blocks in `dispatch/alpaca.rs` (and
//! eventually `dispatch/ascom.rs`).
//!
//! # What this trait deliberately does NOT abstract
//!
//! This is the **read-only metadata probe** surface. It is NOT a general
//! "Alpaca device" trait — it intentionally omits:
//!
//! * **Lifecycle** (`connect`/`disconnect`/`is_connected`) — those exist on
//!   the wrappers but their use is coupled to the bridge's per-device-type
//!   storage maps (`alpaca_cameras`, `alpaca_mounts`, …); abstracting them
//!   here would not actually reduce duplication.
//! * **Heartbeat** — some wrappers expose `heartbeat()` (returns RTT in ms)
//!   while others fall back to `is_connected()` (see `perform_alpaca_health_check`).
//!   That heterogeneity is real, not accidental; forcing it into the trait
//!   would smush a genuine distinction.
//! * **Operational properties** (`can_slew`, `camera_x_size`, …) — these
//!   differ per device role and are precisely what makes the typed wrappers
//!   distinct. They belong on the concrete types, not the common trait.
//!
//! In other words: this trait captures only what is genuinely the same across
//! all 10 wrappers, and stops there.
//!
//! # `supported_actions` silent-fallback policy
//!
//! `supported_actions()` is `unwrap_or_default()`-ed inside `fetch_api_version`
//! because per the ASCOM/Alpaca specification, drivers that do not implement
//! the optional `ISupportedActions` interface legitimately return Alpaca error
//! `0x40C` (`ActionNotImplemented`). The documented semantics for "this driver
//! advertises no custom actions" is an empty list, which is exactly what
//! `Vec::default()` provides. Per the project's "Errors are a feature" policy,
//! we make this not-silent by emitting a `tracing::debug!` so the discarded
//! error is observable in logs even though it does not propagate.

use crate::device::DeviceApiVersion;

/// Read-only ASCOM-Common identification probe for a typed Alpaca wrapper.
///
/// See the module-level docs for what this trait does and does not abstract.
/// Every method maps 1:1 to an ASCOM-Common HTTP endpoint and is safe to call
/// without holding a connection (the wrappers delegate to the underlying
/// `AlpacaHttpClient` which is stateless).
pub(crate) trait AlpacaDeviceCommon {
    /// ASCOM `InterfaceVersion` — small positive integer (currently 1..=4)
    /// per the ASCOM spec. `Err` means the property is missing or the
    /// request failed.
    fn interface_version(&self) -> impl std::future::Future<Output = Result<i32, String>> + Send;

    /// ASCOM `DriverVersion` — free-form vendor version string. `Err` means
    /// the property is missing or the request failed.
    fn driver_version(&self) -> impl std::future::Future<Output = Result<String, String>> + Send;

    /// ASCOM `DriverInfo` — free-form vendor-supplied description. `Err`
    /// means the property is missing or the request failed.
    fn driver_info(&self) -> impl std::future::Future<Output = Result<String, String>> + Send;

    /// ASCOM `SupportedActions` — list of custom action names exposed by the
    /// driver. `Err` means the driver does not implement
    /// `ISupportedActions` (Alpaca `0x40C`) or the request failed.
    fn supported_actions(
        &self,
    ) -> impl std::future::Future<Output = Result<Vec<String>, String>> + Send;
}

/// Build a `DeviceApiVersion` by probing the four ASCOM-Common properties of
/// a typed Alpaca wrapper.
///
/// Replaces the 10x duplicated arm body in `query_alpaca_api_version`. The
/// silent-fallback semantics match the pre-trait code exactly:
///
/// * `interface_version` → `1` (ASCOM V1 baseline) when probe fails.
/// * `driver_version` / `driver_info` → `None` when probe fails.
/// * `supported_actions` → empty `Vec` when probe fails (with a debug log so
///   the discarded error is observable).
///
/// Errors here are not surfaced as `Err` because at the call site any
/// individual probe failure is already documented (per the module docstring)
/// as a valid "missing optional property" signal — propagating it would break
/// the equipment-compatibility-matrix UI for partially-conforming drivers.
/// Connection-absence is still a hard `Err` at the dispatch layer above.
pub(crate) async fn fetch_api_version<T: AlpacaDeviceCommon + ?Sized>(
    device: &T,
    device_id: &str,
) -> DeviceApiVersion {
    let interface_version = device.interface_version().await.ok();
    let driver_version = device.driver_version().await.ok();
    let driver_info = device.driver_info().await.ok();
    let supported_actions = match device.supported_actions().await {
        Ok(actions) => actions,
        Err(e) => {
            // Why: ASCOM `ISupportedActions` is OPTIONAL; missing → empty
            // list per spec. We default rather than propagate, but log the
            // error so the silent fallback is observable in tracing output.
            tracing::debug!(
                device_id = %device_id,
                error = %e,
                "Alpaca supported_actions probe failed; treating as empty (ASCOM-optional)"
            );
            Vec::new()
        }
    };

    DeviceApiVersion::from_alpaca(
        device_id.to_string(),
        interface_version.unwrap_or(1),
        driver_version,
        driver_info,
        supported_actions,
    )
}

// =========================================================================
// Trait implementations for the 10 typed Alpaca wrappers
// =========================================================================
//
// Each impl is a verbatim delegation to the wrapper's existing inherent
// methods (which all share these exact signatures — see the audit-trail
// comment in `dispatch/alpaca.rs::query_alpaca_api_version`). The methods
// are NOT renamed on the wrappers — the trait piggy-backs on the existing
// surface.

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaCamera {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaTelescope {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaFocuser {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaFilterWheel {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaRotator {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaDome {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaSafetyMonitor {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaSwitch {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaCoverCalibrator {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}

impl AlpacaDeviceCommon for nightshade_alpaca::AlpacaObservingConditions {
    async fn interface_version(&self) -> Result<i32, String> {
        Self::interface_version(self).await
    }
    async fn driver_version(&self) -> Result<String, String> {
        Self::driver_version(self).await
    }
    async fn driver_info(&self) -> Result<String, String> {
        Self::driver_info(self).await
    }
    async fn supported_actions(&self) -> Result<Vec<String>, String> {
        Self::supported_actions(self).await
    }
}
