# 8. Supporting Packages Audit

## Rating Scale
- **Production-Ready**: Complete, tested, handles edge cases
- **Functional**: Works for primary use cases, minor gaps
- **Partial**: Core structure exists, significant missing pieces
- **Scaffold**: API/structure defined, minimal implementation

---

## 1. Planetarium (`packages/nightshade_planetarium/`)

**Overall Rating: Functional (strong)**

### File Statistics
- **36 Dart files**, ~20,029 total lines of code
- Largest file: `sky_renderer.dart` (3,491 lines)
- 2 test files

### Feature Inventory

| Feature | Status | Key Files |
|---------|--------|-----------|
| Star rendering (HYG catalog, ~120K stars) | Production-Ready | `star_catalog.dart`, `sky_renderer.dart` |
| DSO rendering (OpenNGC, ~13K+ objects) | Production-Ready | `catalog.dart:20-475` (OpenNgcDsoCatalog) |
| Constellation lines & labels | Production-Ready | `constellation_data.dart`, `sky_renderer.dart:256-300` |
| Coordinate transformations (RA/Dec, Alt/Az) | Production-Ready | `coordinate_system.dart:1-140` |
| Stereographic/orthographic/equidistant projections | Production-Ready | `sky_renderer.dart:154-158` (SkyProjection enum) |
| Milky Way rendering | Functional | `milky_way_data.dart` |
| Planetary positions (Sun, Moon, planets) | Functional | `planetary_positions.dart`, config flags in `sky_renderer.dart:38-42` |
| FOV overlays (camera, eyepiece, Telrad, finder) | Production-Ready | `fov_overlays.dart:1-80` (6 FOV types) |
| Interactive pan/zoom/momentum/twinkle | Production-Ready | `interactive_sky_view.dart` (899 lines) |
| Coordinate grids (Alt/Az, equatorial, ecliptic) | Production-Ready | `sky_renderer.dart:33-43` |
| Ground plane, horizon, meridian rendering | Production-Ready | `sky_renderer.dart:44-83` |
| Mount position indicator | Functional | `sky_renderer.dart:68` |
| Label anti-overlap (LabelLayoutManager) | Production-Ready | `sky_renderer.dart:194-235` |
| Paint cache for performance | Production-Ready | `sky_renderer.dart:237-299` |
| Star PSF cache | Production-Ready | `star_psf_cache.dart` |
| Catalog packages (Essential/Standard/Pro/Ultra) | Functional | `catalog_manager.dart` (tiered download system) |
| Spatial indexing for object queries | Functional | `spatial_index.dart` |
| Survey image overlay service | Functional | `survey_image_service.dart` |
| Mosaic planner | Functional | `mosaic_planner.dart` |
| Target scoring & planning | Functional | `target_scoring.dart` |
| HyperLEDA galaxy catalog | Functional | `hyperleda_catalog.dart` |
| GLADE+ galaxy catalog | Functional | `glade_plus_catalog.dart` |
| Annotation catalog | Functional | `annotation_catalog.dart` |
| Geolocation service | Functional | `geolocation_service.dart` |
| Framing view widget | Functional | `framing_view.dart` |
| Compass HUD | Functional | `compass_hud.dart` |
| Sky minimap | Functional | `sky_minimap.dart` |
| Time control panel | Functional | `time_control_panel.dart` |
| Object details panel | Functional | `object_details_panel.dart` |
| Adaptive layout | Functional | `adaptive_layout.dart` |
| Render quality configuration | Functional | `render_quality.dart` |

### Implementation Quality

