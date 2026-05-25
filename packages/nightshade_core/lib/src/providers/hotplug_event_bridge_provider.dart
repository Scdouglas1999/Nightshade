// Wave 6B (P2-1) — Hot-plug discovery event bridge.
//
// The Rust hot-plug watcher in `native/nightshade_native/bridge/src/hotplug.rs`
// polls the native (vendor SDK) and ASCOM (Windows only) device lists every
// 4 seconds and publishes one `EquipmentEvent::PropertyChanged` per arrival
// or removal with `property: 'device_discovered' | 'device_lost'` and a
// JSON-encoded device payload. Linux/macOS additionally get fine-grained
// libusb hot-plug callbacks; Windows gets WM_DEVICECHANGE notifications;
// all three paths emit through the same Equipment event channel.
//
// This bridge listens on `backend.eventStream` for those events and
// invalidates the equipment-discovery Riverpod providers
// (`availableCamerasProvider`, `availableMountsProvider`, ...,
// `unifiedDiscoveryProvider`) so the equipment screen refreshes inside
// the configured ~3 s P2-1 budget without any user-driven pull-to-refresh.
//
// The bridge is side-effecting and produces no state. To stay alive, the
// surrounding app must `ref.watch(hotplugEventBridgeProvider)` somewhere
// in its bootstrap (the desktop/mobile dashboard scaffolding does this
// alongside the other event bridges).

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/backend/event_types.dart' as core_events;
import '../services/device_service.dart';
import 'backend_provider.dart';
import 'unified_discovery_provider.dart';

/// Bridge that watches the backend event stream for hot-plug arrivals /
/// removals and invalidates the per-class discovery providers so the next
/// UI read re-runs the underlying scan.
///
/// Producing no state, this provider is bound to its container lifetime;
/// reading it once (via `ref.watch` from a long-lived widget) is enough to
/// keep the subscription alive.
final hotplugEventBridgeProvider = Provider<void>((ref) {
  final backend = ref.watch(backendProvider);

  StreamSubscription<core_events.NightshadeEvent>? subscription;
  subscription = backend.eventStream.listen(
    (event) {
      if (event.category != core_events.EventCategory.equipment) return;
      // The Rust hot-plug watcher rides on `PropertyChanged` while the
      // typed `DeviceDiscovered` / `DeviceLost` variants wait for an FRB
      // regen (see event.rs TODO). The wire shape is:
      //   eventType: 'PropertyChanged'
      //   data.property: 'device_discovered' | 'device_lost'
      // so a simple eventType filter is not enough — we must inspect
      // `data.property` to distinguish hot-plug events from the unrelated
      // (and frequent) Mount / Camera / Focuser property-changed traffic.
      if (event.eventType != 'PropertyChanged') return;
      final property = event.data['property'];
      if (property != core_events.deviceDiscoveredProperty &&
          property != core_events.deviceLostProperty) {
        return;
      }

      developer.log(
        '[HotplugEventBridge] $property: ${event.data['value']}',
        name: 'HotplugEventBridge',
        level: 800,
      );

      // Invalidate every per-class discovery provider so the next read
      // re-runs the scan. We invalidate the full set rather than trying
      // to pick the matching class because a single hot-plug event can
      // affect multiple lists (a USB-Serial bridge that registers both a
      // mount and a focuser, an OAG that exposes both a camera and a
      // filter wheel, etc.). The cost is one extra scan per event; the
      // 4 s polling cadence means at most a few invalidations per
      // session even in the most active observatory.
      ref.invalidate(availableCamerasProvider);
      ref.invalidate(availableMountsProvider);
      ref.invalidate(availableFocusersProvider);
      ref.invalidate(availableFilterWheelsProvider);
      ref.invalidate(availableRotatorsProvider);
      ref.invalidate(availableGuidersProvider);
      ref.invalidate(availableDomesProvider);
      ref.invalidate(availableWeatherProvider);
      ref.invalidate(availableSafetyMonitorsProvider);
      ref.invalidate(availableSwitchesProvider);

      // The unified discovery state is a StateNotifier — invalidating it
      // would lose the in-progress scan, which is the wrong behaviour
      // when an arrival lands during a manual rescan. Instead, re-read
      // the notifier and let its next discover call pull the fresh
      // vendor-SDK list. We deliberately do NOT trigger a `discoverAll`
      // from here: that would saturate the LAN if the polling watcher
      // batches arrivals (e.g. plugging in a powered USB hub). The
      // per-class FutureProvider invalidations above are enough to
      // refresh the equipment screen's primary lists.
      try {
        ref.read(unifiedDiscoveryProvider.notifier);
      } catch (_) {
        // Provider not yet read by any UI — nothing to do, the next
        // read will see the invalidated per-class FutureProviders.
      }
    },
    onError: (Object error) {
      developer.log(
        '[HotplugEventBridge] Event stream error: $error',
        name: 'HotplugEventBridge',
        level: 1000,
        error: error,
      );
    },
  );

  ref.onDispose(() {
    subscription?.cancel();
  });
});
