# 04 - Models & Database Audit

**Auditor:** models-auditor
**Date:** 2026-03-07
**Overall Rating:** 7.5/10 - Solid architecture with good schema design, but several model-DB misalignments and a legacy safety enum issue

---

## 1. Model Catalog

### 1.1 Freezed Models (with code generation)

| File | Classes | JSON Support |
|------|---------|-------------|
| `equipment_profile.dart` | `EquipmentProfile` | Yes (fromJson/toJson) |
| `meridian_flip_settings.dart` | `MeridianFlipSettings` | Yes |
| `annotation_settings.dart` | `AnnotationSettings`, `AnnotationMarkerStyle` | Yes |
| `meridian_flip_event.dart` | `MeridianFlipEvent` | Yes |
| `polar_alignment_config.dart` | `PolarAlignmentConfig` + related types | Yes |
| `optical_config.dart` | `OpticalConfig` | Yes |
| `annotation_data.dart` | `AnnotationData` | Yes |
| `phd2_models.dart` | PHD2 guide models | Yes |
| `settings/app_settings.dart` | `AppSettings`, `ObserverLocation` | Yes |
| `weather/weather_settings.dart` | Weather freezed settings | Yes |
| `weather/cloud_motion.dart` | Cloud motion models | Yes |
| `weather/weather_alert.dart` | Weather alert model | Yes |
| `weather/weather_status.dart` | Weather status model | Yes |
| `weather/radar_frame.dart` | Radar frame model | Yes |
| `flat_wizard/flat_wizard_settings.dart` | Flat wizard settings | Yes |
| `flat_wizard/flat_wizard_state.dart` | Flat wizard state | Yes |
| `imaging/auto_stretch_settings.dart` | Auto stretch settings | Yes |
| `alerts/transient_alert.dart` | Transient alert model | Yes |
| `planning/target_suggestion.dart` | Target suggestion model | Yes |
| `sequence/template_snippet.dart` | Template snippet model | Yes |

### 1.2 Equatable/Plain Models (hand-written)

| File | Classes | JSON Support |
|------|---------|-------------|
| `target/target_models.dart` | `CelestialTarget`, `TargetVisibility`, `SessionPlan`, `PlannedTarget` | Manual (copyWith only) |
| `imaging/imaging_models.dart` | `ImageStats`, `DetectedStar`, `StarDetectionResult`, `StretchParams`, `ExposureSettings`, `CoolingSettings`, `CoolingStatus`, `FocusSettings`, `DitherSettings`, `SlewCoordinates`, `CapturedImageData`, `CapturedImage`, `ExposureProgress`, `NamingPattern`, `StarDetectionConfig`, `FilterAutofocusConfig`, `AutofocusSettings` | Manual fromJson/toJson |
| `imaging/camera_preset.dart` | Camera preset model | Manual |
| `sequence/sequence_models.dart` | `SequenceNode` (abstract), 20+ concrete node types, enums | Manual (JSON via properties map) |
| `equipment/discovery_state.dart` | Discovery state model | Manual |
| `equipment/unified_device.dart` | Unified device model | Manual |
| `equipment/equipment_models.dart` | Equipment-related models | Manual |
| `autofocus_progress.dart` | Autofocus progress model | Manual |

### 1.3 Backend Models (pure Dart, no FRB dependency)

| File | Classes | JSON Support |
|------|---------|-------------|
| `backend/device_types.dart` | `DeviceType`, `DriverType`, `ConnectionState`, `PierSide`, `CameraState` enums | N/A (enums) |
| `backend/device_status.dart` | `CameraStatus`, `MountStatus`, `FocuserStatus`, `FilterWheelStatus`, `RotatorStatus` | Yes (fromJson/toJson) |
| `backend/device_capabilities.dart` | `CameraCapabilities`, `MountCapabilities`, `FocuserCapabilities`, `FilterWheelCapabilities`, `RotatorCapabilities` | Yes (fromJson/toJson) |
| `backend/device_info.dart` | `DeviceInfo` | Yes (fromJson/toJson) |
| `backend/event_types.dart` | `NightshadeEvent`, `EventSeverity`, `EventCategory` | Yes |
| `backend/sequencer_status.dart` | `SequencerStatus`, `CheckpointInfo` | Yes |
| `backend/plate_solve_result.dart` | `PlateSolveResult` | Yes |
| `backend/autofocus_result.dart` | `AutofocusResult`, `FocusDataPoint`, `AutofocusConfig` | Yes |
| `backend/image_result.dart` | `CapturedImageResult`, `ImageStatsResult` | Yes |
| `backend/fits_header.dart` | FITS header model | Yes |
| `backend/phd2_status.dart` | PHD2 status model | Yes |

