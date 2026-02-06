//! Sky-Watcher SynScan Mount Protocol Implementation
//!
//! Implements the Sky-Watcher motor controller protocol for EQ and AltAz mounts.
//! Protocol reference: Sky-Watcher Motor Controller Command Set
//!
//! Communication: Serial 9600/115200 baud or UDP (192.168.4.1:11880)

use crate::traits::*;
use crate::NativeVendor;
use async_trait::async_trait;
use std::io::{Read, Write};
use std::sync::Mutex;
use std::time::Duration;

// =============================================================================
// CONSTANTS
// =============================================================================

/// Default serial baud rate for SynScan protocol (older mounts, hand controller)
const SYNSCAN_BAUD_RATE: u32 = 9600;

/// High-speed baud rate for newer mounts (EQ6-R Pro, etc.) via USB

/// Baud rates to try during discovery, in order of preference
/// - 115200: Newer mounts (EQ6-R Pro, EQ8, etc.) via USB
/// - 9600: Older mounts, hand controller connections
const SYNSCAN_DISCOVERY_BAUD_RATES: &[u32] = &[115200, 9600];

/// Default UDP port for WiFi-enabled mounts
const SYNSCAN_UDP_PORT: u16 = 11880;

/// Default UDP IP for WiFi-enabled mounts
const SYNSCAN_UDP_IP: &str = "192.168.4.1";

/// Position offset used in SynScan protocol (0x800000)
const POSITION_OFFSET: i64 = 0x800000;

/// Steps per full rotation (24-bit encoder)
const STEPS_PER_REVOLUTION: f64 = 16777216.0; // 2^24

/// Axis identifiers
const AXIS_RA: char = '1'; // RA or Azimuth
const AXIS_DEC: char = '2'; // Dec or Altitude

// =============================================================================
// SYNSCAN COMMANDS
// =============================================================================

/// SynScan motor controller commands
mod commands {
    // Inquiry commands
    pub const GET_POSITION: char = 'j'; // Get axis position
    pub const GET_STATUS: char = 'f'; // Get axis status
    pub const INIT_CHECK: &str = ":F3"; // Check initialization

    // Motion commands
    pub const SET_GOTO_TARGET: char = 'S'; // Set goto target position
    pub const START_MOTION: char = 'J'; // Start motion to target
    pub const STOP_MOTION: char = 'K'; // Soft stop
    pub const SET_MOTION_MODE: char = 'G'; // Set motion mode (goto/tracking)

    // Position commands
    pub const SYNC_POSITION: char = 'E'; // Sync (set) axis position

    // Response indicators
    pub const RESPONSE_OK: char = '=';
    pub const RESPONSE_ERROR: char = '!';
}

// =============================================================================
// MOTION MODE FLAGS
// =============================================================================

/// Motion mode byte construction
fn build_motion_mode(is_tracking: bool, is_fast: bool, is_ccw: bool) -> u8 {
    let mut mode: u8 = 0;
    if is_tracking {
        mode |= 0x01;
    }
    if is_fast {
        mode |= 0x02;
    }
    if is_ccw {
        mode |= if is_tracking { 0x02 } else { 0x04 };
    }
    mode
}

// =============================================================================
// DATA ENCODING/DECODING
// =============================================================================

/// Encode a 24-bit value to SynScan hex format (reversed byte pairs)
fn encode_24bit(value: i64) -> String {
    let bytes = [
        ((value >> 0) & 0xFF) as u8,
        ((value >> 8) & 0xFF) as u8,
        ((value >> 16) & 0xFF) as u8,
    ];
    format!("{:02X}{:02X}{:02X}", bytes[0], bytes[1], bytes[2])
}

