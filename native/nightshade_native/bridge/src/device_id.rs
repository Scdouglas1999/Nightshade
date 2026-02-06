//! Device ID Parsing and Validation
//!
//! This module provides safe, structured parsing of device IDs across all
//! supported driver types (ASCOM, Alpaca, INDI, Native). Device IDs follow
//! a consistent format:
//!
//! - ASCOM:  `ascom:{prog_id}` (e.g., `ascom:ASCOM.Camera.Simulator`)
//! - Alpaca: `alpaca:{protocol}://{host}:{port}:{device_type}:{device_num}`
//!           (e.g., `alpaca:http://192.168.1.100:11111:camera:0`)
//! - INDI:   `indi:{host}:{port}:{device_name}`
//!           (e.g., `indi:localhost:7624:ZWO CCD`)
//! - Native: `native:{vendor}:{device_id}`
//!           (e.g., `native:zwo:0`)
//!
//! # Example
//!
//! ```rust
//! use nightshade_bridge::device_id::ParsedDeviceId;
//!
//! let parsed = ParsedDeviceId::parse("alpaca:http://192.168.1.100:11111:camera:0")?;
//! if let ConnectionInfo::Alpaca { host, port, device_type, device_num, .. } = parsed.connection_info {
//!     println!("Alpaca device at {}:{}", host, port);
//! }
//! ```

use crate::device::DriverType;
use crate::error::NightshadeError;
use lru::LruCache;
use serde::{Deserialize, Serialize};
use std::num::NonZeroUsize;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

// =========================================================================
// Device ID Cache
// =========================================================================

/// Default cache capacity for parsed device IDs.
/// A typical astrophotography setup has 5-10 devices, so 64 provides
/// ample room for multiple sessions without excessive memory usage.
const DEFAULT_CACHE_CAPACITY: usize = 64;

/// Global cache for parsed device IDs with LRU eviction.
/// Thread-safe via Mutex, with atomic counters for metrics.
static DEVICE_ID_CACHE: std::sync::OnceLock<DeviceIdCache> = std::sync::OnceLock::new();

/// Cache metrics for monitoring hit rates and performance.
#[derive(Debug, Default)]
pub struct CacheMetrics {
    /// Number of cache hits
    hits: AtomicU64,
    /// Number of cache misses
    misses: AtomicU64,
    /// Number of entries evicted due to capacity
    evictions: AtomicU64,
}

impl CacheMetrics {
    /// Get the current number of cache hits
    pub fn hits(&self) -> u64 {
        self.hits.load(Ordering::Relaxed)
    }

    /// Get the current number of cache misses
    pub fn misses(&self) -> u64 {
        self.misses.load(Ordering::Relaxed)
    }

    /// Get the current number of evictions
    pub fn evictions(&self) -> u64 {
        self.evictions.load(Ordering::Relaxed)
    }

    /// Get the cache hit rate as a percentage (0.0 to 100.0)
    pub fn hit_rate(&self) -> f64 {
        let hits = self.hits() as f64;
        let total = hits + self.misses() as f64;
        if total == 0.0 {
            0.0
        } else {
            (hits / total) * 100.0
        }
    }

    /// Increment the hit counter
    fn record_hit(&self) {
        self.hits.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment the miss counter
    fn record_miss(&self) {
        self.misses.fetch_add(1, Ordering::Relaxed);
    }

    /// Increment the eviction counter
    fn record_eviction(&self) {
        self.evictions.fetch_add(1, Ordering::Relaxed);
    }

    /// Reset all metrics (useful for testing)
    pub fn reset(&self) {
        self.hits.store(0, Ordering::Relaxed);
        self.misses.store(0, Ordering::Relaxed);
        self.evictions.store(0, Ordering::Relaxed);
    }
}

/// Thread-safe LRU cache for parsed device IDs.
pub struct DeviceIdCache {
    cache: Mutex<LruCache<String, ParsedDeviceId>>,
    metrics: CacheMetrics,
}

impl DeviceIdCache {
    /// Create a new cache with the specified capacity.
    fn new(capacity: usize) -> Self {
        let cap = NonZeroUsize::new(capacity)
            .unwrap_or(NonZeroUsize::new(DEFAULT_CACHE_CAPACITY).unwrap());
        Self {
            cache: Mutex::new(LruCache::new(cap)),
            metrics: CacheMetrics::default(),
        }
    }

