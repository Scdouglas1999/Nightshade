//! LX200 Mount Protocol Implementation
//!
//! Implements the Meade LX200 serial command protocol, which is the de-facto
//! standard for many telescope mounts including:
//! - Meade LX200, LX600, LX850
//! - OnStep-based mounts (Pegasus NYX-101, DIY builds)
//! - Losmandy Gemini (LX200 mode)
//! - 10Micron mounts
//! - Many other compatible mounts

use crate::traits::*;
use crate::NativeVendor;
use async_trait::async_trait;
use std::io::{Read, Write};
use std::sync::Mutex;
use std::time::Duration;

/// Default baud rate for classic LX200 mounts
const LX200_BAUD_RATE: u32 = 9600;
const RESPONSE_TERM: u8 = b'#';

/// Baud rates to try during discovery, in order of preference
/// - 115200: Pegasus NYX-101, modern OnStep builds
/// - 57600: Some OnStep configurations
/// - 19200: Some mounts use this
/// - 9600: Classic LX200, Meade, Losmandy Gemini
const DISCOVERY_BAUD_RATES: &[u32] = &[115200, 57600, 19200, 9600];

mod commands {
    // Standard LX200 commands
    pub const GET_RA: &str = ":GR#";
    pub const GET_DEC: &str = ":GD#";
    pub const GET_ALT: &str = ":GA#";
    pub const GET_AZ: &str = ":GZ#";
    pub const GET_SIDEREAL_TIME: &str = ":GS#";

    pub const SET_TARGET_RA: &str = ":Sr";
    pub const SET_TARGET_DEC: &str = ":Sd";

    pub const SLEW_TO_TARGET: &str = ":MS#";
    pub const STOP_SLEW: &str = ":Q#";

    pub const SYNC: &str = ":CM#";

    pub const MOVE_NORTH: &str = ":Mn#";
    pub const MOVE_SOUTH: &str = ":Ms#";
    pub const MOVE_EAST: &str = ":Me#";
    pub const MOVE_WEST: &str = ":Mw#";
    pub const STOP_MOVE_NORTH: &str = ":Qn#";
    pub const STOP_MOVE_SOUTH: &str = ":Qs#";
    pub const STOP_MOVE_EAST: &str = ":Qe#";
    pub const STOP_MOVE_WEST: &str = ":Qw#";

    pub const SET_TRACK_SIDEREAL: &str = ":TQ#";
    pub const SET_TRACK_LUNAR: &str = ":TL#";
    pub const SET_TRACK_SOLAR: &str = ":TS#"; // OnStep: :TS# for solar rate
    pub const SET_RATE_GUIDE: &str = ":RG#";

    // OnStep tracking rate commands
    pub const ONSTEP_SET_RATE_KING: &str = ":TK#";

    pub const GET_PRODUCT_NAME: &str = ":GVP#";

    pub const PARK: &str = ":hP#";
    pub const UNPARK_MEADE: &str = ":PO#";

    // OnStep-specific commands (used by Pegasus NYX, DIY OnStep mounts)
    pub const ONSTEP_GET_STATUS: &str = ":GU#";
    pub const ONSTEP_TRACK_ENABLE: &str = ":Te#";
    pub const ONSTEP_TRACK_DISABLE: &str = ":Td#";
    pub const ONSTEP_UNPARK: &str = ":hR#";
    // OnStep pulse guide format: :Mgdnnnn# where d=n/s/e/w, nnnn=milliseconds
    pub const ONSTEP_PULSE_GUIDE_PREFIX: &str = ":Mg";
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Lx200MountType {
    /// Standard Meade LX200 protocol
    Meade,
    /// OnStep-based mounts (Pegasus NYX-101, DIY OnStep builds)
    /// Uses extended LX200 commands for tracking, status, pulse guiding
    OnStep,
    /// Losmandy Gemini in LX200 compatibility mode
    Losmandy,
    /// 10Micron mounts (extended LX200)
    TenMicron,
    /// Generic LX200-compatible mount
    Generic,
}

impl Lx200MountType {
    pub fn vendor(&self) -> NativeVendor {
        match self {
            Lx200MountType::Meade => NativeVendor::Meade,
            Lx200MountType::OnStep => NativeVendor::Pegasus, // Pegasus NYX uses OnStep
            Lx200MountType::Losmandy | Lx200MountType::TenMicron | Lx200MountType::Generic => {
                NativeVendor::Other("LX200".to_string())
            }
        }
    }

