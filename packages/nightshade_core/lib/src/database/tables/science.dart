import 'package:drift/drift.dart';

import 'captured_images.dart';
import 'imaging_sessions.dart';

@DataClassName('ScienceSessionConfigRow')
@TableIndex(name: 'idx_science_session_config_session', columns: {#sessionId})
class ScienceSessionConfig extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()
      .nullable()
      .references(ImagingSessions, #id, onDelete: KeyAction.cascade)();

  BoolColumn get photometryEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get calibrationEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get transparencyEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get psfMapEnabled => boolean().withDefault(const Constant(true))();
  BoolColumn get residualsEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get movingObjectsEnabled =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get narrowbandEnabled =>
      boolean().withDefault(const Constant(false))();

  IntColumn get psfGridRows => integer().withDefault(const Constant(4))();
  IntColumn get psfGridCols => integer().withDefault(const Constant(6))();
  RealColumn get transparencyAlertThreshold =>
      real().withDefault(const Constant(70.0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PhotometryMeasurementRow')
@TableIndex(
    name: 'idx_photometry_measurements_image', columns: {#capturedImageId})
@TableIndex(name: 'idx_photometry_measurements_session', columns: {#sessionId})
@TableIndex(
    name: 'idx_photometry_measurements_timestamp', columns: {#timestamp})
@TableIndex(name: 'idx_photometry_measurements_object', columns: {#objectId})
class PhotometryMeasurements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get capturedImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.cascade)();
  IntColumn get sessionId => integer()
      .nullable()
      .references(ImagingSessions, #id, onDelete: KeyAction.cascade)();

  TextColumn get objectId => text()();
  TextColumn get role => text().withDefault(const Constant('target'))();

  RealColumn get x => real()();
  RealColumn get y => real()();
  RealColumn get flux => real()();
  RealColumn get differentialMagnitude => real().nullable()();
  RealColumn get snr => real().nullable()();
  RealColumn get uncertainty => real().nullable()();
  BoolColumn get isOutlier => boolean().withDefault(const Constant(false))();

  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('FramePhotometricCalibrationRow')
@TableIndex(
    name: 'idx_frame_photometric_calibration_image',
    columns: {#capturedImageId})
@TableIndex(
    name: 'idx_frame_photometric_calibration_session', columns: {#sessionId})
@TableIndex(
    name: 'idx_frame_photometric_calibration_timestamp', columns: {#timestamp})
@TableIndex(
    name: 'idx_frame_photometric_calibration_solver', columns: {#solverId})
class FramePhotometricCalibration extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get capturedImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.cascade)();
  IntColumn get sessionId => integer()
      .nullable()
      .references(ImagingSessions, #id, onDelete: KeyAction.cascade)();

  BoolColumn get isCalibrated => boolean().withDefault(const Constant(false))();
  RealColumn get zeroPoint => real().nullable()();
  RealColumn get limitingMag3Sigma => real().nullable()();
  RealColumn get limitingMag5Sigma => real().nullable()();
  IntColumn get matchedStarCount => integer().withDefault(const Constant(0))();
  RealColumn get calibrationRms => real().withDefault(const Constant(0.0))();
  TextColumn get catalogSource => text().withDefault(const Constant('auto'))();
  TextColumn get solverId => text().withDefault(const Constant('unknown'))();

  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('TransparencySampleRow')
@TableIndex(name: 'idx_transparency_samples_image', columns: {#capturedImageId})
@TableIndex(name: 'idx_transparency_samples_session', columns: {#sessionId})
@TableIndex(name: 'idx_transparency_samples_timestamp', columns: {#timestamp})
class TransparencySamples extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get capturedImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.cascade)();
  IntColumn get sessionId => integer()
      .nullable()
      .references(ImagingSessions, #id, onDelete: KeyAction.cascade)();

  RealColumn get transparencyPercent => real()();
  RealColumn get extinctionCoefficient =>
      real().withDefault(const Constant(0.0))();
  TextColumn get qualityBucket =>
      text().withDefault(const Constant('Unknown'))();
  RealColumn get confidence => real().withDefault(const Constant(0.0))();

  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PsfFieldTileRow')
@TableIndex(name: 'idx_psf_field_tiles_image', columns: {#capturedImageId})
@TableIndex(name: 'idx_psf_field_tiles_session', columns: {#sessionId})
@TableIndex(name: 'idx_psf_field_tiles_timestamp', columns: {#timestamp})
class PsfFieldTiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get capturedImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.cascade)();
  IntColumn get sessionId => integer()
      .nullable()
      .references(ImagingSessions, #id, onDelete: KeyAction.cascade)();

  IntColumn get tileRow => integer()();
  IntColumn get tileCol => integer()();
  IntColumn get starCount => integer().withDefault(const Constant(0))();
  RealColumn get medianFwhm => real().withDefault(const Constant(0.0))();
  RealColumn get medianHfr => real().withDefault(const Constant(0.0))();
  RealColumn get medianEccentricity =>
      real().withDefault(const Constant(0.0))();
  RealColumn get roundness => real().withDefault(const Constant(0.0))();

  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('AstrometryResidualVectorRow')
@TableIndex(
    name: 'idx_astrometry_residual_vectors_image', columns: {#capturedImageId})
@TableIndex(
    name: 'idx_astrometry_residual_vectors_session', columns: {#sessionId})
@TableIndex(
    name: 'idx_astrometry_residual_vectors_timestamp', columns: {#timestamp})
class AstrometryResidualVectors extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get capturedImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.cascade)();
  IntColumn get sessionId => integer()
      .nullable()
      .references(ImagingSessions, #id, onDelete: KeyAction.cascade)();

  RealColumn get x => real()();
  RealColumn get y => real()();
  RealColumn get dxArcsec => real()();
  RealColumn get dyArcsec => real()();
  RealColumn get magnitudeArcsec => real()();
  TextColumn get recommendationCode => text().nullable()();

  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('MovingObjectCandidateRow')
@TableIndex(
    name: 'idx_moving_object_candidates_image', columns: {#capturedImageId})
@TableIndex(name: 'idx_moving_object_candidates_session', columns: {#sessionId})
@TableIndex(
    name: 'idx_moving_object_candidates_timestamp', columns: {#timestamp})
@TableIndex(
    name: 'idx_moving_object_candidates_object', columns: {#candidateId})
class MovingObjectCandidates extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get capturedImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.cascade)();
  IntColumn get sessionId => integer()
      .nullable()
      .references(ImagingSessions, #id, onDelete: KeyAction.cascade)();

  TextColumn get candidateId => text()();
  RealColumn get raDegrees => real()();
  RealColumn get decDegrees => real()();
  RealColumn get motionArcsecPerMinute => real()();
  RealColumn get positionAngleDegrees => real()();
  RealColumn get confidence => real()();
  BoolColumn get isKnownObject =>
      boolean().withDefault(const Constant(false))();
  TextColumn get objectName => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('local'))();

  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('LineRatioProductRow')
@TableIndex(name: 'idx_line_ratio_products_session', columns: {#sessionId})
@TableIndex(name: 'idx_line_ratio_products_timestamp', columns: {#createdAt})
class LineRatioProducts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()
      .nullable()
      .references(ImagingSessions, #id, onDelete: KeyAction.cascade)();

  IntColumn get hAlphaImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.setNull)();
  IntColumn get oiiiImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.setNull)();
  IntColumn get siiImageId => integer()
      .nullable()
      .references(CapturedImages, #id, onDelete: KeyAction.setNull)();

  RealColumn get ratioSiiHa => real().withDefault(const Constant(0.0))();
  RealColumn get ratioOiiiHa => real().withDefault(const Constant(0.0))();
  RealColumn get ratioSiiOiii => real().withDefault(const Constant(0.0))();

  TextColumn get roiJson => text().nullable()();
  TextColumn get exportPath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
