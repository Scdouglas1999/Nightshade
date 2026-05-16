import '../coordinate_system.dart';

/// A single path segment for a constellation art figure.
/// Each segment is either a moveTo (starting a new sub-path) or a lineTo/curveTo.
sealed class ArtPathSegment {
  const ArtPathSegment();
}

/// Move to a celestial coordinate (starts a new sub-path)
class ArtMoveTo extends ArtPathSegment {
  final CelestialCoordinate point;
  const ArtMoveTo(this.point);
}

/// Line to a celestial coordinate
class ArtLineTo extends ArtPathSegment {
  final CelestialCoordinate point;
  const ArtLineTo(this.point);
}

/// Quadratic bezier curve to a celestial coordinate via a control point.
/// Control point is in celestial coordinates (RA hours, Dec degrees).
class ArtQuadTo extends ArtPathSegment {
  final CelestialCoordinate control;
  final CelestialCoordinate point;
  const ArtQuadTo(this.control, this.point);
}

/// Close the current sub-path back to the last moveTo
class ArtClose extends ArtPathSegment {
  const ArtClose();
}

/// Art overlay definition for a single constellation.
/// Each figure is composed of one or more closed or open paths that suggest
/// the mythological figure associated with the constellation. Vertices are
/// anchored to (or offset from) the constellation's named star positions.
class ConstellationArtData {
  /// IAU three-letter abbreviation (matches ConstellationData.abbreviation)
  final String abbreviation;

  /// Ordered path segments that form the figure outline
  final List<ArtPathSegment> segments;

  const ConstellationArtData({
    required this.abbreviation,
    required this.segments,
  });
}

/// Procedural constellation art figures for the 20 most recognizable
/// constellations. Each figure is a stylized outline suggesting the
/// mythological character, built from celestial coordinates anchored to
/// the constellation's prominent stars.
class ConstellationArt {
  static List<ConstellationArtData> get all => _figures;

  static ConstellationArtData? findByAbbreviation(String abbr) {
    final lower = abbr.toLowerCase();
    return _figures
        .where((f) => f.abbreviation.toLowerCase() == lower)
        .firstOrNull;
  }

  // Helper to create coordinates concisely
  static CelestialCoordinate _c(double ra, double dec) =>
      CelestialCoordinate(ra: ra, dec: dec);