**Strengths:**
- Real catalog parsing from HYG and OpenNGC databases with proper CSV parsing (`star_catalog.dart:119-178`)
- Background isolate loading via `compute()` for large catalogs (`star_catalog.dart:68`)
- Tiered catalog system allowing users to download only what they need (`catalog_manager.dart`)
- Extensive `SkyRenderConfig` with 25+ configurable rendering options (`sky_renderer.dart:25-84`)
- Three projection modes: stereographic, orthographic, azimuthal equidistant
- Proper stereographic projection math in `sky_view.dart:378-425`
- Correct Julian Date and Local Sidereal Time calculations (`coordinate_system.dart:59-79`)
- Performance-optimized paint cache avoids per-frame GC pressure (`sky_renderer.dart:237-299`)
- Star color rendering from color index values
- Fallback bright star list (~80 stars) when catalogs not installed (`star_catalog.dart:343-428`)
- Label anti-overlap system with multiple placement attempts (`sky_renderer.dart:194-235`)
- Red night vision theme support (astronomy-specific)
- Smooth zoom, momentum panning, star twinkle animations (`interactive_sky_view.dart`)
- DSO type-specific symbols (galaxies=ellipses, nebulae=squares, clusters=circles with dots in `sky_view.dart:336-375`)

**Weaknesses:**
- Uses `CustomPaint` (Canvas 2D) rather than GPU shaders -- adequate for the feature set but not "GPU rendering" as library name suggests
- `sky_view.dart:64` catches error but only calls `debugPrint` -- should surface to user
- `star_catalog.dart:101-103` silently catches and skips all parse errors in CSV lines
- `coordinate_system.dart` stores RA differently between files (hours in CelestialCoordinate but `star_catalog.dart:169` converts to degrees before storing -- **BUG**: `CelestialCoordinate.ra` is documented as "hours (0-24)" but star_catalog stores degrees)
- No proper mutex/lock for concurrent `loadObjects()` calls; uses busy-wait loop (`star_catalog.dart:48-51`)
- `sky_view.dart` (the simpler SkyView) duplicates coordinate logic that already exists in the full renderer

### Bugs Found

1. **RA unit mismatch** (`star_catalog.dart:169`): `CelestialCoordinate(ra: raHours * 15, dec: dec)` converts RA to degrees, but `CelestialCoordinate.ra` is documented as hours (`coordinate_system.dart:5-6`). The `toHorizontal()` method treats `ra` as hours and multiplies by 15 again (`coordinate_system.dart:36`). This would cause all stars to be positioned incorrectly unless the star catalog path is unused and the fallback stars also use degrees (they do -- `star_catalog.dart:345`: `ra: 101.286` for Sirius). So the `CelestialCoordinate` documentation is wrong -- RA is actually stored in degrees throughout.

2. **Busy-wait antipattern** (`star_catalog.dart:48-51`, `catalog.dart:51-56`): Uses `while (_isLoading) { await Future.delayed(...) }` instead of a Completer or similar synchronization primitive.

### Test Coverage
- `star_psf_shader_cache_test.dart` -- tests PSF cache
- `planetarium_providers_test.dart` -- tests provider state
- **No tests** for coordinate transforms, catalog parsing, or projection math

---

## 2. Updater (`packages/nightshade_updater/`)

**Overall Rating: Production-Ready**

### File Statistics
- **12 Dart files** (including generated freezed/json files)
- 1 test file

### Feature Inventory

| Feature | Status | Key Files |
|---------|--------|-----------|
| Update manifest (freezed model) | Production-Ready | `update_manifest.dart:1-131` |
| Version checking against server | Production-Ready | `update_service.dart:55-115` |
| Package download with progress | Production-Ready | `update_downloader.dart:42-134` |
| Download resume via Range headers | Production-Ready | `update_downloader.dart:62-103` |
| Download cancellation via CancelToken | Production-Ready | `update_downloader.dart:12-21` |
| SHA-256 verification (file hash + size) | Production-Ready | `update_verifier.dart:9-89` |
| Directory verification against manifest | Production-Ready | `update_verifier.dart:29-61` |
| ZIP extraction | Production-Ready | `update_service.dart:200-215` |
| Staged update system (ready.json marker) | Production-Ready | `update_service.dart:188-197` |
| External updater launch | Production-Ready | `update_service.dart:269-336` |
| Backup before applying | Production-Ready | `update_service.dart:278,346-353` |
| LAN push receiver (TCP socket) | Production-Ready | `lan_push_receiver.dart:22-285` |
| Binary push protocol (length-prefixed) | Production-Ready | `lan_push_receiver.dart:102-187` |
| LAN push discovery via UDP broadcast | Production-Ready | `discovery.dart:156-295` (UpdatePushDiscovery) |
| Update channels (stable, beta) | Production-Ready | `update_service.dart:47-52` |
| Min version upgrade constraints | Production-Ready | `update_manifest.dart:82-94` |
| Update state management (Riverpod) | Functional | `update_provider.dart` |
| Update UI widget | Functional | `update_manager_widget.dart` |
| LAN push event stream (global notifier) | Production-Ready | `nightshade_updater.dart:29-77` |

