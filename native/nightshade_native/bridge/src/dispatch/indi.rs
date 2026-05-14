//! INDI driver dispatch helpers.
//!
//! Methods in this module are additional impl blocks on `DeviceManager` and
//! provide INDI-only logic: device discovery, connection, API version query,
//! switch helpers, and the per-device health check. Two free helper functions
//! that map INDI properties / names to a `DeviceType` also live here. They are
//! invoked from dispatcher methods in `crate::device_manager`. No behavior or
//! signature has changed relative to the previous monolithic `devices.rs`.

use crate::device::*;
use crate::device_manager::DeviceManager;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;

/// Heuristically classify an INDI device from its property list. Returned to
/// the discovery helpers as a `DeviceType`, or `None` if no match is found.
pub(crate) fn infer_indi_device_type_from_properties(
    properties: &[nightshade_indi::IndiProperty],
) -> Option<DeviceType> {
    let has = |name: &str| properties.iter().any(|p| p.name == name);

    if has("CCD_EXPOSURE") || has("CCD_INFO") || has("CCD_FRAME") || has("CCD1") {
        return Some(DeviceType::Camera);
    }
    if has("EQUATORIAL_EOD_COORD")
        || has("ON_COORD_SET")
        || has("TELESCOPE_TRACK_MODE")
        || has("TELESCOPE_MOTION_NS")
        || has("TELESCOPE_MOTION_WE")
    {
        return Some(DeviceType::Mount);
    }
    if has("ABS_FOCUS_POSITION") || has("REL_FOCUS_POSITION") || has("FOCUS_MOTION") {
        return Some(DeviceType::Focuser);
    }
    if has("FILTER_SLOT") || has("FILTER_NAME") {
        return Some(DeviceType::FilterWheel);
    }
    if has("DOME_SHUTTER") || has("DOME_MOTION") || has("ABS_DOME_POSITION") {
        return Some(DeviceType::Dome);
    }
    if has("ABS_ROTATOR_ANGLE") || has("ROTATOR_ANGLE") {
        return Some(DeviceType::Rotator);
    }
    if has("TELESCOPE_TIMED_GUIDE_NS") || has("TELESCOPE_TIMED_GUIDE_WE") {
        return Some(DeviceType::Guider);
    }
    if has("SAFETY_STATUS") || has("AUX_SAFETY") {
        return Some(DeviceType::SafetyMonitor);
    }
    if has("WEATHER_STATUS") || has("WEATHER_PARAMETERS") {
        return Some(DeviceType::Weather);
    }
    if has("CAP_PARK")
        || has("FLAT_LIGHT_CONTROL")
        || has("FLAT_LIGHT_INTENSITY")
        || has("DUSTCAP_CONTROL")
        || has("LIGHTBOX_BRIGHTNESS")
    {
        return Some(DeviceType::CoverCalibrator);
    }
    if properties
        .iter()
        .any(|p| matches!(p.property_type, nightshade_indi::IndiPropertyType::Switch))
    {
        return Some(DeviceType::Switch);
    }

    None
}

/// Fallback INDI device classifier when property inspection didn't match a
/// known shape — uses the device name + driver string supplied by the server.
pub(crate) fn infer_indi_device_type_from_name_driver(
    name: &str,
    driver: &str,
) -> Option<DeviceType> {
    let name_upper = name.to_uppercase();
    let driver_upper = driver.to_uppercase();

    if name_upper.contains("CCD")
        || name_upper.contains("CAMERA")
        || driver_upper.contains("CCD")
        || driver_upper.contains("CAMERA")
    {
        return Some(DeviceType::Camera);
    }
    if name_upper.contains("TELESCOPE")
        || name_upper.contains("MOUNT")
        || driver_upper.contains("TELESCOPE")
        || driver_upper.contains("MOUNT")
    {
        return Some(DeviceType::Mount);
    }
    if name_upper.contains("FOCUSER") || driver_upper.contains("FOCUSER") {
        return Some(DeviceType::Focuser);
    }
    if name_upper.contains("WHEEL") || driver_upper.contains("WHEEL") {
        return Some(DeviceType::FilterWheel);
    }
    if name_upper.contains("ROTATOR") || driver_upper.contains("ROTATOR") {
        return Some(DeviceType::Rotator);
    }
    if name_upper.contains("DOME") || driver_upper.contains("DOME") {
        return Some(DeviceType::Dome);
    }
    if name_upper.contains("WEATHER") || driver_upper.contains("WEATHER") {
        return Some(DeviceType::Weather);
    }
    if name_upper.contains("SAFETY") || driver_upper.contains("SAFETY") {
        return Some(DeviceType::SafetyMonitor);
    }

    None
}