  static final List<ConstellationArtData> _figures = [
    // ================================================================
    // ORION — The Hunter
    // Anchor stars: Betelgeuse (5.92, 7.41), Bellatrix (5.42, 6.35),
    //   Mintaka (5.53, -0.30), Alnilam (5.60, -1.20), Alnitak (5.68, -1.94),
    //   Rigel (5.24, -8.20), Saiph (5.80, -9.67)
    // Figure: upright human figure — head, shoulders, belt, legs, raised arm
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Ori',
      segments: [
        // Head (small circle approximated by quad arcs above shoulders)
        ArtMoveTo(_c(5.67, 10.5)),
        ArtQuadTo(_c(5.85, 11.5), _c(5.67, 12.0)),
        ArtQuadTo(_c(5.50, 11.5), _c(5.67, 10.5)),
        const ArtClose(),
        // Torso: shoulders → belt → hips
        ArtMoveTo(_c(5.42, 6.35)),   // Bellatrix (left shoulder)
        ArtLineTo(_c(5.92, 7.41)),    // Betelgeuse (right shoulder)
        ArtLineTo(_c(5.92, 5.0)),     // right armpit
        ArtLineTo(_c(5.68, -1.94)),   // Alnitak (right belt)
        ArtLineTo(_c(5.80, -4.5)),    // right hip
        ArtLineTo(_c(5.48, -4.5)),    // left hip
        ArtLineTo(_c(5.53, -0.30)),   // Mintaka (left belt)
        ArtLineTo(_c(5.42, 5.0)),     // left armpit
        const ArtClose(),
        // Left leg (Mintaka side → Rigel)
        ArtMoveTo(_c(5.48, -4.5)),
        ArtLineTo(_c(5.30, -5.5)),
        ArtLineTo(_c(5.24, -8.20)),   // Rigel
        ArtLineTo(_c(5.15, -8.50)),
        ArtLineTo(_c(5.20, -5.2)),
        ArtLineTo(_c(5.38, -4.5)),
        const ArtClose(),
        // Right leg (Alnitak side → Saiph)
        ArtMoveTo(_c(5.80, -4.5)),
        ArtLineTo(_c(5.88, -5.5)),
        ArtLineTo(_c(5.80, -9.67)),   // Saiph
        ArtLineTo(_c(5.72, -9.97)),
        ArtLineTo(_c(5.75, -5.2)),
        ArtLineTo(_c(5.68, -4.5)),
        const ArtClose(),
        // Raised arm (club, from Betelgeuse up and right)
        ArtMoveTo(_c(5.92, 7.41)),    // Betelgeuse
        ArtLineTo(_c(6.05, 9.0)),
        ArtLineTo(_c(6.20, 14.0)),
        ArtLineTo(_c(6.30, 16.0)),
        ArtLineTo(_c(6.15, 16.5)),
        ArtLineTo(_c(6.05, 14.5)),
        ArtLineTo(_c(5.92, 9.5)),
        ArtLineTo(_c(5.85, 7.8)),
        const ArtClose(),
        // Shield arm (from Bellatrix outward)
        ArtMoveTo(_c(5.42, 6.35)),    // Bellatrix
        ArtLineTo(_c(5.20, 7.0)),
        ArtLineTo(_c(5.05, 5.0)),
        ArtLineTo(_c(4.95, 2.0)),
        ArtLineTo(_c(4.90, -1.0)),
        ArtLineTo(_c(5.05, -1.5)),
        ArtLineTo(_c(5.10, 2.0)),
        ArtLineTo(_c(5.18, 5.0)),
        ArtLineTo(_c(5.32, 6.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // URSA MAJOR — The Great Bear
    // Anchor stars: Dubhe (11.06, 61.75), Merak (11.03, 56.38),
    //   Phecda (11.90, 53.69), Megrez (12.26, 57.03), Alioth (12.90, 55.96),
    //   Mizar (13.40, 54.93), Alkaid (13.79, 49.31)
    // Figure: bear body with long tail (the dipper handle)
    // ================================================================
    ConstellationArtData(
      abbreviation: 'UMa',
      segments: [
        // Bear body encompassing the bowl stars
        ArtMoveTo(_c(10.50, 63.0)),   // above Dubhe (head)
        ArtQuadTo(_c(10.20, 60.0), _c(10.30, 57.0)),  // snout
        ArtLineTo(_c(10.50, 55.0)),
        ArtLineTo(_c(10.80, 53.0)),
        ArtLineTo(_c(11.50, 51.5)),   // belly bottom
        ArtLineTo(_c(12.20, 52.0)),
        ArtLineTo(_c(12.50, 53.5)),   // near Phecda
        // Tail starts — follows handle stars
        ArtLineTo(_c(12.90, 54.5)),   // near Alioth
        ArtLineTo(_c(13.40, 53.5)),   // near Mizar
        ArtLineTo(_c(13.79, 49.31)),  // Alkaid (tail tip)
        ArtLineTo(_c(13.95, 49.0)),   // tail tip outer edge
        ArtLineTo(_c(13.55, 55.5)),   // return along outer tail
        ArtLineTo(_c(13.05, 56.5)),
        ArtLineTo(_c(12.50, 58.0)),   // back top
        ArtLineTo(_c(12.26, 58.5)),   // above Megrez
        ArtLineTo(_c(11.40, 62.5)),   // back to top of body
        ArtLineTo(_c(11.06, 63.0)),   // near Dubhe
        const ArtClose(),
        // Front legs
        ArtMoveTo(_c(10.80, 53.0)),
        ArtLineTo(_c(10.60, 50.0)),
        ArtLineTo(_c(10.40, 48.5)),
        ArtLineTo(_c(10.60, 48.0)),
        ArtLineTo(_c(10.80, 50.5)),
        ArtLineTo(_c(11.00, 52.0)),
        const ArtClose(),
        ArtMoveTo(_c(11.20, 52.0)),
        ArtLineTo(_c(11.10, 49.5)),
        ArtLineTo(_c(10.90, 48.0)),
        ArtLineTo(_c(11.10, 47.5)),
        ArtLineTo(_c(11.30, 50.0)),
        ArtLineTo(_c(11.50, 51.5)),
        const ArtClose(),
        // Hind legs
        ArtMoveTo(_c(12.00, 52.5)),
        ArtLineTo(_c(11.90, 49.5)),
        ArtLineTo(_c(11.70, 48.0)),
        ArtLineTo(_c(11.90, 47.5)),
        ArtLineTo(_c(12.10, 50.0)),
        ArtLineTo(_c(12.20, 52.0)),
        const ArtClose(),
        ArtMoveTo(_c(12.40, 53.0)),
        ArtLineTo(_c(12.40, 50.0)),
        ArtLineTo(_c(12.20, 48.5)),
        ArtLineTo(_c(12.40, 48.0)),
        ArtLineTo(_c(12.60, 50.5)),
        ArtLineTo(_c(12.60, 53.0)),
        const ArtClose(),
        // Ear
        ArtMoveTo(_c(10.50, 63.0)),
        ArtLineTo(_c(10.35, 64.0)),
        ArtLineTo(_c(10.55, 63.8)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // CASSIOPEIA — The Queen (seated on throne)
    // Anchor stars: Caph (0.15, 59.15), Schedar (0.68, 56.54),
    //   Navi (0.95, 60.72), Ruchbah (1.43, 60.24), Segin (1.91, 63.67)
    // Figure: seated woman with arms raised, W-shape suggests throne back
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Cas',
      segments: [
        // Torso (seated figure)
        ArtMoveTo(_c(0.68, 58.0)),    // above Schedar (chest)
        ArtLineTo(_c(0.95, 62.0)),    // near Navi (head area)
        ArtLineTo(_c(1.10, 61.5)),
        ArtLineTo(_c(0.85, 58.0)),
        ArtLineTo(_c(0.85, 55.5)),    // waist
        ArtLineTo(_c(0.68, 55.0)),
        const ArtClose(),
        // Head
        ArtMoveTo(_c(0.92, 62.5)),
        ArtQuadTo(_c(1.05, 63.5), _c(0.95, 64.0)),
        ArtQuadTo(_c(0.82, 63.5), _c(0.92, 62.5)),
        const ArtClose(),
        // Left arm (toward Caph, raised)
        ArtMoveTo(_c(0.68, 58.0)),
        ArtLineTo(_c(0.40, 59.0)),
        ArtLineTo(_c(0.15, 59.15)),   // Caph
        ArtLineTo(_c(0.10, 60.0)),
        ArtLineTo(_c(0.35, 59.7)),
        ArtLineTo(_c(0.60, 58.5)),
        const ArtClose(),
        // Right arm (toward Ruchbah/Segin, raised)
        ArtMoveTo(_c(1.10, 61.5)),
        ArtLineTo(_c(1.43, 60.24)),   // Ruchbah
        ArtLineTo(_c(1.91, 63.67)),   // Segin
        ArtLineTo(_c(2.00, 64.0)),
        ArtLineTo(_c(1.50, 61.0)),
        ArtLineTo(_c(1.15, 62.0)),
        const ArtClose(),
        // Throne seat (below Schedar)
        ArtMoveTo(_c(0.50, 55.0)),
        ArtLineTo(_c(0.50, 54.0)),
        ArtLineTo(_c(1.10, 54.0)),
        ArtLineTo(_c(1.10, 55.0)),
        const ArtClose(),
        // Legs
        ArtMoveTo(_c(0.68, 55.0)),
        ArtLineTo(_c(0.55, 53.5)),
        ArtLineTo(_c(0.50, 52.0)),
        ArtLineTo(_c(0.60, 51.8)),
        ArtLineTo(_c(0.68, 53.5)),
        ArtLineTo(_c(0.75, 55.0)),
        const ArtClose(),
        ArtMoveTo(_c(0.85, 55.0)),
        ArtLineTo(_c(0.90, 53.5)),
        ArtLineTo(_c(0.95, 52.0)),
        ArtLineTo(_c(1.05, 51.8)),
        ArtLineTo(_c(1.00, 53.5)),
        ArtLineTo(_c(0.92, 55.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // LEO — The Lion
    // Anchor stars: Regulus (10.14, 11.97), Algieba (10.12, 23.77),
    //   Zosma (10.28, 26.01), Denebola (11.82, 14.57), Chertan (11.24, 20.52)
    // Figure: crouching lion facing right, sickle = mane
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Leo',
      segments: [
        // Head/mane (follows the sickle)
        ArtMoveTo(_c(10.14, 11.97)),  // Regulus
        ArtQuadTo(_c(9.90, 14.0), _c(9.80, 18.0)),
        ArtQuadTo(_c(9.75, 22.0), _c(10.12, 23.77)),  // Algieba
        ArtLineTo(_c(10.28, 26.01)),  // Zosma (top of mane)
        ArtQuadTo(_c(10.50, 27.0), _c(10.70, 26.0)),
        ArtLineTo(_c(10.50, 22.0)),
        ArtQuadTo(_c(10.30, 17.0), _c(10.40, 13.0)),
        ArtLineTo(_c(10.14, 11.97)),  // back to Regulus
        const ArtClose(),
        // Body (from mane to Denebola)
        ArtMoveTo(_c(10.28, 26.01)),  // Zosma (start of back)
        ArtLineTo(_c(10.70, 26.0)),   // inner mane edge
        ArtQuadTo(_c(11.00, 24.0), _c(11.24, 20.52)),  // Chertan (mid-back)
        ArtLineTo(_c(11.82, 14.57)),  // Denebola (tail)
        ArtLineTo(_c(12.00, 14.0)),   // tail tip
        ArtLineTo(_c(11.90, 13.0)),
        ArtLineTo(_c(11.50, 12.5)),   // belly
        ArtLineTo(_c(11.00, 12.0)),
        ArtLineTo(_c(10.50, 11.5)),
        ArtLineTo(_c(10.14, 11.97)),  // Regulus
        const ArtClose(),
        // Front legs
        ArtMoveTo(_c(10.30, 12.5)),
        ArtLineTo(_c(10.20, 9.5)),
        ArtLineTo(_c(10.05, 8.0)),
        ArtLineTo(_c(10.20, 7.8)),
        ArtLineTo(_c(10.35, 9.5)),
        ArtLineTo(_c(10.45, 11.5)),
        const ArtClose(),
        // Hind legs
        ArtMoveTo(_c(11.20, 12.5)),
        ArtLineTo(_c(11.15, 9.5)),
        ArtLineTo(_c(11.00, 8.0)),
        ArtLineTo(_c(11.15, 7.8)),
        ArtLineTo(_c(11.30, 9.5)),
        ArtLineTo(_c(11.40, 12.0)),
        const ArtClose(),
        // Tail tuft
        ArtMoveTo(_c(11.82, 14.57)),
        ArtQuadTo(_c(12.10, 15.5), _c(12.20, 15.0)),
        ArtQuadTo(_c(12.15, 14.0), _c(12.00, 14.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // SCORPIUS — The Scorpion
    // Anchor stars: Dschubba (16.01, -22.62), Antares (16.49, -26.43),
    //   Shaula (17.56, -37.10), Lesath (17.71, -39.03)
    // Figure: scorpion with pincers, body, and curving tail with stinger
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Sco',
      segments: [
        // Left pincer
        ArtMoveTo(_c(15.90, -20.0)),
        ArtQuadTo(_c(15.70, -18.0), _c(15.50, -19.0)),
        ArtQuadTo(_c(15.65, -21.0), _c(15.90, -20.0)),
        const ArtClose(),
        // Right pincer
        ArtMoveTo(_c(16.15, -20.0)),
        ArtQuadTo(_c(16.35, -18.0), _c(16.55, -19.0)),
        ArtQuadTo(_c(16.40, -21.0), _c(16.15, -20.0)),
        const ArtClose(),
        // Head (connects pincers)
        ArtMoveTo(_c(15.90, -21.5)),
        ArtLineTo(_c(16.01, -22.62)),  // Dschubba
        ArtLineTo(_c(16.15, -21.5)),
        ArtLineTo(_c(16.15, -20.0)),
        ArtLineTo(_c(15.90, -20.0)),
        const ArtClose(),
        // Body (Dschubba to Antares to tail)
        ArtMoveTo(_c(15.90, -22.5)),
        ArtLineTo(_c(16.01, -22.62)),  // Dschubba
        ArtLineTo(_c(16.20, -23.0)),
        ArtLineTo(_c(16.49, -26.43)),  // Antares
        ArtLineTo(_c(16.84, -34.29)),  // Tau Sco
        ArtLineTo(_c(17.20, -37.30)),  // Epsilon Sco
        ArtQuadTo(_c(17.40, -38.0), _c(17.56, -37.10)),  // Shaula
        ArtQuadTo(_c(17.65, -38.5), _c(17.71, -39.03)),  // Lesath
        // Stinger curves back
        ArtLineTo(_c(17.80, -38.0)),
        ArtLineTo(_c(17.85, -37.0)),
        // Return path (other side of body)
        ArtQuadTo(_c(17.70, -37.5), _c(17.62, -37.50)),
        ArtLineTo(_c(17.30, -37.60)),
        ArtLineTo(_c(16.95, -34.60)),
        ArtLineTo(_c(16.60, -27.0)),
        ArtLineTo(_c(16.30, -23.5)),
        ArtLineTo(_c(16.10, -22.8)),
        ArtLineTo(_c(15.90, -22.5)),
        const ArtClose(),
        // Legs (3 pairs along body)
        ArtMoveTo(_c(16.30, -24.5)),
        ArtLineTo(_c(16.05, -25.5)),
        ArtLineTo(_c(16.10, -26.0)),
        ArtLineTo(_c(16.35, -25.0)),
        const ArtClose(),
        ArtMoveTo(_c(16.50, -27.5)),
        ArtLineTo(_c(16.25, -28.5)),
        ArtLineTo(_c(16.30, -29.0)),
        ArtLineTo(_c(16.55, -28.0)),
        const ArtClose(),
        ArtMoveTo(_c(16.70, -30.5)),
        ArtLineTo(_c(16.45, -31.5)),
        ArtLineTo(_c(16.50, -32.0)),
        ArtLineTo(_c(16.75, -31.0)),
        const ArtClose(),
        // Right-side legs
        ArtMoveTo(_c(16.40, -24.0)),
        ArtLineTo(_c(16.65, -25.0)),
        ArtLineTo(_c(16.60, -25.5)),
        ArtLineTo(_c(16.35, -24.5)),
        const ArtClose(),
        ArtMoveTo(_c(16.60, -27.0)),
        ArtLineTo(_c(16.85, -28.0)),
        ArtLineTo(_c(16.80, -28.5)),
        ArtLineTo(_c(16.55, -27.5)),
        const ArtClose(),
        ArtMoveTo(_c(16.80, -30.0)),
        ArtLineTo(_c(17.05, -31.0)),
        ArtLineTo(_c(17.00, -31.5)),
        ArtLineTo(_c(16.75, -30.5)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // CYGNUS — The Swan
    // Anchor stars: Deneb (20.69, 45.28), Albireo (19.51, 27.96),
    //   Sadr (20.37, 40.26), Gienah Cygni (19.75, 45.13)
    // Figure: swan with outstretched wings, long neck
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Cyg',
      segments: [
        // Body (elongated along Deneb-Albireo axis)
        ArtMoveTo(_c(20.69, 45.28)),  // Deneb (tail)
        ArtQuadTo(_c(20.55, 43.5), _c(20.37, 40.26)),  // Sadr (body center)
        ArtQuadTo(_c(20.10, 36.0), _c(19.80, 31.0)),
        ArtLineTo(_c(19.51, 27.96)),  // Albireo (head/beak)
        ArtLineTo(_c(19.45, 27.5)),
        ArtQuadTo(_c(19.75, 31.0), _c(20.05, 36.0)),
        ArtQuadTo(_c(20.30, 40.0), _c(20.60, 45.0)),
        const ArtClose(),
        // Left wing (toward Gienah Cygni)
        ArtMoveTo(_c(20.37, 41.0)),   // above Sadr
        ArtQuadTo(_c(20.00, 43.0), _c(19.75, 45.13)),  // Gienah Cygni
        ArtLineTo(_c(19.40, 46.0)),   // wing tip
        ArtLineTo(_c(19.30, 45.5)),
        ArtQuadTo(_c(19.60, 44.0), _c(20.00, 41.5)),
        ArtLineTo(_c(20.25, 40.0)),
        const ArtClose(),
        // Right wing (toward Fawaris / delta Cyg)
        ArtMoveTo(_c(20.50, 41.0)),
        ArtQuadTo(_c(20.80, 37.0), _c(21.22, 30.23)),  // Fawaris
        ArtLineTo(_c(21.50, 28.0)),   // wing tip
        ArtLineTo(_c(21.55, 28.8)),
        ArtQuadTo(_c(21.00, 33.0), _c(20.70, 38.0)),
        ArtLineTo(_c(20.50, 40.0)),
        const ArtClose(),
        // Tail fan (around Deneb)
        ArtMoveTo(_c(20.55, 45.5)),
        ArtQuadTo(_c(20.60, 47.0), _c(20.69, 47.5)),
        ArtQuadTo(_c(20.80, 47.0), _c(20.75, 45.5)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // GEMINI — The Twins
    // Anchor stars: Castor (7.58, 31.89), Pollux (7.76, 28.03),
    //   Alhena (6.63, 16.40), Mebsuta (7.07, 20.57), Wasat (7.19, 16.54)
    // Figure: two standing figures side by side
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Gem',
      segments: [
        // Castor figure (left twin)
        // Head
        ArtMoveTo(_c(7.52, 33.0)),
        ArtQuadTo(_c(7.65, 34.0), _c(7.58, 34.5)),
        ArtQuadTo(_c(7.50, 34.0), _c(7.52, 33.0)),
        const ArtClose(),
        // Torso
        ArtMoveTo(_c(7.50, 32.5)),
        ArtLineTo(_c(7.65, 32.5)),
        ArtLineTo(_c(7.60, 25.0)),
        ArtLineTo(_c(7.07, 20.57)),   // Mebsuta (mid-body)
        ArtLineTo(_c(6.63, 16.40)),   // Alhena (foot)
        ArtLineTo(_c(6.55, 16.2)),
        ArtLineTo(_c(7.00, 20.3)),
        ArtLineTo(_c(7.45, 25.0)),
        ArtLineTo(_c(7.50, 32.5)),
        const ArtClose(),
        // Pollux figure (right twin)
        // Head
        ArtMoveTo(_c(7.70, 29.0)),
        ArtQuadTo(_c(7.82, 30.0), _c(7.76, 30.5)),
        ArtQuadTo(_c(7.68, 30.0), _c(7.70, 29.0)),
        const ArtClose(),
        // Torso
        ArtMoveTo(_c(7.68, 28.5)),
        ArtLineTo(_c(7.83, 28.5)),
        ArtLineTo(_c(7.60, 22.0)),
        ArtLineTo(_c(7.19, 16.54)),   // Wasat (mid-body)
        ArtLineTo(_c(6.73, 12.90)),   // Mekbuda (foot)
        ArtLineTo(_c(6.65, 12.7)),
        ArtLineTo(_c(7.12, 16.3)),
        ArtLineTo(_c(7.45, 22.0)),
        ArtLineTo(_c(7.68, 28.5)),
        const ArtClose(),
        // Joined hands (between twins at shoulder height)
        ArtMoveTo(_c(7.60, 28.0)),
        ArtLineTo(_c(7.68, 28.0)),
        ArtLineTo(_c(7.68, 28.5)),
        ArtLineTo(_c(7.60, 28.5)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // SAGITTARIUS — The Archer (Teapot)
    // Anchor stars: Kaus Australis (18.40, -34.38), Kaus Media (18.35, -29.83),
    //   Kaus Borealis (18.23, -25.42), Nunki (18.92, -26.30), Ascella (19.04, -29.88)
    // Figure: centaur archer drawing a bow
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Sgr',
      segments: [
        // Human torso (upper body, above Kaus Borealis)
        ArtMoveTo(_c(18.35, -24.0)),
        ArtLineTo(_c(18.50, -23.0)),  // chest
        ArtLineTo(_c(18.45, -21.0)),  // neck
        // Head
        ArtQuadTo(_c(18.50, -19.5), _c(18.40, -19.0)),
        ArtQuadTo(_c(18.30, -19.5), _c(18.35, -21.0)),
        // Shoulders back down
        ArtLineTo(_c(18.20, -23.0)),
        ArtLineTo(_c(18.23, -25.42)),  // Kaus Borealis
        const ArtClose(),
        // Bow arm (extended left)
        ArtMoveTo(_c(18.20, -23.0)),
        ArtLineTo(_c(17.80, -22.0)),
        ArtLineTo(_c(17.50, -21.0)),   // bow grip
        ArtLineTo(_c(17.45, -21.5)),
        ArtLineTo(_c(17.75, -22.5)),
        ArtLineTo(_c(18.15, -23.5)),
        const ArtClose(),
        // Bow arc
        ArtMoveTo(_c(17.50, -21.0)),
        ArtQuadTo(_c(17.30, -24.0), _c(17.50, -27.0)),
        ArtLineTo(_c(17.55, -27.0)),
        ArtQuadTo(_c(17.35, -24.0), _c(17.55, -21.0)),
        const ArtClose(),
        // Horse body (lower, following teapot outline)
        ArtMoveTo(_c(18.23, -25.42)),  // Kaus Borealis
        ArtLineTo(_c(18.35, -29.83)),  // Kaus Media
        ArtLineTo(_c(18.40, -34.38)),  // Kaus Australis
        ArtLineTo(_c(19.04, -29.88)),  // Ascella
        ArtLineTo(_c(18.92, -26.30)),  // Nunki
        ArtLineTo(_c(18.70, -25.5)),
        const ArtClose(),
        // Hind legs
        ArtMoveTo(_c(18.90, -30.0)),
        ArtLineTo(_c(19.10, -33.0)),
        ArtLineTo(_c(19.20, -35.0)),
        ArtLineTo(_c(19.30, -35.2)),
        ArtLineTo(_c(19.20, -33.0)),
        ArtLineTo(_c(19.00, -30.5)),
        const ArtClose(),
        // Front legs
        ArtMoveTo(_c(18.40, -34.38)),
        ArtLineTo(_c(18.30, -36.5)),
        ArtLineTo(_c(18.20, -38.0)),
        ArtLineTo(_c(18.30, -38.2)),
        ArtLineTo(_c(18.40, -36.5)),
        ArtLineTo(_c(18.50, -34.5)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // TAURUS — The Bull
    // Anchor stars: Aldebaran (4.60, 16.51), Elnath (5.44, 28.61),
    //   Zeta Tau (5.63, 21.14)
    // Figure: bull head and shoulders with horns
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Tau',
      segments: [
        // Bull face (V-shape of Hyades)
        ArtMoveTo(_c(4.00, 12.5)),
        ArtQuadTo(_c(4.20, 14.0), _c(4.60, 16.51)),  // Aldebaran (eye)
        ArtLineTo(_c(4.80, 17.0)),
        ArtLineTo(_c(4.60, 14.0)),
        ArtLineTo(_c(4.33, 15.63)),
        ArtLineTo(_c(4.00, 12.5)),
        const ArtClose(),
        // Broad head
        ArtMoveTo(_c(4.00, 12.0)),
        ArtLineTo(_c(4.80, 17.5)),
        ArtLineTo(_c(5.00, 19.0)),
        ArtLineTo(_c(4.80, 19.5)),
        ArtLineTo(_c(3.80, 13.0)),
        const ArtClose(),
        // Left horn (to Elnath)
        ArtMoveTo(_c(4.80, 19.5)),
        ArtQuadTo(_c(5.10, 24.0), _c(5.44, 28.61)),   // Elnath
        ArtLineTo(_c(5.50, 29.0)),
        ArtQuadTo(_c(5.15, 24.5), _c(4.90, 19.5)),
        const ArtClose(),
        // Right horn (to Zeta Tau)
        ArtMoveTo(_c(5.00, 19.0)),
        ArtQuadTo(_c(5.30, 20.0), _c(5.63, 21.14)),   // Zeta Tau
        ArtLineTo(_c(5.70, 21.5)),
        ArtQuadTo(_c(5.35, 20.5), _c(5.10, 19.0)),
        const ArtClose(),
        // Neck/shoulder (trails off to the right)
        ArtMoveTo(_c(3.80, 13.0)),
        ArtLineTo(_c(3.50, 11.0)),
        ArtQuadTo(_c(3.40, 9.0), _c(3.50, 8.0)),
        ArtLineTo(_c(3.70, 8.0)),
        ArtQuadTo(_c(3.60, 9.5), _c(3.70, 11.5)),
        ArtLineTo(_c(4.00, 12.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // CANIS MAJOR — The Great Dog
    // Anchor stars: Sirius (6.75, -16.72), Mirzam (6.38, -17.96),
    //   Wezen (7.14, -26.39), Adhara (6.98, -28.97), Furud (6.61, -32.51)
    // Figure: sitting dog facing left
    // ================================================================
    ConstellationArtData(
      abbreviation: 'CMa',
      segments: [
        // Head (around Sirius)
        ArtMoveTo(_c(6.65, -14.5)),
        ArtQuadTo(_c(6.55, -13.5), _c(6.65, -12.5)),  // top of head
        ArtQuadTo(_c(6.85, -13.0), _c(6.90, -14.5)),
        ArtLineTo(_c(6.85, -16.0)),
        ArtLineTo(_c(6.65, -16.0)),
        const ArtClose(),
        // Ear
        ArtMoveTo(_c(6.60, -13.0)),
        ArtLineTo(_c(6.50, -11.5)),
        ArtLineTo(_c(6.55, -12.0)),
        const ArtClose(),
        // Body
        ArtMoveTo(_c(6.65, -16.0)),
        ArtLineTo(_c(6.38, -17.96)),   // Mirzam (chest)
        ArtLineTo(_c(6.40, -21.0)),
        ArtLineTo(_c(6.61, -25.0)),
        ArtLineTo(_c(6.98, -28.97)),   // Adhara
        ArtLineTo(_c(7.14, -26.39)),   // Wezen (back)
        ArtLineTo(_c(7.00, -22.0)),
        ArtLineTo(_c(6.85, -18.0)),
        ArtLineTo(_c(6.85, -16.0)),
        const ArtClose(),
        // Front legs
        ArtMoveTo(_c(6.40, -21.0)),
        ArtLineTo(_c(6.25, -24.0)),
        ArtLineTo(_c(6.20, -26.0)),
        ArtLineTo(_c(6.30, -26.2)),
        ArtLineTo(_c(6.35, -24.0)),
        ArtLineTo(_c(6.50, -21.5)),
        const ArtClose(),
        // Hind leg
        ArtMoveTo(_c(6.98, -28.97)),
        ArtLineTo(_c(6.80, -31.0)),
        ArtLineTo(_c(6.61, -32.51)),   // Furud
        ArtLineTo(_c(6.55, -32.8)),
        ArtLineTo(_c(6.75, -31.0)),
        ArtLineTo(_c(6.90, -29.5)),
        const ArtClose(),
        // Tail (upward from Wezen)
        ArtMoveTo(_c(7.14, -26.39)),
        ArtQuadTo(_c(7.30, -24.0), _c(7.40, -22.5)),
        ArtLineTo(_c(7.35, -22.0)),
        ArtQuadTo(_c(7.25, -23.5), _c(7.10, -25.5)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // LYRA — The Lyre (harp)
    // Anchor stars: Vega (18.62, 38.78), Sheliak (18.83, 33.36),
    //   Sulafat (18.91, 33.36)
    // Figure: small harp/lyre shape
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Lyr',
      segments: [
        // Frame of the lyre (trapezoidal)
        ArtMoveTo(_c(18.62, 38.78)),   // Vega (top)
        ArtLineTo(_c(18.50, 37.5)),
        ArtLineTo(_c(18.45, 35.0)),
        ArtQuadTo(_c(18.50, 32.0), _c(18.83, 33.36)),  // Sheliak
        ArtLineTo(_c(18.91, 33.36)),   // Sulafat
        ArtQuadTo(_c(19.10, 32.0), _c(19.10, 35.0)),
        ArtLineTo(_c(19.00, 37.5)),
        ArtLineTo(_c(18.62, 38.78)),   // back to Vega
        const ArtClose(),
        // Left string
        ArtMoveTo(_c(18.55, 37.0)),
        ArtLineTo(_c(18.60, 33.5)),
        ArtLineTo(_c(18.62, 33.5)),
        ArtLineTo(_c(18.57, 37.0)),
        const ArtClose(),
        // Center string
        ArtMoveTo(_c(18.75, 37.5)),
        ArtLineTo(_c(18.80, 33.0)),
        ArtLineTo(_c(18.82, 33.0)),
        ArtLineTo(_c(18.77, 37.5)),
        const ArtClose(),
        // Right string
        ArtMoveTo(_c(18.95, 37.0)),
        ArtLineTo(_c(18.93, 33.5)),
        ArtLineTo(_c(18.95, 33.5)),
        ArtLineTo(_c(18.97, 37.0)),
        const ArtClose(),
        // Crossbar
        ArtMoveTo(_c(18.50, 35.5)),
        ArtLineTo(_c(19.05, 35.5)),
        ArtLineTo(_c(19.05, 35.8)),
        ArtLineTo(_c(18.50, 35.8)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // AQUILA — The Eagle
    // Anchor stars: Altair (19.85, 8.87), Tarazed (19.77, 10.61),
    //   Alshain (19.92, 6.41)
    // Figure: eagle with outstretched wings
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Aql',
      segments: [
        // Body
        ArtMoveTo(_c(19.77, 10.61)),   // Tarazed (upper body)
        ArtLineTo(_c(19.85, 8.87)),    // Altair (center)
        ArtLineTo(_c(19.92, 6.41)),    // Alshain (lower body)
        ArtLineTo(_c(20.00, 5.0)),     // tail
        ArtLineTo(_c(19.85, 5.0)),
        ArtLineTo(_c(19.70, 6.5)),
        ArtLineTo(_c(19.65, 8.5)),
        ArtLineTo(_c(19.70, 10.5)),
        const ArtClose(),
        // Head
        ArtMoveTo(_c(19.77, 10.61)),
        ArtQuadTo(_c(19.82, 12.0), _c(19.80, 12.5)),
        ArtQuadTo(_c(19.72, 12.0), _c(19.70, 10.5)),
        const ArtClose(),
        // Left wing (toward Delta Aql)
        ArtMoveTo(_c(19.70, 9.5)),
        ArtQuadTo(_c(19.40, 11.0), _c(19.10, 13.86)),  // Delta Aql
        ArtLineTo(_c(18.80, 15.0)),
        ArtLineTo(_c(18.75, 14.5)),
        ArtQuadTo(_c(19.05, 13.0), _c(19.55, 9.5)),
        const ArtClose(),
        // Right wing (toward Theta Aql)
        ArtMoveTo(_c(20.00, 7.0)),
        ArtQuadTo(_c(20.10, 4.0), _c(20.19, -0.82)),   // Theta Aql
        ArtLineTo(_c(20.40, -2.0)),
        ArtLineTo(_c(20.45, -1.5)),
        ArtQuadTo(_c(20.25, 2.0), _c(20.10, 6.5)),
        const ArtClose(),
        // Tail feathers
        ArtMoveTo(_c(19.90, 5.0)),
        ArtLineTo(_c(20.05, 3.5)),
        ArtLineTo(_c(20.10, 4.0)),
        ArtLineTo(_c(19.95, 5.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // PEGASUS — The Winged Horse (Great Square + neck/head)
    // Anchor stars: Alpheratz (0.14, 29.09), Scheat (23.06, 28.08),
    //   Markab (23.08, 15.21), Algenib (0.22, 15.18), Enif (21.74, 9.87)
    // Figure: horse body from the Great Square with neck to Enif
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Peg',
      segments: [
        // Body (the Great Square)
        ArtMoveTo(_c(0.14, 29.09)),    // Alpheratz
        ArtLineTo(_c(23.06, 28.08)),   // Scheat
        ArtLineTo(_c(23.08, 15.21)),   // Markab
        ArtLineTo(_c(0.22, 15.18)),    // Algenib
        const ArtClose(),
        // Neck (from Scheat toward Enif)
        ArtMoveTo(_c(23.06, 28.08)),   // Scheat
        ArtLineTo(_c(22.80, 27.0)),
        ArtLineTo(_c(22.12, 25.35)),   // Matar
        ArtQuadTo(_c(21.90, 20.0), _c(21.74, 9.87)),  // Enif (head)
        // Head
        ArtQuadTo(_c(21.60, 8.0), _c(21.50, 9.5)),
        ArtQuadTo(_c(21.65, 12.0), _c(21.74, 12.0)),
        // Return along neck
        ArtQuadTo(_c(21.85, 19.0), _c(22.00, 25.0)),
        ArtLineTo(_c(22.70, 27.0)),
        ArtLineTo(_c(22.95, 28.0)),
        const ArtClose(),
        // Wing (above square, from Scheat-Alpheratz edge)
        ArtMoveTo(_c(23.50, 28.5)),
        ArtQuadTo(_c(23.80, 33.0), _c(0.00, 35.0)),
        ArtQuadTo(_c(0.10, 33.0), _c(23.60, 29.0)),
        const ArtClose(),
        // Front legs (below Markab)
        ArtMoveTo(_c(23.08, 15.21)),
        ArtLineTo(_c(23.15, 12.0)),
        ArtLineTo(_c(23.20, 10.0)),
        ArtLineTo(_c(23.30, 10.0)),
        ArtLineTo(_c(23.25, 12.0)),
        ArtLineTo(_c(23.20, 15.0)),
        const ArtClose(),
        // Hind legs (below Algenib)
        ArtMoveTo(_c(0.22, 15.18)),
        ArtLineTo(_c(0.28, 12.0)),
        ArtLineTo(_c(0.32, 10.0)),
        ArtLineTo(_c(0.42, 10.0)),
        ArtLineTo(_c(0.38, 12.0)),
        ArtLineTo(_c(0.32, 15.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // ANDROMEDA — The Chained Princess
    // Anchor stars: Alpheratz (0.14, 29.09), Mirach (1.16, 35.62),
    //   Almach (2.07, 42.33)
    // Figure: woman with arms stretched out (chained)
    // ================================================================
    ConstellationArtData(
      abbreviation: 'And',
      segments: [
        // Body (along the main line of stars)
        ArtMoveTo(_c(0.14, 30.5)),     // above Alpheratz
        ArtLineTo(_c(0.14, 28.0)),     // below
        ArtLineTo(_c(1.16, 34.5)),     // below Mirach
        ArtLineTo(_c(2.07, 41.0)),     // below Almach
        ArtLineTo(_c(2.07, 43.5)),     // above Almach
        ArtLineTo(_c(1.16, 36.8)),     // above Mirach
        const ArtClose(),
        // Head (near Almach)
        ArtMoveTo(_c(2.00, 43.5)),
        ArtQuadTo(_c(2.15, 44.5), _c(2.07, 45.0)),
        ArtQuadTo(_c(1.95, 44.5), _c(2.00, 43.5)),
        const ArtClose(),
        // Left arm (from near Mirach, stretched out)
        ArtMoveTo(_c(1.05, 36.5)),
        ArtLineTo(_c(0.80, 38.0)),
        ArtLineTo(_c(0.50, 39.5)),
        ArtLineTo(_c(0.45, 39.0)),
        ArtLineTo(_c(0.75, 37.5)),
        ArtLineTo(_c(1.00, 35.8)),
        const ArtClose(),
        // Right arm (from near Almach, stretched out)
        ArtMoveTo(_c(2.00, 43.0)),
        ArtLineTo(_c(2.30, 44.5)),
        ArtLineTo(_c(2.60, 45.5)),
        ArtLineTo(_c(2.65, 45.0)),
        ArtLineTo(_c(2.35, 44.0)),
        ArtLineTo(_c(2.07, 42.5)),
        const ArtClose(),
        // Skirt/legs (flowing down from Alpheratz area)
        ArtMoveTo(_c(0.14, 28.0)),
        ArtLineTo(_c(0.00, 26.0)),
        ArtLineTo(_c(-0.05, 24.5)),
        ArtLineTo(_c(0.05, 24.5)),
        ArtLineTo(_c(0.14, 26.5)),
        ArtLineTo(_c(0.25, 24.5)),
        ArtLineTo(_c(0.35, 24.5)),
        ArtLineTo(_c(0.30, 26.0)),
        ArtLineTo(_c(0.14, 28.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // PERSEUS — The Hero
    // Anchor stars: Mirfak (3.41, 49.86), Algol (3.14, 40.96),
    //   Gamma Per (3.72, 47.79)
    // Figure: man holding sword and head of Medusa (Algol)
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Per',
      segments: [
        // Torso
        ArtMoveTo(_c(3.30, 50.0)),
        ArtLineTo(_c(3.50, 50.0)),     // shoulders
        ArtLineTo(_c(3.72, 47.79)),    // Gamma Per (arm)
        ArtLineTo(_c(3.55, 46.0)),
        ArtLineTo(_c(3.45, 43.0)),
        ArtLineTo(_c(3.35, 43.0)),
        ArtLineTo(_c(3.25, 46.0)),
        ArtLineTo(_c(3.08, 47.5)),     // left arm
        ArtLineTo(_c(3.30, 50.0)),
        const ArtClose(),
        // Head
        ArtMoveTo(_c(3.35, 50.5)),
        ArtQuadTo(_c(3.48, 51.5), _c(3.41, 52.0)),
        ArtQuadTo(_c(3.32, 51.5), _c(3.35, 50.5)),
        const ArtClose(),
        // Arm holding Medusa head (toward Algol)
        ArtMoveTo(_c(3.25, 46.0)),
        ArtLineTo(_c(3.14, 43.0)),
        ArtLineTo(_c(3.14, 40.96)),    // Algol (Medusa's head)
        ArtLineTo(_c(3.05, 40.5)),
        ArtLineTo(_c(3.05, 43.0)),
        ArtLineTo(_c(3.15, 46.0)),
        const ArtClose(),
        // Medusa head (circle around Algol)
        ArtMoveTo(_c(3.05, 41.0)),
        ArtQuadTo(_c(2.95, 40.0), _c(3.14, 39.5)),
        ArtQuadTo(_c(3.30, 40.0), _c(3.20, 41.0)),
        ArtQuadTo(_c(3.15, 41.5), _c(3.05, 41.0)),
        const ArtClose(),
        // Sword arm (from Gamma Per outward)
        ArtMoveTo(_c(3.72, 47.79)),
        ArtLineTo(_c(3.90, 48.5)),
        ArtLineTo(_c(4.10, 49.0)),     // sword tip
        ArtLineTo(_c(4.12, 48.5)),
        ArtLineTo(_c(3.92, 48.0)),
        ArtLineTo(_c(3.75, 47.5)),
        const ArtClose(),
        // Legs
        ArtMoveTo(_c(3.35, 43.0)),
        ArtLineTo(_c(3.25, 40.0)),
        ArtLineTo(_c(3.15, 38.0)),
        ArtLineTo(_c(3.25, 37.8)),
        ArtLineTo(_c(3.35, 40.0)),
        ArtLineTo(_c(3.45, 43.0)),
        const ArtClose(),
        ArtMoveTo(_c(3.45, 43.0)),
        ArtLineTo(_c(3.55, 40.0)),
        ArtLineTo(_c(3.65, 38.0)),
        ArtLineTo(_c(3.75, 37.8)),
        ArtLineTo(_c(3.65, 40.0)),
        ArtLineTo(_c(3.55, 43.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // BOOTES — The Herdsman (kite shape)
    // Anchor stars: Arcturus (14.26, 19.18), Izar (14.53, 30.37),
    //   Nekkar (15.03, 40.39)
    // Figure: man with staff, kite-shaped body
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Boo',
      segments: [
        // Body (kite shape)
        ArtMoveTo(_c(14.26, 19.18)),   // Arcturus (base)
        ArtLineTo(_c(13.91, 18.40)),   // Eta Boo (left)
        ArtLineTo(_c(14.53, 30.37)),   // Izar (left-top)
        ArtLineTo(_c(15.03, 40.39)),   // Nekkar (top/head)
        ArtLineTo(_c(14.75, 27.07)),   // Delta Boo (right-top)
        ArtLineTo(_c(14.26, 19.18)),   // back to Arcturus
        const ArtClose(),
        // Head
        ArtMoveTo(_c(14.95, 40.5)),
        ArtQuadTo(_c(15.10, 42.0), _c(15.03, 42.5)),
        ArtQuadTo(_c(14.95, 42.0), _c(14.95, 40.5)),
        const ArtClose(),
        // Staff (from left hand downward)
        ArtMoveTo(_c(13.85, 18.0)),
        ArtLineTo(_c(13.70, 15.0)),
        ArtLineTo(_c(13.60, 12.0)),
        ArtLineTo(_c(13.65, 11.8)),
        ArtLineTo(_c(13.75, 15.0)),
        ArtLineTo(_c(13.91, 18.0)),
        const ArtClose(),
        // Left arm
        ArtMoveTo(_c(14.10, 27.0)),
        ArtLineTo(_c(13.70, 28.0)),
        ArtLineTo(_c(13.50, 28.0)),
        ArtLineTo(_c(13.65, 27.5)),
        ArtLineTo(_c(14.00, 26.5)),
        const ArtClose(),
        // Right arm
        ArtMoveTo(_c(14.70, 28.0)),
        ArtLineTo(_c(15.10, 29.0)),
        ArtLineTo(_c(15.30, 29.0)),
        ArtLineTo(_c(15.15, 28.5)),
        ArtLineTo(_c(14.80, 27.5)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // VIRGO — The Maiden
    // Anchor stars: Spica (13.42, -11.16), Porrima (12.69, -1.45),
    //   Vindemiatrix (12.93, 3.40)
    // Figure: woman holding a sheaf of wheat (Spica)
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Vir',
      segments: [
        // Body
        ArtMoveTo(_c(12.80, 5.0)),     // head area
        ArtLineTo(_c(12.93, 3.40)),    // Vindemiatrix (shoulder)
        ArtLineTo(_c(12.69, -1.45)),   // Porrima (waist)
        ArtLineTo(_c(13.00, -5.0)),    // hip
        ArtLineTo(_c(12.50, -5.0)),    // other hip
        ArtLineTo(_c(12.55, -1.0)),
        ArtLineTo(_c(12.70, 3.0)),
        const ArtClose(),
        // Head
        ArtMoveTo(_c(12.75, 5.5)),
        ArtQuadTo(_c(12.90, 6.5), _c(12.80, 7.0)),
        ArtQuadTo(_c(12.70, 6.5), _c(12.75, 5.5)),
        const ArtClose(),
        // Arm holding wheat (toward Spica)
        ArtMoveTo(_c(12.80, 0.0)),
        ArtLineTo(_c(13.10, -4.0)),
        ArtLineTo(_c(13.42, -11.16)),  // Spica (wheat)
        ArtLineTo(_c(13.50, -11.50)),
        ArtLineTo(_c(13.52, -11.0)),
        ArtLineTo(_c(13.20, -4.0)),
        ArtLineTo(_c(12.90, 0.0)),
        const ArtClose(),
        // Wheat sheaf (rays around Spica)
        ArtMoveTo(_c(13.42, -11.16)),
        ArtLineTo(_c(13.30, -12.5)),
        ArtLineTo(_c(13.35, -12.8)),
        ArtLineTo(_c(13.42, -11.16)),
        ArtLineTo(_c(13.55, -12.5)),
        ArtLineTo(_c(13.50, -12.8)),
        ArtLineTo(_c(13.42, -11.16)),
        const ArtClose(),
        // Flowing skirt (legs)
        ArtMoveTo(_c(12.50, -5.0)),
        ArtLineTo(_c(12.30, -8.0)),
        ArtLineTo(_c(12.20, -10.0)),
        ArtLineTo(_c(12.30, -10.2)),
        ArtLineTo(_c(12.45, -8.0)),
        ArtLineTo(_c(12.65, -5.0)),
        const ArtClose(),
        ArtMoveTo(_c(13.00, -5.0)),
        ArtLineTo(_c(13.10, -8.0)),
        ArtLineTo(_c(13.20, -10.0)),
        ArtLineTo(_c(13.10, -10.2)),
        ArtLineTo(_c(13.00, -8.0)),
        ArtLineTo(_c(12.85, -5.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // URSA MINOR — The Little Bear
    // Anchor stars: Polaris (2.53, 89.26), Kochab (14.85, 74.16),
    //   Pherkad (15.35, 71.83)
    // Figure: small bear with tail at Polaris
    // ================================================================
    ConstellationArtData(
      abbreviation: 'UMi',
      segments: [
        // Body (bowl of Little Dipper)
        ArtMoveTo(_c(14.50, 75.0)),
        ArtLineTo(_c(14.85, 74.16)),   // Kochab
        ArtLineTo(_c(15.35, 71.83)),   // Pherkad
        ArtLineTo(_c(16.29, 75.76)),   // Epsilon UMi
        ArtLineTo(_c(15.73, 77.79)),   // Zeta UMi
        ArtLineTo(_c(14.85, 75.5)),
        const ArtClose(),
        // Tail (handle to Polaris)
        ArtMoveTo(_c(16.29, 76.5)),
        ArtLineTo(_c(17.54, 86.59)),   // Yildun
        ArtQuadTo(_c(5.0, 88.0), _c(2.53, 89.26)),  // Polaris
        ArtQuadTo(_c(5.0, 89.0), _c(17.54, 87.5)),
        ArtLineTo(_c(16.29, 77.0)),
        const ArtClose(),
        // Ear
        ArtMoveTo(_c(14.50, 75.0)),
        ArtLineTo(_c(14.30, 76.0)),
        ArtLineTo(_c(14.50, 75.8)),
        const ArtClose(),
        // Front legs
        ArtMoveTo(_c(14.85, 74.16)),
        ArtLineTo(_c(14.70, 72.5)),
        ArtLineTo(_c(14.60, 71.5)),
        ArtLineTo(_c(14.75, 71.3)),
        ArtLineTo(_c(14.85, 72.5)),
        ArtLineTo(_c(15.00, 73.5)),
        const ArtClose(),
        // Hind legs
        ArtMoveTo(_c(15.80, 72.5)),
        ArtLineTo(_c(15.90, 71.0)),
        ArtLineTo(_c(16.00, 70.0)),
        ArtLineTo(_c(16.15, 69.8)),
        ArtLineTo(_c(16.05, 71.0)),
        ArtLineTo(_c(15.95, 72.5)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // DRACO — The Dragon
    // Anchor stars: Eltanin (17.51, 52.30), Rastaban (17.51, 51.49),
    //   Thuban (14.07, 64.38)
    // Figure: serpentine dragon winding between the bears
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Dra',
      segments: [
        // Head (angular, around Eltanin/Rastaban)
        ArtMoveTo(_c(17.35, 53.5)),
        ArtLineTo(_c(17.51, 52.30)),   // Eltanin
        ArtLineTo(_c(17.70, 52.0)),
        ArtLineTo(_c(17.65, 51.0)),
        ArtLineTo(_c(17.51, 51.49)),   // Rastaban
        ArtLineTo(_c(17.30, 52.0)),
        const ArtClose(),
        // Body (sinuous path through constellation)
        ArtMoveTo(_c(17.35, 53.5)),
        ArtQuadTo(_c(17.20, 54.5), _c(17.15, 54.47)),
        ArtQuadTo(_c(16.80, 58.0), _c(16.40, 61.51)),
        ArtQuadTo(_c(15.80, 59.0), _c(15.42, 58.97)),
        ArtQuadTo(_c(14.50, 62.0), _c(14.07, 64.38)),  // Thuban
        ArtQuadTo(_c(13.30, 67.0), _c(12.56, 69.79)),
        ArtQuadTo(_c(12.00, 69.5), _c(11.52, 69.33)),  // Alpha Dra
        // Tail tip
        ArtLineTo(_c(11.40, 69.8)),
        // Return path (other side of body, slightly offset)
        ArtQuadTo(_c(12.10, 70.5), _c(12.70, 70.5)),
        ArtQuadTo(_c(13.40, 68.0), _c(14.20, 65.0)),
        ArtQuadTo(_c(14.60, 63.0), _c(15.50, 59.8)),
        ArtQuadTo(_c(16.00, 60.5), _c(16.50, 62.5)),
        ArtQuadTo(_c(16.90, 59.0), _c(17.25, 55.5)),
        ArtQuadTo(_c(17.30, 54.0), _c(17.45, 53.5)),
        ArtLineTo(_c(17.35, 53.5)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // HERCULES — The Strongman
    // Anchor stars: Kornephoros (16.15, 14.03), Rasalgethi (17.39, 37.15)
    // Keystone: Zeta (16.50, 21.49), Eta (16.36, 19.15),
    //   Pi (17.25, 24.84), Epsilon (16.69, 31.60)
    // Figure: man with club, upside-down in sky
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Her',
      segments: [
        // Keystone body (torso)
        ArtMoveTo(_c(16.50, 21.49)),   // Zeta Her
        ArtLineTo(_c(16.36, 19.15)),   // Eta Her
        ArtLineTo(_c(17.25, 24.84)),   // Pi Her
        ArtLineTo(_c(16.69, 31.60)),   // Epsilon Her
        const ArtClose(),
        // Head (below keystone since Hercules is upside-down)
        ArtMoveTo(_c(16.10, 14.5)),
        ArtQuadTo(_c(16.25, 13.0), _c(16.15, 12.5)),
        ArtQuadTo(_c(16.05, 13.0), _c(16.10, 14.5)),
        const ArtClose(),
        // Leg down to Kornephoros
        ArtMoveTo(_c(16.50, 21.49)),
        ArtLineTo(_c(16.35, 18.0)),
        ArtLineTo(_c(16.15, 14.03)),   // Kornephoros
        ArtLineTo(_c(16.05, 14.0)),
        ArtLineTo(_c(16.25, 18.0)),
        ArtLineTo(_c(16.36, 19.15)),
        const ArtClose(),
        // Other leg (from Eta Her)
        ArtMoveTo(_c(16.36, 19.15)),
        ArtLineTo(_c(17.24, 14.39)),   // Sarin
        ArtLineTo(_c(17.30, 14.5)),
        ArtLineTo(_c(16.50, 19.5)),
        const ArtClose(),
        // Arm to Rasalgethi
        ArtMoveTo(_c(16.69, 31.60)),
        ArtLineTo(_c(17.00, 34.0)),
        ArtLineTo(_c(17.39, 37.15)),   // Rasalgethi
        ArtLineTo(_c(17.45, 37.5)),
        ArtLineTo(_c(17.05, 34.5)),
        ArtLineTo(_c(16.75, 31.8)),
        const ArtClose(),
        // Arm from Pi Her (with club)
        ArtMoveTo(_c(17.25, 24.84)),
        ArtLineTo(_c(17.58, 12.56)),   // toward Rasalhague
        ArtLineTo(_c(17.65, 12.5)),
        ArtLineTo(_c(17.35, 25.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // AURIGA — The Charioteer
    // Anchor stars: Capella (5.28, 46.00), Menkalinan (6.00, 44.95),
    //   Elnath (5.44, 28.61), Almaaz (5.11, 41.23)
    // Figure: pentagon with charioteer holding reins
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Aur',
      segments: [
        // Pentagon body
        ArtMoveTo(_c(5.28, 46.00)),    // Capella
        ArtLineTo(_c(6.00, 44.95)),    // Menkalinan
        ArtLineTo(_c(5.99, 37.21)),    // Theta Aur
        ArtLineTo(_c(5.44, 28.61)),    // Elnath
        ArtLineTo(_c(5.03, 33.17)),    // Iota Aur
        ArtLineTo(_c(5.11, 41.23)),    // Almaaz
        const ArtClose(),
        // Head (above Capella)
        ArtMoveTo(_c(5.22, 47.0)),
        ArtQuadTo(_c(5.35, 48.5), _c(5.28, 49.0)),
        ArtQuadTo(_c(5.18, 48.5), _c(5.22, 47.0)),
        const ArtClose(),
        // Goat kids (small figure near Almaaz — the charioteer traditionally holds baby goats)
        ArtMoveTo(_c(5.00, 42.0)),
        ArtQuadTo(_c(4.85, 42.5), _c(4.85, 43.0)),
        ArtQuadTo(_c(4.95, 43.5), _c(5.05, 43.0)),
        ArtQuadTo(_c(5.05, 42.5), _c(5.00, 42.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // CRUX — The Southern Cross
    // Anchor stars: Acrux (12.44, -63.10), Gacrux (12.52, -57.11),
    //   Mimosa (12.80, -59.69), Imai (12.25, -58.75)
    // Figure: ornate cross
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Cru',
      segments: [
        // Vertical beam
        ArtMoveTo(_c(12.44, -63.10)),  // Acrux (bottom)
        ArtLineTo(_c(12.38, -62.5)),
        ArtLineTo(_c(12.46, -60.5)),   // center
        ArtLineTo(_c(12.52, -57.11)),  // Gacrux (top)
        ArtLineTo(_c(12.58, -57.5)),
        ArtLineTo(_c(12.52, -60.5)),   // center
        ArtLineTo(_c(12.50, -62.5)),
        const ArtClose(),
        // Horizontal beam
        ArtMoveTo(_c(12.25, -58.75)),  // Imai (left)
        ArtLineTo(_c(12.30, -59.3)),
        ArtLineTo(_c(12.46, -59.8)),   // center
        ArtLineTo(_c(12.80, -59.69)),  // Mimosa (right)
        ArtLineTo(_c(12.75, -60.2)),
        ArtLineTo(_c(12.52, -60.2)),   // center
        ArtLineTo(_c(12.30, -59.8)),
        const ArtClose(),
        // Flared tips (top)
        ArtMoveTo(_c(12.45, -57.3)),
        ArtLineTo(_c(12.40, -56.5)),
        ArtLineTo(_c(12.52, -57.11)),
        ArtLineTo(_c(12.65, -56.5)),
        ArtLineTo(_c(12.58, -57.3)),
        const ArtClose(),
        // Flared tips (bottom)
        ArtMoveTo(_c(12.38, -62.8)),
        ArtLineTo(_c(12.35, -63.5)),
        ArtLineTo(_c(12.44, -63.10)),
        ArtLineTo(_c(12.55, -63.5)),
        ArtLineTo(_c(12.50, -62.8)),
        const ArtClose(),
        // Flared tips (left)
        ArtMoveTo(_c(12.28, -59.0)),
        ArtLineTo(_c(12.15, -58.5)),
        ArtLineTo(_c(12.25, -58.75)),
        ArtLineTo(_c(12.15, -59.3)),
        ArtLineTo(_c(12.28, -59.6)),
        const ArtClose(),
        // Flared tips (right)
        ArtMoveTo(_c(12.77, -59.4)),
        ArtLineTo(_c(12.90, -59.0)),
        ArtLineTo(_c(12.80, -59.69)),
        ArtLineTo(_c(12.90, -60.2)),
        ArtLineTo(_c(12.77, -60.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // CEPHEUS — The King
    // Anchor stars: Alderamin (21.31, 62.59), Errai (23.66, 77.63)
    // Figure: house/pentagon shaped king on throne
    // ================================================================
    ConstellationArtData(
      abbreviation: 'Cep',
      segments: [
        // Body (pentagon of main stars)
        ArtMoveTo(_c(21.31, 62.59)),   // Alderamin
        ArtLineTo(_c(22.49, 58.20)),   // Zeta Cep
        ArtLineTo(_c(22.83, 66.20)),   // Delta Cep
        ArtLineTo(_c(23.19, 75.39)),   // Iota Cep
        ArtLineTo(_c(23.66, 77.63)),   // Errai
        const ArtClose(),
        // Crown (above Errai)
        ArtMoveTo(_c(23.50, 78.0)),
        ArtLineTo(_c(23.45, 79.5)),
        ArtLineTo(_c(23.55, 80.0)),
        ArtLineTo(_c(23.66, 79.5)),
        ArtLineTo(_c(23.75, 80.0)),
        ArtLineTo(_c(23.85, 79.5)),
        ArtLineTo(_c(23.80, 78.0)),
        const ArtClose(),
        // Scepter (from Alderamin outward)
        ArtMoveTo(_c(21.31, 62.59)),
        ArtLineTo(_c(21.00, 61.0)),
        ArtLineTo(_c(20.80, 60.0)),
        ArtLineTo(_c(20.85, 59.5)),
        ArtLineTo(_c(21.05, 60.5)),
        ArtLineTo(_c(21.25, 62.0)),
        const ArtClose(),
      ],
    ),

    // ================================================================
    // CORONA BOREALIS — The Northern Crown
    // Anchor stars: Alphecca (15.58, 26.71), Nusakan (15.46, 29.11)
    // Figure: semicircular crown/diadem
    // ================================================================
    ConstellationArtData(
      abbreviation: 'CrB',
      segments: [
        // Crown arc (follows the arc of stars)
        ArtMoveTo(_c(15.58, 26.71)),   // Alphecca
        ArtQuadTo(_c(15.45, 28.0), _c(15.46, 29.11)),  // Nusakan
        ArtQuadTo(_c(15.60, 30.5), _c(15.71, 31.36)),   // Theta CrB
        ArtQuadTo(_c(15.85, 31.0), _c(15.96, 30.29)),   // Epsilon CrB
        ArtQuadTo(_c(16.00, 30.0), _c(16.02, 29.85)),   // Delta CrB
        ArtQuadTo(_c(16.00, 28.0), _c(15.99, 26.88)),   // Gamma CrB
        ArtLineTo(_c(15.58, 26.71)),   // back to Alphecca
        const ArtClose(),
        // Inner arc (thinner, to give crown depth)
        ArtMoveTo(_c(15.63, 27.5)),
        ArtQuadTo(_c(15.55, 28.5), _c(15.55, 29.5)),
        ArtQuadTo(_c(15.65, 30.5), _c(15.75, 30.8)),
        ArtQuadTo(_c(15.85, 30.5), _c(15.90, 29.8)),
        ArtQuadTo(_c(15.92, 28.5), _c(15.90, 27.5)),
        ArtLineTo(_c(15.63, 27.5)),
        const ArtClose(),
        // Jewel points (three small triangles on top)
        ArtMoveTo(_c(15.55, 29.5)),
        ArtLineTo(_c(15.50, 30.5)),
        ArtLineTo(_c(15.58, 30.0)),
        const ArtClose(),
        ArtMoveTo(_c(15.75, 30.8)),
        ArtLineTo(_c(15.75, 31.8)),
        ArtLineTo(_c(15.80, 31.2)),
        const ArtClose(),
        ArtMoveTo(_c(15.90, 29.8)),
        ArtLineTo(_c(15.95, 30.8)),
        ArtLineTo(_c(15.98, 30.2)),
        const ArtClose(),
      ],
    ),
  ];
}
