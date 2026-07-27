import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../../core/config/api_env.dart';
import '../../../../core/network/token_store.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../modules/travel/data/models/travel_request_model.dart';
import '../../domain/entities/employee_tracking_status.dart';

/// Real-time employee locations for admin live map using Socket.IO.
///
/// Backend expectation:
/// - Namespace: `/tracking`
/// - JWT passed via Socket.IO handshake `auth`
class WebSocketTrackingService {
  WebSocketTrackingService(this._tokenStore) {
    _initConnectivity();
  }

  final TokenStore _tokenStore;
  io.Socket? _socket;
  Timer? _reconnectTimer;
  final Set<String> _joinedRooms = {};

  final _employeesController =
      StreamController<List<TrackedEmployee>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _tripUpdatesController =
      StreamController<TravelRequestModel>.broadcast();
  final _tripRefetchController = StreamController<String>.broadcast();
  final _locationUpdatesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _tripDeleteController = StreamController<String>.broadcast();
  final Map<String, TrackedEmployee> _roster = {};

  bool _connected = false;
  bool _connecting = false;
  bool _manuallyClosed = false;
  bool _backendUnavailable = false;
  int _connectFailures = 0;
  DateTime? _lastMessageAt;
  DateTime? _lastTripUpdateAt;

  static const _maxConnectFailures = 3;
  static const _handshakeTimeout = Duration(seconds: 6);

  Stream<List<TrackedEmployee>> get employeesStream =>
      _employeesController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<TravelRequestModel> get tripUpdates => _tripUpdatesController.stream;

  /// Emits a trip/request id when status changed but full trip body was not sent.
  Stream<String> get tripRefetchIds => _tripRefetchController.stream;

  /// Emits real-time location coordinate updates for maps.
  Stream<Map<String, dynamic>> get locationUpdates => _locationUpdatesController.stream;

  /// Emits a trip/request id when it is deleted.
  Stream<String> get tripDeletes => _tripDeleteController.stream;

  bool get isConnected => _connected;
  bool get isBackendUnavailable => _backendUnavailable;
  DateTime? get lastMessageAt => _lastMessageAt;

  /// True when socket is currently connected.
  bool get isTripRealtimeLive => _connected;
  List<TrackedEmployee> get currentEmployees =>
      List<TrackedEmployee>.unmodifiable(_roster.values);

  /// Candidate Socket.IO URLs (namespace `/tracking`).
  ///
  /// Your backend expects:
  /// - URL: `http://host:port/tracking` (not `/live`)
  /// - JWT passed via Socket.IO handshake `auth` (not `?token=...`)
  List<String> _socketCandidates() {
    final base = ApiEnv.baseUrl.trim();
    final stripped =
        base.endsWith('/api') ? base.substring(0, base.length - 4) : base;

    // Try both: with and without `/api` prefix on the base URL.
    final set = <String>{'$stripped/tracking', '$base/tracking'};
    return set.toList();
  }

  Future<void> connect() async {

    if (_connected ||
        _connecting ||
        _socket != null) {
      return;
    }

    final token = _tokenStore.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }

    _manuallyClosed = false;
    _connecting = true;