### Implementation Quality

**Strengths:**
- Complete end-to-end OTA update pipeline: check -> download -> verify -> stage -> apply
- SHA-256 integrity verification at both package level and per-file level (`update_verifier.dart`)
- Resumable downloads with proper Range header handling (`update_downloader.dart:62-103`)
- Binary TCP protocol for LAN push with manifest-prefixed framing (`lan_push_receiver.dart:102-187`)
- Updater bootstrapping: if `updater.exe` missing from install dir, copies from staged update (`update_service.dart:285-313`)
- Detailed error messages with solutions (`update_service.dart:305-313`)
- Sealed class pattern for LAN push events (`nightshade_updater.dart:52-77`)
- Proper channel-based update system with version comparison
- Size verification before hash verification for efficiency

**Weaknesses:**
- `update_service.dart:335`: Calls `exit(0)` directly -- could corrupt data if not flushed
- No rollback mechanism if the external updater fails mid-copy (relies on backup directory, but no automatic restore)
- ZIP extraction reads entire file into memory (`update_service.dart:201`) -- problematic for very large updates
- LAN push receiver lacks authentication -- any device on the local network can push updates

### Bugs Found

1. **Missing authentication on LAN push** (`lan_push_receiver.dart:57-67`): The TCP server accepts connections from any IP with no authentication. An attacker on the same network could push malicious updates.

2. **Potential null reference** (`update_downloader.dart:98`): `streamedResponse.contentLength!` force-unwrap could crash if the header is missing and no expected size is provided.

### Test Coverage
- `lan_push_test.dart` -- 1 test file
- No tests for download resume, verification, or version comparison logic

---

## 3. WebRTC (`packages/nightshade_webrtc/`)

**Overall Rating: Functional (strong)**

### File Statistics
- **13 Dart files** (including generated DB file)
- 0 test files

### Feature Inventory

| Feature | Status | Key Files |
|---------|--------|-----------|
| WebRTC peer connection (data channel) | Production-Ready | `peer_connection.dart:1-99` |
| Basic signaling server (TCP) | Production-Ready | `signaling.dart:1-117` |
| Secure signaling server (encrypted) | Production-Ready | `secure_signaling_server.dart:1-455` |
| UDP broadcast discovery | Production-Ready | `discovery.dart:31-153` |
| Secure discovery (paired-only/pairing/hidden modes) | Production-Ready | `secure_discovery.dart:1-393` |
| Enhanced discovery | Functional | `enhanced_discovery.dart` |
| Token-based pairing (memorable codes like "STAR-1234") | Production-Ready | `token_manager.dart:1-221` |
| AES-256-GCM channel encryption | Production-Ready | `channel_encryption.dart:1-201` |
| PBKDF2 key derivation (100K iterations) | Production-Ready | `channel_encryption.dart:140-149` |
| Paired devices database (Drift/SQLite) | Production-Ready | `pairing_database.dart`, `paired_devices_table.dart` |
| Device revocation | Production-Ready | `token_manager.dart:168-175` |
| Constant-time token comparison | Production-Ready | `token_manager.dart:202-213` |
| REST API web server (full device control) | Production-Ready | `web_server.dart` (2,992 lines) |
| Heartbeat & timeout management | Production-Ready | `secure_signaling_server.dart:394-419` |
| Authentication timeout (10 seconds) | Production-Ready | `secure_signaling_server.dart:181-188` |

### Implementation Quality

