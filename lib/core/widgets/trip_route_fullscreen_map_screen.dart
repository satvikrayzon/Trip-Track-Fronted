import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../utils/google_map_controller_utils.dart';
import '../utils/geo_utils.dart';
import '../utils/route_point_simplify.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import 'google_map_web_gate.dart';
import 'route_polyline_map_view.dart';
import 'trip_route_map_data.dart';
import '../services/background_location_service.dart';
import '../services/gps_gap_road_fill.dart';
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

  List<List<List<LatLng>>> _legPaths = [];
  List<List<LatLng>> _wholePath = [];
  bool _traveledLoading = true;
  String? _traveledError;
  BackgroundLocationService? _bgLocationService;
  StreamSubscription? _wsLocationSub;
  StreamSubscription? _wsConnSub;

  static const List<Color> _legColors = AppColors.legTrailColors;

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

  Timer? _localPointsDebounce;
  int _loadGeneration = 0;
  bool _userMovedCamera = false;
  bool _initialFitDone = false;

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
        }
      });
      _wsConnSub = ws.connectionStream.listen((connected) {
        if (connected) {
          ws.joinTripRoom(widget.request.requestId);
        }
      });
    }

    _loadTraveled(isInitial: true);
  }

  void _onLocalPointsUpdated() {
    if (_bgLocationService?.activeRequestId != widget.request.requestId) {
      return;
    }
    _localPointsDebounce?.cancel();
    _localPointsDebounce = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      evictRoutePointsCache(widget.request.requestId);
      _loadTraveled(isInitial: false);
    });
  }

  void _appendLivePoint(int legIndex, LatLng point) {
    if (legIndex < 0 || legIndex >= _legPaths.length) return;
    final segments = _legPaths[legIndex];
    if (segments.isEmpty) {
      _legPaths[legIndex] = [
        [point],
      ];
      return;
    }
    final lastSeg = segments.last;
    if (lastSeg.isNotEmpty && lastSeg.last == point) return;
    if (lastSeg.isNotEmpty) {
      final prev = lastSeg.last;
      final jump = GeoUtils.distanceMeters(
        prev.latitude,
        prev.longitude,
        point.latitude,
        point.longitude,
      );
      // Never paint a live chord across a kill/reopen hop — soft reload.
      if (jump > GpsGapRoadFill.breakChordMeters) {
        evictRoutePointsCache(widget.request.requestId);
        unawaited(_loadTraveled(isInitial: false));
        return;
      }
    }
    _legPaths[legIndex] = [
      ...segments.sublist(0, segments.length - 1),
      [...lastSeg, point],
    ];
  }

  void _onLiveLocationReceived(LatLng point, String? legId) {
    if (!mounted) return;
    setState(() {
      // Keep Whole route tip flowing (tab 0 paints _wholePath).
      if (_wholePath.isEmpty) {
        _wholePath = [
          [point],
        ];
      } else {
        final lastSeg = _wholePath.last;
        if (lastSeg.isEmpty || lastSeg.last != point) {
          final prev = lastSeg.isEmpty ? null : lastSeg.last;
          final jump = prev == null
              ? 0.0
              : GeoUtils.distanceMeters(
                  prev.latitude,
                  prev.longitude,
                  point.latitude,
                  point.longitude,
                );
          if (jump > GpsGapRoadFill.breakChordMeters) {
            evictRoutePointsCache(widget.request.requestId);
            unawaited(_loadTraveled(isInitial: false));
          } else if (jump >= 4 || prev == null) {
            _wholePath = [
              ..._wholePath.sublist(0, _wholePath.length - 1),
              [...lastSeg, point],
            ];
          }
        }
      }

      if (_legPaths.isEmpty) {
        _legPaths = [
          [
            [point],
          ],
        ];
        return;
      }

      if (legId != null && legId.isNotEmpty) {
        final legIndex =
            widget.request.tripLegs.indexWhere((l) => l.legId == legId);
        if (legIndex >= 0 && legIndex < _legPaths.length) {
          _appendLivePoint(legIndex, point);
          return;
        }
      }

      final activeIndex = widget.request.currentLegIndex;
      final targetIndex = activeIndex.clamp(0, _legPaths.length - 1);
      _appendLivePoint(targetIndex, point);
    });
    if (!_userMovedCamera) {
      final c = _controller;
      if (c != null) {
        unawaited(c.animateCamera(CameraUpdate.newLatLng(point)));
      }
    }
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    final pts = _pointsForTab(_tabs.index);
    if (pts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitCamera(pts));
    }
  }

  List<LatLng> _pointsForTab(int index) {
    if (index == 0) {
      if (_legPaths.isNotEmpty) {
        return [
          for (final leg in _legPaths)
            for (final seg in leg) ...seg,
        ];
      }
      return [for (final seg in _wholePath) ...seg];
    }
    if (_legPaths.isEmpty) return [];
    final legIndex = index - 1;
    if (legIndex >= 0 && legIndex < _legPaths.length) {
      return [
        for (final seg in _legPaths[legIndex]) ...seg,
      ];
    }
    return [];
  }

  Future<void> _loadTraveled({bool isInitial = false}) async {
    final gen = ++_loadGeneration;
    // Only show blocking loader on first open — never unmount map on live ticks.
    if (isInitial || (_wholePath.isEmpty && _legPaths.isEmpty)) {
      setState(() {
        _traveledLoading = true;
        _traveledError = null;
      });
    }
    try {
      final whole = await loadWholeTripPathFilled(widget.request);
      final paths = await loadTraveledLegPoints(widget.request);
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _wholePath = whole;
        _legPaths = paths;
        _traveledLoading = false;
        _traveledError = null;
      });
      if (!_userMovedCamera && (!_initialFitDone || isInitial)) {
        _initialFitDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fitCamera(_pointsForTab(_tabs.index));
        });
      }
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
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
    _localPointsDebounce?.cancel();
    _bgLocationService?.pointsBuffered.removeListener(_onLocalPointsUpdated);
    _wsLocationSub?.cancel();
    _wsConnSub?.cancel();
    if (ServiceLocator.I.has<WebSocketTrackingService>()) {
      try {
        ServiceLocator.I
            .get<WebSocketTrackingService>()
            .leaveTripRoom(widget.request.requestId);
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
    if (tabIndex == 0) {
      // Whole route: prefer ONE chronological road-aligned path, then color by
      // leg time windows — avoids stacking overlapping per-leg "extra lines".
      final set = <Polyline>{};
      if (_wholePath.isNotEmpty) {
        final flat = [for (final seg in _wholePath) ...seg];
        if (flat.length >= 2) {
          final colored = _colorWholePathByLegs(flat);
          for (var i = 0; i < colored.length; i++) {
            final piece = colored[i];
            if (piece.points.length < 2) continue;
            final pieces = mapDisplayRouteSegments(
              piece.points,
              maxEdgeMeters: kAlignedMapMaxEdgeMeters,
            );
            for (var p = 0; p < pieces.length; p++) {
              final display = pieces[p];
              if (display.length < 2) continue;
              set.add(
                Polyline(
                  polylineId: PolylineId('traveled_whole_${i}_$p'),
                  points: display,
                  color: piece.color,
                  width: 6,
                  jointType: JointType.round,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                ),
              );
            }
          }
          return set;
        }
      }
      if (_legPaths.isNotEmpty) {
        for (var i = 0; i < _legPaths.length; i++) {
          final color = _legColors[i % _legColors.length];
          for (var s = 0; s < _legPaths[i].length; s++) {
            final pieces = mapDisplayRouteSegments(
              _legPaths[i][s],
              maxEdgeMeters: kAlignedMapMaxEdgeMeters,
            );
            for (var p = 0; p < pieces.length; p++) {
              final display = pieces[p];
              if (display.length < 2) continue;
              set.add(
                Polyline(
                  polylineId: PolylineId('traveled_whole_${i}_${s}_$p'),
                  points: display,
                  color: color,
                  width: 6,
                  jointType: JointType.round,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                ),
              );
            }
          }
        }
        return set;
      }
      return set;
    }

    if (_legPaths.isEmpty) return {};
    final legIndex = tabIndex - 1;
    if (legIndex >= 0 && legIndex < _legPaths.length) {
      final color = _legColors[legIndex % _legColors.length];
      final set = <Polyline>{};
      for (var s = 0; s < _legPaths[legIndex].length; s++) {
        final pieces = mapDisplayRouteSegments(
          _legPaths[legIndex][s],
          maxEdgeMeters: kAlignedMapMaxEdgeMeters,
        );
        for (var p = 0; p < pieces.length; p++) {
          final pts = pieces[p];
          if (pts.length < 2) continue;
          set.add(
            Polyline(
              polylineId: PolylineId('traveled_leg_${legIndex}_${s}_$p'),
              points: pts,
              color: color,
              width: 6,
              jointType: JointType.round,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
            ),
          );
        }
      }
      return set;
    }
    return {};
  }

  /// Split one chronological trail into per-leg colors without stacking overlays.
  List<({List<LatLng> points, Color color})> _colorWholePathByLegs(
    List<LatLng> flat,
  ) {
    final legCount = widget.request.tripLegs.isNotEmpty
        ? widget.request.tripLegs.length
        : (_legPaths.isNotEmpty ? _legPaths.length : 1);
    if (legCount <= 1 || flat.length < 4) {
      return [
        (points: flat, color: _legColors[0]),
      ];
    }

    // Prefer proportional split by each leg's own path length when available.
    final weights = <double>[];
    for (var i = 0; i < legCount; i++) {
      var w = 0.0;
      if (i < _legPaths.length) {
        for (final seg in _legPaths[i]) {
          for (var j = 1; j < seg.length; j++) {
            w += GeoUtils.distanceMeters(
              seg[j - 1].latitude,
              seg[j - 1].longitude,
              seg[j].latitude,
              seg[j].longitude,
            );
          }
        }
      }
      weights.add(w > 1 ? w : 1.0);
    }
    final weightSum = weights.fold<double>(0, (a, b) => a + b);

    final totalM = <double>[0];
    for (var i = 1; i < flat.length; i++) {
      totalM.add(
        totalM.last +
            GeoUtils.distanceMeters(
              flat[i - 1].latitude,
              flat[i - 1].longitude,
              flat[i].latitude,
              flat[i].longitude,
            ),
      );
    }
    final pathLen = totalM.last;
    if (pathLen < 1) {
      return [(points: flat, color: _legColors[0])];
    }

    final out = <({List<LatLng> points, Color color})>[];
    var cursor = 0.0;
    var startIdx = 0;
    for (var leg = 0; leg < legCount; leg++) {
      final share = weights[leg] / weightSum;
      final target = leg == legCount - 1
          ? pathLen
          : (cursor + share * pathLen).clamp(0.0, pathLen).toDouble();
      cursor = target;
      var endIdx = startIdx;
      while (endIdx < flat.length - 1 && totalM[endIdx] < target) {
        endIdx++;
      }
      if (leg == legCount - 1) endIdx = flat.length - 1;
      if (endIdx <= startIdx) {
        endIdx = (startIdx + 1).clamp(0, flat.length - 1);
      }
      final slice = flat.sublist(startIdx, endIdx + 1);
      if (slice.length >= 2) {
        out.add((
          points: slice,
          color: _legColors[leg % _legColors.length],
        ));
      }
      startIdx = endIdx;
    }
    return out.isEmpty
        ? [(points: flat, color: _legColors[0])]
        : out;
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
    if (error != null && polylines.isEmpty) {
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
    // Keep GoogleMap mounted — overlay spinner only on first load.
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
            key: ValueKey('fs_map_${widget.request.requestId}'),
            initialCameraPosition:
                CameraPosition(target: initialTarget, zoom: 12),
            polylines: polylines,
            markers: markers,
            onMapCreated: (c) {
              _controller = c;
              _mapCreated = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => onReadyFit());
            },
            onCameraMoveStarted: () {
              _userMovedCamera = true;
            },
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
            compassEnabled: true,
          ),
        ),
        if (loading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.white),
              ),
            ),
          ),
        if (!loading && polylines.isEmpty)
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
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