impl DeviceManager {
    pub(crate) fn parse_indi_device_id(device_id: &str) -> Result<(String, u16, String), String> {
        let parsed = crate::device_id::parse_device_id_cached(device_id)
            .map_err(|e| format!("Invalid INDI device ID format: {}", e))?;
        match parsed.connection_info {
            crate::device_id::ConnectionInfo::Indi {
                host,
                port,
                device_name,
            } => Ok((host, port, device_name)),
            _ => Err(format!("Invalid INDI device ID format: {}", device_id)),
        }
    }

    pub(crate) async fn indi_mount_tracking_rate(
        client: &nightshade_indi::IndiClient,
        device_name: &str,
    ) -> (TrackingRate, bool) {
        let Some(prop) = client
            .get_property(device_name, "TELESCOPE_TRACK_RATE")
            .await
        else {
            return (TrackingRate::Sidereal, false);
        };

        let can_set_tracking_rate = prop.perm != nightshade_indi::IndiPermission::ReadOnly;
        for element in prop.elements {
            if !client
                .get_switch(device_name, "TELESCOPE_TRACK_RATE", &element)
                .await
                .unwrap_or(false)
            {
                continue;
            }

            let upper = element.to_ascii_uppercase();
            let rate = if upper.contains("SIDEREAL") {
                Some(TrackingRate::Sidereal)
            } else if upper.contains("LUNAR") {
                Some(TrackingRate::Lunar)
            } else if upper.contains("SOLAR") {
                Some(TrackingRate::Solar)
            } else if upper.contains("KING") {
                Some(TrackingRate::King)
            } else if upper.contains("CUSTOM") {
                Some(TrackingRate::Custom)
            } else {
                None
            };

            if let Some(rate) = rate {
                return (rate, can_set_tracking_rate);
            }
        }

        (TrackingRate::Sidereal, can_set_tracking_rate)
    }

    /// Connect to an INDI device
    pub(crate) async fn connect_indi(&self, info: &DeviceInfo) -> Result<(), String> {
        use nightshade_indi::IndiClient;

        // Parse INDI device ID: indi:host:port:device_name
        let parts: Vec<&str> = info.id.split(':').collect();
        if parts.len() < 4 {
            return Err(
                "Invalid INDI device ID format. Expected: indi:host:port:device_name".to_string(),
            );
        }

        let host = parts[1];
        let port: u16 = parts[2].parse().map_err(|_| "Invalid port number")?;
        let device_name = parts[3..].join(":");
        let server_key = format!("{}:{}", host, port);

        // Check if client exists
        let client = {
            let mut clients = self.indi_clients.write().await;
            if let Some(client) = clients.get(&server_key) {
                client.clone()
            } else {
                // Create new client
                let mut new_client = IndiClient::new(host, Some(port));
                new_client.connect().await?;
                let client_arc = Arc::new(RwLock::new(new_client));
                clients.insert(server_key.clone(), client_arc.clone());
                client_arc
            }
        };

        // Use the client to connect the device
        let mut locked_client = client.write().await;

        // Enable BLOB for cameras
        if info.device_type == DeviceType::Camera {
            if let Err(e) = locked_client.enable_blob(&device_name).await {
                tracing::warn!("Failed to enable BLOB for {}: {}", device_name, e);
            }
        }

        // Connect to the specific device
        locked_client.connect_device(&device_name).await?;

        tracing::info!(
            "Connected to INDI device: {} at {}",
            device_name,
            server_key
        );
        Ok(())
    }

