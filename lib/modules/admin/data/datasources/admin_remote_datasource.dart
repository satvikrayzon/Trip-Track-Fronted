import 'package:dio/dio.dart';

import '../../../../core/api/api_endpoints.dart';
import '../../../../core/network/api_call.dart';
import '../../../../core/network/models/api_result.dart';

class VehicleFuelRates {
  const VehicleFuelRates({
    required this.petrolPerKm,
    this.dieselPerKm = 0,
    this.cngPerKm = 0,
    this.electricPerKm = 0,
  });

  final double petrolPerKm;
  final double dieselPerKm;
  final double cngPerKm;
  final double electricPerKm;

  factory VehicleFuelRates.fromMap(Map<String, dynamic> map) {
    return VehicleFuelRates(
      petrolPerKm: _toDouble(map['petrolPerKm']),
      dieselPerKm: _toDouble(map['dieselPerKm']),
      cngPerKm: _toDouble(map['cngPerKm']),
      electricPerKm: _toDouble(map['electricPerKm']),
    );
  }

  Map<String, dynamic> toMap() => {
        'petrolPerKm': petrolPerKm,
        'dieselPerKm': dieselPerKm,
        'cngPerKm': cngPerKm,
        'electricPerKm': electricPerKm,
      };
}

class BikeFuelRates {
  const BikeFuelRates({
    required this.petrolPerKm,
    required this.electricPerKm,
  });

  final double petrolPerKm;
  final double electricPerKm;

  factory BikeFuelRates.fromMap(Map<String, dynamic> map) {
    return BikeFuelRates(
      petrolPerKm: _toDouble(map['petrolPerKm']),
      electricPerKm: _toDouble(map['electricPerKm']),
    );
  }

  Map<String, dynamic> toMap() => {
        'petrolPerKm': petrolPerKm,
        'electricPerKm': electricPerKm,
      };
}

class FuelRatesModel {
  const FuelRatesModel({
    required this.car,
    required this.bike,
  });

  final VehicleFuelRates car;
  final BikeFuelRates bike;

  factory FuelRatesModel.fromMap(Map<String, dynamic> map) {
    final carMap = map['car'] is Map
        ? Map<String, dynamic>.from(map['car'] as Map)
        : map;
    final bikeMap = map['bike'] is Map
        ? Map<String, dynamic>.from(map['bike'] as Map)
        : const <String, dynamic>{};

    return FuelRatesModel(
      car: VehicleFuelRates.fromMap(carMap),
      bike: BikeFuelRates.fromMap(bikeMap),
    );
  }

  Map<String, dynamic> toMap() => {
        'car': {
          'petrolPerKm': car.petrolPerKm,
          'dieselPerKm': car.dieselPerKm,
          'cngPerKm': car.cngPerKm,
          'electricPerKm': car.electricPerKm,
        },
        'bike': bike.toMap(),
      };

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}

double _toDouble(dynamic value) {
  return FuelRatesModel._toDouble(value);
}

class AdminRemoteDataSource {
  AdminRemoteDataSource(this._dio);

  final Dio _dio;

  Future<ApiResult<FuelRatesModel>> fetchFuelRates() {
    return runApi(
      () async {
        final response = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.adminFuelRates,
        );
        return FuelRatesModel.fromMap(
          Map<String, dynamic>.from(response.data ?? const {}),
        );
      },
      logLabel: 'GET ${ApiEndpoints.adminFuelRates}',
    );
  }

  Future<ApiResult<FuelRatesModel>> updateFuelRates(
    FuelRatesModel rates,
  ) {
    return runApi(
      () async {
        final response = await _dio.patch<Map<String, dynamic>>(
          ApiEndpoints.adminFuelRates,
          data: rates.toMap(),
        );
        return FuelRatesModel.fromMap(
          Map<String, dynamic>.from(response.data ?? rates.toMap()),
        );
      },
      logLabel: 'PATCH ${ApiEndpoints.adminFuelRates}',
    );
  }
}