**Strengths:**
- Comprehensive security architecture:
  - PBKDF2 with 100,000 iterations (OWASP recommended) for key derivation (`channel_encryption.dart:21`)
  - AES-256-GCM encryption with random nonces (`channel_encryption.dart:40-68`)
  - Constant-time token comparison to prevent timing attacks (`token_manager.dart:202-213`)
  - Memorable pairing codes from astronomical vocabulary (`token_manager.dart:30-34`)
  - Three discovery modes: pairedOnly, pairing, hidden (`secure_discovery.dart:10-18`)
  - Authentication timeout prevents resource exhaustion (`secure_signaling_server.dart:86`)
- Web server exposes extremely comprehensive REST API (`web_server.dart`, 100+ handler types):
  - Full camera control (expose, abort, cooling, gain/offset)
  - Full mount control (slew, sync, park, tracking, pulse guide)
  - Focuser control (move, halt, autofocus)
  - Filter wheel control (set position, set by name)
  - Rotator control (move, halt, status)
  - Sequence control (start, stop, pause, resume, load)
  - PHD2 guiding control (connect, start/stop, dither, star image, algorithm params)
  - Settings and profile management
  - Plate solving
  - Polar alignment
  - Equipment status and capabilities
  - FITS save and image management
- Key memory zeroing on dispose (`channel_encryption.dart:180-184`)

**Weaknesses:**
- `signaling.dart:59`: Raw socket data converted directly to string without considering message framing -- messages could be fragmented or merged
- `peer_connection.dart` missing ICE candidate event forwarding (only listens for data channel, not `onIceCandidate`)
- No TLS/SSL on the web server -- all HTTP traffic is plaintext on the local network
- `channel_encryption.dart:153-158`: Nonce generation uses `DateTime.now().microsecondsSinceEpoch` as seed, which has low entropy. Should use `dart:math` `Random.secure()` instead

### Bugs Found

1. **Weak nonce seed** (`channel_encryption.dart:153-158`): The Fortuna PRNG is seeded with `DateTime.now().microsecondsSinceEpoch & 0xFF` repeated 32 times. Each byte is only the lowest 8 bits of the microsecond timestamp, meaning only 256 possible values per byte. This significantly reduces nonce randomness. Should use `Random.secure()`.

2. **Missing ICE candidate forwarding** (`peer_connection.dart`): The `NightshadePeerConnection` class never sets `_peerConnection!.onIceCandidate`, so the initiator has no way to relay ICE candidates to the answerer. WebRTC connections will likely fail in scenarios requiring STUN/relay.

3. **TCP message framing** (`signaling.dart:58-66`): The `_handleConnection` converts raw socket bytes to string without handling message boundaries. TCP does not guarantee message framing -- a single `data` event may contain partial or multiple messages.

### Test Coverage
- **No test files** -- this is a significant gap given the security-critical nature of the code

---

## 4. Plugins (`packages/nightshade_plugins/`)

**Overall Rating: Scaffold (well-designed)**

### File Statistics
- **5 Dart files**, 1 test file

### Feature Inventory

| Feature | Status | Key Files |
|---------|--------|-----------|
| Plugin API (NightshadePlugin interface) | Production-Ready | `plugin_api.dart:7-61` |
| Plugin lifecycle (load/enable/disable/unload) | Production-Ready | `plugin_api.dart:33-52` |
| Plugin context (logger, storage, events) | Production-Ready | `plugin_api.dart:63-82` |
| PluginLogger (console/developer log) | Production-Ready | `plugin_context.dart:7-38` |
| PluginStorage (key-value, in-memory only) | Partial | `plugin_context.dart:44-101` |
| PluginEventBus (pub/sub pattern) | Production-Ready | `plugin_context.dart:104-147` |
| PluginHost (registry, lifecycle management) | Production-Ready | `plugin_host.dart:86-281` |
| UiPlugin (UI extension points) | Scaffold | `plugin_api.dart:197-231` |
| DevicePlugin (hardware driver extension) | Scaffold | `plugin_api.dart:234-249` |
| SequencePlugin (custom sequence nodes) | Scaffold | `plugin_api.dart:252-272` |
| Example plugins (4 types) | Functional | `example_plugin.dart:1-285` |
| Riverpod integration | Production-Ready | `plugin_host.dart:284-296` |

