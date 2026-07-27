/// Backend base URL (no trailing slash — Dio merges paths like `/auth/login`).
///
/// If login returns 404 with `Cannot POST /api/auth/login`, your Nest route is
/// not under that prefix — try `http://host:port` (no `/api`) or match your
/// global prefix (e.g. `/api/v1`).
///
/// Override for staging/production:
/// `flutter run --dart-define=API_BASE_URL=https://other.host/api`
class ApiEnv {
  ApiEnv._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://triptrack-api.rayzonsolar.one/api',
    // defaultValue: 'http://172.17.51.195:3000/api',
  );

  static bool get isConfigured => baseUrl.trim().isNotEmpty;
}