### 1.4 Science Models

| File | Classes | JSON Support |
|------|---------|-------------|
| `science/science_models.dart` | `ScienceFrameQualityMetrics`, `ScienceTileMetric`, `ScienceVisualizationPrefs`, `SolverCapabilities`, `SolveOptions`, `WcsSolution`, `PhotometryOptions`, `StarMeasurement`, `FramePhotometricCalibration`, `TransparencyOptions`, `TransparencySample`, `PsfMapOptions`, `PsfTileMetric`, `PsfFieldMap`, `AstrometryOptions`, `ResidualVectorSample`, `AstrometricResidualMap`, `MovingObjectOptions`, `MovingObjectMatch`, `NarrowbandSet`, `LineRatioOptions`, `LineRatioMetric`, `LineRatioProduct`, `ScienceModeState`, `ScienceOverlayState`, `ScienceSessionConfig`, `ScienceDiagnostics`, `ScienceFrameContext`, `PhotometryAnchor`, `SciencePhotometrySelection`, `LightCurvePoint`, `TransparencyTrendPoint`, `MovingObjectCandidate`, + enums | Partial (some have JSON) |

### 1.5 Enums Catalog

| Enum | File | Values |
|------|------|--------|
| `FrameType` | imaging_models.dart | light, dark, flat, bias, darkFlat, snapshot |
| `BayerPattern` | imaging_models.dart | rggb, bggr, grbg, gbrg |
| `DebayerAlgorithm` | imaging_models.dart | bilinear, vng, superPixel |
| `ImageFileFormat` | imaging_models.dart | fits, xisf, tiff, png, jpeg |
| `CaptureMode` | imaging_models.dart | single, loop, count |
| `TargetType` | target_models.dart | galaxy, nebula, cluster, star, planet, moon, comet, asteroid, other |
| `DeviceType` | device_types.dart | camera, mount, focuser, filterWheel, guider, dome, rotator, weather, safetyMonitor, switch_, coverCalibrator |
| `DriverType` | device_types.dart | ascom, alpaca, indi, native, simulator |
| `ConnectionState` | device_types.dart | disconnected, connecting, connected, error |
| `PierSide` | device_types.dart | east, west, unknown |
| `CameraState` | device_types.dart | idle, waiting, exposing, reading, download, error |
| `TrackingRate` | device_capabilities.dart | sidereal, lunar, solar, king, custom |
| `EventSeverity` | event_types.dart | info, warning, error, critical |
| `EventCategory` | event_types.dart | equipment, imaging, guiding, sequencer, safety, system, polarAlignment |
| `SequenceExecutionState` | sequence_models.dart | idle, running, paused, stopping, completed, failed |
| `NodeStatus` | sequence_models.dart | pending, running, success, failure, skipped, cancelled |
| `BinningMode` | sequence_models.dart | one, two, three, four |
| `AutofocusMethod` | sequence_models.dart | vCurve, hyperbolic, quadratic |
| `LoopConditionType` | sequence_models.dart | count, untilTime, untilAltitude, altitudeAbove, integrationTime, forever, whileDark |
| `ConditionalType` | sequence_models.dart | always, altitudeAbove, timeAfter, guidingRmsBelow, hfrBelow, weatherSafe, moonSeparationAbove, safetyMonitorSafe |
| `RecoveryActionType` | sequence_models.dart | continueExecution, pause, autofocus, nextTarget, retry, parkAndAbort, customBranch |
| `TriggerType` | sequence_models.dart | hfrDegraded, meridianFlip, guidingFailed, altitudeLimit, weatherUnsafe, temperatureShift, filterChange, dawnApproaching |
| `MeridianTriggerMethod` | meridian_flip_settings.dart | minutesPastMeridian, minutesBeforeLimit, hourAngleThreshold, onTrackingLimitHit |
| `FlipFailureAction` | meridian_flip_settings.dart | pauseAndAlert, abortAndPark |
| `SafetyFailMode` | app_settings.dart | failOpen, failClosed, warnOnly |
| `ScienceFeature` | science_models.dart | photometry, photometricCalibration, transparency, psfMap, astrometricResiduals, movingObjects, narrowbandRatios, frameQualityMaps, surface3d |
| `ScienceLayerType` | science_models.dart | fwhm, hfr, eccentricity, uniformity, clipLow, clipHigh, background, snr, residualMag |
| `PhotometricCatalogSource` | science_models.dart | auto, localGaia, localApass |