/// Decode SynScan hex format to 24-bit value
fn decode_24bit(hex: &str) -> Result<i64, NativeError> {
    if hex.len() != 6 {
        return Err(NativeError::InvalidParameter(format!(
            "Expected 6 hex chars, got {}",
            hex.len()
        )));
    }

    let b0 = u8::from_str_radix(&hex[0..2], 16)
        .map_err(|_| NativeError::SdkError("Invalid hex".into()))?;
    let b1 = u8::from_str_radix(&hex[2..4], 16)
        .map_err(|_| NativeError::SdkError("Invalid hex".into()))?;
    let b2 = u8::from_str_radix(&hex[4..6], 16)
        .map_err(|_| NativeError::SdkError("Invalid hex".into()))?;

    Ok((b0 as i64) | ((b1 as i64) << 8) | ((b2 as i64) << 16))
}

/// Convert encoder steps to degrees
fn steps_to_degrees(steps: i64) -> f64 {
    (steps as f64 / STEPS_PER_REVOLUTION) * 360.0
}

/// Convert degrees to encoder steps
fn degrees_to_steps(degrees: f64) -> i64 {
    ((degrees / 360.0) * STEPS_PER_REVOLUTION) as i64
}

/// Convert hours to degrees (for RA)
fn hours_to_degrees(hours: f64) -> f64 {
    hours * 15.0
}

/// Convert degrees to hours (for RA)
fn degrees_to_hours(degrees: f64) -> f64 {
    degrees / 15.0
}

// =============================================================================
// CONNECTION TYPES
// =============================================================================

/// Connection type for SynScan mount
#[derive(Debug, Clone)]
pub enum SynScanConnection {
    /// Serial port connection
    Serial { port: String, baud_rate: u32 },
    /// UDP/WiFi connection
    Udp { ip: String, port: u16 },
}

impl Default for SynScanConnection {
    fn default() -> Self {
        SynScanConnection::Udp {
            ip: SYNSCAN_UDP_IP.to_string(),
            port: SYNSCAN_UDP_PORT,
        }
    }
}

// =============================================================================
// SKYWATCHER MOUNT IMPLEMENTATION
// =============================================================================

/// Sky-Watcher SynScan mount driver
pub struct SkyWatcherMount {
    device_id: String,
    name: String,
    connection_config: SynScanConnection,
    serial_port: Mutex<Option<Box<dyn serialport::SerialPort + Send>>>,
    connected: Mutex<bool>,
    is_tracking: Mutex<bool>,
    is_slewing: Mutex<bool>,
    is_parked: Mutex<bool>,
}

impl std::fmt::Debug for SkyWatcherMount {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SkyWatcherMount")
            .field("device_id", &self.device_id)
            .field("name", &self.name)
            .finish()
    }
}

impl SkyWatcherMount {
    /// Create a new Sky-Watcher mount with serial connection
    pub fn new_serial(port: String, baud_rate: Option<u32>) -> Self {
        let device_id = format!(
            "native:skywatcher:{}",
            port.replace("/", "_").replace("\\", "_")
        );
        Self {
            device_id,
            name: format!("Sky-Watcher ({})", port),
            connection_config: SynScanConnection::Serial {
                port,
                baud_rate: baud_rate.unwrap_or(SYNSCAN_BAUD_RATE),
            },
            serial_port: Mutex::new(None),
            connected: Mutex::new(false),
            is_tracking: Mutex::new(false),
            is_slewing: Mutex::new(false),
            is_parked: Mutex::new(false),
        }
    }

    /// Create a new Sky-Watcher mount with UDP/WiFi connection
    pub fn new_udp(ip: Option<String>, port: Option<u16>) -> Self {
        let ip = ip.unwrap_or_else(|| SYNSCAN_UDP_IP.to_string());
        let port = port.unwrap_or(SYNSCAN_UDP_PORT);
        let device_id = format!("native:skywatcher:{}:{}", ip, port);
        Self {
            device_id,
            name: format!("Sky-Watcher WiFi ({}:{})", ip, port),
            connection_config: SynScanConnection::Udp { ip, port },
            serial_port: Mutex::new(None),
            connected: Mutex::new(false),
            is_tracking: Mutex::new(false),
            is_slewing: Mutex::new(false),
            is_parked: Mutex::new(false),
        }
    }

