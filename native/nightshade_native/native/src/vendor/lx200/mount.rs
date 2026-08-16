//! `Lx200Mount` state, inherent helpers and `NativeDevice`.

use super::*;

pub struct Lx200Mount {
    pub(crate) device_id: String,
    pub(crate) name: String,
    pub(crate) port_name: String,
    pub(crate) baud_rate: u32,
    pub(crate) mount_type: Lx200MountType,
    pub(crate) serial_port: Mutex<Option<Box<dyn serialport::SerialPort + Send>>>,
    pub(crate) connected: Mutex<bool>,
    pub(crate) is_tracking: Mutex<bool>,
    pub(crate) is_slewing: Mutex<bool>,
    pub(crate) tracking_rate: Mutex<TrackingRate>,
    pub(crate) product_name: Mutex<String>,
    /// In-memory mirror of the persisted park flag. `None` = no canonical
    /// record exists for this device yet; we return `NotSupported` on
    /// is_parked queries until park/unpark has been called at least once
    /// or telemetry confirms a state.
    pub(crate) park_state: Mutex<Option<bool>>,
    /// Cancellation channel for the standard-LX200 pulse-guide sleep.
    /// Notified by `abort_slew` so the start/stop pair
    /// terminates immediately instead of waiting out the full duration.
    pub(crate) pulse_guide_cancel: Arc<Notify>,
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

        // Eagerly hydrate the local park flag from disk. A missing or
        // unreadable cache means "no canonical state yet" — is_parked()
        // will return NotSupported until park() or unpark() has run at
        // least once (or telemetry confirms a state). We log read errors
        // because silent fallbacks hide bugs.
        let park_state_initial: Option<bool> = match read_persisted_park_state(&device_id) {
            Ok(state) => state,
            Err(e) => {
                tracing::warn!(
                    "LX200 park-state cache unreadable for {}: {} (treating as unknown)",
                    device_id,
                    e
                );
                None
            }
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
            park_state: Mutex::new(park_state_initial),
            pulse_guide_cancel: Arc::new(Notify::new()),
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
    pub(crate) fn parse_onstep_status(&self, status: &str) -> (bool, bool, bool, bool, PierSide) {
        parse_onstep_status_fields(status)
    }

    pub(crate) fn send_command(&self, command: &str) -> Result<String, NativeError> {
        let mut port_guard = self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))?;
        let port = port_guard.as_mut().ok_or(NativeError::NotConnected)?;

        port.write_all(command.as_bytes())
            .map_err(NativeError::Io)?;
        port.flush().map_err(NativeError::Io)?;

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

    pub(crate) fn send_command_bool(&self, command: &str) -> Result<bool, NativeError> {
        let mut port_guard = self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))?;
        let port = port_guard.as_mut().ok_or(NativeError::NotConnected)?;

        port.write_all(command.as_bytes())
            .map_err(NativeError::Io)?;
        port.flush().map_err(NativeError::Io)?;

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

    /// Wait up to `duration_ms` or until the pulse-guide cancel is
    /// notified, whichever comes first. Returns `true` if cancelled.
    ///
    /// Separate from `pulse_guide` so the cancellation behaviour is
    /// unit-testable without a serial port.
    pub(crate) async fn pulse_guide_wait(&self, duration_ms: u32) -> bool {
        let cancel = Arc::clone(&self.pulse_guide_cancel);
        let sleep = tokio::time::sleep(Duration::from_millis(duration_ms as u64));
        tokio::select! {
            _ = sleep => false,
            _ = cancel.notified() => true,
        }
    }

    pub(crate) fn send_command_no_response(&self, command: &str) -> Result<(), NativeError> {
        let mut port_guard = self
            .serial_port
            .lock()
            .map_err(|_| NativeError::SdkError("Lock poisoned".into()))?;
        let port = port_guard.as_mut().ok_or(NativeError::NotConnected)?;

        port.write_all(command.as_bytes())
            .map_err(NativeError::Io)?;
        port.flush().map_err(NativeError::Io)?;

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
                // Fall back to a :GR# probe. If that ALSO times out the mount
                // isn't really talking to us, so bail — but first release the
                // serial port we opened above. Otherwise the live handle lingers
                // in `self.serial_port` with `connected` still false, so a later
                // `disconnect()` no-ops (it early-returns on `!is_connected()`),
                // leaking the COM port and locking out every subsequent connect
                // attempt (native OR ASCOM) until the process restarts.
                if let Err(e) = self.send_command(commands::GET_RA) {
                    if let Ok(mut guard) = self.serial_port.lock() {
                        *guard = None;
                    }
                    return Err(e);
                }
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

        // Halt any motion before we drop the port. The port is released either way —
        // holding it open would strand the mount — but a mount that did not take the
        // halt keeps slewing with nothing left connected to stop it, so the failure
        // is reported instead of dropped.
        if let Err(e) = self.send_command_no_response(commands::STOP_SLEW) {
            tracing::error!(
                "LX200 {}: stop-slew ({}) failed while disconnecting: {}. The mount may still be moving — stop it at the hand controller.",
                self.device_id,
                commands::STOP_SLEW,
                e
            );
        }

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