### Implementation Quality

**Strengths:**
- Clean, well-documented API with reverse domain notation for IDs (`plugin_api.dart:11`)
- Proper lifecycle with load/enable/disable/unload stages
- Error handling in plugin registration stores error state but continues (`plugin_host.dart:178-190`)
- Plugin disposal in reverse order of registration (`plugin_host.dart:267-268`)
- Three specialized plugin types: UiPlugin, DevicePlugin, SequencePlugin
- UI extension point system with defined insertion points (`plugin_api.dart:203-218`)
- Complete example plugins demonstrating each type (`example_plugin.dart`)
- Riverpod provider integration (`plugin_host.dart:284-296`)

**Weaknesses:**
- **Storage is in-memory only** (`plugin_context.dart:44`, comment on line 43 says "should be backed by SharedPreferences, SQLite, or another persistent storage mechanism") -- plugin data is lost on restart
- No plugin loading from external sources (e.g., from disk, packages, or URLs) -- only programmatic registration
- UiPlugin `widgetBuilder` returns `dynamic` instead of `Widget?` (`plugin_api.dart:224`)
- Example plugins return `null` from `widgetBuilder` and `createNode` -- not real implementations
- DevicePlugin has no actual device integration API -- just declares supported device types
- SequencePlugin `createNode` returns `dynamic` instead of a concrete node type
- No plugin dependency management (one plugin depending on another)
- No plugin sandboxing or permission system
- No versioned API compatibility checking (only `minAppVersion` string)

### Bugs Found

1. **Non-persistent storage** (`plugin_context.dart:44`): `InMemoryPluginStorage` loses all data on app restart. The comment explicitly acknowledges this needs a real persistence backend, but none exists.

2. **Type-unsafe return types** (`plugin_api.dart:224,269`): `widgetBuilder` returns `dynamic` and `createNode` returns `dynamic`. These should be typed as `Widget?` and a proper `SequenceNode` type respectively.

### Test Coverage
- `plugin_system_test.dart` -- 1 test file for basic registration/lifecycle
- No tests for UiPlugin, DevicePlugin, or SequencePlugin types

---

## 5. UI Design System (`packages/nightshade_ui/`)

**Overall Rating: Production-Ready**

### File Statistics
- **37 Dart files**
- 0 test files

### Feature Inventory

