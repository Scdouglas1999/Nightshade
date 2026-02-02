//! RAII Guards for Device Connections
//!
//! This module provides RAII-style guards that ensure device connections
//! are properly cleaned up, even in the presence of errors or panics.
//!
//! # Overview
//!
//! When working with hardware devices, it's critical to:
//! - Release resources when done (COM objects, sockets, SDK handles)
//! - Handle disconnection gracefully on errors
//! - Clean up properly even if code panics
//!
//! # Example
//!
//! ```rust
//! use nightshade_bridge::device_guard::AlpacaDeviceGuard;
//!
//! async fn capture_image(camera_id: &str) -> Result<Vec<u8>, Error> {
//!     let guard = AlpacaDeviceGuard::connect_camera(base_url, device_num).await?;
//!
//!     // Use the camera through the guard
//!     guard.camera().start_exposure(10.0, true).await?;
//!
//!     // When guard goes out of scope (even on error), it disconnects
//!     Ok(guard.camera().download_image().await?)
//! }
//! ```

use std::sync::Arc;
use std::future::Future;
use std::pin::Pin;
use tokio::sync::Mutex;

// =========================================================================
// Alpaca Device Guards
// =========================================================================

/// RAII guard for Alpaca camera connections
pub struct AlpacaCameraGuard {
    camera: Arc<nightshade_alpaca::AlpacaCamera>,
    connected: bool,
}

impl AlpacaCameraGuard {
    /// Create a new camera guard and connect
    pub async fn connect(base_url: &str, device_num: u32) -> Result<Self, String> {
        let camera = Arc::new(nightshade_alpaca::AlpacaCamera::from_server(base_url, device_num));
        camera.connect().await?;

        Ok(Self {
            camera,
            connected: true,
        })
    }

    /// Get a reference to the underlying camera
    pub fn camera(&self) -> &nightshade_alpaca::AlpacaCamera {
        &self.camera
    }

    /// Get the Arc for shared access
    pub fn camera_arc(&self) -> Arc<nightshade_alpaca::AlpacaCamera> {
        Arc::clone(&self.camera)
    }

    /// Mark the connection as taken (prevents disconnect on drop)
    /// Use this when transferring ownership to a device manager
    pub fn take_connection(mut self) -> Arc<nightshade_alpaca::AlpacaCamera> {
        self.connected = false;
        Arc::clone(&self.camera)
    }

    /// Manually disconnect
    pub async fn disconnect(&mut self) -> Result<(), String> {
        if self.connected {
            self.connected = false;
            self.camera.disconnect().await
        } else {
            Ok(())
        }
    }
}

impl Drop for AlpacaCameraGuard {
    fn drop(&mut self) {
        if self.connected {
            // Best-effort async disconnect in sync Drop
            // Use tokio's Handle if available
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                let camera = Arc::clone(&self.camera);
                handle.spawn(async move {
                    if let Err(e) = camera.disconnect().await {
                        tracing::warn!("Failed to disconnect Alpaca camera on drop: {}", e);
                    }
                });
            } else {
                tracing::debug!("No runtime available for Alpaca camera cleanup on drop");
            }
        }
    }
}

/// RAII guard for Alpaca telescope (mount) connections
pub struct AlpacaTelescopeGuard {
    telescope: Arc<nightshade_alpaca::AlpacaTelescope>,
    connected: bool,
}

impl AlpacaTelescopeGuard {
    /// Create a new telescope guard and connect
    pub async fn connect(base_url: &str, device_num: u32) -> Result<Self, String> {
        let telescope = Arc::new(nightshade_alpaca::AlpacaTelescope::from_server(base_url, device_num));
        telescope.connect().await?;

        Ok(Self {
            telescope,
            connected: true,
        })
    }

    /// Get a reference to the underlying telescope
    pub fn telescope(&self) -> &nightshade_alpaca::AlpacaTelescope {
        &self.telescope
    }

