use crate::timeout_ops::Timeouts;
use nightshade_ascom::{init_com, uninit_com, AscomSafetyMonitor};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

enum AscomSafetyMonitorCommand {
    Connect(oneshot::Sender<Result<(), String>>),
    Disconnect(oneshot::Sender<Result<(), String>>),
    IsSafe(oneshot::Sender<Result<bool, String>>),
    // ASCOM-Common metadata query commands. Mirrors the four
    // `InterfaceVersion` / `DriverVersion` / `DriverInfo` /
    // `SupportedActions` properties common to every ASCOM driver and is
    // consumed by `DeviceCommonMetadata` via `dispatch::ascom_device_common`.
    GetInterfaceVersion(oneshot::Sender<Result<i32, String>>),
    GetDriverVersion(oneshot::Sender<Result<String, String>>),
    GetDriverInfo(oneshot::Sender<Result<String, String>>),
    GetSupportedActions(oneshot::Sender<Result<Vec<String>, String>>),
}

pub struct AscomSafetyMonitorWrapper {
    sender: mpsc::Sender<AscomSafetyMonitorCommand>,
    _thread_handle: Arc<thread::JoinHandle<()>>,
    connected: AtomicBool,
}

impl AscomSafetyMonitorWrapper {
    pub fn new(prog_id: String) -> Result<Self, String> {
        let (tx, mut rx) = mpsc::channel(32);
        let (init_tx, init_rx) = std::sync::mpsc::channel();
        let prog_id_clone = prog_id.clone();

        let handle = thread::spawn(move || {
            if let Err(error) = init_com() {
                let _ = init_tx.send(Err(format!("Failed to init COM: {}", error)));
                return;
            }

            let mut safety_monitor = match AscomSafetyMonitor::new(&prog_id_clone) {
                Ok(safety_monitor) => safety_monitor,
                Err(error) => {
                    let _ = init_tx.send(Err(format!(
                        "Failed to create ASCOM safety monitor: {}",
                        error
                    )));
                    uninit_com();
                    return;
                }
            };

            let _ = init_tx.send(Ok(()));

            while let Some(command) = crate::ascom_wrapper::pump_blocking_recv(&mut rx) {
                match command {
                    AscomSafetyMonitorCommand::Connect(reply) => {
                        let _ = reply.send(safety_monitor.connect());
                    }
                    AscomSafetyMonitorCommand::Disconnect(reply) => {
                        let _ = reply.send(safety_monitor.disconnect());
                    }
                    AscomSafetyMonitorCommand::IsSafe(reply) => {
                        let _ = reply.send(safety_monitor.is_safe());
                    }
                    AscomSafetyMonitorCommand::GetInterfaceVersion(reply) => {
                        let _ = reply.send(safety_monitor.interface_version());
                    }
                    AscomSafetyMonitorCommand::GetDriverVersion(reply) => {
                        let _ = reply.send(safety_monitor.driver_version());
                    }
                    AscomSafetyMonitorCommand::GetDriverInfo(reply) => {
                        let _ = reply.send(safety_monitor.driver_info());
                    }
                    AscomSafetyMonitorCommand::GetSupportedActions(reply) => {
                        let _ = reply.send(safety_monitor.supported_actions());
                    }
                }
            }

            uninit_com();
        });

        init_rx
            .recv()
            .map_err(|error| format!("Failed to receive init result: {}", error))??;

        Ok(Self {
            sender: tx,
            _thread_handle: Arc::new(handle),
            connected: AtomicBool::new(false),
        })
    }

    async fn recv_with_timeout<T>(
        rx: oneshot::Receiver<Result<T, String>>,
        timeout: Duration,
        operation: &str,
    ) -> Result<T, String> {
        match tokio::time::timeout(timeout, rx).await {
            Ok(Ok(result)) => result,
            Ok(Err(_)) => Err(format!("Worker thread dead during {}", operation)),
            Err(_) => Err(format!(
                "Safety monitor {} timed out after {:?}",
                operation, timeout
            )),
        }
    }

    pub async fn connect(&mut self) -> Result<(), String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomSafetyMonitorCommand::Connect(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        let result = Self::recv_with_timeout(rx, Timeouts::connection(), "connect").await;
        if result.is_ok() {
            self.connected.store(true, Ordering::SeqCst);
        }
        result
    }

