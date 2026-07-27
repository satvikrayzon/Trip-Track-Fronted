import 'package:flutter/material.dart';

import '../../../../core/app_messenger.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/hive_database.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/models/picked_location.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/services/active_trip_restore_service.dart';
import '../../../travel/data/datasources/travel_request_remote_datasource.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/utils/travel_request_edit_utils.dart';

class CreateRequestController {
  CreateRequestController({TravelRequestRemoteDataSource? travelApi})
      : _travelApi = travelApi ?? ServiceLocator.I.get(),
        _activeTripRestore = ActiveTripRestoreService(
          travelApi ?? ServiceLocator.I.get<TravelRequestRemoteDataSource>(),
        );

  final TravelRequestRemoteDataSource _travelApi;
  final ActiveTripRestoreService _activeTripRestore;
  final HiveDatabase _localDb = HiveDatabase.instance;

  TravelRequestModel? _editingRequest;
  int? _targetLegIndex;

  bool get isEditMode => _editingRequest != null;

  bool get canEditVehicleSettings =>
      _editingRequest == null ||
      canEditTripVehicleSettings(_editingRequest!);

  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  final ValueNotifier<String> errorMessage = ValueNotifier<String>('');
  final ValueNotifier<String> selectedVehicleType =
      ValueNotifier<String>(AppConstants.vehicleTypeCar);
  final ValueNotifier<String?> selectedFuelType =
      ValueNotifier<String?>(AppConstants.fuelPetrol);
  final ValueNotifier<PickedLocation?> fromLocation =
      ValueNotifier<PickedLocation?>(null);
  final ValueNotifier<PickedLocation?> toLocation =
      ValueNotifier<PickedLocation?>(null);
  final ValueNotifier<bool> showLocationErrors = ValueNotifier<bool>(false);
  final ValueNotifier<bool> attemptedSubmit = ValueNotifier<bool>(false);

  bool get requiresFuelType =>
      AppConstants.vehicleRequiresFuelType(selectedVehicleType.value);

  void dispose() {
    isLoading.dispose();
    errorMessage.dispose();
    selectedVehicleType.dispose();
    selectedFuelType.dispose();
    fromLocation.dispose();
    toLocation.dispose();
    showLocationErrors.dispose();
    attemptedSubmit.dispose();
  }

  void loadForEdit(TravelRequestModel request, {int? targetLegIndex}) {
    _editingRequest = request.ensureTripLegs();
    _targetLegIndex = targetLegIndex;
    fromLocation.value = pickedFromForEdit(_editingRequest!, legIndex: targetLegIndex);
    toLocation.value = pickedToForEdit(_editingRequest!, legIndex: targetLegIndex);
    selectedVehicleType.value = _editingRequest!.vehicleType.isNotEmpty
        ? _editingRequest!.vehicleType
        : AppConstants.vehicleTypeCar;
    selectedFuelType.value = _editingRequest!.fuelType;
    _syncFuelTypeForVehicle(selectedVehicleType.value);
  }

  void _syncFuelTypeForVehicle(String vehicleType) {
    final options = AppConstants.fuelOptionsForVehicle(vehicleType);
    if (options.isEmpty) {
      selectedFuelType.value = null;
      return;
    }
    final current = selectedFuelType.value;
    if (current == null || !options.contains(current)) {
      selectedFuelType.value = options.first;
    }
  }

  /// Returns a running trip if creating a new request should be blocked.
  Future<TravelRequestModel?> findBlockingActiveTrip() async {
    final active = await _activeTripRestore.resolveActiveTrip();
    if (blocksNewTravelRequest(active)) return active;
    return null;
  }

  void selectVehicleType(String type) {
    if (!canEditVehicleSettings) return;
    selectedVehicleType.value = type;
    _syncFuelTypeForVehicle(type);
  }

  void selectFuelType(String fuel) {
    if (!canEditVehicleSettings) return;
    selectedFuelType.value = fuel;
  }

  String? validateFuelType() {
    if (!canEditVehicleSettings) return null;
    if (!requiresFuelType) return null;
    if (selectedFuelType.value == null || selectedFuelType.value!.isEmpty) {
      return 'Select fuel / energy type';
    }
    return null;
  }

  void selectFromLocation(PickedLocation? location) {
    fromLocation.value = location;
  }

  void selectToLocation(PickedLocation? location) {
    toLocation.value = location;
  }

  Future<void> submitRequest({
    required String clientName,
    String? purpose,
  }) async {
    if (isEditMode) {
      await updateRequest(clientName: clientName, purpose: purpose);
    } else {
      await createRequest(clientName: clientName, purpose: purpose);
    }
  }

