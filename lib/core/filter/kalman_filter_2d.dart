import 'dart:math' as math;

/// A 2D Extended Kalman Filter for smoothing GPS lat/lng coordinate streams
/// using a constant velocity model.
class KalmanFilter2D {
  /// Reference latitude for local Mercator/flat projection calculations.
  double? _refLat;

  /// State vector: [x, y, vx, vy] in meters & m/s
  double _x = 0;
  double _y = 0;
  double _vx = 0;
  double _vy = 0;

  /// Error covariance matrix (4x4)
  List<List<double>> _pMatrix = [
    [100, 0, 0, 0],
    [0, 100, 0, 0],
    [0, 0, 25, 0],
    [0, 0, 0, 25],
  ];

  DateTime? _lastTimestamp;
  bool _isInitialized = false;

  /// Process noise covariance magnitude (acceleration uncertainty m/s^2)
  final double processNoise;

  KalmanFilter2D({this.processNoise = 3.0});

  /// Reset the filter state (e.g., when starting a new tracking leg/session).
  void reset() {
    _isInitialized = false;
    _refLat = null;
    _lastTimestamp = null;
    _pMatrix = [
      [100, 0, 0, 0],
      [0, 100, 0, 0],
      [0, 0, 25, 0],
      [0, 0, 0, 25],
    ];
  }

  /// Filters a raw GPS measurement (latitude, longitude, timestamp, reported accuracy in meters).
  /// Returns a map with smoothed `latitude`, `longitude`, `speedMps`, and `isFiltered`.
  Map<String, double> process({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    required double accuracy,
  }) {
    // If raw accuracy is extremely poor (>100m), return raw with flag
    final rVar = math.max(accuracy * accuracy, 4.0); // Variance in m^2

    if (!_isInitialized) {
      _refLat = latitude;
      _x = 0;
      _y = 0;
      _vx = 0;
      _vy = 0;
      _lastTimestamp = timestamp;
      _isInitialized = true;
      return {
        'latitude': latitude,
        'longitude': longitude,
        'speedMps': 0.0,
      };
    }

    final dt = timestamp.difference(_lastTimestamp!).inMilliseconds / 1000.0;
    _lastTimestamp = timestamp;

    if (dt <= 0) {
      final currentLatLng = _metersToLatLng(_x, _y);
      return {
        'latitude': currentLatLng['latitude']!,
        'longitude': currentLatLng['longitude']!,
        'speedMps': math.sqrt(_vx * _vx + _vy * _vy),
      };
    }

    // Convert incoming lat/lng to local meters (x, y) relative to refLat
    final localMeters = _latLngToMeters(latitude, longitude);
    final zX = localMeters['x']!;
    final zY = localMeters['y']!;

    // --- 1. PREDICT STEP ---
    // State extrapolation: x_k = F * x_{k-1}
    _x += _vx * dt;
    _y += _vy * dt;

    // Process Noise Matrix Q (based on piece-wise constant acceleration model)
    final dt2 = dt * dt;
    final dt3 = dt2 * dt / 2.0;
    final dt4 = dt2 * dt2 / 4.0;
    final qVal = processNoise * processNoise;

    final qMatrix = [
      [dt4 * qVal, 0, dt3 * qVal, 0],
      [0, dt4 * qVal, 0, dt3 * qVal],
      [dt3 * qVal, 0, dt2 * qVal, 0],
      [0, dt3 * qVal, 0, dt2 * qVal],
    ];

    // Covariance extrapolation: P = F * P * F^T + Q
    // F = [[1, 0, dt, 0], [0, 1, 0, dt], [0, 0, 1, 0], [0, 0, 0, 1]]
    final pNew = List.generate(4, (_) => List.generate(4, (_) => 0.0));

    // F * P
    final fpMatrix = [
      [
        _pMatrix[0][0] + dt * _pMatrix[2][0],
        _pMatrix[0][1] + dt * _pMatrix[2][1],
        _pMatrix[0][2] + dt * _pMatrix[2][2],
        _pMatrix[0][3] + dt * _pMatrix[2][3]
      ],
      [
        _pMatrix[1][0] + dt * _pMatrix[3][0],
        _pMatrix[1][1] + dt * _pMatrix[3][1],
        _pMatrix[1][2] + dt * _pMatrix[2][2],
        _pMatrix[1][3] + dt * _pMatrix[3][3]
      ],
      [_pMatrix[2][0], _pMatrix[2][1], _pMatrix[2][2], _pMatrix[2][3]],
      [_pMatrix[3][0], _pMatrix[3][1], _pMatrix[3][2], _pMatrix[3][3]],
    ];

    // (F * P) * F^T + Q
    for (int i = 0; i < 4; i++) {
      for (int j = 0; j < 4; j++) {
        double val = fpMatrix[i][j];
        if (j == 0) val += dt * fpMatrix[i][2];
        if (j == 1) val += dt * fpMatrix[i][3];
        pNew[i][j] = val + qMatrix[i][j];
      }
    }
    _pMatrix = pNew;

    // --- 2. UPDATE STEP ---
    // Innovation (measurement residual): y = z - H * x
    // H = [[1, 0, 0, 0], [0, 1, 0, 0]]
    final yX = zX - _x;
    final yY = zY - _y;

    // Innovation covariance: S = H * P * H^T + R
    final sX = _pMatrix[0][0] + rVar;
    final sY = _pMatrix[1][1] + rVar;

    // Kalman Gain: K = P * H^T * S^-1
    final k00 = _pMatrix[0][0] / sX;
    final k11 = _pMatrix[1][1] / sY;
    final k20 = _pMatrix[2][0] / sX;
    final k31 = _pMatrix[3][1] / sY;

    // State update: x = x + K * y
    _x += k00 * yX;
    _y += k11 * yY;
    _vx += k20 * yX;
    _vy += k31 * yY;

    // Covariance update: P = (I - K * H) * P
    _pMatrix[0][0] *= (1.0 - k00);
    _pMatrix[0][2] *= (1.0 - k00);
    _pMatrix[1][1] *= (1.0 - k11);
    _pMatrix[1][3] *= (1.0 - k11);
    _pMatrix[2][0] -= k20 * _pMatrix[0][0];
    _pMatrix[2][2] -= k20 * _pMatrix[0][2];
    _pMatrix[3][1] -= k31 * _pMatrix[1][1];
    _pMatrix[3][3] -= k31 * _pMatrix[1][3];

    // Convert smoothed local meters back to lat/lng
    final filteredLatLng = _metersToLatLng(_x, _y);

    return {
      'latitude': filteredLatLng['latitude']!,
      'longitude': filteredLatLng['longitude']!,
      'speedMps': math.sqrt(_vx * _vx + _vy * _vy),
    };
  }

  Map<String, double> _latLngToMeters(double lat, double lng) {
    const metersPerLatDegree = 111320.0;
    final refRad = (_refLat ?? lat) * math.pi / 180.0;
    final metersPerLngDegree = 111320.0 * math.cos(refRad);

    final y = (lat - _refLat!) * metersPerLatDegree;
    final x = lng * metersPerLngDegree; // local x
    return {'x': x, 'y': y};
  }

  Map<String, double> _metersToLatLng(double x, double y) {
    const metersPerLatDegree = 111320.0;
    final refRad = (_refLat ?? 0) * math.pi / 180.0;
    final metersPerLngDegree = 111320.0 * math.cos(refRad);

    final lat = _refLat! + (y / metersPerLatDegree);
    final lng = x / metersPerLngDegree;
    return {'latitude': lat, 'longitude': lng};
  }
}
