import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/api/api_endpoints.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/network/api_call.dart';
import '../../../../core/network/api_response_list.dart';
import '../../../../core/network/failures/network_failure.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../../core/utils/travel_request_debug_log.dart';
import '../../../../core/utils/app_debug_log.dart';
import '../models/route_segment_model.dart';
import '../models/tracking_coverage_model.dart';
import '../models/travel_request_list_result.dart';
import '../models/travel_request_summary.dart';

/// REST access for travel requests.
class TravelRequestRemoteDataSource {
  TravelRequestRemoteDataSource(this._dio);

  final Dio _dio;

  static const Duration _listTimeout = Duration(seconds: 5);

  /// Paginated list — `GET /travel-requests?page=&limit=&mine=true|false`.
  Future<ApiResult<TravelRequestListResult>> listTravelRequests({
    int page = 1,
    int limit = 10,
    bool mine = true,
    Duration? timeout,
  }) {
    final t = timeout ?? _listTimeout;
    return runApi(() async {
      final response = await _dio.get(
        ApiEndpoints.travelRequests,
        queryParameters: {
          'page': page,
          'limit': limit,
          'mine': mine ? 'true' : 'false',
        },
        options: dioTimeoutOptions(t),
      );
      final parsed = TravelRequestListResult.fromResponse(
        response.data,
        page: page,
        limit: limit,
      );
      TravelRequestDebugLog.logListResponse(
        source: 'GET /travel-requests',
        rawResponse: response.data,
        items: parsed.items,
        page: page,
        limit: limit,
      );
      return parsed;
    }, logLabel: 'GET /travel-requests');
  }

  /// Legacy full list — avoid on home; prefer [listTravelRequests].
  @Deprecated('Use listTravelRequests(page:, limit:)')
  Future<ApiResult<List<Map<String, dynamic>>>> listTravelRequestsAll() {
    return runApi(() async {
      final response = await _dio.get(ApiEndpoints.travelRequests);
      return ApiResponseList.parse(response.data);
    });
  }