    /// Query and cache API version for an INDI device
    pub async fn query_indi_api_version(
        &self,
        device_id: &str,
    ) -> Result<DeviceApiVersion, String> {
        // Get the device info
        let device_info = {
            let devices = self.devices.read().await;
            devices.get(device_id).map(|d| d.info.clone())
        };

        let info = device_info.ok_or_else(|| format!("Device not found: {}", device_id))?;

        if info.driver_type != DriverType::Indi {
            return Err(format!("Device {} is not an INDI device", device_id));
        }

        // Parse INDI connection info from device ID
        let parsed = crate::device_id::parse_device_id_cached(device_id)
            .map_err(|e| format!("Failed to parse device ID: {}", e))?;

        let (host, port) = match &parsed.connection_info {
            crate::device_id::ConnectionInfo::Indi { host, port, .. } => (host.clone(), *port),
            _ => return Err("Invalid INDI device ID".to_string()),
        };

        let client_key = format!("{}:{}", host, port);

        // Get protocol version from INDI client
        let indi_clients = self.indi_clients.read().await;
        let protocol_version = if let Some(client) = indi_clients.get(&client_key) {
            let client_guard = client.read().await;
            client_guard.get_server_version().await.ok()
        } else {
            None
        };

        let version = DeviceApiVersion::from_indi(device_id.to_string(), protocol_version);

        // Cache the version
        self.set_device_api_version(device_id, version.clone())
            .await;
        tracing::info!(
            "Queried API version for {}: protocol_version={:?}",
            device_id,
            version.protocol_version
        );

        Ok(version)
    }

    pub async fn get_indi_client(
        &self,
        device_id: &str,
    ) -> Option<Arc<RwLock<nightshade_indi::IndiClient>>> {
        // Parse INDI device ID: indi:host:port:device_name
        if !device_id.starts_with("indi:") {
            return None;
        }

        let parts: Vec<&str> = device_id.split(':').collect();
        if parts.len() < 4 {
            return None;
        }

        let host = parts[1];
        let port = parts[2];
        let server_key = format!("{}:{}", host, port);

        let clients = self.indi_clients.read().await;
        clients.get(&server_key).cloned()
    }

    /// Discover INDI devices at a specific address
    pub async fn discover_indi_devices(
        &self,
        host: &str,
        port: u16,
    ) -> Result<Vec<DeviceInfo>, String> {
        use nightshade_indi::IndiClient;

        let server_key = format!("{}:{}", host, port);

        // Get or create client
        let client = {
            let mut clients = self.indi_clients.write().await;
            if let Some(client) = clients.get(&server_key) {
                client.clone()
            } else {
                // Create new client
                let mut new_client = IndiClient::new(host, Some(port));
                new_client.connect().await.map_err(|e| e.to_string())?;
                let client_arc = Arc::new(RwLock::new(new_client));
                clients.insert(server_key.clone(), client_arc.clone());
                client_arc
            }
        };

        // Wait a moment for devices to be populated
        // In a real scenario, we might want to wait for a specific event or have a timeout
        // Wait up to 2 seconds for devices to appear.
        let start = std::time::Instant::now();
        loop {
            {
                let locked_client = client.read().await;
                let devices = locked_client.get_devices().await;
                if !devices.is_empty() {
                    break;
                }
            }

            if start.elapsed().as_secs() >= 2 {
                break;
            }

            tokio::time::sleep(Duration::from_millis(100)).await;
        }

        // Get devices and convert to DeviceInfo
        let locked_client = client.read().await;
        let indi_devices = locked_client.get_devices().await;

        let mut devices = Vec::new();
        for dev in indi_devices {
            let properties = locked_client.get_properties(&dev.name).await;
            let device_type = infer_indi_device_type_from_properties(&properties)
                .or_else(|| infer_indi_device_type_from_name_driver(&dev.name, &dev.driver));
            let Some(device_type) = device_type else {
                tracing::warn!(
                    "Skipping INDI device '{}' with unrecognized type (driver='{}')",
                    dev.name,
                    dev.driver
                );
                continue;
            };

            // Serial number is not consistently exposed by INDI discovery; leave unset.
            devices.push(DeviceInfo {
                id: format!("indi:{}:{}:{}", host, port, dev.name),
                name: dev.name.clone(),
                device_type,
                driver_type: DriverType::Indi,
                description: format!("INDI device on {}:{}", host, port),
                driver_version: "INDI".to_string(),
                serial_number: None,
                unique_id: None,
                display_name: dev.name.clone(),
            });
        }

        Ok(devices)
    }