    /// Send a command and receive response (internal, takes lock)
    fn send_command_internal(
        port: &mut Box<dyn serialport::SerialPort + Send>,
        command: &str,
    ) -> Result<String, NativeError> {
        // Send command with CR terminator
        let cmd_bytes = format!("{}\r", command);
        port.write_all(cmd_bytes.as_bytes())
            .map_err(|e| NativeError::Io(e))?;
        port.flush().map_err(|e| NativeError::Io(e))?;

        // Read response until CR
        let mut response = Vec::new();
        let mut buf = [0u8; 1];
        let timeout = std::time::Instant::now();

        loop {
            if timeout.elapsed() > Duration::from_secs(5) {
                return Err(NativeError::Timeout(
                    "SkyWatcher command response timed out".to_string(),
                ));
            }

            match port.read(&mut buf) {
                Ok(1) => {
                    if buf[0] == b'\r' {
                        break;
                    }
                    response.push(buf[0]);
                }
                Ok(_) => continue,
                Err(ref e) if e.kind() == std::io::ErrorKind::TimedOut => continue,
                Err(e) => return Err(NativeError::Io(e)),
            }
        }

        let response_str = String::from_utf8_lossy(&response).to_string();

        // Check for error response
        if response_str.starts_with(commands::RESPONSE_ERROR) {
            return Err(NativeError::SdkError(format!(
                "Mount error: {}",
                response_str
            )));
        }

        // Strip leading '=' if present
        let result = if response_str.starts_with(commands::RESPONSE_OK) {
            response_str[1..].to_string()
        } else {
            response_str
        };

        Ok(result)
    }

    /// Send a command (acquires lock internally)
    fn send_command(&self, command: &str) -> Result<String, NativeError> {
        let mut port_guard = self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))?;
        let port = port_guard.as_mut().ok_or(NativeError::NotConnected)?;
        Self::send_command_internal(port, command)
    }

    /// Send axis command (format: :CMD{axis}{data})
    fn send_axis_command(
        &self,
        cmd: char,
        axis: char,
        data: Option<&str>,
    ) -> Result<String, NativeError> {
        let command = match data {
            Some(d) => format!(":{}{}{}", cmd, axis, d),
            None => format!(":{}{}", cmd, axis),
        };
        self.send_command(&command)
    }

    /// Get axis position in encoder steps
    fn get_axis_position(&self, axis: char) -> Result<i64, NativeError> {
        let response = self.send_axis_command(commands::GET_POSITION, axis, None)?;
        let raw = decode_24bit(&response)?;
        Ok(raw - POSITION_OFFSET)
    }

    /// Get axis status
    fn get_axis_status(&self, axis: char) -> Result<u16, NativeError> {
        let response = self.send_axis_command(commands::GET_STATUS, axis, None)?;
        u16::from_str_radix(&response, 16)
            .map_err(|_| NativeError::SdkError("Invalid status".into()))
    }

    /// Check if axis is moving (from status)
    fn is_axis_moving(&self, axis: char) -> Result<bool, NativeError> {
        let status = self.get_axis_status(axis)?;
        Ok((status & 0x01) != 0)
    }

    /// Set axis goto target
    fn set_axis_target(&self, axis: char, steps: i64) -> Result<(), NativeError> {
        let encoded = encode_24bit(steps + POSITION_OFFSET);
        self.send_axis_command(commands::SET_GOTO_TARGET, axis, Some(&encoded))?;
        Ok(())
    }

    /// Start axis motion
    fn start_axis_motion(&self, axis: char) -> Result<(), NativeError> {
        self.send_axis_command(commands::START_MOTION, axis, None)?;
        Ok(())
    }

    /// Stop axis motion
    fn stop_axis_motion(&self, axis: char) -> Result<(), NativeError> {
        self.send_axis_command(commands::STOP_MOTION, axis, None)?;
        Ok(())
    }

    /// Set motion mode for axis
    fn set_axis_motion_mode(&self, axis: char, mode: u8) -> Result<(), NativeError> {
        let encoded = format!("{:02X}", mode);
        self.send_axis_command(commands::SET_MOTION_MODE, axis, Some(&encoded))?;
        Ok(())
    }

    /// Sync axis position
    fn sync_axis_position(&self, axis: char, steps: i64) -> Result<(), NativeError> {
        let encoded = encode_24bit(steps + POSITION_OFFSET);
        self.send_axis_command(commands::SYNC_POSITION, axis, Some(&encoded))?;
        Ok(())
    }
}