    pub async fn disconnect(&mut self) -> Result<(), String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomSafetyMonitorCommand::Disconnect(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        let result = Self::recv_with_timeout(rx, Timeouts::connection(), "disconnect").await;
        if result.is_ok() {
            self.connected.store(false, Ordering::SeqCst);
        }
        result
    }

    pub async fn is_safe(&self) -> Result<bool, String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomSafetyMonitorCommand::IsSafe(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "is_safe").await
    }

    /// Returns the ASCOM `InterfaceVersion` integer (ASCOM-Common §IAscomDriverV1).
    pub async fn interface_version(&self) -> Result<i32, String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomSafetyMonitorCommand::GetInterfaceVersion(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "interface_version").await
    }

    /// Returns the ASCOM `DriverVersion` free-form vendor version string (ASCOM-Common §IAscomDriverV1).
    pub async fn driver_version(&self) -> Result<String, String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomSafetyMonitorCommand::GetDriverVersion(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "driver_version").await
    }

    /// Returns the ASCOM `DriverInfo` vendor description string (ASCOM-Common §IAscomDriverV1).
    pub async fn driver_info(&self) -> Result<String, String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomSafetyMonitorCommand::GetDriverInfo(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "driver_info").await
    }

    /// Returns the list of custom action names from ASCOM `SupportedActions` (ASCOM-Common §ISupportedActions, V2+ optional).
    pub async fn supported_actions(&self) -> Result<Vec<String>, String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomSafetyMonitorCommand::GetSupportedActions(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "supported_actions").await
    }
}

// =============================================================================
// Tests
// =============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    fn build_test_wrapper<F>(handler: F) -> AscomSafetyMonitorWrapper
    where
        F: FnMut(AscomSafetyMonitorCommand) -> bool + Send + 'static,
    {
        let (tx, mut rx) = mpsc::channel(8);
        let handle = thread::spawn(move || {
            let mut handler = handler;
            while let Some(cmd) = crate::ascom_wrapper::pump_blocking_recv(&mut rx) {
                if handler(cmd) {
                    break;
                }
            }
        });
        AscomSafetyMonitorWrapper {
            sender: tx,
            _thread_handle: Arc::new(handle),
            connected: AtomicBool::new(false),
        }
    }

    #[tokio::test]
    async fn interface_version_returns_worker_value() {
        let wrapper = build_test_wrapper(|cmd| {
            if let AscomSafetyMonitorCommand::GetInterfaceVersion(reply) = cmd {
                let _ = reply.send(Ok(1));
            }
            false
        });
        assert_eq!(wrapper.interface_version().await.expect("ok"), 1);
    }

    #[tokio::test]
    async fn driver_version_returns_worker_value() {
        let wrapper = build_test_wrapper(|cmd| {
            if let AscomSafetyMonitorCommand::GetDriverVersion(reply) = cmd {
                let _ = reply.send(Ok("4.5".to_string()));
            }
            false
        });
        assert_eq!(wrapper.driver_version().await.expect("ok"), "4.5");
    }

    #[tokio::test]
    async fn driver_info_returns_worker_value() {
        let wrapper = build_test_wrapper(|cmd| {
            if let AscomSafetyMonitorCommand::GetDriverInfo(reply) = cmd {
                let _ = reply.send(Ok("Acme Safety Monitor".to_string()));
            }
            false
        });
        assert_eq!(
            wrapper.driver_info().await.expect("ok"),
            "Acme Safety Monitor"
        );
    }

    #[tokio::test]
    async fn supported_actions_returns_worker_value() {
        let wrapper = build_test_wrapper(|cmd| {
            if let AscomSafetyMonitorCommand::GetSupportedActions(reply) = cmd {
                let _ = reply.send(Ok(vec!["RaiseAlarm".to_string()]));
            }
            false
        });
        let actions = wrapper.supported_actions().await.expect("ok");
        assert_eq!(actions, vec!["RaiseAlarm".to_string()]);
    }

    #[tokio::test]
    async fn supported_actions_propagates_property_not_implemented_error() {
        // ASCOM 1.x drivers without `ISupportedActions` raise
        // `PropertyNotImplementedException`. The wrapper passes the error
        // through unchanged; `fetch_api_version` is responsible for the
        // documented silent-fallback-to-empty-Vec policy at the dispatch layer.
        let wrapper = build_test_wrapper(|cmd| {
            if let AscomSafetyMonitorCommand::GetSupportedActions(reply) = cmd {
                let _ = reply.send(Err("PropertyNotImplemented".to_string()));
            }
            false
        });
        assert!(wrapper.supported_actions().await.is_err());
    }
}
