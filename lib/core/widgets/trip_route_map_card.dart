import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import '../utils/google_map_controller_utils.dart';
import '../utils/map_marker_icon.dart';
import 'app_card.dart';
import 'google_map_web_gate.dart';
import 'route_polyline_map_view.dart';
import 'trip_route_fullscreen_map_screen.dart';
import 'trip_route_map_data.dart';

/// Map showing the GPS path for a trip (Hive points or leg polylines).
///
/// For **admins**, pass [adminServerPath] with points from `GET …/route-points`
/// (polled in [RequestDetailsController]) so the trail updates without relying on
/// this device's Hive store.
///
/// Android/iOS use Google Maps; Windows/macOS/Linux/web use OpenStreetMap.
class TripRouteMapCard extends StatefulWidget {
  const TripRouteMapCard({
    super.key,
    required this.request,
    this.adminServerPath,
  });

  final TravelRequestModel request;

  /// When non-null and non-empty, this path is drawn instead of local Hive / leg polylines.
  final List<LatLng>? adminServerPath;

  @override
  State<TripRouteMapCard> createState() => _TripRouteMapCardState();
}

class _TripRouteMapCardState extends State<TripRouteMapCard> {
  GoogleMapController? _mapController;
  bool _mapCreated = false;

  Future<List<List<LatLng>>>? _routeSegmentsFuture;
  String _routePointsCacheKey = '';
  List<List<LatLng>>? _resolvedSegments;

  String _routeDataKey(TravelRequestModel r) =>
      '${r.requestId}|${r.routePointCount}|${r.status}|'
      '${r.tripLegs.map((e) => '${e.legId}:${e.departurePunch?.time}:${e.arrivalPunch?.time}').join(';')}';

  String _adminServerKey(List<LatLng>? p) {
    if (p == null) return 'n';
    if (p.isEmpty) return '0';
    final last = p.last;
    return '${p.length}|${last.latitude}|${last.longitude}';
  }

  String _fullCacheKey() =>
      '${_routeDataKey(widget.request)}|srv:${_adminServerKey(widget.adminServerPath)}|'
      '${widget.request.routePoints.length}';

  bool get _isLiveServer =>
      widget.adminServerPath != null && widget.adminServerPath!.isNotEmpty;

  String get _title =>
      _isLiveServer ? 'Live GPS trail (server)' : 'Route traveled';

  List<LatLng> _flatten(List<List<LatLng>>? segs) {
    if (segs == null) return const [];
    return [for (final s in segs) ...s];
  }

  List<LatLng> _displayPoints(List<LatLng> pts) => mapDisplayRoutePoints(pts);

  void _syncRouteLoad() {
    final key = _fullCacheKey();
    if (key == _routePointsCacheKey) return;
    _routePointsCacheKey = key;

    // Gap-fill server/Hive points — never paint raw admin LatLng chords.
    _resolvedSegments = null;
    _routeSegmentsFuture =
        loadTraveledRoutePointsFilled(widget.request).then((segs) {
      if (!mounted) return segs;
      setState(() => _resolvedSegments = segs);
      return segs;
    });
  }

  @override
  void initState() {
    super.initState();
    _syncRouteLoad();
  }

  @override
  void didUpdateWidget(TripRouteMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRouteLoad();
    if (oldWidget.request.requestId != widget.request.requestId) {
      _releaseMapController();
    }
  }

  void _releaseMapController() {
    safeDisposeGoogleMapController(
      _mapController,
      mapCreated: _mapCreated,
    );
    _mapController = null;
    _mapCreated = false;
  }

  @override
  void dispose() {
    _releaseMapController();
    super.dispose();
  }

  Future<void> _fitCamera(List<LatLng> pts) async {
    final c = _mapController;
    if (c == null || pts.isEmpty) return;

    final display = _displayPoints(pts);
    if (display.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(display.first, 14));
      return;
    }