    /// Mark the connection as taken
    pub fn take_connection(mut self) -> Arc<nightshade_alpaca::AlpacaTelescope> {
        self.connected = false;
        Arc::clone(&self.telescope)
    }

    /// Manually disconnect
    pub async fn disconnect(&mut self) -> Result<(), String> {
        if self.connected {
            self.connected = false;
            self.telescope.disconnect().await
        } else {
            Ok(())
        }
    }
}

impl Drop for AlpacaTelescopeGuard {
    fn drop(&mut self) {
        if self.connected {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                let telescope = Arc::clone(&self.telescope);
                handle.spawn(async move {
                    if let Err(e) = telescope.disconnect().await {
                        tracing::warn!("Failed to disconnect Alpaca telescope on drop: {}", e);
                    }
                });
            }
        }
    }
}

/// RAII guard for Alpaca focuser connections
pub struct AlpacaFocuserGuard {
    focuser: Arc<nightshade_alpaca::AlpacaFocuser>,
    connected: bool,
}

impl AlpacaFocuserGuard {
    /// Create a new focuser guard and connect
    pub async fn connect(base_url: &str, device_num: u32) -> Result<Self, String> {
        let focuser = Arc::new(nightshade_alpaca::AlpacaFocuser::from_server(base_url, device_num));
        focuser.connect().await?;

        Ok(Self {
            focuser,
            connected: true,
        })
    }

    /// Get a reference to the underlying focuser
    pub fn focuser(&self) -> &nightshade_alpaca::AlpacaFocuser {
        &self.focuser
    }

    /// Mark the connection as taken
    pub fn take_connection(mut self) -> Arc<nightshade_alpaca::AlpacaFocuser> {
        self.connected = false;
        Arc::clone(&self.focuser)
    }

    /// Manually disconnect
    pub async fn disconnect(&mut self) -> Result<(), String> {
        if self.connected {
            self.connected = false;
            self.focuser.disconnect().await
        } else {
            Ok(())
        }
    }
}

impl Drop for AlpacaFocuserGuard {
    fn drop(&mut self) {
        if self.connected {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                let focuser = Arc::clone(&self.focuser);
                handle.spawn(async move {
                    if let Err(e) = focuser.disconnect().await {
                        tracing::warn!("Failed to disconnect Alpaca focuser on drop: {}", e);
                    }
                });
            }
        }
    }
}

/// RAII guard for Alpaca filter wheel connections
pub struct AlpacaFilterWheelGuard {
    filter_wheel: Arc<nightshade_alpaca::AlpacaFilterWheel>,
    connected: bool,
}

impl AlpacaFilterWheelGuard {
    /// Create a new filter wheel guard and connect
    pub async fn connect(base_url: &str, device_num: u32) -> Result<Self, String> {
        let filter_wheel = Arc::new(nightshade_alpaca::AlpacaFilterWheel::from_server(base_url, device_num));
        filter_wheel.connect().await?;

        Ok(Self {
            filter_wheel,
            connected: true,
        })
    }

    /// Get a reference to the underlying filter wheel
    pub fn filter_wheel(&self) -> &nightshade_alpaca::AlpacaFilterWheel {
        &self.filter_wheel
    }

    /// Mark the connection as taken
    pub fn take_connection(mut self) -> Arc<nightshade_alpaca::AlpacaFilterWheel> {
        self.connected = false;
        Arc::clone(&self.filter_wheel)
    }

    /// Manually disconnect
    pub async fn disconnect(&mut self) -> Result<(), String> {
        if self.connected {
            self.connected = false;
            self.filter_wheel.disconnect().await
        } else {
            Ok(())
        }
    }
}

impl Drop for AlpacaFilterWheelGuard {
    fn drop(&mut self) {
        if self.connected {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                let fw = Arc::clone(&self.filter_wheel);
                handle.spawn(async move {
                    if let Err(e) = fw.disconnect().await {
                        tracing::warn!("Failed to disconnect Alpaca filter wheel on drop: {}", e);
                    }
                });
            }
        }
    }
}

