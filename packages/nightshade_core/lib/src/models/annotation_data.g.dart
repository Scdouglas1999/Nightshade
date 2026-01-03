// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'annotation_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ImageAnnotationImpl _$$ImageAnnotationImplFromJson(
        Map<String, dynamic> json) =>
    _$ImageAnnotationImpl(
      imagePath: json['imagePath'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      plateSolve:
          PlateSolveData.fromJson(json['plateSolve'] as Map<String, dynamic>),
      objects: (json['objects'] as List<dynamic>)
          .map((e) =>
              CelestialObjectAnnotation.fromJson(e as Map<String, dynamic>))
          .toList(),
      visible: json['visible'] as bool? ?? true,
    );

Map<String, dynamic> _$$ImageAnnotationImplToJson(
        _$ImageAnnotationImpl instance) =>
    <String, dynamic>{
      'imagePath': instance.imagePath,
      'timestamp': instance.timestamp.toIso8601String(),
      'plateSolve': instance.plateSolve,
      'objects': instance.objects,
      'visible': instance.visible,
    };

_$PlateSolveDataImpl _$$PlateSolveDataImplFromJson(Map<String, dynamic> json) =>
    _$PlateSolveDataImpl(
      ra: (json['ra'] as num).toDouble(),
      dec: (json['dec'] as num).toDouble(),
      pixelScale: (json['pixelScale'] as num).toDouble(),
      rotation: (json['rotation'] as num).toDouble(),
      fieldWidth: (json['fieldWidth'] as num).toDouble(),
      fieldHeight: (json['fieldHeight'] as num).toDouble(),
      imageWidth: (json['imageWidth'] as num).toInt(),
      imageHeight: (json['imageHeight'] as num).toInt(),
    );

Map<String, dynamic> _$$PlateSolveDataImplToJson(
        _$PlateSolveDataImpl instance) =>
    <String, dynamic>{
      'ra': instance.ra,
      'dec': instance.dec,
      'pixelScale': instance.pixelScale,
      'rotation': instance.rotation,
      'fieldWidth': instance.fieldWidth,
      'fieldHeight': instance.fieldHeight,
      'imageWidth': instance.imageWidth,
      'imageHeight': instance.imageHeight,
    };

_$CelestialObjectAnnotationImpl _$$CelestialObjectAnnotationImplFromJson(
        Map<String, dynamic> json) =>
    _$CelestialObjectAnnotationImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      type: $enumDecode(_$ObjectTypeEnumMap, json['type']),
      ra: (json['ra'] as num).toDouble(),
      dec: (json['dec'] as num).toDouble(),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      catalogId: json['catalogId'] as String?,
      commonName: json['commonName'] as String?,
      magnitude: (json['magnitude'] as num?)?.toDouble(),
      size: (json['size'] as num?)?.toDouble(),
      detailedData: json['detailedData'] == null
          ? null
          : ObjectData.fromJson(json['detailedData'] as Map<String, dynamic>),
      visible: json['visible'] as bool? ?? true,
    );

Map<String, dynamic> _$$CelestialObjectAnnotationImplToJson(
        _$CelestialObjectAnnotationImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': _$ObjectTypeEnumMap[instance.type]!,
      'ra': instance.ra,
      'dec': instance.dec,
      'x': instance.x,
      'y': instance.y,
      'catalogId': instance.catalogId,
      'commonName': instance.commonName,
      'magnitude': instance.magnitude,
      'size': instance.size,
      'detailedData': instance.detailedData,
      'visible': instance.visible,
    };

const _$ObjectTypeEnumMap = {
  ObjectType.galaxy: 'galaxy',
  ObjectType.nebula: 'nebula',
  ObjectType.starCluster: 'starCluster',
  ObjectType.planetaryNebula: 'planetaryNebula',
  ObjectType.star: 'star',
  ObjectType.doubleStar: 'doubleStar',
  ObjectType.asterism: 'asterism',
  ObjectType.unknown: 'unknown',
};

