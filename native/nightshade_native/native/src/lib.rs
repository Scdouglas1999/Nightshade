//! Native Driver Support
//!
//! Provides direct integration with vendor SDKs (ZWO, QHY, Player One, etc.)
//! without requiring ASCOM, INDI, or Alpaca intermediaries.
//!
//! This module follows a similar architecture to NINA's native driver system,
//! where vendor SDKs are wrapped in a common interface for unified access.
//!
//! ## Thread Safety
//!
//! Vendor SDKs are NOT thread-safe. All SDK operations are protected by
//! per-vendor mutexes in the `sync` module. See `sync.rs` for details.

pub mod camera;
pub mod discovery;
pub mod sync;
pub mod traits;
pub mod utils;
pub mod quirks;
pub mod vendor;

pub use camera::*;
pub use discovery::*;
pub use sync::*;
pub use traits::*;
pub use utils::*;
pub use quirks::*;
pub use vendor::*;

/// Native driver vendor types
#[derive(Debug, Clone, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]
pub enum NativeVendor {
    // Camera vendors
    Zwo,
    Qhy,
    PlayerOne,
    Svbony,
    Atik,
    Fli,
    Touptek,
    StarlightXpress,
    Moravian,
    Fujifilm,
    Ascom,
    // Mount vendors
    SkyWatcher,
    IOptron,
    Celestron,
    Meade,
    Pegasus,
    // Generic
    Other(String),
}

impl NativeVendor {
    pub fn as_str(&self) -> &str {
        match self {
            NativeVendor::Zwo => "ZWO",
            NativeVendor::Qhy => "QHY",
            NativeVendor::PlayerOne => "PlayerOne",
            NativeVendor::Svbony => "SVBony",
            NativeVendor::Atik => "Atik",
            NativeVendor::Fli => "FLI",
            NativeVendor::Touptek => "Touptek",
            NativeVendor::StarlightXpress => "StarlightXpress",
            NativeVendor::Moravian => "Moravian",
            NativeVendor::Fujifilm => "Fujifilm",
            NativeVendor::Ascom => "ASCOM",
            NativeVendor::SkyWatcher => "Sky-Watcher",
            NativeVendor::IOptron => "iOptron",
            NativeVendor::Celestron => "Celestron",
            NativeVendor::Meade => "Meade",
            NativeVendor::Pegasus => "Pegasus",
            NativeVendor::Other(s) => s,
        }
    }
}

/// Check if native drivers are available on this platform
pub fn is_available() -> bool {
    // Native drivers are available on all platforms that have vendor SDKs
    true
}





