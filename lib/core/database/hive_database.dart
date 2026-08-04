import 'package:hive_flutter/hive_flutter.dart';

/// Hive database configuration and initialization
class HiveDatabase {
  static Box<Map>? _syncQueueBox;
  static Box<Map>? _offlineImagesBox;
  static Box<Map>? _offlineTravelRequestsBox;
  static Box<Map>? _offlineUsersBox;
  static Box<Map>? _routePointsBox;
  static Box<Map>? _trackingEventsBox;
  static Box<Map>? _trackingCoverageCacheBox;
  static Box<Map>? _matchedRouteCacheBox;
  static Box<Map>? _sessionBox;

  static HiveDatabase? _instance;

  HiveDatabase._();

  static HiveDatabase get instance {
    _instance ??= HiveDatabase._();
    return _instance!;
  }

  /// Initialize the Hive database
  Future<void> initialize() async {
    try {
      await Hive.initFlutter();

      // Register adapters if needed
      // Hive.registerAdapter(SomeAdapter());

      // Open boxes with error handling
      _syncQueueBox = await Hive.openBox<Map>('sync_queue');
      _offlineImagesBox = await Hive.openBox<Map>('offline_images');
      _offlineTravelRequestsBox =
          await Hive.openBox<Map>('offline_travel_requests');
      _offlineUsersBox = await Hive.openBox<Map>('offline_users');
      _routePointsBox = await Hive.openBox<Map>('route_points');
      _trackingEventsBox = await Hive.openBox<Map>('tracking_events');
      _trackingCoverageCacheBox =
          await Hive.openBox<Map>('tracking_coverage_cache');
      _matchedRouteCacheBox =
          await Hive.openBox<Map>('matched_route_cache');
      _sessionBox = await Hive.openBox<Map>('app_session');

    } catch (e) {
      rethrow;
    }
  }

  /// Close all boxes
  static Future<void> close() async {
    await _syncQueueBox?.close();
    await _offlineImagesBox?.close();
    await _offlineTravelRequestsBox?.close();
    await _offlineUsersBox?.close();
    await _routePointsBox?.close();
    await _trackingEventsBox?.close();
    await _trackingCoverageCacheBox?.close();
    await _matchedRouteCacheBox?.close();
    await _sessionBox?.close();
  }

  static const String _sessionKey = 'tokens';

  /// Persist API JWTs for offline session restore.
  Future<void> saveSessionTokens({
    required String? accessToken,
    required String? refreshToken,
  }) async {
    await _sessionBox?.put(_sessionKey, {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    });
  }

  (String?, String?) getSessionTokensSync() {
    final row = _sessionBox?.get(_sessionKey);
    if (row == null) return (null, null);
    return (
      row['accessToken']?.toString(),
      row['refreshToken']?.toString(),
    );
  }

  Future<void> clearSessionTokens() async {
    await _sessionBox?.delete(_sessionKey);
  }

  static const String _activeTripKey = 'activeTripId';

  /// Last in-progress trip id (UUID) for restore after app restart.
  Future<void> saveActiveTripId(String requestId) async {
    if (requestId.isEmpty) return;
    await _sessionBox?.put(_activeTripKey, {'id': requestId});
  }

  String? getActiveTripIdSync() {
    final row = _sessionBox?.get(_activeTripKey);
    if (row == null) return null;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  Future<void> clearActiveTripId() async {
    await _sessionBox?.delete(_activeTripKey);
  }

  // Sync Queue Operations
  Future<void> addToSyncQueue(String type, Map<String, dynamic> data) async {
    final item = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': type,
      'data': data,
      'createdAt': DateTime.now().toIso8601String(),
      'retryCount': 0
    };
    await _syncQueueBox?.put(item['id'], item);
  }

  Future<List<Map>> getSyncQueueItems() async {
    return _syncQueueBox?.values.toList() ?? [];
  }

  Future<void> removeFromSyncQueue(String id) async {
    await _syncQueueBox?.delete(id);
  }

