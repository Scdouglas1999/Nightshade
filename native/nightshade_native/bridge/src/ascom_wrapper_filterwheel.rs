use crate::timeout_ops::Timeouts;
use nightshade_ascom::{init_com, uninit_com, AscomFilterWheel};
use nightshade_native::traits::{NativeDevice, NativeError, NativeFilterWheel};
use nightshade_native::NativeVendor;
use std::fmt::Debug;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

#[derive(Debug)]
enum AscomFilterWheelCommand {
    Connect(oneshot::Sender<Result<i32, String>>), // Returns filter count on success
    Disconnect(oneshot::Sender<Result<(), String>>),
    SetPosition(i32, oneshot::Sender<Result<(), String>>),
    GetPosition(oneshot::Sender<Result<i32, String>>),
    GetNames(oneshot::Sender<Result<Vec<String>, String>>),
    // Version query commands
    GetInterfaceVersion(oneshot::Sender<Result<i32, String>>),
    GetDriverVersion(oneshot::Sender<Result<String, String>>),
    GetDriverInfo(oneshot::Sender<Result<String, String>>),
    GetSupportedActions(oneshot::Sender<Result<Vec<String>, String>>),
}

pub struct AscomFilterWheelWrapper {
    id: String,
    name: String,
    sender: mpsc::Sender<AscomFilterWheelCommand>,
    _thread_handle: Arc<thread::JoinHandle<()>>,
    connected: AtomicBool,
    // Cache filter count - updated after connect when we can actually read device properties.
    filter_count: AtomicI32,
}

impl Debug for AscomFilterWheelWrapper {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AscomFilterWheelWrapper")
            .field("id", &self.id)
            .field("name", &self.name)
            .finish()
    }
}

impl AscomFilterWheelWrapper {
    pub fn new(prog_id: String) -> Result<Self, String> {
        let (tx, mut rx) = mpsc::channel(32);
        let prog_id_clone = prog_id.clone();

        let (init_tx, init_rx) = std::sync::mpsc::channel();

        let handle = thread::spawn(move || {
            // Initialize COM as STA on this thread
            if let Err(e) = init_com() {
                let _ = init_tx.send(Err(format!("Failed to init COM: {}", e)));
                return;
            }

            let mut fw = match AscomFilterWheel::new(&prog_id_clone) {
                Ok(f) => f,
                Err(e) => {
                    let _ =
                        init_tx.send(Err(format!("Failed to create ASCOM filter wheel: {}", e)));
                    uninit_com();
                    return;
                }
            };

            // Don't read names() here - the device isn't connected yet.
            // Filter count will be updated after connect() when we can actually
            // read device properties.
            let _ = init_tx.send(Ok(()));
            tracing::info!(
                "ASCOM FilterWheel COM object created for: {}",
                prog_id_clone
            );

            while let Some(cmd) = rx.blocking_recv() {
                match cmd {
                    AscomFilterWheelCommand::Connect(reply) => {
                        let result = fw.connect().map_err(|e| e.to_string());
                        let _ = reply.send(result.and_then(|()| {
                            // Now that we're connected, read filter names to get count
                            let names = fw.names().unwrap_or_default();
                            let count = names.len() as i32;
                            tracing::info!(
                                "ASCOM FilterWheel connected with {} filters: {:?}",
                                count,
                                names
                            );

                            // Give the ASCOM driver a moment to settle, then
                            // read initial position for diagnostic logging.
                            std::thread::sleep(std::time::Duration::from_millis(500));
                            match fw.position() {
                                Ok(pos) => tracing::info!(
                                    "[ASCOM FW] Post-connect initial position read: {}",
                                    pos
                                ),
                                Err(e) => tracing::warn!(
                                    "[ASCOM FW] Post-connect position read failed: {}",
                                    e
                                ),
                            }

                            Ok(count)
                        }));
                    }
                    AscomFilterWheelCommand::Disconnect(reply) => {
                        let _ = reply.send(fw.disconnect().map_err(|e| e.to_string()));
                    }
                    AscomFilterWheelCommand::SetPosition(pos, reply) => {
                        let _ = reply.send(fw.set_position(pos).map_err(|e| e.to_string()));
                    }
                    AscomFilterWheelCommand::GetPosition(reply) => {
                        let result = fw.position().map_err(|e| e.to_string());
                        match &result {
                            Ok(pos) => {
                                tracing::info!("[ASCOM FW] GetPosition returned position={}", pos)
                            }
                            Err(e) => tracing::error!("[ASCOM FW] GetPosition failed: {}", e),
                        }
                        let _ = reply.send(result);
                    }
                    AscomFilterWheelCommand::GetNames(reply) => {
                        let result = fw.names();
                        match &result {
                            Ok(names) => tracing::info!(
                                "ASCOM FilterWheel GetNames returned {} filters: {:?}",
                                names.len(),
                                names
                            ),
                            Err(e) => tracing::error!("ASCOM FilterWheel GetNames failed: {}", e),
                        }
                        let _ = reply.send(result.map_err(|e| e.to_string()));
                    }
                    AscomFilterWheelCommand::GetInterfaceVersion(reply) => {
                        let _ = reply.send(fw.interface_version());
                    }
                    AscomFilterWheelCommand::GetDriverVersion(reply) => {
                        let _ = reply.send(fw.driver_version());
                    }
                    AscomFilterWheelCommand::GetDriverInfo(reply) => {
                        let _ = reply.send(fw.driver_info());
                    }
                    AscomFilterWheelCommand::GetSupportedActions(reply) => {
                        let _ = reply.send(fw.supported_actions());
                    }
                }
            }

            // Why: COM teardown ordering — release the typed `AscomFilterWheel`
            // (which holds an IDispatch) BEFORE `uninit_com()`. The Drop on
            // `AscomDeviceConnection` is intentionally a no-op so this is the
            // only correct location to issue the final disconnect.
            if let Err(e) = fw.disconnect() {
                tracing::warn!(
                    "ASCOM filter wheel STA-worker shutdown disconnect failed: {}",
                    e
                );
            }
            drop(fw);
            uninit_com();
        });

        // Wait for initialization
        init_rx
            .recv()
            .map_err(|e| format!("Failed to receive init result: {}", e))??;

        Ok(Self {
            id: prog_id.clone(),
            name: prog_id,
            sender: tx,
            _thread_handle: Arc::new(handle),
            connected: AtomicBool::new(false),
            filter_count: AtomicI32::new(0),
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
                "FilterWheel {} timed out after {:?}",
                operation, timeout
            ))),
        }
    }
}