  Future<ApiResult<Map<String, dynamic>>> getById(String requestId) {
    return runApi(() async {
      final response = await _dio.get(ApiEndpoints.travelRequest(requestId));
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('Travel request response is not a JSON object');
      }
      return Map<String, dynamic>.from(data);
    }, logLabel: 'GET /travel-requests/$requestId');
  }

  /// Current user's in-progress trip (`GET /travel-requests/active`). Null when none.
  Future<ApiResult<Map<String, dynamic>?>> getActiveTravelRequest() {
    return runApi(() async {
      final response = await _dio.get(
        ApiEndpoints.travelRequestsActive,
        options: dioTimeoutOptions(
          const Duration(seconds: 4),
          validateStatus: (status) => status == 200 || status == 404,
        ),
      );
      if (response.statusCode == 404 || response.data == null) {
        return null;
      }
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('Active travel request response is not a JSON object');
      }
      if (data.isEmpty) return null;
      return Map<String, dynamic>.from(data);
    }, logLabel: 'GET /travel-requests/active');
  }

  Future<ApiResult<Map<String, dynamic>>> create(
    Map<String, dynamic> body,
  ) {
    return runApi(() async {
      final response =
          await _dio.post<Map<String, dynamic>>(ApiEndpoints.travelRequests, data: body);
      final data = response.data;
      if (data != null && data.isNotEmpty) {
        return Map<String, dynamic>.from(data);
      }
      final rid = body['requestId']?.toString();
      if (rid != null && rid.isNotEmpty) {
        return Map<String, dynamic>.from(body);
      }
      throw const FormatException('Create travel request returned empty body');
    }, logLabel: 'POST /travel-requests');
  }

  Future<ApiResult<Map<String, dynamic>>> createTravelRequest({
    required String fromLocation,
    required String toLocation,
    required String vehicleType,
    required String clientName,
    String? fuelType,
    String? purpose,
    String? notes,
    double? originLatitude,
    double? originLongitude,
    double? destinationLatitude,
    double? destinationLongitude,
  }) {
    final data = <String, dynamic>{
      'fromLocation': fromLocation,
      'toLocation': toLocation,
      'vehicleType': vehicleType,
      'clientName': clientName.trim(),
    };
    if (originLatitude != null && originLongitude != null) {
      data['originLat'] = originLatitude;
      data['originLng'] = originLongitude;
    }
    if (destinationLatitude != null && destinationLongitude != null) {
      data['destinationLat'] = destinationLatitude;
      data['destinationLng'] = destinationLongitude;
    }
    final trimmedPurpose = purpose?.trim();
    if (trimmedPurpose != null && trimmedPurpose.isNotEmpty) {
      data['purpose'] = trimmedPurpose;
    }
    final trimmedNotes = notes?.trim();
    if (trimmedNotes != null && trimmedNotes.isNotEmpty) {
      data['notes'] = trimmedNotes;
    }
    if (AppConstants.vehicleRequiresFuelType(vehicleType) &&
        fuelType != null &&
        fuelType.isNotEmpty) {
      data['fuelType'] = fuelType;
    }
    return create(data);
  }

  /// Dashboard counters — `GET /travel-requests/summary?mine=true|false`.
  Future<ApiResult<TravelRequestSummary>> getSummary({bool mine = true}) {
    return runApi(() async {
      final response = await _dio.get(
        ApiEndpoints.travelRequestsSummary,
        queryParameters: {'mine': mine ? 'true' : 'false'},
        options: dioTimeoutOptions(_listTimeout),
      );
      return TravelRequestSummary.fromResponse(response.data);
    }, logLabel: 'GET /travel-requests/summary');
  }

  /// Start departure — `POST /travel-requests/:id/departure`.
  Future<ApiResult<Map<String, dynamic>>> postDeparture(
    String requestId,
    Map<String, dynamic> body,
  ) {
    return _postTravelAction(
      ApiEndpoints.travelRequestDeparture(requestId),
      body,
    );
  }

  /// Mark arrival — `POST /travel-requests/:id/arrival`.
  Future<ApiResult<Map<String, dynamic>>> postArrival(
    String requestId,
    Map<String, dynamic> body,
  ) {
    return _postTravelAction(
      ApiEndpoints.travelRequestArrival(requestId),
      body,
    );
  }

  /// Meeting start — `POST /travel-requests/:id/meeting-start` (falls back to `/trips/:id/punches/meeting-start`).
  Future<ApiResult<Map<String, dynamic>>> postMeetingStart(
    String requestId,
    Map<String, dynamic> body,
  ) {
    return _postTravelActionWithFallback(
      primaryPath: ApiEndpoints.travelRequestMeetingStart(requestId),
      fallbackPath: ApiEndpoints.tripMeetingStart(requestId),
      body: body,
    );
  }

  /// Meeting end — `POST /travel-requests/:id/meeting-end` (falls back to `/trips/:id/punches/meeting-end`).
  Future<ApiResult<Map<String, dynamic>>> postMeetingEnd(
    String requestId,
    Map<String, dynamic> body,
  ) {
    return _postTravelActionWithFallback(
      primaryPath: ApiEndpoints.travelRequestMeetingEnd(requestId),
      fallbackPath: ApiEndpoints.tripMeetingEnd(requestId),
      body: body,
    );
  }

  /// Start return leg — `POST /travel-requests/:id/return-start`.
  Future<ApiResult<Map<String, dynamic>>> postReturnStart(
    String requestId,
    Map<String, dynamic> body,
  ) {
    return _postTravelAction(
      ApiEndpoints.travelRequestReturnStart(requestId),
      body,
    );
  }

  /// Append next client leg — `POST /travel-requests/:id/next-client`.
  /// Falls back to PATCH when needed, then verifies legs were saved on server.
  Future<ApiResult<Map<String, dynamic>>> postNextClient(
    String requestId,
    Map<String, dynamic> body,
  ) async {
    final expectedLegCount = _expectedLegCountFromBody(body);
    final postBody = <String, dynamic>{
      'toLocation': body['toLocation'],
      'clientName': body['clientName'],
      'purpose': body['purpose'],
      'clientOfficeAddress': body['clientOfficeAddress'],
    };

    final postResult = await _postTravelAction(
      ApiEndpoints.travelRequestNextClient(requestId),
      postBody,
    );

    if (postResult is ApiSuccess) {
      final verified = await _fetchVerifiedTrip(
        requestId,
        minLegCount: expectedLegCount,
      );
      if (verified != null) return ApiSuccess(verified);
    } else if (postResult case ApiFailure(:final failure)) {
      final canPatch = failure.statusCode == 404 ||
          failure.statusCode == 400 ||
          failure.statusCode == 409;
      if (!canPatch) return postResult;
    }


    final patchResult = await _patchNextClientFallback(requestId, body);
    if (patchResult is ApiFailure) return patchResult;

    final verified = await _fetchVerifiedTrip(
      requestId,
      minLegCount: expectedLegCount,
    );
    if (verified != null) return ApiSuccess(verified);

    return const ApiFailure(
      NetworkFailure(
        message:
            'New client was not saved on the server. Restart the backend with the latest build and try again.',
        statusCode: 409,
      ),
    );
  }

  int _expectedLegCountFromBody(Map<String, dynamic> body) {
    final legs = body['tripLegs'];
    if (legs is List && legs.isNotEmpty) return legs.length + 1;
    return 2;
  }

  int _countTripLegs(Map<String, dynamic> trip) {
    final raw = trip['tripLegs'] ?? trip['legs'];
    if (raw is List && raw.isNotEmpty) return raw.length;
    final from = trip['fromLocation']?.toString().trim() ?? '';
    final to = trip['toLocation']?.toString().trim() ?? '';
    if (from.isNotEmpty || to.isNotEmpty) return 1;
    return 0;
  }

  Future<Map<String, dynamic>?> _fetchVerifiedTrip(
    String requestId, {
    required int minLegCount,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
      final result = await getById(requestId);
      if (result case ApiFailure()) continue;
      final data = (result as ApiSuccess<Map<String, dynamic>>).data;
      if (_countTripLegs(data) >= minLegCount) return data;
    }
    return null;
  }
  Future<ApiResult<Map<String, dynamic>>> _patchNextClientFallback(
    String requestId,
    Map<String, dynamic> body,
  ) async {
    final current = await getById(requestId);
    if (current case ApiFailure(:final failure)) {
      return ApiFailure(failure);
    }
    final trip = (current as ApiSuccess<Map<String, dynamic>>).data;
    final bodyLegs = body['tripLegs'];
    final legs = bodyLegs is List && bodyLegs.isNotEmpty
        ? bodyLegs
            .whereType<Map>()
            .map((leg) => Map<String, dynamic>.from(leg))
            .toList()
        : _legsFromTripMap(trip);
    final fromLocation =
        body['fromLocation']?.toString().trim() ??
            (legs.isNotEmpty ? legs.last['toLocation']?.toString() ?? '' : '');
    final toLocation = body['toLocation']?.toString().trim() ?? '';
    if (toLocation.isEmpty) {
      return const ApiFailure(
        NetworkFailure(message: 'toLocation is required'),
      );
    }

    final nextLeg = <String, dynamic>{
      'legId': 'leg_${legs.length + 1}_${DateTime.now().millisecondsSinceEpoch}',
      'sequence': legs.length + 1,
      'fromLocation': fromLocation,
      'toLocation': toLocation,
      'clientName': body['clientName']?.toString().trim() ?? '',
      'purpose': body['purpose']?.toString().trim() ?? '',
      'clientOfficeAddress':
          body['clientOfficeAddress']?.toString().trim() ?? toLocation,
      'isReturnLeg': false,
    };

    final patchPayload = <String, dynamic>{
      'tripLegs': [...legs, nextLeg],
      'toLocation': toLocation,
      'clientName': body['clientName']?.toString().trim() ?? '',
      'purpose': body['purpose']?.toString().trim() ?? '',
      'status': 'Ready To Start',
      'currentLegIndex': legs.length,
    };

    final patched = await patchTravelRequest(requestId, patchPayload);
    if (patched case ApiFailure(:final failure)) {
      return ApiFailure(failure);
    }

    return patched;
  }

  List<Map<String, dynamic>> _legsFromTripMap(Map<String, dynamic> trip) {
    final raw = trip['tripLegs'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((leg) => Map<String, dynamic>.from(leg))
          .toList();
    }
    final from = trip['fromLocation']?.toString() ?? '';
    final to = trip['toLocation']?.toString() ?? '';
    if (from.isEmpty && to.isEmpty) return [];
    return [
      {
        'legId': 'leg_1',
        'sequence': 1,
        'fromLocation': from,
        'toLocation': to,
        'clientName': trip['clientName']?.toString() ?? '',
        'purpose': trip['purpose']?.toString() ?? '',
        'clientOfficeAddress':
            trip['clientOfficeAddress']?.toString() ?? to,
        'isReturnLeg': false,
      },
    ];
  }

  Future<ApiResult<Map<String, dynamic>>> _postTravelActionWithFallback({
    required String primaryPath,
    required String fallbackPath,
    required Map<String, dynamic> body,
  }) async {
    final primary = await _postTravelAction(primaryPath, body);
    if (primary is ApiSuccess) return primary;
    final statusCode = primary.failureOrNull?.statusCode;
    if (statusCode == 404) {
      return _postTravelAction(fallbackPath, body);
    }
    return primary;
  }

  Future<ApiResult<Map<String, dynamic>>> _postTravelAction(
    String path,
    Map<String, dynamic> body,
  ) {
    return runApi(() async {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      final data = response.data;
      if (data != null && data.isNotEmpty) {
        return Map<String, dynamic>.from(data);
      }
      throw const FormatException('Travel action returned empty body');
    }, logLabel: 'POST $path');
  }

  Future<ApiResult<void>> update(
    String requestId,
    Map<String, dynamic> patch,
  ) {
    return runApi(() async {
      await _dio.patch<void>(
        ApiEndpoints.travelRequest(requestId),
        data: patch,
      );
    }, logLabel: 'PATCH /travel-requests/$requestId');
  }

  /// PATCH travel request and return updated body (for legacy-server fallbacks).
  Future<ApiResult<Map<String, dynamic>>> patchTravelRequest(
    String requestId,
    Map<String, dynamic> patch,
  ) {
    return runApi(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        ApiEndpoints.travelRequest(requestId),
        data: patch,
      );
      final data = response.data;
      if (data != null && data.isNotEmpty) {
        return Map<String, dynamic>.from(data);
      }
      final refetch = await _dio.get(ApiEndpoints.travelRequest(requestId));
      final refetchData = refetch.data;
      if (refetchData is! Map) {
        throw const FormatException('Travel request patch returned no body');
      }
      return Map<String, dynamic>.from(refetchData);
    }, logLabel: 'PATCH /travel-requests/$requestId (with body)');
  }

  Future<ApiResult<void>> delete(String requestId) {
    return runApi(() async {
      await _dio.delete<void>(ApiEndpoints.travelRequest(requestId));
    });
  }

  Future<ApiResult<Map<String, dynamic>>> postRoutePointsBatch(
    String requestId,
    List<Map<String, dynamic>> points,
  ) {
    return runApi(() async {
      final payload = points
          .map(
            (p) => <String, dynamic>{
              'pointId': p['pointId'],
              'clientPointId': p['clientPointId'] ?? p['pointId'],
              'latitude': p['latitude'],
              'longitude': p['longitude'],
              'timestamp': p['timestamp'],
              'accuracy': p['accuracy'],
              'speed': p['speed'],
              'bearing': p['bearing'] ?? p['heading'],
              'heading': p['heading'] ?? p['bearing'],
              'legId': p['legId'],
              'sessionId': p['sessionId'],
              'source': p['source'] ?? 'gps',
              'batteryLevel': p['batteryLevel'],
            },
          )
          .toList();
      final response = await _dio.post(
        ApiEndpoints.travelRequestRoutePointsBatch(requestId),
        data: {'points': payload},
      );
      final data = response.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return <String, dynamic>{
        'inserted': points.length,
        'acceptedClientPointIds': points
            .map((p) => p['pointId']?.toString() ?? p['clientPointId']?.toString())
            .whereType<String>()
            .toList(),
      };
    });
  }

  /// GPS trail — `GET /travel-requests/:id/route-points`.
  Future<ApiResult<List<Map<String, dynamic>>>> listRoutePoints(
    String requestId,
  ) {
    return runApi(() async {
      final response = await _dio.get(
        ApiEndpoints.travelRequestRoutePoints(requestId),
        options: dioTimeoutOptions(const Duration(seconds: 8)),
      );
      final data = response.data;
      if (data is Map) {
        final root = Map<String, dynamic>.from(data);
        final points = root['points'];
        if (points is List) {
          return points
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        final route = root['route'];
        if (route is List) {
          return route
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
      return ApiResponseList.parse(data);
    });
  }

  /// Session events — `POST /travel-requests/:id/tracking-events/batch`.
  Future<ApiResult<int>> postTrackingEventsBatch(
    String requestId,
    List<Map<String, dynamic>> events,
  ) {
    return runApi(() async {
      final response = await _dio.post<void>(
        ApiEndpoints.travelRequestTrackingEventsBatch(requestId),
        data: {'events': events},
      );
      return response.statusCode ?? 201;
    });
  }

  /// GPS coverage report — `GET /travel-requests/:id/tracking-coverage`.
  Future<ApiResult<TrackingCoverageResult>> getTrackingCoverage(
    String requestId, {
    String? legId,
  }) {
    return runApi(() async {
      final response = await _dio.get(
        ApiEndpoints.travelRequestTrackingCoverage(requestId),
        queryParameters: {
          if (legId != null && legId.isNotEmpty) 'legId': legId,
        },
      );
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('Tracking coverage response is not a map');
      }
      return TrackingCoverageResult.fromMap(
        Map<String, dynamic>.from(data),
      );
    });
  }

  /// Official matched route — `GET /travel-requests/:id/matched-route`.
  Future<ApiResult<MatchedRouteResult>> getMatchedRoute(String requestId) {
    return runApi(() async {
      final response = await _dio.get(
        ApiEndpoints.travelRequestMatchedRoute(requestId),
        options: dioTimeoutOptions(const Duration(seconds: 10)),
      );
      final data = response.data;
      if (data is! Map) {
        throw const FormatException('Matched route response is not a map');
      }
      final root = Map<String, dynamic>.from(data);
      final nested = root['data'] ?? root['matchedRoute'] ?? root;
      if (nested is! Map) {
        throw const FormatException('Matched route payload missing');
      }
      final parsed = MatchedRouteResult.fromMap(Map<String, dynamic>.from(nested));
      if (parsed.requestId.isEmpty) {
        return MatchedRouteResult.fromMap({
          ...Map<String, dynamic>.from(nested),
          'requestId': requestId,
        });
      }
      return parsed;
    });
  }

  /// Enqueue map match — `POST /travel-requests/:id/match`.
  ///
  /// [reason]: `catch_up` | `trip_end` | `incremental` | `manual`
  Future<ApiResult<MatchedRouteResult>> triggerRouteMatch(
    String requestId, {
    String reason = 'catch_up',
  }) {
    return runApi(() async {
      final response = await _dio.post(
        ApiEndpoints.travelRequestMatch(requestId),
        data: {'reason': reason},
        options: dioTimeoutOptions(const Duration(seconds: 15)),
      );
      final data = response.data;
      if (data is Map) {
        final root = Map<String, dynamic>.from(data);
        final nested = root['data'] ?? root['matchedRoute'] ?? root;
        if (nested is Map) {
          final parsed =
              MatchedRouteResult.fromMap(Map<String, dynamic>.from(nested));
          if (parsed.requestId.isEmpty) {
            return MatchedRouteResult.fromMap({
              ...Map<String, dynamic>.from(nested),
              'requestId': requestId,
              'status': root['status'] ?? parsed.status,
            });
          }
          return parsed;
        }
      }
      return MatchedRouteResult(
        requestId: requestId,
        status: 'pending',
      );
    });
  }

  /// Multipart meter photo (`captureType`: `start` | `end`).
  Future<ApiResult<Map<String, dynamic>>> uploadMeterImage({
    required String requestId,
    required String filePath,
    required String captureType,
    required double latitude,
    required double longitude,
    required String address,
  }) {
    return runApi(() async {
      final form = FormData.fromMap({
        'type': captureType,
        'latitude': latitude,
        'longitude': longitude,
        'address': address,
        'file': await MultipartFile.fromFile(filePath,
            filename: filePath.split(RegExp(r'[\\/]')).last),
      });
      final response = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.travelRequestMeterImage(requestId),
        data: form,
      );
      final data = response.data;
      if (data == null) return <String, dynamic>{};
      return Map<String, dynamic>.from(data as Map);
    });
  }

  /// Nest Directions proxy — `POST /directions/route`.
  ///
  /// Returns route maps with `points` (list of `{lat,lng}`), `distanceKm`, etc.
  Future<ApiResult<List<Map<String, dynamic>>>> fetchDrivingRoute({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    bool alternatives = true,
  }) {
    return runApi(() async {
      final response = await _dio.post(
        ApiEndpoints.directionsRoute,
        data: {
          'origin': {
            'lat': originLatitude,
            'lng': originLongitude,
          },
          'destination': {
            'lat': destinationLatitude,
            'lng': destinationLongitude,
          },
          'alternatives': alternatives,
        },
        options: dioTimeoutOptions(const Duration(seconds: 15)),
      );
      final data = response.data;
      if (data is! Map) return <Map<String, dynamic>>[];
      final root = Map<String, dynamic>.from(data);
      final routes = root['routes'];
      if (routes is! List) return <Map<String, dynamic>>[];
      return routes
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  }

  /// Nest Roads Snap-to-Roads proxy — `POST /directions/snap-path`.
  Future<ApiResult<List<Map<String, dynamic>>>> snapPathToRoads({
    required List<Map<String, double>> points,
    bool interpolate = true,
  }) {
    return runApi(() async {
      final response = await _dio.post(
        ApiEndpoints.directionsSnapPath,
        data: {
          'points': points,
          'interpolate': interpolate,
        },
        options: dioTimeoutOptions(const Duration(seconds: 20)),
      );
      final data = response.data;
      if (data is! Map) return <Map<String, dynamic>>[];
      final root = Map<String, dynamic>.from(data);
      final list = root['points'];
      if (list is! List) return <Map<String, dynamic>>[];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    });
  }

  /// Nest GPS↔road merge — `POST /directions/align-path`.
  Future<ApiResult<Map<String, dynamic>>> alignPathToRoads({
    required List<Map<String, dynamic>> points,
  }) {
    return runApi(() async {
      final response = await _dio.post(
        ApiEndpoints.directionsAlignPath,
        data: {'points': points},
        options: dioTimeoutOptions(const Duration(seconds: 45)),
      );
      final data = response.data;
      if (data is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(data);
    });
  }
}
