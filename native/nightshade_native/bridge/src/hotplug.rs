//! Hot-plug device detection.
//!
//! Two complementary surfaces feed the same downstream event:
//!
//!   1. **OS bus notifications** (`start_os_hotplug_listener`): a hidden Win32
//!      window subscribes to `WM_DEVICECHANGE`. This fires on USB arrival /
//!      removal within ~100 ms but is unspecific — it tells you that *some*
//!      device changed, not which one. We use it to invalidate the discovery
//!      cache and emit a coarse `PropertyChanged { property: "device_change" }`
//!      event for legacy listeners.
//!
//!   2. **Polling watcher** (`start_device_poll_watcher`): a tokio task that
//!      walks the native (vendor-SDK) and, on Windows, ASCOM registry device
//!      lists every `HOTPLUG_POLL_INTERVAL`. It diffs the live list against
//!      a cached set keyed by `(driver_type, device_id)` and emits one
//!      `device_discovered` event per new arrival and one `device_lost`
//!      event per removal. The event carries the device class, driver, id,
//!      name and (when available) a unique id so the Dart side can refresh
//!      the equipment list without a full backend rescan.
//!
//! INDI and Alpaca are intentionally NOT polled here:
//!
//!   * INDI publishes device-list changes as `getProperties` notifications
//!     on the persistent client connection. The INDI client (in
//!     `nightshade_indi`) already raises those into the event bus when a
//!     remote driver attaches / detaches.
//!   * Alpaca is broadcast-discovered every time a UI rescan runs. Polling
//!     every 4 s would saturate the LAN with UDP broadcasts and battery on
//!     paired mobile clients.
//!
//! Dart consumers filter on `EventCategory::Equipment` + `eventType ==
//! 'device_discovered' | 'device_lost'`. The wave-6b unified discovery
//! provider invalidates its cache and refreshes the visible list on receipt
//! so the equipment screen refreshes without pull-to-refresh.
//!
//! NOTE: a follow-up patch will promote `DeviceDiscovered`/`DeviceLost` to
//! first-class `EquipmentEvent` variants. Doing that requires regenerating
//! the FRB bindings — see `event.rs` for the regen TODO. The current
//! implementation rides on `EquipmentEvent::PropertyChanged` so the wire
//! shape is stable today and the FRB regen can land independently.

use crate::api::{api_invalidate_discovery_cache, get_state};
use crate::device::{DeviceType, DriverType};
use crate::event::{EquipmentEvent, EventSeverity};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex as StdMutex;
use std::sync::OnceLock;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

static LISTENER_STARTED: AtomicBool = AtomicBool::new(false);
static POLL_WATCHER_STARTED: AtomicBool = AtomicBool::new(false);
static POLL_WATCHER_SHUTDOWN: AtomicBool = AtomicBool::new(false);
static LAST_PUBLISHED_MS: AtomicU64 = AtomicU64::new(0);

const HOTPLUG_DEBOUNCE_MS: u64 = 500;

/// Polling cadence for the native / ASCOM hot-plug watcher.
///
/// 4 seconds is the trade-off the task brief calls out (P2-1: "within ~3s"):
///   * Long enough that the vendor SDKs and ASCOM Profile registry are not
///     hammered (most SDKs internally serialise their list call).
///   * Short enough that a user plugging a camera in mid-session sees the
///     device in the equipment screen by the time they switch tabs.
const HOTPLUG_POLL_INTERVAL: Duration = Duration::from_secs(4);

/// Device types we poll for hot-plug events. Keep this list narrow to the
/// classes that are realistically hot-pluggable from the user's perspective:
/// cameras, mounts, focusers, filter wheels, rotators. Domes / weather /
/// safety monitors are not polled — they are effectively permanent fixtures
/// of an observatory install and their drivers do not benefit from a 4 s
/// hot-plug poll.
const POLLED_DEVICE_TYPES: &[DeviceType] = &[
    DeviceType::Camera,
    DeviceType::Mount,
    DeviceType::Focuser,
    DeviceType::FilterWheel,
    DeviceType::Rotator,
];

