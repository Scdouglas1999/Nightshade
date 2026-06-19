part of '../photometric_calibration_wizard.dart';

extension _PhotometricWizardStarMatching on _PhotometricCalibrationWizardState {
  Widget _buildStep2MatchStars(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Matching detected stars to catalog',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: NightshadeTypography.fontSize14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Nightshade is matching stars detected in the selected frame against '
          'the star catalog. Stars with a known V magnitude and B-V color '
          'index will be used for the transformation fit.',
          style: TextStyle(
              color: colors.textSecondary,
              fontSize: NightshadeTypography.fontSize12),
        ),
        const SizedBox(height: 16),
        if (_isComputing)
          const Center(child: CircularProgressIndicator())
        else if (_starMatches.isEmpty)
          _buildRunMatchButton(colors)
        else
          _buildMatchResults(colors),
      ],
    );
  }

  Widget _buildRunMatchButton(NightshadeColors colors) {
    final failed = _statusMessage.startsWith('Star matching failed');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failed) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.error,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertTriangle, color: colors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: NightshadeTypography.label.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Center(
          child: NightshadeButton(
            onPressed: _runStarMatching,
            icon: LucideIcons.scan,
            label: failed ? 'Retry Match' : 'Match Stars',
          ),
        ),
      ],
    );
  }

  Widget _buildMatchResults(NightshadeColors colors) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: NightshadeDecorations.emphasisSurface(
              colors.success,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: colors.success, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${_starMatches.length} catalog stars matched',
                  style: NightshadeTypography.label.copyWith(
                    color: colors.success,
                  ),
                ),
              ],
            ),
          ),
          if (_statusMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              style: TextStyle(
                color: _statusMessage.contains('extinction is fittable')
                    ? colors.success
                    : colors.textSecondary,
                fontSize: NightshadeTypography.fontSize12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: math.min(_starMatches.length, 20),
              itemBuilder: (context, index) {
                final match = _starMatches[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                              color: colors.textMuted,
                              fontSize: NightshadeTypography.fontSize11),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'V=${match.catalogMagV.toStringAsFixed(2)}  '
                          'B-V=${match.colorIndex.toStringAsFixed(2)}  '
                          'Flux=${match.instrumentalFlux.toStringAsFixed(0)}  '
                          'SNR=${match.snr.toStringAsFixed(1)}',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: NightshadeTypography.fontSize11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runStarMatching() async {
    if (_selectedImageIds.isEmpty) {
      return;
    }

    _update(() {
      _isComputing = true;
      _statusMessage = 'Matching stars against catalog...';
    });

    try {
      final backend = ref.read(backendProvider);
      final matches = <CatalogStarMatch>[];
      for (final imageId in _selectedImageIds) {
        if (backend is NetworkBackend) {
          matches.addAll(
            await backend.matchPhotometricCalibrationStars(imageId),
          );
        } else {
          matches.addAll(await _matchesForImage(imageId));
        }
      }
      if (matches.length < 4) {
        throw StateError(
          'Only ${matches.length} catalog matches available (need at least 4)',
        );
      }

      // Keep the strongest detections; with multiple frames the budget
      // scales so each frame keeps contributing airmass leverage.
      matches.sort((a, b) => b.snr.compareTo(a.snr));
      final cap = 200 * _selectedImageIds.length;
      final topMatches =
          matches.length > cap ? matches.sublist(0, cap) : matches;

      // Report the airmass leverage so the user knows whether extinction
      // will be fittable before they hit Compute.
      var airmassMin = topMatches.first.airmass;
      var airmassMax = topMatches.first.airmass;
      for (final match in topMatches) {
        if (match.airmass < airmassMin) airmassMin = match.airmass;
        if (match.airmass > airmassMax) airmassMax = match.airmass;
      }
      final airmassSpan = airmassMax - airmassMin;

      _update(() {
        _starMatches = topMatches;
        _isComputing = false;
        _statusMessage = 'Matched ${topMatches.length} stars across '
            '${_selectedImageIds.length} frame(s). '
            'Airmass span ${airmassSpan.toStringAsFixed(2)} — '
            '${airmassSpan >= 0.05 ? 'extinction is fittable.' : 'add frames at different altitudes to fit extinction (k will be reported as 0).'}';
      });
    } catch (error, stack) {
      _update(() {
        _isComputing = false;
        _statusMessage = 'Star matching failed: $error';
      });
      ref.read(loggingServiceProvider).error(
            'Calibration wizard star matching failed: $error\n$stack',
            source: 'PhotometricCalibrationWizard',
          );
    }
  }

  /// Detect stars in one plate-solved frame, calibrate its zero point, and
  /// return catalog matches with the frame's own airmass attached — the
  /// per-frame airmass is what lets a multi-frame selection constrain
  /// atmospheric extinction.
  Future<List<CatalogStarMatch>> _matchesForImage(int imageId) async {
    final scienceBackend = ref.read(scienceBackendProvider);
    final imagesDao = ref.read(imagesDaoProvider);

    final image = await imagesDao.getImageById(imageId);
    if (image == null) {
      throw StateError('Selected image $imageId not found');
    }
    if (!image.isPlateSolved ||
        image.solvedRa == null ||
        image.solvedDec == null) {
      throw StateError('Image ${image.fileName} is not plate-solved');
    }

    final stars = await scienceBackend.measureStars(
      image.filePath,
      const PhotometryOptions(minSnr: 5.0),
    );

    if (stars.length < 4) {
      throw StateError(
          'Only ${stars.length} stars detected in ${image.fileName} '
          '(need at least 4)');
    }

    // Compute airmass from mount altitude or solved coordinates
    double airmass = 1.0;
    if (image.mountAltitude != null && image.mountAltitude! > 0) {
      final altRad = image.mountAltitude! * math.pi / 180.0;
      airmass = 1.0 /
          (math.sin(altRad) +
              0.50572 * math.pow(image.mountAltitude! + 6.07995, -1.6364));
      airmass = airmass.clamp(1.0, 8.0);
    }

    // When the stored solve carries no pixel scale (older frames, or a
    // solver that didn't report one) we recover it from the rig geometry —
    // the active profile's optical focal length and the camera's sensor
    // pixel pitch — rather than guessing a fixed 1.5"/px. The hard-coded
    // value only applies when BOTH the pixel size and focal length are
    // unavailable.
    final pixelScale =
        image.solvedPixelScale ?? await _resolveFallbackPixelScale();
    final distortion = await imagesDao.getStoredWcsDistortion(image.id);
    final sip = decodeSolvedSip(distortion?.sip);
    final wcs = WcsSolution(
      raHours: image.solvedRa!,
      decDegrees: image.solvedDec!,
      pixelScaleArcsecPerPixel: pixelScale,
      rotationDegrees: image.solvedRotation ?? 0.0,
      fieldWidthDegrees: 1.0,
      fieldHeightDegrees: 1.0,
      solverId: 'stored',
      cd1_1: distortion?.cd1_1,
      cd1_2: distortion?.cd1_2,
      cd2_1: distortion?.cd2_1,
      cd2_2: distortion?.cd2_2,
      aOrder: sip?.aOrder ?? 0,
      bOrder: sip?.bOrder ?? 0,
      aCoeffs: sip?.aCoeffs ?? const [],
      bCoeffs: sip?.bCoeffs ?? const [],
      apOrder: sip?.apOrder ?? 0,
      bpOrder: sip?.bpOrder ?? 0,
      apCoeffs: sip?.apCoeffs ?? const [],
      bpCoeffs: sip?.bpCoeffs ?? const [],
    );

    // calibrateFramePhotometry requires a real frame context (it refuses a
    // null one by contract) — build it from the captured-image row.
    final contextExposure = image.exposureDuration;
    if (!contextExposure.isFinite || contextExposure <= 0) {
      throw StateError(
        'Frame ${image.fileName} has no valid exposure duration; cannot '
        'compute exposure-normalized instrumental magnitudes.',
      );
    }
    final calibration = await scienceBackend.calibrateFramePhotometry(
      image.filePath,
      wcs,
      PhotometricCatalogSource.auto,
      ScienceFrameContext(
        capturedImageId: image.id,
        sessionId: image.sessionId,
        capturedAt: image.capturedAt,
        exposureSeconds: contextExposure,
        filterName: image.filter,
        airmass: airmass,
        imageWidth: 0,
        imageHeight: 0,
      ),
    );

    if (calibration == null || !calibration.isCalibrated) {
      throw StateError(
          'Frame photometric calibration failed for ${image.fileName}. '
          'Cannot match to catalog.');
    }

    final zp = calibration.zeroPoint ?? 0.0;

    // Photometric catalog for this field — APASS DR9 (online/cached, B and
    // V to ~mag 16) with automatic fallback to the bundled HYG catalog.
    final searchRadiusDeg = math.sqrt(
              wcs.fieldWidthDegrees * wcs.fieldWidthDegrees +
                  wcs.fieldHeightDegrees * wcs.fieldHeightDegrees,
            ) *
            0.65 +
        0.3;
    final cone = await ref.read(photometricCatalogServiceProvider).coneSearch(
          raDegrees: wcs.raHours * 15.0,
          decDegrees: wcs.decDegrees,
          radiusDegrees: searchRadiusDeg.clamp(0.25, 8.0),
          maxMagnitude: 16.0,
        );
    final catalogStars = cone.stars;

    // Build a spatial index of catalog stars projected to pixel coords
    // for matching to detected stars.
    final imageSize = await _resolveImagePixelSize(
      filePath: image.filePath,
      stars: stars,
      pixelScale: image.solvedPixelScale,
    );
    // Canonical TAN projection (services/wcs in nightshade_core) — the
    // same implementation the science pipeline and catalog overlay use.
    final solvedWcs = SolvedWcs(
      raHours: wcs.raHours,
      decDegrees: wcs.decDegrees,
      rotationDeg: wcs.rotationDegrees,
      pixelScaleArcsec: wcs.pixelScaleArcsecPerPixel,
      imageWidth: imageSize.width.round(),
      imageHeight: imageSize.height.round(),
      cd1_1: wcs.cd1_1,
      cd1_2: wcs.cd1_2,
      cd2_1: wcs.cd2_1,
      cd2_2: wcs.cd2_2,
      aOrder: wcs.aOrder,
      bOrder: wcs.bOrder,
      aCoeffs: wcs.aCoeffs,
      bCoeffs: wcs.bCoeffs,
      apOrder: wcs.apOrder,
      bpOrder: wcs.bpOrder,
      apCoeffs: wcs.apCoeffs,
      bpCoeffs: wcs.bpCoeffs,
    );
    if (!solvedWcs.isValid) {
      throw StateError(
        'Frame WCS is not projectable (pixel scale '
        '${wcs.pixelScaleArcsecPerPixel}"/px, image '
        '${imageSize.width.round()}x${imageSize.height.round()}).',
      );
    }
    final projection = GnomonicProjection(solvedWcs);
    final projectedCatalog =
        <({double x, double y, PhotometricCatalogStar star})>[];
    for (final catStar in catalogStars) {
      if (!catStar.magV.isFinite) continue;
      final px = projection.worldToPixel(
        raDegrees: catStar.raDegrees,
        decDegrees: catStar.decDegrees,
      );
      if (px != null) {
        projectedCatalog.add((x: px.pixel.x, y: px.pixel.y, star: catStar));
      }
    }

    // Build matches: for each detected star, find the nearest catalog
    // star and take its REAL catalog V magnitude and B-V color index.
    //
    // Why catalog data is mandatory: a previous revision synthesized
    // catalogV from the detected star's own instrumental magnitude plus
    // the frame zero point (catalogV = instMag + zp). That made
    // y = catalogV - instMag a constant for every star, so the transform
    // fit was circular — it could only ever recover the frame ZP with a
    // zero color term, regardless of the camera's true color response.
    // Stars without a genuine catalog counterpart are dropped instead of
    // being filled with synthetic values that would poison the fit.
    //
    // Fluxes are normalized by exposure so the saved transform applies to
    // science frames of any exposure length (the pipeline normalizes the
    // same way before applying the transform). Validated above when the
    // frame context was built.
    final exposureSeconds = contextExposure;
    final usedCatalogIndices = <int>{};
    final matches = <CatalogStarMatch>[];
    var skippedNoCatalog = 0;
    var skippedImplausible = 0;
    for (final star in stars) {
      if (star.flux <= 0 || star.snr < 5.0) continue;
      final normalizedFlux = star.flux / exposureSeconds;
      final instMag = -2.5 *
          math.log(normalizedFlux.clamp(1e-30, double.infinity)) /
          math.ln10;

      // Find the closest unclaimed catalog star within 10 pixels.
      double bestDist = 10.0;
      int? bestIdx;
      for (int i = 0; i < projectedCatalog.length; i++) {
        if (usedCatalogIndices.contains(i)) continue;
        final cat = projectedCatalog[i];
        final dx = star.x - cat.x;
        final dy = star.y - cat.y;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist < bestDist) {
          bestDist = dist;
          bestIdx = i;
        }
      }
      if (bestIdx == null) {
        skippedNoCatalog++;
        continue;
      }
      final matchedStar = projectedCatalog[bestIdx].star;
      final catalogV = matchedStar.magV;

      // Sanity gate on the pairing: the frame ZP predicts
      // V ≈ instMag + zp. A positional match whose brightness disagrees
      // by over ~1.5 mag is almost certainly the wrong star (blend,
      // double, or projection error) and would corrupt the fit.
      if ((instMag + zp - catalogV).abs() > 1.5) {
        skippedImplausible++;
        continue;
      }

      // B-V straight from the catalog (APASS measures it; the HYG fallback
      // derives it from color index or spectral type inside the service).
      // No synthetic fallback: a made-up color paired with a real V mag
      // only adds noise to the color-term fit.
      final bv = matchedStar.colorIndexBv;
      if (bv == null || !bv.isFinite) {
        skippedNoCatalog++;
        continue;
      }

      usedCatalogIndices.add(bestIdx);
      matches.add(CatalogStarMatch(
        x: star.x,
        y: star.y,
        raDegrees: matchedStar.raDegrees,
        decDegrees: matchedStar.decDegrees,
        catalogMagV: catalogV,
        catalogMagB: catalogV + bv,
        instrumentalFlux: normalizedFlux,
        snr: star.snr,
        airmass: airmass,
      ));
    }
    if (skippedNoCatalog > 0 || skippedImplausible > 0) {
      ref.read(loggingServiceProvider).info(
            'Calibration wizard (${image.fileName}): ${matches.length} '
            'catalog matches kept, $skippedNoCatalog star(s) without '
            'usable catalog data, $skippedImplausible implausible '
            'pairing(s) rejected.',
            source: 'PhotometricCalibrationWizard',
          );
    }

    // Per-frame cap: keep the strongest 200 detections; the orchestrator
    // applies an overall budget across frames.
    matches.sort((a, b) => b.snr.compareTo(a.snr));
    return matches.length > 200 ? matches.sublist(0, 200) : matches;
  }

  /// Resolve the pixel scale to use when a frame has no stored
  /// `solvedPixelScale`, from the active rig geometry.
  ///
  /// Reads the active equipment profile for the optical focal length and the
  /// profile camera's [CameraCapabilities.pixelSizeX] for the sensor pitch,
  /// then computes arcsec/pixel via [_fallbackPixelScale]. A missing profile,
  /// camera, or capability query leaves the corresponding input null, and the
  /// helper only collapses to the fixed default when BOTH are unavailable.
  Future<double> _resolveFallbackPixelScale() async {
    final profile = ref.read(activeEquipmentProfileProvider);

    // Effective focal length already folds in any reducer/barlow (the profile
    // stores the optical-train focal length, not the bare OTA value). Treat a
    // non-positive value as "unknown" so it can't divide-by-zero.
    final focalLengthMm = (profile != null && profile.focalLength > 0)
        ? profile.focalLength
        : null;

    double? pixelSizeUm;
    final cameraId = profile?.cameraId;
    if (cameraId != null && cameraId.isNotEmpty) {
      try {
        final caps =
            await ref.read(cameraCapabilitiesProvider(cameraId).future);
        final px = caps?.pixelSizeX;
        if (px != null && px > 0) {
          pixelSizeUm = px;
        }
      } catch (_) {
        // Camera offline / driver exposes no capabilities: leave the pixel
        // size unknown and let the helper fall back accordingly.
      }
    }

    return fallbackPixelScaleArcsecPerPixel(
      pixelSizeUm: pixelSizeUm,
      focalLengthMm: focalLengthMm,
    );
  }

  Future<({double width, double height})> _resolveImagePixelSize({
    required String filePath,
    required List<StarMeasurement> stars,
    double? pixelScale,
  }) async {
    if (!ref.read(isRemoteModeProvider)) {
      final fits = await ref
          .read(imagingBackendProvider)
          .readFitsFile(filePath: filePath);
      return (width: fits.width.toDouble(), height: fits.height.toDouble());
    }

    // Remote: ask the host for the TRUE dimensions (it reads the real FITS
    // header) rather than estimating from the star bounding box. The estimate
    // below remains only as a last resort if the host can't read the file.
    final backend = ref.read(backendProvider);
    if (backend is NetworkBackend) {
      final dims = await backend.getFitsDimensions(filePath);
      if (dims != null) {
        return (width: dims.width.toDouble(), height: dims.height.toDouble());
      }
    }

    if (stars.isNotEmpty) {
      final maxX = stars.map((s) => s.x).reduce(math.max);
      final maxY = stars.map((s) => s.y).reduce(math.max);
      final minX = stars.map((s) => s.x).reduce(math.min);
      final minY = stars.map((s) => s.y).reduce(math.min);
      const margin = 64.0;
      return (
        width: (maxX - minX) + margin * 2,
        height: (maxY - minY) + margin * 2,
      );
    }

    final scale = pixelScale;
    if (scale != null && scale > 0) {
      const fieldDeg = 1.0;
      final px = fieldDeg * 3600.0 / scale;
      return (width: px, height: px);
    }

    throw StateError(
      'Cannot determine image dimensions for remote catalog matching',
    );
  }

  // =========================================================================
  // Step 3: Compute fit
  // =========================================================================
}
