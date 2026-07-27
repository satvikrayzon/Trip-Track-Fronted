import 'package:flutter/material.dart';

import '../../../../core/app_messenger.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/routes/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_input_field.dart';
import '../../../../core/widgets/google_place_search_field.dart';
import '../../../../core/widgets/modern_app_bar.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../../../travel/utils/travel_request_edit_utils.dart';
import '../controllers/create_request_controller.dart';

/// User Create / Edit Request Screen
class UserCreateRequestScreen extends StatefulWidget {
  const UserCreateRequestScreen({super.key, this.initialArgs});

  final dynamic initialArgs;

  @override
  State<UserCreateRequestScreen> createState() =>
      _UserCreateRequestScreenState();
}

class _UserCreateRequestScreenState extends State<UserCreateRequestScreen> {
  late final CreateRequestController _controller;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _clientNameController;
  late final TextEditingController _purposeController;
  bool _isEditMode = false;
  bool _checkedCreateGuard = false;

  @override
  void initState() {
    super.initState();
    _controller = CreateRequestController();
    _clientNameController = TextEditingController();
    _purposeController = TextEditingController();
    _bootstrapFromArgs(widget.initialArgs ?? AppNavigation.arguments);
  }

  void _bootstrapFromArgs(dynamic args) {
    TravelRequestModel? request;
    var isEdit = false;
    int? targetLegIndex;

    if (args is TravelRequestModel) {
      request = args;
      isEdit = true;
    } else if (args is Map) {
      isEdit = args['edit'] == true;
      final raw = args['request'];
      if (raw is TravelRequestModel) {
        request = raw;
      }
      targetLegIndex = args['legIndex'] as int?;
    }

    if (isEdit && request != null) {
      final canEdit = targetLegIndex != null && targetLegIndex < request.tripLegs.length
          ? canEditTripLeg(request, request.tripLegs[targetLegIndex])
          : canEditTravelRequest(request);

      if (!canEdit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showAppSnackBar(
            title: 'Cannot Edit',
            message: editTravelRequestBlockedMessage(request!),
            backgroundColor: AppColors.warning,
          );
          Navigator.of(context).pop();
        });
        return;
      }
      _isEditMode = true;
      _controller.loadForEdit(request, targetLegIndex: targetLegIndex);
      _clientNameController.text = clientNameForEdit(request, legIndex: targetLegIndex);
      _purposeController.text = purposeForEdit(request, legIndex: targetLegIndex);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _guardCreateIfNeeded());
  }

  Future<void> _guardCreateIfNeeded() async {
    if (_checkedCreateGuard || _isEditMode || !mounted) return;
    _checkedCreateGuard = true;

    final blocking = await _controller.findBlockingActiveTrip();
    if (!mounted || blocking == null) return;

    showAppSnackBar(
      title: 'Trip In Progress',
      message: newTravelRequestBlockedMessage(blocking),
      backgroundColor: AppColors.warning,
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    _clientNameController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      _controller.showLocationErrors.value = true;
      _controller.attemptedSubmit.value = true;
      return;
    }

    await _controller.submitRequest(
      clientName: _clientNameController.text.trim(),
      purpose: _purposeController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final canEditVehicle = controller.canEditVehicleSettings;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ModernAppBar(
        title: _isEditMode ? 'Edit Travel Request' : 'Create Travel Request',
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppConstants.defaultPadding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppConstants.defaultPadding),
              AppCard(
                type: AppCardType.outlinedCard,
                backgroundColor: AppColors.info.withOpacity(0.05),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppColors.info,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isEditMode
                            ? 'Update trip details for the current leg before departure.'
                            : 'Search and select from/to locations from the dropdown. '
                                'Each travel step will be punched with time and GPS.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.largePadding),
              AppCard(
                type: AppCardType.elevatedCard,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: controller.showLocationErrors,
                      builder: (context, showErrors, _) {
                        return ValueListenableBuilder(
                          valueListenable: controller.fromLocation,
                          builder: (context, fromLoc, __) {
                            return GooglePlaceSearchField(
                              label: 'From Location',
                              hint: 'Search starting location',
                              icon: Icons.my_location,
                              initial: fromLoc,
                              errorText: showErrors && fromLoc == null
                                  ? 'Please select a starting location'
                                  : null,
                              onLocationSelected: controller.selectFromLocation,
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: AppConstants.defaultPadding),
                    ValueListenableBuilder<bool>(
                      valueListenable: controller.showLocationErrors,
                      builder: (context, showErrors, _) {
                        return ValueListenableBuilder(
                          valueListenable: controller.toLocation,
                          builder: (context, toLoc, __) {
                            return GooglePlaceSearchField(
                              label: 'To / Destination',
                              hint: 'Search client or visit location',
                              icon: Icons.location_on,
                              initial: toLoc,
                              errorText: showErrors && toLoc == null
                                  ? 'Please select a destination'
                                  : null,
                              onLocationSelected: controller.selectToLocation,
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: AppConstants.defaultPadding),
                    AppInputField(
                      label: 'Client Name',
                      hint: 'Enter client name',
                      controller: _clientNameController,
                      prefixIcon: Icons.business,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter client name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppConstants.defaultPadding),
                    AppInputField(
                      label: 'Purpose',
                      hint: 'Enter visit reason (optional)',
                      controller: _purposeController,
                      prefixIcon: Icons.assignment_outlined,
                      maxLines: 2,
                    ),
                    if (canEditVehicle) ...[
                      const SizedBox(height: AppConstants.largePadding),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Vehicle Type',
                            style: AppTextStyles.inputLabel.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ValueListenableBuilder<String>(
                            valueListenable: controller.selectedVehicleType,
                            builder: (context, vehicle, _) {
                              return Row(
                                children: [
                                  for (final option
                                      in AppConstants.vehicleOptions) ...[
                                    Expanded(
                                      child: _buildVehicleOption(
                                        vehicle == option.$1,
                                        option.$1,
                                        option.$2,
                                        _vehicleIcon(option.$1),
                                        () => controller.selectVehicleType(
                                            option.$1),
                                      ),
                                    ),
                                    if (option.$1 !=
                                        AppConstants.vehicleOptions.last.$1)
                                      const SizedBox(width: 12),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      ValueListenableBuilder<String>(
                        valueListenable: controller.selectedVehicleType,
                        builder: (context, vehicle, _) {
                          final fuelOptions =
                              AppConstants.fuelOptionsForVehicle(vehicle);
                          if (fuelOptions.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: AppConstants.largePadding),
                              Text(
                                'Fuel / Energy Type',
                                style: AppTextStyles.inputLabel.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ValueListenableBuilder<String?>(
                                valueListenable: controller.selectedFuelType,
                                builder: (context, selectedFuel, _) {
                                  return Row(
                                    children: [
                                      for (final fuel in fuelOptions) ...[
                                        Expanded(
                                          child: _buildFuelOption(
                                            selectedFuel == fuel,
                                            fuel,
                                            () =>
                                                controller.selectFuelType(fuel),
                                          ),
                                        ),
                                        if (fuel != fuelOptions.last)
                                          const SizedBox(width: 8),
                                      ],
                                    ],
                                  );
                                },
                              ),
                              AnimatedBuilder(
                                animation: Listenable.merge([
                                  controller.attemptedSubmit,
                                  controller.selectedFuelType,
                                ]),
                                builder: (context, _) {
                                  if (!controller.attemptedSubmit.value) {
                                    return const SizedBox.shrink();
                                  }
                                  final fuelError =
                                      controller.validateFuelType();
                                  if (fuelError == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      fuelError,
                                      style: AppTextStyles.errorText,
                                    ),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.largePadding),
              ValueListenableBuilder<bool>(
                valueListenable: controller.isLoading,
                builder: (context, isLoading, _) => AppButton(
                  text: _isEditMode ? 'Save Changes' : 'Create Request',
                  type: AppButtonType.primary,
                  size: AppButtonSize.large,
                  icon: Icons.check,
                  isLoading: isLoading,
                  onPressed: isLoading ? null : _handleSubmit,
                ),
              ),
              const SizedBox(height: AppConstants.defaultPadding),
              ValueListenableBuilder<String>(
                valueListenable: controller.errorMessage,
                builder: (context, errorMessage, _) {
                  if (errorMessage.isNotEmpty) {
                    return Container(
                      padding:
                          const EdgeInsets.all(AppConstants.defaultPadding),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius:
                            BorderRadius.circular(AppConstants.buttonRadius),
                        border: Border.all(
                            color: AppColors.error.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage,
                              style: AppTextStyles.errorText,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _vehicleIcon(String type) {
    switch (type) {
      case AppConstants.vehicleTypeCar:
        return Icons.directions_car;
      case AppConstants.vehicleTypeScooter:
        return Icons.electric_scooter;
      case AppConstants.vehicleTypeBike:
      default:
        return Icons.motorcycle;
    }
  }

  Widget _buildVehicleOption(
    bool isSelected,
    String type,
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        type: AppCardType.elevatedCard,
        backgroundColor: isSelected ? AppColors.primary : AppColors.surface,
        child: Column(
          children: [
            Icon(
              icon,
              size: 36,
              color: isSelected ? AppColors.white : AppColors.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTextStyles.titleMedium.copyWith(
                color: isSelected ? AppColors.white : AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFuelOption(
    bool isSelected,
    String fuel,
    VoidCallback onTap,
  ) {
    final label = AppConstants.fuelTypeLabel(fuel);
    return GestureDetector(
      onTap: onTap,
      child: AppCard(
        type: AppCardType.elevatedCard,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        backgroundColor: isSelected ? AppColors.primary : AppColors.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _fuelIcon(fuel),
              size: 28,
              color: isSelected ? AppColors.white : AppColors.primary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodySmall.copyWith(
                color: isSelected ? AppColors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fuelIcon(String fuel) {
    switch (fuel) {
      case AppConstants.fuelElectric:
        return Icons.electric_bolt_outlined;
      case AppConstants.fuelCng:
        return Icons.eco_outlined;
      case AppConstants.fuelDiesel:
        return Icons.local_gas_station_outlined;
      case AppConstants.fuelPetrol:
      default:
        return Icons.local_gas_station_outlined;
    }
  }
}