  /// Removes queued sync ops for a travel request document id.
  Future<void> purgeSyncQueueForDocument(String documentId) async {
    if (documentId.isEmpty) return;
    final box = _syncQueueBox;
    if (box == null) return;

    final keysToRemove = <dynamic>{};
    for (final entry in box.toMap().entries) {
      final key = entry.key;
      final item = entry.value;
      if (key.toString().contains(documentId)) {
        keysToRemove.add(key);
        continue;
      }
      final data = item['data'];
      if (data is Map && data['documentId']?.toString() == documentId) {
        keysToRemove.add(key);
      }
    }

    for (final key in keysToRemove) {
      await box.delete(key);
    }
  }

  Future<void> updateSyncQueueRetry(
      String id, int retryCount, String error) async {
    final item = _syncQueueBox?.get(id);
    if (item != null) {
      item['retryCount'] = retryCount;
      item['lastError'] = error;
      await _syncQueueBox?.put(id, item);
    }
  }

  // Offline Users Operations
  Future<void> saveUser(Map<String, dynamic> userData) async {
    final user = {
      'uid': userData['uid'] ?? '',
      'email': userData['email'] ?? '',
      'name': userData['name'] ?? '',
      'employeeCode': userData['employeeCode'] ?? '',
      'role': userData['role'] ?? 'user',
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'isSynced': true,
      'lastSyncAt': DateTime.now().toIso8601String(),
      'profileData': userData,
    };
    await _offlineUsersBox?.put(user['uid'], user);
  }

  Future<Map<String, dynamic>?> getUser(String uid) async {
    final result = _offlineUsersBox?.get(uid);
    return result?.cast<String, dynamic>();
  }

  Future<void> deleteUser(String uid) async {
    await _offlineUsersBox?.delete(uid);
  }