    var minLat = display.first.latitude;
    var maxLat = minLat;
    var minLng = display.first.longitude;
    var maxLng = minLng;
    for (final p in display) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    const pad = 0.01;
    try {
      await c.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - pad, minLng - pad),
            northeast: LatLng(maxLat + pad, maxLng + pad),
          ),
          56,
        ),
      );
    } catch (_) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(display.first, 12));
    }
  }

  void _openFullscreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripRouteFullscreenMapScreen(
          request: widget.request,
        ),
      ),
    );
  }

  LatLng? _previewCenter() {
    return tripMapStartTarget(widget.request);
  }

  Widget _buildMapBody(List<List<LatLng>>? segments, {bool isLoading = false}) {
    final flattened = _flatten(segments);
    final display =
        flattened.isNotEmpty ? _displayPoints(flattened) : <LatLng>[];
    final center = display.isNotEmpty
        ? display.first
        : (_previewCenter() ?? const LatLng(20.5937, 78.9629));

    final polylines = <Polyline>{};
    if (segments != null) {
      for (var i = 0; i < segments.length; i++) {
        final segDisplay = _displayPoints(segments[i]);
        if (segDisplay.length < 2) continue;
        polylines.add(
          Polyline(
            polylineId: PolylineId('trip_route_$i'),
            points: segDisplay,
            color: AppColors.primary,
            width: 5,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      }
    }

    final startPos = display.isNotEmpty
        ? (tripMapStartMarkerTarget(
              widget.request,
              pathFirst: display.first,
            ) ??
            display.first)
        : null;
    final endPos = display.length > 1
        ? (tripMapEndMarkerTarget(
              widget.request,
              pathLast: display.last,
            ) ??
            display.last)
        : null;

    final markers = <Marker>{
      if (startPos != null)
        Marker(
          markerId: const MarkerId('route_start'),
          position: startPos,
          icon: mapStartMarkerIcon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: const InfoWindow(title: 'Start'),
        ),
      if (endPos != null &&
          startPos != null &&
          (endPos.latitude != startPos.latitude ||
              endPos.longitude != startPos.longitude))
        Marker(
          markerId: const MarkerId('route_end'),
          position: endPos,
          icon: mapEndMarkerIcon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: const InfoWindow(title: 'End'),
        ),
      ...tripStopMarkers(
        widget.request,
        exclude: [
          if (startPos != null) startPos,
          if (endPos != null) endPos,
        ],
      ),
    };

    final stopPts = tripMapStops(widget.request)
        .map((s) => s.position)
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 260,
        child: Stack(
          children: [
            GoogleMapWebGate(
              fallback: RoutePolylineMapView(
                points: display.isNotEmpty ? display : [center],
                height: null,
                stopPoints: stopPts,
              ),
              builder: (context) => GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: center,
                  zoom: 13,
                ),
                polylines: polylines,
                markers: markers,
                onMapCreated: (controller) {
                  _mapController = controller;
                  _mapCreated = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (flattened.isNotEmpty) _fitCamera(flattened);
                  });
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                mapToolbarEnabled: false,
                compassEnabled: true,
              ),
            ),
            if (isLoading)
              const ColoredBox(
                color: Color(0x33FFFFFF),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!isLoading && display.isEmpty)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Material(
                  color: AppColors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'No GPS path to show yet. Path appears after travel legs are completed with live tracking.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.white),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(List<List<LatLng>>? segments, {bool isLoading = false}) {
    final hasPath = segments != null && segments.any((s) => s.length >= 2);

    return AppCard(
      type: AppCardType.elevatedCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.map_outlined,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  style: AppTextStyles.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (hasPath)
                IconButton(
                  tooltip: 'Full screen',
                  icon: const Icon(Icons.fullscreen, color: AppColors.primary),
                  onPressed: _openFullscreen,
                ),
            ],
          ),
          const SizedBox(height: AppConstants.defaultPadding),
          _buildMapBody(segments, isLoading: isLoading),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedSegments != null) {
      return _buildCard(_resolvedSegments);
    }

    return FutureBuilder<List<List<LatLng>>>(
      future: _routeSegmentsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppCard(
            type: AppCardType.outlinedCard,
            child: Text(
              'Could not load route: ${snapshot.error}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildCard(null, isLoading: true);
        }

        final segs = snapshot.data ?? [];
        return _buildCard(segs.isEmpty ? null : segs);
      },
    );
  }
}
