import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:latlong2/latlong.dart' as ll;

import '../theme/app_colors.dart';
import '../utils/route_point_simplify.dart';
import 'app_map_tile_layer.dart';

/// OpenStreetMap route trail for Windows, macOS, Linux, and web.
class RoutePolylineMapView extends StatefulWidget {
  const RoutePolylineMapView({
    super.key,
    required this.points,
    this.height = 260,
    this.lineColor,
    this.showEndpoints = true,
    this.extraPolylines = const [],
    this.simplify = true,
    this.initialCenterOnFirstPoint = false,
  });

  final List<LatLng> points;
  final double? height;
  final Color? lineColor;
  final bool showEndpoints;
  final bool simplify;
  final bool initialCenterOnFirstPoint;

  /// Additional paths (e.g. driving alternatives) drawn under the main trail.
  final List<({List<LatLng> points, Color color, double width})> extraPolylines;

  @override
  State<RoutePolylineMapView> createState() => _RoutePolylineMapViewState();
}

class _RoutePolylineMapViewState extends State<RoutePolylineMapView> {
  final MapController _mapController = MapController();
  List<ll.LatLng> _primary = const [];
  List<Polyline> _extraLines = const [];
  ll.LatLng _initialCenter = const ll.LatLng(23.0225, 72.5714);
  double _initialZoom = 12;
  bool _didInitialFit = false;

  @override
  void initState() {
    super.initState();
    _rebuildGeometry();
  }

  @override
  void didUpdateWidget(RoutePolylineMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.points != widget.points ||
        oldWidget.extraPolylines != widget.extraPolylines ||
        oldWidget.simplify != widget.simplify ||
        oldWidget.initialCenterOnFirstPoint != widget.initialCenterOnFirstPoint) {
      _rebuildGeometry();
      _didInitialFit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitBounds());
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  List<ll.LatLng> _toLatLong2(List<LatLng> pts) =>
      pts.map((p) => ll.LatLng(p.latitude, p.longitude)).toList();

  void _rebuildGeometry() {
    final raw = widget.simplify
        ? simplifyRoutePointsForMap(widget.points)
        : widget.points;
    _primary = _toLatLong2(raw);
    _extraLines = [
      for (final line in widget.extraPolylines)
        Polyline(
          points: _toLatLong2(
            widget.simplify
                ? simplifyRoutePointsForMap(line.points)
                : line.points,
          ),
          color: line.color,
          strokeWidth: line.width,
        ),
    ];
    final camera = widget.initialCenterOnFirstPoint && _primary.isNotEmpty
        ? (_primary.first, 14.0)
        : _estimateCamera([
            ..._primary,
            for (final line in _extraLines) ...line.points,
          ]);
    _initialCenter = camera.$1;
    _initialZoom = camera.$2;
  }

  (ll.LatLng, double) _estimateCamera(List<ll.LatLng> points) {
    if (points.isEmpty) return (const ll.LatLng(23.0225, 72.5714), 12);
    if (points.length == 1) return (points.first, 14);

    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final center = ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final latSpan = (maxLat - minLat).abs().clamp(0.001, 90.0);
    final lngSpan = (maxLng - minLng).abs().clamp(0.001, 180.0);
    final span = math.max(latSpan, lngSpan);
    final zoom = (math.log(360 / span) / math.ln2 - 0.8).clamp(4.0, 16.0);
    return (center, zoom);
  }

  void _fitBounds() {
    if (_didInitialFit) return;
    final all = <ll.LatLng>[
      ..._primary,
      for (final line in _extraLines) ...line.points,
    ];
    if (all.isEmpty) return;

    if (all.length == 1 || widget.initialCenterOnFirstPoint) {
      _mapController.move(all.first, widget.initialCenterOnFirstPoint ? 14 : 14);
    } else {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(all),
          padding: const EdgeInsets.all(40),
        ),
      );
    }
    _didInitialFit = true;
  }

  Widget _endpointDot(Color color) => Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_primary.isEmpty) return const SizedBox.shrink();

    final map = FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _initialCenter,
        initialZoom: _initialZoom,
        onMapReady: _fitBounds,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all,
        ),
      ),
      children: [
        appMapTileLayer(),
        if (_extraLines.isNotEmpty) PolylineLayer(polylines: _extraLines),
        if (_primary.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _primary,
                color: widget.lineColor ?? AppColors.primary,
                strokeWidth: 4,
              ),
            ],
          ),
        if (widget.showEndpoints)
          MarkerLayer(
            markers: [
              Marker(
                point: _primary.first,
                width: 20,
                height: 20,
                child: _endpointDot(Colors.green),
              ),
              if (_primary.length > 1)
                Marker(
                  point: _primary.last,
                  width: 20,
                  height: 20,
                  child: _endpointDot(Colors.red),
                ),
            ],
          ),
      ],
    );

    final height = widget.height;
    if (height != null) {
      return SizedBox(height: height, child: map);
    }
    return map;
  }
}