#[async_trait]
impl NativeDevice for SkyWatcherMount {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::SkyWatcher
    }

    fn is_connected(&self) -> bool {
        *self.connected.lock().unwrap_or_else(|e| e.into_inner())
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        if self.is_connected() {
            return Ok(());
        }

        match &self.connection_config {
            SynScanConnection::Serial { port, baud_rate } => {
                let serial = serialport::new(port, *baud_rate)
                    .timeout(Duration::from_millis(500))
                    .open()
                    .map_err(|e| {
                        NativeError::SdkError(format!("Failed to open serial port: {}", e))
                    })?;

                *self
                    .serial_port
                    .lock()
                    .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = Some(serial);
            }
            SynScanConnection::Udp { ip: _, port: _ } => {
                return Err(NativeError::NotSupported);
            }
        }

        // Verify connection by querying position
        let _ = self.get_axis_position(AXIS_RA)?;

        *self
            .connected
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = true;
        tracing::info!("Connected to Sky-Watcher mount");

        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Ok(());
        }

        // Stop any motion before disconnecting
        let _ = self.stop_axis_motion(AXIS_RA);
        let _ = self.stop_axis_motion(AXIS_DEC);

        *self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = None;
        *self
            .connected
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = false;

        tracing::info!("Disconnected from Sky-Watcher mount");

        Ok(())
    }
}

#[async_trait]
impl NativeMount for SkyWatcherMount {
    async fn slew_to_coordinates(
        &mut self,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        tracing::info!("Slewing to RA={:.4}h, Dec={:.4}°", ra_hours, dec_degrees);

        let ra_steps = degrees_to_steps(hours_to_degrees(ra_hours));
        let dec_steps = degrees_to_steps(dec_degrees);

        let goto_mode = build_motion_mode(false, true, false);
        self.set_axis_motion_mode(AXIS_RA, goto_mode)?;
        self.set_axis_motion_mode(AXIS_DEC, goto_mode)?;

        self.set_axis_target(AXIS_RA, ra_steps)?;
        self.set_axis_target(AXIS_DEC, dec_steps)?;

        self.start_axis_motion(AXIS_RA)?;
        self.start_axis_motion(AXIS_DEC)?;

        *self
            .is_slewing
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = true;

        Ok(())
    }

    async fn get_coordinates(&self) -> Result<(f64, f64), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        let ra_steps = self.get_axis_position(AXIS_RA)?;
        let dec_steps = self.get_axis_position(AXIS_DEC)?;

        let ra_hours = degrees_to_hours(steps_to_degrees(ra_steps));
        let dec_degrees = steps_to_degrees(dec_steps);

        let ra_normalized = ((ra_hours % 24.0) + 24.0) % 24.0;