    /// Check if this mount type uses OnStep command extensions
    pub fn is_onstep(&self) -> bool {
        matches!(self, Lx200MountType::OnStep)
    }
}

fn parse_ra(response: &str) -> Result<f64, NativeError> {
    let s = response.trim_end_matches('#');

    if let Some((h, rest)) = s.split_once(':') {
        let hours: f64 = h
            .parse()
            .map_err(|_| NativeError::SdkError("Invalid RA hours".into()))?;

        if let Some((m, sec)) = rest.split_once(':') {
            let minutes: f64 = m
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid RA minutes".into()))?;
            let seconds: f64 = sec
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid RA seconds".into()))?;
            return Ok(hours + minutes / 60.0 + seconds / 3600.0);
        } else if let Some((m, t)) = rest.split_once('.') {
            let minutes: f64 = m
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid RA minutes".into()))?;
            let tenths: f64 = t
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid RA tenths".into()))?;
            return Ok(hours + (minutes + tenths / 10.0) / 60.0);
        }
    }

    Err(NativeError::SdkError(format!("Invalid RA format: {}", s)))
}

fn parse_dec(response: &str) -> Result<f64, NativeError> {
    let s = response.trim_end_matches('#');

    let (sign, rest) = if s.starts_with('-') {
        (-1.0, &s[1..])
    } else if s.starts_with('+') {
        (1.0, &s[1..])
    } else {
        (1.0, s)
    };

    let parts: Vec<&str> = rest.split(|c| c == '*' || c == '°' || c == ':').collect();

    if parts.len() >= 2 {
        let degrees: f64 = parts[0]
            .parse()
            .map_err(|_| NativeError::SdkError("Invalid Dec degrees".into()))?;
        let arcmin: f64 = parts[1]
            .parse()
            .map_err(|_| NativeError::SdkError("Invalid Dec arcmin".into()))?;

        let arcsec: f64 = if parts.len() >= 3 {
            parts[2]
                .parse()
                .map_err(|_| NativeError::SdkError("Invalid Dec arcsec".into()))?
        } else {
            0.0
        };

        return Ok(sign * (degrees + arcmin / 60.0 + arcsec / 3600.0));
    }

    Err(NativeError::SdkError(format!("Invalid Dec format: {}", s)))
}

fn format_ra(ra_hours: f64) -> String {
    let hours = ra_hours.floor() as u32;
    let remaining = (ra_hours - hours as f64) * 60.0;
    let minutes = remaining.floor() as u32;
    let seconds = ((remaining - minutes as f64) * 60.0).round() as u32;

    format!("{:02}:{:02}:{:02}", hours, minutes, seconds)
}

fn format_dec(dec_degrees: f64) -> String {
    let sign = if dec_degrees < 0.0 { "-" } else { "+" };
    let dec_abs = dec_degrees.abs();
    let degrees = dec_abs.floor() as u32;
    let remaining = (dec_abs - degrees as f64) * 60.0;
    let arcmin = remaining.floor() as u32;
    let arcsec = ((remaining - arcmin as f64) * 60.0).round() as u32;

    format!("{}{}*{:02}:{:02}", sign, degrees, arcmin, arcsec)
}

pub struct Lx200Mount {
    device_id: String,
    name: String,
    port_name: String,
    baud_rate: u32,
    mount_type: Lx200MountType,
    serial_port: Mutex<Option<Box<dyn serialport::SerialPort + Send>>>,
    connected: Mutex<bool>,
    is_tracking: Mutex<bool>,
    is_slewing: Mutex<bool>,
    tracking_rate: Mutex<TrackingRate>,
    product_name: Mutex<String>,
}

impl std::fmt::Debug for Lx200Mount {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Lx200Mount")
            .field("device_id", &self.device_id)
            .field("name", &self.name)
            .finish()
    }
}