#[cfg(windows)]
const DBT_DEVNODES_CHANGED: usize = 0x0007;
#[cfg(windows)]
const DBT_DEVICEARRIVAL: usize = 0x8000;
#[cfg(windows)]
const DBT_DEVICEREMOVECOMPLETE: usize = 0x8004;

/// Cached device snapshot keyed by `(DriverType, device_id)`. Held in a
/// std::sync::Mutex (not tokio) because we only touch it from the dedicated
/// poll task — there is no `await` while the lock is held.
type DeviceCache = HashMap<(DriverType, String), CachedDevice>;

#[derive(Debug, Clone)]
struct CachedDevice {
    device_type: DeviceType,
    name: String,
    unique_id: Option<String>,
    display_name: String,
}

static DEVICE_CACHE: OnceLock<StdMutex<DeviceCache>> = OnceLock::new();

fn device_cache() -> &'static StdMutex<DeviceCache> {
    DEVICE_CACHE.get_or_init(|| StdMutex::new(HashMap::new()))
}

pub(crate) fn start_os_hotplug_listener() {
    if !LISTENER_STARTED.swap(true, Ordering::AcqRel) {
        start_platform_hotplug_listener();
    }

    // The polling watcher is independent of the OS listener — on Linux/macOS
    // USB bus events cut through the discovery TTL immediately; the poller
    // fills in typed arrived/lost details for SDK-backed device lists.
    start_device_poll_watcher();
}

/// Request the polling task to exit on its next tick. Tests and the bridge
/// shutdown path call this; the OS listener thread is parked on
/// `GetMessageW` and cannot be cleanly stopped, but its impact is negligible
/// (a hidden message-only window).
#[allow(dead_code)]
pub fn stop_device_poll_watcher() {
    POLL_WATCHER_SHUTDOWN.store(true, Ordering::Release);
}

#[cfg(windows)]
fn start_platform_hotplug_listener() {
    match std::thread::Builder::new()
        .name("nightshade-windows-device-change".to_string())
        .spawn(windows_device_change_thread)
    {
        Ok(_) => {}
        Err(err) => {
            LISTENER_STARTED.store(false, Ordering::Release);
            tracing::warn!("Failed to start Windows device-change listener: {}", err);
        }
    }
}

#[cfg(all(unix, any(target_os = "linux", target_os = "macos")))]
fn start_platform_hotplug_listener() {
    match std::thread::Builder::new()
        .name("nightshade-usb-hotplug".to_string())
        .spawn(usb_hotplug_thread)
    {
        Ok(_) => {}
        Err(err) => {
            LISTENER_STARTED.store(false, Ordering::Release);
            tracing::warn!("Failed to start USB hotplug listener: {}", err);
        }
    }
}

#[cfg(all(unix, not(any(target_os = "linux", target_os = "macos"))))]
fn start_platform_hotplug_listener() {
    tracing::debug!("USB hotplug listener is not implemented for this Unix platform yet");
}

fn start_device_poll_watcher() {
    if POLL_WATCHER_STARTED.swap(true, Ordering::AcqRel) {
        return;
    }

    let runtime = match crate::get_runtime() {
        Ok(rt) => rt,
        Err(err) => {
            POLL_WATCHER_STARTED.store(false, Ordering::Release);
            tracing::warn!(
                "Hot-plug polling watcher could not acquire runtime: {} (skipping)",
                err
            );
            return;
        }
    };

    POLL_WATCHER_SHUTDOWN.store(false, Ordering::Release);
    runtime.spawn(async {
        tracing::info!(
            "Hot-plug poll watcher started (interval={}s, types={:?})",
            HOTPLUG_POLL_INTERVAL.as_secs(),
            POLLED_DEVICE_TYPES
        );
        // Seed the cache on first tick without emitting events. Anything
        // that was already plugged in when the listener started is
        // already-known state, not a "newly arrived" device.
        let mut first_tick = true;
        loop {
            if POLL_WATCHER_SHUTDOWN.load(Ordering::Acquire) {
                tracing::info!("Hot-plug poll watcher exiting on shutdown request");
                break;
            }
            tokio::time::sleep(HOTPLUG_POLL_INTERVAL).await;
            if POLL_WATCHER_SHUTDOWN.load(Ordering::Acquire) {
                break;
            }
            poll_once(first_tick).await;
            first_tick = false;
        }
    });
}

