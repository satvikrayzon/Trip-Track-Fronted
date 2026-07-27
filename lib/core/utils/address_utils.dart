import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import '../config/google_maps_config.dart';

/// Helpers for displaying location strings in the UI.
abstract final class AddressUtils {
  /// Compact label for route cards and timelines.
  ///
  /// Google-style addresses are often `"Place, Street, City, State, Country"`.
  /// This keeps the first [maxSegments] parts (default: place + area).
  static String shortAddress(String? address, {int maxSegments = 2}) {
    final trimmed = address?.trim() ?? '';
    if (trimmed.isEmpty) return '';

    final segments = trimmed
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (segments.isEmpty) return trimmed;
    if (segments.length <= maxSegments) return trimmed;

    return segments.take(maxSegments).join(', ');
  }

  /// Reverse-geocode GPS coordinates to a human-readable address.
  static Future<String> reverseGeocode(double lat, double lng) async {
    // 1. Try Google Maps Geocoding API if configured
    if (GoogleMapsConfig.isConfigured) {
      try {
        final uri = Uri.https(
          'maps.googleapis.com',
          '/maps/api/geocode/json',
          {
            'latlng': '$lat,$lng',
            'key': GoogleMapsConfig.apiKey,
          },
        );
        final response =
            await http.get(uri).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map && data['status'] == 'OK') {
            final results = data['results'] as List;
            if (results.isNotEmpty) {
              final first = results.first as Map;
              final formattedAddress =
                  first['formatted_address']?.toString() ?? '';
              if (formattedAddress.isNotEmpty) {
                return formattedAddress;
              }
            }
          }
        }
      } catch (e) {
      }
    }

    // 2. Try native geocoding (if not on Web)
    if (!kIsWeb) {
      try {
        final placemarks = await placemarkFromCoordinates(lat, lng)
            .timeout(const Duration(seconds: 5));
        if (placemarks.isNotEmpty) {
          final first = placemarks.first;
          final parts = [
            if (first.name != null && first.name != first.street) first.name,
            first.street,
            first.subLocality,
            first.locality,
            first.postalCode,
            first.administrativeArea,
            first.country,
          ]
              .where((e) => e != null && e.trim().isNotEmpty)
              .map((e) => e!.trim())
              .toList();
          if (parts.isNotEmpty) {
            return parts.join(', ');
          }
        }
      } catch (e) {
      }
    }

    // 3. Fallback to coordinate representation
    return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
  }
}