  Future<void> createRequest({
    required String clientName,
    String? purpose,
  }) async {
    showLocationErrors.value = true;
    attemptedSubmit.value = true;

    if (fromLocation.value == null || toLocation.value == null) {
      return;
    }

    try {
      isLoading.value = true;
      errorMessage.value = '';

      final blocking = await findBlockingActiveTrip();
      if (blocking != null) {
        errorMessage.value = newTravelRequestBlockedMessage(blocking);
        showAppSnackBar(
          title: 'Trip In Progress',
          message: newTravelRequestBlockedMessage(blocking),
          backgroundColor: const Color(0xFFF59E0B),
        );
        return;
      }

      final fuelError = validateFuelType();
      if (fuelError != null) {
        errorMessage.value = fuelError;
        return;
      }

      final result = await _travelApi.createTravelRequest(
        fromLocation: fromLocation.value!.address,
        toLocation: toLocation.value!.address,
        vehicleType: selectedVehicleType.value,
        clientName: clientName,
        fuelType: selectedFuelType.value,
        purpose: purpose,
        originLatitude: fromLocation.value!.latitude,
        originLongitude: fromLocation.value!.longitude,
        destinationLatitude: toLocation.value!.latitude,
        destinationLongitude: toLocation.value!.longitude,
      );

      switch (result) {
        case ApiSuccess(:final data):
          final from = fromLocation.value!;
          final to = toLocation.value!;
          final merged = TravelRequestModel.fromMap({
            ...Map<String, dynamic>.from(data),
            'clientName': clientName.trim(),
            'fromLocation': data['fromLocation'] ?? from.address,
            'toLocation': data['toLocation'] ?? to.address,
          })
              .ensureTripLegs()
              .copyWith(
                startCoordinates: from.toCoordinatesMap(),
                endCoordinates: to.toCoordinatesMap(),
                startAddress: from.name,
                endAddress: to.name,
              );
          await _localDb.saveTravelRequest(merged.toMap());
          await _activeTripRestore.pinActiveTrip(merged);

          showAppSnackBar(
            title: 'Success',
            message: 'Travel request created successfully',
            backgroundColor: const Color(0xFF10B981),
          );

          AppNavigation.off(
            AppRoutes.userRequestDetails,
            arguments: merged,
          );
        case ApiFailure(:final failure):
          errorMessage.value = failure.message;
          showAppSnackBar(
            title: 'Error',
            message: 'Failed to create request: ${failure.message}',
            backgroundColor: const Color(0xFFEF4444),
          );
      }
    } catch (e) {
      errorMessage.value = 'Failed to create request: $e';
      showAppSnackBar(
        title: 'Error',
        message: 'Failed to create request. Please try again.',
        backgroundColor: const Color(0xFFEF4444),
      );
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> updateRequest({
    required String clientName,
    String? purpose,
  }) async {
    final original = _editingRequest;
    if (original == null) return;

    showLocationErrors.value = true;
    attemptedSubmit.value = true;

    if (fromLocation.value == null || toLocation.value == null) {
      return;
    }

    if (!canEditTravelRequest(original)) {
      errorMessage.value = editTravelRequestBlockedMessage(original);
      return;
    }

    try {
      isLoading.value = true;
      errorMessage.value = '';

      final fuelError = validateFuelType();
      if (fuelError != null) {
        errorMessage.value = fuelError;
        return;
      }

      final from = fromLocation.value!;
      final to = toLocation.value!;
      final trimmedClient = clientName.trim();
      final trimmedPurpose = purpose?.trim() ?? '';

      final legIndex = _targetLegIndex ?? editableLegIndex(original);
      final updatedLegs = original.tripLegs.map((leg) => leg.toMap()).toList();
      if (updatedLegs.isNotEmpty && legIndex < updatedLegs.length) {
        updatedLegs[legIndex] = {
          ...updatedLegs[legIndex],
          'fromLocation': from.address,
          'toLocation': to.address,
          'clientName': trimmedClient,
          'purpose': trimmedPurpose,
        };
      }

      final patch = <String, dynamic>{
        'fromLocation': from.address,
        'toLocation': to.address,
        'clientName': trimmedClient,
        'purpose': trimmedPurpose,
        if (updatedLegs.isNotEmpty) 'tripLegs': updatedLegs,
      };

      if (canEditTripVehicleSettings(original)) {
        patch['vehicleType'] = selectedVehicleType.value;
        patch['fuelType'] = selectedFuelType.value;
      }

      patch['originLat'] = from.latitude;
      patch['originLng'] = from.longitude;
      patch['destinationLat'] = to.latitude;
      patch['destinationLng'] = to.longitude;

      final result = await _travelApi.patchTravelRequest(
        original.restResourceId,
        patch,
      );

      switch (result) {
        case ApiSuccess(:final data):
          final merged = TravelRequestModel.fromMap(data)
              .ensureTripLegs()
              .mergePreservingLocalProgress(original)
              .copyWith(
                startCoordinates: from.toCoordinatesMap(),
                endCoordinates: to.toCoordinatesMap(),
                startAddress: from.name,
                endAddress: to.name,
                clientName: trimmedClient,
                purpose: trimmedPurpose,
                vehicleType: canEditTripVehicleSettings(original)
                    ? selectedVehicleType.value
                    : original.vehicleType,
                fuelType: canEditTripVehicleSettings(original)
                    ? selectedFuelType.value
                    : original.fuelType,
              );
          await _localDb.saveTravelRequest(merged.toMap());
          await _activeTripRestore.pinActiveTrip(merged);

          showAppSnackBar(
            title: 'Updated',
            message: 'Travel request updated successfully',
            backgroundColor: const Color(0xFF10B981),
          );

          AppNavigation.back(result: merged);
        case ApiFailure(:final failure):
          errorMessage.value = failure.message;
          showAppSnackBar(
            title: 'Error',
            message: 'Failed to update request: ${failure.message}',
            backgroundColor: const Color(0xFFEF4444),
          );
      }
    } catch (e) {
      errorMessage.value = 'Failed to update request: $e';
      showAppSnackBar(
        title: 'Error',
        message: 'Failed to update request. Please try again.',
        backgroundColor: const Color(0xFFEF4444),
      );
    } finally {
      isLoading.value = false;
    }
  }

  void clearError() {
    errorMessage.value = '';
  }
}