/// Walk the native + ASCOM (on Windows) device lists for each polled device
/// type and diff against the cached set. Emits one event per (arrived /
/// removed) device.
async fn poll_once(suppress_events: bool) {
    let mut observed: HashMap<(DriverType, String), CachedDevice> = HashMap::new();

    for &device_type in POLLED_DEVICE_TYPES {
        // Native (vendor SDK) backend — always polled, the SDK enumerates
        // are local and don't touch the network.
        match crate::api::discovery::scan_native_for_type_public(device_type).await {
            Ok(devices) => {
                for dev in devices {
                    observed.insert(
                        (DriverType::Native, dev.id.clone()),
                        CachedDevice {
                            device_type: dev.device_type,
                            name: dev.name.clone(),
                            unique_id: dev.unique_id.clone(),
                            display_name: dev.display_name.clone(),
                        },
                    );
                }
            }
            Err(err) => {
                tracing::debug!(
                    "Hot-plug poll: native scan for {:?} failed: {}",
                    device_type,
                    err
                );
            }
        }

        // ASCOM only on Windows. The ASCOM Profile registry doesn't model
        // hot-plug; this catches users registering a driver via the chooser
        // mid-session and is cheap (registry read).
        #[cfg(windows)]
        match crate::api::discovery::scan_ascom_for_type_public(device_type).await {
            Ok(devices) => {
                for dev in devices {
                    observed.insert(
                        (DriverType::Ascom, dev.id.clone()),
                        CachedDevice {
                            device_type: dev.device_type,
                            name: dev.name.clone(),
                            unique_id: dev.unique_id.clone(),
                            display_name: dev.display_name.clone(),
                        },
                    );
                }
            }
            Err(err) => {
                tracing::debug!(
                    "Hot-plug poll: ASCOM scan for {:?} failed: {}",
                    device_type,
                    err
                );
            }
        }
    }

    // Diff against the cache. We do the diff and the cache update in a single
    // lock scope so two concurrent poll ticks can't double-emit the same
    // arrival. POLL_WATCHER_STARTED guarantees only one tokio task is running,
    // but the lock is cheap insurance.
    let (arrivals, removals) = {
        let mut cache = device_cache().lock().expect("device cache mutex poisoned");
        let previous_keys: HashSet<(DriverType, String)> = cache.keys().cloned().collect();
        let observed_keys: HashSet<(DriverType, String)> = observed.keys().cloned().collect();

        let arrival_keys: Vec<(DriverType, String)> =
            observed_keys.difference(&previous_keys).cloned().collect();
        let removal_keys: Vec<(DriverType, String)> =
            previous_keys.difference(&observed_keys).cloned().collect();

        let arrivals: Vec<(DriverType, String, CachedDevice)> = arrival_keys
            .iter()
            .filter_map(|key| {
                observed
                    .get(key)
                    .map(|dev| (key.0, key.1.clone(), dev.clone()))
            })
            .collect();
        let removals: Vec<(DriverType, String, CachedDevice)> = removal_keys
            .iter()
            .filter_map(|key| {
                cache
                    .get(key)
                    .map(|dev| (key.0, key.1.clone(), dev.clone()))
            })
            .collect();

        *cache = observed;
        (arrivals, removals)
    };

    if suppress_events {
        if !arrivals.is_empty() {
            tracing::debug!(
                "Hot-plug poll: seeded cache with {} devices on first tick",
                arrivals.len()
            );
        }
        return;
    }

    if arrivals.is_empty() && removals.is_empty() {
        return;
    }

    // Real change set — flush the discovery cache so the next user-driven
    // discovery scan picks up the new state instead of serving the stale TTL.
    invalidate_discovery_caches();

    for (driver, id, dev) in arrivals {
        let value = encode_device_payload(driver, &id, &dev);
        tracing::info!(
            "Hot-plug arrival: driver={:?} type={:?} id={} name={}",
            driver,
            dev.device_type,
            id,
            dev.name
        );
        get_state().publish_equipment_event(
            EquipmentEvent::PropertyChanged {
                device_type: device_type_str(dev.device_type).to_string(),
                device_id: id,
                property: "device_discovered".to_string(),
                value,
            },
            EventSeverity::Info,
        );
    }

    for (driver, id, dev) in removals {
        let value = encode_device_payload(driver, &id, &dev);
        tracing::info!(
            "Hot-plug removal: driver={:?} type={:?} id={} name={}",
            driver,
            dev.device_type,
            id,
            dev.name
        );
        get_state().publish_equipment_event(
            EquipmentEvent::PropertyChanged {
                device_type: device_type_str(dev.device_type).to_string(),
                device_id: id,
                property: "device_lost".to_string(),
                value,
            },
            EventSeverity::Warning,
        );
    }
}

