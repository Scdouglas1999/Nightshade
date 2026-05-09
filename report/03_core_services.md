# 3. Core Services Audit

## Scope
- `packages/nightshade_core/lib/src/services/` — All business logic services
- Service orchestration, error handling, edge cases, test coverage

---

## Feature Inventory

### Service Catalog (31 files)

| # | Service | File | Lines | Description |
|---|---------|------|-------|-------------|
| 1 | **DeviceService** | `device_service.dart` | 2887 | Central device lifecycle manager — connect, disconnect, reconnect, event routing, temperature polling, filter sync, camera warming |
| 2 | **ImagingService** | `imaging_service.dart` | 933 | Camera capture orchestration — exposure control, FITS saving, quality scoring, file naming patterns |
| 3 | **SessionService** | `session_service.dart` | 459 | Session lifecycle with checkpoint persistence and crash recovery |
| 4 | **CenteringService** | `centering_service.dart` | 636 | Iterative plate-solve-and-slew centering with haversine angular separation |
| 5 | **PlateSolveService** | `plate_solve_service.dart` | 389 | Backend plate solving with local fallback (ASTAP, Astrometry.net, PlateSolve2), WCS parsing |
| 6 | **FocusModelService** | `focus_model_service.dart` | 535 | Temperature-focus linear regression, filter offsets with confidence scoring, JSON persistence |
| 7 | **SchedulerService** | `scheduler_service.dart` | 453 | Astronomical calculations for target scheduling — altitude, transit, moon distance, scoring |
| 8 | **MosaicService** | `mosaic_service.dart` | 580 | Mosaic panel generation with overlap, rotation, cos(dec) RA correction, serpentine ordering |
| 9 | **FlatWizardService** | `flat_wizard_service.dart` | 608 | Iterative flat-frame exposure calibration with adaptive step sizing, sky-flat rate tracking |
| 10 | **AutoSaveService** | `auto_save_service.dart` | 365 | Periodic sequence save + backup rotation with status streaming |
| 11 | **BackupService** | `backup_service.dart` | 764 | Full backup/restore of settings, profiles, sequences, targets with versioned ZIP archives |
| 12 | **AnnotationService** | `annotation_service.dart` | 987 | SNR-based progressive annotation reveal — plate solving, catalog search, external API queries (SIMBAD, Gaia, Exoplanet Archive) |
| 13 | **CatalogService** | `catalog_service.dart` | 449 | Streaming catalog search with pagination; subclasses for HYG stars, OpenNGC DSOs, GLADE+ galaxies |
| 14 | **NotificationService** | `notification_service.dart` | 308 | Discord webhook and Pushover push notifications with event filtering and test methods |
| 15 | **LoggingService** | `logging_service.dart` | 245 | Structured logging with in-memory ring buffer and level-based filtering |
| 16 | **ErrorService** | `error_service.dart` | 651 | Error classification by category/severity, UI notification integration, pattern-based user-friendly message translation |
| 17 | **ProfileService** | `profile_service.dart` | 787 | Equipment profile validation, auto-connect, import/export, device management, filter sync from hardware |
| 18 | **SequenceRepository** | `sequence_repository.dart` | 1030 | Database persistence layer for sequences via DAO pattern |
| 19 | **SequenceFileService** | `sequence_file_service.dart` | 832 | JSON import/export for sequences with version migration |
| 20 | **TargetSuggestionService** | `target_suggestion_service.dart` | 658 | Night-window-based target scoring and suggestion engine |
| 21 | **SmartNotificationService** | `smart_notification_service.dart` | 109 | Screen-aware notification filtering (suppresses redundant alerts on active screen) |
| 22 | **WeatherRadarService** | `weather/weather_radar_service.dart` | ~400 | Multi-provider radar coordination (GOES, NOAA, RainViewer, OpenMeteo) with caching |
| 23 | **WeatherAlertService** | `weather/weather_alert_service.dart` | ~300 | Weather alert generation with debouncing based on cloud density thresholds |
| 24 | **CloudMotionAnalyzer** | `weather/cloud_motion_analyzer.dart` | ~250 | Cloud centroid tracking across radar frames for ETA prediction |
| 25 | **GoesRadarProvider** | `weather/goes_radar_provider.dart` | ~200 | GOES satellite imagery fetcher |
| 26 | **NoaaRadarProvider** | `weather/noaa_radar_provider.dart` | ~200 | NOAA weather radar provider |
| 27 | **RainViewerProvider** | `weather/rainviewer_provider.dart` | ~200 | RainViewer API provider |
| 28 | **OpenMeteoProvider** | `weather/openmeteo_provider.dart` | ~200 | OpenMeteo cloud cover API provider |
| 29 | **ScienceDataService** | `science/science_data_service.dart` | ~400 | Science data collection and persistence |
| 30 | **PhotometryService** | `science/photometry_service.dart` | ~350 | Stellar photometry measurement pipeline |
| 31 | **AstrometryService** | `science/astrometry_service.dart` | ~300 | Astrometric calibration and residual analysis |