---

## 2. Database Schema

### 2.1 Tables (21 total)

| Table | Data Class | Primary Key | Foreign Keys |
|-------|-----------|-------------|-------------|
| `equipment_profiles` | `EquipmentProfile` | `id` (auto) | None |
| `imaging_sessions` | `ImagingSession` | `id` (auto) | `profileId` -> equipment_profiles, `targetId` -> targets, `sequenceId` -> sequences |
| `targets` | `Target` | `id` (auto) | None |
| `sequences` | `Sequence` | `id` (auto) | None |
| `sequence_nodes` | `SequenceNode` | `id` (auto) | `sequenceId` -> sequences (CASCADE), `targetId` -> targets (SET NULL) |
| `sequence_checkpoints` | `SequenceCheckpoint` | `sequenceId` | `sequenceId` -> sequences (CASCADE) |
| `captured_images` | `CapturedImage` | `id` (auto) | `sessionId` -> imaging_sessions (CASCADE), `targetId` -> targets (SET NULL) |
| `image_metadata` | `ImageMetadatum` | `id` (auto) | `imageId` -> captured_images (CASCADE) |
| `app_settings` | `AppSetting` | `id` (auto) | None (key is unique) |
| `weather_settings` | `WeatherSettingRow` | `id` (auto) | None |
| `flat_history` | `FlatHistoryEntry` | `id` (auto) | None (equipmentProfileId not FK-enforced) |
| `tutorial_progress` | `TutorialProgressEntry` | `id` (auto) | None (category is unique) |
| `polar_alignment_history` | `PolarAlignmentHistoryEntry` | `id` (auto) | None (equipmentProfileId is TEXT, not FK) |
| `science_session_config` | `ScienceSessionConfigRow` | `id` (auto) | `sessionId` -> imaging_sessions (CASCADE) |
| `photometry_measurements` | `PhotometryMeasurementRow` | `id` (auto) | `capturedImageId` -> captured_images (CASCADE), `sessionId` -> imaging_sessions (CASCADE) |
| `frame_photometric_calibration` | `FramePhotometricCalibrationRow` | `id` (auto) | Same as above |
| `transparency_samples` | `TransparencySampleRow` | `id` (auto) | Same as above |
| `psf_field_tiles` | `PsfFieldTileRow` | `id` (auto) | Same as above |
| `science_frame_quality_metrics` | `ScienceFrameQualityMetricsRow` | `id` (auto) | Same as above |
| `science_tile_metrics` | `ScienceTileMetricRow` | `id` (auto) | Same as above |
| `astrometry_residual_vectors` | `AstrometryResidualVectorRow` | `id` (auto) | Same as above |
| `moving_object_candidates` | `MovingObjectCandidateRow` | `id` (auto) | Same as above |
| `line_ratio_products` | `LineRatioProductRow` | `id` (auto) | `sessionId` -> imaging_sessions (CASCADE), image FKs with SET NULL |

### 2.2 Migration History