fn encode_device_payload(driver: DriverType, id: &str, dev: &CachedDevice) -> String {
    // We hand-build the JSON to avoid taking a serde_json dep just for this
    // four-field map. The keys match the Dart bridge_event_mapper expectations.
    fn esc(s: &str) -> String {
        let mut out = String::with_capacity(s.len() + 2);
        out.push('"');
        for ch in s.chars() {
            match ch {
                '"' => out.push_str("\\\""),
                '\\' => out.push_str("\\\\"),
                '\n' => out.push_str("\\n"),
                '\r' => out.push_str("\\r"),
                '\t' => out.push_str("\\t"),
                c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
                c => out.push(c),
            }
        }
        out.push('"');
        out
    }

    let unique_id = match dev.unique_id.as_deref() {
        Some(u) if !u.is_empty() => format!(",\"uniqueId\":{}", esc(u)),
        _ => String::new(),
    };

    format!(
        "{{\"driver\":{driver},\"deviceClass\":{class},\"id\":{id},\"name\":{name},\"displayName\":{display}{unique}}}",
        driver = esc(driver_type_str(driver)),
        class = esc(device_type_str(dev.device_type)),
        id = esc(id),
        name = esc(&dev.name),
        display = esc(&dev.display_name),
        unique = unique_id,
    )
}

fn device_type_str(t: DeviceType) -> &'static str {
    match t {
        DeviceType::Camera => "camera",
        DeviceType::Mount => "mount",
        DeviceType::Focuser => "focuser",
        DeviceType::FilterWheel => "filterWheel",
        DeviceType::Rotator => "rotator",
        DeviceType::Dome => "dome",
        DeviceType::Weather => "weather",
        DeviceType::SafetyMonitor => "safetyMonitor",
        DeviceType::CoverCalibrator => "coverCalibrator",
        DeviceType::Switch => "switch",
        DeviceType::Guider => "guider",
    }
}

fn driver_type_str(d: DriverType) -> &'static str {
    match d {
        DriverType::Native => "native",
        DriverType::Ascom => "ascom",
        DriverType::Alpaca => "alpaca",
        DriverType::Indi => "indi",
        DriverType::Simulator => "simulator",
    }
}

fn publish_device_change(action: &str) {
    invalidate_discovery_caches();
    get_state().publish_equipment_event(
        EquipmentEvent::PropertyChanged {
            device_type: "system".to_string(),
            device_id: "device-bus".to_string(),
            property: "device_change".to_string(),
            value: action.to_string(),
        },
        EventSeverity::Info,
    );
}

fn invalidate_discovery_caches() {
    match crate::get_runtime() {
        Ok(runtime) => {
            runtime.spawn(async {
                api_invalidate_discovery_cache().await;
            });
        }
        Err(err) => {
            tracing::warn!(
                "Device-change event could not invalidate discovery cache: {}",
                err
            );
        }
    }
}

fn should_publish_device_change(now_ms: u64) -> bool {
    let previous = LAST_PUBLISHED_MS.load(Ordering::Acquire);
    if now_ms.saturating_sub(previous) < HOTPLUG_DEBOUNCE_MS {
        return false;
    }

    LAST_PUBLISHED_MS
        .compare_exchange(previous, now_ms, Ordering::AcqRel, Ordering::Acquire)
        .is_ok()
}

fn current_time_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(u128::from(u64::MAX)) as u64
}

#[cfg(all(unix, any(target_os = "linux", target_os = "macos")))]
struct UsbHotplugHandler;