// =========================================================================
// Generic Operation Guard
// =========================================================================

/// A guard that executes cleanup code when dropped
///
/// This is useful for wrapping operations that need guaranteed cleanup,
/// such as releasing hardware resources or updating state.
pub struct OperationGuard<F>
where
    F: FnOnce() + Send,
{
    cleanup: Option<F>,
}

impl<F> OperationGuard<F>
where
    F: FnOnce() + Send,
{
    /// Create a new operation guard with the given cleanup function
    pub fn new(cleanup: F) -> Self {
        Self {
            cleanup: Some(cleanup),
        }
    }

    /// Cancel the cleanup (call when operation completes successfully and cleanup isn't needed)
    pub fn disarm(mut self) {
        self.cleanup = None;
    }
}

impl<F> Drop for OperationGuard<F>
where
    F: FnOnce() + Send,
{
    fn drop(&mut self) {
        if let Some(cleanup) = self.cleanup.take() {
            cleanup();
        }
    }
}

// =========================================================================
// Async Operation Guard
// =========================================================================

/// A guard that executes async cleanup code when dropped
///
/// Note: Async cleanup in Drop is tricky. This spawns a task on the
/// current runtime to perform cleanup.
pub struct AsyncOperationGuard {
    cleanup: Option<Pin<Box<dyn Future<Output = ()> + Send + 'static>>>,
    executed: Arc<Mutex<bool>>,
}

impl AsyncOperationGuard {
    /// Create a new async operation guard
    pub fn new<F>(cleanup: F) -> Self
    where
        F: Future<Output = ()> + Send + 'static,
    {
        Self {
            cleanup: Some(Box::pin(cleanup)),
            executed: Arc::new(Mutex::new(false)),
        }
    }

    /// Execute the cleanup immediately (async)
    pub async fn execute(&mut self) {
        let mut executed = self.executed.lock().await;
        if !*executed {
            if let Some(cleanup) = self.cleanup.take() {
                cleanup.await;
                *executed = true;
            }
        }
    }

    /// Disarm the guard (prevent cleanup on drop)
    pub fn disarm(&mut self) {
        self.cleanup = None;
    }
}

impl Drop for AsyncOperationGuard {
    fn drop(&mut self) {
        if self.cleanup.is_some() {
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                // Check if already executed
                let executed = Arc::clone(&self.executed);
                if let Some(cleanup) = self.cleanup.take() {
                    handle.spawn(async move {
                        let mut guard = executed.lock().await;
                        if !*guard {
                            cleanup.await;
                            *guard = true;
                        }
                    });
                }
            } else {
                tracing::warn!("AsyncOperationGuard dropped without runtime - cleanup skipped");
            }
        }
    }
}

// =========================================================================
// Connection State Guard
// =========================================================================

/// Guards a connection state transition, rolling back on failure
///
/// When performing multi-step connection operations, this guard ensures
/// the connection state is properly updated even if an operation fails.
pub struct ConnectionStateGuard {
    device_id: String,
    rollback_state: crate::device::ConnectionState,
    committed: bool,
    state_updater: Option<Box<dyn FnOnce(String, crate::device::ConnectionState) + Send>>,
}

impl ConnectionStateGuard {
    /// Create a new connection state guard
    ///
    /// # Arguments
    /// * `device_id` - The device being connected
    /// * `rollback_state` - State to revert to on failure
    /// * `state_updater` - Function to call to update state
    pub fn new<F>(
        device_id: String,
        rollback_state: crate::device::ConnectionState,
        state_updater: F,
    ) -> Self
    where
        F: FnOnce(String, crate::device::ConnectionState) + Send + 'static,
    {
        Self {
            device_id,
            rollback_state,
            committed: false,
            state_updater: Some(Box::new(state_updater)),
        }
    }

