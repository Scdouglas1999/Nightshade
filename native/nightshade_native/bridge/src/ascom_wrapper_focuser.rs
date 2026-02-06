use crate::timeout_ops::Timeouts;
use nightshade_ascom::{init_com, uninit_com, AscomFocuser};
use nightshade_native::traits::{NativeDevice, NativeError, NativeFocuser};
use nightshade_native::NativeVendor;
use std::fmt::Debug;
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

/// Connection result with device properties that can only be read after connection
#[derive(Debug)]
struct FocuserConnectInfo {
    max_position: i32,
    step_size: f64,
}

#[derive(Debug)]
enum AscomFocuserCommand {
    Connect(oneshot::Sender<Result<FocuserConnectInfo, String>>),
    Disconnect(oneshot::Sender<Result<(), String>>),
    MoveTo(i32, oneshot::Sender<Result<(), String>>),
    MoveRelative(i32, oneshot::Sender<Result<(), String>>),
    GetPosition(oneshot::Sender<Result<i32, String>>),
    IsMoving(oneshot::Sender<Result<bool, String>>),
    Halt(oneshot::Sender<Result<(), String>>),
    GetTemperature(oneshot::Sender<Result<Option<f64>, String>>),
    GetMaxPosition(oneshot::Sender<Result<i32, String>>),
    GetStepSize(oneshot::Sender<Result<f64, String>>),
    // Version query commands
    GetInterfaceVersion(oneshot::Sender<Result<i32, String>>),
    GetDriverVersion(oneshot::Sender<Result<String, String>>),
    GetDriverInfo(oneshot::Sender<Result<String, String>>),
    GetSupportedActions(oneshot::Sender<Result<Vec<String>, String>>),
}

pub struct AscomFocuserWrapper {
    id: String,
    name: String,
    sender: mpsc::Sender<AscomFocuserCommand>,
    _thread_handle: Arc<thread::JoinHandle<()>>,
    // Cache static values - these are fetched AFTER connection, not during init
    // Use interior mutability since we update them in the async connect() method
    max_position: std::sync::atomic::AtomicI32,
    step_size: std::sync::atomic::AtomicU64, // Store f64 bits as u64
}

impl Debug for AscomFocuserWrapper {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AscomFocuserWrapper")
            .field("id", &self.id)
            .field("name", &self.name)
            .finish()
    }
}