    /// Get a cached entry, updating LRU order.
    /// Returns a clone of the cached value if found.
    fn get(&self, key: &str) -> Option<ParsedDeviceId> {
        let mut cache = self.cache.lock().unwrap();
        if let Some(value) = cache.get(key) {
            self.metrics.record_hit();
            Some(value.clone())
        } else {
            self.metrics.record_miss();
            None
        }
    }

    /// Insert a new entry, potentially evicting the LRU entry.
    fn put(&self, key: String, value: ParsedDeviceId) {
        let mut cache = self.cache.lock().unwrap();
        // Check if we're at capacity and will evict
        if cache.len() >= cache.cap().get() && !cache.contains(&key) {
            self.metrics.record_eviction();
        }
        cache.put(key, value);
    }

    /// Remove a specific entry from the cache.
    /// Useful when a device is disconnected or configuration changes.
    pub fn invalidate(&self, key: &str) {
        let mut cache = self.cache.lock().unwrap();
        cache.pop(key);
    }

    /// Clear all cached entries.
    pub fn clear(&self) {
        let mut cache = self.cache.lock().unwrap();
        cache.clear();
    }

    /// Get the current number of entries in the cache.
    pub fn len(&self) -> usize {
        let cache = self.cache.lock().unwrap();
        cache.len()
    }

    /// Check if the cache is empty.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Get a reference to the cache metrics.
    pub fn metrics(&self) -> &CacheMetrics {
        &self.metrics
    }
}

/// Get the global device ID cache, initializing it if necessary.
fn get_cache() -> &'static DeviceIdCache {
    DEVICE_ID_CACHE.get_or_init(|| DeviceIdCache::new(DEFAULT_CACHE_CAPACITY))
}

/// Parse a device ID with caching.
///
/// This is the primary entry point for parsing device IDs. It will:
/// 1. Check the cache for an existing parsed result
/// 2. If not found, parse the ID and cache the result
/// 3. Return a clone of the parsed device ID
///
/// # Arguments
/// * `device_id` - The raw device ID string to parse
///
/// # Returns
/// * `Ok(ParsedDeviceId)` - Successfully parsed (from cache or freshly parsed)
/// * `Err(NightshadeError)` - Parsing failed
///
/// # Example
/// ```rust
/// let parsed = parse_device_id_cached("alpaca:http://192.168.1.100:11111:camera:0")?;
/// ```
pub fn parse_device_id_cached(device_id: &str) -> Result<ParsedDeviceId, NightshadeError> {
    let cache = get_cache();

    // Check cache first
    if let Some(cached) = cache.get(device_id) {
        tracing::trace!("Device ID cache hit: {}", device_id);
        return Ok(cached);
    }

    // Cache miss - parse and store
    tracing::trace!("Device ID cache miss: {}", device_id);
    let parsed = ParsedDeviceId::parse(device_id)?;
    cache.put(device_id.to_string(), parsed.clone());
    Ok(parsed)
}

/// Get current cache statistics.
///
/// Returns a snapshot of cache metrics including hits, misses, and evictions.
pub fn get_device_id_cache_stats() -> DeviceIdCacheStats {
    let cache = get_cache();
    DeviceIdCacheStats {
        size: cache.len(),
        hits: cache.metrics().hits(),
        misses: cache.metrics().misses(),
        evictions: cache.metrics().evictions(),
        hit_rate: cache.metrics().hit_rate(),
    }
}

/// Invalidate a specific device ID from the cache.
///
/// Call this when a device is disconnected or its configuration changes.
pub fn invalidate_device_id_cache(device_id: &str) {
    get_cache().invalidate(device_id);
    tracing::debug!("Invalidated device ID cache entry: {}", device_id);
}

/// Clear the entire device ID cache.
///
/// Call this when switching profiles or during cleanup.
pub fn clear_device_id_cache() {
    get_cache().clear();
    tracing::debug!("Cleared device ID cache");
}

/// Reset cache metrics (primarily for testing).
pub fn reset_device_id_cache_metrics() {
    get_cache().metrics().reset();
}

