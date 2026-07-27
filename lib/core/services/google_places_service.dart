import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_maps_config.dart';
import '../models/picked_location.dart';

class PlacePrediction {
  const PlacePrediction({
    required this.placeId,
    required this.description,
    required this.mainText,
  });

  final String placeId;

  /// Full autocomplete line shown in the dropdown.
  final String description;

  /// Primary place name (business / landmark) the user intends to select.
  final String mainText;
}

class GooglePlacesService {
  Future<List<PlacePrediction>> autocomplete(String input) async {
    final query = input.trim();
    if (query.length < 2 || !GoogleMapsConfig.isConfigured) return [];

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'key': GoogleMapsConfig.apiKey,
        'components': 'country:in',
      },
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) return [];

    final data = jsonDecode(res.body);
    if (data is! Map || data['status'] != 'OK') return [];

    final predictions = data['predictions'];
    if (predictions is! List) return [];

    return predictions
        .map((p) {
          if (p is! Map) return null;
          final id = p['place_id']?.toString();
          final desc = p['description']?.toString();
          if (id == null || desc == null) return null;
          return PlacePrediction(
            placeId: id,
            description: desc,
            mainText: _mainTextFromPrediction(p, desc),
          );
        })
        .whereType<PlacePrediction>()
        .toList();
  }

  Future<PickedLocation?> placeDetails(
    String placeId, {
    required String selectedName,
  }) async {
    if (!GoogleMapsConfig.isConfigured) return null;

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'name,formatted_address,geometry,address_component',
        'key': GoogleMapsConfig.apiKey,
      },
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    if (data is! Map || data['status'] != 'OK') return null;

    final result = data['result'];
    if (result is! Map) return null;

    final geometry = result['geometry'];
    if (geometry is! Map) return null;
    final location = geometry['location'];
    if (location is! Map) return null;

    final lat = (location['lat'] as num?)?.toDouble();
    final lng = (location['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final formattedAddress = result['formatted_address']?.toString() ?? '';
    final apiName = result['name']?.toString();
    final city = _cityFromComponents(result['address_components']);
    final name = _resolveDisplayName(
      selectedName: selectedName,
      apiName: apiName,
      formattedAddress: formattedAddress,
    );

    return PickedLocation(
      name: name,
      formattedAddress:
          formattedAddress.isNotEmpty ? formattedAddress : null,
      latitude: lat,
      longitude: lng,
      city: city,
    );
  }

  static String _mainTextFromPrediction(Map<dynamic, dynamic> prediction,
      String description) {
    final structured = prediction['structured_formatting'];
    if (structured is Map) {
      final main = structured['main_text']?.toString().trim();
      if (main != null && main.isNotEmpty) return main;
    }
    final first = description.split(',').first.trim();
    return first.isNotEmpty ? first : description;
  }

  static String _resolveDisplayName({
    required String selectedName,
    String? apiName,
    required String formattedAddress,
  }) {
    final picked = selectedName.trim();
    if (picked.isNotEmpty) return picked;

    final fromApi = apiName?.trim();
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;

    final first = formattedAddress.split(',').first.trim();
    return first.isNotEmpty ? first : formattedAddress;
  }

  String? _cityFromComponents(dynamic components) {
    if (components is! List) return null;
    for (final c in components) {
      if (c is! Map) continue;
      final types = c['types'];
      if (types is! List) continue;
      if (types.contains('locality') ||
          types.contains('administrative_area_level_2')) {
        final name = c['long_name']?.toString();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return null;
  }
}