- **Schema Version:** 15 (current)
- **Migrations:** 15 versions, all clean and incrementally applied
- **Version 1:** Initial schema creation
- **Version 2:** Added comprehensive indexes (targets, images, sessions, sequences, nodes, metadata, profiles)
- **Version 3:** Sequence checkpoints table + cascade delete foreign keys
- **Version 4:** Weather settings table
- **Version 5:** Cover calibrator ID on equipment profiles
- **Version 6:** Meridian flip overrides on equipment profiles
- **Version 7:** Flat history table + indexes
- **Version 8:** Quick Start columns (sequence_id, equipment_snapshot) on imaging sessions
- **Version 9:** Tutorial progress table
- **Version 10:** Polar alignment history table + quality_score on captured_images
- **Version 11:** User-friendly device names, telescope info, profile customization on equipment profiles
- **Version 12:** cool_on_connect on equipment profiles
- **Version 13:** Science suite tables (9 tables + indexes + default settings)
- **Version 14:** Frame quality and tile metrics tables
- **Version 15:** default_centering_exposure on equipment profiles

Migration quality: **Good** - Uses `_columnExists()` guard for ALTER TABLE operations, preventing crashes on partial migrations. All CREATE TABLE uses `m.createTable()` properly. Indexes use `IF NOT EXISTS`.

### 2.3 DAOs (12 total)

| DAO | Tables | Key Operations |
|-----|--------|---------------|
| `EquipmentProfilesDao` | EquipmentProfiles | CRUD, setActive (transactional), duplicate |
| `TargetsDao` | Targets | CRUD, search, filter by type/priority, getObservableTargets (astro calc) |
| `SequencesDao` | Sequences, SequenceNodes, Targets | CRUD, duplicate (with nodes), node tree operations, reorder |
| `SequenceCheckpointsDao` | SequenceCheckpoints, Sequences | Upsert, progress tracking, cleanup |
| `ImagesDao` | CapturedImages, ImageMetadata, ImagingSessions, Targets | CRUD, pagination, filter stats, plate solve updates, batch metadata |
| `SessionsDao` | ImagingSessions, EquipmentProfiles, Sequences, Targets | CRUD, start/end session, stats, recovery, Quick Start |
| `SettingsDao` | AppSettings | Key-value CRUD, typed getters, upsert with conflict handling |
| `WeatherSettingsDao` | WeatherSettings | Single-row pattern, getOrCreate, typed updates |
| `FlatHistoryDao` | FlatHistory | Historical calibrations, suggested exposure, pruning |
| `TutorialProgressDao` | TutorialProgress | Progress CRUD, completion/dismissal tracking, prompt management |
| `PolarAlignmentHistoryDao` | PolarAlignmentHistory | Insert results, stats aggregation, history pruning, model conversion |
| `ScienceDao` | All 9 science tables | Per-image replace operations, session watches, sessionless queries |

### 2.4 Indexes

**Total indexes defined:** 50+ across all tables

Indexes are well-defined for common query patterns:
- **Targets:** name, catalog_id, priority, is_favorite, object_type
- **Images:** session_id, target_id, frame_type, captured_at, filter, is_accepted, composite (session_id, frame_type)
- **Sessions:** target_id, profile_id, start_time, status
- **Sequences:** name, is_template, updated_at
- **Nodes:** sequence_id, parent_node_id, target_id, node_type, node_id
- **Metadata:** image_id, key
- **Science tables:** All have indexes on captured_image_id, session_id, timestamp; some have composite indexes

---

## 3. Issues Found

### 3.1 CRITICAL: EquipmentProfile Freezed Model Missing 18+ Database Fields

**File:** `packages/nightshade_core/lib/src/models/equipment_profile.dart:7-36`

The freezed `EquipmentProfile` model is **severely misaligned** with the database `EquipmentProfiles` table. The database table has 40+ columns, but the freezed model only has ~18 fields:

