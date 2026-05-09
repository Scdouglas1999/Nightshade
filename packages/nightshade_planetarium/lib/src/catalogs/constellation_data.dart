import '../coordinate_system.dart';

/// Constellation data with lines and boundaries
class ConstellationData {
  final String abbreviation;
  final String name;
  final List<ConstellationLine> lines;
  final CelestialCoordinate center;
  
  const ConstellationData({
    required this.abbreviation,
    required this.name,
    required this.lines,
    required this.center,
  });
}

/// A line segment between two stars in a constellation
class ConstellationLine {
  final CelestialCoordinate start;
  final CelestialCoordinate end;
  final String? startStarName;
  final String? endStarName;
  
  const ConstellationLine({
    required this.start,
    required this.end,
    this.startStarName,
    this.endStarName,
  });
}

/// All constellation line data
class Constellations {
  static List<ConstellationData> get all => _constellations;
  
  static ConstellationData? findByAbbreviation(String abbr) {
    return _constellations.where(
      (c) => c.abbreviation.toLowerCase() == abbr.toLowerCase()
    ).firstOrNull;
  }
  
  static ConstellationData? findByName(String name) {
    return _constellations.where(
      (c) => c.name.toLowerCase() == name.toLowerCase()
    ).firstOrNull;
  }
  