impl Lx200Mount {
    pub fn new(port: String, mount_type: Lx200MountType, baud_rate: Option<u32>) -> Self {
        let type_prefix = match &mount_type {
            Lx200MountType::Meade => "meade",
            Lx200MountType::OnStep => "onstep",
            Lx200MountType::Losmandy => "losmandy",
            Lx200MountType::TenMicron => "10micron",
            Lx200MountType::Generic => "lx200",
        };

        let device_id = format!(
            "native:{}:{}",
            type_prefix,
            port.replace("/", "_").replace("\\", "_")
        );
        let display_name = match &mount_type {
            Lx200MountType::Meade => "Meade LX200",
            Lx200MountType::OnStep => "OnStep Mount",
            Lx200MountType::Losmandy => "Losmandy Gemini",
            Lx200MountType::TenMicron => "10Micron",
            Lx200MountType::Generic => "LX200",
        };

        Self {
            device_id,
            name: format!("{} ({})", display_name, port),
            port_name: port,
            baud_rate: baud_rate.unwrap_or(LX200_BAUD_RATE),
            mount_type,
            serial_port: Mutex::new(None),
            connected: Mutex::new(false),
            is_tracking: Mutex::new(true),
            is_slewing: Mutex::new(false),
            tracking_rate: Mutex::new(TrackingRate::Sidereal),
            product_name: Mutex::new(String::new()),
        }
    }

    /// Create an OnStep-based mount (Pegasus NYX-101, DIY OnStep)
    pub fn new_onstep(port: String) -> Self {
        Self::new(port, Lx200MountType::OnStep, None)
    }

    pub fn new_meade(port: String) -> Self {
        Self::new(port, Lx200MountType::Meade, None)
    }

    /// Parse OnStep status response (:GU#)
    /// Returns (is_tracking, is_slewing, is_parked, is_homed, pier_side)
    fn parse_onstep_status(&self, status: &str) -> (bool, bool, bool, bool, PierSide) {
        let s = status.trim_end_matches('#');

        // OnStep status format: flags like "nNpPHGF..."
        // n = not slewing, N = slewing
        // p = not parked, P = parked
        // H = at home
        // T = tracking on
        // E/W = pier side East/West

        let is_slewing = s.contains('N'); // uppercase N = slewing
        let is_parked = s.contains('P'); // uppercase P = parked
        let is_homed = s.contains('H');
        let is_tracking = s.contains('T') || (!is_parked && !s.contains('n'));

        let pier_side = if s.contains('E') {
            PierSide::East
        } else if s.contains('W') {
            PierSide::West
        } else {
            PierSide::Unknown
        };

        (is_tracking, is_slewing, is_parked, is_homed, pier_side)
    }

