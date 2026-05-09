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

            while let Some(command) = rx.blocking_recv() {
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
}
