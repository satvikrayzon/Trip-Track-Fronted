import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/google_maps_config.dart';
import '../constants/app_constants.dart';import '../utils/geo_utils.dart';
import '../di/service_locator.dart';
import '../../modules/travel/data/models/travel_request_model.dart';
import 'background_location_service.dart';

const bool bypassGeofenceChecks = false; // Temporary testing flag

/// Max plausible hop (meters) between two "current position" reads a few
/// seconds apart. Anything beyond this is a bad fix (stale cache, network
/// geo-IP fallback, cross-country jump) — never trust it for a punch.
const double _kMaxPlausiblePunchJumpMeters = 3000;

/// Fast, accurate GPS reads for trip punches + departure geofence checks.
class PunchLocationService {
  Position? _cachedPosition;
  DateTime? _cachedAt;

  /// Live-tracking fix (Kalman-filtered, jump-gated) used as ground truth to
  /// reject wildly wrong "current position" reads (e.g. iOS returning a
  /// stale/geo-IP fix "in another country").
  Position? _trustedAnchor() {
    if (!ServiceLocator.I.has<BackgroundLocationService>()) return null;
    final bg = ServiceLocator.I.get<BackgroundLocationService>();
    return bg.recentTrackerFix(maxAge: const Duration(minutes: 2));
  }

  /// True when [candidate] is implausibly far from the trusted live-tracking
  /// anchor (same trip, same few seconds) — i.e. almost certainly a bad fix.
  bool _isSuspicious(Position candidate, Position? anchor) {
    if (anchor == null) return false;
    final d = GeoUtils.distanceMeters(
      candidate.latitude,
      candidate.longitude,
      anchor.latitude,
      anchor.longitude,
    );
    return d > _kMaxPlausiblePunchJumpMeters;
  }

