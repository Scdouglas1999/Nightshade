use crate::timeout_ops::Timeouts;
use nightshade_ascom::{init_com, uninit_com, AscomRotator};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

enum AscomRotatorCommand {
    Connect(oneshot::Sender<Result<(), String>>),
    Disconnect(oneshot::Sender<Result<(), String>>),
    Position(oneshot::Sender<Result<f64, String>>),
    MoveAbsolute(f64, oneshot::Sender<Result<(), String>>),
    Halt(oneshot::Sender<Result<(), String>>),
    IsMoving(oneshot::Sender<Result<bool, String>>),
}

pub struct AscomRotatorWrapper {
    sender: mpsc::Sender<AscomRotatorCommand>,
    _thread_handle: Arc<thread::JoinHandle<()>>,
    connected: AtomicBool,
}

impl AscomRotatorWrapper {
    pub fn new(prog_id: String) -> Result<Self, String> {
        let (tx, mut rx) = mpsc::channel(32);
        let (init_tx, init_rx) = std::sync::mpsc::channel();
        let prog_id_clone = prog_id.clone();

        let handle = thread::spawn(move || {
            if let Err(error) = init_com() {
                let _ = init_tx.send(Err(format!("Failed to init COM: {}", error)));
                return;
            }

            let mut rotator = match AscomRotator::new(&prog_id_clone) {
                Ok(rotator) => rotator,
                Err(error) => {
                    let _ = init_tx.send(Err(format!("Failed to create ASCOM rotator: {}", error)));
                    uninit_com();
                    return;
                }
            };

            let _ = init_tx.send(Ok(()));

            while let Some(command) = rx.blocking_recv() {
                match command {
                    AscomRotatorCommand::Connect(reply) => {
                        let _ = reply.send(rotator.connect());
                    }
                    AscomRotatorCommand::Disconnect(reply) => {
                        let _ = reply.send(rotator.disconnect());
                    }
                    AscomRotatorCommand::Position(reply) => {
                        let _ = reply.send(rotator.position());
                    }
                    AscomRotatorCommand::MoveAbsolute(position, reply) => {
                        let _ = reply.send(rotator.move_absolute(position));
                    }
                    AscomRotatorCommand::Halt(reply) => {
                        let _ = reply.send(rotator.halt());
                    }
                    AscomRotatorCommand::IsMoving(reply) => {
                        let _ = reply.send(rotator.is_moving());
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
                "Rotator {} timed out after {:?}",
                operation, timeout
            )),
        }
    }

    pub async fn connect(&mut self) -> Result<(), String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomRotatorCommand::Connect(tx))
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
            .send(AscomRotatorCommand::Disconnect(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        let result = Self::recv_with_timeout(rx, Timeouts::connection(), "disconnect").await;
        if result.is_ok() {
            self.connected.store(false, Ordering::SeqCst);
        }
        result
    }

    pub async fn position(&self) -> Result<f64, String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomRotatorCommand::Position(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "position").await
    }

    pub async fn move_absolute(&self, position: f64) -> Result<(), String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomRotatorCommand::MoveAbsolute(position, tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::rotator_move(), "move_absolute").await
    }

    pub async fn halt(&self) -> Result<(), String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomRotatorCommand::Halt(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_write(), "halt").await
    }

    pub async fn is_moving(&self) -> Result<bool, String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomRotatorCommand::IsMoving(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), "is_moving").await
    }
}