    /// Get all discovered INDI devices from all connected clients
    pub async fn get_all_indi_devices(&self) -> Vec<DeviceInfo> {
        let clients = self.indi_clients.read().await;
        let mut all_devices = Vec::new();

        for (server_key, client_arc) in clients.iter() {
            let client = client_arc.read().await;
            let indi_devices = client.get_devices().await;

            for dev in indi_devices {
                let properties = client.get_properties(&dev.name).await;
                let device_type = infer_indi_device_type_from_properties(&properties)
                    .or_else(|| infer_indi_device_type_from_name_driver(&dev.name, &dev.driver));
                let Some(device_type) = device_type else {
                    tracing::warn!(
                        "Skipping INDI device '{}' with unrecognized type (driver='{}')",
                        dev.name,
                        dev.driver
                    );
                    continue;
                };

                // Serial number is not consistently exposed by INDI discovery; leave unset.
                all_devices.push(DeviceInfo {
                    id: format!("indi:{}:{}", server_key, dev.name),
                    name: dev.name.clone(),
                    device_type,
                    driver_type: DriverType::Indi,
                    description: format!("INDI device on {}", server_key),
                    driver_version: "INDI".to_string(),
                    serial_number: None,
                    unique_id: None,
                    display_name: dev.name.clone(),
                });
            }
        }

        all_devices
    }

    /// Perform health check for INDI devices
    pub(crate) async fn perform_indi_health_check(&self, device_id: &str) -> Result<bool, String> {
        // Parse INDI device ID format: indi:host:port:device_name
        let parts: Vec<&str> = device_id.split(':').collect();
        if parts.len() < 4 {
            return Err("Invalid INDI device ID format".to_string());
        }

        let server_key = format!("{}:{}", parts[1], parts[2]);
        let device_name = parts[3..].join(":");

        let clients = self.indi_clients.read().await;
        if let Some(client) = clients.get(&server_key) {
            let client_guard = client.read().await;
            let is_connected = client_guard.is_connected().await;

            if is_connected {
                // Check if the device is still responding by verifying it exists
                let is_device_connected = client_guard.is_device_connected(&device_name).await;
                tracing::trace!(
                    "INDI {} heartbeat: server_connected={}, device_connected={}",
                    device_id,
                    is_connected,
                    is_device_connected
                );
                Ok(is_device_connected)
            } else {
                tracing::debug!("INDI {} heartbeat: server not connected", device_id);
                Ok(false)
            }
        } else {
            Err(format!("INDI client for {} not found", server_key))
        }
    }

    pub(crate) async fn indi_get_all_switches(
        &self,
        device_id: &str,
    ) -> Result<Vec<nightshade_indi::IndiSwitchInfo>, String> {
        let parts: Vec<&str> = device_id.split(':').collect();
        if parts.len() < 4 {
            return Err("Invalid INDI device ID".to_string());
        }
        let server_key = format!("{}:{}", parts[1], parts[2]);
        let device_name = parts[3..].join(":");

        let clients = self.indi_clients.read().await;
        if let Some(client) = clients.get(&server_key) {
            let switch_dev = nightshade_indi::IndiSwitchDevice::new(client.clone(), &device_name);
            return Ok(switch_dev.get_all_switches().await);
        }
        Err("INDI switch device not connected".to_string())
    }

    /// Get the Nth INDI switch element (0-indexed).
    pub(crate) async fn indi_get_switch_at(
        &self,
        device_id: &str,
        index: i32,
    ) -> Result<nightshade_indi::IndiSwitchInfo, String> {
        let switches = self.indi_get_all_switches(device_id).await?;
        let idx = index as usize;
        if idx >= switches.len() {
            return Err(format!(
                "Switch index {} out of range (device has {} switches)",
                index,
                switches.len()
            ));
        }
        Ok(switches
            .into_iter()
            .nth(idx)
            .ok_or_else(|| format!("Switch index {} out of range", index))?)
    }
}
