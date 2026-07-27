import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A place chosen via Places search.
class PickedLocation {
  const PickedLocation({
    required this.name,
    this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.city,
  });

  /// Place name the user picked (e.g. business name from autocomplete).
  final String name;

  /// Full formatted address from Google Place Details (for reference).
  final String? formattedAddress;

  final double latitude;
  final double longitude;
  final String? city;

  /// Label sent to the API and shown in route UI.
  String get address => name;

  LatLng get latLng => LatLng(latitude, longitude);

  Map<String, double> toCoordinatesMap() => {
        'latitude': latitude,
        'longitude': longitude,
      };
}