  // Major constellations with stick figure lines
  static final List<ConstellationData> _constellations = [
    // Orion
    ConstellationData(
      abbreviation: 'Ori',
      name: 'Orion',
      center: CelestialCoordinate(ra: 5.5, dec: 0),
      lines: [
        // Shoulders to Belt
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.9195, dec: 7.4070), // Betelgeuse
          end: CelestialCoordinate(ra: 5.5334, dec: -0.2991), // Mintaka
          startStarName: 'Betelgeuse',
          endStarName: 'Mintaka',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.4188, dec: 6.3497), // Bellatrix
          end: CelestialCoordinate(ra: 5.6793, dec: -1.9426), // Alnitak
          startStarName: 'Bellatrix',
          endStarName: 'Alnitak',
        ),
        // Belt
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.5334, dec: -0.2991), // Mintaka
          end: CelestialCoordinate(ra: 5.6036, dec: -1.2019), // Alnilam
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.6036, dec: -1.2019), // Alnilam
          end: CelestialCoordinate(ra: 5.6793, dec: -1.9426), // Alnitak
        ),
        // Feet
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.6793, dec: -1.9426), // Alnitak
          end: CelestialCoordinate(ra: 5.7958, dec: -9.6697), // Saiph
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.5334, dec: -0.2991), // Mintaka
          end: CelestialCoordinate(ra: 5.2422, dec: -8.2017), // Rigel
          endStarName: 'Rigel',
        ),
        // Shoulders
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.9195, dec: 7.4070), // Betelgeuse
          end: CelestialCoordinate(ra: 5.4188, dec: 6.3497), // Bellatrix
        ),
      ],
    ),
    
    // Ursa Major (Big Dipper)
    ConstellationData(
      abbreviation: 'UMa',
      name: 'Ursa Major',
      center: CelestialCoordinate(ra: 11.0, dec: 55),
      lines: [
        // Bowl
        ConstellationLine(
          start: CelestialCoordinate(ra: 11.0621, dec: 61.7510), // Dubhe
          end: CelestialCoordinate(ra: 11.0306, dec: 56.3824), // Merak
          startStarName: 'Dubhe',
          endStarName: 'Merak',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 11.0306, dec: 56.3824), // Merak
          end: CelestialCoordinate(ra: 11.8968, dec: 53.6948), // Phecda
          startStarName: 'Merak',
          endStarName: 'Phecda',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 11.8968, dec: 53.6948), // Phecda
          end: CelestialCoordinate(ra: 12.2571, dec: 57.0326), // Megrez
          startStarName: 'Phecda',
          endStarName: 'Megrez',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.2571, dec: 57.0326), // Megrez
          end: CelestialCoordinate(ra: 11.0621, dec: 61.7510), // Dubhe
          startStarName: 'Megrez',
          endStarName: 'Dubhe',
        ),
        // Handle
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.2571, dec: 57.0326), // Megrez
          end: CelestialCoordinate(ra: 12.9004, dec: 55.9598), // Alioth
          startStarName: 'Megrez',
          endStarName: 'Alioth',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.9004, dec: 55.9598), // Alioth
          end: CelestialCoordinate(ra: 13.3988, dec: 54.9254), // Mizar
          startStarName: 'Alioth',
          endStarName: 'Mizar',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.3988, dec: 54.9254), // Mizar
          end: CelestialCoordinate(ra: 13.7923, dec: 49.3133), // Alkaid
          startStarName: 'Mizar',
          endStarName: 'Alkaid',
        ),
      ],
    ),
    
    // Cassiopeia
    ConstellationData(
      abbreviation: 'Cas',
      name: 'Cassiopeia',
      center: CelestialCoordinate(ra: 1.0, dec: 60),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.1530, dec: 59.1498), // Caph
          end: CelestialCoordinate(ra: 0.6752, dec: 56.5373), // Schedar
          startStarName: 'Caph',
          endStarName: 'Schedar',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.6752, dec: 56.5373), // Schedar
          end: CelestialCoordinate(ra: 0.9453, dec: 60.7167), // Navi
          startStarName: 'Schedar',
          endStarName: 'Navi',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.9453, dec: 60.7167), // Navi
          end: CelestialCoordinate(ra: 1.4306, dec: 60.2352), // Ruchbah
          startStarName: 'Navi',
          endStarName: 'Ruchbah',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.4306, dec: 60.2352), // Ruchbah
          end: CelestialCoordinate(ra: 1.9065, dec: 63.6700), // Segin
          startStarName: 'Ruchbah',
          endStarName: 'Segin',
        ),
      ],
    ),
    
    // Cygnus (Northern Cross)
    ConstellationData(
      abbreviation: 'Cyg',
      name: 'Cygnus',
      center: CelestialCoordinate(ra: 20.5, dec: 40),
      lines: [
        // Main body
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.6905, dec: 45.2803), // Deneb
          end: CelestialCoordinate(ra: 19.5120, dec: 27.9597), // Albireo
          startStarName: 'Deneb',
          endStarName: 'Albireo',
        ),
        // Cross beam (simplified)
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.3706, dec: 40.2567), // Sadr
          end: CelestialCoordinate(ra: 19.7489, dec: 45.1309), // Gienah Cygni
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.3706, dec: 40.2567), // Sadr
          end: CelestialCoordinate(ra: 21.2156, dec: 30.2269), // Fawaris
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.6905, dec: 45.2803), // Deneb
          end: CelestialCoordinate(ra: 20.3706, dec: 40.2567), // Sadr
        ),
      ],
    ),
    
    // Leo
    ConstellationData(
      abbreviation: 'Leo',
      name: 'Leo',
      center: CelestialCoordinate(ra: 10.7, dec: 15),
      lines: [
        // Sickle
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.1395, dec: 11.9672), // Regulus
          end: CelestialCoordinate(ra: 10.3328, dec: 19.8415), // Eta Leo
          startStarName: 'Regulus',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.3328, dec: 19.8415), // Eta Leo
          end: CelestialCoordinate(ra: 10.1220, dec: 23.7743), // Algieba
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.1220, dec: 23.7743), // Algieba
          end: CelestialCoordinate(ra: 10.2787, dec: 26.0072), // Zosma
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.2787, dec: 26.0072), // Zosma
          end: CelestialCoordinate(ra: 9.7644, dec: 26.0068), // Ras Elased
        ),
        // Body to tail
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.2787, dec: 26.0072), // Zosma
          end: CelestialCoordinate(ra: 11.2351, dec: 20.5236), // Chertan
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 11.2351, dec: 20.5236), // Chertan
          end: CelestialCoordinate(ra: 11.8177, dec: 14.5720), // Denebola
          endStarName: 'Denebola',
        ),
        // Triangle
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.1395, dec: 11.9672), // Regulus
          end: CelestialCoordinate(ra: 11.2351, dec: 20.5236), // Chertan
        ),
      ],
    ),
    
    // Scorpius
    ConstellationData(
      abbreviation: 'Sco',
      name: 'Scorpius',
      center: CelestialCoordinate(ra: 16.9, dec: -30),
      lines: [
        // Head to heart
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.0053, dec: -22.6217), // Dschubba
          end: CelestialCoordinate(ra: 16.4901, dec: -26.4320), // Antares
          endStarName: 'Antares',
        ),
        // Heart to tail
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.4901, dec: -26.4320), // Antares
          end: CelestialCoordinate(ra: 16.8364, dec: -34.2933), // Tau Sco
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.8364, dec: -34.2933), // Tau Sco
          end: CelestialCoordinate(ra: 17.2024, dec: -37.2959), // Epsilon Sco
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.2024, dec: -37.2959), // Epsilon Sco
          end: CelestialCoordinate(ra: 17.5601, dec: -37.1038), // Shaula
          endStarName: 'Shaula',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.5601, dec: -37.1038), // Shaula
          end: CelestialCoordinate(ra: 17.7081, dec: -39.0299), // Lesath
        ),
      ],
    ),
    
    // Gemini
    ConstellationData(
      abbreviation: 'Gem',
      name: 'Gemini',
      center: CelestialCoordinate(ra: 7.1, dec: 25),
      lines: [
        // Twins' heads
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.5767, dec: 31.8884), // Castor
          end: CelestialCoordinate(ra: 7.7553, dec: 28.0262), // Pollux
          startStarName: 'Castor',
          endStarName: 'Pollux',
        ),
        // Bodies
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.5767, dec: 31.8884), // Castor
          end: CelestialCoordinate(ra: 7.0683, dec: 20.5703), // Mebsuta
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.7553, dec: 28.0262), // Pollux
          end: CelestialCoordinate(ra: 7.1850, dec: 16.5403), // Wasat
        ),
        // Feet
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.0683, dec: 20.5703), // Mebsuta
          end: CelestialCoordinate(ra: 6.6285, dec: 16.3993), // Alhena
          endStarName: 'Alhena',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.1850, dec: 16.5403), // Wasat
          end: CelestialCoordinate(ra: 6.7328, dec: 12.8959), // Mekbuda
        ),
      ],
    ),
    
    // Pegasus (Great Square)
    ConstellationData(
      abbreviation: 'Peg',
      name: 'Pegasus',
      center: CelestialCoordinate(ra: 22.7, dec: 20),
      lines: [
        // Great Square
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.1398, dec: 29.0904), // Alpheratz
          end: CelestialCoordinate(ra: 23.0629, dec: 28.0828), // Scheat
          startStarName: 'Alpheratz',
          endStarName: 'Scheat',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.0629, dec: 28.0828), // Scheat
          end: CelestialCoordinate(ra: 23.0798, dec: 15.2053), // Markab
          endStarName: 'Markab',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.0798, dec: 15.2053), // Markab
          end: CelestialCoordinate(ra: 0.2201, dec: 15.1836), // Algenib
          endStarName: 'Algenib',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.2201, dec: 15.1836), // Algenib
          end: CelestialCoordinate(ra: 0.1398, dec: 29.0904), // Alpheratz
        ),
        // Neck/Head
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.0629, dec: 28.0828), // Scheat
          end: CelestialCoordinate(ra: 22.1168, dec: 25.3450), // Matar
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.1168, dec: 25.3450), // Matar
          end: CelestialCoordinate(ra: 21.7440, dec: 9.8749), // Enif
        ),
      ],
    ),
    
    // Andromeda
    ConstellationData(
      abbreviation: 'And',
      name: 'Andromeda',
      center: CelestialCoordinate(ra: 0.8, dec: 38),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.1398, dec: 29.0904), // Alpheratz
          end: CelestialCoordinate(ra: 1.1621, dec: 35.6206), // Mirach
          startStarName: 'Alpheratz',
          endStarName: 'Mirach',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.1621, dec: 35.6206), // Mirach
          end: CelestialCoordinate(ra: 2.0650, dec: 42.3297), // Almach
          endStarName: 'Almach',
        ),
      ],
    ),
    
    // Taurus
    ConstellationData(
      abbreviation: 'Tau',
      name: 'Taurus',
      center: CelestialCoordinate(ra: 4.5, dec: 17),
      lines: [
        // V-shape head
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.5988, dec: 16.5093), // Aldebaran
          end: CelestialCoordinate(ra: 4.4762, dec: 15.9620), // Theta2 Tau
          startStarName: 'Aldebaran',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.4762, dec: 15.9620), // Theta2 Tau
          end: CelestialCoordinate(ra: 4.3291, dec: 15.6277), // Gamma Tau
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.3291, dec: 15.6277), // Gamma Tau
          end: CelestialCoordinate(ra: 4.0113, dec: 12.4904), // Delta Tau
        ),
        // Horn tips
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.5988, dec: 16.5093), // Aldebaran
          end: CelestialCoordinate(ra: 5.4382, dec: 28.6074), // Elnath
          endStarName: 'Elnath',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.4762, dec: 15.9620), // Theta2 Tau
          end: CelestialCoordinate(ra: 5.6276, dec: 21.1425), // Zeta Tau
        ),
      ],
    ),
    
    // Canis Major
    ConstellationData(
      abbreviation: 'CMa',
      name: 'Canis Major',
      center: CelestialCoordinate(ra: 6.8, dec: -22),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.7524, dec: -16.7161), // Sirius
          end: CelestialCoordinate(ra: 6.3783, dec: -17.9559), // Mirzam
          startStarName: 'Sirius',
          endStarName: 'Mirzam',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.7524, dec: -16.7161), // Sirius
          end: CelestialCoordinate(ra: 7.1399, dec: -26.3932), // Wezen
          endStarName: 'Wezen',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.1399, dec: -26.3932), // Wezen
          end: CelestialCoordinate(ra: 6.9771, dec: -28.9722), // Adhara
          endStarName: 'Adhara',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.9771, dec: -28.9722), // Adhara
          end: CelestialCoordinate(ra: 6.6111, dec: -32.5085), // Furud
        ),
      ],
    ),
    
    // Lyra
    ConstellationData(
      abbreviation: 'Lyr',
      name: 'Lyra',
      center: CelestialCoordinate(ra: 18.8, dec: 36),
      lines: [
        // Main parallelogram
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.6156, dec: 38.7837), // Vega
          end: CelestialCoordinate(ra: 18.7462, dec: 37.6050), // Epsilon1 Lyr
          startStarName: 'Vega',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.6156, dec: 38.7837), // Vega
          end: CelestialCoordinate(ra: 18.9782, dec: 36.8986), // Zeta1 Lyr
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.9782, dec: 36.8986), // Zeta1 Lyr
          end: CelestialCoordinate(ra: 18.9077, dec: 33.3627), // Sulafat
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.9077, dec: 33.3627), // Sulafat
          end: CelestialCoordinate(ra: 18.8348, dec: 33.3629), // Sheliak
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.8348, dec: 33.3629), // Sheliak
          end: CelestialCoordinate(ra: 18.9782, dec: 36.8986), // Zeta1 Lyr
        ),
      ],
    ),
    
    // Aquila
    ConstellationData(
      abbreviation: 'Aql',
      name: 'Aquila',
      center: CelestialCoordinate(ra: 19.7, dec: 3),
      lines: [
        // Main body
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.8464, dec: 8.8683), // Altair
          end: CelestialCoordinate(ra: 19.7714, dec: 10.6132), // Tarazed
          startStarName: 'Altair',
          endStarName: 'Tarazed',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.8464, dec: 8.8683), // Altair
          end: CelestialCoordinate(ra: 19.9216, dec: 6.4067), // Alshain
        ),
        // Wings
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.7714, dec: 10.6132), // Tarazed
          end: CelestialCoordinate(ra: 19.1042, dec: 13.8635), // Delta Aql
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.9216, dec: 6.4067), // Alshain
          end: CelestialCoordinate(ra: 20.1886, dec: -0.8215), // Theta Aql
        ),
      ],
    ),
    
    // Crux (Southern Cross)
    ConstellationData(
      abbreviation: 'Cru',
      name: 'Crux',
      center: CelestialCoordinate(ra: 12.5, dec: -60),
      lines: [
        // Vertical
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.5194, dec: -57.1132), // Gacrux
          end: CelestialCoordinate(ra: 12.4433, dec: -63.0990), // Acrux
          startStarName: 'Gacrux',
          endStarName: 'Acrux',
        ),
        // Horizontal
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.7953, dec: -59.6888), // Mimosa
          end: CelestialCoordinate(ra: 12.2523, dec: -58.7489), // Imai
          startStarName: 'Mimosa',
          endStarName: 'Imai',
        ),
      ],
    ),
    
    // Perseus
    ConstellationData(
      abbreviation: 'Per',
      name: 'Perseus',
      center: CelestialCoordinate(ra: 3.4, dec: 42),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.4054, dec: 49.8612), // Mirfak
          end: CelestialCoordinate(ra: 3.0795, dec: 53.5065), // Delta Per
          startStarName: 'Mirfak',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.4054, dec: 49.8612), // Mirfak
          end: CelestialCoordinate(ra: 3.7155, dec: 47.7876), // Gamma Per
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.7155, dec: 47.7876), // Gamma Per
          end: CelestialCoordinate(ra: 3.1364, dec: 40.9557), // Algol
          endStarName: 'Algol',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.1364, dec: 40.9557), // Algol
          end: CelestialCoordinate(ra: 2.8449, dec: 38.3188), // Rho Per
        ),
      ],
    ),
    
    // Bootes
    ConstellationData(
      abbreviation: 'Boo',
      name: 'Bootes',
      center: CelestialCoordinate(ra: 14.7, dec: 30),
      lines: [
        // Kite shape
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.2612, dec: 19.1825), // Arcturus
          end: CelestialCoordinate(ra: 13.9116, dec: 18.3979), // Eta Boo
          startStarName: 'Arcturus',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.9116, dec: 18.3979), // Eta Boo
          end: CelestialCoordinate(ra: 14.5308, dec: 30.3713), // Izar
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.5308, dec: 30.3713), // Izar
          end: CelestialCoordinate(ra: 14.7499, dec: 27.0743), // Delta Boo
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.7499, dec: 27.0743), // Delta Boo
          end: CelestialCoordinate(ra: 14.2612, dec: 19.1825), // Arcturus
        ),
        // Top
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.5308, dec: 30.3713), // Izar
          end: CelestialCoordinate(ra: 15.0322, dec: 40.3906), // Nekkar
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.7499, dec: 27.0743), // Delta Boo
          end: CelestialCoordinate(ra: 15.0322, dec: 40.3906), // Nekkar
        ),
      ],
    ),
    
    // Virgo
    ConstellationData(
      abbreviation: 'Vir',
      name: 'Virgo',
      center: CelestialCoordinate(ra: 13.0, dec: -4),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.4199, dec: -11.1614), // Spica
          end: CelestialCoordinate(ra: 12.6943, dec: -1.4494), // Porrima
          startStarName: 'Spica',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.6943, dec: -1.4494), // Porrima
          end: CelestialCoordinate(ra: 12.9264, dec: 3.3975), // Vindemiatrix
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.9264, dec: 3.3975), // Vindemiatrix
          end: CelestialCoordinate(ra: 13.0367, dec: 10.9592), // Delta Vir
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.6943, dec: -1.4494), // Porrima
          end: CelestialCoordinate(ra: 11.8446, dec: 1.7648), // Zaniah
        ),
      ],
    ),

    // Ursa Minor (Little Dipper)
    ConstellationData(
      abbreviation: 'UMi',
      name: 'Ursa Minor',
      center: CelestialCoordinate(ra: 15.0, dec: 75),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.5302, dec: 89.2641), // Polaris
          end: CelestialCoordinate(ra: 17.5369, dec: 86.5863), // Yildun
          startStarName: 'Polaris',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.5369, dec: 86.5863), // Yildun
          end: CelestialCoordinate(ra: 16.2917, dec: 75.7555), // Epsilon UMi
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.2917, dec: 75.7555), // Epsilon UMi
          end: CelestialCoordinate(ra: 15.7345, dec: 77.7945), // Zeta UMi
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.7345, dec: 77.7945), // Zeta UMi
          end: CelestialCoordinate(ra: 14.8451, dec: 74.1554), // Kochab
          endStarName: 'Kochab',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.8451, dec: 74.1554), // Kochab
          end: CelestialCoordinate(ra: 15.3453, dec: 71.8340), // Pherkad
          endStarName: 'Pherkad',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.3453, dec: 71.8340), // Pherkad
          end: CelestialCoordinate(ra: 16.2917, dec: 75.7555), // Epsilon UMi
        ),
      ],
    ),

    // Draco
    ConstellationData(
      abbreviation: 'Dra',
      name: 'Draco',
      center: CelestialCoordinate(ra: 15.0, dec: 65),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.5074, dec: 52.3014), // Eltanin
          end: CelestialCoordinate(ra: 17.5073, dec: 51.4890), // Rastaban
          startStarName: 'Eltanin',
          endStarName: 'Rastaban',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.5073, dec: 51.4890), // Rastaban
          end: CelestialCoordinate(ra: 17.1465, dec: 54.4689), // Grumium
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.1465, dec: 54.4689), // Grumium
          end: CelestialCoordinate(ra: 16.4010, dec: 61.5142), // Nu Dra
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.4010, dec: 61.5142), // Nu Dra
          end: CelestialCoordinate(ra: 15.4155, dec: 58.9660), // Chi Dra
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.4155, dec: 58.9660), // Chi Dra
          end: CelestialCoordinate(ra: 14.0732, dec: 64.3758), // Thuban
          endStarName: 'Thuban',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.0732, dec: 64.3758), // Thuban
          end: CelestialCoordinate(ra: 12.5580, dec: 69.7882), // Kappa Dra
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.5580, dec: 69.7882), // Kappa Dra
          end: CelestialCoordinate(ra: 11.5233, dec: 69.3311), // Alpha Dra
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.5074, dec: 52.3014), // Eltanin
          end: CelestialCoordinate(ra: 17.1465, dec: 54.4689), // Grumium
        ),
      ],
    ),

    // Cepheus
    ConstellationData(
      abbreviation: 'Cep',
      name: 'Cepheus',
      center: CelestialCoordinate(ra: 22.0, dec: 65),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.3097, dec: 62.5856), // Alderamin
          end: CelestialCoordinate(ra: 23.6557, dec: 77.6323), // Errai
          startStarName: 'Alderamin',
          endStarName: 'Errai',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.6557, dec: 77.6323), // Errai
          end: CelestialCoordinate(ra: 23.1888, dec: 75.3875), // Iota Cep
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.1888, dec: 75.3875), // Iota Cep
          end: CelestialCoordinate(ra: 22.4868, dec: 58.2012), // Zeta Cep
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.4868, dec: 58.2012), // Zeta Cep
          end: CelestialCoordinate(ra: 21.3097, dec: 62.5856), // Alderamin
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.4868, dec: 58.2012), // Zeta Cep
          end: CelestialCoordinate(ra: 22.8282, dec: 66.2007), // Delta Cep
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.8282, dec: 66.2007), // Delta Cep
          end: CelestialCoordinate(ra: 23.1888, dec: 75.3875), // Iota Cep
        ),
      ],
    ),

    // Sagittarius
    ConstellationData(
      abbreviation: 'Sgr',
      name: 'Sagittarius',
      center: CelestialCoordinate(ra: 19.0, dec: -28),
      lines: [
        // Teapot body
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.4029, dec: -34.3844), // Kaus Australis
          end: CelestialCoordinate(ra: 18.3498, dec: -29.8282), // Kaus Media
          startStarName: 'Kaus Australis',
          endStarName: 'Kaus Media',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.3498, dec: -29.8282), // Kaus Media
          end: CelestialCoordinate(ra: 18.2296, dec: -25.4217), // Kaus Borealis
          endStarName: 'Kaus Borealis',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.2296, dec: -25.4217), // Kaus Borealis
          end: CelestialCoordinate(ra: 18.9210, dec: -26.2967), // Nunki
          endStarName: 'Nunki',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.9210, dec: -26.2967), // Nunki
          end: CelestialCoordinate(ra: 19.1632, dec: -27.6698), // Tau Sgr
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.1632, dec: -27.6698), // Tau Sgr
          end: CelestialCoordinate(ra: 19.0434, dec: -29.8801), // Ascella
          endStarName: 'Ascella',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.0434, dec: -29.8801), // Ascella
          end: CelestialCoordinate(ra: 18.4029, dec: -34.3844), // Kaus Australis
        ),
        // Lid
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.2296, dec: -25.4217), // Kaus Borealis
          end: CelestialCoordinate(ra: 18.7608, dec: -26.9907), // Phi Sgr
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.7608, dec: -26.9907), // Phi Sgr
          end: CelestialCoordinate(ra: 18.9210, dec: -26.2967), // Nunki
        ),
        // Handle (spout)
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.4029, dec: -34.3844), // Kaus Australis
          end: CelestialCoordinate(ra: 18.2965, dec: -36.7615), // Eta Sgr
        ),
      ],
    ),

    // Capricornus
    ConstellationData(
      abbreviation: 'Cap',
      name: 'Capricornus',
      center: CelestialCoordinate(ra: 21.0, dec: -18),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.2940, dec: -12.5082), // Algedi
          end: CelestialCoordinate(ra: 20.3502, dec: -14.7815), // Dabih
          startStarName: 'Algedi',
          endStarName: 'Dabih',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.3502, dec: -14.7815), // Dabih
          end: CelestialCoordinate(ra: 21.0991, dec: -17.2327), // Psi Cap
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.0991, dec: -17.2327), // Psi Cap
          end: CelestialCoordinate(ra: 21.3716, dec: -16.8344), // Deneb Algedi
          endStarName: 'Deneb Algedi',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.3716, dec: -16.8344), // Deneb Algedi
          end: CelestialCoordinate(ra: 21.6180, dec: -16.6617), // Nashira
          endStarName: 'Nashira',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.6180, dec: -16.6617), // Nashira
          end: CelestialCoordinate(ra: 21.4444, dec: -22.4115), // Zeta Cap
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.4444, dec: -22.4115), // Zeta Cap
          end: CelestialCoordinate(ra: 20.7680, dec: -25.2710), // Omega Cap
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.7680, dec: -25.2710), // Omega Cap
          end: CelestialCoordinate(ra: 20.2940, dec: -12.5082), // Algedi
        ),
      ],
    ),

    // Aquarius
    ConstellationData(
      abbreviation: 'Aqr',
      name: 'Aquarius',
      center: CelestialCoordinate(ra: 22.3, dec: -10),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.0965, dec: -0.3197), // Sadalsuud
          end: CelestialCoordinate(ra: 22.3614, dec: -1.3875), // Sadalmelik
          startStarName: 'Sadalsuud',
          endStarName: 'Sadalmelik',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.3614, dec: -1.3875), // Sadalmelik
          end: CelestialCoordinate(ra: 22.4806, dec: -0.0198), // Eta Aqr
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.4806, dec: -0.0198), // Eta Aqr
          end: CelestialCoordinate(ra: 22.8770, dec: -7.5799), // Lambda Aqr
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.8770, dec: -7.5799), // Lambda Aqr
          end: CelestialCoordinate(ra: 22.5906, dec: -13.5925), // Tau2 Aqr
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.5906, dec: -13.5925), // Tau2 Aqr
          end: CelestialCoordinate(ra: 22.8264, dec: -13.5924), // Delta Aqr (Skat)
          endStarName: 'Skat',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.8770, dec: -7.5799), // Lambda Aqr
          end: CelestialCoordinate(ra: 22.8264, dec: -13.5924), // Skat
        ),
      ],
    ),

    // Pisces
    ConstellationData(
      abbreviation: 'Psc',
      name: 'Pisces',
      center: CelestialCoordinate(ra: 0.5, dec: 12),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.0340, dec: 2.7636), // Eta Psc
          end: CelestialCoordinate(ra: 1.5247, dec: 15.3458), // Omicron Psc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.5247, dec: 15.3458), // Omicron Psc
          end: CelestialCoordinate(ra: 1.6905, dec: 19.2934), // Alpha Psc (Alrescha)
          endStarName: 'Alrescha',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.6905, dec: 19.2934), // Alrescha
          end: CelestialCoordinate(ra: 1.0496, dec: 21.4716), // Nu Psc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.0496, dec: 21.4716), // Nu Psc
          end: CelestialCoordinate(ra: 0.8114, dec: 7.5853), // Delta Psc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.8114, dec: 7.5853), // Delta Psc
          end: CelestialCoordinate(ra: 23.6659, dec: 5.6262), // Omega Psc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.6659, dec: 5.6262), // Omega Psc
          end: CelestialCoordinate(ra: 23.4487, dec: 6.3790), // Iota Psc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.4487, dec: 6.3790), // Iota Psc
          end: CelestialCoordinate(ra: 23.2860, dec: 3.2821), // Gamma Psc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.2860, dec: 3.2821), // Gamma Psc
          end: CelestialCoordinate(ra: 23.4487, dec: 6.3790), // Iota Psc
        ),
      ],
    ),

    // Aries
    ConstellationData(
      abbreviation: 'Ari',
      name: 'Aries',
      center: CelestialCoordinate(ra: 2.5, dec: 22),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.1195, dec: 23.4624), // Hamal
          end: CelestialCoordinate(ra: 1.9106, dec: 20.8081), // Sheratan
          startStarName: 'Hamal',
          endStarName: 'Sheratan',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.9106, dec: 20.8081), // Sheratan
          end: CelestialCoordinate(ra: 1.8920, dec: 19.2940), // Mesarthim
          endStarName: 'Mesarthim',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.1195, dec: 23.4624), // Hamal
          end: CelestialCoordinate(ra: 2.8332, dec: 27.2607), // 41 Ari
        ),
      ],
    ),

    // Cancer
    ConstellationData(
      abbreviation: 'Cnc',
      name: 'Cancer',
      center: CelestialCoordinate(ra: 8.7, dec: 20),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.7447, dec: 18.1542), // Acubens
          end: CelestialCoordinate(ra: 8.7213, dec: 21.4686), // Delta Cnc
          startStarName: 'Acubens',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.7213, dec: 21.4686), // Delta Cnc
          end: CelestialCoordinate(ra: 8.2752, dec: 9.1857), // Iota Cnc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.7213, dec: 21.4686), // Delta Cnc
          end: CelestialCoordinate(ra: 9.1843, dec: 22.0431), // Gamma Cnc (Asellus Borealis)
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.7447, dec: 18.1542), // Acubens
          end: CelestialCoordinate(ra: 8.9778, dec: 11.8577), // Beta Cnc (Tarf)
          endStarName: 'Tarf',
        ),
      ],
    ),

    // Libra
    ConstellationData(
      abbreviation: 'Lib',
      name: 'Libra',
      center: CelestialCoordinate(ra: 15.2, dec: -16),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.8461, dec: -16.0418), // Zubenelgenubi
          end: CelestialCoordinate(ra: 15.2832, dec: -9.3829), // Zubeneschamali
          startStarName: 'Zubenelgenubi',
          endStarName: 'Zubeneschamali',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.2832, dec: -9.3829), // Zubeneschamali
          end: CelestialCoordinate(ra: 15.5921, dec: -14.7894), // Gamma Lib
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.5921, dec: -14.7894), // Gamma Lib
          end: CelestialCoordinate(ra: 14.8461, dec: -16.0418), // Zubenelgenubi
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.5921, dec: -14.7894), // Gamma Lib
          end: CelestialCoordinate(ra: 15.0681, dec: -25.2819), // Sigma Lib
        ),
      ],
    ),

    // Ophiuchus
    ConstellationData(
      abbreviation: 'Oph',
      name: 'Ophiuchus',
      center: CelestialCoordinate(ra: 17.3, dec: -4),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.5822, dec: 12.5600), // Rasalhague
          end: CelestialCoordinate(ra: 17.7243, dec: 4.5674), // Cebalrai
          startStarName: 'Rasalhague',
          endStarName: 'Cebalrai',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.7243, dec: 4.5674), // Cebalrai
          end: CelestialCoordinate(ra: 17.1726, dec: -15.7249), // Eta Oph
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.1726, dec: -15.7249), // Eta Oph
          end: CelestialCoordinate(ra: 16.6190, dec: -10.5671), // Zeta Oph
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.6190, dec: -10.5671), // Zeta Oph
          end: CelestialCoordinate(ra: 16.3052, dec: -4.6925), // Delta Oph (Yed Prior)
          endStarName: 'Yed Prior',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.3052, dec: -4.6925), // Yed Prior
          end: CelestialCoordinate(ra: 17.5822, dec: 12.5600), // Rasalhague
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.1726, dec: -15.7249), // Eta Oph
          end: CelestialCoordinate(ra: 17.7981, dec: -24.9996), // Theta Oph
        ),
      ],
    ),

    // Serpens (Caput + Cauda as one)
    ConstellationData(
      abbreviation: 'Ser',
      name: 'Serpens',
      center: CelestialCoordinate(ra: 16.0, dec: 6),
      lines: [
        // Serpens Caput (head)
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.7378, dec: 6.4254), // Unukalhai
          end: CelestialCoordinate(ra: 15.8120, dec: 15.4218), // Beta Ser
          startStarName: 'Unukalhai',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.8120, dec: 15.4218), // Beta Ser
          end: CelestialCoordinate(ra: 15.5802, dec: 15.6618), // Gamma Ser
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.7378, dec: 6.4254), // Unukalhai
          end: CelestialCoordinate(ra: 15.9423, dec: 3.4335), // Delta Ser
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.9423, dec: 3.4335), // Delta Ser
          end: CelestialCoordinate(ra: 15.8470, dec: 4.4776), // Epsilon Ser
        ),
        // Serpens Cauda (tail)
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.3553, dec: -2.8987), // Eta Ser
          end: CelestialCoordinate(ra: 18.9367, dec: 4.2037), // Theta1 Ser
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.9367, dec: 4.2037), // Theta1 Ser
          end: CelestialCoordinate(ra: 18.3553, dec: -2.8987), // Eta Ser
        ),
      ],
    ),

    // Hercules
    ConstellationData(
      abbreviation: 'Her',
      name: 'Hercules',
      center: CelestialCoordinate(ra: 17.4, dec: 27),
      lines: [
        // Keystone
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.5034, dec: 21.4897), // Zeta Her
          end: CelestialCoordinate(ra: 16.3649, dec: 19.1530), // Eta Her
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.3649, dec: 19.1530), // Eta Her
          end: CelestialCoordinate(ra: 17.2508, dec: 24.8392), // Pi Her
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.2508, dec: 24.8392), // Pi Her
          end: CelestialCoordinate(ra: 16.6880, dec: 31.6028), // Epsilon Her
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.6880, dec: 31.6028), // Epsilon Her
          end: CelestialCoordinate(ra: 16.5034, dec: 21.4897), // Zeta Her
        ),
        // Arms and legs
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.5034, dec: 21.4897), // Zeta Her
          end: CelestialCoordinate(ra: 16.1464, dec: 14.0333), // Beta Her (Kornephoros)
          endStarName: 'Kornephoros',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.3649, dec: 19.1530), // Eta Her
          end: CelestialCoordinate(ra: 17.2442, dec: 14.3902), // Sarin
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.2508, dec: 24.8392), // Pi Her
          end: CelestialCoordinate(ra: 17.5822, dec: 12.5600), // Rasalhague (shared with Oph)
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.6880, dec: 31.6028), // Epsilon Her
          end: CelestialCoordinate(ra: 17.3941, dec: 37.1459), // Alpha Her (Rasalgethi)
          endStarName: 'Rasalgethi',
        ),
      ],
    ),

    // Auriga
    ConstellationData(
      abbreviation: 'Aur',
      name: 'Auriga',
      center: CelestialCoordinate(ra: 6.0, dec: 42),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.2783, dec: 45.9981), // Capella
          end: CelestialCoordinate(ra: 5.9953, dec: 44.9474), // Menkalinan
          startStarName: 'Capella',
          endStarName: 'Menkalinan',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.9953, dec: 44.9474), // Menkalinan
          end: CelestialCoordinate(ra: 5.9920, dec: 37.2126), // Theta Aur
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.9920, dec: 37.2126), // Theta Aur
          end: CelestialCoordinate(ra: 5.4382, dec: 28.6074), // Elnath (shared w/ Tau)
          endStarName: 'Elnath',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.4382, dec: 28.6074), // Elnath
          end: CelestialCoordinate(ra: 5.0331, dec: 33.1661), // Iota Aur
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.0331, dec: 33.1661), // Iota Aur
          end: CelestialCoordinate(ra: 5.1089, dec: 41.2346), // Epsilon Aur (Almaaz)
          endStarName: 'Almaaz',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.1089, dec: 41.2346), // Almaaz
          end: CelestialCoordinate(ra: 5.2783, dec: 45.9981), // Capella
        ),
      ],
    ),

    // Canis Minor
    ConstellationData(
      abbreviation: 'CMi',
      name: 'Canis Minor',
      center: CelestialCoordinate(ra: 7.6, dec: 6),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.6553, dec: 5.2250), // Procyon
          end: CelestialCoordinate(ra: 7.4527, dec: 8.2893), // Gomeisa
          startStarName: 'Procyon',
          endStarName: 'Gomeisa',
        ),
      ],
    ),

    // Corvus
    ConstellationData(
      abbreviation: 'Crv',
      name: 'Corvus',
      center: CelestialCoordinate(ra: 12.3, dec: -18),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.4977, dec: -23.3968), // Gienah
          end: CelestialCoordinate(ra: 12.5735, dec: -16.5159), // Gamma Crv
          startStarName: 'Gienah',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.5735, dec: -16.5159), // Gamma Crv
          end: CelestialCoordinate(ra: 12.1685, dec: -22.6197), // Beta Crv (Kraz)
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.1685, dec: -22.6197), // Kraz
          end: CelestialCoordinate(ra: 12.4977, dec: -23.3968), // Gienah
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.1685, dec: -22.6197), // Kraz
          end: CelestialCoordinate(ra: 12.1398, dec: -24.7289), // Epsilon Crv
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.4977, dec: -23.3968), // Gienah
          end: CelestialCoordinate(ra: 12.1398, dec: -24.7289), // Epsilon Crv
        ),
      ],
    ),

    // Crater
    ConstellationData(
      abbreviation: 'Crt',
      name: 'Crater',
      center: CelestialCoordinate(ra: 11.3, dec: -15),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.9965, dec: -18.2989), // Alpha Crt (Alkes)
          end: CelestialCoordinate(ra: 11.1943, dec: -22.8264), // Beta Crt
          startStarName: 'Alkes',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 11.1943, dec: -22.8264), // Beta Crt
          end: CelestialCoordinate(ra: 11.4148, dec: -17.6840), // Gamma Crt
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 11.4148, dec: -17.6840), // Gamma Crt
          end: CelestialCoordinate(ra: 11.3225, dec: -14.7785), // Delta Crt
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 11.3225, dec: -14.7785), // Delta Crt
          end: CelestialCoordinate(ra: 10.9965, dec: -18.2989), // Alkes
        ),
      ],
    ),

    // Centaurus
    ConstellationData(
      abbreviation: 'Cen',
      name: 'Centaurus',
      center: CelestialCoordinate(ra: 13.5, dec: -47),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.6599, dec: -60.8353), // Alpha Cen (Rigil Kentaurus)
          end: CelestialCoordinate(ra: 14.0637, dec: -60.3730), // Beta Cen (Hadar)
          startStarName: 'Rigil Kentaurus',
          endStarName: 'Hadar',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.0637, dec: -60.3730), // Hadar
          end: CelestialCoordinate(ra: 13.6648, dec: -53.4664), // Epsilon Cen
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.6648, dec: -53.4664), // Epsilon Cen
          end: CelestialCoordinate(ra: 12.6917, dec: -48.9597), // Gamma Cen
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.6917, dec: -48.9597), // Gamma Cen
          end: CelestialCoordinate(ra: 14.1114, dec: -36.3700), // Theta Cen (Menkent)
          endStarName: 'Menkent',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.6648, dec: -53.4664), // Epsilon Cen
          end: CelestialCoordinate(ra: 13.9253, dec: -47.2884), // Zeta Cen
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.9253, dec: -47.2884), // Zeta Cen
          end: CelestialCoordinate(ra: 14.1114, dec: -36.3700), // Menkent
        ),
      ],
    ),

    // Lupus
    ConstellationData(
      abbreviation: 'Lup',
      name: 'Lupus',
      center: CelestialCoordinate(ra: 15.3, dec: -42),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.6985, dec: -47.3884), // Alpha Lup
          end: CelestialCoordinate(ra: 14.9758, dec: -43.1340), // Beta Lup
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.9758, dec: -43.1340), // Beta Lup
          end: CelestialCoordinate(ra: 15.3560, dec: -40.6474), // Gamma Lup
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.3560, dec: -40.6474), // Gamma Lup
          end: CelestialCoordinate(ra: 15.5856, dec: -41.1668), // Delta Lup
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.5856, dec: -41.1668), // Delta Lup
          end: CelestialCoordinate(ra: 15.3783, dec: -44.6896), // Epsilon Lup
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.3783, dec: -44.6896), // Epsilon Lup
          end: CelestialCoordinate(ra: 14.6985, dec: -47.3884), // Alpha Lup
        ),
      ],
    ),

    // Corona Borealis
    ConstellationData(
      abbreviation: 'CrB',
      name: 'Corona Borealis',
      center: CelestialCoordinate(ra: 15.9, dec: 30),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.5780, dec: 26.7147), // Alphecca
          end: CelestialCoordinate(ra: 15.4630, dec: 29.1057), // Nusakan
          startStarName: 'Alphecca',
          endStarName: 'Nusakan',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.4630, dec: 29.1057), // Nusakan
          end: CelestialCoordinate(ra: 15.7126, dec: 31.3592), // Theta CrB
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.5780, dec: 26.7147), // Alphecca
          end: CelestialCoordinate(ra: 15.9899, dec: 26.8779), // Gamma CrB
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.9899, dec: 26.8779), // Gamma CrB
          end: CelestialCoordinate(ra: 16.0240, dec: 29.8511), // Delta CrB
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.0240, dec: 29.8511), // Delta CrB
          end: CelestialCoordinate(ra: 15.9592, dec: 30.2882), // Epsilon CrB
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.9592, dec: 30.2882), // Epsilon CrB
          end: CelestialCoordinate(ra: 15.7126, dec: 31.3592), // Theta CrB
        ),
      ],
    ),

    // Coma Berenices
    ConstellationData(
      abbreviation: 'Com',
      name: 'Coma Berenices',
      center: CelestialCoordinate(ra: 12.8, dec: 23),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.1664, dec: 17.5293), // Alpha Com (Diadem)
          end: CelestialCoordinate(ra: 13.1979, dec: 27.8781), // Beta Com
          startStarName: 'Diadem',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.1979, dec: 27.8781), // Beta Com
          end: CelestialCoordinate(ra: 12.4491, dec: 28.2685), // Gamma Com
        ),
      ],
    ),

    // Canes Venatici
    ConstellationData(
      abbreviation: 'CVn',
      name: 'Canes Venatici',
      center: CelestialCoordinate(ra: 13.1, dec: 40),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.9338, dec: 38.3183), // Cor Caroli
          end: CelestialCoordinate(ra: 12.5624, dec: 41.3574), // Chara
          startStarName: 'Cor Caroli',
          endStarName: 'Chara',
        ),
      ],
    ),

    // Triangulum
    ConstellationData(
      abbreviation: 'Tri',
      name: 'Triangulum',
      center: CelestialCoordinate(ra: 2.2, dec: 32),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.8853, dec: 29.5789), // Alpha Tri (Mothallah)
          end: CelestialCoordinate(ra: 2.1591, dec: 34.9872), // Beta Tri
          startStarName: 'Mothallah',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.1591, dec: 34.9872), // Beta Tri
          end: CelestialCoordinate(ra: 2.2886, dec: 33.8473), // Gamma Tri
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.2886, dec: 33.8473), // Gamma Tri
          end: CelestialCoordinate(ra: 1.8853, dec: 29.5789), // Alpha Tri
        ),
      ],
    ),

    // Sagitta
    ConstellationData(
      abbreviation: 'Sge',
      name: 'Sagitta',
      center: CelestialCoordinate(ra: 19.8, dec: 18.5),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.6790, dec: 18.0139), // Gamma Sge
          end: CelestialCoordinate(ra: 19.7894, dec: 18.5340), // Delta Sge
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.7894, dec: 18.5340), // Delta Sge
          end: CelestialCoordinate(ra: 19.9838, dec: 19.4920), // Alpha Sge (Sham)
          endStarName: 'Sham',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.6790, dec: 18.0139), // Gamma Sge
          end: CelestialCoordinate(ra: 19.6844, dec: 17.4763), // Beta Sge
        ),
      ],
    ),

    // Vulpecula
    ConstellationData(
      abbreviation: 'Vul',
      name: 'Vulpecula',
      center: CelestialCoordinate(ra: 20.2, dec: 25),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.4784, dec: 24.6650), // Alpha Vul (Anser)
          end: CelestialCoordinate(ra: 20.6337, dec: 27.7545), // 13 Vul
          startStarName: 'Anser',
        ),
      ],
    ),

    // Delphinus
    ConstellationData(
      abbreviation: 'Del',
      name: 'Delphinus',
      center: CelestialCoordinate(ra: 20.7, dec: 13),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.6259, dec: 14.5952), // Sualocin
          end: CelestialCoordinate(ra: 20.5537, dec: 11.3032), // Rotanev
          startStarName: 'Sualocin',
          endStarName: 'Rotanev',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.5537, dec: 11.3032), // Rotanev
          end: CelestialCoordinate(ra: 20.7243, dec: 15.0746), // Gamma Del
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.7243, dec: 15.0746), // Gamma Del
          end: CelestialCoordinate(ra: 20.7763, dec: 16.1243), // Delta Del
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.7763, dec: 16.1243), // Delta Del
          end: CelestialCoordinate(ra: 20.6259, dec: 14.5952), // Sualocin
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.7763, dec: 16.1243), // Delta Del
          end: CelestialCoordinate(ra: 20.6240, dec: 11.3714), // Epsilon Del (tail)
        ),
      ],
    ),

    // Equuleus
    ConstellationData(
      abbreviation: 'Equ',
      name: 'Equuleus',
      center: CelestialCoordinate(ra: 21.2, dec: 8),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.1726, dec: 10.0063), // Alpha Equ (Kitalpha)
          end: CelestialCoordinate(ra: 21.2415, dec: 6.8112), // Delta Equ
          startStarName: 'Kitalpha',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.2415, dec: 6.8112), // Delta Equ
          end: CelestialCoordinate(ra: 21.2635, dec: 5.2481), // Gamma Equ
        ),
      ],
    ),

    // Lacerta
    ConstellationData(
      abbreviation: 'Lac',
      name: 'Lacerta',
      center: CelestialCoordinate(ra: 22.5, dec: 45),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.5216, dec: 50.2825), // Alpha Lac
          end: CelestialCoordinate(ra: 22.3925, dec: 46.5365), // Beta Lac
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.3925, dec: 46.5365), // Beta Lac
          end: CelestialCoordinate(ra: 22.4082, dec: 43.1233), // 4 Lac
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.4082, dec: 43.1233), // 4 Lac
          end: CelestialCoordinate(ra: 22.4920, dec: 39.6477), // 5 Lac
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.4920, dec: 39.6477), // 5 Lac
          end: CelestialCoordinate(ra: 22.3502, dec: 37.7489), // 1 Lac
        ),
      ],
    ),

    // Eridanus
    ConstellationData(
      abbreviation: 'Eri',
      name: 'Eridanus',
      center: CelestialCoordinate(ra: 3.3, dec: -29),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.6286, dec: -57.2367), // Achernar
          end: CelestialCoordinate(ra: 2.9710, dec: -40.3047), // Acamar
          startStarName: 'Achernar',
          endStarName: 'Acamar',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.9710, dec: -40.3047), // Acamar
          end: CelestialCoordinate(ra: 3.5490, dec: -21.6328), // Zaurak
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.5490, dec: -21.6328), // Zaurak
          end: CelestialCoordinate(ra: 3.7210, dec: -12.1019), // Epsilon Eri (Ran)
          endStarName: 'Ran',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.7210, dec: -12.1019), // Ran
          end: CelestialCoordinate(ra: 4.7580, dec: -3.2543), // Delta Eri
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.7580, dec: -3.2543), // Delta Eri
          end: CelestialCoordinate(ra: 5.1308, dec: -5.0863), // Cursa
          endStarName: 'Cursa',
        ),
      ],
    ),

    // Fornax
    ConstellationData(
      abbreviation: 'For',
      name: 'Fornax',
      center: CelestialCoordinate(ra: 2.8, dec: -30),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.2013, dec: -28.9877), // Alpha For (Dalim)
          end: CelestialCoordinate(ra: 2.8182, dec: -32.4059), // Beta For
          startStarName: 'Dalim',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.8182, dec: -32.4059), // Beta For
          end: CelestialCoordinate(ra: 2.0747, dec: -29.2967), // Nu For
        ),
      ],
    ),

    // Sculptor
    ConstellationData(
      abbreviation: 'Scl',
      name: 'Sculptor',
      center: CelestialCoordinate(ra: 0.5, dec: -32),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.9764, dec: -29.3572), // Alpha Scl
          end: CelestialCoordinate(ra: 23.5497, dec: -28.1302), // Beta Scl
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.5497, dec: -28.1302), // Beta Scl
          end: CelestialCoordinate(ra: 23.3145, dec: -32.5320), // Gamma Scl
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.3145, dec: -32.5320), // Gamma Scl
          end: CelestialCoordinate(ra: 23.8153, dec: -28.1302), // Delta Scl
        ),
      ],
    ),

    // Cetus
    ConstellationData(
      abbreviation: 'Cet',
      name: 'Cetus',
      center: CelestialCoordinate(ra: 1.7, dec: -10),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.7265, dec: -17.9866), // Deneb Kaitos
          end: CelestialCoordinate(ra: 1.1432, dec: -10.1822), // Iota Cet
          startStarName: 'Deneb Kaitos',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.1432, dec: -10.1822), // Iota Cet
          end: CelestialCoordinate(ra: 1.7340, dec: -15.9376), // Eta Cet
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.7340, dec: -15.9376), // Eta Cet
          end: CelestialCoordinate(ra: 0.7265, dec: -17.9866), // Deneb Kaitos
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.1432, dec: -10.1822), // Iota Cet
          end: CelestialCoordinate(ra: 2.3222, dec: -2.9776), // Mira
          endStarName: 'Mira',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.3222, dec: -2.9776), // Mira
          end: CelestialCoordinate(ra: 3.0382, dec: 4.0897), // Menkar
          endStarName: 'Menkar',
        ),
      ],
    ),

    // Phoenix
    ConstellationData(
      abbreviation: 'Phe',
      name: 'Phoenix',
      center: CelestialCoordinate(ra: 0.9, dec: -48),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.4382, dec: -42.3061), // Ankaa
          end: CelestialCoordinate(ra: 1.1013, dec: -46.7185), // Beta Phe
          startStarName: 'Ankaa',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.1013, dec: -46.7185), // Beta Phe
          end: CelestialCoordinate(ra: 1.4728, dec: -43.3186), // Gamma Phe
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.4728, dec: -43.3186), // Gamma Phe
          end: CelestialCoordinate(ra: 0.4382, dec: -42.3061), // Ankaa
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.1013, dec: -46.7185), // Beta Phe
          end: CelestialCoordinate(ra: 1.5207, dec: -49.0728), // Epsilon Phe
        ),
      ],
    ),

    // Grus
    ConstellationData(
      abbreviation: 'Gru',
      name: 'Grus',
      center: CelestialCoordinate(ra: 22.5, dec: -45),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.1372, dec: -46.9609), // Alnair
          end: CelestialCoordinate(ra: 22.4877, dec: -43.4956), // Beta Gru
          startStarName: 'Alnair',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.4877, dec: -43.4956), // Beta Gru
          end: CelestialCoordinate(ra: 22.7111, dec: -46.8847), // Delta1 Gru
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.7111, dec: -46.8847), // Delta1 Gru
          end: CelestialCoordinate(ra: 22.1372, dec: -46.9609), // Alnair
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.4877, dec: -43.4956), // Beta Gru
          end: CelestialCoordinate(ra: 23.0146, dec: -45.2464), // Epsilon Gru
        ),
      ],
    ),

    // Pavo
    ConstellationData(
      abbreviation: 'Pav',
      name: 'Pavo',
      center: CelestialCoordinate(ra: 19.6, dec: -63),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.4275, dec: -56.7351), // Peacock
          end: CelestialCoordinate(ra: 20.0093, dec: -66.2031), // Beta Pav
          startStarName: 'Peacock',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.0093, dec: -66.2031), // Beta Pav
          end: CelestialCoordinate(ra: 18.7170, dec: -71.4280), // Delta Pav
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.7170, dec: -71.4280), // Delta Pav
          end: CelestialCoordinate(ra: 17.7628, dec: -64.7235), // Eta Pav
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.7628, dec: -64.7235), // Eta Pav
          end: CelestialCoordinate(ra: 20.4275, dec: -56.7351), // Peacock
        ),
      ],
    ),

    // Tucana
    ConstellationData(
      abbreviation: 'Tuc',
      name: 'Tucana',
      center: CelestialCoordinate(ra: 23.8, dec: -65),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.3085, dec: -60.2596), // Alpha Tuc
          end: CelestialCoordinate(ra: 23.2905, dec: -58.2358), // Gamma Tuc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 23.2905, dec: -58.2358), // Gamma Tuc
          end: CelestialCoordinate(ra: 0.5256, dec: -62.9581), // Beta1 Tuc
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.5256, dec: -62.9581), // Beta1 Tuc
          end: CelestialCoordinate(ra: 22.3085, dec: -60.2596), // Alpha Tuc
        ),
      ],
    ),

    // Indus
    ConstellationData(
      abbreviation: 'Ind',
      name: 'Indus',
      center: CelestialCoordinate(ra: 21.5, dec: -55),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.6263, dec: -47.2915), // Alpha Ind
          end: CelestialCoordinate(ra: 20.9131, dec: -58.4542), // Beta Ind
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.9131, dec: -58.4542), // Beta Ind
          end: CelestialCoordinate(ra: 21.3312, dec: -53.4493), // Theta Ind
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.3312, dec: -53.4493), // Theta Ind
          end: CelestialCoordinate(ra: 20.6263, dec: -47.2915), // Alpha Ind
        ),
      ],
    ),

    // Microscopium
    ConstellationData(
      abbreviation: 'Mic',
      name: 'Microscopium',
      center: CelestialCoordinate(ra: 21.0, dec: -36),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 20.8329, dec: -33.7797), // Gamma Mic
          end: CelestialCoordinate(ra: 21.2990, dec: -32.1726), // Epsilon Mic
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.2990, dec: -32.1726), // Epsilon Mic
          end: CelestialCoordinate(ra: 21.0210, dec: -41.3869), // Alpha Mic
        ),
      ],
    ),

    // Piscis Austrinus
    ConstellationData(
      abbreviation: 'PsA',
      name: 'Piscis Austrinus',
      center: CelestialCoordinate(ra: 22.3, dec: -31),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.9607, dec: -29.6222), // Fomalhaut
          end: CelestialCoordinate(ra: 22.5254, dec: -32.3460), // Epsilon PsA
          startStarName: 'Fomalhaut',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.5254, dec: -32.3460), // Epsilon PsA
          end: CelestialCoordinate(ra: 22.1407, dec: -32.9884), // Delta PsA
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.1407, dec: -32.9884), // Delta PsA
          end: CelestialCoordinate(ra: 22.6779, dec: -27.0435), // Gamma PsA
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.6779, dec: -27.0435), // Gamma PsA
          end: CelestialCoordinate(ra: 22.9607, dec: -29.6222), // Fomalhaut
        ),
      ],
    ),

    // Ara
    ConstellationData(
      abbreviation: 'Ara',
      name: 'Ara',
      center: CelestialCoordinate(ra: 17.3, dec: -53),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.5307, dec: -49.8761), // Alpha Ara
          end: CelestialCoordinate(ra: 17.4216, dec: -55.5299), // Beta Ara
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.4216, dec: -55.5299), // Beta Ara
          end: CelestialCoordinate(ra: 17.2526, dec: -56.3776), // Gamma Ara
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.2526, dec: -56.3776), // Gamma Ara
          end: CelestialCoordinate(ra: 17.5181, dec: -60.6836), // Delta Ara
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 17.5307, dec: -49.8761), // Alpha Ara
          end: CelestialCoordinate(ra: 16.9776, dec: -55.9901), // Zeta Ara
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.9776, dec: -55.9901), // Zeta Ara
          end: CelestialCoordinate(ra: 17.2526, dec: -56.3776), // Gamma Ara
        ),
      ],
    ),

    // Corona Australis
    ConstellationData(
      abbreviation: 'CrA',
      name: 'Corona Australis',
      center: CelestialCoordinate(ra: 18.6, dec: -40),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.1579, dec: -37.9044), // Alpha CrA (Meridiana)
          end: CelestialCoordinate(ra: 19.1670, dec: -39.3407), // Beta CrA
          startStarName: 'Meridiana',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.1670, dec: -39.3407), // Beta CrA
          end: CelestialCoordinate(ra: 18.8125, dec: -43.6805), // Delta CrA
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.1579, dec: -37.9044), // Meridiana
          end: CelestialCoordinate(ra: 19.1068, dec: -37.0635), // Gamma CrA
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 19.1068, dec: -37.0635), // Gamma CrA
          end: CelestialCoordinate(ra: 18.9780, dec: -37.1071), // Epsilon CrA
        ),
      ],
    ),

    // Telescopium
    ConstellationData(
      abbreviation: 'Tel',
      name: 'Telescopium',
      center: CelestialCoordinate(ra: 18.3, dec: -50),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.4494, dec: -45.9685), // Alpha Tel
          end: CelestialCoordinate(ra: 18.4806, dec: -49.0704), // Zeta Tel
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.4806, dec: -49.0704), // Zeta Tel
          end: CelestialCoordinate(ra: 18.1870, dec: -45.9546), // Epsilon Tel
        ),
      ],
    ),

    // Norma
    ConstellationData(
      abbreviation: 'Nor',
      name: 'Norma',
      center: CelestialCoordinate(ra: 16.0, dec: -50),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.3297, dec: -50.1555), // Gamma2 Nor
          end: CelestialCoordinate(ra: 16.4536, dec: -47.5548), // Epsilon Nor
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.4536, dec: -47.5548), // Epsilon Nor
          end: CelestialCoordinate(ra: 16.1099, dec: -45.1731), // Eta Nor
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.1099, dec: -45.1731), // Eta Nor
          end: CelestialCoordinate(ra: 16.3297, dec: -50.1555), // Gamma2 Nor
        ),
      ],
    ),

    // Circinus
    ConstellationData(
      abbreviation: 'Cir',
      name: 'Circinus',
      center: CelestialCoordinate(ra: 14.6, dec: -63),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.7083, dec: -64.9753), // Alpha Cir
          end: CelestialCoordinate(ra: 15.3909, dec: -59.3208), // Beta Cir
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.3909, dec: -59.3208), // Beta Cir
          end: CelestialCoordinate(ra: 15.3893, dec: -59.3219), // Gamma Cir
        ),
      ],
    ),

    // Triangulum Australe
    ConstellationData(
      abbreviation: 'TrA',
      name: 'Triangulum Australe',
      center: CelestialCoordinate(ra: 16.1, dec: -65),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.8110, dec: -69.0277), // Atria
          end: CelestialCoordinate(ra: 15.9190, dec: -63.4300), // Beta TrA
          startStarName: 'Atria',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.9190, dec: -63.4300), // Beta TrA
          end: CelestialCoordinate(ra: 15.3150, dec: -68.6795), // Gamma TrA
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 15.3150, dec: -68.6795), // Gamma TrA
          end: CelestialCoordinate(ra: 16.8110, dec: -69.0277), // Atria
        ),
      ],
    ),

    // Musca
    ConstellationData(
      abbreviation: 'Mus',
      name: 'Musca',
      center: CelestialCoordinate(ra: 12.5, dec: -70),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.6194, dec: -69.1356), // Alpha Mus
          end: CelestialCoordinate(ra: 12.7711, dec: -68.1080), // Beta Mus
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.7711, dec: -68.1080), // Beta Mus
          end: CelestialCoordinate(ra: 13.0378, dec: -71.5491), // Delta Mus
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.0378, dec: -71.5491), // Delta Mus
          end: CelestialCoordinate(ra: 12.3533, dec: -72.1329), // Lambda Mus
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.3533, dec: -72.1329), // Lambda Mus
          end: CelestialCoordinate(ra: 12.6194, dec: -69.1356), // Alpha Mus
        ),
      ],
    ),

    // Chamaeleon
    ConstellationData(
      abbreviation: 'Cha',
      name: 'Chamaeleon',
      center: CelestialCoordinate(ra: 10.7, dec: -79),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.3088, dec: -76.9199), // Alpha Cha
          end: CelestialCoordinate(ra: 10.5914, dec: -78.6077), // Gamma Cha
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.5914, dec: -78.6077), // Gamma Cha
          end: CelestialCoordinate(ra: 12.3057, dec: -79.3122), // Beta Cha
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 12.3057, dec: -79.3122), // Beta Cha
          end: CelestialCoordinate(ra: 10.7627, dec: -80.5401), // Delta2 Cha
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.7627, dec: -80.5401), // Delta2 Cha
          end: CelestialCoordinate(ra: 8.3088, dec: -76.9199), // Alpha Cha
        ),
      ],
    ),

    // Volans
    ConstellationData(
      abbreviation: 'Vol',
      name: 'Volans',
      center: CelestialCoordinate(ra: 7.8, dec: -69),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.2806, dec: -67.9572), // Gamma2 Vol
          end: CelestialCoordinate(ra: 8.1319, dec: -68.6167), // Beta Vol
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.1319, dec: -68.6167), // Beta Vol
          end: CelestialCoordinate(ra: 7.6966, dec: -72.6062), // Delta Vol
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.6966, dec: -72.6062), // Delta Vol
          end: CelestialCoordinate(ra: 7.2806, dec: -67.9572), // Gamma2 Vol
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.1319, dec: -68.6167), // Beta Vol
          end: CelestialCoordinate(ra: 9.0408, dec: -66.3961), // Alpha Vol
        ),
      ],
    ),

    // Pictor
    ConstellationData(
      abbreviation: 'Pic',
      name: 'Pictor',
      center: CelestialCoordinate(ra: 5.7, dec: -53),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.8030, dec: -61.9414), // Alpha Pic
          end: CelestialCoordinate(ra: 5.7882, dec: -51.0665), // Beta Pic
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.7882, dec: -51.0665), // Beta Pic
          end: CelestialCoordinate(ra: 5.8305, dec: -56.1667), // Gamma Pic
        ),
      ],
    ),

    // Dorado
    ConstellationData(
      abbreviation: 'Dor',
      name: 'Dorado',
      center: CelestialCoordinate(ra: 5.2, dec: -60),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.5666, dec: -55.0450), // Alpha Dor
          end: CelestialCoordinate(ra: 5.5604, dec: -62.4897), // Beta Dor
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.5604, dec: -62.4897), // Beta Dor
          end: CelestialCoordinate(ra: 4.2667, dec: -51.4867), // Gamma Dor
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.2667, dec: -51.4867), // Gamma Dor
          end: CelestialCoordinate(ra: 4.5666, dec: -55.0450), // Alpha Dor
        ),
      ],
    ),

    // Reticulum
    ConstellationData(
      abbreviation: 'Ret',
      name: 'Reticulum',
      center: CelestialCoordinate(ra: 3.9, dec: -60),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.2404, dec: -62.4739), // Alpha Ret
          end: CelestialCoordinate(ra: 3.7365, dec: -64.8071), // Beta Ret
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.7365, dec: -64.8071), // Beta Ret
          end: CelestialCoordinate(ra: 4.0132, dec: -63.2528), // Delta Ret
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.0132, dec: -63.2528), // Delta Ret
          end: CelestialCoordinate(ra: 3.9791, dec: -61.3998), // Epsilon Ret
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.9791, dec: -61.3998), // Epsilon Ret
          end: CelestialCoordinate(ra: 4.2404, dec: -62.4739), // Alpha Ret
        ),
      ],
    ),

    // Horologium
    ConstellationData(
      abbreviation: 'Hor',
      name: 'Horologium',
      center: CelestialCoordinate(ra: 3.3, dec: -53),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.2335, dec: -42.2944), // Alpha Hor
          end: CelestialCoordinate(ra: 2.6237, dec: -52.5435), // Eta Hor
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 2.6237, dec: -52.5435), // Eta Hor
          end: CelestialCoordinate(ra: 2.9806, dec: -64.0712), // Iota Hor
        ),
      ],
    ),

    // Caelum
    ConstellationData(
      abbreviation: 'Cae',
      name: 'Caelum',
      center: CelestialCoordinate(ra: 4.7, dec: -38),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.6761, dec: -41.8638), // Alpha Cae
          end: CelestialCoordinate(ra: 4.7009, dec: -37.1444), // Beta Cae
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.7009, dec: -37.1444), // Beta Cae
          end: CelestialCoordinate(ra: 5.0733, dec: -35.4829), // Gamma Cae
        ),
      ],
    ),

    // Columba
    ConstellationData(
      abbreviation: 'Col',
      name: 'Columba',
      center: CelestialCoordinate(ra: 5.9, dec: -35),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.6600, dec: -34.0741), // Phact
          end: CelestialCoordinate(ra: 5.9588, dec: -35.7703), // Wazn
          startStarName: 'Phact',
          endStarName: 'Wazn',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.9588, dec: -35.7703), // Wazn
          end: CelestialCoordinate(ra: 5.5206, dec: -35.4706), // Delta Col
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.6600, dec: -34.0741), // Phact
          end: CelestialCoordinate(ra: 6.3684, dec: -33.4364), // Epsilon Col
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.9588, dec: -35.7703), // Wazn
          end: CelestialCoordinate(ra: 6.3684, dec: -33.4364), // Epsilon Col
        ),
      ],
    ),

    // Lepus
    ConstellationData(
      abbreviation: 'Lep',
      name: 'Lepus',
      center: CelestialCoordinate(ra: 5.5, dec: -19),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.5456, dec: -17.8222), // Arneb
          end: CelestialCoordinate(ra: 5.4706, dec: -20.7594), // Nihal
          startStarName: 'Arneb',
          endStarName: 'Nihal',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.4706, dec: -20.7594), // Nihal
          end: CelestialCoordinate(ra: 5.0910, dec: -22.3712), // Epsilon Lep
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.0910, dec: -22.3712), // Epsilon Lep
          end: CelestialCoordinate(ra: 5.2155, dec: -16.2054), // Mu Lep
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.2155, dec: -16.2054), // Mu Lep
          end: CelestialCoordinate(ra: 5.5456, dec: -17.8222), // Arneb
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.5456, dec: -17.8222), // Arneb
          end: CelestialCoordinate(ra: 5.7410, dec: -14.1680), // Gamma Lep
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.4706, dec: -20.7594), // Nihal
          end: CelestialCoordinate(ra: 5.8553, dec: -20.8791), // Delta Lep
        ),
      ],
    ),

    // Monoceros
    ConstellationData(
      abbreviation: 'Mon',
      name: 'Monoceros',
      center: CelestialCoordinate(ra: 7.2, dec: -3),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.6873, dec: -9.5516), // Alpha Mon
          end: CelestialCoordinate(ra: 6.4802, dec: -7.0330), // Beta Mon
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.4802, dec: -7.0330), // Beta Mon
          end: CelestialCoordinate(ra: 6.2475, dec: -6.2751), // Gamma Mon
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.2475, dec: -6.2751), // Gamma Mon
          end: CelestialCoordinate(ra: 7.1975, dec: -0.4927), // Delta Mon
        ),
      ],
    ),

    // Hydra
    ConstellationData(
      abbreviation: 'Hya',
      name: 'Hydra',
      center: CelestialCoordinate(ra: 10.2, dec: -20),
      lines: [
        // Head
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.6277, dec: -5.4467), // Zeta Hya
          end: CelestialCoordinate(ra: 8.7232, dec: 6.4189), // Epsilon Hya
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.7232, dec: 6.4189), // Epsilon Hya
          end: CelestialCoordinate(ra: 8.9233, dec: 5.9456), // Delta Hya
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.9233, dec: 5.9456), // Delta Hya
          end: CelestialCoordinate(ra: 9.2398, dec: 2.3141), // Sigma Hya
        ),
        // Body
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.6277, dec: -5.4467), // Zeta Hya
          end: CelestialCoordinate(ra: 9.4596, dec: -8.6586), // Alphard
          endStarName: 'Alphard',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 9.4596, dec: -8.6586), // Alphard
          end: CelestialCoordinate(ra: 10.1765, dec: -12.3541), // Nu Hya
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.1765, dec: -12.3541), // Nu Hya
          end: CelestialCoordinate(ra: 11.5505, dec: -31.8577), // Gamma Hya
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 11.5505, dec: -31.8577), // Gamma Hya
          end: CelestialCoordinate(ra: 13.3152, dec: -23.1716), // Pi Hya
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 13.3152, dec: -23.1716), // Pi Hya
          end: CelestialCoordinate(ra: 14.1062, dec: -26.6822), // Gamma1 Hya (tail end)
        ),
      ],
    ),

    // Sextans
    ConstellationData(
      abbreviation: 'Sex',
      name: 'Sextans',
      center: CelestialCoordinate(ra: 10.3, dec: -2),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.1322, dec: -0.3719), // Alpha Sex
          end: CelestialCoordinate(ra: 10.4993, dec: -0.6375), // Beta Sex
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.4993, dec: -0.6375), // Beta Sex
          end: CelestialCoordinate(ra: 9.8753, dec: -8.1055), // Gamma Sex
        ),
      ],
    ),

    // Antlia
    ConstellationData(
      abbreviation: 'Ant',
      name: 'Antlia',
      center: CelestialCoordinate(ra: 10.3, dec: -34),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.4526, dec: -31.0678), // Alpha Ant
          end: CelestialCoordinate(ra: 9.4874, dec: -35.9514), // Epsilon Ant
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 9.4874, dec: -35.9514), // Epsilon Ant
          end: CelestialCoordinate(ra: 10.4526, dec: -31.0678), // Alpha Ant
        ),
      ],
    ),

    // Pyxis
    ConstellationData(
      abbreviation: 'Pyx',
      name: 'Pyxis',
      center: CelestialCoordinate(ra: 8.9, dec: -27),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.7266, dec: -33.1863), // Alpha Pyx
          end: CelestialCoordinate(ra: 8.8417, dec: -35.3082), // Beta Pyx
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.8417, dec: -35.3082), // Beta Pyx
          end: CelestialCoordinate(ra: 8.8425, dec: -27.7101), // Gamma Pyx
        ),
      ],
    ),

    // Puppis
    ConstellationData(
      abbreviation: 'Pup',
      name: 'Puppis',
      center: CelestialCoordinate(ra: 7.3, dec: -32),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.0594, dec: -40.0036), // Zeta Pup (Naos)
          end: CelestialCoordinate(ra: 7.8218, dec: -24.8597), // Pi Pup
          startStarName: 'Naos',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.8218, dec: -24.8597), // Pi Pup
          end: CelestialCoordinate(ra: 7.2856, dec: -37.0975), // Nu Pup
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 7.2856, dec: -37.0975), // Nu Pup
          end: CelestialCoordinate(ra: 8.0594, dec: -40.0036), // Naos
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.6291, dec: -43.1960), // Rho Pup
          end: CelestialCoordinate(ra: 7.2856, dec: -37.0975), // Nu Pup
        ),
      ],
    ),

    // Vela
    ConstellationData(
      abbreviation: 'Vel',
      name: 'Vela',
      center: CelestialCoordinate(ra: 9.4, dec: -47),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.1586, dec: -47.3367), // Gamma2 Vel (Regor)
          end: CelestialCoordinate(ra: 8.7452, dec: -54.7087), // Delta Vel
          startStarName: 'Regor',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.7452, dec: -54.7087), // Delta Vel
          end: CelestialCoordinate(ra: 9.5115, dec: -40.4668), // Kappa Vel (Markeb)
          endStarName: 'Markeb',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 9.5115, dec: -40.4668), // Markeb
          end: CelestialCoordinate(ra: 9.1330, dec: -43.4326), // Lambda Vel (Suhail)
          endStarName: 'Suhail',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 9.1330, dec: -43.4326), // Suhail
          end: CelestialCoordinate(ra: 8.1586, dec: -47.3367), // Regor
        ),
      ],
    ),

    // Carina
    ConstellationData(
      abbreviation: 'Car',
      name: 'Carina',
      center: CelestialCoordinate(ra: 8.7, dec: -63),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.3992, dec: -52.6956), // Canopus
          end: CelestialCoordinate(ra: 9.2200, dec: -59.2753), // Avior
          startStarName: 'Canopus',
          endStarName: 'Avior',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 9.2200, dec: -59.2753), // Avior
          end: CelestialCoordinate(ra: 9.2847, dec: -69.7172), // Miaplacidus
          endStarName: 'Miaplacidus',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 9.2847, dec: -69.7172), // Miaplacidus
          end: CelestialCoordinate(ra: 10.7156, dec: -64.3944), // Theta Car
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.7156, dec: -64.3944), // Theta Car
          end: CelestialCoordinate(ra: 9.2200, dec: -59.2753), // Avior
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.3992, dec: -52.6956), // Canopus
          end: CelestialCoordinate(ra: 8.3752, dec: -59.5096), // Iota Car (Aspidiske)
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.3752, dec: -59.5096), // Aspidiske
          end: CelestialCoordinate(ra: 9.2200, dec: -59.2753), // Avior
        ),
      ],
    ),

    // Octans
    ConstellationData(
      abbreviation: 'Oct',
      name: 'Octans',
      center: CelestialCoordinate(ra: 22.0, dec: -82),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.4487, dec: -83.6679), // Nu Oct
          end: CelestialCoordinate(ra: 22.7676, dec: -81.3816), // Beta Oct
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 22.7676, dec: -81.3816), // Beta Oct
          end: CelestialCoordinate(ra: 21.6912, dec: -77.3899), // Delta Oct
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 21.6912, dec: -77.3899), // Delta Oct
          end: CelestialCoordinate(ra: 14.4487, dec: -83.6679), // Nu Oct
        ),
      ],
    ),

    // Mensa
    ConstellationData(
      abbreviation: 'Men',
      name: 'Mensa',
      center: CelestialCoordinate(ra: 5.4, dec: -77),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.1706, dec: -74.7531), // Alpha Men
          end: CelestialCoordinate(ra: 5.5313, dec: -76.3414), // Gamma Men
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.5313, dec: -76.3414), // Gamma Men
          end: CelestialCoordinate(ra: 4.9198, dec: -74.9372), // Eta Men
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.9198, dec: -74.9372), // Eta Men
          end: CelestialCoordinate(ra: 5.0451, dec: -71.3143), // Beta Men
        ),
      ],
    ),

    // Hydrus
    ConstellationData(
      abbreviation: 'Hyi',
      name: 'Hydrus',
      center: CelestialCoordinate(ra: 2.3, dec: -72),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 1.9795, dec: -61.5697), // Alpha Hyi
          end: CelestialCoordinate(ra: 0.4293, dec: -77.2542), // Beta Hyi
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 0.4293, dec: -77.2542), // Beta Hyi
          end: CelestialCoordinate(ra: 3.7873, dec: -74.2389), // Gamma Hyi
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.7873, dec: -74.2389), // Gamma Hyi
          end: CelestialCoordinate(ra: 1.9795, dec: -61.5697), // Alpha Hyi
        ),
      ],
    ),

    // Apus
    ConstellationData(
      abbreviation: 'Aps',
      name: 'Apus',
      center: CelestialCoordinate(ra: 16.0, dec: -75),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 14.7977, dec: -79.0447), // Alpha Aps
          end: CelestialCoordinate(ra: 16.3343, dec: -78.8949), // Gamma Aps
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.3343, dec: -78.8949), // Gamma Aps
          end: CelestialCoordinate(ra: 16.7181, dec: -77.5167), // Beta Aps
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 16.7181, dec: -77.5167), // Beta Aps
          end: CelestialCoordinate(ra: 16.3397, dec: -73.3898), // Delta1 Aps
        ),
      ],
    ),

    // Scutum
    ConstellationData(
      abbreviation: 'Sct',
      name: 'Scutum',
      center: CelestialCoordinate(ra: 18.7, dec: -10),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.5862, dec: -8.2440), // Alpha Sct
          end: CelestialCoordinate(ra: 18.7862, dec: -4.7477), // Beta Sct
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.7862, dec: -4.7477), // Beta Sct
          end: CelestialCoordinate(ra: 18.4871, dec: -14.5656), // Gamma Sct
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 18.4871, dec: -14.5656), // Gamma Sct
          end: CelestialCoordinate(ra: 18.5862, dec: -8.2440), // Alpha Sct
        ),
      ],
    ),

    // Camelopardalis
    ConstellationData(
      abbreviation: 'Cam',
      name: 'Camelopardalis',
      center: CelestialCoordinate(ra: 6.1, dec: 69),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 4.9008, dec: 66.3426), // Alpha Cam
          end: CelestialCoordinate(ra: 5.0569, dec: 60.4425), // Beta Cam
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 5.0569, dec: 60.4425), // Beta Cam
          end: CelestialCoordinate(ra: 3.8397, dec: 71.3325), // Gamma Cam
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 3.8397, dec: 71.3325), // Gamma Cam
          end: CelestialCoordinate(ra: 4.9008, dec: 66.3426), // Alpha Cam
        ),
      ],
    ),

    // Lynx
    ConstellationData(
      abbreviation: 'Lyn',
      name: 'Lynx',
      center: CelestialCoordinate(ra: 8.0, dec: 48),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 9.3509, dec: 34.3926), // Alpha Lyn
          end: CelestialCoordinate(ra: 9.0109, dec: 41.7829), // 38 Lyn
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 9.0109, dec: 41.7829), // 38 Lyn
          end: CelestialCoordinate(ra: 8.3803, dec: 43.1882), // 31 Lyn
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 8.3803, dec: 43.1882), // 31 Lyn
          end: CelestialCoordinate(ra: 6.9552, dec: 55.7074), // 21 Lyn
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 6.9552, dec: 55.7074), // 21 Lyn
          end: CelestialCoordinate(ra: 6.3271, dec: 59.0108), // 15 Lyn
        ),
      ],
    ),

    // Leo Minor
    ConstellationData(
      abbreviation: 'LMi',
      name: 'Leo Minor',
      center: CelestialCoordinate(ra: 10.2, dec: 33),
      lines: [
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.4644, dec: 36.7074), // 46 LMi (Praecipua)
          end: CelestialCoordinate(ra: 10.8889, dec: 34.2148), // Beta LMi
          startStarName: 'Praecipua',
        ),
        ConstellationLine(
          start: CelestialCoordinate(ra: 10.8889, dec: 34.2148), // Beta LMi
          end: CelestialCoordinate(ra: 9.8734, dec: 35.2447), // 21 LMi
        ),
      ],
    ),

  ];
}