  // Offline Travel Requests Operations
  Future<void> saveTravelRequest(Map<String, dynamic> requestData) async {
    final requestId = (requestData['requestId'] ??
            DateTime.now().millisecondsSinceEpoch.toString())
        .toString();
    final existingRaw = _offlineTravelRequestsBox?.get(requestId);
    final existing = existingRaw is Map
        ? Map<String, dynamic>.from(existingRaw)
        : <String, dynamic>{};

    dynamic keep(dynamic incoming, dynamic fallback) {
      if (incoming == null) return fallback;
      if (incoming is String && incoming.trim().isEmpty) return fallback;
      if (incoming is num && incoming == 0 && fallback is num && fallback != 0) {
        return fallback;
      }
      if (incoming is List && incoming.isEmpty && fallback is List) {
        return fallback;
      }
      return incoming;
    }

    final request = <String, dynamic>{
      ...existing,
      'requestId': requestId,
      'userId': keep(requestData['userId'], existing['userId'] ?? ''),
      'name': keep(
        requestData['name'] ?? requestData['userName'],
        existing['name'] ?? existing['userName'] ?? '',
      ),
      'userName': keep(
        requestData['userName'] ?? requestData['name'],
        existing['userName'] ?? existing['name'] ?? '',
      ),
      if (requestData['_id'] != null)
        '_id': requestData['_id']
      else if (existing['_id'] != null)
        '_id': existing['_id'],
      if (requestData['tripId'] != null || existing['tripId'] != null)
        'tripId': keep(requestData['tripId'], existing['tripId']),
      'employeeCode': keep(requestData['employeeCode'], existing['employeeCode']),
      'city': keep(requestData['city'], existing['city'] ?? ''),
      'fromLocation':
          keep(requestData['fromLocation'], existing['fromLocation'] ?? ''),
      'toLocation':
          keep(requestData['toLocation'], existing['toLocation'] ?? ''),
      'clientName': keep(requestData['clientName'], existing['clientName']),
      'vehicleType':
          keep(requestData['vehicleType'], existing['vehicleType'] ?? ''),
      'fuelType': keep(requestData['fuelType'], existing['fuelType']),
      'fuelRatePerKm':
          keep(requestData['fuelRatePerKm'], existing['fuelRatePerKm']),
      'travelAllowance':
          keep(requestData['travelAllowance'], existing['travelAllowance']),
      'purpose': keep(requestData['purpose'], existing['purpose']),
      'notes': keep(requestData['notes'], existing['notes']),
      'requestDate': keep(
        requestData['requestDate'],
        existing['requestDate'] ?? DateTime.now().toIso8601String(),
      ),
      'status': keep(
        requestData['status'],
        existing['status'] ?? 'Start Missing',
      ),
      'startImageUrl':
          keep(requestData['startImageUrl'], existing['startImageUrl']),
      'endImageUrl': keep(requestData['endImageUrl'], existing['endImageUrl']),
      'startCoordinates':
          keep(requestData['startCoordinates'], existing['startCoordinates']),
      'endCoordinates':
          keep(requestData['endCoordinates'], existing['endCoordinates']),
      'startAddress': keep(requestData['startAddress'], existing['startAddress']),
      'endAddress': keep(requestData['endAddress'], existing['endAddress']),
      'stops': keep(requestData['stops'], existing['stops']),
      'tripLegs': keep(requestData['tripLegs'], existing['tripLegs']),
      'totalDistanceKm':
          keep(requestData['totalDistanceKm'], existing['totalDistanceKm'] ?? 0),
      'totalTravelDurationMinutes': keep(
        requestData['totalTravelDurationMinutes'],
        existing['totalTravelDurationMinutes'] ?? 0,
      ),
      'totalMeetingDurationMinutes': keep(
        requestData['totalMeetingDurationMinutes'],
        existing['totalMeetingDurationMinutes'] ?? 0,
      ),
      'totalMeetings':
          keep(requestData['totalMeetings'], existing['totalMeetings'] ?? 0),
      'currentLegIndex':
          keep(requestData['currentLegIndex'], existing['currentLegIndex'] ?? 0),
      'trackingSessionId':
          keep(requestData['trackingSessionId'], existing['trackingSessionId']),
      'tripStartedAt':
          keep(requestData['tripStartedAt'], existing['tripStartedAt']),
      'tripEndedAt': keep(requestData['tripEndedAt'], existing['tripEndedAt']),
      'trackingStatus':
          keep(requestData['trackingStatus'], existing['trackingStatus']),
      'enableLiveTracking':
          requestData['enableLiveTracking'] ??
              existing['enableLiveTracking'] ??
              true,
      'routePointCount':
          keep(requestData['routePointCount'], existing['routePointCount'] ?? 0),
      'totalMovingMinutesFromTrack': keep(
        requestData['totalMovingMinutesFromTrack'],
        existing['totalMovingMinutesFromTrack'] ?? 0,
      ),
      'totalStoppedMinutesFromTrack': keep(
        requestData['totalStoppedMinutesFromTrack'],
        existing['totalStoppedMinutesFromTrack'] ?? 0,
      ),
      'createdAt': existing['createdAt'] ?? DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'isSynced': requestData['isSynced'] ?? existing['isSynced'] ?? false,
      'lastSyncAt': requestData['lastSyncAt'] ?? existing['lastSyncAt'],
    };
    await _offlineTravelRequestsBox?.put(requestId, request);
  }

  Future<List<Map>> getOfflineTravelRequestsForUser(String userId) async {
    final allRequests = _offlineTravelRequestsBox?.values.toList() ?? [];
    return allRequests.where((request) => request['userId'] == userId).toList();
  }

  Future<List<Map>> getAllOfflineTravelRequests() async {
    return _offlineTravelRequestsBox?.values.toList() ?? [];
  }

  Future<void> updateTravelRequest(
      String requestId, Map<String, dynamic> updates) async {
    final request = _offlineTravelRequestsBox?.get(requestId);
    if (request != null) {
      request.addAll(updates);
      request['updatedAt'] = DateTime.now().toIso8601String();
      await _offlineTravelRequestsBox?.put(requestId, request);
    }
  }

  Future<void> deleteTravelRequest(String requestId) async {
    await _offlineTravelRequestsBox?.delete(requestId);
  }

  /// Removes cached trips for [userId] that are no longer returned by the API.
  Future<void> pruneOfflineTravelRequestsForUser(
    String userId,
    Set<String> keepRequestIds,
  ) async {
    final rows = await getOfflineTravelRequestsForUser(userId);
    for (final row in rows) {
      final id = row['requestId']?.toString() ?? '';
      if (id.isNotEmpty && !keepRequestIds.contains(id)) {
        await deleteTravelRequest(id);
      }
    }
  }