    /// Commit the state change (prevents rollback on drop)
    pub fn commit(mut self) {
        self.committed = true;
    }
}

impl Drop for ConnectionStateGuard {
    fn drop(&mut self) {
        if !self.committed {
            tracing::debug!(
                "Connection state guard rolling back {} to {:?}",
                self.device_id,
                self.rollback_state
            );
            if let Some(updater) = self.state_updater.take() {
                let device_id = std::mem::take(&mut self.device_id);
                let rollback_state = self.rollback_state;
                updater(device_id, rollback_state);
            }
        }
    }
}

// =========================================================================
// Timeout Guard
// =========================================================================

/// Guards an operation with a timeout, ensuring cleanup happens
/// if the operation exceeds the time limit
pub struct TimeoutGuard {
    /// Cancel token for the timeout task
    cancel_tx: Option<tokio::sync::oneshot::Sender<()>>,
}

impl TimeoutGuard {
    /// Create a new timeout guard
    ///
    /// If the guard is dropped before calling `complete()`, the timeout
    /// task will be cancelled.
    pub fn new(
        timeout: std::time::Duration,
        device_id: String,
        on_timeout: impl FnOnce() + Send + 'static,
    ) -> Self {
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();

        if let Ok(handle) = tokio::runtime::Handle::try_current() {
            handle.spawn(async move {
                tokio::select! {
                    _ = tokio::time::sleep(timeout) => {
                        tracing::warn!("Operation timed out for device {}", device_id);
                        on_timeout();
                    }
                    _ = cancel_rx => {
                        // Operation completed, timeout cancelled
                    }
                }
            });
        }

        Self {
            cancel_tx: Some(cancel_tx),
        }
    }

    /// Mark the operation as complete, cancelling the timeout
    pub fn complete(mut self) {
        if let Some(tx) = self.cancel_tx.take() {
            let _ = tx.send(());
        }
    }
}

impl Drop for TimeoutGuard {
    fn drop(&mut self) {
        // Cancel timeout task on drop
        if let Some(tx) = self.cancel_tx.take() {
            let _ = tx.send(());
        }
    }
}

// =========================================================================
// Scoped Device Lock
// =========================================================================

/// A guard that holds a device lock and releases it on drop
///
/// Useful for ensuring exclusive access to a device during an operation.
pub struct ScopedDeviceLock {
    device_id: String,
    release_fn: Option<Box<dyn FnOnce(String) + Send>>,
}

impl ScopedDeviceLock {
    /// Create a new scoped device lock
    pub fn new<F>(device_id: String, release: F) -> Self
    where
        F: FnOnce(String) + Send + 'static,
    {
        Self {
            device_id,
            release_fn: Some(Box::new(release)),
        }
    }

    /// Get the device ID being locked
    pub fn device_id(&self) -> &str {
        &self.device_id
    }

    /// Explicitly release the lock
    pub fn release(mut self) {
        if let Some(release) = self.release_fn.take() {
            release(std::mem::take(&mut self.device_id));
        }
    }
}

impl Drop for ScopedDeviceLock {
    fn drop(&mut self) {
        if let Some(release) = self.release_fn.take() {
            release(std::mem::take(&mut self.device_id));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ConnectionStateGuard;
    use std::sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    };

    #[test]
    fn connection_state_guard_rolls_back_on_drop() {
        let called = Arc::new(AtomicBool::new(false));
        let called_clone = Arc::clone(&called);
        {
            let _guard = ConnectionStateGuard::new(
                "dev-1".to_string(),
                crate::device::ConnectionState::Disconnected,
                move |id, state| {
                    assert_eq!(id, "dev-1");
                    assert_eq!(state, crate::device::ConnectionState::Disconnected);
                    called_clone.store(true, Ordering::SeqCst);
                },
            );
        }
        assert!(called.load(Ordering::SeqCst));
    }
}