### Dependencies Map

```
DeviceService
  ├── NightshadeBackend (FfiBackend / NetworkBackend / DisconnectedBackend)
  ├── ProfileService
  ├── FocusModelService
  └── EventBus (Rust → Dart stream)

ImagingService
  ├── NightshadeBackend
  ├── DeviceService (device state queries)
  └── File I/O (FITS output)

SessionService
  ├── NightshadeDatabase (Drift DAO)
  └── Timer (checkpoint intervals)

CenteringService
  ├── NightshadeBackend (slew, plate solve)
  ├── PlateSolveService
  └── ImagingService (capture for solve)

PlateSolveService
  ├── NightshadeBackend (backend solve)
  └── Process (local solver executables)

FocusModelService
  ├── File I/O (JSON persistence)
  └── Math (linear regression)

SchedulerService
  ├── Math (spherical astronomy)
  └── Pure computation (no external deps)

MosaicService
  ├── Math (coordinate transforms)
  └── SequenceFileService (sequence generation)

BackupService
  ├── NightshadeDatabase
  ├── File I/O (ZIP archives)
  └── ProfileService

AnnotationService
  ├── PlateSolveService
  ├── CatalogService
  ├── HTTP (SIMBAD, Gaia, Exoplanet Archive)
  └── NightshadeBackend
```

---

## Implementation Quality

### Depth Ratings

| Service | Rating | Notes |
|---------|--------|-------|
| DeviceService | **Production** | Fully implemented with auto-reconnect (exponential backoff), event routing, temperature polling, filter sync, camera warming ramp, comprehensive error handling |
| ImagingService | **Production** | Event-based exposure completion with timeout fallback, optimized Rust FITS API, quality metrics |
| SessionService | **Production** | Checkpoint recovery, DAO persistence, proper timer cleanup |
| CenteringService | **Production** | Iterative solve-slew loop, haversine separation, status callbacks for UI |
| PlateSolveService | **Production** | Multi-solver support, WCS parsing, process execution with timeout |
| FocusModelService | **Production** | Linear regression, confidence scoring, filter offsets, data bucketing |
| SchedulerService | **Production** (1 bug) | Full astronomical calculation suite; moon illumination bug (see Bugs) |
| MosaicService | **Production** | Panel math with cos(dec) correction, overlap, rotation, serpentine ordering |
| FlatWizardService | **Solid** (1 issue) | Adaptive step sizing, rate tracking; uses fragile `Future.delayed` for exposure timing |
| AutoSaveService | **Production** | Clean timer lifecycle, backup rotation, status streaming |
| BackupService | **Production** (1 bug) | Full backup/restore; hardcoded stale version string (see Bugs) |
| AnnotationService | **Production** | SNR-progressive reveal, debounced updates, multi-catalog + external API queries |
| CatalogService | **Production** | Streaming pagination, proper CSV parsing with quote handling |
| NotificationService | **Production** | Discord + Pushover, event filtering, test methods |
| LoggingService | **Solid** (1 bug) | Ring buffer works; switch statement has empty cases (see Bugs) |
| ErrorService | **Production** | Comprehensive error classification, pattern-based user-friendly translations |
| ProfileService | **Production** | Validation, auto-connect, import with conflict resolution |
| SequenceRepository | **Production** | Full CRUD via DAO, proper transaction handling |
| SequenceFileService | **Production** | JSON import/export, version migration, template support |
| TargetSuggestionService | **Production** | Night-window calculations, multi-factor scoring |
| WeatherRadarService | **Production** | Multi-provider with caching and streaming |
| SmartNotificationService | **Production** | Clean screen-aware filtering |