impl AscomFocuserWrapper {
    pub fn new(prog_id: String) -> Result<Self, String> {
        let (tx, mut rx) = mpsc::channel(32);
        let prog_id_clone = prog_id.clone();

        // Use a channel to signal that the thread has initialized the ASCOM object
        // Note: We do NOT fetch max_position/step_size here - they can only be read
        // reliably AFTER the device is connected. We fetch them in the Connect handler.
        let (init_tx, init_rx) = std::sync::mpsc::channel();

        let handle = thread::spawn(move || {
            // Initialize COM as STA on this thread
            if let Err(e) = init_com() {
                let _ = init_tx.send(Err(format!("Failed to init COM: {}", e)));
                return;
            }

            let mut focuser = match AscomFocuser::new(&prog_id_clone) {
                Ok(f) => f,
                Err(e) => {
                    let _ = init_tx.send(Err(format!("Failed to create ASCOM focuser: {}", e)));
                    uninit_com();
                    return;
                }
            };

            // Signal successful initialization (we don't fetch properties here anymore)
            let _ = init_tx.send(Ok(()));

            while let Some(cmd) = rx.blocking_recv() {
                match cmd {
                    AscomFocuserCommand::Connect(reply) => {
                        // Connect first, then fetch properties that require connection
                        let result = focuser.connect().map_err(|e| e.to_string()).and_then(|()| {
                            // Fetch static properties AFTER connection
                            let max_step = focuser
                                .max_step()
                                .map_err(|e| {
                                    tracing::warn!(
                                        "Failed to get focuser max_step after connect: {}",
                                        e
                                    );
                                    e.to_string()
                                })
                                .unwrap_or(50000); // Reasonable default if query fails
                            let step_size = focuser
                                .step_size()
                                .map_err(|e| {
                                    tracing::warn!(
                                        "Failed to get focuser step_size after connect: {}",
                                        e
                                    );
                                    e.to_string()
                                })
                                .unwrap_or(1.0);

                            Ok(FocuserConnectInfo {
                                max_position: max_step,
                                step_size,
                            })
                        });
                        let _ = reply.send(result);
                    }
                    AscomFocuserCommand::Disconnect(reply) => {
                        let _ = reply.send(focuser.disconnect().map_err(|e| e.to_string()));
                    }
                    AscomFocuserCommand::MoveTo(pos, reply) => {
                        let _ = reply.send(focuser.move_to(pos).map_err(|e| e.to_string()));
                    }
                    AscomFocuserCommand::MoveRelative(steps, reply) => {
                        // ASCOM doesn't have move_relative, so we need current pos + steps
                        // But we can't easily do that atomically here without potentially blocking.
                        // Actually we can: get pos, add steps, move to.
                        let res = (|| -> Result<(), String> {
                            let current = focuser.position()?;
                            focuser.move_to(current + steps)
                        })();
                        let _ = reply.send(res.map_err(|e| e.to_string()));
                    }
                    AscomFocuserCommand::GetPosition(reply) => {
                        let _ = reply.send(focuser.position().map_err(|e| e.to_string()));
                    }
                    AscomFocuserCommand::IsMoving(reply) => {
                        let _ = reply.send(focuser.is_moving().map_err(|e| e.to_string()));
                    }
                    AscomFocuserCommand::Halt(reply) => {
                        let _ = reply.send(focuser.halt().map_err(|e| e.to_string()));
                    }
                    AscomFocuserCommand::GetTemperature(reply) => {
                        // Check if temp comp available or just try getting temp
                        // Some drivers might error if not available
                        let res = focuser.temperature().map(Some).or_else(|_| Ok(None));
                        let _ = reply.send(res);
                    }
                    AscomFocuserCommand::GetMaxPosition(reply) => {
                        let _ = reply.send(focuser.max_step().map_err(|e| e.to_string()));
                    }
                    AscomFocuserCommand::GetStepSize(reply) => {
                        let _ = reply.send(focuser.step_size().map_err(|e| e.to_string()));
                    }
                    AscomFocuserCommand::GetInterfaceVersion(reply) => {
                        let _ = reply.send(focuser.interface_version());
                    }
                    AscomFocuserCommand::GetDriverVersion(reply) => {
                        let _ = reply.send(focuser.driver_version());
                    }
                    AscomFocuserCommand::GetDriverInfo(reply) => {
                        let _ = reply.send(focuser.driver_info());
                    }
                    AscomFocuserCommand::GetSupportedActions(reply) => {
                        let _ = reply.send(focuser.supported_actions());
                    }
                }
            }

            uninit_com();
        });

        // Wait for initialization (just confirms thread started OK, not properties)
        init_rx
            .recv()
            .map_err(|e| format!("Failed to receive init result: {}", e))??;

        Ok(Self {
            id: prog_id.clone(),
            name: prog_id,
            sender: tx,
            _thread_handle: Arc::new(handle),
            // Initialize with defaults - real values are fetched after connect()
            max_position: AtomicI32::new(50000),
            step_size: AtomicU64::new(1.0f64.to_bits()),
        })
    }

    /// Helper to receive a response with a timeout
    async fn recv_with_timeout<T>(
        rx: oneshot::Receiver<Result<T, String>>,
        timeout: Duration,
        operation: &str,
    ) -> Result<T, NativeError> {
        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(result)) => result.map_err(|e| NativeError::SdkError(e)),
            Ok(Err(_recv_err)) => Err(NativeError::Unknown(format!(
                "Worker thread dead during {}",
                operation
            ))),
            Err(_elapsed) => Err(NativeError::Timeout(format!(
                "Focuser {} timed out after {:?}",
                operation, timeout
            ))),
        }
    }

    async fn fetch_max_position(&self) -> Result<i32, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::GetMaxPosition(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "get_max_position").await
    }

    async fn fetch_step_size(&self) -> Result<f64, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::GetStepSize(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "get_step_size").await
    }
}

