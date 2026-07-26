//! Device connection lifecycle: register, connect, disconnect, auto-reconnect.
//!
//! Methods in this module are additional impl blocks on `DeviceManager` and
//! contain the cross-driver lifecycle logic. Driver-specific `connect_*`
//! helpers continue to live in `crate::dispatch::{ascom,alpaca,indi,native}`
//! (also split-impl-block) and are invoked from `connect_device_internal`
//! below. No behavior or signature has changed relative to the previous
//! monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::{DeviceManager, ManagedDevice};
use crate::event::*;
use std::time::Duration;
use tokio::sync::watch;
use tokio::time::interval;
// Windows: trait must be in scope so ASCOM wrapper guards resolve its methods.
#[cfg(windows)]
use nightshade_native::traits::NativeDevice;

/// Error message returned by `connect_device_internal` when an in-flight
/// reconnect attempt is aborted by a manual disconnect. The string is part
/// of the public contract (the reconnection loop matches on it to suppress
/// noisy "reconnection attempt failed" events).
pub(crate) const RECONNECT_CANCELED_MSG: &str = "reconnect canceled by manual disconnect";

impl DeviceManager {
    /// Install (or reuse) a per-device cancellation token. The returned
    /// receiver is used by `connect_device_internal` to bail early if a
    /// manual `disconnect_device` arrives during the connect cycle.
    ///
    /// If a previous attempt left a tripped token in the map, this resets
    /// it to `false` so the new attempt starts un-canceled.
    pub(crate) async fn install_reconnect_cancel_token(
        &self,
        device_id: &str,
    ) -> watch::Receiver<bool> {
        let mut tokens = self.reconnect_cancel_tokens.write().await;
        if let Some(sender) = tokens.get(device_id) {
            // Reset to un-tripped state for a fresh attempt.
            // `send_replace` ignores receiver count and doesn't fail when there
            // are no receivers, which suits our reuse-on-second-attempt case.
            let _ = sender.send_replace(false);
            return sender.subscribe();
        }
        let (tx, rx) = watch::channel(false);
        tokens.insert(device_id.to_string(), tx);
        rx
    }

    /// Trip the per-device reconnect cancellation token, if one exists.
    ///
    /// Called from `disconnect_device` so that any in-flight
    /// `connect_device_internal` attempt notices and aborts before publishing
    /// a stale `Connected` event for the device the user just released.
    pub(crate) async fn trip_reconnect_cancel_token(&self, device_id: &str) {
        let tokens = self.reconnect_cancel_tokens.read().await;
        if let Some(sender) = tokens.get(device_id) {
            // send_replace overwrites the value unconditionally. We don't care
            // whether anyone is listening: if nobody is, there was no in-flight
            // attempt to cancel and the no-op is the correct behavior.
            let _ = sender.send_replace(true);
        }
    }

    /// Check whether the given cancellation receiver has been tripped.
    /// Pure inspection — does not await.
    fn reconnect_canceled(rx: &watch::Receiver<bool>) -> bool {
        *rx.borrow()
    }

    /// Subscribe to the existing cancel token for `device_id`, if any.
    ///
    /// Unlike `install_reconnect_cancel_token`, this does NOT create a new
    /// sender on miss — it only borrows an existing one. Used by
    /// `connect_device_internal` to consult an in-flight reconnect's token
    /// without accidentally arming a user-initiated connect path.
    async fn subscribe_existing_cancel_token(
        &self,
        device_id: &str,
    ) -> Option<watch::Receiver<bool>> {
        let tokens = self.reconnect_cancel_tokens.read().await;
        tokens.get(device_id).map(|sender| sender.subscribe())
    }