    fn send_command(&self, command: &str) -> Result<String, NativeError> {
        let mut port_guard = self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))?;
        let port = port_guard.as_mut().ok_or(NativeError::NotConnected)?;

        port.write_all(command.as_bytes())
            .map_err(|e| NativeError::Io(e))?;
        port.flush().map_err(|e| NativeError::Io(e))?;

        let mut response = Vec::new();
        let mut buf = [0u8; 1];
        let timeout = std::time::Instant::now();

        loop {
            if timeout.elapsed() > Duration::from_secs(5) {
                return Err(NativeError::Timeout(
                    "LX200 command response timed out".to_string(),
                ));
            }

            match port.read(&mut buf) {
                Ok(1) => {
                    if buf[0] == RESPONSE_TERM {
                        break;
                    }
                    response.push(buf[0]);
                }
                Ok(_) => {
                    std::thread::sleep(Duration::from_millis(10));
                    continue;
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::TimedOut => continue,
                Err(e) => return Err(NativeError::Io(e)),
            }
        }

        Ok(String::from_utf8_lossy(&response).to_string())
    }

    fn send_command_bool(&self, command: &str) -> Result<bool, NativeError> {
        let mut port_guard = self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))?;
        let port = port_guard.as_mut().ok_or(NativeError::NotConnected)?;

        port.write_all(command.as_bytes())
            .map_err(|e| NativeError::Io(e))?;
        port.flush().map_err(|e| NativeError::Io(e))?;

        let mut buf = [0u8; 1];
        let timeout = std::time::Instant::now();

        loop {
            if timeout.elapsed() > Duration::from_secs(5) {
                return Err(NativeError::Timeout(
                    "LX200 command bool response timed out".to_string(),
                ));
            }

            match port.read(&mut buf) {
                Ok(1) => return Ok(buf[0] == b'1'),
                Ok(_) => {
                    std::thread::sleep(Duration::from_millis(10));
                    continue;
                }
                Err(ref e) if e.kind() == std::io::ErrorKind::TimedOut => continue,
                Err(e) => return Err(NativeError::Io(e)),
            }
        }
    }

    fn send_command_no_response(&self, command: &str) -> Result<(), NativeError> {
        let mut port_guard = self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))?;
        let port = port_guard.as_mut().ok_or(NativeError::NotConnected)?;

        port.write_all(command.as_bytes())
            .map_err(|e| NativeError::Io(e))?;
        port.flush().map_err(|e| NativeError::Io(e))?;

        Ok(())
    }
}

#[async_trait]
impl NativeDevice for Lx200Mount {
    fn id(&self) -> &str {
        &self.device_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        self.mount_type.vendor()
    }

    fn is_connected(&self) -> bool {
        *self.connected.lock().unwrap_or_else(|e| e.into_inner())
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        if self.is_connected() {
            return Ok(());
        }

        let serial = serialport::new(&self.port_name, self.baud_rate)
            .timeout(Duration::from_millis(500))
            .open()
            .map_err(|e| NativeError::SdkError(format!("Failed to open serial port: {}", e)))?;

        *self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = Some(serial);

        match self.send_command(commands::GET_PRODUCT_NAME) {
            Ok(name) => {
                *self
                    .product_name
                    .lock()
                    .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = name.clone();
                self.name = format!("{} ({})", name, self.port_name);
            }
            Err(_) => {
                self.send_command(commands::GET_RA)?;
            }
        }

        *self
            .connected
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = true;
        *self
            .is_tracking
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = true;

        tracing::info!("Connected to LX200 mount: {}", self.name);

        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Ok(());
        }

        let _ = self.send_command_no_response(commands::STOP_SLEW);

        *self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = None;
        *self
            .connected
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = false;

        tracing::info!("Disconnected from LX200 mount");

        Ok(())
    }
}

#[async_trait]
impl NativeMount for Lx200Mount {
    async fn slew_to_coordinates(
        &mut self,
        ra_hours: f64,
        dec_degrees: f64,
    ) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        tracing::info!("Slewing to RA={:.4}h, Dec={:.4}°", ra_hours, dec_degrees);

        let ra_cmd = format!("{}{}#", commands::SET_TARGET_RA, format_ra(ra_hours));
        if !self.send_command_bool(&ra_cmd)? {
            return Err(NativeError::SdkError("Failed to set RA target".into()));
        }

        let dec_cmd = format!("{}{}#", commands::SET_TARGET_DEC, format_dec(dec_degrees));
        if !self.send_command_bool(&dec_cmd)? {
            return Err(NativeError::SdkError("Failed to set Dec target".into()));
        }

        let response = self.send_command(commands::SLEW_TO_TARGET)?;
        if response != "0" && !response.is_empty() {
            match response.chars().next() {
                Some('1') => return Err(NativeError::SdkError("Object is below horizon".into())),
                Some('2') => {
                    return Err(NativeError::SdkError(
                        "Object is below altitude limit".into(),
                    ))
                }
                _ => return Err(NativeError::SdkError(format!("Slew failed: {}", response))),
            }
        }

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