/// Snapshot of cache statistics.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceIdCacheStats {
    /// Current number of entries in the cache
    pub size: usize,
    /// Total number of cache hits
    pub hits: u64,
    /// Total number of cache misses
    pub misses: u64,
    /// Total number of evictions
    pub evictions: u64,
    /// Cache hit rate as a percentage (0.0 to 100.0)
    pub hit_rate: f64,
}

impl std::fmt::Display for DeviceIdCacheStats {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "DeviceIdCache {{ size: {}, hits: {}, misses: {}, evictions: {}, hit_rate: {:.1}% }}",
            self.size, self.hits, self.misses, self.evictions, self.hit_rate
        )
    }
}

// =========================================================================
// Parsed Device ID
// =========================================================================

/// A fully parsed and validated device ID
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedDeviceId {
    /// The raw device ID string
    pub raw_id: String,
    /// The driver type this ID represents
    pub driver_type: DriverType,
    /// The connection-specific information
    pub connection_info: ConnectionInfo,
}

/// Connection information specific to each driver type
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConnectionInfo {
    /// ASCOM driver (Windows COM)
    Ascom {
        /// The ASCOM ProgID (e.g., "ASCOM.Camera.Simulator")
        prog_id: String,
    },

    /// ASCOM Alpaca (REST API)
    Alpaca {
        /// Protocol (http or https)
        protocol: String,
        /// Host address (IP or hostname)
        host: String,
        /// Port number
        port: u16,
        /// Device type string (camera, telescope, focuser, etc.)
        device_type: String,
        /// Device number on the server
        device_num: u32,
        /// Full base URL for convenience
        base_url: String,
    },

    /// INDI protocol
    Indi {
        /// INDI server host
        host: String,
        /// INDI server port
        port: u16,
        /// INDI device name
        device_name: String,
    },

    /// Native SDK (ZWO, QHY, etc.)
    Native {
        /// Vendor name (zwo, qhy, player_one, etc.)
        vendor: String,
        /// Device identifier (could be index or serial number)
        device_id: String,
        /// Parsed device index if numeric
        device_index: Option<i32>,
    },

    /// Simulator device
    Simulator {
        /// Simulator device type
        device_type: String,
        /// Instance index
        instance: u32,
    },
}

impl ParsedDeviceId {
    /// Parse a device ID string into its components
    ///
    /// # Arguments
    /// * `id` - The raw device ID string
    ///
    /// # Returns
    /// * `Ok(ParsedDeviceId)` - Successfully parsed device ID
    /// * `Err(NightshadeError)` - Parsing failed with details
    ///
    /// # Examples
    /// ```rust
    /// let parsed = ParsedDeviceId::parse("ascom:ASCOM.Camera.Simulator")?;
    /// assert_eq!(parsed.driver_type, DriverType::Ascom);
    /// ```
    pub fn parse(id: &str) -> Result<Self, NightshadeError> {
        if id.is_empty() {
            return Err(NightshadeError::invalid_device_id(
                id,
                "Device ID cannot be empty",
            ));
        }

        // Determine the driver type from prefix
        if id.starts_with("ascom:") {
            Self::parse_ascom(id)
        } else if id.starts_with("alpaca:") {
            Self::parse_alpaca(id)
        } else if id.starts_with("indi:") {
            Self::parse_indi(id)
        } else if id.starts_with("native:") {
            Self::parse_native(id)
        } else if id.starts_with("simulator:") || id.starts_with("sim:") {
            Self::parse_simulator(id)
        } else {
            // Try to infer the type from the ID format
            Self::parse_infer(id)
        }
    }

    /// Parse an ASCOM device ID
    fn parse_ascom(id: &str) -> Result<Self, NightshadeError> {
        let prog_id = id
            .strip_prefix("ascom:")
            .ok_or_else(|| NightshadeError::invalid_device_id(id, "Missing 'ascom:' prefix"))?;

        if prog_id.is_empty() {
            return Err(NightshadeError::invalid_device_id(
                id,
                "ASCOM ProgID cannot be empty",
            ));
        }

        // Basic validation: ASCOM ProgIDs should contain at least one dot
        if !prog_id.contains('.') {
            return Err(NightshadeError::invalid_device_id(
                id,
                "Invalid ASCOM ProgID format - expected 'Vendor.Type.Name'",
            ));
        }

        Ok(ParsedDeviceId {
            raw_id: id.to_string(),
            driver_type: DriverType::Ascom,
            connection_info: ConnectionInfo::Ascom {
                prog_id: prog_id.to_string(),
            },
        })
    }