**Overall**: The services layer is remarkably well-implemented. Nearly all services are production-quality with proper error handling, resource cleanup, and real implementations (no stubs or placeholders detected).

---

## Bugs Found

### BUG-S01: Moon Illumination Double Radian Conversion (Critical)

**File**: `packages/nightshade_core/lib/src/services/scheduler_service.dart` ~line 409
**Severity**: High — produces incorrect moon illumination values affecting target scheduling

The moon phase angle `d` is already computed in radians via `atan2`, but it is then converted again:
```dart
// BUG: dRad is already in radians from atan2()
final dRad = d; // d is from atan2() — already radians
final illumination = (1 + math.cos(dRad * math.pi / 180.0)) / 2;
//                                       ^^^^^^^^^^^^^^^^ WRONG
```

Should be:
```dart
final illumination = (1 + math.cos(dRad)) / 2;
```

**Impact**: Moon illumination will be nearly always close to 1.0 (full moon) because `cos(small_radian * pi/180)` ≈ `cos(~0)` ≈ 1. This means the scheduler underweights moon interference, potentially scheduling targets too close to the moon.

---

### BUG-S02: Hardcoded Stale App Version in BackupService (Medium)

**File**: `packages/nightshade_core/lib/src/services/backup_service.dart` ~line 108
**Severity**: Medium — backup metadata contains wrong version

```dart
'appVersion': '2.2.0',  // HARDCODED — should read from version.yaml or a constant
```

`version.yaml` declares version 2.5.0. Backups created with the current code will claim they are from version 2.2.0, which could cause issues if version-specific restore logic is ever added.

**Fix**: Read from a central version constant or the version.yaml source of truth.

---

### BUG-S03: LoggingService Empty Switch Cases (Medium)

**File**: `packages/nightshade_core/lib/src/services/logging_service.dart` ~lines 96-109
**Severity**: Medium — log level filtering/forwarding to Rust is not implemented

The `log()` method has a switch statement on log level with empty case bodies. Logs are added to the in-memory ring buffer, but the switch statement that should forward logs to the Rust-side file logger or apply level-based filtering does nothing:

```dart
switch (level) {
  case LogLevel.debug:
    // empty
    break;
  case LogLevel.info:
    // empty
    break;
  case LogLevel.warning:
    // empty
    break;
  case LogLevel.error:
    // empty
    break;
}
```

**Impact**: Dart-side logs are only kept in the memory buffer and never forwarded to the persistent Rust log file. Debug/info logs that should be filtered out at higher log levels are all treated equally.

---

### BUG-S04: FlatWizardService Fragile Exposure Timing (Low)

**File**: `packages/nightshade_core/lib/src/services/flat_wizard_service.dart`
**Severity**: Low — works in practice but fragile

The `captureTestFrame` method uses `Future.delayed(Duration(seconds: exposureTime.ceil() + 2))` to wait for exposure completion instead of using the event-based exposure completion mechanism that `ImagingService` uses. If the exposure takes longer than expected (e.g., due to download time), the service may read stale data. If it finishes early, unnecessary wait time is added.

**Fix**: Use `ImagingService.captureImage()` or subscribe to the exposure completion event stream.

---

## Test Coverage Analysis

### Services WITH Tests

| Service | Test File | Coverage |
|---------|-----------|----------|
| CenteringService | `centering_service_test.dart` | Good — tests iterative centering, convergence, failure cases |
| TargetSuggestionService | `target_suggestion_service_test.dart` | Good — tests scoring, night windows, filtering |
| SchedulerService | `scheduler_service_test.dart` | Partial — tests altitude calculations but not moon illumination (where the bug is) |
| FocusModelService | `focus_model_service_test.dart` | Good — tests regression, confidence, filter offsets |
| MosaicService | `mosaic_service_test.dart` | Good — tests panel generation, overlap, ordering |
| BackupService | `backup_service_test.dart` | Partial — tests backup creation/restore flow |
| AutoSaveService | `auto_save_service_test.dart` | Partial — tests timer lifecycle |
| ProfileService | `profile_service_test.dart` | Good — tests validation, import/export |
| SequenceRepository | `sequence_repository_test.dart` | Good — tests CRUD operations |
| SequenceFileService | `sequence_file_service_test.dart` | Good — tests JSON round-trip |
| ErrorService | `error_service_test.dart` | Partial — tests error classification |
| CatalogService | `catalog_service_test.dart` | Partial — tests CSV parsing |