_$ObjectDataImpl _$$ObjectDataImplFromJson(Map<String, dynamic> json) =>
    _$ObjectDataImpl(
      description: json['description'] as String?,
      objectClass: json['objectClass'] as String?,
      spectralType:
          $enumDecodeNullable(_$SpectralClassEnumMap, json['spectralType']),
      temperature: (json['temperature'] as num?)?.toDouble(),
      mass: (json['mass'] as num?)?.toDouble(),
      radius: (json['radius'] as num?)?.toDouble(),
      luminosity: (json['luminosity'] as num?)?.toDouble(),
      distance: (json['distance'] as num?)?.toDouble(),
      parallax: (json['parallax'] as num?)?.toDouble(),
      properMotion: json['properMotion'] as String?,
      exoplanets: (json['exoplanets'] as List<dynamic>?)
          ?.map((e) => ExoplanetData.fromJson(e as Map<String, dynamic>))
          .toList(),
      surfaceBrightness: (json['surfaceBrightness'] as num?)?.toDouble(),
      redshift: (json['redshift'] as num?)?.toDouble(),
      morphology: json['morphology'] as String?,
      simbadId: json['simbadId'] as String?,
      wikipediaUrl: json['wikipediaUrl'] as String?,
      catalogIds: (json['catalogIds'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      lastUpdated: json['lastUpdated'] == null
          ? null
          : DateTime.parse(json['lastUpdated'] as String),
      dataSource: json['dataSource'] as String?,
    );

Map<String, dynamic> _$$ObjectDataImplToJson(_$ObjectDataImpl instance) =>
    <String, dynamic>{
      'description': instance.description,
      'objectClass': instance.objectClass,
      'spectralType': _$SpectralClassEnumMap[instance.spectralType],
      'temperature': instance.temperature,
      'mass': instance.mass,
      'radius': instance.radius,
      'luminosity': instance.luminosity,
      'distance': instance.distance,
      'parallax': instance.parallax,
      'properMotion': instance.properMotion,
      'exoplanets': instance.exoplanets,
      'surfaceBrightness': instance.surfaceBrightness,
      'redshift': instance.redshift,
      'morphology': instance.morphology,
      'simbadId': instance.simbadId,
      'wikipediaUrl': instance.wikipediaUrl,
      'catalogIds': instance.catalogIds,
      'lastUpdated': instance.lastUpdated?.toIso8601String(),
      'dataSource': instance.dataSource,
    };

const _$SpectralClassEnumMap = {
  SpectralClass.o: 'o',
  SpectralClass.b: 'b',
  SpectralClass.a: 'a',
  SpectralClass.f: 'f',
  SpectralClass.g: 'g',
  SpectralClass.k: 'k',
  SpectralClass.m: 'm',
  SpectralClass.unknown: 'unknown',
};

_$ExoplanetDataImpl _$$ExoplanetDataImplFromJson(Map<String, dynamic> json) =>
    _$ExoplanetDataImpl(
      name: json['name'] as String,
      mass: (json['mass'] as num?)?.toDouble(),
      radius: (json['radius'] as num?)?.toDouble(),
      orbitalPeriod: (json['orbitalPeriod'] as num?)?.toDouble(),
      semiMajorAxis: (json['semiMajorAxis'] as num?)?.toDouble(),
      eccentricity: (json['eccentricity'] as num?)?.toDouble(),
      discoveryMethod: json['discoveryMethod'] as String?,
      discoveryYear: (json['discoveryYear'] as num?)?.toInt(),
      equilibriumTemp: (json['equilibriumTemp'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$$ExoplanetDataImplToJson(_$ExoplanetDataImpl instance) =>
    <String, dynamic>{
      'name': instance.name,
      'mass': instance.mass,
      'radius': instance.radius,
      'orbitalPeriod': instance.orbitalPeriod,
      'semiMajorAxis': instance.semiMajorAxis,
      'eccentricity': instance.eccentricity,
      'discoveryMethod': instance.discoveryMethod,
      'discoveryYear': instance.discoveryYear,
      'equilibriumTemp': instance.equilibriumTemp,
    };