    /// Background task for automatic reconnection
    pub(crate) async fn reconnection_loop(&self) {
        let mut check_interval = interval(Duration::from_secs(5));

        loop {
            check_interval.tick().await;

            // Check if we should stop
            if *self.stop_reconnect.read().await {
                break;
            }

            if !self.reconnect_config.enabled {
                continue;
            }

            // Find devices that need reconnection
            let devices_to_reconnect: Vec<(String, ManagedDevice)> = {
                let devices = self.devices.read().await;
                devices
                    .iter()
                    .filter(|(_, dev)| {
                        dev.auto_reconnect
                            && dev.connection_state == ConnectionState::Error
                            && (self.reconnect_config.max_attempts == 0
                                || dev.reconnect_attempts < self.reconnect_config.max_attempts)
                    })
                    .map(|(id, dev)| (id.clone(), dev.clone()))
                    .collect()
            };

            // Attempt reconnection for each device
            for (device_id, device) in devices_to_reconnect {
                tracing::info!(
                    "Attempting reconnection for {} (attempt {})",
                    device_id,
                    device.reconnect_attempts + 1
                );

                // Install/reset the per-device cancel token BEFORE the backoff
                // sleep, so a disconnect arriving during the sleep is observed
                // when we wake up (and during the connect dispatch below).
                let mut cancel_rx = self.install_reconnect_cancel_token(&device_id).await;

                // Calculate backoff delay, but race it against the cancel
                // token so a manual disconnect during the sleep aborts the
                // entire attempt — not just the subsequent connect call.
                let delay = self.calculate_backoff_delay(device.reconnect_attempts);
                let sleep_fut = tokio::time::sleep(Duration::from_secs(delay));
                tokio::pin!(sleep_fut);
                let canceled_during_sleep = tokio::select! {
                    _ = &mut sleep_fut => false,
                    res = cancel_rx.changed() => {
                        // changed() returns Err only if the sender was dropped,
                        // which only happens during shutdown — treat as cancel.
                        res.is_err() || *cancel_rx.borrow()
                    }
                };

                if canceled_during_sleep {
                    tracing::info!(
                        "Reconnect for {} canceled during backoff (manual disconnect)",
                        device_id
                    );
                    continue;
                }

                // Attempt reconnection. `connect_device_internal` re-checks the
                // cancel token at additional checkpoints inside the call.
                match self.connect_device_internal(&device.info).await {
                    Err(e) if e == RECONNECT_CANCELED_MSG => {
                        // Reconnect was aborted by a concurrent disconnect.
                        // Do NOT increment the attempt counter or emit a
                        // "reconnection attempt failed" event — that would be
                        // misleading because the user themselves stopped it.
                        tracing::info!(
                            "Reconnect for {} canceled mid-attempt (manual disconnect)",
                            device_id
                        );
                        continue;
                    }
                    Err(e) => {
                        tracing::warn!("Reconnection failed for {}: {}", device_id, e);

                        // Update attempt counter
                        let mut devices = self.devices.write().await;
                        if let Some(dev) = devices.get_mut(&device_id) {
                            dev.reconnect_attempts += 1;
                            dev.last_error = Some(e.clone());

                            // Publish reconnection failed event
                            self.app_state.publish_equipment_event(
                                EquipmentEvent::Error {
                                    device_type: dev.info.device_type.as_str().to_string(),
                                    device_id: device_id.clone(),
                                    message: format!(
                                        "Reconnection attempt {} failed: {}",
                                        dev.reconnect_attempts, e
                                    ),
                                },
                                EventSeverity::Warning,
                            );
                        }
                    }
                    Ok(()) => {
                        tracing::info!("Reconnection successful for {}", device_id);

                        // Reset attempt counter on success
                        let mut devices = self.devices.write().await;
                        if let Some(dev) = devices.get_mut(&device_id) {
                            dev.reconnect_attempts = 0;
                            dev.last_error = None;
                        }
                    }
                }
            }
        }
    }

    /// Calculate backoff delay for reconnection
    pub(crate) fn calculate_backoff_delay(&self, attempts: u32) -> u64 {
        // Why: u64 (initial_delay_secs) → f64 has bounded
        // precision loss for any realistic config (seconds, not nanoseconds).
        // u32 → i32 for `powi` saturates at i32::MAX (~2B retries) which is
        // unreachable; the result is then clamped by `min(max_delay_secs)`.
        // f64 → u64 uses Rust 1.45+ saturating semantics for the final cast.
        let delay = (self.reconnect_config.initial_delay_secs as f64)
            * self
                .reconnect_config
                .backoff_multiplier
                .powi(i32::try_from(attempts).unwrap_or(i32::MAX));

        (delay as u64).min(self.reconnect_config.max_delay_secs)
    }

    /// Register a device for management
    pub async fn register_device(&self, info: DeviceInfo, auto_reconnect: bool) {
        let mut devices = self.devices.write().await;
        devices.insert(
            info.id.clone(),
            ManagedDevice {
                info,
                connection_state: ConnectionState::Disconnected,
                last_error: None,
                reconnect_attempts: 0,
                auto_reconnect,
                last_successful_comm: None,
                heartbeat_active: false,
                api_version: None,
                desired_cooler: None,
                desired_tracking: None,
            },
        );
    }

    /// Check if a device is registered
    pub async fn is_device_registered(&self, device_id: &str) -> bool {
        let devices = self.devices.read().await;
        devices.contains_key(device_id)
    }

    /// Get the display name for a registered device, if it exists.
    pub async fn get_device_display_name(&self, device_id: &str) -> Option<String> {
        let devices = self.devices.read().await;
        devices.get(device_id).map(|d| d.info.display_name.clone())
    }

    /// Connect to a device
    pub async fn connect_device(&self, device_id: &str) -> Result<(), String> {
        let device_info = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?
        };