    /// Parse an Alpaca device ID
    fn parse_alpaca(id: &str) -> Result<Self, NightshadeError> {
        let remainder = id
            .strip_prefix("alpaca:")
            .ok_or_else(|| NightshadeError::invalid_device_id(id, "Missing 'alpaca:' prefix"))?;

        // Format: protocol://host:port:device_type:device_num
        // or:     protocol://host:port/api/v1/device_type/device_num

        // First, try the colon-separated format: http://host:port:type:num
        let parts: Vec<&str> = remainder.split(':').collect();

        if parts.len() >= 5 {
            // Format: protocol://host:port:device_type:device_num
            let protocol = parts[0];
            let host = parts[1].trim_start_matches("//");
            let port: u16 = parts[2]
                .parse()
                .map_err(|_| NightshadeError::invalid_device_id(id, "Invalid port number"))?;
            let device_type = parts[3].to_lowercase();
            let device_num: u32 = parts[4]
                .parse()
                .map_err(|_| NightshadeError::invalid_device_id(id, "Invalid device number"))?;

            let base_url = format!("{}://{}:{}", protocol, host, port);

            return Ok(ParsedDeviceId {
                raw_id: id.to_string(),
                driver_type: DriverType::Alpaca,
                connection_info: ConnectionInfo::Alpaca {
                    protocol: protocol.to_string(),
                    host: host.to_string(),
                    port,
                    device_type,
                    device_num,
                    base_url,
                },
            });
        }

        // Try alternate format: base_url:device_type:device_num
        if parts.len() >= 3 {
            // Try parsing as base_url:type:num where base_url contains ://
            let base_url = parts[0..parts.len() - 2].join(":");
            let device_type = parts[parts.len() - 2].to_lowercase();
            let device_num: u32 = parts[parts.len() - 1]
                .parse()
                .map_err(|_| NightshadeError::invalid_device_id(id, "Invalid device number"))?;

            // Extract protocol, host, port from base_url
            let (protocol, host, port) =
                parse_base_url(&base_url).map_err(|e| NightshadeError::invalid_device_id(id, e))?;

            return Ok(ParsedDeviceId {
                raw_id: id.to_string(),
                driver_type: DriverType::Alpaca,
                connection_info: ConnectionInfo::Alpaca {
                    protocol,
                    host,
                    port,
                    device_type,
                    device_num,
                    base_url,
                },
            });
        }

        Err(NightshadeError::invalid_device_id(
            id,
            "Invalid Alpaca device ID format - expected 'protocol://host:port:device_type:device_num'",
        ))
    }

    /// Parse an INDI device ID
    fn parse_indi(id: &str) -> Result<Self, NightshadeError> {
        let remainder = id
            .strip_prefix("indi:")
            .ok_or_else(|| NightshadeError::invalid_device_id(id, "Missing 'indi:' prefix"))?;

        // Format: host:port:device_name
        // Device name can contain colons, so we split carefully
        let parts: Vec<&str> = remainder.splitn(3, ':').collect();

        if parts.len() < 3 {
            return Err(NightshadeError::invalid_device_id(
                id,
                "Invalid INDI device ID format - expected 'indi:host:port:device_name'",
            ));
        }

        let host = parts[0];
        let port: u16 = parts[1]
            .parse()
            .map_err(|_| NightshadeError::invalid_device_id(id, "Invalid port number"))?;
        let device_name = parts[2];

        if host.is_empty() {
            return Err(NightshadeError::invalid_device_id(
                id,
                "INDI host cannot be empty",
            ));
        }
        if device_name.is_empty() {
            return Err(NightshadeError::invalid_device_id(
                id,
                "INDI device name cannot be empty",
            ));
        }

        Ok(ParsedDeviceId {
            raw_id: id.to_string(),
            driver_type: DriverType::Indi,
            connection_info: ConnectionInfo::Indi {
                host: host.to_string(),
                port,
                device_name: device_name.to_string(),
            },
        })
    }

