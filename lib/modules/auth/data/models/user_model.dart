import '../../domain/entities/user_entity.dart';

/// User model for data layer
class UserModel extends UserEntity {
  final String? id;
  final String status; // 'active' or 'banned'

  const UserModel({
    this.id,
    required super.uid,
    required super.email,
    required super.name,
    required super.employeeCode,
    required super.role,
    super.mobile,
    super.sitingLocation,
    super.reportingManagerId,
    super.reportingManagerName,
    this.status = 'active',
  });

  /// MongoDB id for API payloads (e.g. reportingManagerId); falls back to uid.
  String get apiId =>
      (id != null && id!.isNotEmpty) ? id! : uid;

  static String _str(Map<String, dynamic> data, String key) =>
      data[key]?.toString() ?? '';

  static String? _optionalStr(Map<String, dynamic> data, String key) {
    final v = data[key]?.toString();
    return v == null || v.isEmpty ? null : v;
  }

  static String _normalizeRole(String? raw) {
    if (raw == null || raw.isEmpty) return 'user';
    switch (raw.toLowerCase()) {
      case 'admin':
        return 'admin';
      case 'manager':
      case 'hod':
      case 'reporting_manager':
        return 'manager';
      case 'user':
      case 'employee':
        return 'user';
      default:
        return raw.toLowerCase();
    }
  }

  /// Serialize for local Hive storage and API payloads.
  Map<String, dynamic> toMap() {
    return {
      if (id != null && id!.isNotEmpty) 'id': id,
      'uid': uid,
      'email': email,
      'name': name,
      'employeeCode': employeeCode,
      'role': role,
      'mobile': mobile,
      'sitingLocation': sitingLocation,
      if (reportingManagerId != null) 'reportingManagerId': reportingManagerId,
      if (reportingManagerName != null)
        'reportingManagerName': reportingManagerName,
      'status': status,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Parse user from NestJS JSON (`/auth/me`, `/users`, login).
  factory UserModel.fromJson(Map<String, dynamic> data) =>
      UserModel.fromApi(data);

  /// Backend may use `id` instead of `uid`.
  factory UserModel.fromApi(Map<String, dynamic> data) {
    final manager = data['reportingManager'];
    String? managerId;
    String? managerName;
    if (manager is Map) {
      managerId = manager['id']?.toString() ?? manager['_id']?.toString();
      managerName = manager['fullName']?.toString() ??
          manager['name']?.toString();
    }

    final mongoId = data['id']?.toString() ?? data['_id']?.toString();

    return UserModel(
      id: mongoId,
      uid: data['uid']?.toString() ?? mongoId ?? '',
      email: data['email']?.toString() ?? '',
      name: data['name']?.toString() ??
          data['fullName']?.toString() ??
          '',
      employeeCode: data['employeeCode']?.toString() ?? '',
      role: _normalizeRole(data['role']?.toString()),
      mobile: _str(data, 'mobile').isNotEmpty
          ? _str(data, 'mobile')
          : _str(data, 'mobileNumber'),
      sitingLocation: _str(data, 'sitingLocation').isNotEmpty
          ? _str(data, 'sitingLocation')
          : _str(data, 'sittingLocation'),
      reportingManagerId:
          _optionalStr(data, 'reportingManagerId') ?? managerId,
      reportingManagerName:
          _optionalStr(data, 'reportingManagerName') ?? managerName,
      status: _normalizeStatus(data['status']?.toString()),
    );
  }

  static String _normalizeStatus(String? raw) {
    if (raw == null || raw.isEmpty) return 'active';
    final s = raw.toLowerCase();
    if (s == 'banned' || s == 'inactive') return 'banned';
    return 'active';
  }

  /// Create UserModel from local database
  factory UserModel.fromLocalDb(Map<String, dynamic> data) {
    final mongoId = data['id']?.toString();
    return UserModel(
      id: mongoId,
      uid: data['uid']?.toString() ?? mongoId ?? '',
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      employeeCode: data['employeeCode'] ?? '',
      role: data['role'] ?? 'user',
      mobile: data['mobile']?.toString() ?? '',
      sitingLocation: data['sitingLocation']?.toString() ?? '',
      reportingManagerId: data['reportingManagerId']?.toString(),
      reportingManagerName: data['reportingManagerName']?.toString(),
      status: data['status'] ?? 'active',
    );
  }

  /// Convert UserModel to local database format
  Map<String, dynamic> toLocalDb() {
    return {
      if (id != null && id!.isNotEmpty) 'id': id,
      'uid': uid,
      'email': email,
      'name': name,
      'employeeCode': employeeCode,
      'role': role,
      'mobile': mobile,
      'sitingLocation': sitingLocation,
      'reportingManagerId': reportingManagerId,
      'reportingManagerName': reportingManagerName,
      'status': status,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  /// Create a copy of UserModel with updated fields
  UserModel copyWith({
    String? id,
    String? uid,
    String? email,
    String? name,
    String? employeeCode,
    String? role,
    String? mobile,
    String? sitingLocation,
    String? reportingManagerId,
    String? reportingManagerName,
    String? status,
  }) {
    return UserModel(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      email: email ?? this.email,
      name: name ?? this.name,
      employeeCode: employeeCode ?? this.employeeCode,
      role: role ?? this.role,
      mobile: mobile ?? this.mobile,
      sitingLocation: sitingLocation ?? this.sitingLocation,
      reportingManagerId: reportingManagerId ?? this.reportingManagerId,
      reportingManagerName:
          reportingManagerName ?? this.reportingManagerName,
      status: status ?? this.status,
    );
  }

  @override
  String toString() {
    return 'UserModel(uid: $uid, email: $email, name: $name, employeeCode: $employeeCode, role: $role, mobile: $mobile)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel &&
        other.id == id &&
        other.uid == uid &&
        other.email == email &&
        other.name == name &&
        other.employeeCode == employeeCode &&
        other.role == role &&
        other.mobile == mobile &&
        other.sitingLocation == sitingLocation &&
        other.reportingManagerId == reportingManagerId &&
        other.reportingManagerName == reportingManagerName &&
        other.status == status;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        uid.hashCode ^
        email.hashCode ^
        name.hashCode ^
        employeeCode.hashCode ^
        role.hashCode ^
        mobile.hashCode ^
        sitingLocation.hashCode ^
        reportingManagerId.hashCode ^
        reportingManagerName.hashCode ^
        status.hashCode;
  }
}