| Feature | Status | Key Files |
|---------|--------|-----------|
| **Theme System** | | |
| Dark theme | Production-Ready | `nightshade_theme.dart:46-135` |
| Light theme | Production-Ready | `nightshade_theme.dart:137-226` |
| Red night vision theme | Production-Ready | `nightshade_theme.dart:229-342` |
| Custom accent color support | Production-Ready | `nightshade_theme.dart:344-453` |
| ThemeExtension integration | Production-Ready | `nightshade_colors.dart:3` (extends ThemeExtension) |
| Theme mode provider (Riverpod) | Production-Ready | `nightshade_theme.dart:18-21` |
| **Color System** | | |
| 17 semantic color tokens per theme | Production-Ready | `nightshade_colors.dart:1-192` |
| Surface hierarchy (5 levels) | Production-Ready | `nightshade_colors.dart:7-11` |
| Text hierarchy (primary/secondary/muted) | Production-Ready | `nightshade_colors.dart:12-14` |
| Status colors (success/warning/error/info) | Production-Ready | `nightshade_colors.dart:15-18` |
| Color lerp for theme transitions | Production-Ready | `nightshade_colors.dart:170-191` |
| **Design Tokens** | | |
| Spacing scale (4px grid, 9 sizes) | Production-Ready | `nightshade_tokens.dart:18-42` |
| Edge insets presets (8 variants) | Production-Ready | `nightshade_tokens.dart:48-84` |
| Border radius scale (6 sizes) | Production-Ready | `nightshade_tokens.dart:90-114` |
| Animation durations (10 presets) | Production-Ready | `nightshade_tokens.dart:120-148` |
| Animation curves (7 presets) | Production-Ready | `nightshade_tokens.dart:154-177` |
| Icon sizes (6 sizes) | Production-Ready | `nightshade_tokens.dart:182-198` |
| Responsive breakpoints (5 tiers) | Production-Ready | `nightshade_tokens.dart:204-217` |
| Component sizes (buttons, inputs, sidebar) | Production-Ready | `nightshade_tokens.dart:223-239` |
| Shadow system (3 levels + glow + inset) | Production-Ready | `nightshade_tokens.dart:245-337` |
| Elevation system (3 levels + inset + transition) | Production-Ready | `nightshade_tokens.dart:290-347` |
| Opacity levels (5 presets) | Production-Ready | `nightshade_tokens.dart:352-366` |
| **Typography** | | |
| Heading styles (h1-h6) | Production-Ready | `nightshade_typography.dart:30-88` |
| Body styles (lg/md/sm) | Production-Ready | `nightshade_typography.dart:94-132` |
| Label styles (lg/md/sm) | Production-Ready | `nightshade_typography.dart:138-166` |
| Caption/overline styles | Production-Ready | `nightshade_typography.dart:172-200` |
| Monospace styles (JetBrains Mono, 4 sizes) | Production-Ready | `nightshade_typography.dart:208-241` |
| Special styles (stat value/label, button, input) | Production-Ready | `nightshade_typography.dart:247-302` |
| Helper methods (withColor, bold, italic) | Production-Ready | `nightshade_typography.dart:308-331` |
| **Components** | | |
| NightshadeButton | Production-Ready | `nightshade_button.dart` |
| NightshadeCard | Production-Ready | `nightshade_card.dart` |
| NightshadeDropdown | Production-Ready | `nightshade_dropdown.dart` |
| NightshadeTextField | Production-Ready | `nightshade_text_field.dart` |
| NightshadeCheckbox | Production-Ready | `nightshade_checkbox.dart` |
| NightshadeSwitch | Production-Ready | `nightshade_switch.dart` |
| NightshadeProgressBar | Production-Ready | `nightshade_progress_bar.dart` |
| NightshadeAlert | Production-Ready | `nightshade_alert.dart` |
| NightshadeTooltip | Production-Ready | `nightshade_tooltip.dart` |
| StatusPill | Production-Ready | `status_pill.dart` |
| SubTabButton | Production-Ready | `sub_tab_button.dart` |
| ResponsiveCardGrid | Production-Ready | `responsive_card_grid.dart` |
| ShimmerLoading | Production-Ready | `shimmer_loading.dart` |
| AnimatedIconButton | Production-Ready | `animated_icon_button.dart` |
| AnimatedValue | Production-Ready | `animated_value.dart` |
| HistogramDisplay | Production-Ready | `histogram_display.dart` |
| FocusRing | Production-Ready | `focus_ring.dart` |
| ScreenHeader | Production-Ready | `screen_header.dart` |
| **Widgets** | | |
| PolarAlignmentWizard | Functional | `polar_alignment_wizard.dart` |
| ResizablePanel | Production-Ready | `resizable_panel.dart` |
| ErrorDialog | Production-Ready | `error_dialog.dart` |
| UpdateDialog | Production-Ready | `update_dialog.dart` |
| AccessibleIconButton | Production-Ready | `accessible_icon_button.dart` |
| FocusTraversalScaffold | Production-Ready | `focus_traversal_scaffold.dart` |
| **PHD2 Widgets** | | |
| GuideStarView | Production-Ready | `guide_star_view.dart` |
| GuideTargetDisplay | Production-Ready | `guide_target_display.dart` |
| GuideGraphAdvanced | Production-Ready | `guide_graph_advanced.dart` |
| BrainSettingsPanel | Production-Ready | `brain_settings_panel.dart` |
| GuideControlsPanel | Production-Ready | `guide_controls_panel.dart` |
| CalibrationPanel | Production-Ready | `calibration_panel.dart` |
| **Utils** | | |
| ResponsiveUtils | Production-Ready | `responsive_utils.dart` |
| ScaledConfig | Production-Ready | `scaled_config.dart` |

### Implementation Quality

