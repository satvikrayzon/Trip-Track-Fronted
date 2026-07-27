import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

import '../config/google_maps_config.dart';
import '../layout/adaptive_layout.dart';
import '../models/picked_location.dart';
import '../services/punch_location_service.dart';
import '../services/google_places_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/google_map_controller_utils.dart';
import '../widgets/app_button.dart';
import '../widgets/app_map_tile_layer.dart';

/// Screen allowing the user to visually pick a location from a map.
class MapLocationPickerScreen extends StatefulWidget {
  const MapLocationPickerScreen({
    super.key,
    required this.label,
    this.initialLocation,
  });

  final String label;
  final LatLng? initialLocation;

  @override
  State<MapLocationPickerScreen> createState() =>
      _MapLocationPickerScreenState();
}

class _MapLocationPickerScreenState extends State<MapLocationPickerScreen> {
  GoogleMapController? _googleMapController;
  final fm.MapController _osmMapController = fm.MapController();

  LatLng _cameraPosition = const LatLng(23.0225, 72.5714);
  bool _useGoogleMaps = false;
  bool _mapCreated = false;

  final ValueNotifier<String> _addressNotifier =
      ValueNotifier<String>('Drag the map to choose location');
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _confirmEnabledNotifier =
      ValueNotifier<bool>(false);

  PickedLocation? _resolvedLocation;
  Timer? _debounceTimer;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<PlacePrediction> _predictions = [];
  bool _searching = false;
  final GooglePlacesService _placesService = GooglePlacesService();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _useGoogleMaps = googleMapsSupported();
    if (widget.initialLocation != null) {
      _cameraPosition = widget.initialLocation!;
      _geocodePosition(_cameraPosition);
    } else {
      _loadCurrentLocation();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _addressNotifier.dispose();
    _loadingNotifier.dispose();
    _confirmEnabledNotifier.dispose();
    _osmMapController.dispose();
    safeDisposeGoogleMapController(
      _googleMapController,
      mapCreated: _mapCreated,
    );
    _googleMapController = null;
    _mapCreated = false;
    super.dispose();
  }

  Future<void> _loadCurrentLocation() async {
    _loadingNotifier.value = true;
    try {
      final service = PunchLocationService();
      final pos = await service.getFastPosition();
      if (pos != null && mounted) {
        final target = LatLng(pos.latitude, pos.longitude);
        setState(() {
          _cameraPosition = target;
        });

        if (_useGoogleMaps && _googleMapController != null) {
          _googleMapController?.moveCamera(CameraUpdate.newLatLng(target));
        } else {
          _osmMapController.move(
            ll.LatLng(target.latitude, target.longitude),
            15,
          );
        }
        _geocodePosition(target);
      } else {
        _geocodePosition(_cameraPosition);
      }
    } catch (_) {
      _geocodePosition(_cameraPosition);
    }
  }