        Ok((ra_normalized, dec_degrees))
    }

    async fn sync_to_coordinates(
        &mut self,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        tracing::info!("Syncing to RA={:.4}h, Dec={:.4}°", ra_hours, dec_degrees);

        let ra_steps = degrees_to_steps(hours_to_degrees(ra_hours));
        let dec_steps = degrees_to_steps(dec_degrees);

        self.sync_axis_position(AXIS_RA, ra_steps)?;
        self.sync_axis_position(AXIS_DEC, dec_steps)?;

        Ok(())
    }

    async fn park(&mut self) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        tracing::info!("Parking mount");

        self.slew_to_coordinates(0.0, 0.0).await?;

        while self.is_slewing().await? {
            tokio::time::sleep(Duration::from_millis(500)).await;
        }

        self.set_tracking(false).await?;

        *self
            .is_parked
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = true;

        Ok(())
    }

    async fn unpark(&mut self) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        *self
            .is_parked
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = false;

        self.set_tracking(true).await?;

        tracing::info!("Mount unparked");

        Ok(())
    }

    async fn is_slewing(&self) -> Result<bool, NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        let ra_moving = self.is_axis_moving(AXIS_RA)?;
        let dec_moving = self.is_axis_moving(AXIS_DEC)?;

        Ok(ra_moving || dec_moving)
    }

    async fn is_parked(&self) -> Result<bool, NativeError> {
        Ok(*self.is_parked.lock().unwrap_or_else(|e| e.into_inner()))
    }

    async fn pulse_guide(
        &mut self,
        direction: GuideDirection,
        duration_ms: u32,
    ) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        let (axis, is_positive) = match direction {
            GuideDirection::North => (AXIS_DEC, true),
            GuideDirection::South => (AXIS_DEC, false),
            GuideDirection::East => (AXIS_RA, false),
            GuideDirection::West => (AXIS_RA, true),
        };

        let mode = build_motion_mode(true, false, !is_positive);
        self.set_axis_motion_mode(axis, mode)?;

        self.start_axis_motion(axis)?;

        tokio::time::sleep(Duration::from_millis(duration_ms as u64)).await;

        self.stop_axis_motion(axis)?;

        Ok(())
    }

    async fn abort_slew(&mut self) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        tracing::info!("Aborting slew");

        self.stop_axis_motion(AXIS_RA)?;
        self.stop_axis_motion(AXIS_DEC)?;

        *self
            .is_slewing
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = false;

        Ok(())
    }

    async fn set_tracking(&mut self, enabled: bool) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        if enabled {
            let mode = build_motion_mode(true, false, false);
            self.set_axis_motion_mode(AXIS_RA, mode)?;
            self.start_axis_motion(AXIS_RA)?;
        } else {
            self.stop_axis_motion(AXIS_RA)?;
        }

        *self
            .is_tracking
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = enabled;

        tracing::info!("Tracking {}", if enabled { "enabled" } else { "disabled" });

        Ok(())
    }

    async fn get_tracking(&self) -> Result<bool, NativeError> {
        Ok(*self.is_tracking.lock().unwrap_or_else(|e| e.into_inner()))
    }

    async fn get_side_of_pier(&self) -> Result<PierSide, NativeError> {
        Ok(PierSide::Unknown)
    }

    async fn get_alt_az(&self) -> Result<(f64, f64), NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn get_sidereal_time(&self) -> Result<f64, NativeError> {
        Err(NativeError::NotSupported)
    }

    async fn set_tracking_rate(&mut self, rate: TrackingRate) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        // SynScan protocol supports tracking rate changes via motor speed adjustments
        // For now, we only fully support sidereal rate - others require specific mount commands
        match rate {
            TrackingRate::Sidereal => {
                // Sidereal is the default tracking mode
                tracing::info!("Setting tracking rate to Sidereal");
                Ok(())
            }
            TrackingRate::Lunar | TrackingRate::Solar | TrackingRate::King => {
                // These rates require specific motor speed calculations
                // The SynScan protocol uses motor speed values rather than named rates
                tracing::info!("Setting tracking rate to {:?}", rate);
                // TODO: Implement proper motor speed calculations for different rates
                Ok(())
            }
            TrackingRate::Custom => Err(NativeError::NotSupported),
        }
    }

    async fn get_tracking_rate(&self) -> Result<TrackingRate, NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        // SynScan doesn't have a direct query for tracking rate
        // Default to sidereal
        Ok(TrackingRate::Sidereal)
    }

    fn can_set_tracking_rate(&self) -> bool {
        true
    }
}

