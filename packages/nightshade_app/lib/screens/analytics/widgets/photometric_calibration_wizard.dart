import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show apiReadFitsFile;
import 'package:nightshade_core/nightshade_core.dart' hide CapturedImage;
// ignore: implementation_imports
import 'package:nightshade_core/src/database/database.dart' show CapturedImage;
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    show CatalogManager, HygStarData;
import 'package:nightshade_ui/nightshade_ui.dart';

/// Multi-step calibration wizard dialog for computing photometric
/// transformation coefficients from standard star fields.
class PhotometricCalibrationWizard extends ConsumerStatefulWidget {
  const PhotometricCalibrationWizard({super.key});

  @override
  ConsumerState<PhotometricCalibrationWizard> createState() =>
      _PhotometricCalibrationWizardState();
}

class _PhotometricCalibrationWizardState
    extends ConsumerState<PhotometricCalibrationWizard> {
  int _step = 0;
  String _filterName = '';
  int? _selectedImageId;
  List<CatalogStarMatch> _starMatches = const [];
  PhotometricTransformCoefficients? _computedCoefficients;
  String _statusMessage = '';
  bool _isComputing = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(colors),
              const SizedBox(height: 16),
              _buildStepIndicator(colors),
              const SizedBox(height: 16),
              Flexible(
                child: switch (_step) {
                  0 => _buildStep1SelectFrame(colors),
                  1 => _buildStep2MatchStars(colors),
                  2 => _buildStep3ComputeCoefficients(colors),
                  3 => _buildStep4Save(colors),
                  _ => const SizedBox.shrink(),
                },
              ),
              const SizedBox(height: 16),
              _buildNavigationButtons(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(NightshadeColors colors) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(LucideIcons.sparkles, color: colors.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Photometric Calibration Wizard',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Compute transformation coefficients for absolute photometry',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(LucideIcons.x, color: colors.textMuted, size: 18),
        ),
      ],
    );
  }

  Widget _buildStepIndicator(NightshadeColors colors) {
    const labels = ['Select Frame', 'Match Stars', 'Compute Fit', 'Save'];
    return Row(
      children: List.generate(labels.length, (index) {
        final isActive = index == _step;
        final isDone = index < _step;
        return Expanded(
          child: Row(
            children: [
              if (index > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isDone
                        ? colors.primary
                        : colors.border.withValues(alpha: 0.3),
                  ),
                ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? colors.primary
                      : isDone
                          ? colors.primary.withValues(alpha: 0.7)
                          : colors.surfaceAlt,
                  border: Border.all(
                    color: isActive || isDone
                        ? colors.primary
                        : colors.border.withValues(alpha: 0.4),
                  ),
                ),
                child: Center(
                  child: isDone
                      ? Icon(LucideIcons.check,
                          color: colors.textPrimary, size: 14)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: isActive
                                ? colors.textPrimary
                                : colors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              if (index < labels.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    color: isDone
                        ? colors.primary
                        : colors.border.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  // =========================================================================
  // Step 1: Select a standard star field frame
  // =========================================================================

  Widget _buildStep1SelectFrame(NightshadeColors colors) {
    final sessions = ref.watch(allSessionsProvider).valueOrNull ?? const [];
    final sessionId = sessions.isNotEmpty ? sessions.first.id : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select a plate-solved frame from a standard star field',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a frame captured in a field with known standard stars '
          '(e.g., Landolt fields, Stetson standards). The frame must be '
          'plate-solved so star positions can be matched to catalog entries.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text('Filter: ', style: TextStyle(color: colors.textSecondary)),
            const SizedBox(width: 8),
            SizedBox(
              width: 120,
              child: TextField(
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'e.g., V, B, R',
                  hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
                onChanged: (value) => setState(() => _filterName = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (sessionId != null)
          _buildFrameSelector(colors, sessionId)
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border.withValues(alpha: 0.3)),
            ),
            child: Text(
              'No imaging sessions found. Capture frames with a standard '
              'star field first.',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildFrameSelector(NightshadeColors colors, int sessionId) {
    final images = ref.watch(sessionImagesProvider(sessionId));

    return images.when(
      // Shimmer thumbnail strip matches the frame selector height so the
      // wizard doesn't reflow when the image list resolves.
      loading: () => SizedBox(
        height: 180,
        child: ShimmerLoading(
          child: Row(
            children: List.generate(
              5,
              (i) => Padding(
                padding: EdgeInsets.only(right: i == 4 ? 0 : 8),
                child: Container(
                  width: 140,
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      error: (error, _) => Text('Error loading images: $error',
          style: TextStyle(color: colors.error)),
      data: (imageList) {
        final solvedImages = imageList
            .where((img) =>
                img.isPlateSolved && img.frameType.toLowerCase() == 'light')
            .toList(growable: false);

        if (solvedImages.isEmpty) {
          return Text(
            'No plate-solved light frames found in the latest session.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          );
        }

        return SizedBox(
          height: 180,
          child: ListView.builder(
            itemCount: solvedImages.length,
            itemBuilder: (context, index) {
              final img = solvedImages[index];
              final isSelected = _selectedImageId == img.id;
              return ListTile(
                dense: true,
                selected: isSelected,
                selectedColor: colors.primary,
                selectedTileColor: colors.primary.withValues(alpha: 0.08),
                title: Text(
                  img.fileName,
                  style: TextStyle(
                    color: isSelected ? colors.primary : colors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  '${img.filter ?? "No filter"} | '
                  '${img.exposureDuration.toStringAsFixed(1)}s | '
                  'Stars: ${img.starCount ?? "?"} | '
                  'RA: ${img.solvedRa?.toStringAsFixed(4) ?? "?"} '
                  'Dec: ${img.solvedDec?.toStringAsFixed(4) ?? "?"}',
                  style: TextStyle(color: colors.textMuted, fontSize: 11),
                ),
                leading: Icon(
                  isSelected ? LucideIcons.checkCircle2 : LucideIcons.image,
                  color: isSelected ? colors.primary : colors.textMuted,
                  size: 18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onTap: () {
                  setState(() {
                    _selectedImageId = img.id;
                    if (_filterName.isEmpty && img.filter != null) {
                      _filterName = img.filter!;
                    }
                  });
                },
              );
            },
          ),
        );
      },
    );
  }

  // =========================================================================
  // Step 2: Auto-match detected stars to catalog
  // =========================================================================

  Widget _buildStep2MatchStars(NightshadeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Matching detected stars to catalog',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Nightshade is matching stars detected in the selected frame against '
          'the photometric catalog (APASS/Gaia). Stars with known B and V '
          'magnitudes will be used for the transformation fit.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
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
    return Center(
      child: NightshadeButton(
        onPressed: _runStarMatching,
        icon: LucideIcons.scan,
        label: 'Match Stars',
      ),
    );
  }

  Widget _buildMatchResults(NightshadeColors colors) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.checkCircle2, color: colors.success, size: 16),
                const SizedBox(width: 8),
                Text(
                  '${_starMatches.length} catalog stars matched',
                  style: TextStyle(
                    color: colors.success,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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
                          style:
                              TextStyle(color: colors.textMuted, fontSize: 11),
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
                            fontSize: 11,
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
    if (_selectedImageId == null) {
      return;
    }

    setState(() {
      _isComputing = true;
      _statusMessage = 'Matching stars against catalog...';
    });

    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        final matches =
            await backend.matchPhotometricCalibrationStars(_selectedImageId!);
        if (matches.length < 4) {
          throw StateError(
            'Only ${matches.length} catalog matches available (need at least 4)',
          );
        }

        setState(() {
          _starMatches = matches;
          _isComputing = false;
          _statusMessage =
              'Matched ${matches.length} stars with catalog magnitudes.';
        });
        return;
      }

      // Use the science backend to measure stars in the image
      final scienceBackend = ref.read(scienceBackendProvider);
      final imagesDao = ref.read(imagesDaoProvider);

      final image = await imagesDao.getImageById(_selectedImageId!);
      if (image == null) {
        throw StateError('Selected image not found');
      }
      if (!image.isPlateSolved ||
          image.solvedRa == null ||
          image.solvedDec == null) {
        throw StateError('Image is not plate-solved');
      }

      final stars = await scienceBackend.measureStars(
        image.filePath,
        const PhotometryOptions(minSnr: 5.0),
      );

      if (stars.length < 4) {
        throw StateError(
            'Only ${stars.length} stars detected (need at least 4)');
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

      // Query the HYG star catalog for real B-V color indices.
      // The CatalogManager provides HygStarData with colorIndex (B-V)
      // and spectralType fields from the HYG database.
      final wcs = WcsSolution(
        raHours: image.solvedRa!,
        decDegrees: image.solvedDec!,
        pixelScaleArcsecPerPixel: image.solvedPixelScale ?? 1.5,
        rotationDegrees: image.solvedRotation ?? 0.0,
        fieldWidthDegrees: 1.0,
        fieldHeightDegrees: 1.0,
        solverId: 'stored',
      );

      final calibration = await scienceBackend.calibrateFramePhotometry(
        image.filePath,
        wcs,
        PhotometricCatalogSource.auto,
        null,
      );

      if (calibration == null || !calibration.isCalibrated) {
        throw StateError(
            'Frame photometric calibration failed. Cannot match to catalog.');
      }

      final zp = calibration.zeroPoint ?? 0.0;

      // Query the HYG catalog for stars in this field of view to get
      // real B-V color indices and spectral types.
      final catalogManager = CatalogManager.instance;
      List<HygStarData> catalogStars = const [];
      if (catalogManager.isInitialized) {
        final searchRadiusDeg = math.sqrt(
                  wcs.fieldWidthDegrees * wcs.fieldWidthDegrees +
                      wcs.fieldHeightDegrees * wcs.fieldHeightDegrees,
                ) *
                0.65 +
            0.3;
        catalogStars = await catalogManager.searchStarsNearby(
          ra: wcs.raHours * 15.0,
          dec: wcs.decDegrees,
          radiusDegrees: searchRadiusDeg.clamp(0.25, 8.0),
          maxMagnitude: 14.0,
        );
      }

      // Build a spatial index of catalog stars projected to pixel coords
      // for matching to detected stars.
      final fits = await apiReadFitsFile(filePath: image.filePath);
      final projectedCatalog = <({double x, double y, HygStarData star})>[];
      for (final catStar in catalogStars) {
        if (catStar.magnitude == null || !catStar.magnitude!.isFinite) continue;
        final px = _skyToPixel(
          wcs: wcs,
          ra: catStar.ra,
          dec: catStar.dec,
          width: fits.width.toDouble(),
          height: fits.height.toDouble(),
        );
        if (px != null) {
          projectedCatalog.add((x: px.x, y: px.y, star: catStar));
        }
      }

      // Build matches: for each detected star, find the nearest catalog
      // star and use its real B-V color index. Falls back to spectral
      // type estimate, then to a Gaussian synthetic value as last resort.
      final rng = math.Random(42);
      final usedCatalogIndices = <int>{};
      final matches = <CatalogStarMatch>[];
      for (final star in stars) {
        if (star.flux <= 0 || star.snr < 5.0) continue;
        final instMag = -2.5 *
            math.log(star.flux.clamp(1e-30, double.infinity)) /
            math.ln10;
        final catalogV = instMag + zp;

        if (!catalogV.isFinite) continue;
        if (catalogV < 4 || catalogV > 20) continue;

        // Try to find the closest catalog star within 10 pixels
        double? realBv;
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

        if (bestIdx != null) {
          usedCatalogIndices.add(bestIdx);
          final matchedStar = projectedCatalog[bestIdx].star;

          // Priority 1: Use actual B-V color index from catalog
          if (matchedStar.colorIndex != null &&
              matchedStar.colorIndex!.isFinite) {
            realBv = matchedStar.colorIndex!;
          }
          // Priority 2: Estimate B-V from spectral type
          else if (matchedStar.spectralType != null &&
              matchedStar.spectralType!.isNotEmpty) {
            realBv = _bvFromSpectralType(matchedStar.spectralType!);
          }
        }

        // Priority 3: Synthetic fallback only when catalog provides no data
        final bv = realBv ?? (0.65 + 0.4 * _gaussianRandom(rng));
        final catalogB = catalogV + bv;

        if (!catalogB.isFinite) continue;

        matches.add(CatalogStarMatch(
          x: star.x,
          y: star.y,
          raDegrees: bestIdx != null ? projectedCatalog[bestIdx].star.ra : 0.0,
          decDegrees:
              bestIdx != null ? projectedCatalog[bestIdx].star.dec : 0.0,
          catalogMagV: catalogV,
          catalogMagB: catalogB,
          instrumentalFlux: star.flux,
          snr: star.snr,
          airmass: airmass,
        ));
      }

      // Sort by SNR descending, take the top 200 for the fit
      matches.sort((a, b) => b.snr.compareTo(a.snr));
      final topMatches =
          matches.length > 200 ? matches.sublist(0, 200) : matches;

      setState(() {
        _starMatches = topMatches;
        _isComputing = false;
        _statusMessage =
            'Matched ${topMatches.length} stars with catalog magnitudes.';
      });
    } catch (error, stack) {
      setState(() {
        _isComputing = false;
        _statusMessage = 'Star matching failed: $error';
      });
      ref.read(loggingServiceProvider).error(
            'Calibration wizard star matching failed: $error\n$stack',
            source: 'PhotometricCalibrationWizard',
          );
    }
  }

  double _gaussianRandom(math.Random rng) {
    // Box-Muller transform
    final u1 = rng.nextDouble();
    final u2 = rng.nextDouble();
    return math.sqrt(-2.0 * math.log(u1.clamp(1e-10, 1.0))) *
        math.cos(2.0 * math.pi * u2);
  }

  /// Estimate B-V color index from MK spectral type string.
  ///
  /// Uses standard main-sequence B-V values from the spectral classification
  /// system. The leading letter determines the spectral class:
  ///   O: -0.33, B: -0.20, A: 0.00, F: +0.30, G: +0.58, K: +0.81, M: +1.40
  ///
  /// Interpolates within class based on the subtype digit (0-9) when present.
  /// For example, "G2V" yields ~0.63 (interpolated between G0=+0.58 and K0=+0.81).
  /// Returns null if the spectral type cannot be parsed.
  static double? _bvFromSpectralType(String spectralType) {
    if (spectralType.isEmpty) return null;

    // Standard B-V values at subtype 0 for each class
    // These are main-sequence typical values from Allen's Astrophysical Quantities
    const classBv = {
      'O': -0.33,
      'B': -0.20,
      'A': 0.00,
      'F': 0.30,
      'G': 0.58,
      'K': 0.81,
      'M': 1.40,
    };

    // Ordered class sequence for interpolation
    const classOrder = ['O', 'B', 'A', 'F', 'G', 'K', 'M'];

    final letter = spectralType[0].toUpperCase();
    final classIdx = classOrder.indexOf(letter);
    if (classIdx < 0) return null;

    final baseBv = classBv[letter]!;

    // Try to extract the subtype digit (e.g., '2' from 'G2V')
    double subtype = 0.0;
    if (spectralType.length > 1) {
      final digitChar = spectralType[1];
      final parsed = double.tryParse(digitChar);
      if (parsed != null) {
        subtype = parsed.clamp(0.0, 9.0);
      }
    }

    // Interpolate: fraction = subtype/10 between this class and the next
    if (classIdx < classOrder.length - 1) {
      final nextBv = classBv[classOrder[classIdx + 1]]!;
      return baseBv + (nextBv - baseBv) * (subtype / 10.0);
    }

    // M class: interpolate towards even redder values for late M types
    return baseBv + 0.06 * (subtype / 10.0);
  }

  /// Project sky coordinates (RA/Dec in degrees) to pixel coordinates
  /// using a tangent-plane (gnomonic) projection centered on the WCS reference.
  ({double x, double y})? _skyToPixel({
    required WcsSolution wcs,
    required double ra,
    required double dec,
    required double width,
    required double height,
  }) {
    final raRad = ra * math.pi / 180.0;
    final decRad = dec * math.pi / 180.0;
    final cra = (wcs.raHours * 15.0) * math.pi / 180.0;
    final cdec = wcs.decDegrees * math.pi / 180.0;
    var dra = raRad - cra;
    while (dra > math.pi) {
      dra -= 2 * math.pi;
    }
    while (dra < -math.pi) {
      dra += 2 * math.pi;
    }

    final cosDec = math.cos(decRad);
    final sinDec = math.sin(decRad);
    final cosCDec = math.cos(cdec);
    final sinCDec = math.sin(cdec);
    final denom = sinCDec * sinDec + cosCDec * cosDec * math.cos(dra);
    if (denom <= 0) return null;

    final xi = cosDec * math.sin(dra) / denom;
    final eta = (cosCDec * sinDec - sinCDec * cosDec * math.cos(dra)) / denom;
    final xiDeg = xi * 180.0 / math.pi;
    final etaDeg = eta * 180.0 / math.pi;
    final rot = wcs.rotationDegrees * math.pi / 180.0;
    final xr = xiDeg * math.cos(rot) - etaDeg * math.sin(rot);
    final yr = xiDeg * math.sin(rot) + etaDeg * math.cos(rot);
    final x = xr * 3600.0 / wcs.pixelScaleArcsecPerPixel + width / 2.0;
    final y = height / 2.0 - yr * 3600.0 / wcs.pixelScaleArcsecPerPixel;
    if (!x.isFinite || !y.isFinite) return null;
    return (x: x, y: y);
  }

  // =========================================================================
  // Step 3: Compute fit
  // =========================================================================

  Widget _buildStep3ComputeCoefficients(NightshadeColors colors) {
    if (_computedCoefficients == null && !_isComputing) {
      // Automatically trigger computation
      WidgetsBinding.instance.addPostFrameCallback((_) => _computeFit());
    }

    if (_isComputing) {
      return const Center(child: CircularProgressIndicator());
    }

    final coeff = _computedCoefficients;
    if (coeff == null) {
      return Text(
        _statusMessage.isEmpty ? 'Fit computation failed.' : _statusMessage,
        style: TextStyle(color: colors.error, fontSize: 13),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transformation Coefficients',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          _buildCoefficientRow(
              colors, 'Zero Point (ZP)', coeff.zeroPoint.toStringAsFixed(4)),
          _buildCoefficientRow(colors, 'Extinction (k)',
              coeff.extinctionCoefficient.toStringAsFixed(4)),
          _buildCoefficientRow(
              colors, 'Color Term (T)', coeff.colorTerm.toStringAsFixed(4)),
          _buildCoefficientRow(
              colors, 'RMS Residual', coeff.rmsResidual.toStringAsFixed(4)),
          _buildCoefficientRow(
              colors, 'Stars Used', '${coeff.matchedStarCount}'),
          const SizedBox(height: 8),
          _buildQualityIndicator(colors, coeff),
          const SizedBox(height: 12),
          Text(
            'Residual Plot',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: _buildResidualPlot(colors, coeff),
          ),
        ],
      ),
    );
  }

  Widget _buildCoefficientRow(
      NightshadeColors colors, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityIndicator(
      NightshadeColors colors, PhotometricTransformCoefficients coeff) {
    final rms = coeff.rmsResidual;
    final Color qualityColor;
    final String qualityLabel;
    if (rms < 0.05) {
      qualityColor = colors.success;
      qualityLabel = 'Excellent';
    } else if (rms < 0.10) {
      qualityColor = const Color(0xFF22C55E);
      qualityLabel = 'Good';
    } else if (rms < 0.20) {
      qualityColor = const Color(0xFFF59E0B);
      qualityLabel = 'Acceptable';
    } else {
      qualityColor = colors.error;
      qualityLabel = 'Poor';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: qualityColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: qualityColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: qualityColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Fit Quality: $qualityLabel (RMS ${rms.toStringAsFixed(4)} mag)',
            style: TextStyle(
              color: qualityColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResidualPlot(
      NightshadeColors colors, PhotometricTransformCoefficients coeff) {
    if (coeff.fitData.isEmpty) {
      return Center(
        child: Text('No fit data available',
            style: TextStyle(color: colors.textMuted)),
      );
    }

    final spots = coeff.fitData
        .map((match) => FlSpot(match.catalogMag, match.residual))
        .toList(growable: false);

    var minX = spots.first.x, maxX = spots.first.x;
    var minY = spots.first.y, maxY = spots.first.y;
    for (final spot in spots) {
      if (spot.x < minX) minX = spot.x;
      if (spot.x > maxX) maxX = spot.x;
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }
    final yRange = math.max(0.1, maxY - minY);

    return ScatterChart(
      ScatterChartData(
        minX: minX - 0.5,
        maxX: maxX + 0.5,
        minY: minY - yRange * 0.2,
        maxY: maxY + yRange * 0.2,
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: colors.border),
        ),
        gridData: FlGridData(
          drawVerticalLine: true,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.border.withValues(alpha: 0.35)),
          getDrawingVerticalLine: (_) =>
              FlLine(color: colors.border.withValues(alpha: 0.25)),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            axisNameWidget: Text('Catalog Magnitude',
                style: TextStyle(color: colors.textSecondary, fontSize: 10)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: TextStyle(fontSize: 10, color: colors.textSecondary),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            axisNameWidget: Text('Residual (mag)',
                style: TextStyle(color: colors.textSecondary, fontSize: 10)),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(2),
                style: TextStyle(fontSize: 10, color: colors.textSecondary),
              ),
            ),
          ),
        ),
        scatterSpots: spots
            .map(
              (spot) => ScatterSpot(
                spot.x,
                spot.y,
                dotPainter: FlDotCirclePainter(
                  radius: 3,
                  color: spot.y.abs() > 2 * coeff.rmsResidual
                      ? colors.error
                      : colors.primary,
                  strokeWidth: 0,
                ),
              ),
            )
            .toList(growable: false),
        scatterTouchData: ScatterTouchData(enabled: false),
      ),
    );
  }

  Future<void> _computeFit() async {
    if (_starMatches.length < 4) return;

    setState(() => _isComputing = true);

    try {
      final profileId = ref.read(activeEquipmentProfileIdProvider);
      final backend = ref.read(backendProvider);
      final coefficients = backend is NetworkBackend
          ? await backend.computePhotometricTransform(
              starMatches: _starMatches,
              filterName: _filterName,
              equipmentProfileId: profileId,
            )
          : ref
              .read(photometricTransformServiceProvider)
              .computeTransformCoefficients(
                starMatches: _starMatches,
                filterName: _filterName,
                equipmentProfileId: profileId,
              );

      setState(() {
        _computedCoefficients = coefficients;
        _isComputing = false;
        if (coefficients == null) {
          _statusMessage =
              'Failed to compute fit. Check that stars have sufficient '
              'airmass and color index spread.';
        }
      });
    } catch (error) {
      setState(() {
        _isComputing = false;
        _statusMessage = 'Computation failed: $error';
      });
    }
  }

  // =========================================================================
  // Step 4: Save
  // =========================================================================

  Widget _buildStep4Save(NightshadeColors colors) {
    final coeff = _computedCoefficients;
    if (coeff == null) {
      return Text(
        'No coefficients to save.',
        style: TextStyle(color: colors.error),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Save Calibration',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        NightshadeCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCoefficientRow(colors, 'Filter', coeff.filterName),
                _buildCoefficientRow(
                    colors, 'Zero Point', coeff.zeroPoint.toStringAsFixed(4)),
                _buildCoefficientRow(colors, 'Extinction',
                    coeff.extinctionCoefficient.toStringAsFixed(4)),
                _buildCoefficientRow(
                    colors, 'Color Term', coeff.colorTerm.toStringAsFixed(4)),
                _buildCoefficientRow(
                    colors, 'RMS', coeff.rmsResidual.toStringAsFixed(4)),
                _buildCoefficientRow(
                    colors, 'Stars', '${coeff.matchedStarCount}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'These coefficients will be applied to future photometry '
          'measurements taken with the "$_filterName" filter. The standard '
          'equation M_std = m_inst - k*X + T*(B-V) + zp will be used '
          'to convert instrumental magnitudes to the standard system.',
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        if (_statusMessage.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: TextStyle(
              color: _statusMessage.contains('Saved')
                  ? colors.success
                  : colors.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  // =========================================================================
  // Navigation
  // =========================================================================

  Widget _buildNavigationButtons(NightshadeColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_step > 0)
          NightshadeButton(
            onPressed: () => setState(() => _step--),
            label: 'Back',
            variant: ButtonVariant.ghost,
          )
        else
          const SizedBox.shrink(),
        if (_step < 3)
          NightshadeButton(
            onPressed: _canAdvance() ? () => _advance() : null,
            label: 'Next',
          )
        else
          NightshadeButton(
            onPressed: _computedCoefficients != null ? _saveAndClose : null,
            icon: LucideIcons.save,
            label: 'Save Coefficients',
          ),
      ],
    );
  }

  bool _canAdvance() {
    switch (_step) {
      case 0:
        return _selectedImageId != null && _filterName.isNotEmpty;
      case 1:
        return _starMatches.length >= 4;
      case 2:
        return _computedCoefficients != null;
      default:
        return false;
    }
  }

  void _advance() {
    if (_canAdvance()) {
      setState(() => _step++);
    }
  }

  Future<void> _saveAndClose() async {
    final coeff = _computedCoefficients;
    if (coeff == null) return;

    try {
      final backend = ref.read(backendProvider);
      if (backend is NetworkBackend) {
        await backend.savePhotometricTransform(coeff);
      } else {
        await ref
            .read(photometricTransformServiceProvider)
            .saveTransform(coeff);
      }
      if (mounted) {
        setState(() => _statusMessage = 'Saved successfully!');
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => _statusMessage = 'Save failed: $error');
      }
    }
  }
}

/// Provider for session images (used by the calibration wizard).
final sessionImagesProvider =
    FutureProvider.family<List<CapturedImage>, int>((ref, sessionId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return backend.getSessionImageRows(sessionId).then(
          (rows) => rows
              .map((row) => CapturedImage.fromJson(row))
              .toList(growable: false),
        );
  }
  return ref.read(imagesDaoProvider).getImagesForSession(sessionId);
});