/// A boundary polygon vertex (RA in hours, Dec in degrees, J2000)
class BoundaryVertex {
  final double ra;
  final double dec;
  const BoundaryVertex(this.ra, this.dec);
}

/// Constellation boundary data with point-in-polygon lookup.
/// Boundaries are simplified IAU constellation boundaries (J2000 epoch).
/// Each boundary is a closed polygon of RA/Dec vertices.
class ConstellationBoundaries {
  /// Get boundary vertices for a given constellation abbreviation.
  static List<BoundaryVertex>? getBoundary(String abbreviation) {
    return _boundaries[abbreviation];
  }

  /// Get all boundary data.
  static Map<String, List<BoundaryVertex>> get all => _boundaries;

  /// Determine which constellation contains the given RA/Dec coordinate.
  /// Uses ray-casting point-in-polygon algorithm adapted for spherical coords.
  /// Returns the IAU abbreviation, or null if not found.
  static String? getConstellationAtCoordinate(double ra, double dec) {
    for (final entry in _boundaries.entries) {
      if (_pointInPolygon(ra, dec, entry.value)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Ray-casting algorithm for point-in-polygon on the RA/Dec sphere.
  /// RA is in hours (0-24), Dec in degrees (-90 to +90).
  /// Handles RA wraparound at the 0h/24h boundary.
  static bool _pointInPolygon(double ra, double dec, List<BoundaryVertex> polygon) {
    if (polygon.length < 3) return false;

    // Convert RA to degrees for the algorithm (0-360)
    final testRa = ra * 15.0;
    final testDec = dec;

    var inside = false;
    var j = polygon.length - 1;

    for (var i = 0; i < polygon.length; i++) {
      final iRa = polygon[i].ra * 15.0;
      final iDec = polygon[i].dec;
      final jRa = polygon[j].ra * 15.0;
      final jDec = polygon[j].dec;

      // Handle RA wraparound: if edge spans more than 180 degrees,
      // it wraps around the 0/360 boundary
      var effectiveIRa = iRa;
      var effectiveJRa = jRa;
      var effectiveTestRa = testRa;

      if ((effectiveIRa - effectiveJRa).abs() > 180) {
        // Wraparound case: shift coordinates so the edge doesn't cross 0/360
        if (effectiveIRa < 180) effectiveIRa += 360;
        if (effectiveJRa < 180) effectiveJRa += 360;
        if (effectiveTestRa < 180) effectiveTestRa += 360;
      }

      if (((iDec > testDec) != (jDec > testDec)) &&
          (effectiveTestRa < (effectiveJRa - effectiveIRa) * (testDec - iDec) / (jDec - iDec) + effectiveIRa)) {
        inside = !inside;
      }
      j = i;
    }

    return inside;
  }

  // Simplified IAU constellation boundary polygons (J2000 epoch).
  // Vertices are (RA hours, Dec degrees). Polygons are closed (last vertex connects to first).
  // These are simplified versions with key vertices along the boundary.
  static final Map<String, List<BoundaryVertex>> _boundaries = {
    'And': [
      BoundaryVertex(23.5583, 53.1681), BoundaryVertex(23.6675, 46.5314),
      BoundaryVertex(23.5000, 43.9581), BoundaryVertex(23.5000, 36.7500),
      BoundaryVertex(1.5667, 36.7500), BoundaryVertex(1.6833, 36.2500),
      BoundaryVertex(2.0583, 33.2500), BoundaryVertex(2.3917, 33.2500),
      BoundaryVertex(2.5750, 37.2500), BoundaryVertex(1.3333, 48.0000),
      BoundaryVertex(0.1417, 48.0000), BoundaryVertex(0.0000, 48.0000),
      BoundaryVertex(23.5583, 48.0000), BoundaryVertex(23.5583, 53.1681),
    ],
    'Ant': [
      BoundaryVertex(9.4500, -24.5000), BoundaryVertex(11.0583, -24.5000),
      BoundaryVertex(11.0583, -35.5833), BoundaryVertex(9.4500, -35.5833),
      BoundaryVertex(9.4500, -24.5000),
    ],
    'Aps': [
      BoundaryVertex(13.8333, -67.5000), BoundaryVertex(18.4583, -67.5000),
      BoundaryVertex(18.4583, -75.0000), BoundaryVertex(16.4167, -75.0000),
      BoundaryVertex(13.8333, -75.0000), BoundaryVertex(13.8333, -83.1200),
      BoundaryVertex(14.1667, -83.1200), BoundaryVertex(18.0000, -82.0000),
      BoundaryVertex(18.4583, -75.0000), BoundaryVertex(13.8333, -67.5000),
    ],
    'Aqr': [
      BoundaryVertex(20.6417, 2.0000), BoundaryVertex(20.8750, -2.0000),
      BoundaryVertex(21.0417, -2.0000), BoundaryVertex(22.8583, -2.0000),
      BoundaryVertex(23.8333, -6.0000), BoundaryVertex(23.8333, -24.8250),
      BoundaryVertex(22.0000, -24.8250), BoundaryVertex(20.6417, -24.8250),
      BoundaryVertex(20.6417, 2.0000),
    ],
    'Aql': [
      BoundaryVertex(18.5833, 18.0000), BoundaryVertex(20.6417, 18.0000),
      BoundaryVertex(20.6417, 2.0000), BoundaryVertex(20.0000, -2.0000),
      BoundaryVertex(18.5833, -12.0333), BoundaryVertex(18.2417, -12.0333),
      BoundaryVertex(18.5833, 0.0000), BoundaryVertex(18.5833, 18.0000),
    ],
    'Ara': [
      BoundaryVertex(16.5833, -45.5000), BoundaryVertex(18.0417, -45.5000),
      BoundaryVertex(18.0417, -56.5000), BoundaryVertex(17.5000, -60.0000),
      BoundaryVertex(16.5833, -60.0000), BoundaryVertex(16.5833, -56.5000),
      BoundaryVertex(16.5833, -45.5000),
    ],
    'Ari': [
      BoundaryVertex(1.4667, 10.0000), BoundaryVertex(3.5000, 10.0000),
      BoundaryVertex(3.5000, 31.2222), BoundaryVertex(1.4667, 31.2222),
      BoundaryVertex(1.4667, 10.0000),
    ],
    'Aur': [
      BoundaryVertex(4.9667, 56.1667), BoundaryVertex(7.0333, 56.1667),
      BoundaryVertex(7.0333, 44.5000), BoundaryVertex(6.1083, 28.0000),
      BoundaryVertex(4.9667, 28.0000), BoundaryVertex(4.9667, 36.7500),
      BoundaryVertex(4.9667, 56.1667),
    ],
    'Boo': [
      BoundaryVertex(13.5000, 8.0000), BoundaryVertex(15.7500, 8.0000),
      BoundaryVertex(15.7500, 25.5000), BoundaryVertex(15.4917, 40.0000),
      BoundaryVertex(15.0750, 52.5000), BoundaryVertex(13.5000, 52.5000),
      BoundaryVertex(13.5000, 8.0000),
    ],
    'Cae': [
      BoundaryVertex(4.5167, -27.0000), BoundaryVertex(5.0583, -27.0000),
      BoundaryVertex(5.0583, -49.0000), BoundaryVertex(4.5167, -49.0000),
      BoundaryVertex(4.5167, -27.0000),
    ],
    'Cam': [
      BoundaryVertex(3.1583, 53.0000), BoundaryVertex(7.0000, 53.0000),
      BoundaryVertex(7.0000, 60.0000), BoundaryVertex(8.4167, 60.0000),
      BoundaryVertex(8.4167, 68.0000), BoundaryVertex(5.0000, 77.0000),
      BoundaryVertex(3.1583, 77.0000), BoundaryVertex(3.1583, 53.0000),
    ],
    'Cnc': [
      BoundaryVertex(7.8917, 7.0000), BoundaryVertex(9.3583, 7.0000),
      BoundaryVertex(9.3583, 33.1417), BoundaryVertex(7.8917, 33.1417),
      BoundaryVertex(7.8917, 7.0000),
    ],
    'CVn': [
      BoundaryVertex(12.0583, 28.0000), BoundaryVertex(14.0750, 28.0000),
      BoundaryVertex(14.0750, 52.3611), BoundaryVertex(12.0583, 52.3611),
      BoundaryVertex(12.0583, 28.0000),
    ],
    'CMa': [
      BoundaryVertex(6.0000, -11.0000), BoundaryVertex(7.3667, -11.0000),
      BoundaryVertex(7.3667, -33.2500), BoundaryVertex(6.0000, -33.2500),
      BoundaryVertex(6.0000, -11.0000),
    ],
    'CMi': [
      BoundaryVertex(7.0583, 0.0000), BoundaryVertex(8.1750, 0.0000),
      BoundaryVertex(8.1750, 13.2222), BoundaryVertex(7.0583, 13.2222),
      BoundaryVertex(7.0583, 0.0000),
    ],
    'Cap': [
      BoundaryVertex(20.0667, -8.0000), BoundaryVertex(21.6667, -8.0000),
      BoundaryVertex(21.6667, -28.0000), BoundaryVertex(20.0667, -28.0000),
      BoundaryVertex(20.0667, -8.0000),
    ],
    'Car': [
      BoundaryVertex(6.0250, -51.0000), BoundaryVertex(11.2500, -51.0000),
      BoundaryVertex(11.2500, -64.0000), BoundaryVertex(9.0333, -75.0000),
      BoundaryVertex(6.0250, -75.0000), BoundaryVertex(6.0250, -51.0000),
    ],
    'Cas': [
      BoundaryVertex(22.5667, 46.0000), BoundaryVertex(3.4167, 46.0000),
      BoundaryVertex(3.4167, 52.0000), BoundaryVertex(3.1583, 59.0000),
      BoundaryVertex(0.0000, 59.0000), BoundaryVertex(23.5833, 59.0000),
      BoundaryVertex(22.8667, 68.0000), BoundaryVertex(0.3333, 68.0000),
      BoundaryVertex(0.0000, 59.0000), BoundaryVertex(22.5667, 46.0000),
    ],
    'Cen': [
      BoundaryVertex(11.0500, -35.0000), BoundaryVertex(15.1667, -35.0000),
      BoundaryVertex(15.1667, -55.0000), BoundaryVertex(14.9167, -64.0000),
      BoundaryVertex(11.8333, -64.0000), BoundaryVertex(11.0500, -55.0000),
      BoundaryVertex(11.0500, -35.0000),
    ],
    'Cep': [
      BoundaryVertex(20.1667, 61.0000), BoundaryVertex(8.0000, 61.0000),
      BoundaryVertex(8.0000, 68.0000), BoundaryVertex(6.1000, 75.5000),
      BoundaryVertex(0.0000, 80.0000), BoundaryVertex(20.1667, 80.0000),
      BoundaryVertex(23.5833, 75.0000), BoundaryVertex(22.8667, 68.0000),
      BoundaryVertex(20.1667, 61.0000),
    ],
    'Cet': [
      BoundaryVertex(23.8333, -6.0000), BoundaryVertex(1.4667, -6.0000),
      BoundaryVertex(1.4667, 10.0000), BoundaryVertex(3.3667, 10.0000),
      BoundaryVertex(3.3667, -0.5000), BoundaryVertex(2.7333, -0.5000),
      BoundaryVertex(2.1000, -24.8333), BoundaryVertex(23.8333, -24.8333),
      BoundaryVertex(23.8333, -6.0000),
    ],
    'Cha': [
      BoundaryVertex(7.6667, -75.0000), BoundaryVertex(13.8333, -75.0000),
      BoundaryVertex(13.8333, -83.1200), BoundaryVertex(7.6667, -83.1200),
      BoundaryVertex(7.6667, -75.0000),
    ],
    'Cir': [
      BoundaryVertex(13.5000, -55.0000), BoundaryVertex(15.5833, -55.0000),
      BoundaryVertex(15.5833, -67.5000), BoundaryVertex(13.5000, -67.5000),
      BoundaryVertex(13.5000, -55.0000),
    ],
    'Col': [
      BoundaryVertex(5.0583, -27.0000), BoundaryVertex(6.5833, -27.0000),
      BoundaryVertex(6.5833, -43.0000), BoundaryVertex(5.0583, -43.0000),
      BoundaryVertex(5.0583, -27.0000),
    ],
    'Com': [
      BoundaryVertex(11.8667, 14.0000), BoundaryVertex(13.5000, 14.0000),
      BoundaryVertex(13.5000, 28.0000), BoundaryVertex(11.8667, 33.3056),
      BoundaryVertex(11.8667, 14.0000),
    ],
    'CrA': [
      BoundaryVertex(17.5000, -37.0000), BoundaryVertex(19.1833, -37.0000),
      BoundaryVertex(19.1833, -45.5000), BoundaryVertex(17.5000, -45.5000),
      BoundaryVertex(17.5000, -37.0000),
    ],
    'CrB': [
      BoundaryVertex(15.2333, 26.0000), BoundaryVertex(16.3667, 26.0000),
      BoundaryVertex(16.3667, 39.7167), BoundaryVertex(15.2333, 39.7167),
      BoundaryVertex(15.2333, 26.0000),
    ],
    'Crv': [
      BoundaryVertex(11.8333, -11.0000), BoundaryVertex(12.5833, -11.0000),
      BoundaryVertex(12.5833, -24.5000), BoundaryVertex(11.8333, -24.5000),
      BoundaryVertex(11.8333, -11.0000),
    ],
    'Crt': [
      BoundaryVertex(10.7500, -6.6667), BoundaryVertex(11.8333, -6.6667),
      BoundaryVertex(11.8333, -24.5000), BoundaryVertex(10.7500, -24.5000),
      BoundaryVertex(10.7500, -6.6667),
    ],
    'Cru': [
      BoundaryVertex(11.8333, -55.6833), BoundaryVertex(12.7917, -55.6833),
      BoundaryVertex(12.7917, -64.0000), BoundaryVertex(11.8333, -64.0000),
      BoundaryVertex(11.8333, -55.6833),
    ],
    'Cyg': [
      BoundaryVertex(19.1083, 28.0000), BoundaryVertex(21.7333, 28.0000),
      BoundaryVertex(21.7333, 44.0000), BoundaryVertex(21.1000, 47.0000),
      BoundaryVertex(21.1000, 55.0000), BoundaryVertex(19.4000, 61.0000),
      BoundaryVertex(19.1083, 55.0000), BoundaryVertex(19.1083, 28.0000),
    ],
    'Del': [
      BoundaryVertex(20.1417, 2.0000), BoundaryVertex(21.0833, 2.0000),
      BoundaryVertex(21.0833, 21.0000), BoundaryVertex(20.1417, 21.0000),
      BoundaryVertex(20.1417, 2.0000),
    ],
    'Dor': [
      BoundaryVertex(3.8667, -49.0000), BoundaryVertex(6.5833, -49.0000),
      BoundaryVertex(6.5833, -69.0000), BoundaryVertex(4.4500, -69.0000),
      BoundaryVertex(3.8667, -57.0000), BoundaryVertex(3.8667, -49.0000),
    ],
    'Dra': [
      BoundaryVertex(9.0333, 54.0000), BoundaryVertex(14.0000, 54.0000),
      BoundaryVertex(15.0750, 54.0000), BoundaryVertex(15.6667, 60.0000),
      BoundaryVertex(17.5000, 55.0000), BoundaryVertex(18.4583, 50.0000),
      BoundaryVertex(20.1667, 61.0000), BoundaryVertex(20.1667, 73.5000),
      BoundaryVertex(15.6667, 80.0000), BoundaryVertex(9.0333, 73.5000),
      BoundaryVertex(9.0333, 54.0000),
    ],
    'Equ': [
      BoundaryVertex(20.8750, 2.0000), BoundaryVertex(21.4583, 2.0000),
      BoundaryVertex(21.4583, 13.0000), BoundaryVertex(20.8750, 13.0000),
      BoundaryVertex(20.8750, 2.0000),
    ],
    'Eri': [
      BoundaryVertex(1.3917, -57.5000), BoundaryVertex(5.1333, -11.0000),
      BoundaryVertex(3.7500, -11.0000), BoundaryVertex(3.3667, -0.5000),
      BoundaryVertex(2.1000, -24.8333), BoundaryVertex(1.3917, -39.5833),
      BoundaryVertex(1.3917, -57.5000),
    ],
    'For': [
      BoundaryVertex(1.7667, -24.0000), BoundaryVertex(3.8667, -24.0000),
      BoundaryVertex(3.8667, -39.5833), BoundaryVertex(1.7667, -39.5833),
      BoundaryVertex(1.7667, -24.0000),
    ],
    'Gem': [
      BoundaryVertex(6.0000, 10.0000), BoundaryVertex(8.1250, 10.0000),
      BoundaryVertex(8.1250, 33.5000), BoundaryVertex(6.0000, 35.0000),
      BoundaryVertex(6.0000, 10.0000),
    ],
    'Gru': [
      BoundaryVertex(21.3333, -37.0000), BoundaryVertex(23.4500, -37.0000),
      BoundaryVertex(23.4500, -57.0000), BoundaryVertex(21.3333, -57.0000),
      BoundaryVertex(21.3333, -37.0000),
    ],
    'Her': [
      BoundaryVertex(15.8167, 4.0000), BoundaryVertex(18.5833, 4.0000),
      BoundaryVertex(18.5833, 28.5000), BoundaryVertex(18.0000, 30.0000),
      BoundaryVertex(17.5000, 37.0000), BoundaryVertex(17.5000, 51.0000),
      BoundaryVertex(15.8167, 51.0000), BoundaryVertex(15.8167, 4.0000),
    ],
    'Hor': [
      BoundaryVertex(2.3667, -40.0000), BoundaryVertex(4.3333, -40.0000),
      BoundaryVertex(4.3333, -67.0000), BoundaryVertex(2.3667, -67.0000),
      BoundaryVertex(2.3667, -40.0000),
    ],
    'Hya': [
      BoundaryVertex(8.1083, -7.0000), BoundaryVertex(14.5250, -7.0000),
      BoundaryVertex(14.5250, -35.0000), BoundaryVertex(8.1083, -35.0000),
      BoundaryVertex(8.1083, -7.0000),
    ],
    'Hyi': [
      BoundaryVertex(23.3333, -58.0000), BoundaryVertex(4.3667, -58.0000),
      BoundaryVertex(4.3667, -82.0000), BoundaryVertex(0.0000, -82.0000),
      BoundaryVertex(23.3333, -75.0000), BoundaryVertex(23.3333, -58.0000),
    ],
    'Ind': [
      BoundaryVertex(20.2833, -45.0000), BoundaryVertex(21.3333, -45.0000),
      BoundaryVertex(23.4500, -45.0000), BoundaryVertex(23.4500, -57.0000),
      BoundaryVertex(21.3333, -57.0000), BoundaryVertex(20.2833, -57.0000),
      BoundaryVertex(20.2833, -75.0000), BoundaryVertex(20.2833, -45.0000),
    ],
    'Lac': [
      BoundaryVertex(22.0000, 35.0000), BoundaryVertex(22.8667, 35.0000),
      BoundaryVertex(22.8667, 56.0000), BoundaryVertex(22.0000, 56.0000),
      BoundaryVertex(22.0000, 35.0000),
    ],
    'Leo': [
      BoundaryVertex(9.3583, 7.0000), BoundaryVertex(11.8667, 7.0000),
      BoundaryVertex(11.8667, 33.3056), BoundaryVertex(9.3583, 33.3056),
      BoundaryVertex(9.3583, 7.0000),
    ],
    'LMi': [
      BoundaryVertex(9.3583, 33.3056), BoundaryVertex(11.0667, 33.3056),
      BoundaryVertex(11.0667, 42.0000), BoundaryVertex(9.3583, 42.0000),
      BoundaryVertex(9.3583, 33.3056),
    ],
    'Lep': [
      BoundaryVertex(4.9250, -11.0000), BoundaryVertex(6.2083, -11.0000),
      BoundaryVertex(6.2083, -27.2833), BoundaryVertex(4.9250, -27.2833),
      BoundaryVertex(4.9250, -11.0000),
    ],
    'Lib': [
      BoundaryVertex(14.3583, -0.5000), BoundaryVertex(16.0250, -0.5000),
      BoundaryVertex(16.0250, -30.0000), BoundaryVertex(14.3583, -30.0000),
      BoundaryVertex(14.3583, -0.5000),
    ],
    'Lup': [
      BoundaryVertex(14.1667, -33.0000), BoundaryVertex(16.5833, -33.0000),
      BoundaryVertex(16.5833, -55.0000), BoundaryVertex(14.1667, -55.0000),
      BoundaryVertex(14.1667, -33.0000),
    ],
    'Lyn': [
      BoundaryVertex(6.3083, 42.0000), BoundaryVertex(9.3583, 42.0000),
      BoundaryVertex(9.3583, 59.0000), BoundaryVertex(6.3083, 59.0000),
      BoundaryVertex(6.3083, 42.0000),
    ],
    'Lyr': [
      BoundaryVertex(18.3083, 26.0000), BoundaryVertex(19.4000, 26.0000),
      BoundaryVertex(19.4000, 47.7139), BoundaryVertex(18.3083, 47.7139),
      BoundaryVertex(18.3083, 26.0000),
    ],
    'Men': [
      BoundaryVertex(3.5000, -70.0000), BoundaryVertex(7.6667, -70.0000),
      BoundaryVertex(7.6667, -85.2611), BoundaryVertex(3.5000, -85.2611),
      BoundaryVertex(3.5000, -70.0000),
    ],
    'Mic': [
      BoundaryVertex(20.4583, -27.0000), BoundaryVertex(21.4667, -27.0000),
      BoundaryVertex(21.4667, -45.0000), BoundaryVertex(20.4583, -45.0000),
      BoundaryVertex(20.4583, -27.0000),
    ],
    'Mon': [
      BoundaryVertex(5.8333, -11.0000), BoundaryVertex(8.0833, -11.0000),
      BoundaryVertex(8.0833, 12.0000), BoundaryVertex(5.8333, 12.0000),
      BoundaryVertex(5.8333, -11.0000),
    ],
    'Mus': [
      BoundaryVertex(11.3000, -64.0000), BoundaryVertex(13.8333, -64.0000),
      BoundaryVertex(13.8333, -75.0000), BoundaryVertex(11.3000, -75.0000),
      BoundaryVertex(11.3000, -64.0000),
    ],
    'Nor': [
      BoundaryVertex(15.7333, -42.0000), BoundaryVertex(16.5833, -42.0000),
      BoundaryVertex(16.5833, -55.0000), BoundaryVertex(15.7333, -55.0000),
      BoundaryVertex(15.7333, -42.0000),
    ],
    'Oct': [
      BoundaryVertex(0.0000, -82.0000), BoundaryVertex(24.0000, -82.0000),
      BoundaryVertex(24.0000, -90.0000), BoundaryVertex(0.0000, -90.0000),
      BoundaryVertex(0.0000, -82.0000),
    ],
    'Oph': [
      BoundaryVertex(16.0250, -8.0000), BoundaryVertex(18.0333, -8.0000),
      BoundaryVertex(18.0333, 2.5000), BoundaryVertex(17.8333, 4.0000),
      BoundaryVertex(17.5000, 10.0000), BoundaryVertex(17.5000, 14.0000),
      BoundaryVertex(16.5333, 14.0000), BoundaryVertex(16.0250, -8.0000),
    ],
    'Ori': [
      BoundaryVertex(4.5000, -11.0000), BoundaryVertex(6.4000, -11.0000),
      BoundaryVertex(6.4000, 22.8750), BoundaryVertex(4.5000, 22.8750),
      BoundaryVertex(4.5000, -11.0000),
    ],
    'Pav': [
      BoundaryVertex(18.1667, -57.0000), BoundaryVertex(21.4667, -57.0000),
      BoundaryVertex(21.4667, -75.0000), BoundaryVertex(18.1667, -75.0000),
      BoundaryVertex(18.1667, -57.0000),
    ],
    'Peg': [
      BoundaryVertex(21.1250, 2.0000), BoundaryVertex(0.1417, 2.0000),
      BoundaryVertex(0.1417, 36.7500), BoundaryVertex(23.5000, 36.7500),
      BoundaryVertex(23.5000, 28.0000), BoundaryVertex(21.7333, 28.0000),
      BoundaryVertex(21.1250, 2.0000),
    ],
    'Per': [
      BoundaryVertex(1.6583, 24.0000), BoundaryVertex(4.5000, 24.0000),
      BoundaryVertex(4.5000, 35.0000), BoundaryVertex(4.5000, 59.0000),
      BoundaryVertex(1.6583, 59.0000), BoundaryVertex(1.6583, 24.0000),
    ],
    'Phe': [
      BoundaryVertex(23.4500, -40.0000), BoundaryVertex(2.1667, -40.0000),
      BoundaryVertex(2.1667, -57.0000), BoundaryVertex(23.4500, -57.0000),
      BoundaryVertex(23.4500, -40.0000),
    ],
    'Pic': [
      BoundaryVertex(4.5333, -43.0000), BoundaryVertex(6.8500, -43.0000),
      BoundaryVertex(6.8500, -64.0000), BoundaryVertex(4.5333, -64.0000),
      BoundaryVertex(4.5333, -43.0000),
    ],
    'Psc': [
      BoundaryVertex(22.8583, -2.0000), BoundaryVertex(2.0583, -2.0000),
      BoundaryVertex(2.0583, 33.2500), BoundaryVertex(0.1417, 33.2500),
      BoundaryVertex(0.1417, 2.0000), BoundaryVertex(23.8333, 2.0000),
      BoundaryVertex(22.8583, -2.0000),
    ],
    'PsA': [
      BoundaryVertex(21.4500, -25.0000), BoundaryVertex(23.0583, -25.0000),
      BoundaryVertex(23.0583, -37.0000), BoundaryVertex(21.4500, -37.0000),
      BoundaryVertex(21.4500, -25.0000),
    ],
    'Pup': [
      BoundaryVertex(6.0250, -37.0000), BoundaryVertex(8.4583, -37.0000),
      BoundaryVertex(8.4583, -51.0000), BoundaryVertex(6.0250, -51.0000),
      BoundaryVertex(6.0250, -37.0000),
    ],
    'Pyx': [
      BoundaryVertex(8.4583, -17.0000), BoundaryVertex(9.4500, -17.0000),
      BoundaryVertex(9.4500, -37.0000), BoundaryVertex(8.4583, -37.0000),
      BoundaryVertex(8.4583, -17.0000),
    ],
    'Ret': [
      BoundaryVertex(3.3333, -53.0000), BoundaryVertex(4.6000, -53.0000),
      BoundaryVertex(4.6000, -67.0000), BoundaryVertex(3.3333, -67.0000),
      BoundaryVertex(3.3333, -53.0000),
    ],
    'Sge': [
      BoundaryVertex(19.0417, 16.0000), BoundaryVertex(20.1417, 16.0000),
      BoundaryVertex(20.1417, 21.0000), BoundaryVertex(19.0417, 21.0000),
      BoundaryVertex(19.0417, 16.0000),
    ],
    'Sgr': [
      BoundaryVertex(17.7500, -12.0333), BoundaryVertex(20.4583, -12.0333),
      BoundaryVertex(20.4583, -27.0000), BoundaryVertex(20.0667, -27.0000),
      BoundaryVertex(20.0667, -37.0000), BoundaryVertex(18.7500, -45.5000),
      BoundaryVertex(17.7500, -45.5000), BoundaryVertex(17.7500, -12.0333),
    ],
    'Sco': [
      BoundaryVertex(15.7500, -8.0000), BoundaryVertex(17.8333, -8.0000),
      BoundaryVertex(17.8333, -30.0000), BoundaryVertex(17.5000, -37.0000),
      BoundaryVertex(16.5833, -45.5000), BoundaryVertex(15.7500, -45.5000),
      BoundaryVertex(15.7500, -8.0000),
    ],
    'Scl': [
      BoundaryVertex(23.0583, -25.0000), BoundaryVertex(1.6583, -25.0000),
      BoundaryVertex(1.6583, -39.5833), BoundaryVertex(23.0583, -39.5833),
      BoundaryVertex(23.0583, -25.0000),
    ],
    'Sct': [
      BoundaryVertex(18.2417, -4.0000), BoundaryVertex(18.9917, -4.0000),
      BoundaryVertex(18.9917, -16.0000), BoundaryVertex(18.2417, -16.0000),
      BoundaryVertex(18.2417, -4.0000),
    ],
    'Ser': [
      // Serpens Caput
      BoundaryVertex(15.0000, 0.0000), BoundaryVertex(16.0833, 0.0000),
      BoundaryVertex(16.0833, 25.5000), BoundaryVertex(15.0000, 25.5000),
      BoundaryVertex(15.0000, 0.0000),
    ],
    'Sex': [
      BoundaryVertex(9.8750, -11.0000), BoundaryVertex(10.5167, -11.0000),
      BoundaryVertex(10.5167, 6.4333), BoundaryVertex(9.8750, 6.4333),
      BoundaryVertex(9.8750, -11.0000),
    ],
    'Tau': [
      BoundaryVertex(3.3667, 0.0000), BoundaryVertex(5.9833, 0.0000),
      BoundaryVertex(5.9833, 31.1000), BoundaryVertex(3.3667, 31.1000),
      BoundaryVertex(3.3667, 0.0000),
    ],
    'Tel': [
      BoundaryVertex(18.1667, -45.5000), BoundaryVertex(20.2833, -45.5000),
      BoundaryVertex(20.2833, -57.0000), BoundaryVertex(18.1667, -57.0000),
      BoundaryVertex(18.1667, -45.5000),
    ],
    'Tri': [
      BoundaryVertex(1.5583, 25.5000), BoundaryVertex(2.5417, 25.5000),
      BoundaryVertex(2.5417, 37.3472), BoundaryVertex(1.5583, 37.3472),
      BoundaryVertex(1.5583, 25.5000),
    ],
    'TrA': [
      BoundaryVertex(14.9167, -60.0000), BoundaryVertex(17.0000, -60.0000),
      BoundaryVertex(17.0000, -70.0000), BoundaryVertex(14.9167, -70.0000),
      BoundaryVertex(14.9167, -60.0000),
    ],
    'Tuc': [
      BoundaryVertex(22.1667, -57.0000), BoundaryVertex(1.3250, -57.0000),
      BoundaryVertex(1.3250, -75.0000), BoundaryVertex(23.3333, -75.0000),
      BoundaryVertex(22.1667, -67.0000), BoundaryVertex(22.1667, -57.0000),
    ],
    'UMa': [
      BoundaryVertex(8.0833, 28.5000), BoundaryVertex(14.5000, 28.5000),
      BoundaryVertex(14.5000, 47.0000), BoundaryVertex(14.0333, 54.0000),
      BoundaryVertex(9.0333, 73.0000), BoundaryVertex(8.0833, 73.0000),
      BoundaryVertex(8.0833, 28.5000),
    ],
    'UMi': [
      BoundaryVertex(0.0000, 66.0000), BoundaryVertex(24.0000, 66.0000),
      BoundaryVertex(24.0000, 90.0000), BoundaryVertex(0.0000, 90.0000),
      BoundaryVertex(0.0000, 66.0000),
    ],
    'Vel': [
      BoundaryVertex(8.0583, -37.0000), BoundaryVertex(11.0583, -37.0000),
      BoundaryVertex(11.0583, -57.0000), BoundaryVertex(8.0583, -57.0000),
      BoundaryVertex(8.0583, -37.0000),
    ],
    'Vir': [
      BoundaryVertex(11.8333, 0.0000), BoundaryVertex(15.0000, 0.0000),
      BoundaryVertex(15.0000, 14.0000), BoundaryVertex(14.0333, 14.0000),
      BoundaryVertex(12.0583, 14.0000), BoundaryVertex(11.8333, 0.0000),
    ],
    'Vol': [
      BoundaryVertex(6.5833, -64.0000), BoundaryVertex(9.0333, -64.0000),
      BoundaryVertex(9.0333, -75.0000), BoundaryVertex(6.5833, -75.0000),
      BoundaryVertex(6.5833, -64.0000),
    ],
    'Vul': [
      BoundaryVertex(19.2167, 19.1667), BoundaryVertex(21.4500, 19.1667),
      BoundaryVertex(21.4500, 29.5000), BoundaryVertex(19.2167, 29.5000),
      BoundaryVertex(19.2167, 19.1667),
    ],
  };
}