**Missing from freezed model (present in DB table):**
- `description` - profile description
- `mountName`, `focuserName`, `filterWheelName`, `guiderName`, `rotatorName` - user-friendly device names
- `defaultGain`, `defaultOffset`, `defaultBinX`, `defaultBinY`, `defaultCoolingTemp` - camera defaults
- `defaultCenteringExposure` - centering exposure default
- `filterNames`, `filterFocusOffsets` - filter configuration
- `meridianFlipOverrides` - per-profile meridian flip settings
- `profileIcon`, `profileColor`, `sortOrder`, `isDefault` - profile customization
- `coolOnConnect` - auto-cool on connect flag
- `createdAt` - creation timestamp

**Impact:** The Drift-generated `EquipmentProfile` data class (from the table definition) is used for database operations, while the freezed `EquipmentProfile` model is used for JSON serialization and some UI operations. These are **two different classes with the same name** in different packages. The freezed model is imported from `models/equipment_profile.dart` while the Drift model is generated from `tables/equipment_profiles.dart`. This creates confusion and potential bugs where the wrong type is used.

The `duplicateProfile` method in `EquipmentProfilesDao` (line 66) correctly uses the Drift-generated model, but the new fields added in v11+ (device names, telescope info, customization) are **not copied during duplication** -- only the original fields are carried over.

**Severity:** HIGH -- The profile duplicate function silently drops telescope names, device names, profile customization, and centering exposure settings.

### 3.2 HIGH: SafetyFailMode Enum Contains Misleading Legacy Values

**File:** `packages/nightshade_core/lib/src/models/settings/app_settings.dart:7-14`

```dart
enum SafetyFailMode {
  /// Legacy mode retained for backward compatibility. Runtime is fail-closed.
  failOpen,
  /// Treat unavailable safety data as unsafe (production behavior).
  failClosed,
  /// Legacy mode retained for backward compatibility. Runtime is fail-closed.
  warnOnly,
}
```

The comments say `failOpen` and `warnOnly` are "legacy modes retained for backward compatibility" and that "runtime is fail-closed" for them. However, in `weather_safety_provider.dart:226-242`, these values are actively matched in switch statements and may still produce different runtime behavior. If both values really map to fail-closed at runtime, they should be removed or the switch logic audited for correctness.

**Severity:** HIGH -- Safety-critical code with potentially misleading enum semantics. If a user selects `failOpen` thinking it does what it says (and the runtime actually is fail-closed as the comment claims), there's a disconnect between UI presentation and behavior.

### 3.3 MEDIUM: CelestialTarget Not Using Freezed

**File:** `packages/nightshade_core/lib/src/models/target/target_models.dart:47-176`

`CelestialTarget` is a hand-written Equatable class with manual `copyWith()` and no JSON serialization. This is inconsistent with other core models like `EquipmentProfile` and `MeridianFlipSettings` which use freezed. The lack of `fromJson`/`toJson` means conversions between the model and the Drift `Target` data class must be done manually in every service/provider.

Additionally, the `copyWith()` method has the standard nullable-field bug: you can't set a nullable field to `null` because `null` is treated as "don't change." For example:
```dart
copyWith(magnitude: null) // Does NOT clear magnitude, keeps existing value
```

**Severity:** MEDIUM -- Consistency issue and potential null-clearing bugs.

### 3.4 MEDIUM: _normalizeDegrees Bug in TargetsDao

**File:** `packages/nightshade_core/lib/src/database/daos/targets_dao.dart:194-199`

```dart
double _normalizeDegrees(double value) {
    var normalized = value % 360.0;
    if (normalized < -180.0) normalized += 360.0;
    if (normalized > 180.0) normalized -= 360.0;
    return normalized;
  }
```

This function normalizes to [-180, 180] range, but it's used for both hour angle (which needs [0, 360] or [-180, 180]) and sidereal time / GMST (which needs [0, 360]). For GMST specifically, the modulo can produce negative values (e.g., `-50.0 % 360.0 = -50.0` in Dart), and the correction only handles `< -180` but not general negative values. A value of `-50.0` would pass through unchanged as `-50.0`.

