import 'package:flutter_map/flutter_map.dart';

/// Shared basemap tiles — Carto CDN is faster than the main OSM tile server.
TileLayer appMapTileLayer() => TileLayer(
      urlTemplate:
          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
      subdomains: const ['a', 'b', 'c', 'd'],
      userAgentPackageName: 'com.rayzonsolar.triptrack',
      panBuffer: 1,
      keepBuffer: 2,
    );