        self.connect_device_internal(&device_info).await
    }

    /// Internal connection logic
    pub(crate) async fn connect_device_internal(&self, info: &DeviceInfo) -> Result<(), String> {
        let device_id = &info.id;

        // Subscribe to the device's reconnect cancel token (if any). Only the
        // reconnection loop installs these, so a user-initiated `connect_device`
        // call usually sees `None` here and the cancel checks below are no-ops.
        let cancel_rx = self.subscribe_existing_cancel_token(device_id).await;

        // Pre-dispatch cancel check: a manual `disconnect_device` may have run
        // between the reconnection loop's backoff wakeup and our entry here.
        if let Some(rx) = cancel_rx.as_ref() {
            if Self::reconnect_canceled(rx) {
                return Err(RECONNECT_CANCELED_MSG.to_string());
            }
        }

        // Update state to connecting. Capture the prior state first: a connect
        // arriving from `ConnectionState::Error` is an *unplanned reconnect*
        // (heartbeat-lost or report_error path), and on success we must
        // re-apply the essential device state the driver loses across a
        // physical reconnect (camera cooling setpoint, mount tracking). A
        // fresh user-initiated connect from Disconnected does NOT re-apply —
        // there is no prior desired state worth restoring and the user is
        // about to drive the device anyway.
        let was_error_before_connect = {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                let prior = dev.connection_state == ConnectionState::Error;
                dev.connection_state = ConnectionState::Connecting;
                prior
            } else {
                false
            }
        };

        // Publish connecting event
        self.app_state.publish_equipment_event(
            EquipmentEvent::Connecting {
                device_type: info.device_type.as_str().to_string(),
                device_id: device_id.clone(),
            },
            EventSeverity::Info,
        );

        // Perform actual connection based on driver type
        let result = match info.driver_type {
            DriverType::Simulator => self.connect_simulator(info).await,
            DriverType::Ascom => self.connect_ascom(info).await,
            DriverType::Alpaca => self.connect_alpaca(info).await,
            DriverType::Indi => self.connect_indi(info).await,
            DriverType::Native => self.connect_native(info).await,
        };

        // Post-dispatch cancel check: the driver dispatch above can take
        // seconds (TCP/USB negotiation). If `disconnect_device` tripped the
        // token while we were awaiting, treat the result as canceled so we
        // never overwrite the user's `Disconnected` with `Connected` and
        // never publish a misleading event.
        //
        // Errors are a feature: if the dispatch happened to
        // succeed we deliberately discard that success so the user sees their
        // disconnect honored. The reconnection_loop already special-cases
        // `RECONNECT_CANCELED_MSG` to suppress the "attempt failed" event.
        if let Some(rx) = cancel_rx.as_ref() {
            if Self::reconnect_canceled(rx) {
                // Best-effort: leave the device in whatever state the post-
                // dispatch result implies; the disconnect path will fix it up
                // when it acquires the `devices` write lock next.
                return Err(RECONNECT_CANCELED_MSG.to_string());
            }
        }

        // Update state based on result
        {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                match &result {
                    Ok(_) => {
                        dev.connection_state = ConnectionState::Connected;
                        dev.last_error = None;
                        dev.reconnect_attempts = 0;
                    }
                    Err(e) => {
                        dev.connection_state = ConnectionState::Error;
                        dev.last_error = Some(e.clone());
                    }
                }
            }
        }

        // Publish result event
        match &result {
            Ok(_) => {
                crate::device_capabilities::invalidate_capability_cache_for_device(device_id).await;

                self.app_state.publish_equipment_event(
                    EquipmentEvent::Connected {
                        device_type: info.device_type.as_str().to_string(),
                        device_id: device_id.clone(),
                    },
                    EventSeverity::Info,
                );

                // Also register in app state
                self.app_state
                    .register_device(info.clone(), ConnectionState::Connected)
                    .await;

                // Auto-start heartbeat monitoring for the connected device
                let heartbeat_config = Self::get_heartbeat_config(&info.device_type);
                if let Err(e) = self
                    .start_heartbeat_with_config(device_id, heartbeat_config)
                    .await
                {
                    tracing::warn!("Failed to start heartbeat for {}: {}", device_id, e);
                } else {
                    tracing::info!("Auto-started heartbeat for device {}", device_id);
                }

                // Reconnect-only: re-apply the essential device state the
                // driver drops across a physical reconnect. We deliberately
                // gate on `was_error_before_connect` so a fresh user connect
                // does not silently command cooling / tracking the user did
                // not ask for. Failures here are non-fatal — the reconnect
                // itself succeeded; a re-apply failure is logged + surfaced as
                // a warning so the operator can intervene, but it does not
                // turn a recovered device back into an error.
                if was_error_before_connect {
                    self.reapply_essential_state_after_reconnect(info).await;
                }
            }
            Err(e) => {
                self.app_state.publish_equipment_event(
                    EquipmentEvent::Error {
                        device_type: info.device_type.as_str().to_string(),
                        device_id: device_id.clone(),
                        message: e.clone(),
                    },
                    EventSeverity::Error,
                );
            }
        }

        result
    }

    /// Connect to a simulator device.
    ///
    /// Sets the matching `simulation.rs` singleton's `connected = true` so
    /// status accessors, heartbeat checks, and Dart-side `isConnected`
    /// observers all see a consistent "real" connection state for the
    /// simulator.
    ///
    /// # Behavior
    ///
    /// * Validates the device id has the `sim_` prefix (the established
    ///   convention used by every `device_id.starts_with("sim_")` branch in
    ///   `bridge::api::devices`). An unrecognized id returns `Err` —
    ///   silent fallbacks would let typoed sim ids appear "connected" without
    ///   any backing state. Errors are a feature.
    /// * Dispatches by `DeviceInfo.device_type`. Device types without a
    ///   `simulation.rs` singleton (Switch, CoverCalibrator, Guider) return
    ///   `Err` so we never claim "connected"
    ///   for a simulator backend that doesn't exist. The existing
    ///   ops-level `DriverType::Simulator => Ok(...)` short-circuits in
    ///   `device_manager/ops/*` are a separate, known inconsistency.
    /// * Idempotent: if the singleton is already `connected`, returns `Ok`
    ///   so the user can re-trigger "Connect" from the UI without spurious
    ///   errors.
    pub(crate) async fn connect_simulator(&self, info: &DeviceInfo) -> Result<(), String> {
        if !info.id.starts_with("sim_") {
            return Err(format!(
                "connect_simulator: device id '{}' is not a simulator id (expected 'sim_' prefix)",
                info.id
            ));
        }

        use crate::api::devices::simulation::{
            get_sim_camera, get_sim_dome, get_sim_filterwheel, get_sim_focuser, get_sim_mount,
            get_sim_rotator, get_sim_safety_monitor, get_sim_weather,
        };

        match info.device_type {
            DeviceType::Camera => {
                let mut cam = get_sim_camera().write().await;
                cam.status.connected = true;
            }
            DeviceType::Mount => {
                let mut mount = get_sim_mount().write().await;
                mount.status.connected = true;
            }
            DeviceType::Focuser => {
                let mut focuser = get_sim_focuser().write().await;
                focuser.status.connected = true;
            }
            DeviceType::FilterWheel => {
                let mut fw = get_sim_filterwheel().write().await;
                fw.status.connected = true;
            }
            DeviceType::Rotator => {
                let mut rot = get_sim_rotator().write().await;
                rot.status.connected = true;
            }
            DeviceType::Dome => {
                get_sim_dome().write().await.status.connected = true;
            }
            DeviceType::Weather => {
                get_sim_weather().write().await.connected = true;
            }
            DeviceType::SafetyMonitor => {
                get_sim_safety_monitor().write().await.status.connected = true;
            }
            other => {
                return Err(format!(
                    "connect_simulator: no simulator implementation for device type {:?} (id '{}')",
                    other, info.id
                ));
            }
        }

        tracing::info!(
            "Simulator connected: id={} type={:?}",
            info.id,
            info.device_type
        );
        Ok(())
    }

    /// Disconnect a simulator device.
    ///
    /// Mirrors `connect_simulator`: sets the matching singleton's
    /// `connected = false` so the heartbeat loop and any other consumer of
    /// the singleton state agree that the device is no longer connected.
    /// Idempotent — disconnecting an already-disconnected simulator returns
    /// `Ok`.
    ///
    /// Unrecognized device types return `Err` (consistent with
    /// `connect_simulator`): a silent no-op would hide bugs where the user
    /// thinks a disconnect happened but no singleton was actually touched.
    pub(crate) async fn disconnect_simulator(&self, info: &DeviceInfo) -> Result<(), String> {
        if !info.id.starts_with("sim_") {
            return Err(format!(
                "disconnect_simulator: device id '{}' is not a simulator id (expected 'sim_' prefix)",
                info.id
            ));
        }

        use crate::api::devices::simulation::{
            get_sim_camera, get_sim_dome, get_sim_filterwheel, get_sim_focuser, get_sim_mount,
            get_sim_rotator, get_sim_safety_monitor, get_sim_weather,
        };

        match info.device_type {
            DeviceType::Camera => {
                let mut cam = get_sim_camera().write().await;
                cam.status.connected = false;
            }
            DeviceType::Mount => {
                let mut mount = get_sim_mount().write().await;
                mount.status.connected = false;
            }
            DeviceType::Focuser => {
                let mut focuser = get_sim_focuser().write().await;
                focuser.status.connected = false;
            }
            DeviceType::FilterWheel => {
                let mut fw = get_sim_filterwheel().write().await;
                fw.status.connected = false;
            }
            DeviceType::Rotator => {
                let mut rot = get_sim_rotator().write().await;
                rot.status.connected = false;
            }
            DeviceType::Dome => {
                get_sim_dome().write().await.status.connected = false;
            }
            DeviceType::Weather => {
                get_sim_weather().write().await.connected = false;
            }
            DeviceType::SafetyMonitor => {
                get_sim_safety_monitor().write().await.status.connected = false;
            }
            other => {
                return Err(format!(
                    "disconnect_simulator: no simulator implementation for device type {:?} (id '{}')",
                    other, info.id
                ));
            }
        }

        tracing::info!(
            "Simulator disconnected: id={} type={:?}",
            info.id,
            info.device_type
        );
        Ok(())
    }

    /// Disconnect a device
    pub async fn disconnect_device(&self, device_id: &str) -> Result<(), String> {
        // Stop heartbeat monitoring first to prevent false disconnect events
        let _ = self.stop_heartbeat(device_id).await;
        crate::device_capabilities::invalidate_capability_cache_for_device(device_id).await;

        let device_info = {
            let devices = self.devices.read().await;
            devices
                .get(device_id)
                .map(|d| d.info.clone())
                .ok_or_else(|| format!("Device not found: {}", device_id))?
        };

        // Update state
        {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                dev.connection_state = ConnectionState::Disconnected;
                dev.auto_reconnect = false; // Disable auto-reconnect on manual disconnect
            }
        }

        // Trip any in-flight reconnect attempt's cancel token. This
        // must happen AFTER releasing the `devices` write lock above (lock
        // ordering: `devices` then `reconnect_cancel_tokens`) but BEFORE we
        // begin tearing down driver-specific state — otherwise a reconnect
        // currently inside `connect_device_internal` could re-populate the
        // driver maps we are about to drain.
        //
        // We do not block waiting for the reconnect to bail: `connect_device_
        // internal` polls the token at pre- and post-dispatch checkpoints and
        // returns `RECONNECT_CANCELED_MSG`, which the reconnection_loop
        // suppresses. Worst case, the driver dispatch is mid-flight and runs
        // to completion against now-stale maps; its result is then discarded
        // by the post-dispatch cancel check.
        self.trip_reconnect_cancel_token(device_id).await;

        // Clean up device from driver-specific storage based on driver type and device type
        let mut disconnect_errors = Vec::new();
        macro_rules! record_disconnect {
            ($label:expr, $result:expr) => {
                if let Err(e) = $result {
                    let message = format!("{} disconnect failed for {}: {}", $label, device_id, e);
                    tracing::warn!("{}", message);
                    disconnect_errors.push(message);
                }
            };
        }

        if device_info.id == crate::builtin_guider::device_id() {
            record_disconnect!("Built-in guider", crate::builtin_guider::disconnect().await);
        }
        // PHD2 has its own out-of-band disconnect path (the PHD2
        // client storage lives outside the per-driver maps below). If a user
        // disconnects PHD2 via the generic `disconnect_device` route, we have
        // to mirror the built-in-guider check above so the PHD2 socket is
        // actually torn down. Without this the PHD2 client was leaked: state
        // was reset but the TCP connection and event listener kept running,
        // so a subsequent reconnect attempted to talk through a stale client.
        if crate::api::connection::is_phd2_device_id(&device_info.id) {
            if let Err(e) = crate::api::phd2::api_phd2_disconnect().await {
                // Errors are a feature: log loudly so we never hide a stuck
                // PHD2 client. We continue with the generic cleanup below
                // either way — the device is already being released and we
                // don't want a PHD2-side error to block disconnecting the
                // rest of the device record.
                tracing::warn!(
                    "PHD2 disconnect via generic route failed for {}: {}",
                    device_info.id,
                    e
                );
            }
        }
        match device_info.driver_type {
            DriverType::Native => {
                // Remove from generic native_devices map
                let mut native_devices = self.native_devices.write().await;
                if let Some(mut device) = native_devices.remove(device_id) {
                    record_disconnect!("Native device", device.disconnect().await);
                }

                // Also remove from typed native storage maps
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.native_cameras.write().await;
                        if let Some(mut camera) = cameras.remove(device_id) {
                            record_disconnect!("Native camera", camera.disconnect().await);
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.native_mounts.write().await;
                        if let Some(mut mount) = mounts.remove(device_id) {
                            record_disconnect!("Native mount", mount.disconnect().await);
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.native_focusers.write().await;
                        if let Some(mut focuser) = focusers.remove(device_id) {
                            record_disconnect!("Native focuser", focuser.disconnect().await);
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.native_filter_wheels.write().await;
                        if let Some(mut fw) = fws.remove(device_id) {
                            record_disconnect!("Native filter wheel", fw.disconnect().await);
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.native_rotators.write().await;
                        if let Some(mut rotator) = rotators.remove(device_id) {
                            record_disconnect!("Native rotator", rotator.disconnect().await);
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.native_domes.write().await;
                        if let Some(mut dome) = domes.remove(device_id) {
                            record_disconnect!("Native dome", dome.disconnect().await);
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.native_weather.write().await;
                        if let Some(mut w) = weather.remove(device_id) {
                            record_disconnect!("Native weather", w.disconnect().await);
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety = self.native_safety_monitors.write().await;
                        if let Some(mut s) = safety.remove(device_id) {
                            record_disconnect!("Native safety monitor", s.disconnect().await);
                        }
                    }
                    DeviceType::Switch => {
                        let mut switches = self.native_switches.write().await;
                        if let Some(mut sw) = switches.remove(device_id) {
                            record_disconnect!("Native switch", sw.disconnect().await);
                        }
                    }
                    DeviceType::CoverCalibrator => {
                        let mut covers = self.native_cover_calibrators.write().await;
                        if let Some(mut cover) = covers.remove(device_id) {
                            record_disconnect!("Native cover calibrator", cover.disconnect().await);
                        }
                    }
                    DeviceType::Guider => {}
                }
            }
            DriverType::Alpaca => {
                // Remove from Alpaca storage based on device type
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.alpaca_cameras.write().await;
                        if let Some(camera) = cameras.remove(device_id) {
                            record_disconnect!("Alpaca camera", camera.disconnect().await);
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.alpaca_mounts.write().await;
                        if let Some(mount) = mounts.remove(device_id) {
                            record_disconnect!("Alpaca mount", mount.disconnect().await);
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.alpaca_focusers.write().await;
                        if let Some(focuser) = focusers.remove(device_id) {
                            record_disconnect!("Alpaca focuser", focuser.disconnect().await);
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.alpaca_filter_wheels.write().await;
                        if let Some(fw) = fws.remove(device_id) {
                            record_disconnect!("Alpaca filter wheel", fw.disconnect().await);
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.alpaca_rotators.write().await;
                        if let Some(rotator) = rotators.remove(device_id) {
                            record_disconnect!("Alpaca rotator", rotator.disconnect().await);
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.alpaca_domes.write().await;
                        if let Some(dome) = domes.remove(device_id) {
                            record_disconnect!("Alpaca dome", dome.disconnect().await);
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.alpaca_weather.write().await;
                        if let Some(w) = weather.remove(device_id) {
                            record_disconnect!("Alpaca weather", w.disconnect().await);
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety = self.alpaca_safety_monitors.write().await;
                        if let Some(s) = safety.remove(device_id) {
                            record_disconnect!("Alpaca safety monitor", s.disconnect().await);
                        }
                    }
                    DeviceType::Switch => {
                        let mut switches = self.alpaca_switches.write().await;
                        if let Some(sw) = switches.remove(device_id) {
                            record_disconnect!("Alpaca switch", sw.disconnect().await);
                        }
                    }
                    DeviceType::CoverCalibrator => {
                        let mut covers = self.alpaca_cover_calibrators.write().await;
                        if let Some(cover) = covers.remove(device_id) {
                            record_disconnect!("Alpaca cover calibrator", cover.disconnect().await);
                        }
                    }
                    DeviceType::Guider => {} // Alpaca guider devices are not currently managed here
                }
            }
            #[cfg(windows)]
            DriverType::Ascom => {
                // Remove from ASCOM storage based on device type
                match device_info.device_type {
                    DeviceType::Camera => {
                        let mut cameras = self.ascom_cameras.write().await;
                        if let Some(camera) = cameras.remove(device_id) {
                            let mut cam = camera.write().await;
                            record_disconnect!("ASCOM camera", cam.disconnect().await);
                        }
                    }
                    DeviceType::Mount => {
                        let mut mounts = self.ascom_mounts.write().await;
                        if let Some(mount) = mounts.remove(device_id) {
                            let mut m = mount.write().await;
                            record_disconnect!("ASCOM mount", m.disconnect().await);
                        }
                    }
                    DeviceType::Focuser => {
                        let mut focusers = self.ascom_focusers.write().await;
                        if let Some(focuser) = focusers.remove(device_id) {
                            let mut f = focuser.write().await;
                            record_disconnect!("ASCOM focuser", f.disconnect().await);
                        }
                    }
                    DeviceType::FilterWheel => {
                        let mut fws = self.ascom_filter_wheels.write().await;
                        if let Some(fw) = fws.remove(device_id) {
                            let mut f = fw.write().await;
                            record_disconnect!("ASCOM filter wheel", f.disconnect().await);
                        }
                    }
                    DeviceType::Rotator => {
                        let mut rotators = self.ascom_rotators.write().await;
                        if let Some(rotator) = rotators.remove(device_id) {
                            let mut r = rotator.write().await;
                            record_disconnect!("ASCOM rotator", r.disconnect().await);
                        }
                    }
                    DeviceType::Dome => {
                        let mut domes = self.ascom_domes.write().await;
                        if let Some(dome) = domes.remove(device_id) {
                            let mut d = dome.write().await;
                            record_disconnect!("ASCOM dome", d.disconnect().await);
                        }
                    }
                    DeviceType::Weather => {
                        let mut weather = self.ascom_weather.write().await;
                        if let Some(device) = weather.remove(device_id) {
                            let mut w = device.write().await;
                            record_disconnect!("ASCOM weather", w.disconnect().await);
                        }
                    }
                    DeviceType::SafetyMonitor => {
                        let mut safety_monitors = self.ascom_safety_monitors.write().await;
                        if let Some(monitor) = safety_monitors.remove(device_id) {
                            let mut sm = monitor.write().await;
                            record_disconnect!("ASCOM safety monitor", sm.disconnect().await);
                        }
                    }
                    DeviceType::Switch => {
                        let mut switches = self.ascom_switches.write().await;
                        if let Some(sw) = switches.remove(device_id) {
                            let mut s = sw.write().await;
                            record_disconnect!("ASCOM switch", s.disconnect().await);
                        }
                    }
                    DeviceType::CoverCalibrator => {
                        let mut covers = self.ascom_cover_calibrators.write().await;
                        if let Some(cover) = covers.remove(device_id) {
                            let mut c = cover.write().await;
                            record_disconnect!("ASCOM cover calibrator", c.disconnect().await);
                        }
                    }
                    _ => {}
                }
            }
            #[cfg(not(windows))]
            DriverType::Ascom => {
                // ASCOM not available on non-Windows platforms
            }
            DriverType::Indi => {
                let parts: Vec<&str> = device_id.split(':').collect();
                if parts.len() < 4 {
                    return Err(format!("Invalid INDI device ID format: {}", device_id));
                }
                let host = parts[1];
                let port = parts[2];
                let device_name = parts[3..].join(":");
                let server_key = format!("{}:{}", host, port);

                let client = {
                    let clients = self.indi_clients.read().await;
                    clients.get(&server_key).cloned()
                };

                let Some(client) = client else {
                    return Err(format!("INDI client not connected for {}", server_key));
                };

                client
                    .write()
                    .await
                    .disconnect_device(&device_name)
                    .await
                    .map_err(|e| {
                        format!(
                            "Failed to disconnect INDI device {} via {}: {}",
                            device_name, server_key, e
                        )
                    })?;
            }
            DriverType::Simulator => {
                // Flip the matching `simulation.rs` singleton's `connected`
                // bit back to false so the heartbeat loop and any other
                // observer agrees the simulator is offline. Errors here are
                // logged but do not block the rest of disconnect cleanup —
                // the user has already asked to release the device, and the
                // managed-device state is being torn down regardless.
                if let Err(e) = self.disconnect_simulator(&device_info).await {
                    tracing::warn!("disconnect_simulator failed for {}: {}", device_info.id, e);
                }
            }
        }

        // Publish event
        self.app_state.publish_equipment_event(
            EquipmentEvent::Disconnected {
                device_type: device_info.device_type.as_str().to_string(),
                device_id: device_id.to_string(),
            },
            EventSeverity::Info,
        );

        // Update app state
        self.app_state
            .remove_device(device_info.device_type, device_id)
            .await;

        if !disconnect_errors.is_empty() {
            return Err(format!(
                "Disconnected {} from Nightshade state, but driver cleanup reported: {}",
                device_id,
                disconnect_errors.join("; ")
            ));
        }

        Ok(())
    }

    /// Enable or disable auto-reconnect for a device
    pub async fn set_auto_reconnect(&self, device_id: &str, enabled: bool) {
        let mut devices = self.devices.write().await;
        if let Some(dev) = devices.get_mut(device_id) {
            dev.auto_reconnect = enabled;
        }
    }

    /// Report a connection error (triggers auto-reconnect if enabled)
    pub async fn report_error(&self, device_id: &str, error: String) {
        crate::device_capabilities::invalidate_capability_cache_for_device(device_id).await;

        let device_type = {
            let mut devices = self.devices.write().await;
            if let Some(dev) = devices.get_mut(device_id) {
                dev.connection_state = ConnectionState::Error;
                dev.last_error = Some(error.clone());
                dev.info.device_type
            } else {
                return;
            }
        };

        self.app_state.remove_device(device_type, device_id).await;

        self.app_state.publish_equipment_event(
            EquipmentEvent::Error {
                device_type: device_type.as_str().to_string(),
                device_id: device_id.to_string(),
                message: error,
            },
            EventSeverity::Error,
        );
    }

    /// Heartbeat threshold reached: mark the device unhealthy and mirror registry state.
    ///
    /// Real reconnection is handled exclusively by `reconnection_loop` when
    /// `auto_reconnect` is enabled (FB-); the heartbeat task must not sleep
    /// and pretend to reconnect.
    pub(crate) async fn handle_heartbeat_lost(
        &self,
        device_id: &str,
        heartbeat_auto_reconnect: bool,
        consecutive_failures: u32,
        error_msg: &str,
    ) -> Option<DeviceInfo> {
        let info = {
            let mut devices = self.devices.write().await;
            let dev = devices.get_mut(device_id)?;
            dev.connection_state = ConnectionState::Error;
            dev.last_error = Some(format!(
                "Unresponsive after {} heartbeat failures: {}",
                consecutive_failures, error_msg
            ));
            if heartbeat_auto_reconnect {
                dev.auto_reconnect = true;
            }
            dev.info.clone()
        };

        self.app_state
            .remove_device(info.device_type, device_id)
            .await;

        Some(info)
    }

    /// Re-apply the essential device state that a physical reconnect drops.
    ///
    /// Drivers come back from a USB / serial reconnect in their power-on
    /// defaults: a camera's cooler is off and its setpoint cleared, a mount is
    /// parked / not tracking. After an unplanned reconnect we replay the last
    /// state the user / sequencer commanded (recorded in `camera_set_cooler` /
    /// `mount_set_tracking`) so an unattended run does not silently warm the
    /// sensor or leave the mount stationary while the sequence "resumes".
    ///
    /// Only camera cooling and mount tracking are replayed — these are the two
    /// pieces of state that (a) are commanded ahead of time and persist, and
    /// (b) materially break the session if lost. Position / filter / focus are
    /// re-established by the recovery loop and the next instruction's own
    /// centering / filter-change steps, so we do not duplicate them here.
    ///
    /// Errors are non-fatal: the reconnect already succeeded, so a replay
    /// failure is surfaced as a `Warning` event for operator visibility but
    /// does NOT flip the device back into an error state.
    async fn reapply_essential_state_after_reconnect(&self, info: &DeviceInfo) {
        let device_id = &info.id;

        let (desired_cooler, desired_tracking) = {
            let devices = self.devices.read().await;
            match devices.get(device_id) {
                Some(dev) => (dev.desired_cooler, dev.desired_tracking),
                None => return,
            }
        };

        match info.device_type {
            DeviceType::Camera => {
                if let Some((enabled, target_temp)) = desired_cooler {
                    tracing::info!(
                        "Reconnect: re-applying camera {} cooler (enabled={}, target={:?})",
                        device_id,
                        enabled,
                        target_temp
                    );
                    if let Err(e) = self
                        .camera_set_cooler(device_id, enabled, target_temp)
                        .await
                    {
                        tracing::warn!(
                            "Reconnect: failed to re-apply camera {} cooler: {}",
                            device_id,
                            e
                        );
                        self.app_state.publish_equipment_event(
                            EquipmentEvent::Error {
                                device_type: info.device_type.as_str().to_string(),
                                device_id: device_id.clone(),
                                message: format!(
                                    "Reconnected but could not restore cooling setpoint: {}",
                                    e
                                ),
                            },
                            EventSeverity::Warning,
                        );
                    }
                }
            }
            DeviceType::Mount => {
                if let Some(enabled) = desired_tracking {
                    tracing::info!(
                        "Reconnect: re-applying mount {} tracking={}",
                        device_id,
                        enabled
                    );
                    if let Err(e) = self.mount_set_tracking(device_id, enabled).await {
                        tracing::warn!(
                            "Reconnect: failed to re-apply mount {} tracking: {}",
                            device_id,
                            e
                        );
                        self.app_state.publish_equipment_event(
                            EquipmentEvent::Error {
                                device_type: info.device_type.as_str().to_string(),
                                device_id: device_id.clone(),
                                message: format!(
                                    "Reconnected but could not restore mount tracking: {}",
                                    e
                                ),
                            },
                            EventSeverity::Warning,
                        );
                    }
                }
            }
            _ => {}
        }
    }

    /// Stop the reconnection background task
    pub async fn shutdown(&self) {
        *self.stop_reconnect.write().await = true;
    }

    /// Unregister a device
    pub async fn unregister_device(&self, device_id: &str) {
        let mut devices = self.devices.write().await;
        devices.remove(device_id);
    }
}