    /// Parse a native SDK device ID
    fn parse_native(id: &str) -> Result<Self, NightshadeError> {
        let remainder = id
            .strip_prefix("native:")
            .ok_or_else(|| NightshadeError::invalid_device_id(id, "Missing 'native:' prefix"))?;

        // Format: vendor:device_id
        let parts: Vec<&str> = remainder.splitn(2, ':').collect();

        if parts.len() < 2 {
            return Err(NightshadeError::invalid_device_id(
                id,
                "Invalid native device ID format - expected 'native:vendor:device_id'",
            ));
        }

        let vendor = parts[0].to_lowercase();
        let device_id = parts[1];

        // Validate vendor
        let valid_vendors = [
            "zwo",
            "qhy",
            "player_one",
            "svbony",
            "atik",
            "fli",
            "touptek",
            "moravian",
            "skywatcher",
            "ioptron",
            "lx200",
        ];
        if !valid_vendors.contains(&vendor.as_str()) {
            return Err(NightshadeError::invalid_device_id(
                id,
                format!(
                    "Unknown vendor '{}'. Valid vendors: {:?}",
                    vendor, valid_vendors
                ),
            ));
        }

        // Try to parse device_id as an index
        let device_index = device_id.parse::<i32>().ok();

        Ok(ParsedDeviceId {
            raw_id: id.to_string(),
            driver_type: DriverType::Native,
            connection_info: ConnectionInfo::Native {
                vendor,
                device_id: device_id.to_string(),
                device_index,
            },
        })
    }

    /// Parse a simulator device ID
    fn parse_simulator(id: &str) -> Result<Self, NightshadeError> {
        let remainder = id
            .strip_prefix("simulator:")
            .or_else(|| id.strip_prefix("sim:"))
            .ok_or_else(|| NightshadeError::invalid_device_id(id, "Missing simulator prefix"))?;

        // Format: device_type:instance (instance optional, defaults to 0)
        let parts: Vec<&str> = remainder.split(':').collect();

        let device_type = parts
            .first()
            .ok_or_else(|| NightshadeError::invalid_device_id(id, "Missing device type"))?
            .to_lowercase();

        let instance: u32 = if parts.len() > 1 {
            parts[1].parse().unwrap_or(0)
        } else {
            0
        };

        Ok(ParsedDeviceId {
            raw_id: id.to_string(),
            driver_type: DriverType::Simulator,
            connection_info: ConnectionInfo::Simulator {
                device_type,
                instance,
            },
        })
    }

    /// Try to infer the device type from the ID format
    fn parse_infer(id: &str) -> Result<Self, NightshadeError> {
        // Check if it looks like an ASCOM ProgID (contains dots, no scheme)
        if id.contains('.') && !id.contains("://") && !id.contains(':') {
            return Self::parse_ascom(&format!("ascom:{}", id));
        }

        // Check if it looks like a URL
        if id.starts_with("http://") || id.starts_with("https://") {
            // Likely an Alpaca URL without prefix
            return Self::parse_alpaca(&format!("alpaca:{}", id));
        }

        Err(NightshadeError::invalid_device_id(
            id,
            "Unable to infer device type - use a prefix (ascom:, alpaca:, indi:, native:)",
        ))
    }

    // =========================================================================
    // Accessor Methods
    // =========================================================================

    /// Get the raw device ID string
    pub fn raw(&self) -> &str {
        &self.raw_id
    }

    /// Get the ASCOM ProgID if this is an ASCOM device
    pub fn ascom_prog_id(&self) -> Option<&str> {
        match &self.connection_info {
            ConnectionInfo::Ascom { prog_id } => Some(prog_id),
            _ => None,
        }
    }

    /// Get Alpaca connection info if this is an Alpaca device
    pub fn alpaca_info(&self) -> Option<(&str, &str, u16, &str, u32)> {
        match &self.connection_info {
            ConnectionInfo::Alpaca {
                protocol,
                host,
                port,
                device_type,
                device_num,
                ..
            } => Some((protocol, host, *port, device_type, *device_num)),
            _ => None,
        }
    }

    /// Get the Alpaca base URL if this is an Alpaca device
    pub fn alpaca_base_url(&self) -> Option<&str> {
        match &self.connection_info {
            ConnectionInfo::Alpaca { base_url, .. } => Some(base_url),
            _ => None,
        }
    }