  // Offline Images Operations
  Future<void> saveOfflineImage(Map<String, dynamic> imageData) async {
    final image = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'requestId': imageData['requestId'] ?? '',
      'imageType': imageData['imageType'] ?? '', // 'start' or 'end'
      'localPath': imageData['localPath'] ?? '',
      'fileName': imageData['fileName'] ?? '',
      'coordinates': imageData['coordinates'] ?? {},
      'address': imageData['address'] ?? '',
      'timestamp': imageData['timestamp'] ?? DateTime.now().toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
      'isSynced': false,
      'lastSyncAt': null
    };
    await _offlineImagesBox?.put(image['id'], image);
  }

  Future<List<Map>> getOfflineImages() async {
    return _offlineImagesBox?.values.toList() ?? [];
  }

  Future<List<Map>> getUnsyncedImages() async {
    final allImages = _offlineImagesBox?.values.toList() ?? [];
    return allImages.where((image) => image['isSynced'] == false).toList();
  }

  Future<void> updateImageSyncStatus(String imageId, bool isSynced) async {
    final image = _offlineImagesBox?.get(imageId);
    if (image != null) {
      image['isSynced'] = isSynced;
      image['lastSyncAt'] = DateTime.now().toIso8601String();
      image['updatedAt'] = DateTime.now().toIso8601String();
      await _offlineImagesBox?.put(imageId, image);
    }
  }

  Future<void> deleteOfflineImage(String imageId) async {
    await _offlineImagesBox?.delete(imageId);
  }

  Future<void> updateOfflineImageRemoteUrl(
      String imageId, String remoteUrl) async {
    final image = _offlineImagesBox?.get(imageId);
    if (image != null) {
      image['remoteUrl'] = remoteUrl;
      image['isSynced'] = true;
      image['lastSyncAt'] = DateTime.now().toIso8601String();
      image['updatedAt'] = DateTime.now().toIso8601String();
      await _offlineImagesBox?.put(imageId, image);
    }
  }

  /// Get sync statistics
  Future<Map<String, int>> getSyncStatistics() async {
    final pendingSync = _syncQueueBox?.length ?? 0;
    final unsyncedImages = getUnsyncedImages().then((images) => images.length);
    final unsyncedRequests = getAllOfflineTravelRequests().then(
        (requests) => requests.where((req) => req['isSynced'] == false).length);
    final unsyncedRoutePoints = countUnsyncedRoutePoints();
    final unsyncedTrackingEvents = countUnsyncedTrackingEvents();

    return {
      'pendingSync': pendingSync,
      'offlineImages': await unsyncedImages,
      'offlineRequests': await unsyncedRequests,
      'routePoints': await unsyncedRoutePoints,
      'trackingEvents': await unsyncedTrackingEvents,
    };
  }

  // --- Route points (live GPS) ---

  Future<void> saveRoutePoint(Map<String, dynamic> pointMap) async {
    final id = pointMap['pointId']?.toString();
    if (id == null || id.isEmpty) return;
    await _routePointsBox?.put(id, Map<String, dynamic>.from(pointMap));
  }

  Future<List<Map<String, dynamic>>> getRoutePointsForRequest(
      String requestId) async {
    final box = _routePointsBox;
    if (box == null) return [];
    final out = <Map<String, dynamic>>[];
    for (final m in box.values) {
      if (m['requestId'] == requestId) {
        out.add(Map<String, dynamic>.from(m));
      }
    }
    out.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    return out;
  }

  /// Only points for one leg (avoids loading every GPS sample for the whole trip).
  Future<List<Map<String, dynamic>>> getRoutePointsForLeg(
      String requestId, String legId) async {
    final box = _routePointsBox;
    if (box == null) return [];
    final out = <Map<String, dynamic>>[];
    for (final m in box.values) {
      if (m['requestId'] == requestId && m['legId'] == legId) {
        out.add(Map<String, dynamic>.from(m));
      }
    }
    out.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    return out;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedRoutePoints(
      {int limit = 500}) async {
    final box = _routePointsBox;
    if (box == null) return [];
    final unsynced = <Map<String, dynamic>>[];
    for (final m in box.values) {
      if (m['isSynced'] != true) {
        unsynced.add(Map<String, dynamic>.from(m));
      }
    }
    unsynced.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    if (unsynced.length <= limit) return unsynced;
    return unsynced.sublist(0, limit);
  }

  Future<void> markRoutePointsSynced(Iterable<String> pointIds) async {
    for (final id in pointIds) {
      final m = _routePointsBox?.get(id);
      if (m != null) {
        m['isSynced'] = true;
        await _routePointsBox?.put(id, m);
      }
    }
  }

  Future<int> countRoutePointsForRequest(String requestId) async {
    final box = _routePointsBox;
    if (box == null) return 0;
    var n = 0;
    for (final m in box.values) {
      if (m['requestId'] == requestId) n++;
    }
    return n;
  }

  Future<int> countUnsyncedRoutePoints() async {
    final box = _routePointsBox;
    if (box == null) return 0;
    var n = 0;
    for (final m in box.values) {
      if (m['isSynced'] != true) n++;
    }
    return n;
  }

  Future<void> deleteRoutePointsForRequest(String requestId) async {
    if (requestId.isEmpty) return;
    final box = _routePointsBox;
    if (box == null) return;
    final keysToRemove = <dynamic>[];
    for (final entry in box.toMap().entries) {
      if (entry.value['requestId']?.toString() == requestId) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      await box.delete(key);
    }
  }

  Future<void> deleteOfflineImagesForRequest(String requestId) async {
    if (requestId.isEmpty) return;
    final box = _offlineImagesBox;
    if (box == null) return;
    final keysToRemove = <dynamic>[];
    for (final entry in box.toMap().entries) {
      if (entry.value['requestId']?.toString() == requestId) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      await box.delete(key);
    }
  }

  // --- Tracking events ---

  Future<void> saveTrackingEvent(Map<String, dynamic> eventMap) async {
    final id = eventMap['eventId']?.toString();
    if (id == null || id.isEmpty) return;
    await _trackingEventsBox?.put(id, Map<String, dynamic>.from(eventMap));
  }

  Future<List<Map<String, dynamic>>> getUnsyncedTrackingEvents({
    int limit = 100,
  }) async {
    final box = _trackingEventsBox;
    if (box == null) return [];
    final unsynced = <Map<String, dynamic>>[];
    for (final m in box.values) {
      if (m['isSynced'] != true) {
        unsynced.add(Map<String, dynamic>.from(m));
      }
    }
    unsynced.sort((a, b) {
      final ta = DateTime.tryParse(a['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final tb = DateTime.tryParse(b['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });
    if (unsynced.length <= limit) return unsynced;
    return unsynced.sublist(0, limit);
  }

  Future<void> markTrackingEventsSynced(Iterable<String> eventIds) async {
    for (final id in eventIds) {
      final m = _trackingEventsBox?.get(id);
      if (m != null) {
        m['isSynced'] = true;
        await _trackingEventsBox?.put(id, m);
      }
    }
  }

  Future<int> countUnsyncedTrackingEvents() async {
    final box = _trackingEventsBox;
    if (box == null) return 0;
    var n = 0;
    for (final m in box.values) {
      if (m['isSynced'] != true) n++;
    }
    return n;
  }

  Future<DateTime?> lastRoutePointTimestamp(String requestId) async {
    final points = await getRoutePointsForRequest(requestId);
    if (points.isEmpty) return null;
    final last = points.last['timestamp']?.toString();
    if (last == null) return null;
    return DateTime.tryParse(last)?.toUtc();
  }

  // --- Tracking coverage cache ---

  Future<void> saveTrackingCoverageCache(
    String requestId,
    Map<String, dynamic> data,
  ) async {
    if (requestId.isEmpty) return;
    await _trackingCoverageCacheBox?.put(
      requestId,
      {
        ...Map<String, dynamic>.from(data),
        'cachedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>?> getTrackingCoverageCache(
    String requestId,
  ) async {
    final row = _trackingCoverageCacheBox?.get(requestId);
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  // --- Matched route (official km / segments) ---

  Future<void> saveMatchedRouteCache(
    String requestId,
    Map<String, dynamic> data,
  ) async {
    if (requestId.isEmpty) return;
    await _matchedRouteCacheBox?.put(
      requestId,
      {
        ...Map<String, dynamic>.from(data),
        'cachedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<Map<String, dynamic>?> getMatchedRouteCache(String requestId) async {
    final row = _matchedRouteCacheBox?.get(requestId);
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }
}