#[async_trait::async_trait]
impl NativeDevice for AscomFocuserWrapper {
    fn id(&self) -> &str {
        &self.id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn vendor(&self) -> NativeVendor {
        NativeVendor::Ascom
    }

    fn is_connected(&self) -> bool {
        true // Placeholder, ideally we'd track this state
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::Connect(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        let info = Self::recv_with_timeout(rx, Timeouts::connection(), "connect").await?;

        // Update cached values with real values from the connected device
        self.max_position.store(info.max_position, Ordering::SeqCst);
        self.step_size
            .store(info.step_size.to_bits(), Ordering::SeqCst);

        tracing::info!(
            "Focuser connected: max_position={}, step_size={}",
            info.max_position,
            info.step_size
        );

        match self.fetch_max_position().await {
            Ok(max_position) => {
                self.max_position.store(max_position, Ordering::SeqCst);
            }
            Err(err) => {
                tracing::warn!(
                    "Failed to refresh focuser max_position after connect: {}",
                    err
                );
            }
        }

        match self.fetch_step_size().await {
            Ok(step_size) => {
                self.step_size.store(step_size.to_bits(), Ordering::SeqCst);
            }
            Err(err) => {
                tracing::warn!("Failed to refresh focuser step_size after connect: {}", err);
            }
        }

        Ok(())
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::Disconnect(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::connection(), "disconnect").await
    }
}

#[async_trait::async_trait]
impl NativeFocuser for AscomFocuserWrapper {
    async fn move_to(&mut self, position: i32) -> Result<(), NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::MoveTo(position, tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        // Focuser moves can take a long time
        Self::recv_with_timeout(rx, Timeouts::focuser_move(), "move_to").await
    }

    async fn move_relative(&mut self, steps: i32) -> Result<(), NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::MoveRelative(steps, tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::focuser_move(), "move_relative").await
    }

    async fn get_position(&self) -> Result<i32, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::GetPosition(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "get_position").await
    }

    async fn is_moving(&self) -> Result<bool, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::IsMoving(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "is_moving").await
    }

    async fn halt(&mut self) -> Result<(), NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::Halt(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_write(), "halt").await
    }

    async fn get_temperature(&self) -> Result<Option<f64>, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::GetTemperature(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "get_temperature").await
    }

    fn get_max_position(&self) -> i32 {
        self.max_position.load(Ordering::SeqCst)
    }

    fn get_step_size(&self) -> f64 {
        f64::from_bits(self.step_size.load(Ordering::SeqCst))
    }
}

// Version query methods
impl AscomFocuserWrapper {
    /// Get the ASCOM interface version number
    pub async fn interface_version(&self) -> Result<i32, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::GetInterfaceVersion(tx))
            .await
            .map_err(|_| NativeError::Unknown("Worker thread dead".to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "interface_version").await
    }

    /// Get the driver version string
    pub async fn driver_version(&self) -> Result<String, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::GetDriverVersion(tx))
            .await
            .map_err(|_| NativeError::Unknown("Worker thread dead".to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "driver_version").await
    }

    /// Get the driver info/description
    pub async fn driver_info(&self) -> Result<String, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::GetDriverInfo(tx))
            .await
            .map_err(|_| NativeError::Unknown("Worker thread dead".to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "driver_info").await
    }

    /// Get the list of supported actions
    pub async fn supported_actions(&self) -> Result<Vec<String>, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFocuserCommand::GetSupportedActions(tx))
            .await
            .map_err(|_| NativeError::Unknown("Worker thread dead".to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "supported_actions").await
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn build_test_wrapper<F>(handler: F) -> AscomFocuserWrapper
    where
        F: FnMut(AscomFocuserCommand) -> bool + Send + 'static,
    {
        let (tx, mut rx) = mpsc::channel(8);
        let handle = thread::spawn(move || {
            let mut handler = handler;
            while let Some(cmd) = rx.blocking_recv() {
                if handler(cmd) {
                    break;
                }
            }
        });

        AscomFocuserWrapper {
            id: "test-focuser".to_string(),
            name: "Test Focuser".to_string(),
            sender: tx,
            _thread_handle: Arc::new(handle),
            max_position: AtomicI32::new(0),
            step_size: AtomicU64::new(1.0f64.to_bits()),
        }
    }

    #[tokio::test]
    async fn test_connect_refreshes_cached_limits_from_commands() {
        let mut wrapper = build_test_wrapper(|cmd| {
            match cmd {
                AscomFocuserCommand::Connect(reply) => {
                    let info = FocuserConnectInfo {
                        max_position: 1000,
                        step_size: 1.0,
                    };
                    let _ = reply.send(Ok(info));
                }
                AscomFocuserCommand::GetMaxPosition(reply) => {
                    let _ = reply.send(Ok(1200));
                }
                AscomFocuserCommand::GetStepSize(reply) => {
                    let _ = reply.send(Ok(2.5));
                }
                _ => {}
            }
            false
        });

        wrapper.connect().await.expect("connect");
        assert_eq!(wrapper.get_max_position(), 1200);
        assert!((wrapper.get_step_size() - 2.5).abs() < f64::EPSILON);
    }
}
