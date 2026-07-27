import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/network/models/api_result.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_input_field.dart';
import '../../../../core/widgets/custom_appbar.dart';
import '../../../../core/widgets/header_widget.dart';
import '../../data/datasources/admin_remote_datasource.dart';

class AdminFuelRatesScreen extends StatefulWidget {
  const AdminFuelRatesScreen({super.key});

  @override
  State<AdminFuelRatesScreen> createState() => _AdminFuelRatesScreenState();
}

class _AdminFuelRatesScreenState extends State<AdminFuelRatesScreen> {
  final _formKey = GlobalKey<FormState>();
  final _carPetrolController = TextEditingController();
  final _carDieselController = TextEditingController();
  final _carCngController = TextEditingController();
  final _carElectricController = TextEditingController();
  final _bikePetrolController = TextEditingController();
  final _bikeElectricController = TextEditingController();

  late final AdminRemoteDataSource _adminApi;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _adminApi = ServiceLocator.I.get<AdminRemoteDataSource>();
    _loadRates();
  }

  @override
  void dispose() {
    _carPetrolController.dispose();
    _carDieselController.dispose();
    _carCngController.dispose();
    _carElectricController.dispose();
    _bikePetrolController.dispose();
    _bikeElectricController.dispose();
    super.dispose();
  }

  void _applyRates(FuelRatesModel data) {
    _carPetrolController.text = _formatRate(data.car.petrolPerKm);
    _carDieselController.text = _formatRate(data.car.dieselPerKm);
    _carCngController.text = _formatRate(data.car.cngPerKm);
    _carElectricController.text = _formatRate(data.car.electricPerKm);
    _bikePetrolController.text = _formatRate(data.bike.petrolPerKm);
    _bikeElectricController.text = _formatRate(data.bike.electricPerKm);
  }

  Future<void> _loadRates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await _adminApi.fetchFuelRates();
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        _applyRates(data);
        setState(() => _isLoading = false);
      case ApiFailure(:final failure):
        setState(() {
          _isLoading = false;
          _error = failure.message;
        });
    }
  }

  Future<void> _saveRates() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final result = await _adminApi.updateFuelRates(
      FuelRatesModel(
        car: VehicleFuelRates(
          petrolPerKm: double.parse(_carPetrolController.text.trim()),
          dieselPerKm: double.parse(_carDieselController.text.trim()),
          cngPerKm: double.parse(_carCngController.text.trim()),
          electricPerKm: double.parse(_carElectricController.text.trim()),
        ),
        bike: BikeFuelRates(
          petrolPerKm: double.parse(_bikePetrolController.text.trim()),
          electricPerKm: double.parse(_bikeElectricController.text.trim()),
        ),
      ),
    );
    if (!mounted) return;

    switch (result) {
      case ApiSuccess(:final data):
        _applyRates(data);
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fuel rates saved'),
            backgroundColor: AppColors.success,
          ),
        );
      case ApiFailure(:final failure):
        setState(() {
          _isSaving = false;
          _error = failure.message;
        });
    }
  }

  String _formatRate(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  String? _validateRate(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Enter a rate';
    }
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid number';
    if (parsed < 0) return 'Rate cannot be negative';
    return null;
  }

  Widget _rateField({
    required TextEditingController controller,
    required String label,
    IconData icon = Icons.local_gas_station_outlined,
  }) {
    return AppInputField(
      controller: controller,
      label: label,
      type: AppInputType.number,
      validator: _validateRate,
      prefixIcon: icon,
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return HeaderWidget(
      headerChild: CustomAppBar(
        title: 'Fuel Rates',
        isCenterTitle: true,
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.defaultPadding),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Travel allowance per km',
                      style: AppTextStyles.titleMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Set reimbursement rates by vehicle and fuel/energy type. '
                      'Allowance = distance traveled × rate.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle(
                      'Car',
                      'Petrol, Diesel, CNG, and Electric',
                    ),
                    const SizedBox(height: 12),
                    _rateField(
                      controller: _carPetrolController,
                      label: 'Petrol (₹ per km)',
                    ),
                    const SizedBox(height: 12),
                    _rateField(
                      controller: _carDieselController,
                      label: 'Diesel (₹ per km)',
                    ),
                    const SizedBox(height: 12),
                    _rateField(
                      controller: _carCngController,
                      label: 'CNG (₹ per km)',
                    ),
                    const SizedBox(height: 12),
                    _rateField(
                      controller: _carElectricController,
                      label: 'Electric (₹ per km)',
                      icon: Icons.electric_bolt_outlined,
                    ),
                    const SizedBox(height: 28),
                    _sectionTitle(
                      'Two Wheeler (Bike)',
                      'Petrol and Electric only',
                    ),
                    const SizedBox(height: 12),
                    _rateField(
                      controller: _bikePetrolController,
                      label: 'Petrol (₹ per km)',
                    ),
                    const SizedBox(height: 12),
                    _rateField(
                      controller: _bikeElectricController,
                      label: 'Electric (₹ per km)',
                      icon: Icons.electric_bolt_outlined,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    AppButton(
                      text: 'Save Rates',
                      type: AppButtonType.primary,
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _saveRates,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