  void _onOsmPositionChanged(ll.LatLng center) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _geocodePosition(LatLng(center.latitude, center.longitude));
    });
  }

  Future<void> _geocodePosition(LatLng position) async {
    _loadingNotifier.value = true;
    _confirmEnabledNotifier.value = false;

    try {
      final resolved = await _reverseGeocode(
        position.latitude,
        position.longitude,
      );

      _resolvedLocation = PickedLocation(
        name: resolved.name,
        formattedAddress: resolved.address,
        latitude: position.latitude,
        longitude: position.longitude,
        city: resolved.city,
      );

      _addressNotifier.value = resolved.address;
      _confirmEnabledNotifier.value = true;
    } catch (e) {
      _addressNotifier.value = 'Failed to resolve location address';
      _confirmEnabledNotifier.value = false;
    } finally {
      _loadingNotifier.value = false;
    }
  }

  Future<({String name, String address, String? city})> _reverseGeocode(
    double lat,
    double lng,
  ) async {
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

              String? city;
              final components = first['address_components'] as List?;
              if (components != null) {
                for (final comp in components) {
                  final types = comp['types'] as List?;
                  if (types != null &&
                      (types.contains('locality') ||
                          types.contains('administrative_area_level_2'))) {
                    city = comp['long_name']?.toString();
                    break;
                  }
                }
              }

              String name = first['name']?.toString() ?? '';
              if (name.isEmpty) {
                if (components != null && components.isNotEmpty) {
                  name = components.first['long_name']?.toString() ?? '';
                }
              }
              if (name.isEmpty) name = formattedAddress;

              return (
                name: name,
                address: formattedAddress,
                city: city,
              );
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
          final city = first.locality ??
              first.subAdministrativeArea ??
              first.administrativeArea;
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

          final fullAddress = parts.join(', ');
          final shortName = first.name ??
              first.street ??
              first.locality ??
              'Selected Location';

          return (
            name: shortName,
            address: fullAddress,
            city: city,
          );
        }
      } catch (e) {
      }
    }

    // 3. Fallback
    final fallbackAddr = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    return (
      name: fallbackAddr,
      address: fallbackAddr,
      city: null,
    );
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      if (query.trim().isEmpty) {
        setState(() {
          _predictions = [];
          _searching = false;
        });
        return;
      }
      setState(() {
        _searching = true;
      });
      try {
        final results = await _placesService.autocomplete(query);
        if (mounted) {
          setState(() {
            _predictions = results;
            _searching = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _searching = false;
          });
        }
      }
    });
  }

  Future<void> _selectPrediction(PlacePrediction pred) async {
    _searchFocusNode.unfocus();
    _searchController.text = pred.description;
    setState(() {
      _predictions = [];
    });

    _loadingNotifier.value = true;
    _confirmEnabledNotifier.value = false;

    try {
      final locDetail = await _placesService.placeDetails(
        pred.placeId,
        selectedName: pred.mainText,
      );
      if (locDetail != null && mounted) {
        final target = LatLng(locDetail.latitude, locDetail.longitude);
        _cameraPosition = target;
        _resolvedLocation = locDetail;

        if (_useGoogleMaps && _googleMapController != null) {
          _googleMapController?.animateCamera(CameraUpdate.newLatLng(target));
        } else {
          _osmMapController.move(
            ll.LatLng(target.latitude, target.longitude),
            15,
          );
        }
        _addressNotifier.value = locDetail.formattedAddress ?? '';
        _confirmEnabledNotifier.value = true;
      }
    } catch (e) {
    } finally {
      _loadingNotifier.value = false;
    }
  }

  Future<void> _performSearchKeyboardFallback(String query) async {
    if (query.trim().isEmpty) return;
    _searchFocusNode.unfocus();
    setState(() {
      _predictions = [];
    });

    _loadingNotifier.value = true;
    _confirmEnabledNotifier.value = false;

    try {
      final locations = await locationFromAddress(query);
      if (locations.isNotEmpty && mounted) {
        final first = locations.first;
        final target = LatLng(first.latitude, first.longitude);
        _cameraPosition = target;

        if (_useGoogleMaps && _googleMapController != null) {
          _googleMapController?.animateCamera(CameraUpdate.newLatLng(target));
        } else {
          _osmMapController.move(
            ll.LatLng(target.latitude, target.longitude),
            15,
          );
        }
        _geocodePosition(target);
      }
    } catch (e) {
      _addressNotifier.value = 'Could not find address: $query';
    } finally {
      _loadingNotifier.value = false;
    }
  }

  void _handleConfirm() {
    if (_resolvedLocation != null) {
      Navigator.of(context).pop(_resolvedLocation);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.label,
          style: AppTextStyles.titleMedium.copyWith(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'My location',
            onPressed: _loadCurrentLocation,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _useGoogleMaps ? _buildGoogleMap() : _buildOsmMap(),
          ),
          // Floating Search Bar & Auto-complete Suggestions Overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSearchField(),
                if (_searching || _predictions.isNotEmpty)
                  _buildSuggestionsList(),
              ],
            ),
          ),
          // Central Marker Pin (the map moves beneath it)
          const Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(
                  Icons.location_on,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildGoogleMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _cameraPosition,
        zoom: 15,
      ),
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      onMapCreated: (c) {
        _googleMapController = c;
        _mapCreated = true;
      },
      onCameraMove: (position) {
        _cameraPosition = position.target;
      },
      onCameraIdle: () {
        _geocodePosition(_cameraPosition);
      },
    );
  }

  Widget _buildOsmMap() {
    return fm.FlutterMap(
      mapController: _osmMapController,
      options: fm.MapOptions(
        initialCenter: ll.LatLng(
          _cameraPosition.latitude,
          _cameraPosition.longitude,
        ),
        initialZoom: 15,
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.all,
        ),
        onPositionChanged: (pos, hasGesture) {
          if (hasGesture) {
            _onOsmPositionChanged(pos.center);
          }
        },
      ),
      children: [
        appMapTileLayer(),
      ],
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Material(
        elevation: 8,
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pin Location',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _addressNotifier,
                      builder: (context, address, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: _loadingNotifier,
                          builder: (context, loading, _) {
                            if (loading) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: LinearProgressIndicator(minHeight: 2),
                              );
                            }
                            return Text(
                              address,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<bool>(
                valueListenable: _confirmEnabledNotifier,
                builder: (context, enabled, _) {
                  return AppButton(
                    text: 'Confirm Location',
                    type: AppButtonType.primary,
                    size: AppButtonSize.medium,
                    onPressed: enabled ? _handleConfirm : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        textInputAction: TextInputAction.search,
        onChanged: _onSearchChanged,
        onSubmitted: _performSearchKeyboardFallback,
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search location...',
          hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _searching
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _predictions.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final pred = _predictions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, color: AppColors.textSecondary, size: 20),
                    title: Text(
                      pred.mainText,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      pred.description,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => _selectPrediction(pred),
                  );
                },
              ),
      ),
    );
  }
}