    try {
      bool connected = false;
      for (final url in _socketCandidates()) {
        try {
          await _connectOnce(url: url, token: token);
          connected = true;
          break;
        } catch (e) {
        }
      }

      if (!connected) {
        _recordFailure();
        _handleDisconnect(scheduleReconnect: !_backendUnavailable);
      }
    } catch (e) {
      _recordFailure();
      _handleDisconnect(scheduleReconnect: !_backendUnavailable);
    } finally {
      _connecting = false;
    }
  }

  Future<void> _connectOnce({
    required String url,
    required String token,
  }) async {

    final completer = Completer<void>();
    final socket = io.io(
      url,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .disableReconnection()
          .enableForceNew()
          .setAuth({
            'token': token,
            // Some backends use different auth key names.
            'authorization': token,
          })
          .build(),
    );

    _socket = socket;

    bool didConnect = false;

    socket.onConnect((_) {
      didConnect = true;

      _connected = true;
      _connectFailures = 0;
      _backendUnavailable = false;
      _connectionController.add(true);

      // Rejoin all active rooms on connection / reconnection
      for (final room in _joinedRooms) {
        socket.emit('tracking.join', {'tripId': room});
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    socket.onConnectError((Object? err) {

      if (completer.isCompleted) return;
      completer.completeError(err ?? Exception('SocketIO connect_error'));
    });

    socket.onDisconnect((data) {
      if (!didConnect) return;
      if (_manuallyClosed || _backendUnavailable) {
        _handleDisconnect(scheduleReconnect: false);
        return;
      }
      // Unexpected disconnect after a successful connect.
      _handleDisconnect(scheduleReconnect: true);
    });

    socket.onAny((event, data) {
      final e = event.toString().toLowerCase();
      if (e == 'connect' ||
          e == 'disconnect' ||
          e == 'connect_error' ||
          e == 'error' ||
          e == 'reconnect' ||
          e == 'reconnect_attempt' ||
          e == 'reconnect_failed') {
        return;
      }
      _handleSocketPayload(data, eventName: e);
    });

    socket.connect();

    try {
      await completer.future.timeout(_handshakeTimeout);
    } catch (e) {
      try {
        socket.dispose();
      } catch (_) {}
      if (identical(_socket, socket)) _socket = null;
      _connected = false;
      rethrow;
    }
  }

  void _recordFailure() {
    _connectFailures++;
    if (_connectFailures >= _maxConnectFailures) {
      _backendUnavailable = true;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
  }

  void _handleSocketPayload(dynamic payload, {String? eventName}) {
    try {
      _lastMessageAt = DateTime.now();

      if (eventName == 'trip.location.updated') {
        Map<String, dynamic>? dataMap;
        if (payload is Map) {
          dataMap = Map<String, dynamic>.from(payload);
        } else if (payload is String) {
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map) dataMap = Map<String, dynamic>.from(decoded);
          } catch (_) {}
        }
        if (dataMap != null) {
          _locationUpdatesController.add(dataMap);

          final userId = dataMap['userId']?.toString() ?? '';
          final requestId = dataMap['requestId']?.toString() ?? '';
          final tripId = dataMap['tripId']?.toString() ?? '';

          String? foundKey;
          TrackedEmployee? existing;
          if (userId.isNotEmpty && _roster.containsKey(userId)) {
            foundKey = userId;
            existing = _roster[userId];
          } else if (requestId.isNotEmpty && _roster.containsKey(requestId)) {
            foundKey = requestId;
            existing = _roster[requestId];
          } else {
            for (final entry in _roster.entries) {
              if ((requestId.isNotEmpty && entry.value.activeTripId == requestId) ||
                  (tripId.isNotEmpty && entry.value.activeTripId == tripId) ||
                  (userId.isNotEmpty && entry.key == userId)) {
                foundKey = entry.key;
                existing = entry.value;
                break;
              }
            }
          }

          if (foundKey != null && existing != null) {
            final lat = (dataMap['latitude'] as num?)?.toDouble();
            final lng = (dataMap['longitude'] as num?)?.toDouble();
            if (lat != null && lng != null) {
              final speed = (dataMap['speed'] as num?)?.toDouble() ?? 0.0;
              final bearing = (dataMap['heading'] ?? dataMap['bearing'] as num?)?.toDouble() ?? 0.0;
              final newPoint = LatLng(lat, lng);
              final updatedEmployee = existing.copyWith(
                position: newPoint,
                path: existing.path.isEmpty
                    ? [existing.position, newPoint]
                    : (existing.path.last != newPoint ? [...existing.path, newPoint] : existing.path),
                speedKmh: speed * 3.6,
                bearing: bearing,
                lastUpdated: DateTime.tryParse(dataMap['timestamp']?.toString() ?? '') ?? DateTime.now(),
              );
              _roster[foundKey] = updatedEmployee;
              _employeesController.add(currentEmployees);
            }
          }
        }
      }

      if (eventName == 'trip:delete') {
        final id = payload?.toString() ?? '';
        if (id.isNotEmpty) {
          _tripDeleteController.add(id);
        }
      }

      bool changed = false;

      bool mergeOne(Map<String, dynamic> json) {
        final parsed = _parseEmployee(json);
        if (parsed == null) return false;
        final id = parsed.id;
        if (id.isEmpty) return false;

        final previous = _roster[id];
        final merged = previous == null ? parsed : _merge(previous, parsed);
        _roster[id] = merged;
        _maybeEmitTripRefetch(previous, merged);
        return true;
      }

      bool mergeList(List list) {
        var listChanged = false;
        for (final item in list) {
          if (item is! Map) continue;
          listChanged |= mergeOne(Map<String, dynamic>.from(item));
        }
        return listChanged;
      }

      Map<String, dynamic>? decodedMap;
      List? decodedList;

      if (payload is String) {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) decodedMap = decoded;
        if (decoded is List) decodedList = decoded;
      } else if (payload is Map<String, dynamic>) {
        decodedMap = payload;
      } else if (payload is Map) {
        decodedMap = Map<String, dynamic>.from(payload);
      } else if (payload is List) {
        decodedList = payload;
      }

      if (decodedMap != null) {
        final map = decodedMap;
        _tryEmitTripUpdate(map, eventName: eventName);
        final type = map['type']?.toString().toLowerCase();

        if (type == 'location_update' || type == 'employee_update') {
          final inner = map['employee'] ?? map['payload'] ?? map;
          if (inner is Map) {
            changed = mergeOne(Map<String, dynamic>.from(inner));
          }
        } else if (map['employee'] is Map) {
          changed = mergeOne(
            Map<String, dynamic>.from(map['employee'] as Map),
          );
        } else if (map['employees'] is List) {
          changed = mergeList(map['employees'] as List);
        } else if (map['data'] is List) {
          changed = mergeList(map['data'] as List);
        } else {
          changed = mergeOne(map);
        }
      } else if (decodedList != null) {
        changed = mergeList(decodedList);
      }

      if (changed) _employeesController.add(currentEmployees);
    } catch (e) {
    }
  }

  void _maybeEmitTripRefetch(TrackedEmployee? previous, TrackedEmployee update) {
    final tripId = update.activeTripId;
    if (tripId == null || tripId.isEmpty) return;

    final statusChanged = previous?.tripStatus != update.tripStatus;
    final tripFlagChanged =
        update.hasActiveTrip && (previous == null || !previous.hasActiveTrip);
    if (!statusChanged && !tripFlagChanged) return;

    _lastTripUpdateAt = DateTime.now();
    _tripRefetchController.add(tripId);
  }

  void _tryEmitTripUpdate(
    Map<String, dynamic> map, {
    String? eventName,
  }) {
    final trip = _parseTripUpdateMap(map, eventName: eventName);
    if (trip == null) return;
    _lastTripUpdateAt = DateTime.now();
    if (!_tripUpdatesController.isClosed) {
      _tripUpdatesController.add(trip);
    }
  }

  TravelRequestModel? _parseTripUpdateMap(
    Map<String, dynamic> map, {
    String? eventName,
  }) {
    final type = (map['type'] ?? eventName ?? '').toString().toLowerCase();
    final tripEvent = type.contains('trip') ||
        type.contains('travel') ||
        type.contains('request') ||
        type.contains('punch');

    Map<String, dynamic>? tripMap;

    if (tripEvent) {
      for (final key in [
        'trip',
        'travelRequest',
        'travel_request',
        'request',
        'payload',
        'data',
      ]) {
        final value = map[key];
        if (value is Map) {
          tripMap = Map<String, dynamic>.from(value);
          break;
        }
      }
    }

    tripMap ??= _looksLikeTravelRequest(map) ? map : null;

    final employee = map['employee'];
    if (tripMap == null && employee is Map) {
      for (final key in ['trip', 'travelRequest', 'activeTrip', 'request']) {
        final value = Map<String, dynamic>.from(employee)[key];
        if (value is Map) {
          tripMap = Map<String, dynamic>.from(value);
          break;
        }
      }
    }

    if (tripMap == null) return null;

    try {
      return TravelRequestModel.fromMap(tripMap).ensureTripLegs();
    } catch (e) {
      return null;
    }
  }

  bool _looksLikeTravelRequest(Map<String, dynamic> map) {
    final hasId = map['requestId'] != null ||
        map['_id'] != null ||
        map['tripId'] != null ||
        map['id'] != null;
    final hasLegs = map['tripLegs'] is List || map['legs'] is List;
    final hasStatus = map['status'] != null;
    return hasId && (hasLegs || hasStatus);
  }

  TrackedEmployee _merge(TrackedEmployee existing, TrackedEmployee update) {
    final keepName = _isGenericEmployeeName(update.name);
    return existing.copyWith(
      name: keepName ? existing.name : update.name,
      team: update.team ?? existing.team,
      position: update.position,
      speedKmh: update.speedKmh,
      batteryPercent: update.batteryPercent,
      bearing: update.bearing,
      status: update.status,
      hasActiveTrip: update.hasActiveTrip || existing.hasActiveTrip,
      activeTripId: update.activeTripId ?? existing.activeTripId,
      lastUpdated: update.lastUpdated,
      email: update.email ?? existing.email,
      employeeCode: update.employeeCode ?? existing.employeeCode,
      mobile: update.mobile ?? existing.mobile,
      role: update.role ?? existing.role,
      reportingManagerName:
          update.reportingManagerName ?? existing.reportingManagerName,
      tripStatus: update.tripStatus ?? existing.tripStatus,
      tripFrom: update.tripFrom ?? existing.tripFrom,
      tripTo: update.tripTo ?? existing.tripTo,
    );
  }

  bool _isGenericEmployeeName(String name) {
    final n = name.trim().toLowerCase();
    return n.isEmpty ||
        n == 'employee' ||
        n == 'user' ||
        n == 'unknown' ||
        n == 'on trip';
  }

  TrackedEmployee? _parseEmployee(Map<String, dynamic> json) {
    var lat = (json['latitude'] as num?)?.toDouble() ??
        (json['lat'] as num?)?.toDouble();
    var lng = (json['longitude'] as num?)?.toDouble() ??
        (json['lng'] as num?)?.toDouble();

    final nested = json['position'] ?? json['location'] ?? json['coordinates'];
    if ((lat == null || lng == null) && nested is Map) {
      final map = Map<String, dynamic>.from(nested);
      lat ??= (map['latitude'] as num?)?.toDouble() ??
          (map['lat'] as num?)?.toDouble();
      lng ??= (map['longitude'] as num?)?.toDouble() ??
          (map['lng'] as num?)?.toDouble();
    }

    if (lat == null || lng == null) return null;
    if (lat.abs() < 1e-6 && lng.abs() < 1e-6) return null;

    final statusRaw =
        json['status']?.toString() ?? json['trackingStatus']?.toString() ?? '';
    final status = switch (statusRaw.toLowerCase()) {
      'active' || 'tracking' || 'travelling' || 'returning' =>
        TrackingMarkerStatus.active,
      'online' || 'in meeting' || 'at client' => TrackingMarkerStatus.online,
      'gps_stopped' || 'paused' => TrackingMarkerStatus.gpsStopped,
      _ => TrackingMarkerStatus.offline,
    };

    final id = json['id']?.toString() ??
        json['userId']?.toString() ??
        json['uid']?.toString() ??
        '';
    if (id.isEmpty) return null;

    final nestedUser = json['user'];
    var rawName = json['name']?.toString().trim();
    if ((rawName == null || rawName.isEmpty) && nestedUser is Map) {
      rawName = Map<String, dynamic>.from(nestedUser)['name']?.toString().trim();
    }
    rawName = rawName != null && rawName.isNotEmpty ? rawName : 'Employee';

    return TrackedEmployee(
      id: id,
      name: rawName,
      avatarUrl: json['avatarUrl']?.toString(),
      team: json['team']?.toString(),
      position: LatLng(lat, lng),
      speedKmh: (json['speedKmh'] as num?)?.toDouble() ??
          (json['speed'] as num?)?.toDouble() ??
          0,
      batteryPercent: (json['batteryPercent'] as num?)?.toInt() ?? 100,
      bearing: (json['bearing'] as num?)?.toDouble() ?? 0,
      status: status,
      hasActiveTrip:
          json['hasActiveTrip'] == true || json['activeTripId'] != null,
      activeTripId: json['activeTripId']?.toString() ??
          json['requestId']?.toString() ??
          json['tripId']?.toString(),
      lastUpdated: DateTime.tryParse(json['lastUpdated']?.toString() ?? '') ??
          DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      email: json['email']?.toString(),
      employeeCode: json['employeeCode']?.toString(),
      mobile: json['mobile']?.toString() ?? json['mobileNumber']?.toString(),
      role: json['role']?.toString(),
      reportingManagerName: json['reportingManagerName']?.toString(),
      tripStatus: json['tripStatus']?.toString(),
      tripFrom: json['tripFrom']?.toString() ?? json['fromLocation']?.toString(),
      tripTo: json['tripTo']?.toString() ?? json['toLocation']?.toString(),
    );
  }

  void _handleDisconnect({bool scheduleReconnect = false}) {
    final wasConnected = _connected;
    _connected = false;
    _connecting = false;
    if (wasConnected) _connectionController.add(false);

    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        socket.dispose();
      } catch (_) {}
    }

    if (!_manuallyClosed) {
      _reconnectTimer?.cancel();
      final delay = _backendUnavailable ? const Duration(seconds: 45) : const Duration(seconds: 15);
      _reconnectTimer = Timer(delay, () {
        unawaited(connect());
      });
    }
  }

  Future<void> disconnect() async {
    _manuallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _handleDisconnect();
    _roster.clear();
    _joinedRooms.clear();
  }

  Future<bool> emitLocationUpdate({
    required String tripId,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    double? speed,
    double? bearing,
    double? accuracy,
    String? address,
    String? pointId,
    String? requestId,
    String? legId,
    String? sessionId,
  }) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      return false;
    }

    final completer = Completer<bool>();
    final payload = {
      'tripId': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toUtc().toIso8601String(),
      if (speed != null) 'speed': speed,
      if (bearing != null) 'bearing': bearing,
      if (bearing != null) 'heading': bearing,
      if (accuracy != null) 'accuracy': accuracy,
      if (address != null && address.isNotEmpty) 'address': address,
      if (pointId != null && pointId.isNotEmpty) 'pointId': pointId,
      if (requestId != null && requestId.isNotEmpty) 'requestId': requestId,
      if (legId != null && legId.isNotEmpty) 'legId': legId,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
    };

    socket.emitWithAck('tracking.location.update', payload, ack: (data) {
      if (data is Map) {
        final ok = data['ok'] == true || data['persisted'] == true;
        completer.complete(ok);
      } else {
        completer.complete(false);
      }
    });

    try {
      return await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      return false;
    }
  }

  void joinTripRoom(String tripId) {
    _joinedRooms.add(tripId);
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit('tracking.join', {'tripId': tripId});
    }
  }

  void leaveTripRoom(String tripId) {
    _joinedRooms.remove(tripId);
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit('tracking.leave', {'tripId': tripId});
    }
  }

  void _initConnectivity() {
    Future.microtask(() {
      if (ServiceLocator.I.has<ConnectivityService>()) {
        ServiceLocator.I.get<ConnectivityService>().onConnectivityChanged.listen((online) {
          if (online) {
            _backendUnavailable = false;
            _connectFailures = 0;
            if (!_connected && !_connecting && !_manuallyClosed) {
              unawaited(connect());
            }
          }
        });
      }
    });
  }

  void dispose() {
    disconnect();
    _employeesController.close();
    _connectionController.close();
    _tripUpdatesController.close();
    _tripRefetchController.close();
    _locationUpdatesController.close();
    _tripDeleteController.close();
  }
}
