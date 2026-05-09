use crate::timeout_ops::Timeouts;
use nightshade_ascom::{init_com, uninit_com, AscomObservingConditions};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

enum AscomWeatherCommand {
    Connect(oneshot::Sender<Result<(), String>>),
    Disconnect(oneshot::Sender<Result<(), String>>),
    Temperature(oneshot::Sender<Result<f64, String>>),
    Humidity(oneshot::Sender<Result<f64, String>>),
    Pressure(oneshot::Sender<Result<f64, String>>),
    CloudCover(oneshot::Sender<Result<f64, String>>),
    DewPoint(oneshot::Sender<Result<f64, String>>),
    WindSpeed(oneshot::Sender<Result<f64, String>>),
    WindDirection(oneshot::Sender<Result<f64, String>>),
    SkyQuality(oneshot::Sender<Result<f64, String>>),
    SkyTemperature(oneshot::Sender<Result<f64, String>>),
    RainRate(oneshot::Sender<Result<f64, String>>),
}

pub struct AscomObservingConditionsWrapper {
    sender: mpsc::Sender<AscomWeatherCommand>,
    _thread_handle: Arc<thread::JoinHandle<()>>,
    connected: AtomicBool,
}

impl AscomObservingConditionsWrapper {
    pub fn new(prog_id: String) -> Result<Self, String> {
        let (tx, mut rx) = mpsc::channel(32);
        let (init_tx, init_rx) = std::sync::mpsc::channel();
        let prog_id_clone = prog_id.clone();

        let handle = thread::spawn(move || {
            if let Err(error) = init_com() {
                let _ = init_tx.send(Err(format!("Failed to init COM: {}", error)));
                return;
            }

            let mut weather = match AscomObservingConditions::new(&prog_id_clone) {
                Ok(weather) => weather,
                Err(error) => {
                    let _ = init_tx.send(Err(format!(
                        "Failed to create ASCOM observing conditions device: {}",
                        error
                    )));
                    uninit_com();
                    return;
                }
            };

            let _ = init_tx.send(Ok(()));

            while let Some(command) = rx.blocking_recv() {
                match command {
                    AscomWeatherCommand::Connect(reply) => {
                        let _ = reply.send(weather.connect());
                    }
                    AscomWeatherCommand::Disconnect(reply) => {
                        let _ = reply.send(weather.disconnect());
                    }
                    AscomWeatherCommand::Temperature(reply) => {
                        let _ = reply.send(weather.temperature());
                    }
                    AscomWeatherCommand::Humidity(reply) => {
                        let _ = reply.send(weather.humidity());
                    }
                    AscomWeatherCommand::Pressure(reply) => {
                        let _ = reply.send(weather.pressure());
                    }
                    AscomWeatherCommand::CloudCover(reply) => {
                        let _ = reply.send(weather.cloud_cover());
                    }
                    AscomWeatherCommand::DewPoint(reply) => {
                        let _ = reply.send(weather.dew_point());
                    }
                    AscomWeatherCommand::WindSpeed(reply) => {
                        let _ = reply.send(weather.wind_speed());
                    }
                    AscomWeatherCommand::WindDirection(reply) => {
                        let _ = reply.send(weather.wind_direction());
                    }
                    AscomWeatherCommand::SkyQuality(reply) => {
                        let _ = reply.send(weather.sky_quality());
                    }
                    AscomWeatherCommand::SkyTemperature(reply) => {
                        let _ = reply.send(weather.sky_temperature());
                    }
                    AscomWeatherCommand::RainRate(reply) => {
                        let _ = reply.send(weather.rain_rate());
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
                "Weather {} timed out after {:?}",
                operation, timeout
            )),
        }
    }

    pub async fn connect(&mut self) -> Result<(), String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(AscomWeatherCommand::Connect(tx))
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
            .send(AscomWeatherCommand::Disconnect(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        let result = Self::recv_with_timeout(rx, Timeouts::connection(), "disconnect").await;
        if result.is_ok() {
            self.connected.store(false, Ordering::SeqCst);
        }
        result
    }

    pub async fn temperature(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::Temperature, "temperature")
            .await
    }

    pub async fn humidity(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::Humidity, "humidity")
            .await
    }

    pub async fn pressure(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::Pressure, "pressure")
            .await
    }

    pub async fn cloud_cover(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::CloudCover, "cloud_cover")
            .await
    }

    pub async fn dew_point(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::DewPoint, "dew_point")
            .await
    }

    pub async fn wind_speed(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::WindSpeed, "wind_speed")
            .await
    }

    pub async fn wind_direction(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::WindDirection, "wind_direction")
            .await
    }

    pub async fn sky_quality(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::SkyQuality, "sky_quality")
            .await
    }

    pub async fn sky_temperature(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::SkyTemperature, "sky_temperature")
            .await
    }

    pub async fn rain_rate(&self) -> Result<f64, String> {
        self.read_float(AscomWeatherCommand::RainRate, "rain_rate")
            .await
    }

    async fn read_float(
        &self,
        build_command: impl FnOnce(oneshot::Sender<Result<f64, String>>) -> AscomWeatherCommand,
        operation: &str,
    ) -> Result<f64, String> {
        let (tx, rx) = oneshot::channel();
        self.sender
            .send(build_command(tx))
            .await
            .map_err(|error| format!("Send error: {}", error))?;
        Self::recv_with_timeout(rx, Timeouts::property_read(), operation).await
    }
}
