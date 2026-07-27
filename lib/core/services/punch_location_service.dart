import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/google_maps_config.dart';
import '../constants/app_constants.dart';import '../utils/geo_utils.dart';
import '../../modules/travel/data/models/travel_request_model.dart';

const bool bypassGeofenceChecks = false; // Temporary testing flag

/// Fast, accurate GPS reads for trip punches + departure geofence checks.
class PunchLocationService {
  Position? _cachedPosition;
  DateTime? _cachedAt;

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

    final cached = _cachedPosition;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) <=
            AppConstants.punchCachedPositionMaxAge &&
        cached.accuracy <= maxAccuracyMeters) {
      return cached;
    }

    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      final age = DateTime.now().difference(lastKnown.timestamp);
      if (age <= AppConstants.punchLastKnownMaxAge &&
          lastKnown.accuracy <= maxAccuracyMeters) {
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
      _remember(current);
      return current;
    } on TimeoutException {
    } catch (e) {
    }

    if (lastKnown != null) {
      _remember(lastKnown);
      return lastKnown;
    }
    return cached;
  }

  Future<Map<String, double>?> resolveStartCoordinates(
    TravelRequestModel request,
  ) async {
    final existing = request.startCoordinates;
    if (existing != null) {
      final lat = existing['latitude'];
      final lng = existing['longitude'];
      if (lat != null && lng != null) {
        return {'latitude': lat, 'longitude': lng};
      }
    }

    final from = request.fromLocation.trim();
    if (from.isEmpty) return null;
    return _resolveCoordinatesForAddress(from);
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
    return 'Start Departure only within ${allowed}m of '
        '$originLabel. You are about ${away}m away.';
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
      final start = request.startCoordinates;
      if (start != null) {
        final lat = start['latitude'];
        final lng = start['longitude'];
        if (lat != null && lng != null) {
          return {'latitude': lat, 'longitude': lng};
        }
      }
      final to = leg.toLocation.trim().isNotEmpty
          ? leg.toLocation.trim()
          : request.fromLocation.trim();
      return _resolveCoordinatesForAddress(to);
    }

    // For intermediate legs in a multi-leg trip, we must geocode the leg's planned destination address
    // (do not use request.endCoordinates because that represents the final destination of the entire trip).
    // Only use request.endCoordinates if it is a single-leg trip.
    final isMultiLeg = request.tripLegs.length > 1;
    if (!isMultiLeg) {
      final existing = request.endCoordinates;
      if (existing != null) {
        final lat = existing['latitude'];
        final lng = existing['longitude'];
        if (lat != null && lng != null) {
          return {'latitude': lat, 'longitude': lng};
        }
      }
    }

    final to = leg.toLocation.trim().isNotEmpty
        ? leg.toLocation.trim()
        : request.toLocation.trim();
    return _resolveCoordinatesForAddress(to);
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

    if (updated.startCoordinates == null) {
      final start = await resolveStartCoordinates(updated);
      if (start != null) {
        updated = updated.copyWith(startCoordinates: start);
      }
    }

    if (activeLeg != null && updated.endCoordinates == null) {
      final end = await resolveDestinationCoordinates(updated, activeLeg);
      if (end != null) {
        updated = updated.copyWith(endCoordinates: end);
      }
    }

    return updated;
  }

  Map<String, dynamic> plannedCoordinatePatch(TravelRequestModel request) {
    final patch = <String, dynamic>{};
    final start = request.startCoordinates;
    final end = request.endCoordinates;
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
    final destination = await resolveDestinationCoordinates(request, leg);
    if (destination == null) {
      return 'Could not verify the destination. '
          'Re-open this trip or recreate the request with map search.';
    }

    final destLat = destination['latitude']!;
    final destLng = destination['longitude']!;
    final distance = GeoUtils.distanceMeters(
      userLat,
      userLng,
      destLat,
      destLng,
    );
    const radius = AppConstants.arrivalGeofenceRadiusMeters;

    if (distance <= radius) return null;

    final away = distance.round();
    final allowed = radius.round();
    final label = leg.toLocation.trim().isNotEmpty
        ? leg.toLocation
        : request.toLocation;
    return 'Mark Arrival only within ${allowed}m of $label. '
        'You are about ${away}m away.';
  }

  void _remember(Position position) {
    _cachedPosition = position;
    _cachedAt = DateTime.now();
  }
}