#[cfg(all(unix, any(target_os = "linux", target_os = "macos")))]
impl<T: rusb::UsbContext> rusb::Hotplug<T> for UsbHotplugHandler {
    fn device_arrived(&mut self, device: rusb::Device<T>) {
        handle_usb_hotplug("arrival", &device);
    }

    fn device_left(&mut self, device: rusb::Device<T>) {
        handle_usb_hotplug("removal", &device);
    }
}

#[cfg(all(unix, any(target_os = "linux", target_os = "macos")))]
fn handle_usb_hotplug<T: rusb::UsbContext>(action: &'static str, device: &rusb::Device<T>) {
    let now_ms = current_time_ms();
    if !should_publish_device_change(now_ms) {
        tracing::debug!(
            "Debounced USB hotplug action={} bus={} address={}",
            action,
            device.bus_number(),
            device.address()
        );
        return;
    }

    tracing::info!(
        "USB hotplug event received: action={} bus={} address={}",
        action,
        device.bus_number(),
        device.address()
    );
    publish_device_change(action);
}

#[cfg(all(unix, any(target_os = "linux", target_os = "macos")))]
fn usb_hotplug_thread() {
    use rusb::{Context, HotplugBuilder, UsbContext};
    use std::time::Duration;

    if !rusb::has_hotplug() {
        LISTENER_STARTED.store(false, Ordering::Release);
        tracing::warn!("libusb hotplug support is unavailable on this platform");
        return;
    }

    let context = match Context::new() {
        Ok(context) => context,
        Err(err) => {
            LISTENER_STARTED.store(false, Ordering::Release);
            tracing::warn!("Failed to initialize libusb hotplug context: {}", err);
            return;
        }
    };

    let _registration = match HotplugBuilder::new()
        .enumerate(false)
        .register(&context, Box::new(UsbHotplugHandler))
    {
        Ok(registration) => registration,
        Err(err) => {
            LISTENER_STARTED.store(false, Ordering::Release);
            tracing::warn!("Failed to register libusb hotplug callback: {}", err);
            return;
        }
    };

    tracing::info!("USB hotplug listener started");
    loop {
        if let Err(err) = context.handle_events(None) {
            tracing::warn!("USB hotplug event loop error: {}", err);
            std::thread::sleep(Duration::from_millis(250));
        }
    }
}

#[cfg(windows)]
fn device_change_action(wparam: usize) -> Option<&'static str> {
    match wparam {
        DBT_DEVICEARRIVAL => Some("arrival"),
        DBT_DEVICEREMOVECOMPLETE => Some("removal"),
        DBT_DEVNODES_CHANGED => Some("changed"),
        _ => None,
    }
}

#[cfg(windows)]
fn handle_windows_device_change(wparam: usize) {
    let Some(action) = device_change_action(wparam) else {
        return;
    };

    let now_ms = current_time_ms();
    if !should_publish_device_change(now_ms) {
        tracing::debug!("Debounced Windows WM_DEVICECHANGE action={}", action);
        return;
    }

    tracing::info!("Windows device-change event received: {}", action);
    publish_device_change(action);
}