#[async_trait::async_trait]
impl NativeDevice for AscomFilterWheelWrapper {
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
        self.connected.load(Ordering::SeqCst)
    }

    async fn connect(&mut self) -> Result<(), NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::Connect(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        let result: Result<i32, NativeError> =
            Self::recv_with_timeout(rx, Timeouts::connection(), "connect").await;
        match result {
            Ok(count) => {
                self.connected.store(true, Ordering::SeqCst);
                self.filter_count.store(count, Ordering::SeqCst);
                Ok(())
            }
            Err(e) => Err(e),
        }
    }

    async fn disconnect(&mut self) -> Result<(), NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::Disconnect(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        let result = Self::recv_with_timeout(rx, Timeouts::connection(), "disconnect").await;
        if result.is_ok() {
            self.connected.store(false, Ordering::SeqCst);
        }
        result
    }
}

#[async_trait::async_trait]
impl NativeFilterWheel for AscomFilterWheelWrapper {
    async fn move_to_position(&mut self, position: i32) -> Result<(), NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::SetPosition(position, tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        // Filter wheel rotation can take time
        Self::recv_with_timeout(rx, Timeouts::filter_wheel(), "move_to_position").await
    }

    async fn get_position(&self) -> Result<i32, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::GetPosition(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "get_position").await
    }

    async fn is_moving(&self) -> Result<bool, NativeError> {
        // ASCOM Position returns -1 if moving
        let pos = self.get_position().await?;
        Ok(pos == -1)
    }

    fn get_filter_count(&self) -> i32 {
        self.filter_count.load(Ordering::SeqCst)
    }

    async fn get_filter_names(&self) -> Result<Vec<String>, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::GetNames(tx))
            .await
            .map_err(|e| NativeError::SdkError(e.to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "get_filter_names").await
    }

    async fn set_filter_name(&mut self, _position: i32, _name: String) -> Result<(), NativeError> {
        Err(NativeError::NotSupported)
    }
}

// Version query methods
impl AscomFilterWheelWrapper {
    /// Get the ASCOM interface version number
    pub async fn interface_version(&self) -> Result<i32, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::GetInterfaceVersion(tx))
            .await
            .map_err(|_| NativeError::Unknown("Worker thread dead".to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "interface_version").await
    }

    /// Get the driver version string
    pub async fn driver_version(&self) -> Result<String, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::GetDriverVersion(tx))
            .await
            .map_err(|_| NativeError::Unknown("Worker thread dead".to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "driver_version").await
    }

    /// Get the driver info/description
    pub async fn driver_info(&self) -> Result<String, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::GetDriverInfo(tx))
            .await
            .map_err(|_| NativeError::Unknown("Worker thread dead".to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "driver_info").await
    }

    /// Get the list of supported actions
    pub async fn supported_actions(&self) -> Result<Vec<String>, NativeError> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomFilterWheelCommand::GetSupportedActions(tx))
            .await
            .map_err(|_| NativeError::Unknown("Worker thread dead".to_string()))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "supported_actions").await
    }
}
