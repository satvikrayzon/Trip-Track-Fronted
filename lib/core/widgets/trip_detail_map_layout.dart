import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../layout/adaptive_layout.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/google_map_controller_utils.dart';
import '../utils/map_marker_icon.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import 'route_polyline_map_view.dart';
import '../utils/trip_route_polyline_decode.dart';
import 'google_map_web_gate.dart';
import 'map_web_pointer_shield.dart';
import 'trip_route_fullscreen_map_screen.dart';
import 'trip_route_map_data.dart';
import '../services/background_location_service.dart';
import '../services/gps_gap_road_fill.dart';
import '../di/service_locator.dart';
import '../utils/distance_sanity.dart';
import '../utils/geo_utils.dart';
import '../../modules/travel/data/models/route_segment_model.dart';

/// Zomato / Swiggy / Uber style trip detail: full-screen map + draggable sheet.
class TripDetailMapLayout extends StatefulWidget {
  const TripDetailMapLayout({
    super.key,
    required this.request,
    required this.sheetBuilder,
    this.adminServerPath,
    this.onBack,
    this.sheetFooter,
    this.useGoogleMaps,
  });

  final TravelRequestModel request;
  final List<LatLng>? adminServerPath;
  final VoidCallback? onBack;

  /// When true, uses Google Maps instead of the OSM fallback (web admin/manager).
  final bool? useGoogleMaps;

  /// Sticky footer inside the bottom sheet (punch / primary actions).
  final Widget? Function(BuildContext context)? sheetFooter;

  final Widget Function(BuildContext context, ScrollController scrollController)
      sheetBuilder;

  @override
  State<TripDetailMapLayout> createState() => _TripDetailMapLayoutState();
}