For the hour angle calculation at line 139, this might produce incorrect altitude calculations for some targets since the hour angle should be in [-180, 180] or [0, 360] for the cosine function (which is symmetric, so the sign doesn't actually matter for `cos(haRad)` -- the bug is cosmetic for the HA but could produce negative sidereal times).

**Severity:** MEDIUM -- Could produce incorrect observable target lists for certain longitude/time combinations.

### 3.5 MEDIUM: FlatHistory.equipmentProfileId Not a Real Foreign Key

**File:** `packages/nightshade_core/lib/src/database/tables/flat_history.dart:12`

```dart
IntColumn get equipmentProfileId => integer().nullable()();
```

This is declared as a plain nullable integer, not as a foreign key reference to `equipment_profiles.id`. This means:
- No referential integrity enforcement
- No cascade behavior when profiles are deleted
- Orphaned flat history entries can accumulate

**Severity:** MEDIUM -- Data integrity issue; orphaned records after profile deletion.

### 3.6 MEDIUM: PolarAlignmentHistory.equipmentProfileId Type Mismatch

**File:** `packages/nightshade_core/lib/src/database/tables/polar_alignment_history.dart:14`

```dart
TextColumn get equipmentProfileId => text().nullable()();
```

The `equipmentProfileId` is a **TEXT** column, but `equipment_profiles.id` is an **INTEGER** auto-increment column. This means the FK relationship is broken by type mismatch. It can never be joined properly to the equipment_profiles table via a standard integer FK.

**Severity:** MEDIUM -- Design smell; makes profile-to-alignment joins unreliable and prevents FK enforcement.

### 3.7 MEDIUM: ImagingSessions Missing Cascade Deletes

**File:** `packages/nightshade_core/lib/src/database/tables/imaging_sessions.dart:19-20`

```dart
IntColumn get profileId => integer().nullable().references(EquipmentProfiles, #id)();
IntColumn get targetId => integer().nullable().references(Targets, #id)();
```

Neither `profileId` nor `targetId` have `onDelete` behavior specified. This means deleting an equipment profile or target that has associated sessions will fail with a foreign key constraint violation (the PRAGMA is enabled in `beforeOpen`). The app would need to handle this gracefully, but there's no evidence of pre-deletion cleanup for these FKs.

**Severity:** MEDIUM -- Deleting profiles or targets with existing sessions will throw database errors.

### 3.8 LOW: Duplicate Model Names Between Drift and Dart

Multiple model files define classes with the same name as Drift-generated data classes:
- `EquipmentProfile` exists in both `models/equipment_profile.dart` (freezed) and is generated from `tables/equipment_profiles.dart` (Drift)
- `CapturedImage` exists in both `models/imaging/imaging_models.dart` and generated from `tables/captured_images.dart`
- `SequenceNode` exists in both `models/sequence/sequence_models.dart` and generated from `tables/sequences.dart`
- `ScienceSessionConfig` exists in both `models/science/science_models.dart` and generated from `tables/science.dart`
- `ScienceFrameQualityMetrics` exists in both `models/science/science_models.dart` and generated from `tables/science.dart`

This requires careful import management and can cause confusing compile errors.

**Severity:** LOW -- Managed via imports but creates maintenance burden.

### 3.9 LOW: Science Models Not Using Freezed

**File:** `packages/nightshade_core/lib/src/models/science/science_models.dart`

This 850+ line file contains 30+ model classes, none of which use freezed or Equatable. Most lack proper equality semantics, and many have no JSON serialization. Some classes like `PhotometryAnchor` and `SciencePhotometrySelection` have hand-written JSON methods while most don't.

**Severity:** LOW -- Functional but inconsistent with rest of codebase.

### 3.10 LOW-MEDIUM: EquipmentProfilesDao.duplicateProfile Missing New Fields

**File:** `packages/nightshade_core/lib/src/database/daos/equipment_profiles_dao.dart:66-98`

The `duplicateProfile` method copies fields from the original profile but is missing several fields that were added in later migrations:
- `cameraName`, `mountName`, `focuserName`, `filterWheelName`, `guiderName`, `rotatorName` (v11)
- `telescopeName`, `telescopeFocalLength`, `telescopeAperture` (v11)
- `profileIcon`, `profileColor`, `sortOrder` (v11)
- `coolOnConnect` (v12)
- `defaultCenteringExposure` (v15)

**Severity:** LOW-MEDIUM -- Profile duplication silently drops these fields, giving the user a partial copy.

### 3.11 LOW: AppSettings Contains Duplicate Location Fields

**File:** `packages/nightshade_core/lib/src/models/settings/app_settings.dart:29-77`

The `AppSettings` model has both:
- `ObserverLocation? location` (nested freezed object with lat/lon/elevation)
- `double latitude`, `double longitude`, `double elevation` (top-level fields)

An `AppSettingsExtension` provides `effectiveLatitude` etc. that prefers the nested object. This dual representation is confusing and error-prone -- callers must know to use the extension getters rather than the direct fields.

**Severity:** LOW -- Cosmetic, but creates API confusion.

---

## 4. Positive Findings

### 4.1 Well-Designed Migration Strategy (9/10)

The migration system is robust:
- Uses `_columnExists()` checks before ALTER TABLE operations
- Foreign keys enabled via PRAGMA in `beforeOpen`
- Each version is cleanly separated with `if (from < N)` guards
- Indexes use `IF NOT EXISTS` to be idempotent
- Default settings are seeded both in `onCreate` and migrations

### 4.2 Comprehensive Indexing (9/10)

50+ indexes cover all common query patterns. Notable compound indexes like `(session_id, frame_type)` on captured_images and `(session_id, processing_tier, timestamp)` on science_frame_quality_metrics show thoughtful query optimization.

### 4.3 DAO Quality (8/10)

DAOs are well-structured with:
- Proper use of Drift's reactive streams (`watch*` methods)
- Pagination support for large datasets (images)
- Transactional operations where needed (setActiveProfile, deleteSequence)
- Batch operations for performance (metadata, science data)
- Upsert patterns for checkpoints and settings

### 4.4 Backend Models (8/10)

Device status, capabilities, and result types are well-designed:
- Pure Dart types (no FRB dependency)
- Dual JSON key support (camelCase and snake_case) for network compatibility
- Proper null handling in fromJson factories
- Graceful fallbacks for unknown enum values (orElse handlers)

### 4.5 Science Schema (8/10)

The science suite tables are well-normalized:
- Proper cascade deletes from parent tables
- Per-image replacement operations to prevent stale data
- Sessionless query support for standalone captures
- Good separation between frame-level and tile-level metrics

### 4.6 Seed Data (7/10)

The `DatabaseSeeder` provides useful test data:
- Realistic equipment profiles with proper ASCOM device IDs
- Template sequences with real imaging parameters
- Default settings that match production defaults
- `clearAll()` method for test isolation

---

## 5. Summary

### Strengths
- Robust migration strategy with 15 clean versions
- Comprehensive indexing for query performance
- Well-structured DAOs with reactive stream support
- Foreign key enforcement with appropriate cascade/set-null behavior
- Good separation between Dart models and DB schema

### Critical Issues
1. **EquipmentProfile model-DB misalignment** -- 18+ fields missing from freezed model, profile duplication drops fields
2. **SafetyFailMode enum misleading** -- Legacy values may not behave as documented in safety-critical code
3. **ImagingSessions missing onDelete behavior** -- Profile/target deletion can break with FK violations

### Recommended Actions
1. Either remove the freezed `EquipmentProfile` model entirely (use Drift's generated class) or sync it with all 40+ DB columns
2. Audit `SafetyFailMode.failOpen` and `.warnOnly` runtime behavior against documentation; remove if truly unused
3. Update `duplicateProfile` to copy all fields including v11-v15 additions
4. Add proper FK references to `flat_history.equipmentProfileId`
5. Fix type mismatch on `polar_alignment_history.equipmentProfileId` (TEXT vs INTEGER)
6. Add `onDelete` behavior to `imaging_sessions.profileId` and `imaging_sessions.targetId` (likely SET NULL)
7. Fix `_normalizeDegrees` to handle negative modulo results correctly
