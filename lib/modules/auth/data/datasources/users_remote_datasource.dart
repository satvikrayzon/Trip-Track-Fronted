import 'package:dio/dio.dart';

import '../../../../core/api/api_endpoints.dart';
import '../../../../core/network/api_call.dart';
import '../../../../core/network/api_response_list.dart';
import '../../../../core/network/models/api_result.dart';
import '../models/user_model.dart';

class UsersRemoteDataSource {
  UsersRemoteDataSource(this._dio);

  final Dio _dio;

  Future<ApiResult<UserModel>> getUserById(String userId) {
    return runApi(() async {
      final res = await _dio.get<dynamic>(ApiEndpoints.user(userId));
      final data = res.data;
      if (data is! Map) {
        throw const FormatException('User response is not a JSON object');
      }
      return UserModel.fromJson(Map<String, dynamic>.from(data));
    }, logLabel: 'Users.getById');
  }

  Future<ApiResult<List<UserModel>>> fetchReportingManagers() {
    return runApi(() async {
      final res = await _dio.get<dynamic>(ApiEndpoints.reportingManagers);
      return _parseUserList(res.data);
    }, logLabel: 'Users.reportingManagers');
  }

  Future<ApiResult<List<UserModel>>> listUsers({
    int limit = 100,
    String? role,
    String? status,
    String? search,
    bool paginated = false,
  }) {
    return runApi(() async {
      final res = await _dio.get<dynamic>(
        ApiEndpoints.users,
        queryParameters: {
          'limit': limit,
          if (role != null) 'role': role,
          if (status != null) 'status': status,
          if (search != null) 'search': search,
          if (paginated) 'paginated': 'true',
        },
      );
      return _parseUserList(res.data);
    }, logLabel: 'Users.list');
  }

  Future<ApiResult<UserModel>> createUser({
    required String email,
    required String password,
    required String name,
    required String employeeCode,
    required String role,
    required String mobile,
    String? sitingLocation,
    String? reportingManagerId,
  }) {
    return runApi(() async {
      final payload = <String, dynamic>{
        'email': email,
        'password': password,
        'name': name,
        'employeeCode': employeeCode,
        'role': role,
        'mobile': mobile,
        if (sitingLocation != null && sitingLocation.isNotEmpty)
          'sitingLocation': sitingLocation,
        if (reportingManagerId != null && reportingManagerId.isNotEmpty)
          'reportingManagerId': reportingManagerId,
      };
      final res = await _dio.post<Map<String, dynamic>>(
        ApiEndpoints.users,
        data: payload,
      );
      final data = res.data;
      if (data == null) {
        throw const FormatException('Empty create user response');
      }
      return UserModel.fromJson(data);
    }, logLabel: 'Users.create');
  }

  Future<ApiResult<void>> updateUser(
    String userId,
    Map<String, dynamic> patch,
  ) {
    return runApi(() async {
      await _dio.patch<void>(ApiEndpoints.user(userId), data: patch);
    });
  }

  Future<ApiResult<void>> deactivateUser(String userId) {
    return runApi(() async {
      await _dio.post<void>(ApiEndpoints.userDeactivate(userId));
    });
  }

  Future<ApiResult<void>> activateUser(String userId) {
    return runApi(() async {
      await _dio.post<void>(ApiEndpoints.userActivate(userId));
    });
  }

  List<UserModel> _parseUserList(dynamic data) {
    if (data is List) {
      return data
          .map((e) => UserModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return ApiResponseList.parse(data).map(UserModel.fromJson).toList();
  }
}