  Future<bool> ensurePermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      final opened = await Geolocator.openLocationSettings();
      if (!opened) return false;
      if (!await Geolocator.isLocationServiceEnabled()) return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Warms GPS while the trip details screen is open (Ready To Start).
  Future<void> prewarm() async {
    try {
      if (!await ensurePermissions()) return;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        _remember(last);
      }
      unawaited(
        getFastPosition(
          maxAccuracyMeters: AppConstants.punchMaxAccuracyMeters * 2,
        ),
      );
    } catch (e) {
    }
  }

  Future<Position?> getFastPosition({
    Duration timeout = AppConstants.punchLocationTimeout,
    double maxAccuracyMeters = AppConstants.punchMaxAccuracyMeters,
  }) async {
    if (!await ensurePermissions()) return null;

    // Ground truth from the live tracker (if this trip is already tracking).
    // A "current position" read that disagrees wildly with this is a bad fix
    // (iOS geo-IP/stale-cache "wrong country" jump) and must never be trusted.
    final anchor = _trustedAnchor();

    final cached = _cachedPosition;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) <=
            AppConstants.punchCachedPositionMaxAge &&
        cached.accuracy <= maxAccuracyMeters &&
        !_isSuspicious(cached, anchor)) {
      return cached;
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      final age = DateTime.now().difference(lastKnown.timestamp);
      if (age <= AppConstants.punchLastKnownMaxAge &&
          lastKnown.accuracy <= maxAccuracyMeters &&
          !_isSuspicious(lastKnown, anchor)) {
        _remember(lastKnown);
        return lastKnown;
      }
    }

    try {
      final current = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      ).timeout(timeout);

      if (!_isSuspicious(current, anchor)) {
        _remember(current);
        return current;
      }

      // Bad fix vs. the live tracker — one retry at best accuracy before
      // giving up (common right after iOS wakes location services).
      try {
        final retry = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: timeout,
          ),
        ).timeout(timeout);
        if (!_isSuspicious(retry, anchor)) {
          _remember(retry);
          return retry;
        }
      } catch (_) {}

      // Still disagrees with the live trail — trust the trail, not the jump.
      if (anchor != null) return anchor;
      _remember(current);
      return current;
    } on TimeoutException {
    } catch (e) {
    }

    if (anchor != null) return anchor;

    if (lastKnown != null &&
        !_isSuspicious(lastKnown, anchor) &&
        DateTime.now().difference(lastKnown.timestamp) <=
            const Duration(minutes: 15)) {
      _remember(lastKnown);
      return lastKnown;
    }
    if (cached != null &&
        cachedAt != null &&
        !_isSuspicious(cached, anchor) &&
        DateTime.now().difference(cachedAt) <= const Duration(minutes: 15)) {
      return cached;
    }
    // Honest "GPS unavailable" beats guessing with a wrong-country fix.
    return null;
  }

  Future<Map<String, double>?> resolveStartCoordinates(
    TravelRequestModel request,
  ) async {
    final existing = GeoUtils.validCoordinates(request.startCoordinates);
    if (existing != null) return existing;

    final from = request.fromLocation.trim();
    if (from.isEmpty) return null;
    return GeoUtils.validCoordinates(await _resolveCoordinatesForAddress(from));
  }

  /// Anchor used for the 500m Start Departure geofence.
  Future<Map<String, double>?> resolveDepartureAnchor({
    required TravelRequestModel request,
    TripLegModel? activeLeg,
  }) async {
    final leg = activeLeg ?? request.activeLeg;
    Map<String, double>? start;

    if (leg != null && leg.sequence > 1) {
      TripLegModel? previousLeg;
      for (final candidate in request.tripLegs) {
        if (candidate.sequence < leg.sequence &&
            (previousLeg == null ||
                candidate.sequence > previousLeg.sequence)) {
          previousLeg = candidate;
        }
      }
      final arrival = previousLeg?.arrivalPunch;
      if (arrival != null) {
        start = {
          'latitude': arrival.latitude,
          'longitude': arrival.longitude,
        };
      } else if (leg.fromLocation.trim().isNotEmpty) {
        start = await _resolveCoordinatesForAddress(leg.fromLocation);
      }
    }
    start ??= await resolveStartCoordinates(request);
    return start;
  }

  /// Returns `null` when allowed; otherwise a user-facing error message.
  Future<String?> departureGeofenceError({
    required TravelRequestModel request,
    required double userLat,
    required double userLng,
    TripLegModel? activeLeg,
  }) async {
    if (bypassGeofenceChecks) return null;
    final leg = activeLeg ?? request.activeLeg;
    final start = await resolveDepartureAnchor(
      request: request,
      activeLeg: leg,
    );
    if (start == null) {
      return 'Could not verify the starting location. '
          'Edit this request and re-select the from location on the map.';
    }

    final startLat = start['latitude']!;
    final startLng = start['longitude']!;
    final distance = GeoUtils.distanceMeters(
      userLat,
      userLng,
      startLat,
      startLng,
    );
    const radius = AppConstants.departureGeofenceRadiusMeters;

    if (distance <= radius) return null;

    final away = distance.round();
    final allowed = radius.round();
    final originLabel = leg != null &&
            leg.sequence > 1 &&
            leg.fromLocation.trim().isNotEmpty
        ? leg.fromLocation
        : request.fromLocation;
    return 'Start Departure only within ${allowed}m of $originLabel. '
        'You are about ${away}m away — return to that location to punch. '
        'Travel before Start Departure is not counted.';
  }

  Future<Map<String, double>?> _resolveCoordinatesForAddress(
    String address,
  ) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;

    if (!kIsWeb) {
      try {
        final results = await locationFromAddress(trimmed).timeout(
          const Duration(seconds: 8),
        );
        if (results.isNotEmpty) {
          return {
            'latitude': results.first.latitude,
            'longitude': results.first.longitude,
          };
        }
      } catch (e) {
      }
    }

    return _geocodeViaGoogleApi(trimmed);
  }

  Future<Map<String, double>?> _geocodeViaGoogleApi(String address) async {
    if (!GoogleMapsConfig.isConfigured) return null;
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'address': address,
          'key': GoogleMapsConfig.apiKey,
          'region': 'in',
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map || data['status'] != 'OK') return null;

      final results = data['results'];
      if (results is! List || results.isEmpty) return null;

      final first = results.first;
      if (first is! Map) return null;
      final geometry = first['geometry'];
      if (geometry is! Map) return null;
      final location = geometry['location'];
      if (location is! Map) return null;

      final lat = (location['lat'] as num?)?.toDouble();
      final lng = (location['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      return {'latitude': lat, 'longitude': lng};
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, double>?> resolveDestinationCoordinates(
    TravelRequestModel request,
    TripLegModel leg,
  ) async {
    // If it is the return leg, the destination is the starting point of the trip
    if (leg.isReturnLeg) {
      final start = GeoUtils.validCoordinates(request.startCoordinates);
      if (start != null) return start;
      final to = leg.toLocation.trim().isNotEmpty
          ? leg.toLocation.trim()
          : request.fromLocation.trim();
      return GeoUtils.validCoordinates(await _resolveCoordinatesForAddress(to));
    }

    final end = GeoUtils.validCoordinates(request.endCoordinates);
    final isMultiLeg = request.tripLegs.length > 1;
    final legTo = leg.toLocation.trim();
    final requestTo = request.toLocation.trim();
    final matchesTripDestination = legTo.isNotEmpty &&
        requestTo.isNotEmpty &&
        (legTo.toLowerCase() == requestTo.toLowerCase() ||
            legTo.toLowerCase().contains(requestTo.toLowerCase()) ||
            requestTo.toLowerCase().contains(legTo.toLowerCase()));

    // Prefer map-picked coords whenever this leg is the trip destination.
    // Avoids bad address geocodes (e.g. "rayzon Solar" → lat≈0).
    if (end != null &&
        (!isMultiLeg ||
            matchesTripDestination ||
            (!leg.isReturnLeg && leg.sequence <= 1))) {
      return end;
    }

    final to = legTo.isNotEmpty ? legTo : requestTo;
    final geocoded =
        GeoUtils.validCoordinates(await _resolveCoordinatesForAddress(to));
    if (geocoded != null) return geocoded;

    // Last resort: still use trip end coords if they are valid.
    return end;
  }

  /// Reverse-geocode GPS into a human-readable address for punch records.
  Future<String> addressFromGps(double latitude, double longitude) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        latitude,
        longitude,
      ).timeout(const Duration(seconds: 6));
      if (placemarks.isEmpty) {
        return _coordsFallback(latitude, longitude);
      }
      return _formatPlacemark(placemarks.first, latitude, longitude);
    } catch (e) {
      return _coordsFallback(latitude, longitude);
    }
  }

  String _coordsFallback(double latitude, double longitude) =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  String _formatPlacemark(Placemark place, double latitude, double longitude) {
    final parts = <String>[
      if (place.name != null && place.name!.trim().isNotEmpty) place.name!.trim(),
      if (place.street != null && place.street!.trim().isNotEmpty)
        place.street!.trim(),
      if (place.subLocality != null && place.subLocality!.trim().isNotEmpty)
        place.subLocality!.trim(),
      if (place.locality != null && place.locality!.trim().isNotEmpty)
        place.locality!.trim(),
      if (place.administrativeArea != null &&
          place.administrativeArea!.trim().isNotEmpty)
        place.administrativeArea!.trim(),
      if (place.postalCode != null && place.postalCode!.trim().isNotEmpty)
        place.postalCode!.trim(),
    ];
    final seen = <String>{};
    final unique = parts.where((part) => seen.add(part.toLowerCase())).toList();
    if (unique.isNotEmpty) return unique.join(', ');
    return _coordsFallback(latitude, longitude);
  }

  /// Ensures planned origin/destination coordinates exist before geofence checks.
  Future<TravelRequestModel> ensurePlannedCoordinates(
    TravelRequestModel request, {
    TripLegModel? leg,
  }) async {
    var updated = request;
    final activeLeg = leg ?? request.activeLeg;

    if (GeoUtils.validCoordinates(updated.startCoordinates) == null) {
      final start = await resolveStartCoordinates(updated);
      if (start != null) {
        updated = updated.copyWith(startCoordinates: start);
      }
    }

    if (activeLeg != null &&
        GeoUtils.validCoordinates(updated.endCoordinates) == null) {
      final end = await resolveDestinationCoordinates(updated, activeLeg);
      if (end != null) {
        updated = updated.copyWith(endCoordinates: end);
      }
    }

    return updated;
  }

  Map<String, dynamic> plannedCoordinatePatch(TravelRequestModel request) {
    final patch = <String, dynamic>{};
    final start = GeoUtils.validCoordinates(request.startCoordinates);
    final end = GeoUtils.validCoordinates(request.endCoordinates);
    if (start != null) {
      patch['originLat'] = start['latitude'];
      patch['originLng'] = start['longitude'];
    }
    if (end != null) {
      patch['destinationLat'] = end['latitude'];
      patch['destinationLng'] = end['longitude'];
    }
    return patch;
  }

  /// Returns `null` when allowed; otherwise a user-facing error message.
  Future<String?> arrivalGeofenceError({
    required TravelRequestModel request,
    required TripLegModel leg,
    required double userLat,
    required double userLng,
  }) async {
    if (bypassGeofenceChecks) return null;
    if (!GeoUtils.isValidLatLng(userLat, userLng)) {
      return 'Could not read your GPS position. Wait a moment and try again.';
    }

    var destination = await resolveDestinationCoordinates(request, leg);
    destination = GeoUtils.validCoordinates(destination);

    // Prefer map-picked end coords when resolve produced nothing / invalid.
    destination ??= GeoUtils.validCoordinates(request.endCoordinates);

    if (destination == null) {
      return 'Could not verify the destination. '
          'Re-open this trip or recreate the request with map search.';
    }

    var destLat = destination['latitude']!;
    var destLng = destination['longitude']!;
    var distance = GeoUtils.distanceMeters(
      userLat,
      userLng,
      destLat,
      destLng,
    );

    // If primary dest looks absurdly far, try map-picked endCoordinates.
    final end = GeoUtils.validCoordinates(request.endCoordinates);
    if (distance > 50000 && end != null) {
      final alt = GeoUtils.distanceMeters(
        userLat,
        userLng,
        end['latitude']!,
        end['longitude']!,
      );
      if (alt < distance) {
        destLat = end['latitude']!;
        destLng = end['longitude']!;
        distance = alt;
      }
    }

    const radius = AppConstants.arrivalGeofenceRadiusMeters;

    if (distance <= radius) return null;

    final away = distance.round();
    final allowed = radius.round();
    final label = leg.toLocation.trim().isNotEmpty
        ? leg.toLocation
        : request.toLocation;
    return 'Mark Arrival only within ${allowed}m of $label. '
        'You are about ${away}m away — return to that location to punch. '
        'GPS keeps tracking until you mark arrival.';
  }

  void _remember(Position position) {
    _cachedPosition = position;
    _cachedAt = DateTime.now();
  }
}