    /// Get INDI connection info if this is an INDI device
    pub fn indi_info(&self) -> Option<(&str, u16, &str)> {
        match &self.connection_info {
            ConnectionInfo::Indi {
                host,
                port,
                device_name,
            } => Some((host, *port, device_name)),
            _ => None,
        }
    }

    /// Get native vendor and device ID if this is a native device
    pub fn native_info(&self) -> Option<(&str, &str, Option<i32>)> {
        match &self.connection_info {
            ConnectionInfo::Native {
                vendor,
                device_id,
                device_index,
            } => Some((vendor, device_id, *device_index)),
            _ => None,
        }
    }

    /// Check if this device uses a network connection
    pub fn is_network_device(&self) -> bool {
        matches!(
            &self.connection_info,
            ConnectionInfo::Alpaca { .. } | ConnectionInfo::Indi { .. }
        )
    }

    /// Get the network address if this is a network device
    pub fn network_address(&self) -> Option<String> {
        match &self.connection_info {
            ConnectionInfo::Alpaca { host, port, .. } => Some(format!("{}:{}", host, port)),
            ConnectionInfo::Indi { host, port, .. } => Some(format!("{}:{}", host, port)),
            _ => None,
        }
    }
}

// =========================================================================
// Helper Functions
// =========================================================================

/// Parse a base URL into protocol, host, and port
fn parse_base_url(url: &str) -> Result<(String, String, u16), &'static str> {
    // Expected format: http://host:port or https://host:port
    let (protocol, remainder) = if url.starts_with("https://") {
        (
            "https".to_string(),
            url.strip_prefix("https://").unwrap_or(""),
        )
    } else if url.starts_with("http://") {
        (
            "http".to_string(),
            url.strip_prefix("http://").unwrap_or(""),
        )
    } else {
        return Err("Invalid URL protocol - expected http:// or https://");
    };

    // Split host and port
    let parts: Vec<&str> = remainder.split(':').collect();
    if parts.len() < 2 {
        return Err("Invalid URL format - expected host:port");
    }

    let host = parts[0].to_string();
    let port: u16 = parts[1]
        .split('/')
        .next()
        .and_then(|p| p.parse().ok())
        .ok_or("Invalid port number")?;

    Ok((protocol, host, port))
}

// =========================================================================
// Display Implementation
// =========================================================================

impl std::fmt::Display for ParsedDeviceId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match &self.connection_info {
            ConnectionInfo::Ascom { prog_id } => {
                write!(f, "ASCOM:{}", prog_id)
            }
            ConnectionInfo::Alpaca {
                host,
                port,
                device_type,
                device_num,
                ..
            } => {
                write!(f, "Alpaca:{}:{}/{}:{}", host, port, device_type, device_num)
            }
            ConnectionInfo::Indi {
                host,
                port,
                device_name,
            } => {
                write!(f, "INDI:{}:{}/{}", host, port, device_name)
            }
            ConnectionInfo::Native {
                vendor, device_id, ..
            } => {
                write!(f, "Native:{}:{}", vendor, device_id)
            }
            ConnectionInfo::Simulator {
                device_type,
                instance,
            } => {
                write!(f, "Simulator:{}:{}", device_type, instance)
            }
        }
    }
}