        let ra_response = self.send_command(commands::GET_RA)?;
        let dec_response = self.send_command(commands::GET_DEC)?;

        let ra = parse_ra(&ra_response)?;
        let dec = parse_dec(&dec_response)?;

        Ok((ra, dec))
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

        let ra_cmd = format!("{}{}#", commands::SET_TARGET_RA, format_ra(ra_hours));
        self.send_command_bool(&ra_cmd)?;

        let dec_cmd = format!("{}{}#", commands::SET_TARGET_DEC, format_dec(dec_degrees));
        self.send_command_bool(&dec_cmd)?;

        let _ = self.send_command(commands::SYNC)?;

        Ok(())
    }

    async fn park(&mut self) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        tracing::info!("Parking mount");
        self.send_command_no_response(commands::PARK)?;

        Ok(())
    }

    async fn unpark(&mut self) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        tracing::info!("Unparking mount");

        // OnStep uses :hR# for unpark, standard LX200 uses :PO#
        if self.mount_type.is_onstep() {
            self.send_command_no_response(commands::ONSTEP_UNPARK)?;
        } else {
            self.send_command_no_response(commands::UNPARK_MEADE)?;
        }

        Ok(())
    }

    async fn is_slewing(&self) -> Result<bool, NativeError> {
        if !self.is_connected() {
            return Ok(false);
        }

        // OnStep can query actual status
        if self.mount_type.is_onstep() {
            if let Ok(status) = self.send_command(commands::ONSTEP_GET_STATUS) {
                let (_, is_slewing, _, _, _) = self.parse_onstep_status(&status);
                *self.is_slewing.lock().unwrap_or_else(|e| e.into_inner()) = is_slewing;
                return Ok(is_slewing);
            }
        }

        Ok(*self.is_slewing.lock().unwrap_or_else(|e| e.into_inner()))
    }

    async fn is_parked(&self) -> Result<bool, NativeError> {
        if !self.is_connected() {
            return Ok(false);
        }

        // OnStep can query actual park status
        if self.mount_type.is_onstep() {
            if let Ok(status) = self.send_command(commands::ONSTEP_GET_STATUS) {
                let (_, _, is_parked, _, _) = self.parse_onstep_status(&status);
                return Ok(is_parked);
            }
        }

        Ok(false)
    }

    async fn pulse_guide(
        &mut self,
        direction: GuideDirection,
        duration_ms: u32,
    ) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        // OnStep has native pulse guide command: :Mgdnnnn#
        // where d = direction (n/s/e/w), nnnn = duration in ms (20-16399)
        if self.mount_type.is_onstep() {
            let dir_char = match direction {
                GuideDirection::North => 'n',
                GuideDirection::South => 's',
                GuideDirection::East => 'e',
                GuideDirection::West => 'w',
            };

            // Clamp duration to OnStep's valid range (20-16399ms)
            let clamped_ms = duration_ms.clamp(20, 16399);
            let cmd = format!(
                "{}{}{}#",
                commands::ONSTEP_PULSE_GUIDE_PREFIX,
                dir_char,
                clamped_ms
            );
            self.send_command_no_response(&cmd)?;

            return Ok(());
        }

        // Standard LX200: set guide rate, start move, wait, stop move
        self.send_command_no_response(commands::SET_RATE_GUIDE)?;

        let start_cmd = match direction {
            GuideDirection::North => commands::MOVE_NORTH,
            GuideDirection::South => commands::MOVE_SOUTH,
            GuideDirection::East => commands::MOVE_EAST,
            GuideDirection::West => commands::MOVE_WEST,
        };
        self.send_command_no_response(start_cmd)?;

        tokio::time::sleep(Duration::from_millis(duration_ms as u64)).await;

        let stop_cmd = match direction {
            GuideDirection::North => commands::STOP_MOVE_NORTH,
            GuideDirection::South => commands::STOP_MOVE_SOUTH,
            GuideDirection::East => commands::STOP_MOVE_EAST,
            GuideDirection::West => commands::STOP_MOVE_WEST,
        };
        self.send_command_no_response(stop_cmd)?;

        Ok(())
    }

    async fn abort_slew(&mut self) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        tracing::info!("Aborting slew");
        self.send_command_no_response(commands::STOP_SLEW)?;
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

        // OnStep uses :Te# (enable) and :Td# (disable)
        if self.mount_type.is_onstep() {
            if enabled {
                self.send_command_no_response(commands::ONSTEP_TRACK_ENABLE)?;
            } else {
                self.send_command_no_response(commands::ONSTEP_TRACK_DISABLE)?;
            }
        } else {
            // Standard LX200
            if enabled {
                self.send_command_no_response(commands::SET_TRACK_SIDEREAL)?;
            } else {
                // Standard LX200 doesn't have explicit tracking disable
                // Using stop slew as workaround (not ideal)
                self.send_command_no_response(commands::STOP_SLEW)?;
            }
        }

        *self
            .is_tracking
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = enabled;
        tracing::info!("Tracking {}", if enabled { "enabled" } else { "disabled" });

        Ok(())
    }

    async fn get_tracking(&self) -> Result<bool, NativeError> {
        if !self.is_connected() {
            return Ok(false);
        }

        // OnStep can query actual tracking status
        if self.mount_type.is_onstep() {
            if let Ok(status) = self.send_command(commands::ONSTEP_GET_STATUS) {
                let (is_tracking, _, _, _, _) = self.parse_onstep_status(&status);
                *self.is_tracking.lock().unwrap_or_else(|e| e.into_inner()) = is_tracking;
                return Ok(is_tracking);
            }
        }

        Ok(*self.is_tracking.lock().unwrap_or_else(|e| e.into_inner()))
    }

    async fn get_side_of_pier(&self) -> Result<PierSide, NativeError> {
        if !self.is_connected() {
            return Ok(PierSide::Unknown);
        }

        // OnStep can query pier side
        if self.mount_type.is_onstep() {
            if let Ok(status) = self.send_command(commands::ONSTEP_GET_STATUS) {
                let (_, _, _, _, pier_side) = self.parse_onstep_status(&status);
                return Ok(pier_side);
            }
        }

        Ok(PierSide::Unknown)
    }

    async fn get_alt_az(&self) -> Result<(f64, f64), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        let alt_response = self.send_command(commands::GET_ALT)?;
        let az_response = self.send_command(commands::GET_AZ)?;

        let alt = parse_dec(&alt_response)?;
        let az = parse_dec(&az_response)?;

        Ok((alt, az.abs()))
    }

    async fn get_sidereal_time(&self) -> Result<f64, NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        let response = self.send_command(commands::GET_SIDEREAL_TIME)?;
        parse_ra(&response)
    }

    async fn set_tracking_rate(&mut self, rate: TrackingRate) -> Result<(), NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        // OnStep and standard LX200 use the same commands for tracking rates
        let cmd = match rate {
            TrackingRate::Sidereal => commands::SET_TRACK_SIDEREAL,
            TrackingRate::Lunar => commands::SET_TRACK_LUNAR,
            TrackingRate::Solar => commands::SET_TRACK_SOLAR,
            TrackingRate::King => {
                // King rate is only supported by OnStep
                if self.mount_type.is_onstep() {
                    commands::ONSTEP_SET_RATE_KING
                } else {
                    return Err(NativeError::NotSupported);
                }
            }
            TrackingRate::Custom => {
                return Err(NativeError::NotSupported);
            }
        };

        self.send_command_no_response(cmd)?;
        *self
            .tracking_rate
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))? = rate;
        tracing::info!("Set tracking rate to {:?}", rate);

        Ok(())
    }

    async fn get_tracking_rate(&self) -> Result<TrackingRate, NativeError> {
        if !self.is_connected() {
            return Err(NativeError::NotConnected);
        }

        Ok(*self.tracking_rate.lock().unwrap_or_else(|e| e.into_inner()))
    }

    fn can_slew(&self) -> bool {
        true
    }

    fn can_sync(&self) -> bool {
        true
    }

    fn can_pulse_guide(&self) -> bool {
        true
    }

    fn can_set_tracking_rate(&self) -> bool {
        true
    }
}