#[cfg(windows)]
fn windows_device_change_thread() {
    use windows::core::{w, PCWSTR};
    use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
    use windows::Win32::System::LibraryLoader::GetModuleHandleW;
    use windows::Win32::UI::WindowsAndMessaging::{
        CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW, RegisterClassW,
        TranslateMessage, MSG, WINDOW_EX_STYLE, WINDOW_STYLE, WM_DEVICECHANGE, WNDCLASSW,
    };

    unsafe extern "system" fn wnd_proc(
        hwnd: HWND,
        msg: u32,
        wparam: WPARAM,
        lparam: LPARAM,
    ) -> LRESULT {
        if msg == WM_DEVICECHANGE {
            handle_windows_device_change(wparam.0);
        }

        // SAFETY: Forwarding unhandled messages to DefWindowProcW is the
        // documented default window procedure path for a Win32 window proc.
        unsafe { DefWindowProcW(hwnd, msg, wparam, lparam) }
    }

    // SAFETY: This thread owns the hidden window and its message loop. All
    // Win32 pointers passed here are either null/default handles or static
    // UTF-16 string pointers created by `w!`.
    unsafe {
        let Ok(module) = GetModuleHandleW(None) else {
            tracing::warn!("Windows device-change listener could not get module handle");
            LISTENER_STARTED.store(false, Ordering::Release);
            return;
        };
        let hinstance = module.into();
        let class_name = w!("NightshadeDeviceChangeWindow");
        let wnd_class = WNDCLASSW {
            hInstance: hinstance,
            lpszClassName: class_name,
            lpfnWndProc: Some(wnd_proc),
            ..Default::default()
        };

        if RegisterClassW(&wnd_class) == 0 {
            tracing::warn!("Windows device-change listener could not register window class");
            LISTENER_STARTED.store(false, Ordering::Release);
            return;
        }

        let hwnd = CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            class_name,
            PCWSTR::null(),
            WINDOW_STYLE::default(),
            0,
            0,
            0,
            0,
            HWND::default(),
            None,
            hinstance,
            None,
        );

        if hwnd.0 == 0 {
            tracing::warn!("Windows device-change listener could not create hidden window");
            LISTENER_STARTED.store(false, Ordering::Release);
            return;
        }

        tracing::info!("Windows device-change listener started");
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, HWND::default(), 0, 0).into() {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debounce_suppresses_close_device_change_events() {
        LAST_PUBLISHED_MS.store(1_000, Ordering::Release);

        assert!(!should_publish_device_change(1_250));
        assert!(should_publish_device_change(1_600));
        assert_eq!(LAST_PUBLISHED_MS.load(Ordering::Acquire), 1_600);
    }

    #[cfg(windows)]
    #[test]
    fn windows_device_change_action_maps_known_messages() {
        assert_eq!(device_change_action(DBT_DEVICEARRIVAL), Some("arrival"));
        assert_eq!(
            device_change_action(DBT_DEVICEREMOVECOMPLETE),
            Some("removal")
        );
        assert_eq!(device_change_action(DBT_DEVNODES_CHANGED), Some("changed"));
        assert_eq!(device_change_action(0xFFFF), None);
    }

    #[test]
    fn driver_and_device_type_strings_are_stable() {
        // The Dart side keys off these strings — keep them lowercase and
        // matching the canonical enum names the rest of the bridge uses.
        assert_eq!(driver_type_str(DriverType::Native), "native");
        assert_eq!(driver_type_str(DriverType::Ascom), "ascom");
        assert_eq!(driver_type_str(DriverType::Alpaca), "alpaca");
        assert_eq!(driver_type_str(DriverType::Indi), "indi");
        assert_eq!(device_type_str(DeviceType::Camera), "camera");
        assert_eq!(device_type_str(DeviceType::FilterWheel), "filterWheel");
        assert_eq!(device_type_str(DeviceType::Mount), "mount");
    }

    #[test]
    fn payload_encoding_escapes_special_chars() {
        let dev = CachedDevice {
            device_type: DeviceType::Camera,
            name: "ZWO ASI \"533\"".to_string(),
            unique_id: Some("usb-1234".to_string()),
            display_name: "ZWO ASI 533".to_string(),
        };
        let payload = encode_device_payload(DriverType::Native, "native:zwo:0", &dev);
        // Quotes inside name must be escaped.
        assert!(
            payload.contains("ZWO ASI \\\"533\\\""),
            "expected escaped quotes in payload, got: {}",
            payload
        );
        // All expected keys present.
        assert!(payload.contains("\"driver\":\"native\""));
        assert!(payload.contains("\"deviceClass\":\"camera\""));
        assert!(payload.contains("\"id\":\"native:zwo:0\""));
        assert!(payload.contains("\"uniqueId\":\"usb-1234\""));
    }

    #[test]
    fn payload_omits_empty_unique_id() {
        let dev = CachedDevice {
            device_type: DeviceType::Mount,
            name: "AZ-GTi".to_string(),
            unique_id: None,
            display_name: "AZ-GTi".to_string(),
        };
        let payload = encode_device_payload(DriverType::Native, "native:sw:0", &dev);
        assert!(!payload.contains("uniqueId"), "payload: {}", payload);
    }
}
