import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/distance_service.dart';
import '../utils/google_map_controller_utils.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import 'google_map_web_gate.dart';
import 'route_polyline_map_view.dart';
import 'trip_route_map_data.dart';
import '../services/background_location_service.dart';
import '../../features/tracking/data/services/websocket_tracking_service.dart';
import '../di/service_locator.dart';

/// Fullscreen map: actual GPS path and optional Google-style driving alternatives.
class TripRouteFullscreenMapScreen extends StatefulWidget {
  const TripRouteFullscreenMapScreen({
    super.key,
    required this.request,
    this.initialDrivingTab = false,
    this.useGoogleMaps,
  });

  final TravelRequestModel request;
  final bool initialDrivingTab;
  final bool? useGoogleMaps;

  @override
  State<TripRouteFullscreenMapScreen> createState() =>
      _TripRouteFullscreenMapScreenState();
}

class _TripRouteFullscreenMapScreenState
    extends State<TripRouteFullscreenMapScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _controller;
  bool _mapCreated = false;
  late TabController _tabs;

  List<List<LatLng>> _legPaths = [];
  bool _traveledLoading = true;
  String? _traveledError;
  BackgroundLocationService? _bgLocationService;
  StreamSubscription? _wsLocationSub;
  StreamSubscription? _wsConnSub;

  final _distanceService = DistanceService();

  static const List<Color> _legColors = [
    AppColors.primary,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.brown,
    Colors.indigo,
  ];

  int get _tabCount {
    if (widget.request.tripLegs.isEmpty) return 1; // Path traveled
    return 1 + widget.request.tripLegs.length; // Whole route, N legs
  }

  List<String> get _tabLabels {
    final labels = <String>['Whole route'];
    if (widget.request.tripLegs.isNotEmpty) {
      for (var i = 0; i < widget.request.tripLegs.length; i++) {
        final leg = widget.request.tripLegs[i];
        if (leg.isReturnLeg) {
          labels.add('Return route');
        } else {
          labels.add('Leg ${i + 1}');
        }
      }
    } else {
      labels[0] = 'Path traveled';
    }
    return labels;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _tabCount,
      vsync: this,
      initialIndex: widget.initialDrivingTab ? _tabCount - 1 : 0,
    );
    _tabs.addListener(_onTabChanged);

    if (ServiceLocator.I.has<BackgroundLocationService>()) {
      _bgLocationService = ServiceLocator.I.get<BackgroundLocationService>();
      _bgLocationService?.pointsBuffered.addListener(_onLocalPointsUpdated);
    }

    if (ServiceLocator.I.has<WebSocketTrackingService>()) {
      final ws = ServiceLocator.I.get<WebSocketTrackingService>();
      if (!ws.isConnected && !ws.isBackendUnavailable) {
        unawaited(ws.connect());
      }
      ws.joinTripRoom(widget.request.requestId);
      
      _wsLocationSub = ws.locationUpdates.listen((payload) {
        final tid = payload['tripId'] ?? payload['requestId'];
        if (tid == widget.request.requestId) {
          final lat = (payload['latitude'] as num?)?.toDouble();
          final lng = (payload['longitude'] as num?)?.toDouble();
          final legId = payload['legId']?.toString();
          if (lat != null && lng != null) {
            final latLng = LatLng(lat, lng);
            _onLiveLocationReceived(latLng, legId);
          }
        } else {
        }
      });
      _wsConnSub = ws.connectionStream.listen((connected) {
        if (connected) {
          ws.joinTripRoom(widget.request.requestId);
        }
      });
    } else {
    }

    _loadTraveled();
  }

  void _onLocalPointsUpdated() {
    if (_bgLocationService?.activeRequestId == widget.request.requestId) {
      evictRoutePointsCache(widget.request.requestId);
      _loadTraveled();
    }
  }

  void _onLiveLocationReceived(LatLng point, String? legId) {
    if (!mounted) return;
    setState(() {
      if (_legPaths.isEmpty) {
        _legPaths = [[point]];
        return;
      }
      
      if (legId != null && legId.isNotEmpty) {
        final legIndex = widget.request.tripLegs.indexWhere((l) => l.legId == legId);
        if (legIndex >= 0 && legIndex < _legPaths.length) {
          final path = _legPaths[legIndex];
          if (path.isEmpty || path.last != point) {
            _legPaths[legIndex] = [...path, point];
          }
          return;
        }
      }
      
      final activeIndex = widget.request.currentLegIndex;
      final targetIndex = activeIndex.clamp(0, _legPaths.length - 1);
      final path = _legPaths[targetIndex];
      if (path.isEmpty || path.last != point) {
        _legPaths[targetIndex] = [...path, point];
      }
    });
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    final pts = _pointsForTab(_tabs.index);
    if (pts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitCamera(pts));
    }
  }

  List<LatLng> _pointsForTab(int index) {
    if (_legPaths.isEmpty) return [];
    if (index == 0) {
      final all = <LatLng>[];
      for (final p in _legPaths) {
        all.addAll(p);
      }
      return all;
    }
    final legIndex = index - 1;
    if (legIndex >= 0 && legIndex < _legPaths.length) {
      return _legPaths[legIndex];
    }
    return [];
  }

  Future<void> _loadTraveled() async {
    setState(() {
      _traveledLoading = true;
      _traveledError = null;
    });
    try {
      final paths = await loadTraveledLegPoints(widget.request);
      if (!mounted) return;
      setState(() {
        _legPaths = paths;
        _traveledLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fitCamera(_pointsForTab(_tabs.index));
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _traveledError = '$e';
        _traveledLoading = false;
      });
    }
  }

  Future<void> _fitCamera(List<LatLng> pts) async {
    final c = _controller;
    if (c == null || pts.isEmpty) return;

    if (pts.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 14));
      return;
    }

    var minLat = pts.first.latitude;
    var maxLat = minLat;
    var minLng = pts.first.longitude;
    var maxLng = minLng;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    final latDelta = maxLat - minLat;
    final lngDelta = maxLng - minLng;
    final padLat = (latDelta * 0.15).clamp(0.0006, 0.015);
    final padLng = (lngDelta * 0.15).clamp(0.0006, 0.015);

    try {
      await c.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - padLat, minLng - padLng),
            northeast: LatLng(maxLat + padLat, maxLng + padLng),
          ),
          72,
        ),
      );
    } catch (_) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
    }
  }

  @override
  void dispose() {
    _bgLocationService?.pointsBuffered.removeListener(_onLocalPointsUpdated);
    _wsLocationSub?.cancel();
    _wsConnSub?.cancel();
    if (ServiceLocator.I.has<WebSocketTrackingService>()) {
      try {
        ServiceLocator.I.get<WebSocketTrackingService>().leaveTripRoom(widget.request.requestId);
      } catch (_) {}
    }
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    safeDisposeGoogleMapController(_controller, mapCreated: _mapCreated);
    _controller = null;
    _mapCreated = false;
    super.dispose();
  }

  Set<Polyline> _traveledPolylines(int tabIndex) {
    if (_legPaths.isEmpty) return {};

    if (tabIndex == 0) {
      final set = <Polyline>{};
      for (var i = 0; i < _legPaths.length; i++) {
        final pts = _legPaths[i];
        if (pts.length < 2) continue;
        set.add(
          Polyline(
            polylineId: PolylineId('traveled_$i'),
            points: pts,
            color: _legColors[i % _legColors.length],
            width: 6,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        );
      }
      return set;
    } else {
      final legIndex = tabIndex - 1;
      if (legIndex >= 0 && legIndex < _legPaths.length) {
        final pts = _legPaths[legIndex];
        if (pts.length < 2) return {};
        return {
          Polyline(
            polylineId: PolylineId('traveled_leg_$legIndex'),
            points: pts,
            color: _legColors[legIndex % _legColors.length],
            width: 6,
            jointType: JointType.round,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
          ),
        };
      }
    }
    return {};
  }

  Set<Marker> _traveledMarkers(int tabIndex) {
    final pts = _pointsForTab(tabIndex);

    String startTitle = 'Start';
    String endTitle = 'End';
    LatLng? startPos;
    LatLng? endPos;

    if (pts.isNotEmpty) {
      startPos = pts.first;
      endPos = pts.length > 1 ? pts.last : null;
    }

    if (tabIndex > 0) {
      final legIndex = tabIndex - 1;
      if (legIndex >= 0 && legIndex < widget.request.tripLegs.length) {
        final leg = widget.request.tripLegs[legIndex];
        startTitle = 'Start: ${leg.fromLocation}';
        endTitle = 'End: ${leg.toLocation}';

        if (startPos == null && leg.departurePunch != null) {
          startPos = LatLng(
              leg.departurePunch!.latitude, leg.departurePunch!.longitude);
        }
        if (endPos == null && leg.arrivalPunch != null) {
          endPos =
              LatLng(leg.arrivalPunch!.latitude, leg.arrivalPunch!.longitude);
        }
      }
    } else if (startPos == null) {
      final ends = tripDrivingEndpoints(widget.request);
      startPos = ends.origin;
      endPos = ends.dest;
    }

    if (startPos == null) return {};

    return {
      Marker(
        markerId: const MarkerId('t_start'),
        position: startPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: startTitle),
      ),
      if (endPos != null && endPos != startPos)
        Marker(
          markerId: const MarkerId('t_end'),
          position: endPos,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: endTitle),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Route map',
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: _tabCount > 1
            ? TabBar(
                controller: _tabs,
                isScrollable: _tabCount > 2,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: _tabLabels.map((t) => Tab(text: t)).toList(),
              )
            : null,
      ),
      body: _tabCount > 1
          ? TabBarView(
              controller: _tabs,
              physics: NeverScrollableScrollPhysics(),
              children: List.generate(_tabCount, (index) {
                final markers = _traveledMarkers(index);
                final pts = _pointsForTab(index);
                final allPts = pts.isNotEmpty
                    ? pts
                    : markers.map((m) => m.position).toList();

                return _buildMapTab(
                  loading: _traveledLoading,
                  error: _traveledError,
                  emptyMessage: index == 0
                      ? 'No GPS path yet.'
                      : 'No GPS path for this leg.',
                  polylines: _traveledPolylines(index),
                  markers: markers,
                  initialTarget: allPts.isNotEmpty
                      ? allPts.first
                      : const LatLng(20.5937, 78.9629),
                  onReadyFit: () => _fitCamera(allPts),
                );
              }),
            )
          : (() {
              final markers = _traveledMarkers(0);
              final pts = _pointsForTab(0);
              final allPts = pts.isNotEmpty
                  ? pts
                  : markers.map((m) => m.position).toList();

              return _buildMapTab(
                loading: _traveledLoading,
                error: _traveledError,
                emptyMessage: 'No GPS path yet.',
                polylines: _traveledPolylines(0),
                markers: markers,
                initialTarget: allPts.isNotEmpty
                    ? allPts.first
                    : const LatLng(20.5937, 78.9629),
                onReadyFit: () => _fitCamera(allPts),
              );
            })(),
    );
  }

  Widget _buildMapTab({
    required bool loading,
    required String? error,
    required String emptyMessage,
    required Set<Polyline> polylines,
    required Set<Marker> markers,
    required LatLng initialTarget,
    required VoidCallback onReadyFit,
  }) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.white),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
          ),
        ),
      );
    }
    return Stack(
      children: [
        GoogleMapWebGate(
          fallback: RoutePolylineMapView(
            points: polylines.isNotEmpty
                ? List<LatLng>.from(polylines.first.points)
                : (markers.isNotEmpty
                    ? [markers.first.position]
                    : [initialTarget]),
            height: null,
          ),
          builder: (context) => GoogleMap(
            initialCameraPosition:
                CameraPosition(target: initialTarget, zoom: 12),
            polylines: polylines,
            markers: markers,
            onMapCreated: (c) {
              _controller = c;
              _mapCreated = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => onReadyFit());
            },
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
            compassEnabled: true,
          ),
        ),
        if (polylines.isEmpty)
          Positioned(
            top: 24,
            left: 24,
            right: 24,
            child: Material(
              color: AppColors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  emptyMessage,
                  textAlign: TextAlign.center,
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