// =============================================================================
// DISCOVERY
// =============================================================================

pub struct Lx200MountInfo {
    pub port: String,
    pub name: String,
    pub mount_type: Lx200MountType,
    /// Baud rate that was successful during discovery
    pub baud_rate: u32,
}

pub async fn discover_mounts() -> Result<Vec<Lx200MountInfo>, NativeError> {
    let mut mounts = Vec::new();

    let ports = serialport::available_ports()
        .map_err(|e| NativeError::SdkError(format!("Failed to enumerate ports: {}", e)))?;

    tracing::info!(
        "LX200 discovery: found {} serial ports to scan",
        ports.len()
    );

    for port_info in ports {
        let port_name = port_info.port_name.clone();

        // Log port info for debugging
        let port_type = match &port_info.port_type {
            serialport::SerialPortType::UsbPort(usb) => {
                format!(
                    "USB (VID:{:04X} PID:{:04X} {})",
                    usb.vid,
                    usb.pid,
                    usb.product.as_deref().unwrap_or("unknown")
                )
            }
            serialport::SerialPortType::PciPort => "PCI".to_string(),
            serialport::SerialPortType::BluetoothPort => "Bluetooth".to_string(),
            serialport::SerialPortType::Unknown => "Unknown".to_string(),
        };
        tracing::debug!("Checking port {} ({})", port_name, port_type);

        // Try multiple baud rates - modern mounts like Pegasus NYX use 115200
        let mut found_mount = false;
        for &baud_rate in DISCOVERY_BAUD_RATES {
            if found_mount {
                break;
            }

            tracing::debug!("Trying {} at {} baud", port_name, baud_rate);

            let result = serialport::new(&port_name, baud_rate)
                .timeout(Duration::from_millis(500))
                .open();

            match result {
                Err(e) => {
                    // Common on Windows: port is busy/locked by another app (e.g., ASCOM driver)
                    let msg = e.to_string();
                    let is_access_denied = msg.contains("Access is denied")
                        || msg.contains("access is denied")
                        || msg.contains("Permission denied")
                        || msg.contains("permission denied");

                    if is_access_denied {
                        tracing::debug!(
                            "Port {} is locked by another application (possibly ASCOM driver) - skipping LX200 scan",
                            port_name
                        );
                    } else {
                        tracing::debug!(
                            "Could not open port {} at {} baud for LX200 detection: {}",
                            port_name,
                            baud_rate,
                            msg
                        );
                    }
                    // If we can't open at any baud rate, skip to next port
                    break;
                }
                Ok(mut port) => {
                    // First, try OnStep status command to detect OnStep-based mounts (Pegasus NYX, etc.)
                    // OnStep responds to :GU# with a status string like "nNpPHT..." or similar flags
                    let is_onstep = if port
                        .write_all(commands::ONSTEP_GET_STATUS.as_bytes())
                        .is_ok()
                    {
                        let _ = port.flush();
                        let mut buf = [0u8; 32];
                        std::thread::sleep(Duration::from_millis(200));

                        if let Ok(n) = port.read(&mut buf) {
                            let response = String::from_utf8_lossy(&buf[..n]);
                            let trimmed = response.trim();
                            tracing::debug!(
                                "OnStep detection response from {} at {} baud: {:?}",
                                port_name,
                                baud_rate,
                                trimmed
                            );
                            // OnStep status ends with # and has some content
                            // Be more permissive - just check it ends with # and has reasonable length
                            trimmed.ends_with('#') && trimmed.len() >= 2 && trimmed.len() <= 30
                        } else {
                            false
                        }
                    } else {
                        false
                    };

                    if is_onstep {
                        // Get product name for display
                        let name = if port
                            .write_all(commands::GET_PRODUCT_NAME.as_bytes())
                            .is_ok()
                        {
                            let _ = port.flush();
                            let mut buf = [0u8; 64];
                            std::thread::sleep(Duration::from_millis(200));

                            if let Ok(n) = port.read(&mut buf) {
                                let response = String::from_utf8_lossy(&buf[..n]);
                                response.trim_end_matches('#').to_string()
                            } else {
                                "OnStep Mount".to_string()
                            }
                        } else {
                            "OnStep Mount".to_string()
                        };

                        // Check if it's a Pegasus NYX specifically
                        let display_name = if name.to_lowercase().contains("pegasus")
                            || name.to_lowercase().contains("nyx")
                        {
                            format!("Pegasus {} ({})", name, port_name)
                        } else if name.to_lowercase().contains("onstep") {
                            format!("{} ({})", name, port_name)
                        } else {
                            format!("OnStep: {} ({})", name, port_name)
                        };

                        mounts.push(Lx200MountInfo {
                            port: port_name.clone(),
                            name: display_name.clone(),
                            mount_type: Lx200MountType::OnStep,
                            baud_rate,
                        });
                        tracing::info!(
                            "Found OnStep mount on {} at {} baud: {}",
                            port_name,
                            baud_rate,
                            display_name
                        );
                        found_mount = true;
                        continue;
                    }

                    // Try standard LX200 detection
                    if port
                        .write_all(commands::GET_PRODUCT_NAME.as_bytes())
                        .is_ok()
                    {
                        let _ = port.flush();

                        let mut buf = [0u8; 64];
                        std::thread::sleep(Duration::from_millis(200));

                        if let Ok(n) = port.read(&mut buf) {
                            let response = String::from_utf8_lossy(&buf[..n]);
                            let name = response.trim_end_matches('#').to_string();

                            let mount_type = if name.to_lowercase().contains("meade")
                                || name.to_lowercase().contains("lx")
                            {
                                Some(Lx200MountType::Meade)
                            } else if name.to_lowercase().contains("gemini")
                                || name.to_lowercase().contains("losmandy")
                            {
                                Some(Lx200MountType::Losmandy)
                            } else if name.to_lowercase().contains("10micron") {
                                Some(Lx200MountType::TenMicron)
                            } else if !name.is_empty()
                                && name != "\0"
                                && name.chars().any(|c| c.is_alphanumeric())
                            {
                                Some(Lx200MountType::Generic)
                            } else {
                                None
                            };

                            if let Some(mount_type) = mount_type {
                                let display_name = format!("{} ({})", name, port_name);
                                mounts.push(Lx200MountInfo {
                                    port: port_name.clone(),
                                    name: display_name.clone(),
                                    mount_type,
                                    baud_rate,
                                });
                                tracing::info!(
                                    "Found LX200 mount on {} at {} baud: {}",
                                    port_name,
                                    baud_rate,
                                    display_name
                                );
                                found_mount = true;
                                continue;
                            }
                        }
                    }

                    // Fallback: try GET_RA for basic LX200 detection
                    if port.write_all(commands::GET_RA.as_bytes()).is_ok() {
                        let _ = port.flush();

                        let mut buf = [0u8; 32];
                        std::thread::sleep(Duration::from_millis(200));

                        if let Ok(n) = port.read(&mut buf) {
                            let response = String::from_utf8_lossy(&buf[..n]);
                            if response.contains(':') && response.ends_with('#') {
                                let display_name = format!("LX200 Compatible ({})", port_name);
                                mounts.push(Lx200MountInfo {
                                    port: port_name.clone(),
                                    name: display_name.clone(),
                                    mount_type: Lx200MountType::Generic,
                                    baud_rate,
                                });
                                tracing::info!(
                                    "Found generic LX200 mount on {} at {} baud",
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
                } // end Ok(mut port) =>
            } // end match
        } // end for baud_rate
    } // end for port_info

    tracing::debug!("LX200 discovery complete: found {} mounts", mounts.len());
    Ok(mounts)
}

pub fn is_available() -> bool {
    true
}