// =============================================================================
// DISCOVERY
// =============================================================================

/// Sky-Watcher mount discovery info
pub struct SkyWatcherMountInfo {
    pub port: String,
    pub name: String,
    /// Baud rate that was successful during discovery
    pub baud_rate: u32,
}

/// Discover Sky-Watcher mounts on serial ports
/// Tries multiple baud rates to support both older and newer mounts
pub async fn discover_mounts() -> Result<Vec<SkyWatcherMountInfo>, NativeError> {
    let mut mounts = Vec::new();

    let ports = serialport::available_ports()
        .map_err(|e| NativeError::SdkError(format!("Failed to enumerate ports: {}", e)))?;

    tracing::info!(
        "Sky-Watcher discovery: found {} serial ports to scan",
        ports.len()
    );

    for port_info in ports {
        let port_name = port_info.port_name.clone();
        let mut found_mount = false;

        // Try multiple baud rates - newer mounts like EQ6-R Pro use 115200
        for &baud_rate in SYNSCAN_DISCOVERY_BAUD_RATES {
            if found_mount {
                break;
            }

            tracing::debug!("Trying {} at {} baud for Sky-Watcher", port_name, baud_rate);

            let result = serialport::new(&port_name, baud_rate)
                .timeout(Duration::from_millis(500))
                .open();

            match result {
                Err(e) => {
                    // Common on Windows: port is busy/locked by another app -> don't spam logs.
                    let msg = e.to_string();
                    let is_access_denied = msg.contains("Access is denied")
                        || msg.contains("access is denied")
                        || msg.contains("Permission denied")
                        || msg.contains("permission denied");

                    if is_access_denied {
                        tracing::trace!(
                            "Skipping busy port {} at {} baud for Sky-Watcher detection: {}",
                            port_name,
                            baud_rate,
                            msg
                        );
                    } else {
                        tracing::debug!(
                            "Could not open port {} at {} baud for Sky-Watcher detection: {}",
                            port_name,
                            baud_rate,
                            msg
                        );
                    }
                    // If we can't open at any baud rate, skip to next port
                    break;
                }
                Ok(mut port) => {
                    let cmd = format!("{}\r", commands::INIT_CHECK);
                    if port.write_all(cmd.as_bytes()).is_ok() {
                        let _ = port.flush();

                        let mut buf = [0u8; 32];
                        std::thread::sleep(Duration::from_millis(100));

                        if let Ok(n) = port.read(&mut buf) {
                            let response = String::from_utf8_lossy(&buf[..n]);
                            tracing::debug!(
                                "Sky-Watcher response from {} at {} baud: {:?}",
                                port_name,
                                baud_rate,
                                response
                            );
                            if response.contains('=') || response.contains('!') {
                                let display_name = format!("Sky-Watcher ({})", port_name);
                                mounts.push(SkyWatcherMountInfo {
                                    port: port_name.clone(),
                                    name: display_name.clone(),
                                    baud_rate,
                                });
                                tracing::info!(
                                    "Found Sky-Watcher mount on {} at {} baud",
                                    port_name,
                                    baud_rate
                                );
                                found_mount = true;
                            }
                        }
                    }
                    // Explicit drop + sleep for Windows to fully release the COM port handle
                    drop(port);
                    std::thread::sleep(Duration::from_millis(50));
                }
            }
        }
    }

    tracing::info!(
        "Sky-Watcher discovery complete: found {} mounts",
        mounts.len()
    );
    Ok(mounts)
}

/// Check if Sky-Watcher protocol is available
pub fn is_available() -> bool {
    true
}