class _TripDetailMapLayoutState extends State<TripDetailMapLayout>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  bool _mapCreated = false;
  late DraggableScrollableController _sheetController;
  LatLng? _lastCameraTarget;
  String? _lastCameraPathSig;
  bool _userMovedCamera = false;
  bool _cameraFollowLive = true;
  Timer? _liveReloadDebounce;
  int _routeLoadGeneration = 0;

  /// True while the user's finger is actively panning/zooming the map.
  /// Route/GPS updates that arrive mid-gesture are queued (see
  /// [_pendingPointsUpdate]) so we never rebuild the polyline layer while
  /// the platform view is mid-drag — that's what caused the map to feel
  /// laggy/jerky when a location tick landed during a swipe.
  bool _isCameraMoving = false;
  List<List<List<LatLng>>>? _pendingPointsUpdate;

  /// google_maps_flutter's `onCameraMoveStarted` fires for BOTH real user
  /// gestures AND our own `animateCamera()` calls — it doesn't distinguish
  /// them. Without this flag, every auto-follow tick would immediately look
  /// like "the user dragged the map" and permanently kill live-follow mode
  /// (it would die on the very first tick after being (re)enabled). Route
  /// every programmatic camera move through [_animateCamera] so the move-start
  /// callback can tell the two apart.
  bool _programmaticCameraMove = false;

  Future<void> _animateCamera(
    GoogleMapController controller,
    CameraUpdate update,
  ) async {
    _programmaticCameraMove = true;
    try {
      await controller.animateCamera(update);
    } finally {
      // onCameraMoveStarted can arrive a frame after the future resolves.
      unawaited(Future.delayed(const Duration(milliseconds: 80), () {
        _programmaticCameraMove = false;
      }));
    }
  }

  String _routePointsCacheKey = '';
  List<List<List<LatLng>>>? _resolvedPoints;
  double? _trackedPathKm;
  List<RouteSegmentModel> _matchedSegments = const [];
  String _matchedCacheKey = '';
  BackgroundLocationService? _bgLocationService;

  late AnimationController _livePulse;

  static const double _sheetMin = 0.22;
  static const double _sheetInitial = 0.38;
  static const double _sheetMax = 0.92;

  /// Start easing the action button toward the screen bottom.
  static const double _actionPinStart = 0.68;

  /// Approx height of floating punch UI (reminder banner + large button).
  /// Used to keep map FABs above the overlay.
  static const double _actionWithReminderHeight = 168;

  /// Map padding tracks sheet size only after drag settles — avoids rebuilding
  /// the platform map view every frame while dragging.
  double _mapPaddingFraction = _sheetInitial;
  Timer? _mapPaddingDebounce;

  bool get _useGoogleMaps => widget.useGoogleMaps ?? googleMapsSupported();

  bool get _shieldWebMapOverlays => kIsWeb && _useGoogleMaps;

  /// Prefer gap-filled paths. adminServerPath only signals live mode.
  bool get _isLiveServer =>
      widget.adminServerPath != null && widget.adminServerPath!.isNotEmpty;

  bool get _isLiveTrip {
    final s = widget.request.status;
    return s == 'Travelling' ||
        s == 'Returning' ||
        s == 'At Client' ||
        s == 'In Meeting';
  }

  bool get _isCompletedTrip {
    final s = widget.request.status.trim().toLowerCase();
    return s == 'completed' || widget.request.tripEndedAt != null;
  }

  double get _sheetSize =>
      _sheetController.isAttached ? _sheetController.size : _sheetInitial;

  /// 0 = sheet low (action rides sheet edge), 1 = sheet full (action at bottom).
  double get _actionPinT {
    if (_sheetSize <= _actionPinStart) return 0;
    return ((_sheetSize - _actionPinStart) / (_sheetMax - _actionPinStart))
        .clamp(0.0, 1.0);
  }

  /// Bottom offset for widgets that sit just above the sheet top edge.
  double _aboveSheetBottom(double screenH, {double gap = 8}) =>
      screenH * _sheetSize + gap;

  /// Action button bottom: follows sheet, then eases to screen bottom when full.
  double _actionButtonBottom(double screenH) {
    final aboveSheet = _aboveSheetBottom(screenH);
    return aboveSheet * (1 - _actionPinT);
  }

  bool get _hasActionButton => widget.sheetFooter != null;

  /// Structural only — punches / status / match. Live tip must NOT be here or
  /// every GPS tick wipes the trail and shows a loader.
  String _routeDataKey(TravelRequestModel r) {
    return '${r.requestId}|${r.status}|'
        '${r.tripLegs.map((e) => '${e.legId}:${e.departurePunch?.time}:${e.arrivalPunch?.time}:${e.officialDistanceKm}:${e.matchedRoutePolylineEncoded?.length ?? 0}').join(';')}';
  }

  String _fullCacheKey() {
    return _routeDataKey(widget.request);
  }

  /// Tip signature for lightweight live append (not full Snap reload).
  String _liveTipKey() {
    final bgCount = _isActiveLocalTrip()
        ? _bgLocationService?.pointsBuffered.value ?? 0
        : 0;
    // Include device tip coords so offline updates aren't ignored when the
    // requestId used by BackgroundLocationService differs from widget.requestId.
    final tip = _latestLiveTip();
    final tipSig = tip == null
        ? '0'
        : '${tip.latitude.toStringAsFixed(5)},${tip.longitude.toStringAsFixed(5)}';
    final admin = widget.adminServerPath;
    final adminTip = (admin != null && admin.isNotEmpty)
        ? '${admin.length}|${admin.last.latitude}|${admin.last.longitude}'
        : '0';
    final pts = widget.request.routePoints;
    final last = pts.isNotEmpty ? pts.last : null;
    final lastSig = last == null
        ? '0'
        : '${last['latitude']}|${last['longitude']}|${pts.length}';
    return 'tip:$tipSig|bg:$bgCount|srv:$adminTip|rp:$lastSig';
  }

  String _lastLiveTipKey = '';
  Timer? _offlineLiveTipTimer;

  List<List<List<LatLng>>>? get _activePoints {
    // Always prefer gap-filled resolved paths. Admin live LatLng lists used to
    // bypass fill and painted false straight chords after app-kill.
    return _resolvedPoints;
  }

  List<LatLng> _flattenPaths(List<List<List<LatLng>>>? paths) {
    if (paths == null) return [];
    return [
      for (final leg in paths)
        for (final seg in leg) ...seg,
    ];
  }

  @override
  void initState() {
    super.initState();
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (_isLiveTrip || _isLiveServer) _livePulse.repeat(reverse: true);
    _initSheetController();
    if (ServiceLocator.I.has<BackgroundLocationService>()) {
      _bgLocationService = ServiceLocator.I.get<BackgroundLocationService>();
      _bgLocationService?.pointsBuffered.addListener(_onLocalPointsUpdated);
    }
    _syncOfflineLiveTipTimer();
    _syncRouteLoad();
    _syncMatchedLoad();
  }

  void _syncOfflineLiveTipTimer() {
    _offlineLiveTipTimer?.cancel();
    _offlineLiveTipTimer = null;
    if (!_isLiveTrip) return;
    // Offline has no websocket tips — poll device GPS so the polyline keeps
    // moving even when pointsBuffered listeners miss an id mismatch.
    _offlineLiveTipTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || !_isLiveTrip) return;
      _applyLiveTipAppend();
    });
  }

  Timer? _localPointsDebounce;

  bool _isActiveLocalTrip() {
    final activeId = _bgLocationService?.activeRequestId;
    if (activeId == null || activeId.isEmpty) return false;
    final r = widget.request;
    return activeId == r.requestId ||
        activeId == r.restResourceId ||
        activeId == r.tripId ||
        (r.mongoDocumentId != null && activeId == r.mongoDocumentId);
  }

  void _onLocalPointsUpdated() {
    if (!_isActiveLocalTrip()) return;
    _scheduleLiveTipUpdate();
  }

  void _scheduleLiveTipUpdate() {
    _applyLiveTipAppend();
    // Heavy Snap/Directions reconcile — keep trail visible meanwhile.
    _liveReloadDebounce?.cancel();
    _liveReloadDebounce = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      evictRoutePointsCache(widget.request.requestId);
      _routePointsCacheKey = '';
      _syncRouteLoad(keepPrevious: true);
    });
  }

  LatLng? _latestLiveTip() {
    // Prefer the device GPS stream so the tip keeps moving after offline,
    // reconnect, or kill/reopen — even when server/admin path is stale.
    if (_isActiveLocalTrip()) {
      final fix = _bgLocationService?.recentTrackerFix(
        maxAge: const Duration(minutes: 2),
      );
      final lat = fix?.latitude;
      final lng = fix?.longitude;
      if (lat != null &&
          lng != null &&
          GeoUtils.isValidLatLng(lat, lng)) {
        return LatLng(lat, lng);
      }
    }

    final admin = widget.adminServerPath;
    if (admin != null && admin.isNotEmpty) return admin.last;
    final pts = widget.request.routePoints;
    if (pts.isEmpty) return null;
    final last = pts.last;
    final lat = (last['latitude'] as num?)?.toDouble() ??
        (last['lat'] as num?)?.toDouble();
    final lng = (last['longitude'] as num?)?.toDouble() ??
        (last['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    if (!GeoUtils.isValidLatLng(lat, lng)) return null;
    return LatLng(lat, lng);
  }

  void _applyLiveTipAppend() {
    final tip = _latestLiveTip();
    if (tip == null) return;

    // Offline / first fix: bootstrap a trail from device GPS immediately.
    if (_resolvedPoints == null || _resolvedPoints!.isEmpty) {
      final tipKey = _liveTipKey();
      if (tipKey == _lastLiveTipKey) return;
      _lastLiveTipKey = tipKey;
      setState(() => _resolvedPoints = [
            [
              [tip]
            ]
          ]);
      _followLiveCamera(tip);
      return;
    }

    final tipKey = _liveTipKey();
    if (tipKey == _lastLiveTipKey) return;

    final paths = _resolvedPoints!;
    final legIndex =
        widget.request.currentLegIndex.clamp(0, paths.length - 1);
    final leg = paths[legIndex];
    if (leg.isEmpty || leg.last.isEmpty) {
      // Start a segment on the active leg.
      final next = [
        for (var i = 0; i < paths.length; i++)
          if (i == legIndex)
            [
              [tip],
            ]
          else
            paths[i],
      ];
      _lastLiveTipKey = tipKey;
      setState(() => _resolvedPoints = next);
      _followLiveCamera(tip);
      return;
    }
    final lastSeg = leg.last;
    final prev = lastSeg.last;
    final jump = GeoUtils.distanceMeters(
      prev.latitude,
      prev.longitude,
      tip.latitude,
      tip.longitude,
    );
    if (jump < 4) return;
    _lastLiveTipKey = tipKey;

    if (jump > GpsGapRoadFill.breakChordMeters) {
      // Large hop (kill/reopen or GPS gap): start a new segment with the tip
      // so the map keeps updating offline — don't wait on network reload.
      final newLeg = [...leg, [tip]];
      setState(() {
        _resolvedPoints = [
          for (var i = 0; i < paths.length; i++)
            if (i == legIndex) newLeg else paths[i],
        ];
      });
      _followLiveCamera(tip);
      evictRoutePointsCache(widget.request.requestId);
      _routePointsCacheKey = '';
      _syncRouteLoad(keepPrevious: true);
      return;
    }

    final newSeg = [...lastSeg, tip];
    final newLeg = [
      ...leg.sublist(0, leg.length - 1),
      newSeg,
    ];
    setState(() {
      _resolvedPoints = [
        for (var i = 0; i < paths.length; i++)
          if (i == legIndex) newLeg else paths[i],
      ];
    });
    _followLiveCamera(tip);
  }

  void _followLiveCamera(LatLng tip, {bool forceZoom = false}) {
    if (!_cameraFollowLive || _userMovedCamera) return;
    if (!_isLiveTrip && !_isLiveServer) return;
    final c = _mapController;
    if (c == null) return;
    // Nav-style: keep the moving dot centered and reasonably zoomed in,
    // never fight a zoom level the user picked (only bump it up, never down).
    if (forceZoom) {
      unawaited(_animateCamera(c, CameraUpdate.newLatLngZoom(tip, 16.5)));
    } else {
      unawaited(_animateCamera(c, CameraUpdate.newLatLng(tip)));
    }
  }

  /// Google-Maps-navigation-style "recenter" — re-engages auto follow after
  /// the user panned away, and snaps back onto the live current-location dot.
  void _resumeLiveFollow() {
    setState(() {
      _userMovedCamera = false;
      _cameraFollowLive = true;
    });
    final pts = _activePoints;
    if (pts == null) return;
    final flat = _flattenPaths(pts);
    if (flat.isNotEmpty) _followLiveCamera(flat.last, forceZoom: true);
  }

  void _initSheetController() {
    _sheetController = DraggableScrollableController();
    _sheetController.addListener(_onSheetSizeChanged);
  }

  void _recreateSheetController() {
    _mapPaddingDebounce?.cancel();
    _sheetController.removeListener(_onSheetSizeChanged);
    _sheetController.dispose();
    _mapPaddingFraction = _sheetInitial;
    _initSheetController();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload keeps State but replaces the sheet widget — reset the controller.
    _recreateSheetController();
  }

  void _onSheetSizeChanged() {
    _mapPaddingDebounce?.cancel();
    _mapPaddingDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final next = _sheetSize;
      if ((next - _mapPaddingFraction).abs() < 0.004) return;
      setState(() => _mapPaddingFraction = next);
    });
  }

  @override
  void didUpdateWidget(TripDetailMapLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tripChanged =
        oldWidget.request.requestId != widget.request.requestId;
    if (tripChanged) {
      _releaseMapController();
      _lastCameraTarget = null;
      _lastCameraPathSig = null;
      _userMovedCamera = false;
      _cameraFollowLive = true;
      _lastLiveTipKey = '';
      _recreateSheetController();
      _routePointsCacheKey = '';
      _resolvedPoints = null;
    }
    _syncRouteLoad(keepPrevious: !tripChanged);
    _syncMatchedLoad();
    _syncOfflineLiveTipTimer();
    // Live tip: append smoothly; do not fit whole route every tick.
    if (!tripChanged && (_isLiveTrip || _isLiveServer)) {
      _scheduleLiveTipUpdate();
    } else if (tripChanged) {
      _moveCameraToStartIfNeeded();
    }
    if ((_isLiveTrip || _isLiveServer) && !_livePulse.isAnimating) {
      _livePulse.repeat(reverse: true);
    } else if (!_isLiveTrip && !_isLiveServer && _livePulse.isAnimating) {
      _livePulse.stop();
    }
  }

  void _syncRouteLoad({bool keepPrevious = true}) {
    final key = _fullCacheKey();
    if (key == _routePointsCacheKey && _resolvedPoints != null) return;
    _routePointsCacheKey = key;

    // Keep last good trail visible — never flash loader on live GPS ticks.
    if (!keepPrevious || _resolvedPoints == null) {
      _resolvedPoints = null;
      _trackedPathKm = null;
    }
    final gen = ++_routeLoadGeneration;

    void applyPoints(List<List<List<LatLng>>> pts, {required bool fitCamera}) {
      if (!mounted || gen != _routeLoadGeneration) return;
      final flat = <LatLng>[
        for (final leg in pts)
          for (final seg in leg)
            if (seg.length >= 2) ...seg,
      ];
      final trackedKm = pathSegmentsLengthKm([
        for (final leg in pts)
          for (final seg in leg)
            if (seg.length >= 2) seg,
      ]);
      // Never rebuild the polyline layer mid-gesture — queue it and flush
      // on onCameraIdle instead, so panning/zooming stays smooth.
      if (_isCameraMoving && !fitCamera) {
        _pendingPointsUpdate = pts;
        _trackedPathKm = trackedKm > 0.05 ? trackedKm : _trackedPathKm;
        return;
      }
      _pendingPointsUpdate = null;
      setState(() {
        _resolvedPoints = pts;
        _trackedPathKm = trackedKm > 0.05 ? trackedKm : null;
      });
      if (fitCamera && (!keepPrevious || _lastCameraPathSig == null)) {
        _lastCameraPathSig = null;
        _moveCameraToStartIfNeeded();
      } else if (_isLiveTrip || _isLiveServer) {
        final tip = flat.isNotEmpty ? flat.last : null;
        if (tip != null) _followLiveCamera(tip);
      }
    }

    // Phase 1: local Hive / polyline / cache — clear loader ASAP (offline-first).
    unawaited(() async {
      final local = await loadTraveledLegPointsLocalFirst(widget.request);
      final hasLocal =
          local.any((leg) => leg.any((s) => s.length >= 2));
      if (hasLocal) {
        applyPoints(local, fitCamera: true);
      }

      // Phase 2: road-align / server refresh when needed (refine in place).
      final legs = await loadTraveledLegPoints(widget.request);
      final hasLegPaint = legs.any((leg) => leg.any((s) => s.length >= 2));
      if (hasLegPaint) {
        applyPoints(legs, fitCamera: !hasLocal);
        return;
      }
      final whole = await loadWholeTripPathFilled(widget.request);
      if (whole.isNotEmpty) {
        applyPoints([whole], fitCamera: !hasLocal);
        return;
      }
      if (!hasLocal && mounted && gen == _routeLoadGeneration) {
        applyPoints(const [], fitCamera: true);
      }
    }());
  }

  /// Same km as list cards — never use painted-path length (it drifts every
  /// Snap/Directions reload). Live trips may show tracked tip length only when
  /// stored km is still missing.
  (double? km, String label) _sheetDistance(TravelRequestModel request) {
    final cardKm = request.effectiveDistanceKm > 0
        ? request.effectiveDistanceKm
        : (request.distance ?? 0);
    if (cardKm > 0.05) {
      return (cardKm, request.displayDistanceLabel);
    }
    final tracked = _trackedPathKm;
    if (tracked != null && tracked > 0.05) {
      return (tracked, 'Tracked');
    }
    return (null, request.displayDistanceLabel);
  }

  void _syncMatchedLoad() {
    final key = _routeDataKey(widget.request);
    if (key == _matchedCacheKey && _matchedSegments.isNotEmpty) return;
    _matchedCacheKey = key;
    unawaited(() async {
      final segs = await loadMatchedRouteSegments(widget.request);
      if (!mounted) return;
      setState(() => _matchedSegments = segs);
    }());
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
    _bgLocationService?.pointsBuffered.removeListener(_onLocalPointsUpdated);
    _offlineLiveTipTimer?.cancel();
    _localPointsDebounce?.cancel();
    _liveReloadDebounce?.cancel();
    _mapPaddingDebounce?.cancel();
    _sheetController.removeListener(_onSheetSizeChanged);
    _livePulse.dispose();
    _releaseMapController();
    _sheetController.dispose();
    super.dispose();
  }

  LatLng _initialCameraTarget() {
    return tripMapStartTarget(widget.request) ??
        tripMapDestinationTarget(widget.request) ??
        const LatLng(23.0225, 72.5714);
  }

  void _moveCameraToStartIfNeeded() {
    final controller = _mapController;
    if (controller == null) return;
    if (_userMovedCamera && (_isLiveTrip || _isLiveServer)) return;

    final pts = _activePoints;
    if (pts != null && pts.any((leg) => leg.any((s) => s.isNotEmpty))) {
      final flattened = _flattenPaths(pts);
      if (flattened.isNotEmpty) {
        // Live: follow tip, don't re-fit whole bounds every update.
        if (_isLiveTrip || _isLiveServer) {
          _followLiveCamera(flattened.last);
          _lastCameraPathSig =
              '${flattened.length}_${flattened.last.latitude}';
          return;
        }
        final pathSig =
            '${flattened.length}_${flattened.first.latitude}_${flattened.last.latitude}';
        if (_lastCameraPathSig == pathSig) return;
        _lastCameraPathSig = pathSig;
        unawaited(_fitCamera(flattened));
        return;
      }
    }

    final target = _initialCameraTarget();
    if (_lastCameraTarget != null &&
        _lastCameraTarget!.latitude == target.latitude &&
        _lastCameraTarget!.longitude == target.longitude) {
      return;
    }
    _lastCameraTarget = target;
    unawaited(
      _animateCamera(controller, CameraUpdate.newLatLngZoom(target, 14)),
    );
  }

  Set<Marker> _buildPlannedMarkers() {
    final start = tripMapStartTarget(widget.request);
    if (start == null) return {};

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('planned_start'),
        position: start,
        icon: mapStartMarkerIcon,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(
          title: 'Start',
          snippet: widget.request.displayFromLocation,
        ),
      ),
    };

    final dest = tripMapDestinationTarget(widget.request);
    if (dest != null &&
        (dest.latitude != start.latitude ||
            dest.longitude != start.longitude)) {
      markers.add(
        Marker(
          markerId: const MarkerId('planned_dest'),
          position: dest,
          icon: mapEndMarkerIcon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: 'Destination',
            snippet: widget.request.displayToLocation,
          ),
        ),
      );
    }

    markers.addAll(
      tripStopMarkers(
        widget.request,
        exclude: [
          start,
          if (dest != null) dest,
        ],
      ),
    );

    return markers;
  }

  Future<void> _fitCamera(List<LatLng> pts) async {
    final c = _mapController;
    if (c == null || pts.isEmpty) return;

    final display = mapDisplayRoutePoints(pts);
    if (display.length == 1) {
      await _animateCamera(c, CameraUpdate.newLatLngZoom(display.first, 14));
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

    final latDelta = maxLat - minLat;
    final lngDelta = maxLng - minLng;
    final padLat = (latDelta * 0.15).clamp(0.0006, 0.015);
    final padLng = (lngDelta * 0.15).clamp(0.0006, 0.015);

    try {
      await _animateCamera(
        c,
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat - padLat, minLng - padLng),
            northeast: LatLng(maxLat + padLat, maxLng + padLng),
          ),
          120,
        ),
      );
    } catch (_) {
      await _animateCamera(c, CameraUpdate.newLatLngZoom(display.first, 15));
    }
  }

  void _openFullscreenMap() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripRouteFullscreenMapScreen(
          request: widget.request,
          useGoogleMaps: widget.useGoogleMaps ?? googleMapsSupported(),
        ),
      ),
    );
  }

  Set<Polyline> _buildPolylines(List<List<List<LatLng>>>? paths) {
    final set = <Polyline>{};
    final hasMatched = _matchedSegments.isNotEmpty ||
        widget.request.tripLegs
            .any((l) => (l.matchedRoutePolylineEncoded ?? '').isNotEmpty);

    // Planned corridor only for short local trips — never draw Oman→India lines.
    if (!hasMatched &&
        (paths == null ||
            paths.every((leg) => leg.every((s) => s.length < 2)))) {
      final start = tripMapStartTarget(widget.request);
      final dest = tripMapDestinationTarget(widget.request);
      if (start != null &&
          dest != null &&
          (start.latitude != dest.latitude ||
              start.longitude != dest.longitude)) {
        final plannedM = GeoUtils.distanceMeters(
          start.latitude,
          start.longitude,
          dest.latitude,
          dest.longitude,
        );
        if (plannedM > 0 && plannedM <= 40000) {
          set.add(
            Polyline(
              polylineId: const PolylineId('planned_route_line'),
              points: [start, dest],
              color: Colors.grey.withValues(alpha: 0.35),
              width: 3,
              patterns: [PatternItem.dash(10), PatternItem.gap(10)],
            ),
          );
        }
      }
    }

    // One trail only — never GPS zigzags + Nest matched purple on top.
    // After mark arrival, matched polylines used to paint a second fake route.
    final isCompleted = _isCompletedTrip;
    final gpsHasPath = paths != null &&
        paths.any((leg) => leg.any((s) => s.length >= 2));
    final showGpsLayer = gpsHasPath || _isLiveTrip || isCompleted;
    final showMatchedLayer = hasMatched && !gpsHasPath && !isCompleted;
    // `paths` here has already been through the full gap-fill → snap →
    // corridor → stitch pipeline (see RoadAlignedRouteService.align). Re-
    // breaking it at a tight 400-900m threshold would undo that work and
    // paint visible holes for gaps that were already bridged with real road
    // geometry — or with a straight fallback when Directions had nothing.
    // Only break on genuine teleports (wrong-country jumps).
    const edgeMax = GpsGapRoadFill.maxStraightLineMeters;
    if (showGpsLayer && paths != null) {
      for (var i = 0; i < paths.length; i++) {
        final color = _legTrailColor(i);
        for (var s = 0; s < paths[i].length; s++) {
          final pieces = mapDisplayRouteSegments(
            paths[i][s],
            maxEdgeMeters: edgeMax,
            maxJumpMeters: edgeMax,
          );
          for (var p = 0; p < pieces.length; p++) {
            final display = pieces[p];
            if (display.length < 2) continue;
            set.add(
              Polyline(
                polylineId: PolylineId('trip_route_${i}_${s}_$p'),
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
    }

    // Layer B — official matched segments (live / in-progress only).
    if (!showMatchedLayer) return set;
    final segments = (_matchedSegments.isNotEmpty
            ? _matchedSegments
            : widget.request.tripLegs
                .where((l) =>
                    (l.matchedRoutePolylineEncoded ?? '').isNotEmpty &&
                    !l.hasAbsurdOfficialDistance)
                .map(
                  (l) => RouteSegmentModel(
                    segId: '${l.legId}_matched',
                    legId: l.legId,
                    kind: RouteSegmentKind.mapMatched,
                    confidence: l.matchConfidence ?? 0.7,
                    lengthM: (l.officialDistanceKm ?? 0) * 1000,
                    polylineEncoded: l.matchedRoutePolylineEncoded!,
                  ),
                )
                .toList())
        .where((seg) {
      TripLegModel? leg;
      for (final l in widget.request.tripLegs) {
        if (l.legId == seg.legId) {
          leg = l;
          break;
        }
      }
      if (leg?.hasAbsurdOfficialDistance == true) return false;
      final km = seg.lengthM / 1000.0;
      if (km <= 0) return true;
      final gps = leg?.provisionalDistanceKm ?? leg?.actualDistanceKmFromTrack;
      final gpsOrTrip = gps ??
          (widget.request.effectiveDistanceKm > 0
              ? widget.request.effectiveDistanceKm
              : null);
      return !DistanceSanity.isOfficialAbsurd(
        officialKm: km,
        gpsKm: gpsOrTrip,
        plannedKm: leg?.plannedDistanceKm,
        travelMinutes: leg?.travelDurationMinutes ??
            widget.request.totalTravelDurationMinutes,
      );
    }).toList();

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final pts =
          mapDisplayRoutePoints(decodePipePolyline(seg.polylineEncoded));
      if (pts.length < 2) continue;
      final style = _segmentStyle(seg.kind);
      set.add(
        Polyline(
          polylineId: PolylineId('matched_seg_$i'),
          points: pts,
          color: style.color,
          width: style.width,
          patterns: style.dashed
              ? [PatternItem.dash(14), PatternItem.gap(8)]
              : const <PatternItem>[],
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }
    return set;
  }

  Color _legTrailColor(int legIndex) => AppColors.legTrailColor(legIndex);

  ({Color color, int width, bool dashed}) _segmentStyle(RouteSegmentKind kind) {
    // One consistent road color — orange "estimated" chords looked like bugs.
    switch (kind) {
      case RouteSegmentKind.gpsVerified:
        return (
          color: AppColors.primary,
          width: 7,
          dashed: false,
        );
      case RouteSegmentKind.mapMatched:
        return (
          color: AppColors.primary,
          width: 7,
          dashed: false,
        );
      case RouteSegmentKind.estimated:
        return (
          color: AppColors.primary,
          width: 6,
          dashed: false,
        );
    }
  }

  Set<Marker> _buildMarkers(List<List<List<LatLng>>> paths) {
    final display = _flattenPaths(paths);
    final sanitized = mapDisplayRoutePoints(display);
    if (sanitized.isEmpty) return {};

    final startPos = tripMapStartMarkerTarget(
          widget.request,
          pathFirst: sanitized.first,
        ) ??
        sanitized.first;
    final endPos = sanitized.length > 1
        ? (tripMapEndMarkerTarget(
              widget.request,
              pathLast: sanitized.last,
              isLive: _isLiveTrip,
            ) ??
            sanitized.last)
        : null;

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('route_start'),
        position: startPos,
        icon: mapStartMarkerIcon,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow(
          title: 'Start',
          snippet: widget.request.displayFromLocation,
        ),
      ),
    };

    if (endPos != null &&
        (endPos.latitude != startPos.latitude ||
            endPos.longitude != startPos.longitude)) {
      markers.add(
        Marker(
          markerId: const MarkerId('route_current'),
          position: endPos,
          icon: _isLiveTrip ? mapLiveMarkerIcon : mapEndMarkerIcon,
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: _isLiveTrip ? 'Current location' : 'End',
            snippet: widget.request.displayToLocation,
          ),
        ),
      );
    }

    markers.addAll(
      tripStopMarkers(
        widget.request,
        exclude: [
          startPos,
          if (endPos != null) endPos,
        ],
      ),
    );

    return markers;
  }

  Widget _buildGoogleMap(List<List<List<LatLng>>>? paths) {
    final center = _initialCameraTarget();
    final hasPath =
        paths != null && paths.any((leg) => leg.any((s) => s.isNotEmpty));
    final screenH = MediaQuery.sizeOf(context).height;

    return GoogleMap(
      key: ValueKey('trip_map_${widget.request.requestId}'),
      initialCameraPosition: CameraPosition(target: center, zoom: 14),
      polylines: _buildPolylines(paths),
      markers: hasPath ? _buildMarkers(paths) : _buildPlannedMarkers(),
      onMapCreated: (controller) {
        _mapController = controller;
        _mapCreated = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _lastCameraTarget = null;
          _lastCameraPathSig = null;
          _userMovedCamera = false;
          _moveCameraToStartIfNeeded();
        });
      },
      onCameraMoveStarted: () {
        _isCameraMoving = true;
        // Ignore moves we triggered ourselves (auto-follow/fit) — only a
        // real user gesture should ever kick the camera out of follow mode.
        if (_programmaticCameraMove) return;
        // User panned/zoomed — stop fighting their gesture with auto-fit.
        // Only rebuild once per transition (shows the recenter FAB), never
        // per-frame, so dragging stays smooth.
        if ((_isLiveTrip || _isLiveServer) && _cameraFollowLive) {
          setState(() {
            _userMovedCamera = true;
            _cameraFollowLive = false;
          });
        }
      },
      onCameraIdle: () {
        _isCameraMoving = false;
        // A GPS/route update may have arrived mid-drag — flush it now
        // instead of rebuilding polylines while the user was panning.
        if (_pendingPointsUpdate != null && mounted) {
          final pts = _pendingPointsUpdate!;
          _pendingPointsUpdate = null;
          setState(() {
            _resolvedPoints = pts;
          });
        }
      },
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 72,
        bottom: screenH * _mapPaddingFraction + 16,
      ),
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false,
      webGestureHandling: kIsWeb ? WebGestureHandling.cooperative : null,
    );
  }

  Widget _buildOsmMap(List<List<List<LatLng>>>? paths) {
    final start = tripMapStartTarget(widget.request);
    final dest = tripMapDestinationTarget(widget.request);
    final fallback = start ?? dest ?? const LatLng(23.0225, 72.5714);
    final flattened =
        paths != null && paths.any((leg) => leg.any((s) => s.isNotEmpty))
            ? _flattenPaths(paths)
            : [start ?? dest ?? fallback];

    return RoutePolylineMapView(
      key: ValueKey(
        'trip_osm_${widget.request.requestId}_'
        '${flattened.first.latitude}_${flattened.first.longitude}',
      ),
      points: flattened,
      height: null,
      lineColor: AppColors.primary,
      initialCenterOnFirstPoint: true,
      stopPoints: tripMapStops(widget.request).map((s) => s.position).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pts = _activePoints;
    // Loader only on first paint — never flash while reconciling live GPS.
    final loading = pts == null && _resolvedPoints == null;
    final screenH = MediaQuery.sizeOf(context).height;
    final actionChild = _resolveActionChild(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: _useGoogleMaps
                  ? GoogleMapWebGate(
                      fallback: _buildOsmMap(pts),
                      builder: (_) => _buildGoogleMap(pts),
                    )
                  : _buildOsmMap(pts),
            ),
          ),
          if (loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          _buildTopOverlay(context),
          _buildWebSheetPointerBarrier(screenH),
          _buildBottomSheet(context),
          // Keep floating controls above the sheet.
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _sheetController,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildMapControls(pts, screenH),
                  _buildActionOverlay(screenH, actionChild),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _resolveActionChild(BuildContext context) {
    final builder = widget.sheetFooter;
    if (builder == null) return null;
    final child = builder(context);
    if (child == null || _isCollapsedFooter(child)) return null;
    return child;
  }

  Widget _buildTopOverlay(BuildContext context) {
    final request = widget.request;
    final statusColor = _statusColor(request.status);

    return mapWebPointerShield(
      enabled: _shieldWebMapOverlays,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              _FloatingMapButton(
                icon: Icons.arrow_back_rounded,
                onPressed:
                    widget.onBack ?? () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Material(
                  elevation: 4,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        if (_isLiveTrip || _isLiveServer) ...[
                          AnimatedBuilder(
                            animation: _livePulse,
                            builder: (context, child) {
                              final t = 0.45 + _livePulse.value * 0.55;
                              return Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: t),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.success
                                          .withValues(alpha: 0.35 * t),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                request.status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              Text(
                                request.routeSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapControls(List<List<List<LatLng>>>? pts, double screenH) {
    final flattened = _flattenPaths(pts);
    final hasPath = flattened.isNotEmpty;
    if (!hasPath) return const SizedBox.shrink();

    // Stay above the sheet + floating punch stack (reminder can be tall).
    final actionLift = _hasActionButton
        ? (_actionWithReminderHeight + 12) * (1 - _actionPinT)
        : 0.0;
    final bottomOffset = _aboveSheetBottom(screenH, gap: 12) + actionLift;

    final showRecenter =
        (_isLiveTrip || _isLiveServer) && !_cameraFollowLive;

    return Positioned(
      right: 14,
      bottom: bottomOffset,
      child: mapWebPointerShield(
        enabled: _shieldWebMapOverlays,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showRecenter) ...[
              _FloatingMapButton(
                icon: Icons.navigation_rounded,
                tooltip: 'Recenter on my location',
                highlighted: true,
                onPressed: _resumeLiveFollow,
              ),
              const SizedBox(height: 10),
            ],
            _FloatingMapButton(
              icon: Icons.my_location_rounded,
              tooltip: 'Fit route',
              onPressed: () => _fitCamera(flattened),
            ),
            const SizedBox(height: 10),
            _FloatingMapButton(
              icon: Icons.open_in_full_rounded,
              tooltip: 'Full screen map',
              onPressed: _openFullscreenMap,
            ),
          ],
        ),
      ),
    );
  }

  /// Floats above the sheet while collapsed; eases to screen bottom when expanded.
  Widget _buildActionOverlay(double screenH, Widget? child) {
    if (child == null) return const SizedBox.shrink();

    final pinT = _actionPinT;
    final bottom = _actionButtonBottom(screenH);
    final horizontalInset = 16.0 * (1 - pinT);

    if (pinT >= 0.98) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: mapWebPointerShield(
          enabled: _shieldWebMapOverlays,
          child: Material(
            elevation: 10,
            color: AppColors.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: child,
              ),
            ),
          ),
        ),
      );
    }

    // Transparent — warning + button carry their own backgrounds. A white
    // Material here filled the gap between them and covered map FABs.
    return Positioned(
      left: horizontalInset,
      right: horizontalInset,
      bottom: bottom,
      child: mapWebPointerShield(
        enabled: _shieldWebMapOverlays,
        child: Material(
          type: MaterialType.transparency,
          child: child,
        ),
      ),
    );
  }

  void _dragSheetBy(double deltaPixels) {
    if (!_sheetController.isAttached) return;
    final screenH = MediaQuery.sizeOf(context).height;
    final next = (_sheetController.size - deltaPixels / screenH)
        .clamp(_sheetMin, _sheetMax);
    _sheetController.jumpTo(next);
  }

  /// Blocks the Google Map iframe from eating events in the sheet region on web.
  Widget _buildWebSheetPointerBarrier(double screenH) {
    if (!_shieldWebMapOverlays) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: _sheetController,
      builder: (context, _) {
        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: screenH * _sheetSize,
          child: mapWebPointerShield(
            enabled: true,
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  Widget _buildSheetDragHeader() {
    final handle = Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          width: 48,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.grey.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );

    if (!_shieldWebMapOverlays) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          handle,
          const SizedBox(height: 8),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (details) => _dragSheetBy(details.delta.dy),
          child: handle,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildBottomSheet(BuildContext context) {
    final request = widget.request;
    final leg = request.activeLeg ?? request.tripLegs.firstOrNull;

    return DraggableScrollableSheet(
      key: ValueKey('trip_sheet_${widget.request.requestId}'),
      controller: _sheetController,
      initialChildSize: _sheetInitial,
      minChildSize: _sheetMin,
      maxChildSize: _sheetMax,
      snap: true,
      snapSizes: const [_sheetMin, _sheetInitial, _sheetMax],
      snapAnimationDuration: const Duration(milliseconds: 220),
      builder: (context, scrollController) {
        final sheet = DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildSheetDragHeader(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _shieldWebMapOverlays
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) =>
                            _dragSheetBy(details.delta.dy),
                        child: Builder(
                          builder: (context) {
                            final dist = _sheetDistance(request);
                            return _RoutePreviewStrip(
                              from: leg?.fromLocation ?? request.fromLocation,
                              to: leg?.toLocation ?? request.toLocation,
                              distanceKm: dist.$1,
                              distanceLabel: dist.$2,
                              isLive: _isLiveTrip,
                            );
                          },
                        ),
                      )
                    : Builder(
                        builder: (context) {
                          final dist = _sheetDistance(request);
                          return _RoutePreviewStrip(
                            from: leg?.fromLocation ?? request.fromLocation,
                            to: leg?.toLocation ?? request.toLocation,
                            distanceKm: dist.$1,
                            distanceLabel: dist.$2,
                            isLive: _isLiveTrip,
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Expanded(
                child: widget.sheetBuilder(context, scrollController),
              ),
            ],
          ),
        );

        return mapWebPointerShield(
          enabled: _shieldWebMapOverlays,
          child: sheet,
        );
      },
    );
  }

  static bool _isCollapsedFooter(Widget footer) {
    if (footer is! SizedBox) return false;
    final w = footer.width ?? 0;
    final h = footer.height ?? 0;
    return footer.child == null && w == 0 && h == 0;
  }

  Color _statusColor(String status) => switch (status) {
        'Ready To Start' => AppColors.warning,
        'Travelling' || 'Returning' => AppColors.info,
        'At Client' => AppColors.accent,
        'In Meeting' => AppColors.primary,
        'Ready For Next' || 'Ready To Return' => AppColors.warning,
        'Completed' => AppColors.success,
        _ => AppColors.textPrimary,
      };
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

class _FloatingMapButton extends StatelessWidget {
  const _FloatingMapButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      color: highlighted ? AppColors.primary : Colors.white,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(
          icon,
          color: highlighted ? Colors.white : AppColors.textPrimary,
          size: 22,
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _RoutePreviewStrip extends StatelessWidget {
  const _RoutePreviewStrip({
    required this.from,
    required this.to,
    this.distanceKm,
    this.distanceLabel,
    this.isLive = false,
  });

  final String from;
  final String to;
  final double? distanceKm;
  final String? distanceLabel;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            const _Dot(color: AppColors.success),
            Container(width: 2, height: 28, color: AppColors.greyLight),
            _Dot(color: isLive ? AppColors.info : AppColors.error),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                from,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                to,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        if (distanceKm != null && distanceKm! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${distanceKm!.toStringAsFixed(1)} km',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (distanceLabel != null && distanceLabel!.isNotEmpty)
                  Text(
                    distanceLabel!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}
