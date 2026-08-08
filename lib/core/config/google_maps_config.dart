/// Google Maps API key for client HTTP calls (Directions, Roads Snap, Places).
/// Native map tiles use the key in AndroidManifest / iOS AppDelegate.
abstract final class GoogleMapsConfig {
  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyC31E3HDIZHp0-yn50EqhYN5TPNfptFJYk',
  );

  static bool get isConfigured => apiKey.trim().isNotEmpty;
}
