import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/models/picked_location.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_input_field.dart';
import '../../../../core/widgets/google_place_search_field.dart';
import '../../../../core/widgets/modern_app_bar.dart';
import '../../../travel/data/models/travel_request_model.dart';
import '../controllers/add_next_client_controller.dart';

class AddNextClientScreen extends StatefulWidget {
  const AddNextClientScreen({
    super.key,
    required this.request,
  });

  final TravelRequestModel request;

  @override
  State<AddNextClientScreen> createState() => _AddNextClientScreenState();
}

class _AddNextClientScreenState extends State<AddNextClientScreen> {
  final _formKey = GlobalKey<FormState>();
  late final AddNextClientController _controller;
  late final TextEditingController _clientNameController;
  late final TextEditingController _purposeController;

  @override
  void initState() {
    super.initState();
    _controller = AddNextClientController(
      initialFrom: _initialFromLocation(widget.request),
    );
    _clientNameController = TextEditingController();
    _purposeController = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _clientNameController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  PickedLocation _initialFromLocation(TravelRequestModel request) {
    final lastLeg = request.tripLegs.isNotEmpty
        ? request.tripLegs.last
        : null;
    final address = (lastLeg?.toLocation.trim().isNotEmpty == true
            ? lastLeg!.toLocation
            : request.toLocation)
        .trim();
    final punch = lastLeg?.arrivalPunch ?? lastLeg?.meetingEndPunch;
    if (punch != null) {
      return PickedLocation(
        name: address,
        formattedAddress: address,
        latitude: punch.latitude,
        longitude: punch.longitude,
      );
    }
    return PickedLocation(
      name: address,
      formattedAddress: address,
      latitude: 0,
      longitude: 0,
    );
  }

  void _submit() {
    _controller.showLocationErrors.value = true;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_controller.toLocation.value == null) return;

    Navigator.of(context).pop(
      AddNextClientInput(
        clientName: _clientNameController.text.trim(),
        destination: _controller.toLocation.value!.address,
        purpose: _purposeController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const ModernAppBar(
        title: 'Add Next Client',
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
                backgroundColor: AppColors.info.withValues(alpha: 0.05),
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
                        'Search and select the next client destination from the dropdown. '
                        'From location is set from your previous stop.',
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
                    ValueListenableBuilder(
                      valueListenable: controller.fromLocation,
                      builder: (context, fromLoc, _) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GooglePlaceSearchField(
                              label: 'From Location',
                              hint: 'Previous stop location',
                              icon: Icons.my_location,
                              initial: fromLoc,
                              readOnly: true,
                              onLocationSelected: (_) {},
                            ),
                          ],
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
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                GooglePlaceSearchField(
                                  label: 'To / Destination',
                                  hint: 'Search client or visit location',
                                  icon: Icons.location_on,
                                  initial: toLoc,
                                  errorText: showErrors && toLoc == null
                                      ? 'Please select a destination'
                                      : null,
                                  onLocationSelected:
                                      controller.selectToLocation,
                                ),
                              ],
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
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.largePadding),
              AppButton(
                text: 'Add Client',
                type: AppButtonType.primary,
                size: AppButtonSize.large,
                icon: Icons.check,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
