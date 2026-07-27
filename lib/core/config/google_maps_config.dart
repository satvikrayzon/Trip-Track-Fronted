/// Google Maps / Places API key for HTTP calls (Directions, Places).
/// Native map tiles use the key in AndroidManifest / iOS AppDelegate.
abstract final class GoogleMapsConfig {
  static const String apiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyCIQpnYm2zzBj6T3zZljkbym47hcvYr1qA',
  );

  static bool get isConfigured => apiKey.trim().isNotEmpty;
}
