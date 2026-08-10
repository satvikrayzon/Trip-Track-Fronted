/// Application constants and configuration values
class AppConstants {
  // Brand Colors
  static const int primaryColorValue = 0xFF095763;
  static const String primaryColorHex = '#095763';

  // App Information
  static const String appName = 'Rayzon Solar';
  static const String appVersion = '1.0.0';
  static const String privacyPolicyUrl =
      'https://triptrack-api.rayzonsolar.one/privacy-policy.html';

  // Backend sync queue uses this logical collection name for travel payloads.
  static const String travelRequestsCollection = 'travel_requests';

  // Storage Paths
  static const String imagesStoragePath = 'images';
  static const String startImagesPath = 'start_meter_images';
  static const String endImagesPath = 'end_meter_images';

  // User Roles
  static const String adminRole = 'admin';
  static const String managerRole = 'manager';
  static const String userRole = 'user';

  // Request Status
  static const String statusStartMissing = 'Start Missing';
  static const String statusEndMissing = 'End Missing';
  static const String statusReadyToStart = 'Ready To Start';
  static const String statusTravelling = 'Travelling';
  static const String statusAtClient = 'At Client';
  static const String statusInMeeting = 'In Meeting';
  static const String statusReadyForNext = 'Ready For Next';
  static const String statusReadyToReturn = 'Ready To Return';
  static const String statusReturning = 'Returning';
  static const String statusCompleted = 'Completed';

  // Vehicle types (API values — lowercase)
  static const String vehicleTypeCar = 'car';
  static const String vehicleTypeBike = 'bike';
  static const String vehicleTypeScooter = 'scooter';

  static const List<(String value, String label)> vehicleOptions = [
    (vehicleTypeCar, 'Car'),
    (vehicleTypeBike, 'Bike'),
  ];

  // Fuel / energy types (API values — lowercase)
  static const String fuelPetrol = 'petrol';
  static const String fuelDiesel = 'diesel';
  static const String fuelCng = 'cng';
  static const String fuelElectric = 'electric';

  static const List<String> carFuelOptions = [
    fuelPetrol,
    fuelDiesel,
    fuelCng,
    fuelElectric,
  ];

  static const List<String> bikeFuelOptions = [
    fuelPetrol,
    fuelElectric,
  ];

  static bool isBikeVehicle(String? value) {
    final v = value?.toLowerCase();
    return v == vehicleTypeBike || v == vehicleTypeScooter;
  }

  static bool vehicleRequiresFuelType(String? vehicleType) =>
      isCarVehicle(vehicleType) || isBikeVehicle(vehicleType);

  static List<String> fuelOptionsForVehicle(String? vehicleType) {
    if (isCarVehicle(vehicleType)) return carFuelOptions;
    if (isBikeVehicle(vehicleType)) return bikeFuelOptions;
    return const [];
  }

  static String vehicleTypeLabel(String? value) {
    switch (value?.toLowerCase()) {
      case vehicleTypeCar:
        return 'Car';
      case vehicleTypeBike:
        return 'Bike';
      case vehicleTypeScooter:
        return 'Scooter';
      default:
        return value ?? '';
    }
  }

  static String fuelTypeLabel(String? value) {
    switch (value?.toLowerCase()) {
      case fuelPetrol:
        return 'Petrol';
      case fuelDiesel:
        return 'Diesel';
      case fuelCng:
        return 'CNG';
      case fuelElectric:
        return 'Electric';
      default:
        return value ?? '';
    }
  }

  static bool isCarVehicle(String? value) =>
      value?.toLowerCase() == vehicleTypeCar;

  // Local Storage
  static const String localDbName = 'rayzon_solar.db';
  static const String syncQueueTable = 'sync_queue';
  static const String offlineImagesTable = 'offline_images';

  // Animation Durations
  static const Duration shortAnimationDuration = Duration(milliseconds: 300);
  static const Duration mediumAnimationDuration = Duration(milliseconds: 500);
  static const Duration longAnimationDuration = Duration(milliseconds: 800);

  // UI Constants - Modern & Compact
  static const double defaultPadding = 12.0;
  static const double smallPadding = 6.0;
  static const double largePadding = 16.0;
  static const double cardRadius = 16.0;
  static const double buttonRadius = 12.0;

  // Image Constants
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  static const int imageQuality = 85;
  static const double overlayTextFontSize = 14.0;

  // Sync Constants
  static const int maxRetryAttempts = 3;
  static const Duration syncTimeout = Duration(minutes: 5);
  static const Duration backgroundSyncInterval = Duration(minutes: 15);

  /// Live GPS: master switch (also per-request `enableLiveTracking` from API).
  static const bool featureLiveGpsTracking = true;

  /// When false (default), Dio does not print full request/error traces in debug.
  /// Enable with: flutter run --dart-define=VERBOSE_API_LOGS=true
  static const bool verboseApiLogging = bool.fromEnvironment(
    'VERBOSE_API_LOGS',
    defaultValue: false,
  );

  /// Legacy key for local route-point batches (API path is in [ApiEndpoints]).
  static const String routePointsSubcollection = 'route_points';

  /// Batch size for uploading route points to the API.
  static const int routePointsUploadBatchSize = 40;

  /// Gap between GPS points longer than this counts as missing tracking.
  static const int trackingGapThresholdSeconds = 90;

  static const int trackingEventsUploadBatchSize = 50;

  // TODO(temp): geofence radius checks disabled for testing — restore both
  // back to 500 before release.
  /// Departure punch: max distance from [fromLocation] coordinates (meters).
  static const double departureGeofenceRadiusMeters = 999999999;

  /// Arrival punch: max distance from [toLocation] coordinates (meters).
  static const double arrivalGeofenceRadiusMeters = 999999999;

  /// Warn while still inside the geofence but nearing the edge (meters).
  static const double punchReminderEdgeMeters = 350;

  /// How often the punch-reminder monitor samples location.
  static const Duration punchReminderPollInterval = Duration(seconds: 40);

  /// Minimum dwell inside destination before arrival nudge.
  static const Duration punchReminderArrivalDwell = Duration(minutes: 2);

  /// Cooldown between identical punch reminder notifications.
  static const Duration punchReminderNotifyCooldown = Duration(minutes: 4);

  /// Shorter cooldown when user is about to leave / already left the zone.
  static const Duration punchReminderUrgentCooldown = Duration(minutes: 2);

  /// Reject GPS fixes worse than this accuracy (meters).
  static const double punchMaxAccuracyMeters = 100;

  /// Max wait for a fresh GPS fix on punch.
  static const Duration punchLocationTimeout = Duration(seconds: 10);

  static const Duration punchLastKnownMaxAge = Duration(seconds: 90);
  static const Duration punchCachedPositionMaxAge = Duration(seconds: 30);

  // Validation
  static const int minPasswordLength = 6;
  static const int maxNameLength = 50;
  static const int maxLocationLength = 100;

  // Error Messages
  static const String networkErrorMessage = 'No internet connection';
  static const String genericErrorMessage =
      'Something went wrong. Please try again.';
  static const String authenticationErrorMessage = 'Authentication failed';
  static const String permissionErrorMessage = 'Permission denied';
}