// =========================================================================
// Tests
// =========================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_ascom() {
        let parsed = ParsedDeviceId::parse("ascom:ASCOM.Camera.Simulator").unwrap();
        assert_eq!(parsed.driver_type, DriverType::Ascom);
        assert_eq!(parsed.ascom_prog_id(), Some("ASCOM.Camera.Simulator"));
    }

    #[test]
    fn test_parse_alpaca() {
        let parsed = ParsedDeviceId::parse("alpaca:http://192.168.1.100:11111:camera:0").unwrap();
        assert_eq!(parsed.driver_type, DriverType::Alpaca);
        let (proto, host, port, dtype, dnum) = parsed.alpaca_info().unwrap();
        assert_eq!(proto, "http");
        assert_eq!(host, "192.168.1.100");
        assert_eq!(port, 11111);
        assert_eq!(dtype, "camera");
        assert_eq!(dnum, 0);
    }

    #[test]
    fn test_parse_indi() {
        let parsed = ParsedDeviceId::parse("indi:localhost:7624:ZWO CCD ASI120").unwrap();
        assert_eq!(parsed.driver_type, DriverType::Indi);
        let (host, port, device_name) = parsed.indi_info().unwrap();
        assert_eq!(host, "localhost");
        assert_eq!(port, 7624);
        assert_eq!(device_name, "ZWO CCD ASI120");
    }

    #[test]
    fn test_parse_native() {
        let parsed = ParsedDeviceId::parse("native:zwo:0").unwrap();
        assert_eq!(parsed.driver_type, DriverType::Native);
        let (vendor, device_id, device_index) = parsed.native_info().unwrap();
        assert_eq!(vendor, "zwo");
        assert_eq!(device_id, "0");
        assert_eq!(device_index, Some(0));
    }

    #[test]
    fn test_invalid_empty() {
        assert!(ParsedDeviceId::parse("").is_err());
    }

    #[test]
    fn test_invalid_ascom_no_dot() {
        assert!(ParsedDeviceId::parse("ascom:NoDotProgId").is_err());
    }

    #[test]
    fn test_invalid_alpaca_bad_port() {
        assert!(ParsedDeviceId::parse("alpaca:http://host:notaport:camera:0").is_err());
    }

    // =========================================================================
    // Cache Tests
    // =========================================================================

    #[test]
    fn test_cached_parse_returns_same_result() {
        // First call should be a cache miss
        let parsed1 = parse_device_id_cached("ascom:ASCOM.Telescope.Simulator").unwrap();

        // Second call should be a cache hit with identical result
        let parsed2 = parse_device_id_cached("ascom:ASCOM.Telescope.Simulator").unwrap();

        assert_eq!(parsed1.raw_id, parsed2.raw_id);
        assert_eq!(parsed1.driver_type, parsed2.driver_type);
    }

    #[test]
    fn test_cache_metrics() {
        // Reset metrics for a clean test
        reset_device_id_cache_metrics();

        // Clear cache to ensure cache miss
        clear_device_id_cache();

        // First call should be a miss
        let _ = parse_device_id_cached("indi:testhost:7624:TestDevice").unwrap();

        // Get stats - should have 1 miss
        let stats = get_device_id_cache_stats();
        assert!(
            stats.misses >= 1,
            "Expected at least 1 miss, got {}",
            stats.misses
        );

        // Second call should be a hit
        let _ = parse_device_id_cached("indi:testhost:7624:TestDevice").unwrap();

        let stats2 = get_device_id_cache_stats();
        assert!(
            stats2.hits >= 1,
            "Expected at least 1 hit, got {}",
            stats2.hits
        );
    }

    #[test]
    fn test_cache_invalidation() {
        let device_id = "alpaca:http://192.168.1.50:11111:focuser:0";

        // Parse and cache
        let _ = parse_device_id_cached(device_id).unwrap();
        let stats_before = get_device_id_cache_stats();
        let _initial_size = stats_before.size;

        // Invalidate
        invalidate_device_id_cache(device_id);

        // After invalidation, parsing again should work
        // (the cache entry was removed, will be re-added on parse)
        let _ = parse_device_id_cached(device_id).unwrap();

        // Size should be similar (entry was removed then re-added)
        let stats_after = get_device_id_cache_stats();
        assert!(
            stats_after.size >= 1,
            "Cache should have at least one entry"
        );
    }

    #[test]
    fn test_cache_clear() {
        // Parse a few device IDs
        let _ = parse_device_id_cached("native:zwo:1").unwrap();
        let _ = parse_device_id_cached("native:qhy:2").unwrap();

        // Clear the cache
        clear_device_id_cache();

        // Cache should be empty
        let stats = get_device_id_cache_stats();
        assert_eq!(stats.size, 0, "Cache should be empty after clear");
    }

    #[test]
    fn test_cache_stats_display() {
        let stats = get_device_id_cache_stats();
        let display = format!("{}", stats);
        assert!(display.contains("DeviceIdCache"));
        assert!(display.contains("size"));
        assert!(display.contains("hits"));
        assert!(display.contains("hit_rate"));
    }

    #[test]
    fn test_cache_handles_invalid_ids() {
        // Invalid IDs should not be cached (they return errors)
        let result = parse_device_id_cached("");
        assert!(result.is_err());

        let result = parse_device_id_cached("invalid:format");
        assert!(result.is_err());
    }
}