### Services WITHOUT Tests

| Service | Risk | Notes |
|---------|------|-------|
| **DeviceService** | **High** | 2887 lines of device lifecycle code with no tests. Most critical service in the system. Auto-reconnect, event routing, filter sync all untested. |
| **ImagingService** | **High** | Capture pipeline, FITS saving, quality scoring untested |
| **SessionService** | **Medium** | Checkpoint recovery logic untested |
| **PlateSolveService** | **Medium** | Multi-solver fallback logic untested |
| **FlatWizardService** | **Medium** | Iterative calibration algorithm untested |
| **AnnotationService** | **Medium** | SNR-progressive reveal, external API integration untested |
| **NotificationService** | **Low** | Discord/Pushover integration (inherently hard to unit test) |
| **LoggingService** | **Low** | Simple ring buffer (but the bug would have been caught by tests) |
| **WeatherRadarService** | **Medium** | Multi-provider coordination untested |
| **WeatherAlertService** | **Medium** | Alert debouncing and threshold logic untested |
| **CloudMotionAnalyzer** | **Medium** | Motion vector computation untested |
| **SmartNotificationService** | **Low** | Simple filtering logic |
| **Science services** | **Medium** | Photometry, astrometry pipelines untested |

**Coverage Summary**: ~12 of 31 services have test files. The two most critical services (DeviceService at 2887 lines and ImagingService at 933 lines) have zero tests.

---

## Missing Pieces

### No Stubs or Placeholders Detected

A grep for `TODO`, `FIXME`, `HACK`, `STUB`, `placeholder`, and `not implemented` across all service files returned **zero results**. Every service method has a real implementation.

### Gaps Identified

1. **No central version constant** — `BackupService` hardcodes version; other services may need version info in the future. A single source of truth (read from `version.yaml` at build time) would prevent staleness.

2. **LoggingService Rust forwarding** — The switch statement suggests log forwarding to Rust was planned but never implemented. Dart-side logs are ephemeral (memory-only).

3. **FlatWizardService exposure completion** — Should use the event-based completion mechanism rather than timed delays.

4. **DeviceService test coverage** — At 2887 lines it is the largest and most complex service, handling auto-reconnect with exponential backoff, temperature polling, filter sync, camera warming, and event routing. Zero test coverage creates significant regression risk.

---

## Recommendations

### Priority 1 — Fix Bugs
1. **Fix moon illumination** in `scheduler_service.dart` — remove the `* math.pi / 180.0` from the already-radian value. This affects target scheduling decisions.
2. **Fix hardcoded version** in `backup_service.dart` — create a central version constant derived from `version.yaml`.
3. **Implement or remove** the empty switch statement in `logging_service.dart` — either forward logs to Rust or remove the dead code.

### Priority 2 — Add Critical Tests
4. **Add DeviceService tests** — mock the backend and test connection lifecycle, auto-reconnect timing, event routing, filter sync, and camera warming. This is the highest-risk untested code.
5. **Add ImagingService tests** — test capture pipeline, FITS saving path generation, quality scoring.
6. **Add moon illumination test** to `scheduler_service_test.dart` — verify known phase angles produce correct illumination values.

### Priority 3 — Improve Robustness
7. **FlatWizardService** — replace `Future.delayed` with event-based exposure completion.
8. **Weather service tests** — add tests for multi-provider coordination, alert debouncing, and cloud motion analysis.

### Overall Assessment

The services layer is **strong**. Out of 31 service files totaling ~14,000+ lines of code:
- Zero stubs or placeholders were found
- Error handling is consistent and thorough across nearly all services
- Resource cleanup (timers, streams, controllers) is properly implemented
- Only 4 bugs were identified, none catastrophic
- The main weakness is test coverage: the two most critical services (DeviceService, ImagingService) have no tests

The codebase demonstrates disciplined engineering with real implementations throughout. The bugs found are isolated mistakes rather than systemic issues.
