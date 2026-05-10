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
//! - Native: `native:{vendor}:{device_id}` for the simple case, with
//!           multi-segment forms documented on `parse_native`.
//!
//! # Example
//!
//! ```rust,ignore
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
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
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
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        // Check if we're at capacity and will evict
        if cache.len() >= cache.cap().get() && !cache.contains(&key) {
            self.metrics.record_eviction();
        }
        cache.put(key, value);
    }

    /// Remove a specific entry from the cache.
    /// Useful when a device is disconnected or configuration changes.
    pub fn invalidate(&self, key: &str) {
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        cache.pop(key);
    }

    /// Clear all cached entries.
    pub fn clear(&self) {
        let mut cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
        cache.clear();
    }

    /// Get the current number of entries in the cache.
    pub fn len(&self) -> usize {
        let cache = self.cache.lock().unwrap_or_else(|e| e.into_inner());
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
/// ```rust,ignore
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
        /// Vendor name (zwo, qhy, playerone, etc.) lower-cased and
        /// validated against `nightshade_native::SUPPORTED_NATIVE_VENDORS`.
        vendor: String,
        /// Device identifier (index, serial, port, etc.). For
        /// multi-segment IDs this is the trailing payload AFTER any
        /// `vendor_brand` / `device_subtype` segment is stripped.
        device_id: String,
        /// Parsed device index if `device_id` is purely numeric.
        device_index: Option<i32>,
        /// Touptek brand segment for IDs of the form
        /// `native:touptek:{brand}:{idx}` (e.g. brand = "ogma"). `None`
        /// for any other vendor — including 3-part Touptek IDs, which
        /// `parse_native` rejects rather than silently fall through.
        vendor_brand: Option<String>,
        /// Subtype segment for vendors that use a 4-part form to
        /// distinguish accessory devices from cameras: ZWO `eaf`/`efw`,
        /// QHY `cfw`, FLI `focuser`/`fw`. `None` for the composite
        /// (`zwo_eaf`, `qhy_cfw`, ...) form and for vendors with no
        /// subtype concept.
        device_subtype: Option<String>,
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
    /// ```rust,ignore
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

    /// Parse a native SDK device ID.
    ///
    /// Native IDs are emitted by `nightshade_native::discovery` and the
    /// per-vendor modules. Encoded forms in the wild:
    ///
    /// * 3-part: `native:{vendor}:{id}` (camera index, serial, etc.)
    ///   e.g. `native:zwo:0`, `native:qhy:QHY600M-12345`,
    ///   `native:lx200:COM3`.
    /// * 4-part subtype: `native:{vendor}:{subtype}:{id}` for ZWO
    ///   `eaf`/`efw`, QHY `cfw`, FLI `focuser`/`fw`.
    ///   e.g. `native:zwo:eaf:0`.
    /// * 4-part composite (alternative encoding emitted by
    ///   `discovery.rs`): `native:{vendor}_{subtype}:{id}`, e.g.
    ///   `native:zwo_eaf:0`. The composite token is in the allow-list
    ///   so this hits the default branch with `device_subtype: None`.
    /// * 4-part Touptek brand: `native:touptek:{brand}:{idx}`
    ///   (multi-brand SDK — brand is "ogma", "altair", "nncam", ...).
    /// * 4-part mount with port + baud: `native:{vendor}:{port}:{baud}`
    ///   for skywatcher / ioptron / lx200 / meade / onstep / losmandy /
    ///   10micron. Treated as the default 3-part form with `{port}:{baud}`
    ///   collapsed into `device_id` (preserves today's call-site
    ///   behaviour in `bridge/src/devices.rs`).
    /// * 5-part gphoto2: `native:gphoto2:{idx}:{port_hex}:{model}`. Same
    ///   collapsing rule.
    ///
    /// CRITICAL: an unknown leading vendor token returns an error. We do
    /// NOT silently default — that would let typo'd or future-vendor IDs
    /// reach hardware dispatch where they trigger far more confusing
    /// failures.
    fn parse_native(id: &str) -> Result<Self, NightshadeError> {
        let remainder = id
            .strip_prefix("native:")
            .ok_or_else(|| NightshadeError::invalid_device_id(id, "Missing 'native:' prefix"))?;

        // Split into all segments up-front so the multi-segment branches
        // below can index without re-splitting. `splitn(2, ':')` (the old
        // behaviour) collapsed every byte after the vendor into a single
        // string, which is exactly the bug §5.2 calls out.
        let segments: Vec<&str> = remainder.split(':').collect();
        if segments.len() < 2 || segments[0].is_empty() || segments[1].is_empty() {
            return Err(NightshadeError::invalid_device_id(
                id,
                "Invalid native device ID format - expected 'native:vendor:device_id'",
            ));
        }

        let vendor = segments[0].to_lowercase();

        // Validate vendor against the single source of truth. Composite
        // tokens (`zwo_eaf`, `qhy_cfw`, ...) live in the constant
        // because that is what `discovery.rs` emits.
        if !nightshade_native::SUPPORTED_NATIVE_VENDORS.contains(&vendor.as_str()) {
            return Err(NightshadeError::invalid_device_id(
                id,
                format!(
                    "Unknown native vendor '{}'. Allow-list lives in \
                     nightshade_native::SUPPORTED_NATIVE_VENDORS",
                    vendor,
                ),
            ));
        }

        // Touptek IDs are always 4-part: `native:touptek:{brand}:{idx}`.
        // A 3-part Touptek ID (`native:touptek:0`) is rejected because
        // the bridge dispatch needs the brand to pick the right SDK
        // wrapper — see `bridge/src/devices.rs` Touptek branch.
        if vendor == "touptek" {
            if segments.len() != 3 {
                return Err(NightshadeError::invalid_device_id(
                    id,
                    "Touptek device ID must be 'native:touptek:{brand}:{idx}'",
                ));
            }
            let brand = segments[1].to_lowercase();
            let idx_str = segments[2];
            if brand.is_empty() {
                return Err(NightshadeError::invalid_device_id(
                    id,
                    "Touptek brand segment cannot be empty",
                ));
            }
            let device_index = idx_str.parse::<i32>().ok();
            return Ok(ParsedDeviceId {
                raw_id: id.to_string(),
                driver_type: DriverType::Native,
                connection_info: ConnectionInfo::Native {
                    vendor,
                    device_id: idx_str.to_string(),
                    device_index,
                    vendor_brand: Some(brand),
                    device_subtype: None,
                },
            });
        }

        // 4-part subtype form: `native:{vendor}:{subtype}:{id}` where
        // {subtype} is one of the registered subtype tokens for the
        // vendor (zwo: eaf/efw, qhy: cfw, fli: focuser/fw). We only
        // claim this branch when both conditions hold so legitimate
        // 3-part vendor IDs whose payload happens to contain colons
        // (e.g. `native:lx200:COM3:9600`) still take the default path.
        if segments.len() >= 3 {
            if let Some((_, subtypes)) = nightshade_native::NATIVE_VENDOR_SUBTYPES
                .iter()
                .find(|(v, _)| *v == vendor.as_str())
            {
                let candidate = segments[1].to_lowercase();
                if subtypes.contains(&candidate.as_str()) {
                    // Everything after the subtype is the device id —
                    // join with ':' to preserve any legitimate colons in
                    // the trailing payload (paths, serials).
                    let payload = segments[2..].join(":");
                    if payload.is_empty() {
                        return Err(NightshadeError::invalid_device_id(
                            id,
                            "Subtype device ID cannot be empty",
                        ));
                    }
                    let device_index = payload.parse::<i32>().ok();
                    return Ok(ParsedDeviceId {
                        raw_id: id.to_string(),
                        driver_type: DriverType::Native,
                        connection_info: ConnectionInfo::Native {
                            vendor,
                            device_id: payload,
                            device_index,
                            vendor_brand: None,
                            device_subtype: Some(candidate),
                        },
                    });
                }
            }
        }

        // Default: collapse everything after the vendor into device_id.
        // This preserves the historical contract for serial-port mounts
        // (`native:skywatcher:COM3:9600`), gPhoto2 5-part IDs, and the
        // composite-subtype form (`native:zwo_eaf:0`) where the subtype
        // is already baked into the vendor token.
        let device_id_str = segments[1..].join(":");
        let device_index = device_id_str.parse::<i32>().ok();
        Ok(ParsedDeviceId {
            raw_id: id.to_string(),
            driver_type: DriverType::Native,
            connection_info: ConnectionInfo::Native {
                vendor,
                device_id: device_id_str,
                device_index,
                vendor_brand: None,
                device_subtype: None,
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

    /// Get native vendor and device ID if this is a native device.
    ///
    /// Returns `(vendor, device_id, device_index)`. For 4-part subtype
    /// or Touptek-brand IDs, prefer the dedicated accessors below — the
    /// `device_id` returned here is the trailing payload only (the
    /// brand / subtype segment is already stripped).
    pub fn native_info(&self) -> Option<(&str, &str, Option<i32>)> {
        match &self.connection_info {
            ConnectionInfo::Native {
                vendor,
                device_id,
                device_index,
                ..
            } => Some((vendor, device_id, *device_index)),
            _ => None,
        }
    }

    /// Get the native vendor token, lower-cased and validated against
    /// `SUPPORTED_NATIVE_VENDORS`. `None` for non-native IDs.
    pub fn native_vendor(&self) -> Option<&str> {
        match &self.connection_info {
            ConnectionInfo::Native { vendor, .. } => Some(vendor.as_str()),
            _ => None,
        }
    }

    /// Get the Touptek brand and discovery index for IDs of the form
    /// `native:touptek:{brand}:{idx}`. Returns `None` for non-Touptek
    /// IDs and for malformed Touptek IDs whose index is non-numeric
    /// (the parser already rejects the latter, but the accessor is
    /// defensive against future encoding changes).
    pub fn touptek_info(&self) -> Option<(&str, usize)> {
        match &self.connection_info {
            ConnectionInfo::Native {
                vendor,
                device_id,
                vendor_brand: Some(brand),
                ..
            } if vendor == "touptek" => device_id
                .parse::<usize>()
                .ok()
                .map(|idx| (brand.as_str(), idx)),
            _ => None,
        }
    }

    /// Get the ZWO accessory subtype (`eaf` or `efw`) and trailing
    /// payload for 4-part ZWO IDs of the form `native:zwo:eaf:{n}`.
    /// Returns `None` for the composite form `native:zwo_eaf:{n}` —
    /// callers must check `native_vendor()` separately for that
    /// encoding.
    pub fn zwo_subtype(&self) -> Option<(&str, &str)> {
        match &self.connection_info {
            ConnectionInfo::Native {
                vendor,
                device_id,
                device_subtype: Some(sub),
                ..
            } if vendor == "zwo" => Some((sub.as_str(), device_id.as_str())),
            _ => None,
        }
    }

    /// Get the QHY CFW subtype payload for 4-part QHY IDs
    /// (`native:qhy:cfw:{camera_id}`). Returns `None` for the composite
    /// form `native:qhy_cfw:{camera_id}`.
    pub fn qhy_subtype(&self) -> Option<(&str, &str)> {
        match &self.connection_info {
            ConnectionInfo::Native {
                vendor,
                device_id,
                device_subtype: Some(sub),
                ..
            } if vendor == "qhy" => Some((sub.as_str(), device_id.as_str())),
            _ => None,
        }
    }

    /// Get the FLI accessory subtype (`focuser` or `fw`) and trailing
    /// payload for 4-part FLI IDs (`native:fli:focuser:{path}`).
    /// Returns `None` for the composite form
    /// (`native:fli_focuser:{path}`).
    pub fn fli_subtype(&self) -> Option<(&str, &str)> {
        match &self.connection_info {
            ConnectionInfo::Native {
                vendor,
                device_id,
                device_subtype: Some(sub),
                ..
            } if vendor == "fli" => Some((sub.as_str(), device_id.as_str())),
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
                vendor,
                device_id,
                vendor_brand,
                device_subtype,
                ..
            } => {
                // Render in a form that mirrors the parsed structure so
                // log output makes the brand / subtype distinction
                // visible. We do NOT round-trip back to the raw ID
                // here — `raw()` is the contract for that.
                if let Some(brand) = vendor_brand {
                    write!(f, "Native:{}:{}:{}", vendor, brand, device_id)
                } else if let Some(sub) = device_subtype {
                    write!(f, "Native:{}:{}:{}", vendor, sub, device_id)
                } else {
                    write!(f, "Native:{}:{}", vendor, device_id)
                }
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
    // §5.1 / §5.2 — Multi-segment native ID round-trip tests
    // =========================================================================
    //
    // Every observed `format!("native:...")` site in `discovery.rs` and
    // the per-vendor modules is exercised here. If a vendor agent adds a
    // new prefix without updating `SUPPORTED_NATIVE_VENDORS`, one of
    // these tests fails and the bug is caught at `cargo test` time
    // instead of at user-machine "Unknown vendor" startup.

    fn assert_native_roundtrip(raw: &str, expected_vendor: &str) {
        let parsed = ParsedDeviceId::parse(raw)
            .unwrap_or_else(|e| panic!("expected `{}` to parse, got: {}", raw, e));
        assert_eq!(parsed.raw(), raw, "raw_id must survive parse for `{}`", raw);
        assert_eq!(
            parsed.native_vendor(),
            Some(expected_vendor),
            "vendor mismatch for `{}`",
            raw
        );
    }

    #[test]
    fn native_zwo_camera_3part() {
        assert_native_roundtrip("native:zwo:0", "zwo");
        let parsed = ParsedDeviceId::parse("native:zwo:7").unwrap();
        let (_, dev, idx) = parsed.native_info().unwrap();
        assert_eq!(dev, "7");
        assert_eq!(idx, Some(7));
        assert!(parsed.zwo_subtype().is_none());
    }

    #[test]
    fn native_zwo_eaf_4part_subtype_form() {
        // Vendor-module emit: `native:zwo:eaf:N`
        assert_native_roundtrip("native:zwo:eaf:0", "zwo");
        let parsed = ParsedDeviceId::parse("native:zwo:eaf:3").unwrap();
        let (sub, payload) = parsed.zwo_subtype().expect("zwo_subtype must surface");
        assert_eq!(sub, "eaf");
        assert_eq!(payload, "3");
        let (_, dev, idx) = parsed.native_info().unwrap();
        assert_eq!(dev, "3");
        assert_eq!(idx, Some(3));
    }

    #[test]
    fn native_zwo_efw_4part_subtype_form() {
        assert_native_roundtrip("native:zwo:efw:0", "zwo");
        let parsed = ParsedDeviceId::parse("native:zwo:efw:1").unwrap();
        let (sub, payload) = parsed.zwo_subtype().unwrap();
        assert_eq!(sub, "efw");
        assert_eq!(payload, "1");
    }

    #[test]
    fn native_zwo_eaf_composite_form() {
        // Discovery-emit: `native:zwo_eaf:N` — composite token, no
        // subtype field set.
        assert_native_roundtrip("native:zwo_eaf:0", "zwo_eaf");
        let parsed = ParsedDeviceId::parse("native:zwo_eaf:0").unwrap();
        assert!(parsed.zwo_subtype().is_none());
        let (_, dev, idx) = parsed.native_info().unwrap();
        assert_eq!(dev, "0");
        assert_eq!(idx, Some(0));
    }

    #[test]
    fn native_zwo_efw_composite_form() {
        assert_native_roundtrip("native:zwo_efw:0", "zwo_efw");
    }

    #[test]
    fn native_qhy_camera_3part() {
        // QHY camera IDs are typically "ModelName-SerialNumber",
        // i.e. non-numeric — `device_index` must be `None`.
        let parsed = ParsedDeviceId::parse("native:qhy:QHY600M-12345").unwrap();
        let (vendor, dev, idx) = parsed.native_info().unwrap();
        assert_eq!(vendor, "qhy");
        assert_eq!(dev, "QHY600M-12345");
        assert_eq!(idx, None);
        // Plain numeric form too:
        let parsed2 = ParsedDeviceId::parse("native:qhy:0").unwrap();
        let (_, _, idx2) = parsed2.native_info().unwrap();
        assert_eq!(idx2, Some(0));
    }

    #[test]
    fn native_qhy_cfw_4part_subtype_form() {
        assert_native_roundtrip("native:qhy:cfw:QHY600M-12345", "qhy");
        let parsed = ParsedDeviceId::parse("native:qhy:cfw:CAM_A").unwrap();
        let (sub, payload) = parsed.qhy_subtype().expect("qhy_subtype must surface");
        assert_eq!(sub, "cfw");
        assert_eq!(payload, "CAM_A");
    }

    #[test]
    fn native_qhy_cfw_composite_form() {
        assert_native_roundtrip("native:qhy_cfw:CAM_A", "qhy_cfw");
        let parsed = ParsedDeviceId::parse("native:qhy_cfw:CAM_A").unwrap();
        assert!(parsed.qhy_subtype().is_none());
    }

    #[test]
    fn native_fli_camera_3part_with_path() {
        // FLI uses sanitized device path as ID; path-safe form may
        // contain underscores from `/` or `\` substitution.
        let parsed = ParsedDeviceId::parse("native:fli:_dev_fliusb0").unwrap();
        let (vendor, dev, idx) = parsed.native_info().unwrap();
        assert_eq!(vendor, "fli");
        assert_eq!(dev, "_dev_fliusb0");
        assert_eq!(idx, None);
    }

    #[test]
    fn native_fli_focuser_4part_subtype_form() {
        assert_native_roundtrip("native:fli:focuser:_dev_fliusb0", "fli");
        let parsed = ParsedDeviceId::parse("native:fli:focuser:_dev_fliusb0").unwrap();
        let (sub, payload) = parsed.fli_subtype().unwrap();
        assert_eq!(sub, "focuser");
        assert_eq!(payload, "_dev_fliusb0");
    }

    #[test]
    fn native_fli_fw_4part_subtype_form() {
        assert_native_roundtrip("native:fli:fw:_dev_fliusb0", "fli");
        let parsed = ParsedDeviceId::parse("native:fli:fw:_dev_fliusb0").unwrap();
        let (sub, payload) = parsed.fli_subtype().unwrap();
        assert_eq!(sub, "fw");
        assert_eq!(payload, "_dev_fliusb0");
    }

    #[test]
    fn native_fli_focuser_composite_form() {
        assert_native_roundtrip("native:fli_focuser:_dev_fliusb0", "fli_focuser");
        assert_native_roundtrip("native:fli_fw:_dev_fliusb0", "fli_fw");
    }

    #[test]
    fn native_touptek_4part_brand_form() {
        // Multi-brand SDK: brand identifies which library to load.
        assert_native_roundtrip("native:touptek:ogma:0", "touptek");
        let parsed = ParsedDeviceId::parse("native:touptek:ogma:0").unwrap();
        let (brand, idx) = parsed.touptek_info().expect("touptek_info must surface");
        assert_eq!(brand, "ogma");
        assert_eq!(idx, 0);
        // Other brands the SDK supports:
        for brand in &["altair", "nncam", "starshootg", "touptek"] {
            let raw = format!("native:touptek:{}:2", brand);
            let parsed = ParsedDeviceId::parse(&raw).unwrap();
            let (b, idx) = parsed.touptek_info().unwrap();
            assert_eq!(b, *brand);
            assert_eq!(idx, 2);
        }
    }

    #[test]
    fn native_touptek_3part_is_rejected() {
        // §5.2: 3-part Touptek must NOT silently fall through — the
        // bridge dispatch needs the brand segment.
        let err = ParsedDeviceId::parse("native:touptek:0").unwrap_err();
        let msg = format!("{}", err);
        assert!(
            msg.contains("Touptek"),
            "expected Touptek-specific error, got: {}",
            msg
        );
    }

    #[test]
    fn native_playerone_3part() {
        // Discovery emits `playerone` (no underscore).
        assert_native_roundtrip("native:playerone:0", "playerone");
        let parsed = ParsedDeviceId::parse("native:playerone:0").unwrap();
        let (_, _, idx) = parsed.native_info().unwrap();
        assert_eq!(idx, Some(0));
    }

    #[test]
    fn native_player_one_underscore_form() {
        // `bridge/src/devices.rs` historically dispatches on
        // `player_one`. Both are accepted while the discovery /
        // dispatch alignment is in flight.
        assert_native_roundtrip("native:player_one:0", "player_one");
    }

    #[test]
    fn native_svbony_atik_moravian_3part() {
        assert_native_roundtrip("native:svbony:0", "svbony");
        assert_native_roundtrip("native:atik:1", "atik");
        assert_native_roundtrip("native:moravian:0", "moravian");
    }

    #[test]
    fn native_fujifilm_serial_id() {
        // Fujifilm emits `native:fujifilm:{serial_or_name}`; serials
        // are non-numeric so device_index is None.
        let parsed = ParsedDeviceId::parse("native:fujifilm:7CB12345").unwrap();
        let (vendor, dev, idx) = parsed.native_info().unwrap();
        assert_eq!(vendor, "fujifilm");
        assert_eq!(dev, "7CB12345");
        assert_eq!(idx, None);
    }

    #[test]
    fn native_gphoto2_5part() {
        // gPhoto2 ID: `native:gphoto2:{idx}:{port_hex}:{model}`.
        // Default branch collapses everything after the vendor into
        // `device_id` — `bridge/src/devices.rs` re-splits it for
        // its own dispatch.
        let raw = "native:gphoto2:0:7573623a3030312c303034:Canon EOS R6";
        let parsed = ParsedDeviceId::parse(raw).unwrap();
        assert_eq!(parsed.native_vendor(), Some("gphoto2"));
        let (_, dev, idx) = parsed.native_info().unwrap();
        assert_eq!(dev, "0:7573623a3030312c303034:Canon EOS R6");
        assert_eq!(idx, None);
        assert_eq!(parsed.raw(), raw);
    }

    #[test]
    fn native_skywatcher_4part_serial_mount() {
        // Serial-mount form: `native:skywatcher:{port}:{baud}`.
        // device_id collapses port + baud — call site already splits.
        let parsed = ParsedDeviceId::parse("native:skywatcher:COM3:9600").unwrap();
        let (vendor, dev, idx) = parsed.native_info().unwrap();
        assert_eq!(vendor, "skywatcher");
        assert_eq!(dev, "COM3:9600");
        assert_eq!(idx, None);
    }

    #[test]
    fn native_skywatcher_udp_form() {
        // `vendor/skywatcher.rs:215` emits `native:skywatcher:{ip}:{port}`
        let parsed = ParsedDeviceId::parse("native:skywatcher:192.168.4.1:11880").unwrap();
        let (vendor, dev, _) = parsed.native_info().unwrap();
        assert_eq!(vendor, "skywatcher");
        assert_eq!(dev, "192.168.4.1:11880");
    }

    #[test]
    fn native_ioptron_4part_serial_mount() {
        let parsed = ParsedDeviceId::parse("native:ioptron:COM4:9600").unwrap();
        let (vendor, dev, _) = parsed.native_info().unwrap();
        assert_eq!(vendor, "ioptron");
        assert_eq!(dev, "COM4:9600");
    }

    #[test]
    fn native_lx200_family_serial_mounts() {
        // discovery.rs emits one of: lx200, meade, onstep, losmandy,
        // 10micron — each followed by `{port}:{baud}`.
        for vendor in &["lx200", "meade", "onstep", "losmandy", "10micron"] {
            let raw = format!("native:{}:COM3:9600", vendor);
            assert_native_roundtrip(&raw, vendor);
            let parsed = ParsedDeviceId::parse(&raw).unwrap();
            let (_, dev, _) = parsed.native_info().unwrap();
            assert_eq!(dev, "COM3:9600");
        }
    }

    #[test]
    fn native_builtin_guider_3part() {
        // `bridge/src/builtin_guider.rs` exposes
        // `native:builtin_guider:multi_star`.
        assert_native_roundtrip("native:builtin_guider:multi_star", "builtin_guider");
    }

    #[test]
    fn native_unknown_vendor_is_rejected() {
        // CRITICAL §5.1: unknown vendors do NOT silently fall through.
        let err = ParsedDeviceId::parse("native:notarealvendor:0").unwrap_err();
        let msg = format!("{}", err);
        assert!(
            msg.contains("notarealvendor") || msg.contains("Unknown native vendor"),
            "expected unknown-vendor error, got: {}",
            msg
        );
    }

    #[test]
    fn native_empty_device_id_is_rejected() {
        // `native:zwo:` has a vendor but no payload.
        assert!(ParsedDeviceId::parse("native:zwo:").is_err());
    }

    #[test]
    fn native_subtype_empty_payload_is_rejected() {
        // `native:zwo:eaf:` claims a subtype but no payload — must
        // fail rather than fabricate device_id="".
        assert!(ParsedDeviceId::parse("native:zwo:eaf:").is_err());
    }

    #[test]
    fn native_supported_vendors_constant_is_exhaustive() {
        // Smoke-test that every token in the registry parses for at
        // least one minimal payload. Catches typos / dead entries in
        // SUPPORTED_NATIVE_VENDORS.
        for vendor in nightshade_native::SUPPORTED_NATIVE_VENDORS {
            // Touptek requires a brand segment; supply one.
            let raw = if *vendor == "touptek" {
                "native:touptek:ogma:0".to_string()
            } else {
                format!("native:{}:0", vendor)
            };
            ParsedDeviceId::parse(&raw).unwrap_or_else(|e| {
                panic!("registered vendor `{}` failed to parse: {}", vendor, e)
            });
        }
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