**Strengths:**
- Comprehensive design token system with consistent 4px grid
- Three theme variants including astronomy-specific red night vision
- Custom accent color generation from any seed color (`nightshade_colors.dart:85-98`)
- ThemeExtension integration for proper theme-aware color access
- Well-structured typography scale with both Inter (UI) and JetBrains Mono (technical values)
- Full PHD2 guiding widget suite -- specialized astrophotography components
- Accessibility support: `AccessibleIconButton`, `FocusTraversalScaffold`, `FocusRing`
- Elevation system designed for dark themes with layered shadows
- Color lerp implementation enables smooth theme transitions

**Weaknesses:**
- **No test files at all** -- design system components should have widget tests
- Red night vision theme reuses same border radius, spacing, and typography values -- should consider reduced contrast for text sizes in low-light
- `nightshade_typography.dart:24`: Accessing `GoogleFonts.jetBrainsMono().fontFamily!` force-unwraps and will crash if the font hasn't been pre-loaded on all platforms

### Bugs Found

None critical. Minor issues:
1. **Force-unwrap on font family** (`nightshade_typography.dart:24`): `GoogleFonts.jetBrainsMono().fontFamily!` could throw if Google Fonts is unavailable (offline, restricted environment).

---

## Cross-Package Issues

### Shared Code Duplication
- `_extractZip()` is duplicated between `update_service.dart:200-215` and `lan_push_receiver.dart:254-269`
- Constellation name mappings are duplicated between `star_catalog.dart:289-339` and `catalog.dart:306-330`
- `getLocalIp()` is duplicated between `signaling.dart:90-100` and `secure_signaling_server.dart:434-444`

### Dependency Graph
- Updater depends on: `archive`, `http`, `path_provider`, `crypto`, `freezed`
- WebRTC depends on: `flutter_webrtc`, `pointycastle`, `crypto`, `drift`
- Plugins depends on: `flutter_riverpod` (minimal)
- UI depends on: `flutter_riverpod`, `google_fonts`
- Planetarium depends on: `http`, `flutter_riverpod`

---

## Summary Table

| Package | Rating | Files | Lines (est.) | Tests | Key Concern |
|---------|--------|-------|-------|-------|-------------|
| Planetarium | Functional (strong) | 36 | ~20K | 2 | RA unit confusion, no GPU shaders |
| Updater | Production-Ready | 12 | ~1.5K | 1 | No auth on LAN push |
| WebRTC | Functional (strong) | 13 | ~5K | 0 | Weak nonce seed, no tests |
| Plugins | Scaffold | 5 | ~0.8K | 1 | Storage not persistent, APIs untyped |
| UI | Production-Ready | 37 | ~3K | 0 | No tests |

## Top Recommendations

1. **Security: Fix WebRTC nonce generation** (`channel_encryption.dart:152-158`): Replace `DateTime`-based seeding with `Random.secure()`. This is a cryptographic vulnerability.

2. **Security: Add authentication to LAN push** (`lan_push_receiver.dart`): At minimum, require a shared secret or paired device token before accepting update pushes.

3. **Fix RA unit documentation** (`coordinate_system.dart`): Document that `CelestialCoordinate.ra` is in degrees (not hours as stated), or change all callers to pass hours. The inconsistency is a maintenance hazard.

4. **Fix WebRTC ICE candidate handling** (`peer_connection.dart`): Add `onIceCandidate` handler and relay candidates through signaling. Without this, connections requiring STUN/relay will fail.

5. **Persist plugin storage**: Replace `InMemoryPluginStorage` with SharedPreferences or Drift-backed storage. Current implementation loses all plugin state on restart.

6. **Add tests**: WebRTC (0 tests) and UI (0 tests) are the biggest gaps. At minimum, add tests for the security-critical token manager, encryption, and theme rendering.

7. **Eliminate code duplication**: Extract `_extractZip()`, constellation name maps, and `getLocalIp()` into shared utilities.

8. **Type-safe plugin API**: Change `widgetBuilder` return type from `dynamic` to `Widget?` and `createNode` from `dynamic` to a proper typed interface.
