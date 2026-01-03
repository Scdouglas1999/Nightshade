# Planetarium API Reference

The Planetarium API provides sky rendering, catalog management, and astronomical calculations.

## Sky View

### SkyView

Main sky view widget for rendering the celestial sphere.

```dart
SkyView({
  required double ra,
  required double dec,
  required double fov,
  required DateTime time,
  required ObserverLocation location,
  // ... other parameters
})
```

## Celestial Objects

### CelestialObject

Base class for celestial objects (stars, deep sky objects, planets, etc.).

```dart
abstract class CelestialObject {
  final double ra;
  final double dec;
  final double magnitude;
  final String name;
  // ... other properties
}
```

## Catalogs

### Catalog

Base class for astronomical catalogs.

```dart
abstract class Catalog<T extends CelestialObject> {
  Future<List<T>> loadObjects();
  Future<List<T>> searchObjects(String query);
  Future<List<T>> getObjectsInRegion(double ra, double dec, double radius);
}
```

### Star Catalog

Star catalog implementations (Hipparcos, Tycho, etc.).

```dart
class HygStarCatalog extends Catalog<Star> {
  Future<List<Star>> loadObjects();
}
```

### Deep Sky Object Catalog

DSO catalog implementations (NGC, IC, Messier, etc.).

```dart
class OpenNgcDsoCatalog extends Catalog<DeepSkyObject> {
  Future<List<DeepSkyObject>> loadObjects();
}
```

### CatalogManager

Manages multiple catalogs.

```dart
class CatalogManager {
  Future<void> loadCatalogs();
  List<Catalog> getCatalogs();
  Catalog? getCatalog(String name);
}
```

## Astronomy Calculations

### AstronomyCalculations

Astronomical calculation utilities.

```dart
class AstronomyCalculations {
  static double calculateAltitude(double ra, double dec, DateTime time, ObserverLocation location);
  static double calculateAzimuth(double ra, double dec, DateTime time, ObserverLocation location);
  static double calculateHourAngle(double ra, DateTime time, ObserverLocation location);
  static double calculateLst(DateTime time, ObserverLocation location);
  // ... other calculations
}
```

### PlanetaryPositions

Planetary position calculations.

```dart
class PlanetaryPositions {
  static (double ra, double dec) getPlanetPosition(String planet, DateTime time);
}
```

### MilkyWayData

Milky Way rendering data.

## Rendering

### SkyRenderer

GPU-based sky renderer.

```dart
class SkyRenderer {
  void renderSky({
    required double ra,
    required double dec,
    required double fov,
    required DateTime time,
    required ObserverLocation location,
  });
}
```

## Services

### SurveyImageService

Service for survey image overlay.

```dart
class SurveyImageService {
  Future<Image?> getSurveyImage(double ra, double dec, double fov);
}
```

### MosaicPlanner

Service for planning mosaic images.

```dart
class MosaicPlanner {
  List<MosaicTile> planMosaic({
    required double centerRa,
    required double centerDec,
    required double totalFov,
    required double cameraFov,
    required double overlap,
  });
}
```

### GeolocationService

Service for geolocation.

```dart
class GeolocationService {
  static Future<(double latitude, double longitude, String? locationName)?> fetchLocationFromInternet();
  static Future<(double latitude, double longitude, String? locationName)?> fetchLocationFromGPS();
}
```

## Planning

### TargetScoring

Target scoring for planning.

```dart
class TargetScoring {
  static double scoreTarget({
    required double ra,
    required double dec,
    required DateTime time,
    required ObserverLocation location,
    required double minAltitude,
  });
}
```

## Providers

Planetarium providers for state management:

- `planetariumProviders` - Planetarium state
- `catalogProviders` - Catalog management
- `planningProviders` - Planning operations
- `targetQueueProvider` - Target queue management

## Widgets

### InteractiveSkyView

Interactive sky view widget with pan/zoom.

```dart
InteractiveSkyView({
  required double initialRa,
  required double initialDec,
  required double initialFov,
  // ... other parameters
})
```

### FramingView

Framing view for planning images.

```dart
FramingView({
  required double ra,
  required double dec,
  required double fov,
  // ... other parameters
})
```

## Coordinate Systems

### CoordinateSystem

Coordinate system conversions.

```dart
class CoordinateSystem {
  static (double ra, double dec) altAzToEquatorial(double alt, double az, DateTime time, ObserverLocation location);
  static (double alt, double az) equatorialToAltAz(double ra, double dec, DateTime time, ObserverLocation location);
  static (double x, double y) equatorialToScreen(double ra, double dec, double centerRa, double centerDec, double fov);
  static (double ra, double dec) screenToEquatorial(double x, double y, double centerRa, double centerDec, double fov);
}
```

## Example Usage

```dart
// Load star catalog
final catalog = HygStarCatalog();
final stars = await catalog.loadObjects();

// Calculate target altitude
final altitude = AstronomyCalculations.calculateAltitude(
  ra: 5.5,
  dec: -5.0,
  time: DateTime.now(),
  location: ObserverLocation(
    latitude: 40.0,
    longitude: -105.0,
    elevation: 1600.0,
  ),
);

// Render sky view
SkyView(
  ra: 5.5,
  dec: -5.0,
  fov: 5.0,
  time: DateTime.now(),
  location: location,
);
```

